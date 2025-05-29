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
      body: items.isEmpty
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isLowStock = item.quantity < item.lowStockThreshold;

                return ListTile(
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
              },
            ),
    );
  }
} 
