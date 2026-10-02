import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class KitchenPage extends StatefulWidget {
  const KitchenPage({super.key});
  @override
  State<KitchenPage> createState() => _KitchenPageState();
}

class _KitchenPageState extends State<KitchenPage> {
  late final stream = repository.watch('kitchen');
  final clock = ValueNotifier(DateTime.now());
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => clock.value = DateTime.now(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('COCINA · La Casa Cantones')),
    body: LiveList(
      stream: stream,
      builder: (all) {
        final orders =
            all
                .where(
                  (o) =>
                      [
                        'pendiente',
                        'preparando',
                        'listo',
                      ].contains(o['status']) &&
                      objects(o['lines']).isNotEmpty,
                )
                .toList()
              ..sort(
                (a, b) => (date(a['createdAt']) ?? DateTime(2100)).compareTo(
                  date(b['createdAt']) ?? DateTime(2100),
                ),
              );
        if (orders.isEmpty) {
          return const Center(
            child: Text('Sin comandas', style: TextStyle(fontSize: 36)),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (c, b) {
              final count = b.maxWidth > 1100
                  ? 3
                  : b.maxWidth > 700
                  ? 2
                  : 1;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: orders
                    .map(
                      (o) => SizedBox(
                        key: ValueKey(o['id']),
                        width: (b.maxWidth - (count - 1) * 16) / count,
                        child: KitchenCard(order: o, clock: clock),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        );
      },
    ),
  );
}

class KitchenCard extends StatefulWidget {
  final Json order;
  final ValueNotifier<DateTime> clock;
  const KitchenCard({super.key, required this.order, required this.clock});
  @override
  State<KitchenCard> createState() => _KitchenCardState();
}

class _KitchenCardState extends State<KitchenCard> {
  bool busy = false;
  Future<void> advance() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await repository.call(
        widget.order['status'] == 'listo' ? 'archiveKitchen' : 'kitchenStatus',
        {
          'orderId': widget.order['id'],
          'ticketId': widget.order['id'],
          'status': widget.order['status'] == 'pendiente'
              ? 'preparando'
              : 'listo',
        },
      );
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${o['label']}',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            Text(
              '${o['number']} · ${o['status']}',
              style: const TextStyle(fontSize: 20, color: gold),
            ),
            ValueListenableBuilder<DateTime>(
              valueListenable: widget.clock,
              builder: (c, now, _) {
                final seconds = now
                    .difference(date(o['createdAt']) ?? now)
                    .inSeconds
                    .clamp(0, 1000000000);
                final minutes = seconds ~/ 60;
                final color = o['status'] == 'listo' || seconds < 600
                    ? jade
                    : seconds <= 1200
                    ? Colors.amber
                    : imperial;
                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  opacity:
                      o['status'] != 'listo' &&
                          seconds > 1200 &&
                          now.second.isOdd &&
                          !MediaQuery.of(context).disableAnimations
                      ? 0.7
                      : 1,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    padding: const EdgeInsets.all(12),
                    color: color.withValues(alpha: .2),
                    child: Text(
                      o['status'] == 'listo'
                          ? 'LISTO'
                          : '$minutes min ${seconds > 1200 ? '· URGENTE' : ''}',
                      style: TextStyle(
                        fontSize: 32,
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
            for (final l in objects(
              o['lines'],
            ).where((l) => l['esComida'] == true))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l['qty']} × ${l['name']}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if ('${l['note']}'.isNotEmpty)
                      Text(
                        '${l['note']}',
                        style: const TextStyle(fontSize: 22, color: gold),
                      ),
                  ],
                ),
              ),
            if (o['note'] != '')
              Text(
                '${o['note']}',
                style: const TextStyle(fontSize: 22, color: gold),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : advance,
                child: Text(
                  busy
                      ? 'Confirmando…'
                      : o['status'] == 'listo'
                      ? 'Retirar de pantalla'
                      : o['status'] == 'pendiente'
                      ? 'Preparar'
                      : 'Marcar listo',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
