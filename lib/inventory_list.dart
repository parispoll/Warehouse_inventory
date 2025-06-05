import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'database_helper.dart';
import 'main.dart'; // for routeObserver
import 'package:flutter/widgets.dart';
import 'models/inventory_item.dart';

class InventoryHomePage extends StatefulWidget {
  @override
  _InventoryHomePageState createState() => _InventoryHomePageState();
}

class _InventoryHomePageState extends State<InventoryHomePage> with RouteAware {
  Database? database;
  List<InventoryItem> items = [];
  List<String> parentCategories = ['Kitchen Items', 'Bar Item', 'Other Items'];
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    initDatabase();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    fetchItems();
  }

  Future<void> initDatabase() async {
    database = await DatabaseHelper.getDatabase();
    await fetchItems();
  }

  Future<void> fetchItems() async {
    final List<Map<String, dynamic>> result = await database!.rawQuery(inventoryItemQuery);
    setState(() {
      items = result.map((e) => InventoryItem.fromMap(e)).toList();
    });
  }

  Future<void> updateQuantity(int id, String location, int newQuantity) async {
    final locResult = await database!.rawQuery('SELECT id FROM locations WHERE name = ?', [location]);
    if (locResult.isNotEmpty) {
      final locationId = locResult.first['id'];
      await database!.update(
        'inventory_stock',
        {'quantity': newQuantity, 'last_updated': DateTime.now().toIso8601String()},
        where: 'inventory_id = ? AND location_id = ?',
        whereArgs: [id, locationId],
      );
      fetchItems();
    }
  }

  Future<List<Map<String, dynamic>>> fetchLogs(int itemId) async {
    return await database!.query(
      'order_logs',
      where: 'inventory_id = ?',
      whereArgs: [itemId],
    );
  }

  void showLogs(BuildContext context, int itemId, String itemName) async {
    List<Map<String, dynamic>> logs = await fetchLogs(itemId);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logs for "$itemName"'),
        content: logs.isEmpty
            ? Text("No logs found.")
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: logs.map((log) {
                  return Text(
                    '${log['timestamp']} - ${log['log_name']}: -${log['quantity_subtracted']}',
                  );
                }).toList(),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEditSubcategoryDialog(String subcategory) async {
    String? selectedParent = parentCategories.first;
    String? newParent = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Change Parent for "$subcategory"'),
          content: DropdownButtonFormField<String>(
            value: selectedParent,
            items: parentCategories.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (val) => selectedParent = val,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, selectedParent), child: Text('Save')),
          ],
        );
      }
    );

    if (newParent != null) {
      await database!.rawUpdate('''
        UPDATE categories SET parent_id = (
          SELECT id FROM categories WHERE name = ?
        ) WHERE name = ?
      ''', [newParent, subcategory]);
      fetchItems();
    }
  }

  void _showEditItemDialog(InventoryItem item) async {
  final thresholdController = TextEditingController(text: item.lowStockThreshold.toString());

  // Fetch all quantities for this item across all locations
  final stockResult = await database!.rawQuery('''
    SELECT l.name AS location, s.quantity
    FROM inventory_stock s
    JOIN locations l ON s.location_id = l.id
    WHERE s.inventory_id = ?
  ''', [item.id]);

  final Map<String, TextEditingController> qtyControllers = {
    for (var row in stockResult)
      row['location'] as String: TextEditingController(text: row['quantity'].toString())
  };

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Item: ${item.name}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Code: ${item.id}"),
              SizedBox(height: 4),
              Text("Category: ${item.categoryName ?? 'Uncategorized'}"),
              SizedBox(height: 16),
              ...qtyControllers.entries.map((entry) => TextField(
                controller: entry.value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Quantity (${entry.key})'),
              )),
              SizedBox(height: 16),
              TextField(
                controller: thresholdController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Low Stock Threshold'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              // Update quantities per location
              for (var entry in qtyControllers.entries) {
                final locName = entry.key;
                final qty = int.tryParse(entry.value.text) ?? 0;
                final locIdResult = await database!.rawQuery(
                  'SELECT id FROM locations WHERE name = ?', [locName]);
                if (locIdResult.isNotEmpty) {
                  final locId = locIdResult.first['id'];
                  await database!.update(
                    'inventory_stock',
                    {
                      'quantity': qty,
                      'last_updated': DateTime.now().toIso8601String(),
                    },
                    where: 'inventory_id = ? AND location_id = ?',
                    whereArgs: [item.id, locId],
                  );
                }
              }

              // Update low stock threshold
              await database!.update(
                'inventory',
                {'low_stock_threshold': int.tryParse(thresholdController.text) ?? 0},
                where: 'id = ?',
                whereArgs: [item.id],
              );

              Navigator.pop(context);
              fetchItems();
            },
            child: Text('Save'),
          ),
        ],
      );
    },
  );
}


  int _naturalCompare(String a, String b) {
    final numberRegex = RegExp(r'(\d+)');

    final aMatch = numberRegex.firstMatch(a);
    final bMatch = numberRegex.firstMatch(b);

    if (aMatch != null && bMatch != null) {
      final prefixA = a.substring(0, aMatch.start);
      final prefixB = b.substring(0, bMatch.start);
      final numA = int.tryParse(aMatch.group(0)!) ?? 0;
      final numB = int.tryParse(bMatch.group(0)!) ?? 0;

      final prefixComparison = prefixA.compareTo(prefixB);
      if (prefixComparison != 0) return prefixComparison;

      return numA.compareTo(numB);
    }

    return a.compareTo(b);
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = items.where((item) =>
      item.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
      (item.categoryName?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false)
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Inventory List'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: fetchItems,
          )
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(48.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(hintText: 'Search inventory...'),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),
          ),
        ),
      ),
      body: filteredItems.isEmpty
          ? Center(child: CircularProgressIndicator())
          : ListView(
              children: parentCategories.map((parent) {
                final parentItems = filteredItems.where((item) => item.parentCategory == parent).toList();

                final subcategories = parentItems
                    .map((e) => e.categoryName?.trim() ?? 'Uncategorized')
                    .toSet()
                    .toList()
                  ..sort((a, b) => _naturalCompare(a, b));

                return ExpansionTile(
                  title: Text(parent),
                  children: subcategories.map((sub) {
                    final subItems = parentItems
                        .where((item) => (item.categoryName?.trim() ?? 'Uncategorized') == sub)
                        .toList()
                      ..sort((a, b) => _naturalCompare(a.name, b.name));

                    return ExpansionTile(
                      title: GestureDetector(
                        onLongPress: () => _showEditSubcategoryDialog(sub),
                        child: Text(sub),
                      ),
                      children: subItems.map((item) {
                        final isLowStock = item.quantity < item.lowStockThreshold;

                        return ListTile(
                          onLongPress: () => _showEditItemDialog(item),
                          title: Text('${item.name} (${item.location})'),
                          subtitle: Text(
                            'Qty: ${item.quantity} | Category: ${item.categoryName ?? "Uncategorized"}',
                            style: isLowStock ? TextStyle(color: Colors.red) : null,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.remove),
                                onPressed: () => updateQuantity(item.id, item.location, item.quantity - 1),
                              ),
                              Text('${item.quantity}'),
                              IconButton(
                                icon: Icon(Icons.add),
                                onPressed: () => updateQuantity(item.id, item.location, item.quantity + 1),
                              ),
                            ],
                          ),
                          onTap: () => showLogs(context, item.id, item.name),
                        );
                      }).toList(),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
    );
  }
}