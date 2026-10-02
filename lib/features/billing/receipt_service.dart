import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/models.dart';
import '../../core/theme.dart';

class ReceiptService {
  static Future<pw.ThemeData> fonts() async => pw.ThemeData.withFont(
    base: pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    ),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')),
  );
  static Future<Uint8List> ticket(Json invoice) async {
    final doc = pw.Document();
    final theme = await fonts();
    final business = json(invoice['business']);
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/images/logo_casa_cantones.png')).buffer
          .asUint8List(),
    );
    final currency = business['currency'] as String? ?? 'C\$';
    pw.Widget row(String label, dynamic cents) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(child: pw.Text(label)),
        pw.Text(money(number(cents), currency)),
      ],
    );
    final items = objects(invoice['lines']);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          297 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        maxPages: 100,
        theme: theme,
        build: (_) => [
          pw.Center(
            child: pw.Image(
              logo,
              width: 45 * PdfPageFormat.mm,
              height: 30 * PdfPageFormat.mm,
              fit: pw.BoxFit.contain,
            ),
          ),
          pw.Center(
            child: pw.Text(
              '${business['name']}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
          for (final key in ['ruc', 'address', 'phone'])
            if ('${business[key]}'.isNotEmpty)
              pw.Center(
                child: pw.Text(
                  '${key == 'ruc' ? 'RUC: ' : ''}${business[key]}',
                  textAlign: pw.TextAlign.center,
                ),
              ),
          pw.SizedBox(height: 8),
          pw.Text('Factura ${invoice['number']}'),
          pw.Text('Pedido ${invoice['orderNumber']}'),
          if (date(invoice['createdAt']) != null)
            pw.Text('${date(invoice['createdAt'])!.toLocal()}'),
          if ('${invoice['customer'] ?? ''}'.isNotEmpty)
            pw.Text('Cliente: ${invoice['customer']}'),
          pw.Divider(),
          for (final item in items)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${item['qty']} x ${item['name']}'),
                  row(
                    '  ${money(number(item['priceCents']), currency)} c/u',
                    number(item['priceCents']) * number(item['qty']),
                  ),
                ],
              ),
            ),
          pw.Divider(),
          row('Subtotal', invoice['subtotalCents']),
          row('Descuento', invoice['discountCents']),
          row('IVA ${number(business['vatBps']) / 100}%', invoice['vatCents']),
          row('Propina', invoice['tipCents']),
          pw.SizedBox(height: 4),
          row('TOTAL', invoice['totalCents']),
          pw.Divider(),
          pw.Text('Pago: ${invoice['method']}'),
          row('Recibido', invoice['receivedCents']),
          row('Cambio', invoice['changeCents']),
          if ((invoice['shares'] as List? ?? []).length > 1) ...[
            pw.Divider(),
            pw.Text('Distribución entre personas (pago registrado completo):'),
            for (final s in (invoice['shares'] as List).indexed)
              row('Persona ${s.$1 + 1}', s.$2),
          ],
          pw.SizedBox(height: 12),
          pw.Center(child: pw.Text('Gracias por su visita')),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> printTicket(Json invoice) async {
    final bytes = await ticket(invoice);
    await Printing.layoutPdf(
      name: '${invoice['number']}',
      format: PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm),
      dynamicLayout: false,
      onLayout: (_) => bytes,
    );
  }

  static Future<void> shareTicket(Json invoice) async {
    await Printing.sharePdf(
      bytes: await ticket(invoice),
      filename: '${invoice['number']}.pdf',
    );
  }

  static Future<Uint8List> monthly(
    List<Json> invoices,
    int year,
    int month,
  ) async {
    final doc = pw.Document();
    final theme = await fonts();
    final sorted = [...invoices]
      ..sort((a, b) => '${a['number']}'.compareTo('${b['number']}'));
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        maxPages: 100,
        header: (_) => pw.Text(
          'La Casa Cantones - Reporte de ventas $year-${month.toString().padLeft(2, '0')}',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        footer: (c) => pw.Text('Página ${c.pageNumber} de ${c.pagesCount}'),
        build: (_) => [
          pw.SizedBox(height: 16),
          pw.Text('Resumen de facturas emitidas durante el mes.'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
            cellPadding: const pw.EdgeInsets.all(4),
            headers: [
              'Factura',
              'Método',
              'Subtotal',
              'IVA',
              'Propina',
              'Total',
            ],
            data: sorted
                .map(
                  (i) => [
                    i['number'],
                    i['method'],
                    money(number(i['subtotalCents'])),
                    money(number(i['vatCents'])),
                    money(number(i['tipCents'])),
                    money(number(i['totalCents'])),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Facturas: ${sorted.length}'),
          pw.Text(
            'Ventas: ${money(sorted.fold<num>(0, (s, i) => s + number(i['totalCents'])))}',
          ),
        ],
      ),
    );
    return doc.save();
  }
}
