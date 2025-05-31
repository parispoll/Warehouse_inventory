import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:csv/csv.dart';
import 'database_helper.dart';

class LowStockPage extends StatefulWidget {
  @override
  _LowStockPageState createState() => _LowStockPageState();
}

class _LowStockPageState extends State<LowStockPage> {
  Database? database;
  Map<String, List<Map<String, dynamic>>> categorizedLowStockItems = {};

  @override
  void initState() {
    super.initState();
    initDb();
  }

  Future<void> initDb() async {
    database = await DatabaseHelper.getDatabase();
    await fetchLowStockItems();
  }

  Future<void> fetchLowStockItems() async {
    final results = await database!.rawQuery('''
      SELECT 
        i.name AS item_name,
        i.low_stock_threshold,
        s.quantity,
        l.name AS location,
        c.name AS category
      FROM inventory_stock s
      JOIN inventory i ON s.inventory_id = i.id
      JOIN locations l ON s.location_id = l.id
      LEFT JOIN categories c ON i.category_id = c.id
      WHERE s.quantity < COALESCE(i.low_stock_threshold, 5)
      ORDER BY c.name, i.name
    ''');

    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in results) {
      final category = (item['category'] ?? 'Uncategorized').toString();
      grouped.putIfAbsent(category, () => []).add(item);
    }

    setState(() {
      categorizedLowStockItems = grouped;
    });
  }

  Future<void> exportLowStockToCSV() async {
    final rows = [
      ['Item', 'Category', 'Location', 'Quantity', 'Threshold'],
      for (var entry in categorizedLowStockItems.entries)
        for (var item in entry.value)
          [
            item['item_name'] ?? '',
            entry.key,
            item['location'] ?? '',
            item['quantity']?.toString() ?? '',
            (item['low_stock_threshold'] ?? 5).toString()
          ]
    ];

    final csv = const ListToCsvConverter().convert(rows);

    final warehouseDir = Directory('/storage/emulated/0/Warehouse');
    if (!warehouseDir.existsSync()) {
      await warehouseDir.create(recursive: true);
    }

    final now = DateTime.now();
    final fileName = 'low_stock_${now.year}-${now.month}-${now.day}_${now.hour}${now.minute}.csv';
    final file = File('${warehouseDir.path}/$fileName');
    await file.writeAsString(csv);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Exported to Warehouse: $fileName')),
    );
  }

  Future<void> _changeThreshold(Map<String, dynamic> item) async {
  final TextEditingController _controller = TextEditingController(
    text: (item['low_stock_threshold'] ?? 5).toString(),
  );

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Change Threshold"),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: "New Threshold"),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () async {
            final newThreshold = int.tryParse(_controller.text.trim());
            if (newThreshold != null && database != null) {
              await database!.update(
                'inventory',
                {'low_stock_threshold': newThreshold},
                where: 'name = ?',
                whereArgs: [item['item_name']],
              );
              Navigator.pop(context);
              await fetchLowStockItems(); // refresh list
            }
          },
          child: Text("Save"),
        )
      ],
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Low Stock Items'),
        actions: [
          IconButton(
            icon: Icon(Icons.download),
            onPressed: exportLowStockToCSV,
            tooltip: 'Export Low Stock',
          ),
        ],
      ),
      body: categorizedLowStockItems.isEmpty
          ? Center(child: Text('✅ All items are well-stocked'))
          : ListView(
              children: categorizedLowStockItems.entries.map((entry) {
                final category = entry.key;
                final items = entry.value;
                return ExpansionTile(
                  title: Text(category, style: TextStyle(fontWeight: FontWeight.bold)),
                  children: items.map((item) {
                    return ListTile(
  title: Text('${item['item_name']} (${item['location']})'),
  subtitle: Text(
    'Quantity: ${item['quantity']} | Threshold: ${item['low_stock_threshold'] ?? 5}',
  ),
  onLongPress: () => _changeThreshold(item),
);

                  }).toList(),
                );
              }).toList(),
            ),
    );
  }
}
