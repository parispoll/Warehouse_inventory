import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class LowStockPage extends StatefulWidget {
  @override
  _LowStockPageState createState() => _LowStockPageState();
}

class _LowStockPageState extends State<LowStockPage> {
  Database? database;
  List<Map<String, dynamic>> lowStockItems = [];

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
      SELECT * FROM inventory 
      WHERE quantity < COALESCE(low_stock_threshold, 5)
    ''');

    setState(() {
      lowStockItems = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Low Stock Items')),
      body: lowStockItems.isEmpty
          ? Center(child: Text('✅ All items are well-stocked'))
          : ListView.builder(
              itemCount: lowStockItems.length,
              itemBuilder: (context, index) {
                final item = lowStockItems[index];
                return ListTile(
                  title: Text(item['item']),
                  subtitle: Text('Quantity: ${item['quantity']} | Threshold: ${item['low_stock_threshold'] ?? 5}'),
                );
              },
            ),
    );
  }
}
