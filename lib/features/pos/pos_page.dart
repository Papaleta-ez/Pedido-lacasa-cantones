import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../billing/checkout_page.dart';

class PosPage extends StatefulWidget {
  const PosPage({super.key});
  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final productsStream = repository.watch('products'),
      inventoryStream = repository.watch('inventory'),
      zonesStream = repository.watch('zones'),
      tablesStream = repository.watch('tables');
  final prefs = SharedPreferencesAsync();
  final lines = <DraftLine>[];
  final customer = TextEditingController();
  String kind = 'mesa', zoneId = 'salon', category = '';
  Json? table, pending;
  bool busy = false, loading = true, showMenu = false;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      final s = await prefs.getString('pos_pending_v2');
      if (s != null) pending = json(jsonDecode(s));
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    customer.dispose();
    super.dispose();
  }

  bool get locked => busy || pending != null;
  void selectTable(Json t) {
    if (locked) return;
    setState(() {
      table = t;
      kind = 'mesa';
      showMenu = true;
    });
  }

  void add(Product p, Map<String, Json> inv) {
    if (locked) return;
    final existing = lines.where((l) => l.product.id == p.id).firstOrNull;
    final qty = existing?.qty ?? 0;
    if (qty >= p.available(inv) || qty >= 99) return;
    setState(() {
      if (existing != null) {
        existing.qty++;
      } else {
        lines.add(DraftLine(p));
      }
    });
  }

  Future<void> send() async {
    if (busy) return;
    if (pending == null &&
        (lines.isEmpty ||
            (kind == 'mesa' && table == null) ||
            (kind != 'mesa' && customer.text.trim().isEmpty))) {
      notice(context, 'Elegí mesa o cliente y agregá artículos');
      return;
    }
    setState(() => busy = true);
    try {
      pending ??= {
        'requestId': repository.newId(),
        'kind': kind,
        'tableIds': kind == 'mesa' ? [table!['id']] : [],
        if (kind == 'mesa' && table?['orderId'] != null)
          'existingOrderId': table!['orderId'],
        'customer': customer.text.trim(),
        'lines': lines.map((l) => l.toJson()).toList(),
        'note': '',
        'display': lines
            .map((l) => {'name': l.product.name, 'qty': l.qty})
            .toList(),
      };
      await prefs.setString('pos_pending_v2', jsonEncode(pending));
      final result = await repository.call(
        pending!['existingOrderId'] == null ? 'submitOrder' : 'addToOrder',
        pending!,
      );
      await prefs.remove('pos_pending_v2');
      if (mounted) {
        notice(context, 'Enviado: ${result['number']}');
        setState(() {
          pending = null;
          lines.clear();
          table = null;
          showMenu = false;
          customer.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        notice(context, 'Envío sin confirmar: $e. Reintentá la misma comanda.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> unlockRejected() async {
    if (pending == null || busy) return;
    // Only an authoritative server read proving nonexistence allows discarding a request.
    setState(() => busy = true);
    try {
      final uid = await repository.functions
          .httpsCallable('checkSubmission')
          .call({'requestId': pending!['requestId']});
      if (json(uid.data)['exists'] == true) {
        await repository.call(
          pending!['existingOrderId'] == null ? 'submitOrder' : 'addToOrder',
          pending!,
        );
        await prefs.remove('pos_pending_v2');
        if (mounted) {
          setState(() {
            pending = null;
            lines.clear();
            table = null;
            showMenu = false;
          });
        }
      } else {
        await prefs.remove('pos_pending_v2');
        if (mounted) setState(() => pending = null);
      }
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('La Casa Cantones · Mesero / Caja'),
        actions: [
          IconButton(
            tooltip: 'Pedidos y cobros',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const OpenOrdersPage()),
            ),
            icon: const Icon(Icons.receipt_long),
          ),
        ],
      ),
      body: LiveList(
        stream: productsStream,
        builder: (ps) => LiveList(
          stream: inventoryStream,
          builder: (inventory) => LiveList(
            stream: zonesStream,
            builder: (zones) => LiveList(
              stream: tablesStream,
              builder: (tables) {
                final inv = {for (final i in inventory) i['id'] as String: i};
                final products = ps
                    .map((p) => Product(p['id'], p))
                    .where((p) => p.active)
                    .toList();
                final map = mapPanel(zones, tables);
                final menu = menuPanel(products, inv);
                final command = commandPanel(inv);
                return LayoutBuilder(
                  builder: (c, b) {
                    if (b.maxWidth >= 1200) {
                      return Row(
                        children: [
                          Expanded(flex: 3, child: map),
                          Expanded(flex: 5, child: menu),
                          SizedBox(width: 360, child: command),
                        ],
                      );
                    }
                    if (b.maxWidth >= 760) {
                      return Row(
                        children: [
                          Expanded(child: showMenu ? menu : map),
                          SizedBox(width: 320, child: command),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(flex: 5, child: showMenu ? menu : map),
                        Expanded(flex: 4, child: command),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget mapPanel(List<Json> zones, List<Json> tables) {
    final z =
        zones.where((z) => z['id'] == zoneId).firstOrNull ?? zones.firstOrNull;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final zone in zones)
                ChoiceChip(
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('${zone['name']}'),
                  ),
                  selected: z?['id'] == zone['id'],
                  onSelected: locked
                      ? null
                      : (_) => setState(() => zoneId = zone['id']),
                ),
              for (final k in ['llevar', 'delivery'])
                OutlinedButton(
                  onPressed: locked
                      ? null
                      : () => setState(() {
                          kind = k;
                          table = null;
                          showMenu = true;
                        }),
                  child: Text(k == 'llevar' ? 'Para llevar' : 'Delivery'),
                ),
            ],
          ),
        ),
        const Text(
          'Dorado: libre · Verde: activo · Rojo: pendiente',
          textAlign: TextAlign.center,
        ),
        if (z == null)
          const Expanded(
            child: Center(child: Text('El dueño debe inicializar las zonas')),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (c, b) {
                final width = number(z['width'], 12),
                    height = number(z['height'], 8);
                final scale = (b.maxWidth / width).clamp(25.0, 100.0);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: width * scale,
                      height: height * scale,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white24),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          for (final t in tables.where(
                            (t) => t['zoneId'] == z['id'],
                          ))
                            Positioned(
                              left: number(t['x']) * scale,
                              top: number(t['y']) * scale,
                              width: (number(t['side'], 1.3) * scale).clamp(
                                56.0,
                                200.0,
                              ),
                              height: (number(t['side'], 1.3) * scale).clamp(
                                56.0,
                                200.0,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.all(4),
                                    backgroundColor: t['orderId'] == null
                                        ? gold
                                        : t['status'] == 'active'
                                        ? jade
                                        : imperial,
                                    foregroundColor: ink,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: locked
                                      ? null
                                      : () => selectTable(t),
                                  child: Text(
                                    '${t['name']}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget menuPanel(List<Product> products, Map<String, Json> inv) {
    const order = [
      'Entradas',
      'Pollo/Pato',
      'Res',
      'Cerdo',
      'Mariscos',
      'Tofu y vegetales',
      'Arroz y fideos',
      'Sopas',
      'Combos',
    ];
    final categories = products.map((p) => p.category).toSet().toList()
      ..sort((a, b) {
        final ai = order.indexOf(a), bi = order.indexOf(b);
        return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
      });
    final selected = categories.contains(category)
        ? category
        : categories.firstOrNull ?? '';
    return Column(
      children: [
        ListTile(
          title: Text(
            kind == 'mesa'
                ? (table?['name'] ?? 'Elegí una mesa')
                : kind == 'llevar'
                ? 'Para llevar'
                : 'Delivery',
          ),
          leading: IconButton(
            onPressed: locked ? null : () => setState(() => showMenu = false),
            icon: const Icon(Icons.table_restaurant),
          ),
        ),
        if (kind != 'mesa')
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: customer,
              readOnly: locked,
              decoration: const InputDecoration(
                labelText: 'Nombre del cliente',
              ),
            ),
          ),
        SizedBox(
          height: 68,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: categories
                .map(
                  (cat) => Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                      label: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(cat),
                      ),
                      selected: cat == selected,
                      onSelected: (_) => setState(() => category = cat),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (c, b) => GridView.extent(
              maxCrossAxisExtent: 290,
              mainAxisExtent: 190,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              padding: const EdgeInsets.all(8),
              children: products.where((p) => p.category == selected).map((p) {
                final left = p.available(inv);
                return Opacity(
                  opacity: left <= 0 ? 0.4 : 1,
                  child: Card(
                    child: InkWell(
                      onTap:
                          left <= 0 ||
                              locked ||
                              (kind == 'mesa' && table == null)
                          ? null
                          : () => add(p, inv),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              money(p.price),
                              style: const TextStyle(color: gold),
                            ),
                            Text(
                              p.price <= 0
                                  ? 'PRECIO SIN CONFIGURAR'
                                  : left <= 0
                                  ? 'AGOTADO'
                                  : 'Quedan: $left ${p.food ? '' : '· Despacha mesero'}',
                              style: TextStyle(
                                color: left <= 0 ? imperial : jade,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget commandPanel(Map<String, Json> inv) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF242020),
      border: Border(left: BorderSide(color: gold)),
    ),
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        const Text(
          'COMANDA',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: gold,
          ),
        ),
        if (table?['orderId'] != null)
          OutlinedButton(
            onPressed: locked
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CheckoutPage(orderId: table!['orderId']),
                    ),
                  ),
            child: const Text('Ver cuenta / Cobrar'),
          ),
        Expanded(
          child: ListView(
            children: [
              if (pending != null)
                ...objects(pending!['display']).map(
                  (l) => ListTile(title: Text('${l['qty']} × ${l['name']}')),
                )
              else
                for (final line in lines)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.product.name,
                            style: const TextStyle(fontSize: 18),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: locked
                                    ? null
                                    : () => setState(() {
                                        line.qty--;
                                        if (line.qty <= 0) lines.remove(line);
                                      }),
                                icon: const Icon(Icons.remove),
                              ),
                              Text(
                                '${line.qty}',
                                style: const TextStyle(fontSize: 24),
                              ),
                              IconButton(
                                onPressed:
                                    locked ||
                                        line.qty >=
                                            line.product.available(inv) ||
                                        line.qty >= 99
                                    ? null
                                    : () => setState(() => line.qty++),
                                icon: const Icon(Icons.add),
                              ),
                              const Spacer(),
                              Text(money(line.qty * line.product.price)),
                            ],
                          ),
                          Wrap(
                            spacing: 4,
                            children:
                                [
                                      'Sin picante',
                                      'Extra picante',
                                      'Salsa aparte',
                                      'Sin cebollín',
                                      'Alergia a mariscos',
                                    ]
                                    .map(
                                      (note) => FilterChip(
                                        label: Text(note),
                                        selected: line.note
                                            .split('; ')
                                            .contains(note),
                                        onSelected: locked
                                            ? null
                                            : (selected) => setState(() {
                                                final notes = line.note.isEmpty
                                                    ? <String>[]
                                                    : line.note.split('; ');
                                                if (selected) {
                                                  notes.add(note);
                                                } else {
                                                  notes.remove(note);
                                                }
                                                line.note = notes.join('; ');
                                              }),
                                      ),
                                    )
                                    .toList(),
                          ),
                          if (line.note.isNotEmpty)
                            Text(
                              line.note,
                              style: const TextStyle(color: gold),
                            ),
                          OutlinedButton(
                            onPressed: locked
                                ? null
                                : () async {
                                    final note = await askText(
                                      context,
                                      'Indicaciones / selección del combo',
                                      initial: line.note,
                                    );
                                    if (note != null && mounted) {
                                      setState(() => line.note = note);
                                    }
                                  },
                            child: const Text('Editar indicaciones'),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        if (pending == null)
          Text(
            'Subtotal: ${money(lines.fold<int>(0, (s, l) => s + l.qty * l.product.price))}',
            style: const TextStyle(fontSize: 20),
          ),
        if (pending != null)
          TextButton(
            onPressed: busy ? null : unlockRejected,
            child: const Text('Verificar envío / corregir rechazo'),
          ),
        SizedBox(
          width: double.infinity,
          height: 72,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: imperial,
              foregroundColor: ivory,
            ),
            onPressed: busy || (pending == null && lines.isEmpty) ? null : send,
            icon: const Icon(Icons.send),
            label: Text(
              busy
                  ? 'Confirmando…'
                  : pending != null
                  ? 'Reintentar misma comanda'
                  : 'Enviar a Cocina',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    ),
  );
}

class OpenOrdersPage extends StatefulWidget {
  const OpenOrdersPage({super.key});
  @override
  State<OpenOrdersPage> createState() => _OpenOrdersPageState();
}

class _OpenOrdersPageState extends State<OpenOrdersPage> {
  late final stream = repository.watch(
    'orders',
    field: 'status',
    equal: 'open',
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pedidos abiertos · Cobrar')),
    body: LiveList(
      stream: stream,
      builder: (orders) => ListView(
        children: orders
            .map(
              (o) => Card(
                child: ListTile(
                  minVerticalPadding: 20,
                  title: Text(
                    '${o['number']} · ${(o['tableNames'] as List).join(' + ')} ${o['customer']}',
                  ),
                  subtitle: Text('${o['kind']} · ${o['kitchenStatus']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CheckoutPage(orderId: o['id']),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );
}
