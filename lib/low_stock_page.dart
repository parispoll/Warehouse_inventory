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
      SELECT 
        i.name AS item_name,
        i.low_stock_threshold,
        s.quantity,
        l.name AS location
      FROM inventory_stock s
      JOIN inventory i ON s.inventory_id = i.id
      JOIN locations l ON s.location_id = l.id
      WHERE s.quantity < COALESCE(i.low_stock_threshold, 5)
      ORDER BY l.name, i.name
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
                  title: Text('${item['item_name']} (${item['location']})'),
                  subtitle: Text(
                    'Quantity: ${item['quantity']} | Threshold: ${item['low_stock_threshold'] ?? 5}',
                  ),
                );
              },
            ),
    );
  }
}
