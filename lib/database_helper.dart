import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Database? _database;

  

  static Future<Database> getDatabase() async {
    if (_database != null) return _database!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'hotel_warehouse_inventory10.db');
    final file = File(path);

    if (!await file.exists()) {
      ByteData data = await rootBundle.load('assets/database/hotel_warehouse_inventory10.db');
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await file.writeAsBytes(bytes, flush: true);
    }

    _database = await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await _createAllTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createAllTables(db);
      },
    );

    return _database!;
  }

  // Inside database_helper.dart (optional utility)
static Future<String> getDatabasePath() async {
  final dbPath = await getDatabasesPath();
  return p.join(dbPath, 'hotel_warehouse_inventory10.db');
}


  static Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        parent_id INTEGER,
        FOREIGN KEY (parent_id) REFERENCES categories(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_id INTEGER,
        brand TEXT,
        price REAL,
        unit TEXT,
        barcode TEXT,
        low_stock_threshold INTEGER DEFAULT 5,
        FOREIGN KEY (category_id) REFERENCES categories(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_stock (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inventory_id INTEGER NOT NULL,
        location_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        last_updated TEXT,
        FOREIGN KEY (inventory_id) REFERENCES inventory(id),
        FOREIGN KEY (location_id) REFERENCES locations(id),
        UNIQUE(inventory_id, location_id)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alias TEXT NOT NULL UNIQUE,
        inventory_id INTEGER NOT NULL,
        FOREIGN KEY (inventory_id) REFERENCES inventory(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        log_name TEXT,
        inventory_id INTEGER,
        location_id INTEGER,
        quantity_subtracted INTEGER,
        timestamp TEXT,
        FOREIGN KEY (inventory_id) REFERENCES inventory(id),
        FOREIGN KEY (location_id) REFERENCES locations(id)
      );
    ''');
  }
}
