import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class CatalogEditor extends StatefulWidget {
  final String type;
  final Json? value;
  const CatalogEditor({super.key, required this.type, this.value});
  @override
  State<CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<CatalogEditor> {
  late final String id =
      widget.value?['id'] ??
      (widget.type == 'settings' ? 'business' : repository.newId());
  late final Json value = {...defaults(), ...?widget.value};
  final controllers = <String, TextEditingController>{};
  bool busy = false;
  late final inventory = repository.watch('inventory'),
      zones = repository.watch('zones');
  Json defaults() {
    switch (widget.type) {
      case 'products':
        return {
          'name': '',
          'category': 'Entradas',
          'priceCents': 0,
          'active': true,
          'esComida': true,
          'inventoryId': '',
          'recipe': <Json>[],
        };
      case 'inventory':
        return {'name': '', 'unit': 'unidad', 'stock': 0, 'low': 5};
      case 'zones':
        return {'name': '', 'width': 12, 'height': 8};
      case 'tables':
        return {'name': '', 'zoneId': 'salon', 'x': 0, 'y': 0, 'side': 1.3};
      default:
        return {
          'name': 'La Casa Cantones',
          'ruc': '',
          'address': '',
          'phone': '',
          'currency': 'C\$',
          'vatBps': 0,
          'packagingId': 'empaque',
        };
    }
  }

  @override
  void initState() {
    super.initState();
    value['recipe'] = objects(value['recipe']);
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget textField(String key, String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(
      controller: controllers.putIfAbsent(
        key,
        () => TextEditingController(text: '${value[key] ?? ''}'),
      ),
      onChanged: (v) => value[key] = v,
      decoration: InputDecoration(labelText: title),
      readOnly: busy,
    ),
  );
  Widget numeric(String key, String title, {double scale = 100}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: OutlinedButton(
      onPressed: busy
          ? null
          : () async {
              final result = await keypad(
                context,
                '$title · ingresá ${scale == 1 ? (key == 'vatBps' ? 'puntos básicos' : 'centavos') : 'valor × 100'}',
                monetary: key == 'priceCents',
                initial: (number(value[key]) * scale).round(),
              );
              if (result != null && mounted) {
                setState(
                  () => value[key] = scale == 1 ? result : result / scale,
                );
              }
            },
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('$title: ${value[key]}'),
      ),
    ),
  );
  Widget selector(String key, String title, List<Json> options) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      initialValue: options.any((o) => o['id'] == value[key])
          ? value[key]
          : null,
      decoration: InputDecoration(labelText: title),
      items: options
          .map(
            (o) => DropdownMenuItem<String>(
              value: o['id'],
              child: Text('${o['name']}', overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: busy ? null : (v) => setState(() => value[key] = v),
    ),
  );
  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (widget.type == 'inventory' &&
          number(value['stock']) < number(widget.value?['stock'])) {
        final pin = await askPin(context);
        if (pin == null) return;
        value['pin'] = pin;
      }
      await repository.save(widget.type, id, value);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      value.remove('pin');
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Editar ${const {'products':'producto','inventory':'insumo','zones':'zona','tables':'mesa','settings':'datos del negocio'}[widget.type]}')),
    body: LiveList(
      stream: inventory,
      builder: (stock) => LiveList(
        stream: zones,
        builder: (areas) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                textField('name', 'Nombre'),
                if (widget.type == 'products') ...[
                  textField('category', 'Categoría (editable)'),
                  textField('description', 'Descripción / contenido del combo'),
                  numeric('priceCents', 'Precio', scale: 1),
                  SwitchListTile(
                    title: const Text('Producto activo'),
                    value: value['active'] == true,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => value['active'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('Comida · enviar a cocina'),
                    value: value['esComida'] == true,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => value['esComida'] = v),
                  ),
                  selector(
                    'inventoryId',
                    'Stock directo (si no hay receta)',
                    stock,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Receta · ingredientes por unidad vendida',
                    style: TextStyle(fontSize: 22),
                  ),
                  for (final entry in objects(value['recipe']).indexed)
                    ListTile(
                      title: Text(
                        '${stock.where((s) => s['id'] == entry.$2['inventoryId']).firstOrNull?['name'] ?? entry.$2['inventoryId']} · ${entry.$2['qty']}',
                      ),
                      trailing: IconButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                final list = objects(value['recipe']);
                                list.removeAt(entry.$1);
                                value['recipe'] = list;
                              }),
                        icon: const Icon(Icons.delete),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final ingredient = await showDialog<Json>(
                              context: context,
                              builder: (c) => SimpleDialog(
                                title: const Text('Elegí insumo'),
                                children: stock
                                    .map(
                                      (s) => SimpleDialogOption(
                                        onPressed: () => Navigator.pop(c, s),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(
                                            '${s['name']} (${s['unit']})',
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            );
                            if (ingredient == null || !context.mounted) return;
                            final quantity = await keypad(
                              context,
                              'Cantidad por plato × 100',
                              monetary: false,
                            );
                            if (quantity == null || quantity <= 0 || !mounted) {
                              return;
                            }
                            setState(
                              () => value['recipe'] = [
                                ...objects(value['recipe']),
                                {
                                  'inventoryId': ingredient['id'],
                                  'qty': quantity / 100,
                                },
                              ],
                            );
                          },
                    child: const Text('Agregar ingrediente'),
                  ),
                ],
                if (widget.type == 'inventory') ...[
                  textField('unit', 'Unidad (kg, litro, unidad, porción)'),
                  numeric('stock', 'Stock contado'),
                  numeric('low', 'Alerta de stock bajo'),
                  const Text(
                    'El stock contado reemplaza el saldo actual; registrá mermas desde inventario para conservar su motivo.',
                  ),
                ],
                if (widget.type == 'zones') ...[
                  numeric('width', 'Ancho en metros'),
                  numeric('height', 'Largo en metros'),
                ],
                if (widget.type == 'tables') ...[
                  selector('zoneId', 'Zona', areas),
                  numeric('x', 'Posición X en metros'),
                  numeric('y', 'Posición Y en metros'),
                  numeric('side', 'Lado en metros'),
                ],
                if (widget.type == 'settings') ...[
                  textField('ruc', 'RUC'),
                  textField('address', 'Dirección'),
                  textField('phone', 'Teléfono'),
                  textField('currency', 'Símbolo de moneda'),
                  numeric(
                    'vatBps',
                    'IVA en puntos básicos (1500 = 15%)',
                    scale: 1,
                  ),
                  selector(
                    'packagingId',
                    'Insumo de empaque por artículo para llevar',
                    stock,
                  ),
                  const Text(
                    'Precios antes de IVA. Propina opcional: 10% del subtotal después de descuento.',
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Guardando…' : 'Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
