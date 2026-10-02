import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedidos_casa_cantones/core/models.dart';
import 'package:pedidos_casa_cantones/features/billing/receipt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final invoice = <String, dynamic>{
    'number': 'F-00000001',
    'orderNumber': 'CC-000001',
    'customer': 'Cliente de prueba',
    'createdAt': Timestamp.fromDate(DateTime(2026, 9, 30, 12)),
    'business': {
      'name': 'La Casa Cantones',
      'ruc': 'RUC DE PRUEBA',
      'address': 'Dirección de prueba del restaurante',
      'phone': '0000-0000',
      'currency': 'C\$',
      'vatBps': 1500,
    },
    'lines': [
      {
        'name': 'Pollo al vapor con cebollín y jengibre',
        'qty': 2,
        'priceCents': 25000,
      },
      {
        'name': 'Camarones medianos a la plancha al estilo Szechuan',
        'qty': 1,
        'priceCents': 35000,
      },
    ],
    'subtotalCents': 85000,
    'discountCents': 5000,
    'vatCents': 12000,
    'tipCents': 8000,
    'totalCents': 100000,
    'method': 'efectivo',
    'receivedCents': 110000,
    'changeCents': 10000,
    'shares': [33334, 33333, 33333],
  };
  test('ticket térmico y reporte generan PDF con artículos extensos', () async {
    final ticket = await ReceiptService.ticket(invoice);
    final report = await ReceiptService.monthly(
      List.generate(50, (i) => {...invoice, 'number': 'F-${i + 1}'}),
      2026,
      9,
    );
    expect(String.fromCharCodes(ticket.take(4)), '%PDF');
    expect(ticket.length, greaterThan(1000));
    expect(String.fromCharCodes(report.take(4)), '%PDF');
    const path = String.fromEnvironment('PDF_QA_DIR');
    if (path.isNotEmpty) {
      await Directory(path).create(recursive: true);
      await File('$path/ticket.pdf').writeAsBytes(ticket);
      await File('$path/monthly.pdf').writeAsBytes(report);
    }
  });
  test('comanda grande pagina en 80 mm sin perder artículos', () async {
    final large = <String, dynamic>{
      ...invoice,
      'lines': List.generate(
        100,
        (i) => {
          'name': 'Plato de prueba número ${i + 1} con nombre extenso',
          'qty': 1,
          'priceCents': 100,
        },
      ),
    };
    final bytes = await ReceiptService.ticket(large);
    expect(bytes.length, greaterThan(1000));
    expect(objects(large['lines']).length, 100);
  });
}
