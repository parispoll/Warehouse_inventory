import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class AddItemsPage extends StatefulWidget {
  @override
  _AddItemsPageState createState() => _AddItemsPageState();
}

class _AddItemsPageState extends State<AddItemsPage> {
  final TextEditingController _textController = TextEditingController();
  Database? database;

  @override
  void initState() {
    super.initState();
    initDatabase();
  }

  Future<void> initDatabase() async {
    database = await DatabaseHelper.getDatabase();
  }

  Future<void> processItems() async {
    final lines = _textController.text.trim().split('\n');
    final alreadyExists = <String>[];
    final addedItems = <String>[];
    final skippedItems = <String>[];

    final int? mainWarehouseId = Sqflite.firstIntValue(await database!.rawQuery("SELECT id FROM locations WHERE name = 'Main Warehouse'"));
    if (mainWarehouseId == null) {
      _showError("Main Warehouse location not found in database.");
      return;
    }

    for (String line in lines) {
      final parts = line.trim().split(' ');
      if (parts.length < 3) {
        skippedItems.add(line);
        continue;
      }

      final quantity = int.tryParse(parts.last);
      if (quantity == null) {
        skippedItems.add(line);
        continue;
      }

      final categoryName = parts.first.toLowerCase();
      final itemName = parts.sublist(1, parts.length - 1).join(' ').toLowerCase();

      // Get or insert category
      int? categoryId = Sqflite.firstIntValue(await database!.rawQuery(
        "SELECT id FROM categories WHERE LOWER(name) = ?",
        [categoryName],
      ));
      if (categoryId == null) {
        categoryId = await database!.insert('categories', {'name': categoryName});
      }

      // Check if item exists
      final existing = await database!.query(
        'inventory',
        where: 'LOWER(name) = ?',
        whereArgs: [itemName],
      );

      if (existing.isNotEmpty) {
        alreadyExists.add(itemName);
        bool? replace = await askToReplace(itemName, quantity);
        if (replace == true) {
          final itemId = existing.first['id'] as int;
          await database!.update(
            'inventory',
            {
              'category_id': categoryId,
              'name': itemName,
            },
            where: 'id = ?',
            whereArgs: [itemId],
          );

          await database!.update(
            'inventory_stock',
            {
              'quantity': quantity,
              'last_updated': DateTime.now().toIso8601String(),
            },
            where: 'inventory_id = ? AND location_id = ?',
            whereArgs: [itemId, mainWarehouseId],
          );
        }
      } else {
        final itemId = await database!.insert('inventory', {
          'name': itemName,
          'category_id': categoryId,
          'low_stock_threshold': 5,
        });

        await database!.insert('inventory_stock', {
          'inventory_id': itemId,
          'location_id': mainWarehouseId,
          'quantity': quantity,
          'last_updated': DateTime.now().toIso8601String(),
        });

        addedItems.add(itemName);
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Import Complete"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (addedItems.isNotEmpty) ...[
                Text("✅ Added:", style: TextStyle(fontWeight: FontWeight.bold)),
                ...addedItems.map((e) => Text("- $e")),
                SizedBox(height: 10),
              ],
              if (alreadyExists.isNotEmpty) ...[
                Text("🔁 Already existed:", style: TextStyle(fontWeight: FontWeight.bold)),
                ...alreadyExists.map((e) => Text("- $e")),
                SizedBox(height: 10),
              ],
              if (skippedItems.isNotEmpty) ...[
                Text("⚠️ Skipped (invalid format):", style: TextStyle(fontWeight: FontWeight.bold)),
                ...skippedItems.map((e) => Text("- $e")),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          )
        ],
      ),
    );
  }

  Future<bool?> askToReplace(String item, int qty) async {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Item already exists"),
        content: Text("Item \"$item\" already exists.\nReplace quantity with $qty?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Yes, replace"),
          )
        ],
      ),
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Add New Items")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Enter items in the format: category item_name quantity"),
            SizedBox(height: 10),
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. water zagori 15',
                ),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: processItems,
              child: Text("Add Items"),
            )
          ],
        ),
      ),
    );
  }
}
