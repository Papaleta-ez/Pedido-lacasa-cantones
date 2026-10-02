import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'receipt_service.dart';

class CheckoutPage extends StatefulWidget {
  final String orderId;
  const CheckoutPage({super.key, required this.orderId});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  late final stream = repository.document('orders', widget.orderId),
      settings = repository.document('settings', 'business');
  final prefs = SharedPreferencesAsync();
  final selected = <String, int>{};
  bool busy = false, tip = false, partial = false, ready = false;
  String method = 'efectivo';
  int received = 0, discount = 0, people = 1;
  Json? pending;
  String get key => 'payment_pending_${widget.orderId}';
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      final s = await prefs.getString(key);
      if (s != null) pending = json(jsonDecode(s));
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => ready = true);
    }
  }

  bool get locked => busy || pending != null;
  Future<void> pay(Json order) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (pending == null) {
        String? pin;
        if (discount > 0) {
          pin = await askPin(context);
          if (pin == null) return;
        }
        final selections = partial
            ? selected.entries
                  .where((e) => e.value > 0)
                  .map((e) => {'lineId': e.key, 'qty': e.value})
                  .toList()
            : objects(order['lines'])
                  .where((l) => number(l['remaining']) > 0)
                  .map((l) => {'lineId': l['lineId'], 'qty': l['remaining']})
                  .toList();
        pending = {
          'orderId': widget.orderId,
          'requestId': repository.newId(),
          'selections': selections,
          'method': method,
          'tip': tip,
          'discountCents': discount,
          'receivedCents': received,
          'people': people,
          'pin': ?pin,
        };
        // Do not persist a supervisor PIN. Ask again when recovering a discounted payment.
        await prefs.setString(key, jsonEncode({...pending!}..remove('pin')));
      }
      if (number(pending!['discountCents']) > 0 && pending!['pin'] == null) {
        if (!mounted) return;
        final pin = await askPin(context);
        if (pin == null) return;
        pending!['pin'] = pin;
      }
      final result = await repository.call('payOrder', pending!);
      await prefs.remove(key);
      pending = null;
      final invoice = await repository.db
          .collection('invoices')
          .doc(result['id'])
          .get();
      if (mounted) {
        selected.clear();
        notice(context, 'Cobro registrado: ${result['number']}');
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(
              '${result['number']} · ${money(number(result['totalCents']))}',
            ),
            content: Text('Cambio: ${money(number(result['changeCents']))}'),
            actions: [
              TextButton(
                onPressed: () => ReceiptService.printTicket(invoice.data()!),
                child: const Text('Imprimir'),
              ),
              TextButton(
                onPressed: () => ReceiptService.shareTicket(invoice.data()!),
                child: const Text('Compartir PDF'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      pending?.remove('pin');
      if (mounted) {
        notice(context, 'Cobro sin confirmar: $e. Reintentá o verificá.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyPayment() async {
    if (pending == null || busy) return;
    setState(() => busy = true);
    try {
      final r = await repository.call('checkPayment', {
        'requestId': pending!['requestId'],
      });
      if (r['exists'] == true) {
        await prefs.remove(key);
        pending = null;
        if (mounted) {
          notice(
            context,
            'Cobro ya registrado. Podés abrir la factura en el historial.',
          );
        }
      } else {
        await prefs.remove(key);
        pending = null;
      }
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    if (locked) return;
    final pin = await askPin(context);
    if (pin == null || !mounted) return;
    final reason = await askText(context, 'Motivo de cancelación');
    if (reason == null || !mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Devolver stock?'),
        content: const Text(
          'Solo se permite devolverlo antes de preparar. Si ya se preparó, se registra el consumo como merma.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('No devolver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Devolver stock'),
          ),
        ],
      ),
    );
    if (restore == null) return;
    setState(() => busy = true);
    try {
      await repository.call('cancelOrder', {
        'orderId': widget.orderId,
        'pin': pin,
        'reason': reason,
        'restore': restore,
      });
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> join() async {
    final tables = await repository.db.collection('tables').get();
    if (!mounted) return;
    final keys = <String>{};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Unir mesas libres a esta cuenta'),
          content: SizedBox(
            width: 350,
            height: 300,
            child: ListView(
              children: tables.docs
                  .where((t) => t.data()['orderId'] == null)
                  .map(
                    (t) => CheckboxListTile(
                      title: Text('${t.data()['name']}'),
                      value: keys.contains(t.id),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          keys.add(t.id);
                        } else {
                          keys.remove(t.id);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, keys.toList()),
              child: const Text('Unir'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      await repository.call('joinTables', {
        'orderId': widget.orderId,
        'tableIds': result,
      });
    } catch (e) {
      if (mounted) notice(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta · Cobro')),
      body: StreamBuilder<Json?>(
        stream: stream,
        builder: (c, s) {
          if (s.hasError) return Center(child: SelectableText('${s.error}'));
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final order = s.data!;
          return StreamBuilder<Json?>(
            stream: settings,
            builder: (c, b) {
              final business = b.data ?? {};
              final lines = objects(order['lines']);
              final subtotal = lines.fold<int>(
                0,
                (sum, l) =>
                    sum +
                    (number(l['priceCents']) *
                            (partial
                                ? (selected[l['lineId']] ?? 0)
                                : number(l['remaining'])))
                        .round(),
              );
              final net = subtotal - discount;
              final total =
                  net +
                  (net * number(business['vatBps']) / 10000).round() +
                  (tip ? (net * .1).round() : 0);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '${order['number']} · ${(order['tableNames'] as List).join(' + ')} ${order['customer']}',
                        style: const TextStyle(fontSize: 24),
                      ),
                      if (pending != null && order['status'] != 'open') ...[
                        FilledButton(
                          onPressed: busy ? null : () => pay(order),
                          child: const Text('Confirmar cobro pendiente'),
                        ),
                        TextButton(
                          onPressed: busy ? null : verifyPayment,
                          child: const Text('Verificar pago registrado'),
                        ),
                      ],
                      if (order['status'] != 'open') ...[
                        Text(
                          'Pedido ${order['status']}',
                          style: const TextStyle(fontSize: 24, color: gold),
                        ),
                        LiveList(
                          stream: repository.watch(
                            'invoices',
                            field: 'orderId',
                            equal: widget.orderId,
                          ),
                          builder: (invoices) => Column(
                            children: invoices
                                .map(
                                  (i) => ListTile(
                                    title: Text(
                                      '${i['number']} · ${money(number(i['totalCents']))}',
                                    ),
                                    trailing: Wrap(
                                      children: [
                                        IconButton(
                                          onPressed: () =>
                                              ReceiptService.printTicket(i),
                                          icon: const Icon(Icons.print),
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              ReceiptService.shareTicket(i),
                                          icon: const Icon(Icons.share),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ] else ...[
                        SwitchListTile(
                          title: const Text(
                            'Dividir por artículos · cobrar selección',
                          ),
                          value: partial,
                          onChanged: locked
                              ? null
                              : (v) => setState(() => partial = v),
                        ),
                        for (final l in lines.where(
                          (l) => number(l['remaining']) > 0,
                        ))
                          Card(
                            child: ListTile(
                              title: Text(
                                '${l['name']} · ${money(number(l['priceCents']))}',
                              ),
                              subtitle: Text('Pendientes: ${l['remaining']}'),
                              trailing: partial
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          onPressed: locked
                                              ? null
                                              : () => setState(
                                                  () => selected[l['lineId']] =
                                                      ((selected[l['lineId']] ??
                                                                  0) -
                                                              1)
                                                          .clamp(
                                                            0,
                                                            number(
                                                              l['remaining'],
                                                            ).toInt(),
                                                          ),
                                                ),
                                          icon: const Icon(Icons.remove),
                                        ),
                                        Text('${selected[l['lineId']] ?? 0}'),
                                        IconButton(
                                          onPressed: locked
                                              ? null
                                              : () => setState(
                                                  () => selected[l['lineId']] =
                                                      ((selected[l['lineId']] ??
                                                                  0) +
                                                              1)
                                                          .clamp(
                                                            0,
                                                            number(
                                                              l['remaining'],
                                                            ).toInt(),
                                                          ),
                                                ),
                                          icon: const Icon(Icons.add),
                                        ),
                                      ],
                                    )
                                  : Text('${l['remaining']}'),
                            ),
                          ),
                        SwitchListTile(
                          title: const Text(
                            'Propina opcional 10% (antes de IVA)',
                          ),
                          value: tip,
                          onChanged: locked
                              ? null
                              : (v) => setState(() => tip = v),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: locked
                                  ? null
                                  : () async {
                                      final v = await keypad(
                                        context,
                                        'Descuento (centavos)',
                                        initial: discount,
                                      );
                                      if (v != null && mounted) {
                                        setState(() => discount = v);
                                      }
                                    },
                              child: Text('Descuento: ${money(discount)}'),
                            ),
                            OutlinedButton(
                              onPressed: locked
                                  ? null
                                  : () async {
                                      final v = await showDialog<int>(
                                        context: context,
                                        builder: (c) => SimpleDialog(
                                          title: const Text(
                                            'Dividir total entre personas',
                                          ),
                                          children: List.generate(
                                            20,
                                            (i) => SimpleDialogOption(
                                              onPressed: () =>
                                                  Navigator.pop(c, i + 1),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                child: Text(
                                                  '${i + 1} personas',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                      if (v != null && mounted) {
                                        setState(() => people = v);
                                      }
                                    },
                              child: Text('$people personas'),
                            ),
                            if (order['kind'] == 'mesa')
                              OutlinedButton(
                                onPressed: locked ? null : join,
                                child: const Text('Unir mesas'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Total estimado: ${money(total)}',
                          style: const TextStyle(fontSize: 28, color: gold),
                        ),
                        if (people > 1)
                          Text(
                            'Aprox. ${money(total / people)} por persona. Se registra un pago completo; para pagos separados usá división por artículos.',
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          children: ['efectivo', 'tarjeta', 'transferencia']
                              .map(
                                (m) => ChoiceChip(
                                  label: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(m),
                                  ),
                                  selected: method == m,
                                  onSelected: locked
                                      ? null
                                      : (_) => setState(() => method = m),
                                ),
                              )
                              .toList(),
                        ),
                        if (method == 'efectivo')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: OutlinedButton(
                              onPressed: locked
                                  ? null
                                  : () async {
                                      final v = await keypad(
                                        context,
                                        'Efectivo recibido (centavos)',
                                        initial: received,
                                      );
                                      if (v != null && mounted) {
                                        setState(() => received = v);
                                      }
                                    },
                              child: Text(
                                'Recibido: ${money(received)} · Cambio: ${money(received - total)}',
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed:
                              busy ||
                                  (pending == null &&
                                      (subtotal <= 0 ||
                                          discount > subtotal ||
                                          (method == 'efectivo' &&
                                              received < total)))
                              ? null
                              : () => pay(order),
                          child: Text(
                            busy
                                ? 'Confirmando…'
                                : pending == null
                                ? 'Registrar pago'
                                : 'Reintentar mismo pago',
                          ),
                        ),
                        if (pending != null)
                          TextButton(
                            onPressed: busy ? null : verifyPayment,
                            child: const Text(
                              'Verificar pago / corregir rechazo',
                            ),
                          ),
                        TextButton(
                          onPressed: locked ? null : cancel,
                          child: const Text(
                            'Cancelar pedido · requiere PIN',
                            style: TextStyle(color: imperial),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
