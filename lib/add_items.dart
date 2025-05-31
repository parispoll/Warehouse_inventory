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
  String? selectedParentCategory;
  String? selectedSubCategory;
  List<String> parentCategories = [];
  List<String> subCategories = [];
  String selectedFormat = 'Name & Quantity';

  @override
  void initState() {
    super.initState();
    initDatabase();
  }

  Future<void> initDatabase() async {
    database = await DatabaseHelper.getDatabase();
    await loadParentCategories();
  }

  Future<void> loadParentCategories() async {
    final result = await database!.rawQuery("SELECT name FROM categories WHERE parent_id IS NULL");
    setState(() {
      parentCategories = result.map((e) => e['name'] as String).toList();
      if (parentCategories.isNotEmpty) {
        selectedParentCategory = parentCategories.first;
        loadSubCategories();
      }
    });
  }

  Future<void> loadSubCategories() async {
    if (selectedParentCategory == null) return;
    final parentId = Sqflite.firstIntValue(await database!.rawQuery("SELECT id FROM categories WHERE name = ?", [selectedParentCategory]));
    if (parentId == null) return;

    final result = await database!.rawQuery("SELECT name FROM categories WHERE parent_id = ?", [parentId]);
    setState(() {
      subCategories = result.map((e) => e['name'] as String).toList();
      if (subCategories.isNotEmpty) {
        selectedSubCategory = subCategories.first;
      }
    });
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

    int? categoryId;
    if (selectedSubCategory != null) {
      categoryId = Sqflite.firstIntValue(await database!.rawQuery("SELECT id FROM categories WHERE name = ?", [selectedSubCategory]));
    }

    for (String line in lines) {
      if (selectedFormat == 'Name & Quantity') {
        final parts = line.trim().split(' ');
        if (parts.length < 2) {
          skippedItems.add(line);
          continue;
        }

        final quantity = int.tryParse(parts.last);
        if (quantity == null) {
          skippedItems.add(line);
          continue;
        }

        final itemName = parts.sublist(0, parts.length - 1).join(' ').toLowerCase();

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
            await database!.update('inventory', {'category_id': categoryId, 'name': itemName}, where: 'id = ?', whereArgs: [itemId]);
            await database!.update('inventory_stock', {'quantity': quantity, 'last_updated': DateTime.now().toIso8601String()}, where: 'inventory_id = ? AND location_id = ?', whereArgs: [itemId, mainWarehouseId]);
          }
        } else {
          final itemId = await database!.insert('inventory', {'name': itemName, 'category_id': categoryId, 'low_stock_threshold': 5, 'unit': 'TMX', 'code': null});
          await database!.update('inventory', {'code': itemId}, where: 'id = ?', whereArgs: [itemId]);
          await database!.insert('inventory_stock', {'inventory_id': itemId, 'location_id': mainWarehouseId, 'quantity': quantity, 'last_updated': DateTime.now().toIso8601String()});
          addedItems.add(itemName);
        }
      } else if (selectedFormat == 'Code, Name, Quantity, Unit') {
        final parts = line.split(',').map((e) => e.trim()).toList();
        if (parts.length != 4) {
          skippedItems.add(line);
          continue;
        }

        final code = int.tryParse(parts[0]);
        final itemName = parts[1].toLowerCase();
        final quantity = int.tryParse(parts[2]);
        final unit = parts[3];

        if (code == null || quantity == null) {
          skippedItems.add(line);
          continue;
        }

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
            await database!.update('inventory', {'category_id': categoryId, 'name': itemName, 'unit': unit, 'code': code}, where: 'id = ?', whereArgs: [itemId]);
            await database!.update('inventory_stock', {'quantity': quantity, 'last_updated': DateTime.now().toIso8601String()}, where: 'inventory_id = ? AND location_id = ?', whereArgs: [itemId, mainWarehouseId]);
          }
        } else {
          final itemId = await database!.insert('inventory', {'name': itemName, 'category_id': categoryId, 'unit': unit, 'code': code, 'low_stock_threshold': 5});
          await database!.insert('inventory_stock', {'inventory_id': itemId, 'location_id': mainWarehouseId, 'quantity': quantity, 'last_updated': DateTime.now().toIso8601String()});
          addedItems.add(itemName);
        }
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
            if (parentCategories.isNotEmpty) ...[
              Text("Select Parent Category for Subcategories:"),
              DropdownButton<String>(
                value: selectedParentCategory,
                isExpanded: true,
                items: parentCategories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedParentCategory = value;
                    loadSubCategories();
                  });
                },
              ),
              SizedBox(height: 10),
              if (subCategories.isNotEmpty) ...[
                Text("Select Subcategory:"),
                DropdownButton<String>(
                  value: selectedSubCategory,
                  isExpanded: true,
                  items: subCategories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                  onChanged: (value) => setState(() => selectedSubCategory = value),
                ),
                SizedBox(height: 10),
              ]
            ],
            Text("Select Input Format:"),
            DropdownButton<String>(
              value: selectedFormat,
              isExpanded: true,
              items: ['Name & Quantity', 'Code, Name, Quantity, Unit']
                  .map((format) => DropdownMenuItem(value: format, child: Text(format)))
                  .toList(),
              onChanged: (value) => setState(() => selectedFormat = value!),
            ),
            SizedBox(height: 10),
            Text("Enter items in the selected format:"),
            SizedBox(height: 10),
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: selectedFormat == 'Name & Quantity' ? 'e.g. water zagori 15' : 'e.g. 1234, water zagori, 15, TMX',
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
