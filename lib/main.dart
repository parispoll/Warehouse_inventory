import 'package:flutter/material.dart';
import 'inventory_list.dart';
import 'in_orders.dart';
import 'logs_view.dart';
import 'alias_manager.dart';
import 'add_items.dart';
import 'low_stock_page.dart';
import 'database_helper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> copyDatabaseToDownloads(BuildContext context) async {
  var status = await Permission.storage.request();
  if (!status.isGranted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Storage permission denied')),
    );
    return;
  }

  try {
    final dbPath = await DatabaseHelper.getDatabasePath();
    final sourceFile = File(dbPath);
    final downloadsDir = Directory('/storage/emulated/0/Download');

    if (!downloadsDir.existsSync()) {
      await downloadsDir.create(recursive: true);
    }

    final backupFile = File('${downloadsDir.path}/inventory_backup.db');
    await sourceFile.copy(backupFile.path);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Database copied to Downloads')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Failed to copy DB: $e')),
    );
  }
}

Future<List<String>> getLowStockItems() async {
  final db = await DatabaseHelper.getDatabase();

  final result = await db.rawQuery('''
    SELECT 
      i.name AS item_name,
      s.quantity,
      l.name AS location,
      COALESCE(i.low_stock_threshold, 5) AS threshold
    FROM inventory_stock s
    JOIN inventory i ON s.inventory_id = i.id
    JOIN locations l ON s.location_id = l.id
    WHERE s.quantity < COALESCE(i.low_stock_threshold, 5)
    ORDER BY l.name, i.name
  ''');

  return result.map((row) =>
    "${row['item_name']} (${row['location']}) - qty: ${row['quantity']}/${row['threshold']}"
  ).toList();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(InventoryApp());
}

class InventoryApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [routeObserver],
      title: 'Warehouse Inventory',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int lowStockCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLowStock();
    });
  }

  void _loadLowStock() async {
    final lowStockItems = await getLowStockItems();
    setState(() {
      lowStockCount = lowStockItems.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Warehouse Inventory')),
      body: Column(
        children: [
          if (lowStockCount > 0)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LowStockPage()),
                );
              },
              child: Container(
                color: Colors.red,
                width: double.infinity,
                padding: EdgeInsets.all(12),
                child: Text(
                  '⚠ $lowStockCount items in low stock - Tap to view',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    child: Text("Inventory List"),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => InventoryHomePage()),
                    ),
                  ),
                  ElevatedButton(
                    child: Text("InOrders"),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => InOrdersPage()),
                    ),
                  ),
                  ElevatedButton(
                    child: Text("View Logs"),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => LogsViewPage()),
                    ),
                  ),
                  ElevatedButton(
                    child: Text("Alias Manager"),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => AliasManagerPage()),
                    ),
                  ),
                  ElevatedButton(
                    child: Text("Add New Items"),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AddItemsPage()));
                    },
                  ),
                  ElevatedButton(
                    child: Text("Backup Database"),
                    onPressed: () async {
                      await Permission.storage.request();
                      copyDatabaseToDownloads(context);
                    },
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
