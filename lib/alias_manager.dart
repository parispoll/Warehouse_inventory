import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:flutter/services.dart';
import 'database_helper.dart';

class AliasManagerPage extends StatefulWidget {
  @override
  _AliasManagerPageState createState() => _AliasManagerPageState();
}

class _AliasManagerPageState extends State<AliasManagerPage> {
  Database? database;
  Map<String, List<String>> aliasGroups = {};
  List<String> allItems = [];

  @override
  void initState() {
    super.initState();
    initDatabase();
  }

  Future<void> initDatabase() async {
    database = await DatabaseHelper.getDatabase();
    await fetchAliases();
  }

  Future<void> fetchAliases() async {
    final aliasResults = await database!.rawQuery('''
      SELECT i.item AS actual_name, a.alias
      FROM item_aliases a
      JOIN inventory i ON LOWER(a.actual_name) = LOWER(i.item)
    ''');

    final grouped = <String, List<String>>{};
    for (var row in aliasResults) {
      final actual = row['actual_name'] as String;
      final alias = row['alias'] as String;
      grouped.putIfAbsent(actual, () => []).add(alias);
    }

    final itemsResult = await database!.query('inventory');
    allItems = itemsResult.map((e) => e['item'].toString()).toList();

    setState(() {
      aliasGroups = grouped;
    });
  }

  Future<void> showAddAliasDialog({String? existingAlias}) async {
  String? selectedItem;
  TextEditingController aliasController = TextEditingController(text: existingAlias ?? '');

  if (existingAlias != null) {
    // Lookup current actual_name for this alias
    final result = await database!.query(
      'item_aliases',
      where: 'alias = ?',
      whereArgs: [existingAlias],
      limit: 1,
    );
    if (result.isNotEmpty) {
  selectedItem = result.first['actual_name'] as String?;
  if (selectedItem != null && !allItems.contains(selectedItem)) {
    allItems.add(selectedItem);
  }
}

  }

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(existingAlias == null ? "Add New Alias" : "Edit Alias"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            hint: Text("Select inventory item"),
            value: selectedItem,
            onChanged: existingAlias == null
                ? (value) => selectedItem = value
                : null, // disable dropdown for editing
            items: allItems.map((item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            disabledHint: selectedItem != null ? Text(selectedItem!) : Text("No item"),
          ),
          TextField(
            controller: aliasController,
            decoration: InputDecoration(labelText: "Alias name"),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("Cancel")),
        ElevatedButton(
          onPressed: () async {
            final alias = aliasController.text.trim().toLowerCase();
            final actual = selectedItem?.toLowerCase();

            if (alias.isNotEmpty && actual != null) {
              if (existingAlias != null) {
                await database!.update(
                  'item_aliases',
                  {'alias': alias, 'actual_name': actual},
                  where: 'alias = ?',
                  whereArgs: [existingAlias],
                );
              } else {
                await database!.insert(
                  'item_aliases',
                  {'alias': alias, 'actual_name': actual},
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }

              await fetchAliases();
              Navigator.of(context).pop();
            }
          },
          child: Text("Save"),
        ),
      ],
    ),
  );
}


  Future<void> deleteAlias(String alias) async {
    await database!.delete('item_aliases', where: 'alias = ?', whereArgs: [alias]);
    await fetchAliases();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Alias Manager')),
      body: Column(
        children: [
          Expanded(
            child: aliasGroups.isEmpty
                ? Center(child: Text("No aliases available"))
                : ListView(
                    children: aliasGroups.entries.map((entry) {
                      final item = entry.key;
                      final aliases = entry.value;
                      return ExpansionTile(
                        title: Text("$item (${aliases.length})"),
                        children: aliases.map((alias) {
                          return ListTile(
                            title: Text(alias),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit),
                                  onPressed: () => showAddAliasDialog(existingAlias: alias),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => deleteAlias(alias),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () => showAddAliasDialog(),
              icon: Icon(Icons.add),
              label: Text("Add New Alias"),
            ),
          )
        ],
      ),
    );
  }
}
