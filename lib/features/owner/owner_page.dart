import '../../core/firebase_connection.dart';

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../billing/receipt_service.dart';
import 'catalog_editor.dart';

class OwnerPage extends StatefulWidget {
  const OwnerPage({super.key});
  @override
  State<OwnerPage> createState() => _OwnerPageState();
}

class _OwnerPageState extends State<OwnerPage> {
  int tab = 0;
  bool busy = true;
  final prefs = SharedPreferencesAsync();
  Json? pendingOperation;
  String get operationKey => 'owner_operation_${posAuth.currentUser!.uid}';
  @override
  void initState() {
    super.initState();
    restoreOperation();
  }

  Future<void> restoreOperation() async {
    try {
      final s = await prefs.getString(operationKey);
      if (s != null && mounted) {
        setState(() => pendingOperation = json(jsonDecode(s)));
      }
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Json> safeCall(String name, Json data) async {
    if (pendingOperation != null) {
      throw StateError(
        'Hay una operación sin confirmar. Usá los botones de reintentar o verificar arriba.',
      );
    }
    pendingOperation = {
      'name': name,
      'data': {...data}..remove('pin'),
    };
    await prefs.setString(operationKey, jsonEncode(pendingOperation));
    final result = await repository.call(name, data);
    await prefs.remove(operationKey);
    pendingOperation = null;
    return result;
  }

  Future<void> recoverOperation(bool verify) async {
    await task(() async {
      final op = pendingOperation;
      if (op == null) return;
      final data = json(op['data']);
      if (verify) {
        final result = await repository.call('checkOwnerOperation', {
          'name': op['name'],
          'requestId': data['requestId'],
        });
        await prefs.remove(operationKey);
        pendingOperation = null;
        if (mounted) {
          notice(
            context,
            result['exists'] == true
                ? 'Operación ya registrada'
                : 'Solicitud descartada. Podés corregirla.',
          );
        }
      } else {
        if (op['name'] == 'recordWaste') {
          if (!mounted) return;
          final pin = await askPin(context);
          if (pin == null) return;
          data['pin'] = pin;
        }
        await repository.call(op['name'], data);
        await prefs.remove(operationKey);
        pendingOperation = null;
        if (mounted) notice(context, 'Operación confirmada');
      }
    });
  }

  late final inventory = repository.watch('inventory'),
      invoices = repository.watch('invoices'),
      devices = repository.watch('devices'),
      products = repository.watch('products'),
      zones = repository.watch('zones'),
      tables = repository.watch('tables'),
      settings = repository.document('settings', 'business');
  Future<void> task(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(String type, [Json? value]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CatalogEditor(type: type, value: value),
      ),
    );
  }

  Future<void> close(String type) async {
    final counted = await keypad(context, 'Efectivo contado (centavos)');
    if (counted == null || !mounted) return;
    int opening = 0;
    if (type == 'Z') {
      final v = await keypad(context, 'Fondo de apertura siguiente (centavos)');
      if (v == null) return;
      opening = v;
    }
    await task(() async {
      final r = await safeCall('closeShift', {
        'requestId': repository.newId(),
        'type': type,
        'countedCents': counted,
        'nextOpeningCents': opening,
      });
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Cierre $type'),
            content: Text(
              'Esperado: ${money(number(r['expectedCents']))}\nContado: ${money(number(r['countedCents']))}\nDiferencia: ${money(number(r['differenceCents']))}',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      }
    });
  }

  Future<void> monthly(List<Json> all) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null) return;
    await task(() async {
      final selected = all.where((i) {
        final d = date(i['createdAt'])?.toLocal();
        return d?.year == picked.year && d?.month == picked.month;
      }).toList();
      final bytes = await ReceiptService.monthly(
        selected,
        picked.year,
        picked.month,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Ventas-${picked.year}-${picked.month}.pdf',
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('La Casa Cantones · Dueño'),
      actions: [
        if (pendingOperation != null)
          IconButton(
            tooltip: 'Reintentar operación pendiente',
            onPressed: busy ? null : () => recoverOperation(false),
            icon: const Icon(Icons.sync, color: gold),
          ),
        if (pendingOperation != null)
          IconButton(
            tooltip: 'Verificar operación o descartar rechazo',
            onPressed: busy ? null : () => recoverOperation(true),
            icon: const Icon(Icons.fact_check, color: gold),
          ),
        IconButton(
          onPressed: posAuth.signOut,
          tooltip: 'Cerrar sesión',
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard), label: 'Resumen'),
        NavigationDestination(
          icon: Icon(Icons.restaurant_menu),
          label: 'Catálogo',
        ),
        NavigationDestination(
          icon: Icon(Icons.table_restaurant),
          label: 'Plano',
        ),
        NavigationDestination(icon: Icon(Icons.settings), label: 'Gestión'),
      ],
    ),
    body: tab == 0
        ? dashboard()
        : tab == 1
        ? catalog()
        : tab == 2
        ? layout()
        : management(),
  );
  Widget dashboard() => LiveList(
    stream: invoices,
    builder: (all) => LiveList(
      stream: inventory,
      builder: (stock) {
        final today = DateTime.now();
        final sales = all.where((i) {
          final d = date(i['createdAt'])?.toLocal();
          return d != null &&
              d.year == today.year &&
              d.month == today.month &&
              d.day == today.day;
        }).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Ventas de hoy: ${money(sales.fold<num>(0, (sum, i) => sum + number(i['totalCents'])))}',
              style: const TextStyle(fontSize: 30, color: gold),
            ),
            Text('${sales.length} facturas emitidas'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : () => close('X'),
                  child: const Text('Cierre X'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => close('Z'),
                  child: const Text('Cierre Z'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => monthly(all),
                  child: const Text('Reporte mensual PDF'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Stock bajo', style: TextStyle(fontSize: 24)),
            for (final s in stock.where(
              (i) => number(i['stock']) <= number(i['low']),
            ))
              Card(
                child: ListTile(
                  title: Text('${s['name']}'),
                  subtitle: Text(
                    '${s['stock']} ${s['unit']} · mínimo ${s['low']}',
                  ),
                  trailing: const Icon(Icons.warning, color: imperial),
                  onTap: () => edit('inventory', s),
                ),
              ),
            const SizedBox(height: 24),
            const Text('Últimas facturas', style: TextStyle(fontSize: 24)),
            ...((all.toList()..sort(
                      (a, b) => (date(b['createdAt']) ?? DateTime(2000))
                          .compareTo(date(a['createdAt']) ?? DateTime(2000)),
                    ))
                    .take(30))
                .map(
                  (i) => Card(
                    child: ListTile(
                      title: Text(
                        '${i['number']} · ${money(number(i['totalCents']))}',
                      ),
                      subtitle: Text('${i['method']}'),
                      trailing: IconButton(
                        onPressed: () => ReceiptService.shareTicket(i),
                        icon: const Icon(Icons.share),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    ),
  );
  Widget catalog() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: () => edit('products'),
            child: const Text('Agregar producto'),
          ),
          OutlinedButton(
            onPressed: () => edit('inventory'),
            child: const Text('Agregar insumo'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text('Productos y recetas', style: TextStyle(fontSize: 24)),
      LiveList(
        stream: products,
        builder: (ps) => Column(
          children: ps
              .map(
                (p) => Card(
                  child: ListTile(
                    title: Text(
                      '${p['name']} · ${money(number(p['priceCents']))}',
                    ),
                    subtitle: Text(
                      '${p['category']} · ${p['esComida'] == true ? 'Cocina' : 'Bebida'} · ${p['active'] == true ? 'Activo' : 'Inactivo'}',
                    ),
                    onTap: () => edit('products', p),
                  ),
                ),
              )
              .toList(),
        ),
      ),
      const SizedBox(height: 24),
      const Text('Inventario e insumos', style: TextStyle(fontSize: 24)),
      LiveList(
        stream: inventory,
        builder: (ss) => Column(
          children: ss
              .map(
                (s) => Card(
                  child: ListTile(
                    title: Text('${s['name']}'),
                    subtitle: Text('Quedan ${s['stock']} ${s['unit']}'),
                    onTap: () => edit('inventory', s),
                    trailing: IconButton(
                      tooltip: 'Registrar merma',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: busy
                          ? null
                          : () async {
                              final qty = await keypad(
                                context,
                                'Merma · ingresá cantidad × 100',
                              );
                              if (qty == null || qty == 0 || !mounted) return;
                              final pin = await askPin(context);
                              if (pin == null || !mounted) return;
                              final reason = await askText(
                                context,
                                'Motivo de merma',
                              );
                              if (reason == null) return;
                              await task(() async {
                                await safeCall('recordWaste', {
                                  'requestId': repository.newId(),
                                  'inventoryId': s['id'],
                                  'qty': qty / 100,
                                  'pin': pin,
                                  'reason': reason,
                                });
                              });
                            },
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ],
  );
  Widget layout() => LiveList(
    stream: zones,
    builder: (zz) => LiveList(
      stream: tables,
      builder: (tt) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => edit('zones'),
                child: const Text('Agregar zona'),
              ),
              OutlinedButton(
                onPressed: () => edit('tables'),
                child: const Text('Agregar mesa'),
              ),
            ],
          ),
          for (final z in zz) ...[
            const SizedBox(height: 16),
            ListTile(
              title: Text(
                '${z['name']} · ${z['width']} × ${z['height']} m',
                style: const TextStyle(fontSize: 24),
              ),
              trailing: const Icon(Icons.edit),
              onTap: () => edit('zones', z),
            ),
            for (final t in tt.where((t) => t['zoneId'] == z['id']))
              Card(
                child: ListTile(
                  title: Text('${t['name']} · lado ${t['side']} m'),
                  subtitle: Text(
                    'Posición: ${t['x']}, ${t['y']} · ${t['orderId'] == null ? 'Libre' : 'Ocupada'}',
                  ),
                  onTap: () => edit('tables', t),
                ),
              ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Las posiciones y medidas se editan en metros. El servidor impide superposiciones y mesas fuera de la zona.',
          ),
        ],
      ),
    ),
  );
  Widget management() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      StreamBuilder<Json?>(
        stream: settings,
        builder: (c, s) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: busy
                  ? null
                  : () => task(() async {
                      await repository.call('seedBusiness', {});
                      if (mounted) {
                        notice(
                          context,
                          'Menú inicial creado. Configurá precios, stock, datos y PIN.',
                        );
                      }
                    }),
              child: const Text('Inicializar negocio y menú (una sola vez)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => edit('settings', s.data ?? {'id': 'business'}),
              child: const Text('Datos del negocio · IVA · Empaque'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final pin = await askPin(context);
                      if (pin == null) return;
                      await task(() async {
                        await repository.call('setPin', {'pin': pin});
                        if (mounted) notice(context, 'PIN actualizado');
                      });
                    },
              child: const Text('Configurar / cambiar PIN del dueño'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Text('Dispositivos', style: TextStyle(fontSize: 24)),
      LiveList(
        stream: devices,
        builder: (dd) => Column(
          children: dd
              .map(
                (d) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d['name']} · ${d['active'] == true ? 'Autorizado' : 'Bloqueado'}',
                        ),
                        SelectableText('UID: ${d['id']}'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final role in ['mesero', 'cocina'])
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => task(() async {
                                        await repository.call(
                                          'authorizeDevice',
                                          {
                                            'uid': d['id'],
                                            'role': role,
                                            'active': true,
                                          },
                                        );
                                      }),
                                child: Text('Autorizar $role'),
                              ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => task(() async {
                                      await repository.call('authorizeDevice', {
                                        'uid': d['id'],
                                        'role': d['role'] == ''
                                            ? d['requestedRole']
                                            : d['role'],
                                        'active': false,
                                      });
                                    }),
                              child: const Text(
                                'Revocar',
                                style: TextStyle(color: imperial),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ],
  );
}
