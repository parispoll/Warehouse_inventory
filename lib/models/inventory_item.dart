class InventoryItem {
  final int id;
  final String name;
  final String? brand;
  final double? price;
  final String? unit;
  final String? barcode;
  final int lowStockThreshold;
  final String? categoryName;
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
      lowStockThreshold: map['low_stock_threshold'],
      categoryName: map['category_name'],
      quantity: map['quantity'],
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
  s.quantity,
  l.name AS location
FROM inventory i
LEFT JOIN categories c ON i.category_id = c.id
LEFT JOIN inventory_stock s ON i.id = s.inventory_id
LEFT JOIN locations l ON s.location_id = l.id
ORDER BY i.name ASC;
''';

