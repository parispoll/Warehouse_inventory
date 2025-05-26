import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'package:flutter/services.dart';
import 'database_helper.dart';
import 'main.dart'; // for routeObserver
import 'package:flutter/widgets.dart';

class InventoryHomePage extends StatefulWidget {
  @override
  _InventoryHomePageState createState() => _InventoryHomePageState();
}

class _InventoryHomePageState extends State<InventoryHomePage> with RouteAware {
  Database? database;
  Map<String, List<Map<String, dynamic>>> categorizedItems = {};
  Future<List<String>> getCategories() async {
  final results = await database!.rawQuery('SELECT DISTINCT category FROM inventory WHERE category IS NOT NULL');
  return results.map((e) => e['category'] as String).toList();
}

  Future<void> printAllItemsWithPrices(Database database) async {
  final List<Map<String, dynamic>> items =
      await database.query('inventory', columns: ['item', 'price']);

  if (items.isEmpty) {
    print("📭 No inventory items found.");
  } else {
    print("📦 Inventory Items with Prices:");
    for (var item in items) {
      final name = item['item'] ?? 'Unknown';
      final price = item['price'] ?? '—';
      print("🔹 $name: €$price");
    }
  }
}


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
    fetchItems(); // Refresh when returning to this screen
  }

 Future<void> initDatabase() async {
  database = await DatabaseHelper.getDatabase();
  await fetchItems();
  await printAllItemsWithPrices(database!);
}

  Future<void> fetchItems() async {
    final List<Map<String, dynamic>> items =
        await database!.query('inventory', orderBy: 'category');
    setState(() {
      categorizedItems.clear();
      for (var item in items) {
        final category = item['category'] ?? 'Uncategorized';
        categorizedItems.putIfAbsent(category, () => []).add(item);
      }
    });
  }

  Future<void> updateQuantity(int id, int newQuantity) async {
    await database!.update(
      'inventory',
      {'quantity': newQuantity},
      where: 'id = ?',
      whereArgs: [id],
    );
    fetchItems();
  }

  Future<List<Map<String, dynamic>>> fetchLogs(int itemId) async {
    return await database!.query(
      'order_logs',
      where: 'item_id = ?',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inventory List'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: fetchItems,
          )
        ],
      ),
      body: categorizedItems.isEmpty
          ? Center(child: CircularProgressIndicator())
          : ListView(
              children: categorizedItems.entries.map((entry) {
                return ExpansionTile(
                title: GestureDetector(
                onLongPress: () => showCategoryOptions(entry.key),
               child: Text(entry.key, style: TextStyle(fontWeight: FontWeight.bold)),
              ),

                  children: entry.value.map((item) {
                    bool isLowStock = item['quantity'] < (item['low_stock_threshold'] ?? 5);

                    return ListTile(
                      title: Text(item['item']),
                      subtitle: isLowStock ? Text('⚠ Low Stock', style: TextStyle(color: Colors.red)) : null,
                      onLongPress: () => showItemOptions(item),
                      trailing: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                       IconButton(
                      icon: Icon(Icons.remove),
                      onPressed: () => updateQuantity(item['id'], item['quantity'] - 1),
                    ),
                    Text('${item['quantity']}'),
                    IconButton(
                    icon: Icon(Icons.add),
                    onPressed: () => updateQuantity(item['id'], item['quantity'] + 1),
                    ),
                  ],
                  ),
                onTap: () => showLogs(context, item['id'], item['item']),
                );

                  }).toList(),
                );
              }).toList(),
            ),
    );
  }

  void showItemOptions(Map<String, dynamic> item) {
  TextEditingController nameController = TextEditingController(text: item['item']);
  TextEditingController categoryController = TextEditingController(text: item['category']);

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Edit Item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: nameController, decoration: InputDecoration(labelText: 'Item Name')),
          FutureBuilder<List<String>>(
  future: getCategories(),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return CircularProgressIndicator();
    return DropdownButtonFormField<String>(
      value: categoryController.text,
      items: snapshot.data!
          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
          .toList(),
      onChanged: (val) {
        if (val != null) categoryController.text = val;
      },
      decoration: InputDecoration(labelText: 'Category'),
    );
  },
),

        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await database!.update(
              'inventory',
              {
                'item': nameController.text.trim(),
                'category': categoryController.text.trim(),
              },
              where: 'id = ?',
              whereArgs: [item['id']],
            );
            Navigator.pop(context);
            fetchItems();
          },
          child: Text('Save'),
        ),
        TextButton(
          onPressed: () async {
            await database!.delete('inventory', where: 'id = ?', whereArgs: [item['id']]);
            Navigator.pop(context);
            fetchItems();
          },
          child: Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

void showCategoryOptions(String category) {
  TextEditingController controller = TextEditingController(text: category);

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Edit Category'),
      content: TextField(controller: controller),
      actions: [
        TextButton(
          onPressed: () async {
            await database!.update(
              'inventory',
              {'category': controller.text.trim()},
              where: 'category = ?',
              whereArgs: [category],
            );
            Navigator.pop(context);
            fetchItems();
          },
          child: Text('Rename'),
        ),
        TextButton(
          onPressed: () async {
            await database!.delete('inventory', where: 'category = ?', whereArgs: [category]);
            Navigator.pop(context);
            fetchItems();
          },
          child: Text('Delete All', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}



}
