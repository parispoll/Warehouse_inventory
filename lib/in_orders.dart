import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:string_similarity/string_similarity.dart';
import 'database_helper.dart';

class InOrdersPage extends StatefulWidget {
  @override
  _InOrdersPageState createState() => _InOrdersPageState();
}

class _InOrdersPageState extends State<InOrdersPage> {
  final TextEditingController _orderController = TextEditingController();
  final TextEditingController _logNameController = TextEditingController();
  Database? database;
  List<String> notFoundItems = [];
  Map<String, Map<String, dynamic>> inventoryMap = {};
  Map<String, int> aliasToInventoryId = {};

  @override
  void initState() {
    super.initState();
    initDatabase();
  }

  Future<void> initDatabase() async {
    database = await DatabaseHelper.getDatabase();
    await _loadInventoryAndAliases();
  }

  Future<void> _loadInventoryAndAliases() async {
    final inventoryRows = await database!.rawQuery('''
      SELECT i.id, i.name, s.quantity
      FROM inventory i
      JOIN inventory_stock s ON i.id = s.inventory_id
    ''');

    inventoryMap = {
      for (var row in inventoryRows)
        row['name'].toString().toLowerCase(): {
          'id': row['id'],
          'name': row['name'],
          'quantity': row['quantity']
        }
    };

    final aliasRows = await database!.rawQuery('''
      SELECT a.alias, i.id
      FROM item_aliases a
      JOIN inventory i ON a.inventory_id = i.id
    ''');

    aliasToInventoryId = {
      for (var row in aliasRows) row['alias'].toString().toLowerCase(): row['id'] as int
    };
  }

  Future<void> processOrder() async {
    final logName = _logNameController.text.trim();
    final lines = _orderController.text.trim().split('\n');
    notFoundItems.clear();
    List<String> updatedSummary = [];

    for (final line in lines) {
      final match = RegExp(r'^(\d+)\s+(.*)$').firstMatch(line.trim().toLowerCase());
      if (match == null) {
        notFoundItems.add(line);
        continue;
      }

      final quantity = int.tryParse(match.group(1)!);
      String inputName = match.group(2)!;

      if (quantity == null) {
        notFoundItems.add(line);
        continue;
      }

      Map<String, dynamic>? item;
      int? inventoryId;

      // 1. Exact match
      item = inventoryMap[inputName];
      inventoryId = item?['id'];

      // 2. Alias match
      if (inventoryId == null && aliasToInventoryId.containsKey(inputName)) {
        inventoryId = aliasToInventoryId[inputName];
        item = inventoryMap.values.firstWhere((e) => e['id'] == inventoryId);
      }

      // 3. Fuzzy match
      if (inventoryId == null) {
        final best = inventoryMap.entries
            .map((e) => {
                  'name': e.key,
                  'data': e.value,
                  'score': StringSimilarity.compareTwoStrings(inputName, e.key)
                })
            .where((e) => (e['score'] as double) > 0.65)
            .toList();

        if (best.isNotEmpty) {
          best.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
          item = best.first['data'] as Map<String, dynamic>;
          inventoryId = item!['id'];
        }
      }

      // 4. Prompt for alias if still not matched
      if (inventoryId == null || item == null) {
        notFoundItems.add(line);
        await promptAddAlias(inputName);
        continue;
      }

      final newQty = (item['quantity'] as int) - quantity;

      await database!.update(
        'inventory_stock',
        {'quantity': newQty},
        where: 'inventory_id = ?',
        whereArgs: [inventoryId],
      );

      await database!.insert('order_logs', {
        'log_name': logName,
        'item_id': inventoryId,
        'quantity_subtracted': quantity,
        'timestamp': DateTime.now().toIso8601String(),
      });

      updatedSummary.add("${item['name']} → $newQty");
    }

    await _loadInventoryAndAliases(); // Refresh maps

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Order Summary"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...updatedSummary.map((e) => Text("✔ $e")),
              if (notFoundItems.isNotEmpty) ...[
                SizedBox(height: 12),
                Text("⚠ Not Found:", style: TextStyle(fontWeight: FontWeight.bold)),
                ...notFoundItems.map((e) => Text(e, style: TextStyle(color: Colors.red))),
              ]
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("OK"))
        ],
      ),
    );

    _orderController.clear();
  }

   Future<void> promptAddAlias(String unknownItem) async {
  String? selectedCategory;
  String? selectedItemName;
  List<Map<String, dynamic>> inventoryList = inventoryMap.values.toList();
  List<String> categoryList = [];

  // Fetch category names from the database
  final categories = await database!.rawQuery('SELECT DISTINCT c.name FROM categories c JOIN inventory i ON i.category_id = c.id');
  categoryList = categories.map((row) => row['name'].toString()).toList();

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text("Item Not Found"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Unknown item: \"$unknownItem\"", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(labelText: "Select Category"),
              value: selectedCategory,
              items: categoryList.map((cat) {
                return DropdownMenuItem<String>(
                  value: cat,
                  child: Text(cat),
                );
              }).toList(),
              onChanged: (value) async {
                selectedCategory = value;
                final result = await database!.rawQuery('''
                  SELECT i.name FROM inventory i
                  JOIN categories c ON i.category_id = c.id
                  WHERE c.name = ?
                ''', [selectedCategory]);
                inventoryList = result.map((row) => {
                  'name': row['name'],
                  'id': inventoryMap[row['name']!.toString().toLowerCase()]?['id']
                }).where((item) => item['id'] != null).toList();

                selectedItemName = null; // Reset selected item
                setState(() {});
              },
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(labelText: "Link to existing item"),
              value: selectedItemName,
              items: inventoryList.map<DropdownMenuItem<String>>((item) {
                return DropdownMenuItem<String>(
                  value: item['name'],
                  child: Text(item['name']),
                );
              }).toList(),
              onChanged: (value) => setState(() => selectedItemName = value),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (selectedItemName != null) {
                final itemId = inventoryMap[selectedItemName!.toLowerCase()]!['id'];
                await database!.insert('item_aliases', {
                  'alias': unknownItem.toLowerCase(),
                  'inventory_id': itemId,
                }, conflictAlgorithm: ConflictAlgorithm.ignore);
                await _loadInventoryAndAliases();
              }
              Navigator.pop(context);
            },
            child: Text("Save Alias"),
          )
        ],
      ),
    ),
  );
}



  Future<void> undoLastOrder() async {
    final logName = _logNameController.text.trim();
    if (logName.isEmpty) return;

    final logs = await database!.query(
      'order_logs',
      where: 'log_name = ?',
      whereArgs: [logName],
    );

    for (final log in logs) {
      final itemId = log['item_id'] as int;
      final qty = log['quantity_subtracted'] as int;

      await database!.rawUpdate('''
        UPDATE inventory_stock SET quantity = quantity + ? WHERE inventory_id = ?
      ''', [qty, itemId]);
    }

    await database!.delete('order_logs', where: 'log_name = ?', whereArgs: [logName]);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ Undo complete for log: $logName")),
    );

    await _loadInventoryAndAliases();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("InOrders")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Paste Order Details (e.g. 3 Fanta Orange)"),
              SizedBox(height: 8),
              TextField(
                controller: _orderController,
                maxLines: 8,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "Item name and quantity each line",
                ),
              ),
              SizedBox(height: 16),
              Text("Log Name:"),
              TextField(
                controller: _logNameController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "Enter a name for this log",
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton(onPressed: processOrder, child: Text("Process Order")),
              ElevatedButton(onPressed: undoLastOrder, child: Text("Undo Last Order")),
              if (notFoundItems.isNotEmpty) ...[
                SizedBox(height: 16),
                Text("Items Not Found:", style: TextStyle(fontWeight: FontWeight.bold)),
                ...notFoundItems.map((e) => Text(e, style: TextStyle(color: Colors.red)))
              ]
            ],
          ),
        ),
      ),
    );
  }
}