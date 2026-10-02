import 'package:cloud_firestore/cloud_firestore.dart';

typedef Json = Map<String, dynamic>;
Json json(dynamic value) => Map<String, dynamic>.from(value as Map);
double number(dynamic value, [double fallback = 0]) =>
    (value as num?)?.toDouble() ?? fallback;
List<Json> objects(dynamic value) => (value as List? ?? []).map(json).toList();

class Product {
  final String id, name, category, inventoryId;
  final int price;
  final bool active, food;
  final List<Json> recipe;
  Product(this.id, Json d)
    : name = d['name'] ?? '',
      category = d['category'] ?? '',
      inventoryId = d['inventoryId'] ?? '',
      price = (d['priceCents'] as num?)?.toInt() ?? 0,
      active = d['active'] == true,
      food = d['esComida'] == true,
      recipe = objects(d['recipe']);
  int available(Map<String, Json> inventory) {
    if (!active || price <= 0) return 0;
    if (recipe.isEmpty) return number(inventory[inventoryId]?['stock']).floor();
    return recipe
        .map((r) {
          final qty = number(r['qty']);
          return qty > 0
              ? (number(inventory[r['inventoryId']]?['stock']) / qty + 1e-9)
                    .floor()
              : 0;
        })
        .reduce((a, b) => a < b ? a : b);
  }
}

DateTime? date(dynamic v) => v is Timestamp ? v.toDate() : null;

class DraftLine {
  final Product product;
  int qty;
  String note;
  DraftLine(this.product, {this.qty = 1, this.note = ''});
  Json toJson() => {'productId': product.id, 'qty': qty, 'note': note};
}
