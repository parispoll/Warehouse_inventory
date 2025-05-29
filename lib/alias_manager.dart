import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class AliasManagerPage extends StatefulWidget {
  @override
  _AliasManagerPageState createState() => _AliasManagerPageState();
}

class _AliasManagerPageState extends State<AliasManagerPage> {
  Database? database;
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> aliases = [];

  int? selectedCategoryId;
  int? selectedItemId;
  String? selectedAlias;
  TextEditingController aliasController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initDatabase();
  }

  Future<void> initDatabase() async {
    database = await DatabaseHelper.getDatabase();
    await loadCategories();
  }

  Future<void> loadCategories() async {
    final result = await database!.query(
      'categories',
      where: 'parent_id IS NOT NULL',
      orderBy: 'name',
    );
    setState(() {
      categories = result;
    });
  }

  Future<void> loadItems(int categoryId) async {
    final result = await database!.rawQuery('''
      SELECT i.id, i.name, COUNT(a.id) AS alias_count
      FROM inventory i
      LEFT JOIN item_aliases a ON a.inventory_id = i.id
      WHERE i.category_id = ?
      GROUP BY i.id
      ORDER BY i.name
    ''', [categoryId]);

    setState(() {
      items = result;
      selectedItemId = null;
      aliases = [];
      selectedAlias = null;
      aliasController.clear();
    });
  }

  Future<void> loadAliases(int inventoryId) async {
    final result = await database!.query(
      'item_aliases',
      where: 'inventory_id = ?',
      whereArgs: [inventoryId],
    );

    setState(() {
      aliases = result;
      selectedAlias = null;
      aliasController.clear();
    });
  }

  Future<void> saveAlias() async {
    final text = aliasController.text.trim().toLowerCase();
    if (text.isEmpty || selectedItemId == null) return;

    if (selectedAlias != null) {
      await database!.update(
        'item_aliases',
        {'alias': text},
        where: 'alias = ? AND inventory_id = ?',
        whereArgs: [selectedAlias, selectedItemId],
      );
    } else {
      await database!.insert(
        'item_aliases',
        {'alias': text, 'inventory_id': selectedItemId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await loadAliases(selectedItemId!);
    aliasController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Alias Manager")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<int>(
              hint: Text("Select Category"),
              value: selectedCategoryId,
              isExpanded: true,
              items: categories.map((cat) {
                return DropdownMenuItem<int>(
                  value: cat['id'] as int,
                  child: Text(cat['name'] ?? ''),
                );
              }).toList(),
              onChanged: (value) async {
                selectedCategoryId = value;
                await loadItems(value!);
              },
            ),
            SizedBox(height: 10),
            DropdownButton<int>(
              hint: Text("Select Item"),
              value: selectedItemId,
              isExpanded: true,
              items: items.map((item) {
                final aliasCount = item['alias_count'];
                return DropdownMenuItem<int>(
                  value: item['id'] as int,
                  child: Text("${item['name']} (${aliasCount})"),
                );
              }).toList(),
              onChanged: (value) async {
                selectedItemId = value;
                await loadAliases(value!);
              },
            ),
            if (aliases.isNotEmpty) ...[
              SizedBox(height: 10),
              DropdownButton<String>(
                hint: Text("Select Alias to Edit"),
                value: selectedAlias,
                isExpanded: true,
                items: aliases.map((a) {
                  return DropdownMenuItem<String>(
                    value: a['alias'] as String,
                    child: Text(a['alias']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedAlias = value;
                    aliasController.text = value ?? '';
                  });
                },
              )
            ],
            SizedBox(height: 10),
            TextField(
              controller: aliasController,
              decoration: InputDecoration(labelText: "Alias name"),
            ),
            SizedBox(height: 10),
            ElevatedButton.icon(
              icon: Icon(Icons.save),
              label: Text("Save Alias"),
              onPressed: saveAlias,
            )
          ],
        ),
      ),
    );
  }
} 
