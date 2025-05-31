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
  final nameController = TextEditingController(text: item.name);
  final qtyController = TextEditingController(text: item.quantity.toString());
  final newCategoryController = TextEditingController();
  String? selectedCategory = item.categoryName;

  // Fetch available categories
  final categoriesResult = await database!.rawQuery('SELECT name FROM categories ORDER BY name');
  final categoryList = categoriesResult.map((e) => e['name'] as String).toList();

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Edit "${item.name}"'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: InputDecoration(labelText: 'Name')),
              TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Quantity')),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: InputDecoration(labelText: 'Select Existing Category'),
                items: categoryList.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (val) => selectedCategory = val,
              ),
              SizedBox(height: 8),
              TextField(
                controller: newCategoryController,
                decoration: InputDecoration(labelText: 'Or Create New Category'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              String? finalCategory = selectedCategory;

              if (newCategoryController.text.trim().isNotEmpty) {
                final newCatName = newCategoryController.text.trim();

                // Get parent category ID
                final parentIdResult = await database!.rawQuery(
                  'SELECT id FROM categories WHERE name = ?',
                  [item.parentCategory],
                );

                int? parentId = parentIdResult.isNotEmpty ? parentIdResult.first['id'] as int : null;

                // Insert new category
                final newCategoryId = await database!.insert('categories', {
                  'name': newCatName,
                  'parent_id': parentId,
                });

                finalCategory = newCatName;
              }

              if (finalCategory != null) {
                await database!.rawUpdate(
                  'UPDATE inventory SET name = ?, category_id = (SELECT id FROM categories WHERE name = ?) WHERE id = ?',
                  [nameController.text, finalCategory, item.id],
                );

                await database!.rawUpdate(
                  'UPDATE inventory_stock SET quantity = ? WHERE inventory_id = ?',
                  [int.tryParse(qtyController.text) ?? item.quantity, item.id],
                );
              }

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



  @override
  Widget build(BuildContext context) {
    final filteredItems = items.where((item) =>
      item.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
      (item.categoryName?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false)
    ).toList();

    print("ITEMS DEBUG:");
    for (var item in filteredItems) {
      print("Item: ${item.name}, Parent: ${item.parentCategory}, Category: ${item.categoryName}");
    }

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
              decoration: InputDecoration(
                hintText: 'Search inventory...'
              ),
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
                print("Parent: $parent has ${parentItems.length} items");

                final subcategories = parentItems
                    .map((e) => e.categoryName?.trim() ?? 'Uncategorized')
                    .toSet();
                print("Subcategories under $parent: $subcategories");

                return ExpansionTile(
                  title: Text(parent),
                  children: subcategories.map((sub) {
                    final subItems = parentItems
                        .where((item) => (item.categoryName?.trim() ?? 'Uncategorized') == sub)
                        .toList();

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