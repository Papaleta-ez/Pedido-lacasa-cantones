import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PROTOTIPO LOCAL: menú y mapa se guardan en este dispositivo.
// Los pedidos son de prueba, viven en memoria y NO se envían a otro equipo.
// Los accesos Mesero/Cocina/Dueño todavía no tienen autenticación.
const negro = Color(0xFF111318);
const dorado = Color(0xFFFFB547);
const rojo = Color(0xFFB71C1C);
const verde = Color(0xFF68D5A4);
const logo = 'assets/images/logo_casa_cantones.png';
const anchoPlano = 1000.0;
const altoPlano = 620.0;
final datos = Datos();
int secuenciaId = 0;
String nuevoId() => '${DateTime.now().microsecondsSinceEpoch}_${secuenciaId++}';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? error;
  try {
    await datos.cargar();
  } catch (_) {
    error = 'No se pudo abrir el guardado local. Cerrá y abrí la app. '
        'No se han borrado tus datos.';
  }
  runApp(CasaCantonesApp(error: error));
}

class Producto {
  final String id, nombre, categoria;
  final bool disponible;
  const Producto(this.id, this.nombre, this.categoria, this.disponible);
  Map<String, dynamic> toJson() => {
    'id': id, 'nombre': nombre, 'categoria': categoria, 'disponible': disponible,
  };
  factory Producto.fromJson(Map<String, dynamic> j) => Producto(
    j['id'] as String, j['nombre'] as String, j['categoria'] as String,
    j['disponible'] as bool,
  );
}

class Mesa {
  final String id, nombre, forma;
  final int sillas;
  final bool girada;
  double x, y;
  Mesa(this.id, this.nombre, this.forma, this.sillas, this.girada, this.x, this.y);
  double get ancho => forma == 'Rectangular' && !girada ? 190 : 136;
  double get alto => forma == 'Rectangular' && girada ? 190 : 136;
  Map<String, dynamic> toJson() => {
    'id': id, 'nombre': nombre, 'forma': forma, 'sillas': sillas,
    'girada': girada, 'x': x, 'y': y,
  };
  factory Mesa.fromJson(Map<String, dynamic> j) => Mesa(
    j['id'] as String, j['nombre'] as String, j['forma'] as String,
    j['sillas'] as int, j['girada'] as bool,
    (j['x'] as num).toDouble(), (j['y'] as num).toDouble(),
  );
  Mesa copia() => Mesa.fromJson(toJson());
}

class LineaPedido {
  final String nombre;
  final int cantidad;
  const LineaPedido(this.nombre, this.cantidad);
}

enum EstadoPedido { pendiente, preparando, listo, entregado }
const nombresEstado = ['Pendiente', 'Preparando', 'Listo', 'Entregado'];
const coloresEstado = [dorado, Colors.lightBlueAccent, verde, Colors.grey];

class Pedido {
  final int numero;
  final String mesaId, mesaNombre, nota;
  final List<LineaPedido> lineas;
  final DateTime hora = DateTime.now();
  EstadoPedido estado = EstadoPedido.pendiente;
  Pedido(this.numero, this.mesaId, this.mesaNombre, this.nota, this.lineas);
}

class Datos extends ChangeNotifier {
  final _preferencias = SharedPreferencesAsync();
  static const _clave = 'cantones_config_local_v1';
  List<Producto> productos = [
    const Producto('p1', 'Arroz chino', 'Comidas', true),
    const Producto('p2', 'Chop Suey', 'Comidas', true),
    const Producto('p3', 'Pollo agridulce', 'Comidas', true),
    const Producto('p4', 'Wantán frito', 'Entradas', true),
    const Producto('p5', 'Coca-Cola lata', 'Bebidas', true),
    const Producto('p6', 'Té frío', 'Bebidas', true),
  ];
  List<Mesa> mesas = [
    Mesa('m1', 'Mesa 1', 'Redonda', 2, false, 90, 80),
    Mesa('m2', 'Mesa 2', 'Cuadrada', 4, false, 400, 80),
    Mesa('m3', 'Mesa 3', 'Rectangular', 6, false, 700, 80),
    Mesa('m4', 'Mesa 4', 'Redonda', 4, false, 90, 370),
    Mesa('m5', 'Mesa 5', 'Cuadrada', 8, false, 400, 370),
    Mesa('m6', 'Mesa 6', 'Rectangular', 8, false, 700, 370),
  ];
  final List<Pedido> pedidos = [];
  int _numero = 1;

  Future<void> cargar() async {
    final texto = await _preferencias.getString(_clave);
    if (texto == null) return;
    final j = jsonDecode(texto) as Map<String, dynamic>;
    final menu = (j['productos'] as List)
        .map((p) => Producto.fromJson(Map<String, dynamic>.from(p))).toList();
    final plano = (j['mesas'] as List)
        .map((m) => Mesa.fromJson(Map<String, dynamic>.from(m))).toList();
    productos = menu;
    mesas = plano;
  }

  Future<void> guardar({List<Producto>? menu, List<Mesa>? plano}) async {
    final nuevosProductos = menu ?? productos;
    final nuevasMesas = plano ?? mesas;
    await _preferencias.setString(_clave, jsonEncode({
      'productos': nuevosProductos.map((p) => p.toJson()).toList(),
      'mesas': nuevasMesas.map((m) => m.toJson()).toList(),
    }));
    productos = nuevosProductos;
    mesas = nuevasMesas;
    notifyListeners();
  }

  bool conPedido(String id) => pedidos.any(
        (p) => p.mesaId == id && p.estado != EstadoPedido.entregado,
  );

  Pedido agregarPedido(Mesa mesa, List<LineaPedido> lineas, String nota) {
    final p = Pedido(
      _numero++, mesa.id, mesa.nombre, nota, List.unmodifiable(lineas),
    );
    pedidos.add(p);
    notifyListeners();
    return p;
  }

  void avanzar(Pedido p) {
    if (p.estado == EstadoPedido.entregado) return;
    p.estado = EstadoPedido.values[p.estado.index + 1];
    notifyListeners();
  }
}

class CasaCantonesApp extends StatelessWidget {
  final String? error;
  const CasaCantonesApp({super.key, this.error});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Pedidos · La Casa Cantones',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: dorado,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: negro,
      appBarTheme: const AppBarThemeData(
        backgroundColor: negro,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationThemeData(
        border: OutlineInputBorder(),
        filled: true,
      ),
    ),
    home: error == null ? const InicioPage() : Scaffold(
      body: Center(child: Padding(
        padding: const EdgeInsets.all(30),
        child: Text(error!),
      )),
    ),
  );
}

void abrir(BuildContext context, Widget pantalla) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => pantalla),
  );
}

void aviso(BuildContext context, String mensaje) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(mensaje)),
  );
}

Future<bool> confirmar(
    BuildContext context,
    String titulo,
    String texto,
    ) async {
  return await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  ) ?? false;
}

class Logotipo extends StatelessWidget {
  final double lado;
  const Logotipo({super.key, this.lado = 40});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.asset(
      logo,
      width: lado,
      height: lado,
      fit: BoxFit.contain,
      errorBuilder: (_, error, stack) => SizedBox(
        width: lado,
        height: lado,
        child: Icon(
          Icons.restaurant,
          size: lado * 0.65,
          color: dorado,
        ),
      ),
    ),
  );
}

class Marco extends StatelessWidget {
  final String titulo;
  final Widget child;
  final List<Widget> acciones;

  const Marco({
    super.key,
    required this.titulo,
    required this.child,
    this.acciones = const [],
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(children: [
        const Logotipo(),
        const SizedBox(width: 12),
        Expanded(child: Text(
          titulo,
          overflow: TextOverflow.ellipsis,
        )),
      ]),
      actions: acciones,
    ),
    body: SafeArea(child: Column(children: [
      Container(
        width: double.infinity,
        color: const Color(0xFF332810),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: const Text(
          'PRUEBA LOCAL · No conecta dispositivos · No usar con pedidos reales',
          textAlign: TextAlign.center,
          style: TextStyle(color: dorado, fontSize: 12),
        ),
      ),
      Expanded(child: child),
    ])),
  );
}

class ConfirmarSalida extends StatefulWidget {
  final bool cambios;
  final Widget child;

  const ConfirmarSalida({
    super.key,
    required this.cambios,
    required this.child,
  });

  @override
  State<ConfirmarSalida> createState() => _ConfirmarSalidaState();
}

class _ConfirmarSalidaState extends State<ConfirmarSalida> {
  bool salir = false, preguntando = false;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.cambios || salir,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || preguntando) return;
      preguntando = true;
      final ok = await confirmar(
        context,
        '¿Salir sin guardar?',
        'Los cambios o el pedido sin enviar de esta pantalla se perderán.',
      );
      preguntando = false;
      if (!mounted || !ok) return;
      setState(() => salir = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    },
    child: widget.child,
  );
}

class InicioPage extends StatelessWidget {
  const InicioPage({super.key});

  @override
  Widget build(BuildContext context) => Marco(
    titulo: 'La Casa Cantones',
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [negro, Color(0xFF351015)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              border: Border.all(color: dorado, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Logotipo(lado: 145),
          ),
          const SizedBox(height: 18),
          const Text(
            'LA CASA CANTONES',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: dorado,
            ),
          ),
          const Text('PEDIDOS A COCINA · SIN PRECIOS'),
          const SizedBox(height: 30),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            alignment: WrapAlignment.center,
            children: [
              _acceso(
                context, 'MESERO', 'Mesas y pedidos',
                Icons.table_restaurant,
                const MesasPage(),
                Colors.lightBlueAccent,
              ),
              _acceso(
                context, 'COCINA', 'Pantalla de solo lectura',
                Icons.soup_kitchen,
                const PedidosPage(cocina: true),
                dorado,
              ),
              _acceso(
                context, 'DUEÑO', 'Editar productos y mapa',
                Icons.tune,
                const DuenoPage(),
                Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Accesos libres solo para esta prueba. Todavía no hay contraseñas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ]),
      )),
    ),
  );

  Widget _acceso(
      BuildContext c,
      String titulo,
      String texto,
      IconData icono,
      Widget pantalla,
      Color color,
      ) => SizedBox(
    width: 230,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => abrir(c, pantalla),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(children: [
            Icon(icono, size: 52, color: color),
            const SizedBox(height: 12),
            Text(
              titulo,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            Text(texto, textAlign: TextAlign.center),
          ]),
        ),
      ),
    ),
  );
}

class DuenoPage extends StatelessWidget {
  const DuenoPage({super.key});

  @override
  Widget build(BuildContext context) => Marco(
    titulo: 'Dueño',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(child: ListTile(
          leading: const Icon(Icons.restaurant_menu, color: dorado),
          title: const Text('PRODUCTOS'),
          subtitle: const Text('Agregar, editar, ocultar o quitar'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => abrir(context, const ProductosPage()),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.dashboard_customize, color: dorado),
          title: const Text('EDITAR MAPA DE MESAS'),
          subtitle: const Text('Mover mesas, cambiar nombre, forma y sillas'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => abrir(context, const EditorMapaPage()),
        )),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Los productos y el mapa se guardan localmente al confirmar. '
                'No hace falta editar el código para cambiarlos.',
          ),
        ),
      ],
    ),
  );
}

class ProductosPage extends StatefulWidget {
  const ProductosPage({super.key});

  @override
  State<ProductosPage> createState() => _ProductosPageState();
}

class _ProductosPageState extends State<ProductosPage> {
  bool guardando = false;

  Future<void> guardar(List<Producto> lista) async {
    if (guardando) return;
    setState(() => guardando = true);
    try {
      await datos.guardar(menu: lista);
      if (mounted) aviso(context, 'Menú guardado en este dispositivo');
    } catch (_) {
      if (mounted) {
        aviso(context, 'No se pudo guardar. No se aplicaron los cambios.');
      }
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Future<void> editar([Producto? p]) async {
    final nuevo = await showDialog<Producto>(
      context: context,
      builder: (_) => FormularioProducto(producto: p),
    );
    if (nuevo == null || !mounted) return;
    final lista = [...datos.productos];
    final i = lista.indexWhere((e) => e.id == nuevo.id);
    if (i < 0) {
      lista.add(nuevo);
    } else {
      lista[i] = nuevo;
    }
    await guardar(lista);
  }

  @override
  Widget build(BuildContext context) => Marco(
    titulo: 'Productos · Dueño',
    acciones: [
      IconButton(
        tooltip: 'Agregar producto',
        onPressed: guardando ? null : () => editar(),
        icon: const Icon(Icons.add_circle, color: dorado),
      ),
    ],
    child: ListenableBuilder(
      listenable: datos,
      builder: (context, _) => Column(children: [
        if (guardando) const LinearProgressIndicator(),
        Expanded(
          child: datos.productos.isEmpty
              ? const Center(
            child: Text('Tocá + para agregar el primer producto'),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: datos.productos.length,
            itemBuilder: (context, i) {
              final p = datos.productos[i];
              return Card(child: ListTile(
                leading: Icon(
                  p.disponible
                      ? Icons.restaurant
                      : Icons.visibility_off,
                  color: dorado,
                ),
                title: Text(p.nombre),
                subtitle: Text(
                  '${p.categoria} · ${p.disponible ? "Disponible" : "Oculto"}',
                ),
                onTap: guardando ? null : () => editar(p),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: guardando ? null : () => editar(p),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Quitar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: guardando ? null : () async {
                        final ok = await confirmar(
                          context,
                          '¿Quitar ${p.nombre}?',
                          'Se quitará del menú. Los pedidos de prueba '
                              'ya creados no cambian.',
                        );
                        if (ok && mounted) {
                          await guardar(
                            datos.productos
                                .where((e) => e.id != p.id)
                                .toList(),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ));
            },
          ),
        ),
      ]),
    ),
  );
}

class FormularioProducto extends StatefulWidget {
  final Producto? producto;
  const FormularioProducto({super.key, this.producto});

  @override
  State<FormularioProducto> createState() => _FormularioProductoState();
}

class _FormularioProductoState extends State<FormularioProducto> {
  final form = GlobalKey<FormState>();
  late final nombre = TextEditingController(
    text: widget.producto?.nombre ?? '',
  );
  late final categoria = TextEditingController(
    text: widget.producto?.categoria ?? 'Comidas',
  );
  late bool disponible = widget.producto?.disponible ?? true;

  @override
  void dispose() {
    nombre.dispose();
    categoria.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.producto == null ? 'Nuevo producto' : 'Editar producto',
    ),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nombre,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Nombre del plato o bebida',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Escribí el nombre';
                  }
                  if (datos.productos.any(
                        (p) => p.id != widget.producto?.id &&
                        p.nombre.toLowerCase() == v.trim().toLowerCase(),
                  )) {
                    return 'Ese producto ya existe';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: categoria,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  hintText: 'Comidas, Bebidas...',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Escribí una categoría'
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Disponible para pedir'),
                value: disponible,
                onChanged: (v) => setState(() => disponible = v),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, Producto(
            widget.producto?.id ?? nuevoId(),
            nombre.text.trim(),
            categoria.text.trim(),
            disponible,
          ));
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}

class EditorMapaPage extends StatefulWidget {
  const EditorMapaPage({super.key});

  @override
  State<EditorMapaPage> createState() => _EditorMapaPageState();
}

class _EditorMapaPageState extends State<EditorMapaPage> {
  late final List<Mesa> borrador =
  datos.mesas.map((m) => m.copia()).toList();

  String? seleccion;
  bool cambios = false, guardando = false;

  Mesa? get elegida {
    for (final m in borrador) {
      if (m.id == seleccion) return m;
    }
    return null;
  }

  Future<void> editar([Mesa? m]) async {
    final nueva = await showDialog<Mesa>(
      context: context,
      builder: (_) => FormularioMesa(mesa: m, mesas: borrador),
    );
    if (nueva == null || !mounted) return;

    nueva.x = nueva.x.clamp(0, anchoPlano - nueva.ancho).toDouble();
    nueva.y = nueva.y.clamp(0, altoPlano - nueva.alto).toDouble();

    setState(() {
      final i = borrador.indexWhere((e) => e.id == nueva.id);
      if (i < 0) {
        borrador.add(nueva);
      } else {
        borrador[i] = nueva;
      }
      seleccion = nueva.id;
      cambios = true;
    });
  }

  Future<void> quitar() async {
    final m = elegida;
    if (m == null) return;

    if (datos.conPedido(m.id)) {
      aviso(context, 'Esta mesa tiene pedidos pendientes de entregar');
      return;
    }

    if (!await confirmar(
      context,
      '¿Quitar ${m.nombre}?',
      'Desaparecerá al guardar el mapa.',
    )) return;

    if (!mounted) return;
    setState(() {
      borrador.removeWhere((e) => e.id == m.id);
      seleccion = null;
      cambios = true;
    });
  }

  Future<void> guardar() async {
    setState(() => guardando = true);
    try {
      await datos.guardar(
        plano: borrador.map((m) => m.copia()).toList(),
      );
      if (!mounted) return;
      setState(() => cambios = false);
      aviso(context, 'Mapa guardado en este dispositivo');
    } catch (_) {
      if (mounted) {
        aviso(
          context,
          'No se pudo guardar. Tus cambios siguen aquí para reintentar.',
        );
      }
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => ConfirmarSalida(
    cambios: cambios,
    child: Marco(
      titulo: 'Editar mapa · Dueño',
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: guardando ? null : () => editar(),
                icon: const Icon(Icons.add),
                label: const Text('Agregar mesa'),
              ),
              OutlinedButton.icon(
                onPressed: elegida == null || guardando
                    ? null
                    : () => editar(elegida),
                icon: const Icon(Icons.edit),
                label: const Text('Editar seleccionada'),
              ),
              OutlinedButton.icon(
                onPressed: elegida == null || guardando ? null : quitar,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar'),
              ),
              FilledButton.icon(
                onPressed: !cambios || guardando ? null : guardar,
                icon: const Icon(Icons.save),
                label: Text(
                  guardando ? 'Guardando...' : 'Guardar mapa',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${elegida?.nombre ?? "Tocá una mesa"} · Arrastrá para mover · '
                '${cambios ? "Cambios sin guardar" : "Sin cambios pendientes"}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: dorado),
          ),
        ),
        Expanded(
          child: AbsorbPointer(
            absorbing: guardando,
            child: MapaMesas(
              mesas: borrador,
              seleccion: seleccion,
              alTocar: (m) => setState(() => seleccion = m.id),
              alMover: (m, pos) => setState(() {
                m.x = pos.dx;
                m.y = pos.dy;
                seleccion = m.id;
                cambios = true;
              }),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'El nombre identifica la mesa; las sillas indican su capacidad.',
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    ),
  );
}

class FormularioMesa extends StatefulWidget {
  final Mesa? mesa;
  final List<Mesa> mesas;

  const FormularioMesa({
    super.key,
    this.mesa,
    required this.mesas,
  });

  @override
  State<FormularioMesa> createState() => _FormularioMesaState();
}

class _FormularioMesaState extends State<FormularioMesa> {
  final form = GlobalKey<FormState>();
  late final nombre = TextEditingController(
    text: widget.mesa?.nombre ?? sugerirNombre(),
  );
  late final sillas = TextEditingController(
    text: '${widget.mesa?.sillas ?? 4}',
  );
  late String forma = widget.mesa?.forma ?? 'Redonda';
  late bool girada = widget.mesa?.girada ?? false;

  String sugerirNombre() {
    var n = 1;
    while (widget.mesas.any(
          (m) => m.nombre.toLowerCase() == 'mesa $n',
    )) {
      n++;
    }
    return 'Mesa $n';
  }

  @override
  void dispose() {
    nombre.dispose();
    sillas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.mesa == null ? 'Nueva mesa' : 'Editar mesa'),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nombre,
                maxLength: 18,
                decoration: const InputDecoration(
                  labelText: 'Nombre o número de mesa',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Escribí un nombre';
                  }
                  if (widget.mesas.any(
                        (m) => m.id != widget.mesa?.id &&
                        m.nombre.toLowerCase() == v.trim().toLowerCase(),
                  )) {
                    return 'Ese nombre ya existe';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: sillas,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Cantidad de sillas (1 a 12)',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 1 || n > 12
                      ? 'Usá un número del 1 al 12'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: forma,
                decoration: const InputDecoration(labelText: 'Forma'),
                items: ['Redonda', 'Cuadrada', 'Rectangular']
                    .map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(f),
                )).toList(),
                onChanged: (v) => setState(() => forma = v!),
              ),
              if (forma == 'Rectangular')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Posición vertical'),
                  value: girada,
                  onChanged: (v) => setState(() => girada = v),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, Mesa(
            widget.mesa?.id ?? nuevoId(),
            nombre.text.trim(),
            forma,
            int.parse(sillas.text),
            girada,
            widget.mesa?.x ?? 40,
            widget.mesa?.y ?? 40,
          ));
        },
        child: const Text('Aplicar'),
      ),
    ],
  );
}

// Plano a escala: mantiene las posiciones aunque cambie la pantalla.
class MapaMesas extends StatefulWidget {
  final List<Mesa> mesas;
  final String? seleccion;
  final ValueChanged<Mesa> alTocar;
  final void Function(Mesa, Offset)? alMover;

  const MapaMesas({
    super.key,
    required this.mesas,
    required this.alTocar,
    this.alMover,
    this.seleccion,
  });

  @override
  State<MapaMesas> createState() => _MapaMesasState();
}

class _MapaMesasState extends State<MapaMesas> {
  Offset inicioPuntero = Offset.zero, inicioMesa = Offset.zero;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, limites) {
        final escala = math.min(
          limites.maxWidth / anchoPlano,
          limites.maxHeight / altoPlano,
        );
        if (escala <= 0) return const SizedBox.shrink();

        return Center(child: FittedBox(
          child: SizedBox(
            width: anchoPlano,
            height: altoPlano,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF1B1D23),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24),
              ),
              child: Stack(children: [
                const Positioned(
                  left: 24,
                  top: 12,
                  child: Text(
                    'SALÓN',
                    style: TextStyle(
                      color: Colors.white38,
                      letterSpacing: 4,
                      fontSize: 18,
                    ),
                  ),
                ),
                if (widget.mesas.isEmpty)
                  const Center(child: Text('Todavía no hay mesas')),

                for (final m in widget.mesas)
                  Positioned(
                    key: ValueKey(m.id),
                    left: m.x,
                    top: m.y,
                    width: m.ancho,
                    height: m.alto,
                    child: Semantics(
                      button: true,
                      label: '${m.nombre}, ${m.sillas} sillas',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.alTocar(m),
                        onPanStart: widget.alMover == null ? null : (e) {
                          inicioPuntero = e.globalPosition;
                          inicioMesa = Offset(m.x, m.y);
                          widget.alTocar(m);
                        },
                        onPanUpdate: widget.alMover == null ? null : (e) {
                          final nueva = inicioMesa +
                              (e.globalPosition - inicioPuntero) / escala;

                          widget.alMover!(m, Offset(
                            nueva.dx
                                .clamp(0, anchoPlano - m.ancho)
                                .toDouble(),
                            nueva.dy
                                .clamp(0, altoPlano - m.alto)
                                .toDouble(),
                          ));
                        },
                        child: CustomPaint(
                          painter: MesaPainter(
                            m,
                            widget.seleccion == m.id
                                ? Colors.white
                                : (widget.alMover == null &&
                                datos.conPedido(m.id)
                                ? verde
                                : dorado),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: m.ancho - 54,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    m.nombre,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '${m.sillas} sillas',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ));
      },
    ),
  );
}

class MesaPainter extends CustomPainter {
  final Mesa mesa;
  final Color color;
  MesaPainter(this.mesa, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final centro = Offset(size.width / 2, size.height / 2);
    final borde = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final fondo = Paint()..color = const Color(0xFF3B3030);
    final cuerpo = Rect.fromLTWH(
      22, 22, size.width - 44, size.height - 44,
    );

    for (var i = 0; i < mesa.sillas; i++) {
      final angulo = 2 * math.pi * i / mesa.sillas - math.pi / 2;
      final dx = math.cos(angulo), dy = math.sin(angulo);
      final rx = cuerpo.width / 2 + 10;
      final ry = cuerpo.height / 2 + 10;

      final r = mesa.forma == 'Redonda'
          ? rx
          : math.min(
        rx / math.max(dx.abs(), 0.001),
        ry / math.max(dy.abs(), 0.001),
      );

      canvas.save();
      canvas.translate(centro.dx + dx * r, centro.dy + dy * r);
      canvas.rotate(angulo + math.pi / 2);

      final silla = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-8, -8, 16, 16),
        const Radius.circular(5),
      );
      canvas.drawRRect(silla, fondo);
      canvas.drawRRect(silla, borde);
      canvas.restore();
    }

    if (mesa.forma == 'Redonda') {
      canvas.drawOval(cuerpo, fondo);
      canvas.drawOval(cuerpo, borde);
    } else {
      final rect = RRect.fromRectAndRadius(
        cuerpo,
        const Radius.circular(12),
      );
      canvas.drawRRect(rect, fondo);
      canvas.drawRRect(rect, borde);
    }
  }

  @override
  bool shouldRepaint(covariant MesaPainter oldDelegate) => true;
}

class MesasPage extends StatelessWidget {
  const MesasPage({super.key});

  @override
  Widget build(BuildContext context) => Marco(
    titulo: 'Mesero · Elegir mesa',
    acciones: [
      IconButton(
        tooltip: 'Ver pedidos',
        icon: const Icon(Icons.receipt_long, color: dorado),
        onPressed: () => abrir(
          context,
          const PedidosPage(cocina: false),
        ),
      ),
    ],
    child: ListenableBuilder(
      listenable: datos,
      builder: (context, _) => Column(children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Tocá la mesa para tomar el pedido',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const Text(
          'Dorado: sin pedidos activos · Verde: con pedidos activos',
          textAlign: TextAlign.center,
        ),
        Expanded(
          child: MapaMesas(
            mesas: datos.mesas,
            alTocar: (m) => abrir(context, TomarPedidoPage(mesa: m)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => abrir(
              context,
              const PedidosPage(cocina: false),
            ),
            icon: const Icon(Icons.receipt_long),
            label: const Text('Ver pedidos y cambiar estado'),
          ),
        ),
      ]),
    ),
  );
}

class TomarPedidoPage extends StatefulWidget {
  final Mesa mesa;
  const TomarPedidoPage({super.key, required this.mesa});

  @override
  State<TomarPedidoPage> createState() => _TomarPedidoPageState();
}

class _TomarPedidoPageState extends State<TomarPedidoPage> {
  final cantidades = <String, int>{};
  final notas = TextEditingController();
  String busqueda = '';
  bool enviando = false;

  int get unidades => cantidades.values.fold(0, (suma, n) => suma + n);

  void cambiar(Producto p, int delta) {
    setState(() {
      final n = (cantidades[p.id] ?? 0) + delta;
      if (n <= 0) {
        cantidades.remove(p.id);
      } else {
        cantidades[p.id] = n;
      }
    });
  }

  Future<void> enviar() async {
    if (enviando || cantidades.isEmpty) return;
    setState(() => enviando = true);

    final ok = await confirmar(
      context,
      '¿Crear pedido de prueba?',
      '${widget.mesa.nombre} · $unidades unidades. '
          'Aparecerá en Cocina de ESTA app, no en otro dispositivo.',
    );

    if (!mounted) return;

    if (ok) {
      final lineas = datos.productos
          .where((p) => cantidades.containsKey(p.id))
          .map((p) => LineaPedido(p.nombre, cantidades[p.id]!))
          .toList();

      final pedido = datos.agregarPedido(
        widget.mesa,
        lineas,
        notas.text.trim(),
      );

      cantidades.clear();
      notas.clear();

      aviso(
        context,
        'Pedido de prueba #${pedido.numero} creado. Podés verlo en Cocina.',
      );
    }

    setState(() => enviando = false);
  }

  @override
  void dispose() {
    notas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConfirmarSalida(
    cambios: cantidades.isNotEmpty || notas.text.trim().isNotEmpty,
    child: Marco(
      titulo: 'Tomar pedido · ${widget.mesa.nombre}',
      child: LayoutBuilder(
        builder: (context, limites) => limites.maxWidth >= 800
            ? Row(children: [
          Expanded(child: menu()),
          SizedBox(width: 340, child: carrito()),
        ])
            : DefaultTabController(
          length: 2,
          child: Column(children: [
            TabBar(tabs: [
              const Tab(text: 'MENÚ'),
              Tab(text: 'PEDIDO ($unidades)'),
            ]),
            Expanded(child: TabBarView(
              children: [menu(), carrito()],
            )),
          ]),
        ),
      ),
    ),
  );

  Widget menu() {
    final lista = datos.productos.where(
          (p) => p.disponible &&
          '${p.nombre} ${p.categoria}'
              .toLowerCase()
              .contains(busqueda.toLowerCase()),
    ).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Buscar plato, bebida o categoría',
          ),
          onChanged: (v) => setState(() => busqueda = v),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: lista.isEmpty
              ? const Center(child: Text('No hay productos disponibles'))
              : LayoutBuilder(
            builder: (context, limites) => GridView.builder(
              itemCount: lista.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: limites.maxWidth >= 550
                    ? 3
                    : (limites.maxWidth >= 350 ? 2 : 1),
                mainAxisExtent: 204,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, i) {
                final p = lista[i];
                final n = cantidades[p.id] ?? 0;

                return Card(child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(children: [
                    const Icon(
                      Icons.restaurant_menu,
                      color: dorado,
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: Center(child: Text(
                      p.nombre,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ))),
                    Text(
                      p.categoria,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Quitar uno',
                          onPressed: n == 0 || enviando
                              ? null
                              : () => cambiar(p, -1),
                          icon: const Icon(
                            Icons.remove_circle_outline,
                          ),
                        ),
                        Text(
                          '$n',
                          style: const TextStyle(fontSize: 20),
                        ),
                        IconButton(
                          tooltip: 'Agregar uno',
                          onPressed: enviando || n >= 99
                              ? null
                              : () => cambiar(p, 1),
                          icon: const Icon(
                            Icons.add_circle,
                            color: dorado,
                          ),
                        ),
                      ],
                    ),
                  ]),
                ));
              },
            ),
          ),
        ),
      ]),
    );
  }

  Widget carrito() => Container(
    color: const Color(0xFF202128),
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'PEDIDO · ${widget.mesa.nombre}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: dorado,
            fontSize: 22,
          ),
        ),
        const Divider(),

        if (cantidades.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('Agregá platos usando el botón + del menú.'),
          ),

        for (final p in datos.productos.where(
              (p) => cantidades.containsKey(p.id),
        ))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${cantidades[p.id]} × ${p.nombre}'),
            trailing: IconButton(
              tooltip: 'Quitar producto',
              icon: const Icon(Icons.close),
              onPressed: enviando
                  ? null
                  : () => setState(() => cantidades.remove(p.id)),
            ),
          ),

        const SizedBox(height: 16),
        TextField(
          controller: notas,
          enabled: !enviando,
          minLines: 2,
          maxLines: 4,
          maxLength: 250,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Notas para cocina',
            hintText: 'Ejemplo: arroz sin cebolla',
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '$unidades unidades · Sin precios',
          style: const TextStyle(color: dorado),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: cantidades.isEmpty || enviando ? null : enviar,
          icon: const Icon(Icons.send),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('ENVIAR A COCINA · PRUEBA'),
          ),
        ),
      ],
    ),
  );
}

class PedidosPage extends StatelessWidget {
  final bool cocina;
  const PedidosPage({super.key, required this.cocina});

  @override
  Widget build(BuildContext context) => Marco(
    titulo: cocina
        ? 'Cocina · Solo lectura'
        : 'Pedidos · Control desde tablet',

    child: ListenableBuilder(
      listenable: datos,
      builder: (context, _) {
        final lista = datos.pedidos
            .where((p) => p.estado != EstadoPedido.entregado)
            .toList();

        if (lista.isEmpty) {
          return const Center(child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Logotipo(lado: 130),
                SizedBox(height: 20),
                Icon(Icons.soup_kitchen, size: 55, color: dorado),
                SizedBox(height: 14),
                Text(
                  'Sin pedidos activos',
                  style: TextStyle(fontSize: 26),
                ),
                Text(
                  'Creá uno desde Mesero en esta misma app.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ));
        }

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              cocina
                  ? 'Pedidos de prueba por orden de llegada.'
                  : 'Como la cocina es solo una pantalla, cambiá el '
                  'estado aquí cuando te avisen.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, limites) {
                final columnas = limites.maxWidth >= 1050
                    ? 3
                    : (limites.maxWidth >= 660 ? 2 : 1);

                final ancho =
                    (limites.maxWidth - (columnas - 1) * 14) / columnas;

                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: lista.map((p) => SizedBox(
                    width: ancho,
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: coloresEstado[p.estado.index],
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${p.numero} · ${p.mesaNombre}',
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${p.hora.hour.toString().padLeft(2, "0")}:'
                                  '${p.hora.minute.toString().padLeft(2, "0")} '
                                  '· ${nombresEstado[p.estado.index]}',
                              style: TextStyle(
                                color: coloresEstado[p.estado.index],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Divider(),

                            for (final linea in p.lineas)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Text(
                                  '${linea.cantidad} × ${linea.nombre}',
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),

                            if (p.nota.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'NOTA: ${p.nota}',
                                  style: const TextStyle(
                                    color: dorado,
                                    fontSize: 19,
                                  ),
                                ),
                              ),

                            if (!cocina)
                              Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: FilledButton(
                                  onPressed: () async {
                                    final estadoAnterior = p.estado;
                                    final siguiente =
                                    nombresEstado[estadoAnterior.index + 1];

                                    final ok = await confirmar(
                                      context,
                                      'Pedido #${p.numero}',
                                      '¿Cambiar a $siguiente?'
                                          '${siguiente == "Entregado"
                                          ? " Se retirará de cocina."
                                          : ""}',
                                    );

                                    if (ok && context.mounted &&
                                        p.estado == estadoAnterior) {
                                      datos.avanzar(p);
                                    }
                                  },
                                  child: Text(
                                    'Marcar ${nombresEstado[p.estado.index + 1]}',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  )).toList(),
                );
              },
            ),
          ],
        );
      },
    ),
  );
}