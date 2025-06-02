class InventoryItem {
  final int id;
  final String name;
  final String? brand;
  final double? price;
  final String? unit;
  final String? barcode;
  final int lowStockThreshold;
  final String? categoryName;
  final String? parentCategory;
  final int quantity;
  final String location;

  InventoryItem({
    required this.id,
    required this.name,
    this.brand,
    this.price,
    this.unit,
    this.barcode,
    required this.lowStockThreshold,
    this.categoryName,
    this.parentCategory,
    required this.quantity,
    required this.location,
  });

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'],
      name: map['name'],
      brand: map['brand'],
      price: map['price']?.toDouble(),
      unit: map['unit'],
      barcode: map['barcode'],
      lowStockThreshold: _toInt(map['low_stock_threshold']),
      categoryName: map['category_name'],
      parentCategory: map['parent_category'],
      quantity: _toInt(map['quantity']),
      location: map['location'],
    );
  }
}

const String inventoryItemQuery = '''
SELECT 
  i.id,
  i.name,
  i.brand,
  i.price,
  i.unit,
  i.barcode,
  i.low_stock_threshold,
  c.name AS category_name,
  pc.name AS parent_category,
  s.quantity,
  l.name AS location
FROM inventory i
LEFT JOIN categories c ON i.category_id = c.id
LEFT JOIN categories pc ON c.parent_id = pc.id
LEFT JOIN inventory_stock s ON i.id = s.inventory_id
LEFT JOIN locations l ON s.location_id = l.id
ORDER BY i.name ASC;
''';

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return double.tryParse(value)?.toInt() ?? 0;
  return 0;
}
