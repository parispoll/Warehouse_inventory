import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'database_helper.dart';
import 'main.dart'; // to access routeObserver
import 'package:flutter/widgets.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class LogsViewPage extends StatefulWidget {
  @override
  _LogsViewPageState createState() => _LogsViewPageState();
}

class _LogsViewPageState extends State<LogsViewPage> with RouteAware {
  Database? database;
  Map<String, List<Map<String, dynamic>>> groupedLogs = {};

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
    fetchLogs(); // Auto-refresh when returning
  }

  Future<void> initDatabase() async {
    database = await DatabaseHelper.getDatabase();
    await fetchLogs();
  }

  Future<void> fetchLogs() async {
    final result = await database!.rawQuery('''
      SELECT ol.*, inv.name AS item_name, inv.price
FROM order_logs ol
LEFT JOIN inventory inv ON ol.item_id = inv.id
ORDER BY ol.timestamp DESC

    ''');

    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var log in result) {
      final logName = (log['log_name'] ?? 'Unnamed Log').toString();
      grouped.putIfAbsent(logName, () => []).add(log);
    }

    setState(() {
      groupedLogs = grouped;
    });
  }

  Future<void> exportLogToCSV(String logName, List<Map<String, dynamic>> items) async {
    final safeLogName = logName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');

    final rows = [
      ['Item', 'Price (€)', 'Quantity Subtracted'],
      ...items.map((log) => [
        log['item_name'],
        log['price'] ?? '—',
        log['quantity_subtracted']
      ]),
    ];

    final csv = const ListToCsvConverter().convert(rows);

    final warehouseDir = Directory('/storage/emulated/0/Warehouse');
    if (!warehouseDir.existsSync()) {
      await warehouseDir.create(recursive: true);
    }

    final file = File('${warehouseDir.path}/order_$safeLogName.csv');
    await file.writeAsString(csv);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Exported to Warehouse: order_$safeLogName.csv')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Order Logs'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: fetchLogs,
          )
        ],
      ),
      body: groupedLogs.isEmpty
          ? Center(child: Text('No logs available'))
          : ListView(
              children: groupedLogs.entries.map((entry) {
                final logName = entry.key;
                final items = entry.value;
                return ExpansionTile(
                  title: Text(logName, style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: IconButton(
                    icon: Icon(Icons.download),
                    onPressed: () async {
                      final status = await Permission.storage.request();
                      if (status.isGranted) {
                        await exportLogToCSV(logName, items);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('❌ Storage permission denied')),
                        );
                      }
                    },
                  ),
                  children: items.map((log) {
                    return ListTile(
                      title: Text(log['item_name'] ?? 'Unknown Item'),
                      subtitle: Text(
                        'Qty: -${log['quantity_subtracted']}\nTime: ${log['timestamp']}',
                      ),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
    );
  }
}
