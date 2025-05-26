import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Database? _database;

  static Future<Database> getDatabase() async {
    if (_database != null) return _database!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'hotel_warehouse_inventory.db');

    if (!File(path).existsSync()) {
      ByteData data = await rootBundle.load('assets/database/hotel_warehouse_inventory.db');
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes);
    }

    _database = await openDatabase(
      path,
      version: 5, // Increment this when schema changes
      onCreate: (db, version) async {
        // Ensure essential tables exist
        await db.execute('''
          CREATE TABLE IF NOT EXISTS item_aliases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            alias TEXT UNIQUE,
            actual_name TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS order_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            log_name TEXT,
            item_id INTEGER,
            quantity_subtracted INTEGER,
            timestamp TEXT
          );
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS item_aliases (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              alias TEXT UNIQUE,
              actual_name TEXT
            );
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE inventory ADD COLUMN price REAL');
          await db.execute('UPDATE inventory SET price = 1 WHERE price IS NULL');
          }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE inventory ADD COLUMN low_stock_threshold INTEGER DEFAULT 5');
        }
          

        // Always ensure critical tables exist
        await db.execute('''
          CREATE TABLE IF NOT EXISTS order_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            log_name TEXT,
            item_id INTEGER,
            quantity_subtracted INTEGER,
            timestamp TEXT
          );
        ''');
      },
    );

    return _database!;
  }
}
