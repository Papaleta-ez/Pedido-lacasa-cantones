import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedidos_casa_cantones/core/catalog_payload.dart';

void main() {
  test(
    'edited stock omits Firestore metadata and preserves version and PIN',
    () {
      final document = <String, dynamic>{
        'id': 'cerdo',
        'name': 'Cerdo rostizado',
        'unit': 'porción',
        'stock': 8,
        'low': 5,
        'version': 3,
        'pin': '0123',
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        'recipe': <dynamic>[],
      };
      final payload = catalogPayload('inventory', document);
      expect(payload, {
        'name': 'Cerdo rostizado',
        'unit': 'porción',
        'stock': 8,
        'low': 5,
        'version': 3,
        'pin': '0123',
      });
      expect(() => jsonEncode(payload), returnsNormally);
      expect(document.containsKey('updatedAt'), isTrue);
    },
  );

  test('product recipes keep quantities without nested metadata', () {
    final payload = catalogPayload('products', {
      'name': 'Plato',
      'priceCents': 1000,
      'active': true,
      'recipe': [
        {
          'inventoryId': 'cerdo',
          'qty': 0.5,
          'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        },
      ],
    });
    expect(payload['recipe'], [
      {'inventoryId': 'cerdo', 'qty': 0.5},
    ]);
    expect(() => jsonEncode(payload), returnsNormally);
  });

  test('editing tables does not send occupancy state', () {
    expect(
      catalogPayload('tables', {
        'name': 'Mesa 1',
        'zoneId': 'salon',
        'x': 0,
        'y': 0,
        'side': 1.3,
        'orderId': 'pedido',
        'updatedAt': Timestamp.now(),
      }),
      {'name': 'Mesa 1', 'zoneId': 'salon', 'x': 0, 'y': 0, 'side': 1.3},
    );
  });
}
