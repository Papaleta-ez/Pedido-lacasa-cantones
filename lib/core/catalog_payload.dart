import 'models.dart';

/// Only editable fields belong in callable requests. Firestore metadata may
/// contain Timestamp values, which callable functions cannot serialize.
Json catalogPayload(String type, Json value) {
  const fields = <String, List<String>>{
    'inventory': ['name', 'unit', 'stock', 'low', 'version', 'pin'],
    'products': [
      'name',
      'description',
      'category',
      'priceCents',
      'active',
      'esComida',
      'inventoryId',
      'recipe',
    ],
    'zones': ['name', 'width', 'height'],
    'tables': ['name', 'zoneId', 'x', 'y', 'side'],
    'settings': [
      'name',
      'ruc',
      'address',
      'phone',
      'currency',
      'vatBps',
      'packagingId',
    ],
  };
  final allowed = fields[type];
  if (allowed == null) throw ArgumentError.value(type, 'type');
  final payload = <String, dynamic>{
    for (final field in allowed)
      if (value.containsKey(field)) field: value[field],
  };
  if (type == 'products' && payload.containsKey('recipe')) {
    payload['recipe'] = objects(payload['recipe'])
        .map(
          (item) => <String, dynamic>{
            'inventoryId': item['inventoryId'],
            'qty': item['qty'],
          },
        )
        .toList();
  }
  return payload;
}
