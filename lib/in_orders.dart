import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'database_helper.dart';
import 'package:string_similarity/string_similarity.dart';



class InOrdersPage extends StatefulWidget {
  @override
  _InOrdersPageState createState() => _InOrdersPageState();
}

class _InOrdersPageState extends State<InOrdersPage> {
  final TextEditingController _orderController = TextEditingController();
  final TextEditingController _logNameController = TextEditingController();
  Database? database;
  List<String> notFoundItems = [];
  int? lastLogId;
  Map<String, String> aliasMap = {};

  @override
  void initState() {
    super.initState();
    initDatabase();
  }

  
    Future<void> initDatabase() async {
    database = await DatabaseHelper.getDatabase();

    }

Future<Map<String, String>> loadAliasMap() async {
  final aliasRows = await database!.query('item_aliases');
  return {
    for (var row in aliasRows)
      row['alias'].toString().toLowerCase(): row['actual_name'].toString().toLowerCase(),
  };
}


Future<void> processOrder() async {
  final logName = _logNameController.text.trim();
  final orderText = _orderController.text.trim();
  final lines = orderText.split('\n');
  aliasMap = await loadAliasMap();
  notFoundItems.clear();

  List<String> updatedSummary = [];

  for (final line in lines) {
    final cleaned = line.trim().toLowerCase();
    if (cleaned.isEmpty) continue;

    final match = RegExp(r'^(\d+)\s+(.*)$').firstMatch(cleaned);
    if (match == null) {
      notFoundItems.add(line);
      continue;
    }

    final quantity = int.tryParse(match.group(1)!);
    final inputName = match.group(2)!;

    if (quantity == null || inputName.isEmpty) {
      notFoundItems.add(line);
      continue;
    }

    String? matchedName;
    List<Map<String, dynamic>> result = [];

    // Step 1: Exact match
    result = await database!.query(
      'inventory',
      where: 'LOWER(item) = ?',
      whereArgs: [inputName.toLowerCase()],
    );
    if (result.isNotEmpty) {
      matchedName = inputName;
    }

    // Step 2: Alias match
    if (matchedName == null && aliasMap.containsKey(inputName)) {
      matchedName = aliasMap[inputName];
      result = await database!.query(
        'inventory',
        where: 'LOWER(item) = ?',
        whereArgs: [matchedName],
      );
    }

    // Step 3: Fuzzy match
    if (matchedName == null) {
      final allItems = await database!.query('inventory');
      final best = allItems.map((item) {
        final score = StringSimilarity.compareTwoStrings(inputName, item['item'].toString().toLowerCase());
        return {'item': item, 'score': score};
      }).where((e) => (e['score'] as double) > 0.7).toList();

      if (best.isNotEmpty) {
        best.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
        final bestMatch = best.first['item'] as Map<String, dynamic>;
        matchedName = bestMatch['item'].toString();
        result = [bestMatch];
      }
    }

    // Step 4: Prompt for alias if still not matched
    if (matchedName == null || result.isEmpty) {
      notFoundItems.add(line);
      await promptAddAlias(line); // User will choose and alias will be saved
      continue;
    }

    final item = result.first;
    print("Item quantity before: ${item['quantity']} | subtracting: $quantity");
    final currentQty = (item['quantity'] ?? 0) as int;
    final newQty = currentQty - quantity;

    await database!.update(
      'inventory',
      {'quantity': newQty},
      where: 'id = ?',
      whereArgs: [item['id']],
    );

    await database!.insert('order_logs', {
      'log_name': logName,
      'item_id': item['id'],
      'quantity_subtracted': quantity,
      'timestamp': DateTime.now().toIso8601String(),
    });

    updatedSummary.add("${item['item']} → $newQty");
    print("✅ Processed: ${item['item']} -$quantity");
  }

  aliasMap = await loadAliasMap(); // refresh after possible new aliases
  setState(() {});
  _orderController.clear();

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Order Summary'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
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
      actions: [
        TextButton(
          child: Text("OK"),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

Future<void> promptAddAlias(String unknownItem) async {
  final List<Map<String, dynamic>> items = await database!.query('inventory');
  String? selectedItem;

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Unknown Item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Item "$unknownItem" not found.\nPlease link it to an existing item:'),
          DropdownButtonFormField<String>(
            items: items.map((item) {
              return DropdownMenuItem<String>(
                value: item['item'],
                child: Text(item['item']),
              );
            }).toList(),
            onChanged: (value) {
              selectedItem = value;
            },
            decoration: InputDecoration(labelText: 'Select item'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () async {
            if (selectedItem != null) {
              final alias = unknownItem.toLowerCase();
              final actual = selectedItem!.toLowerCase();

              aliasMap[alias] = actual;

              await database!.insert(
                'item_aliases',
                {'alias': alias, 'actual_name': actual},
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Alias saved: $alias → $actual")),
              );
            }

            Navigator.of(context).pop();
          },
          child: Text("Save Alias"),
        ),
      ],
    ),
  );
}




  Future<Map<String, dynamic>?> findBestMatch(String input) async {
    final items = await database!.query('inventory');
    double bestScore = 0;
    Map<String, dynamic>? bestMatch;
    for (var item in items) {
      final itemName = (item['item'] as String).toLowerCase();
      double score = _similarity(input, itemName);
      if (score > bestScore && score > 0.4) {
        bestScore = score;
        bestMatch = item;
      }
    }
    return bestMatch;
  }

  double _similarity(String a, String b) {
    int matches = 0;
    int length = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < length; i++) {
      if (a[i] == b[i]) matches++;
    }
    return matches / b.length;
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
      UPDATE inventory SET quantity = quantity + ? WHERE id = ?
    ''', [qty, itemId]);
  }

  await database!.delete(
    'order_logs',
    where: 'log_name = ?',
    whereArgs: [logName],
  );

  setState(() {});
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("✅ Undo complete for: $logName")),
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("InOrders")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Paste Order Details (e.g. Coca cola zero 5):"),
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
            ElevatedButton(
              onPressed: processOrder,
              child: Text("Process Order"),
            ),
            ElevatedButton(
                onPressed: undoLastOrder,
                 child: Text("Undo Last Order"),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: undoLastOrder,
              child: Text("Undo Last Order"),
            ),
            if (notFoundItems.isNotEmpty) ...[
              SizedBox(height: 16),
              Text("Items Not Found:", style: TextStyle(fontWeight: FontWeight.bold)),
              ...notFoundItems.map((e) => Text(e, style: TextStyle(color: Colors.red)))
            ]
          ],
        ),
      ),
    );
  }
}
