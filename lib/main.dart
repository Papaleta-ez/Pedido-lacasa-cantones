import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

const negro = Color(0xFF101214);
const superficie = Color(0xFF1A1E22);
const dorado = Color(0xFFE6B75F);
const rojo = Color(0xFFB32636);
const verde = Color(0xFF67D5AD);
const amarillo = Color(0xFFFFD166);
const urgente = Color(0xFFFF6B75);
const logo = 'assets/images/logo_casa_cantones.png';
const unidadesPorMetro = 100.0;

const modoDispositivo = String.fromEnvironment(
  'MODO',
  defaultValue: 'mesero',
);

final datos = Datos();

String nuevoId() =>
    FirebaseFirestore.instance.collection('identificadores').doc().id;

// -----------------------------------------------------------------------------
// INICIO: MESERO / COCINA / DUEÑO
// -----------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // También podés reemplazar esta selección por una sola pantalla:
  // const MesasPage()
  // const PedidosPage(cocina: true)
  // const DuenoPage()

  final Widget home = modoDispositivo == 'cocina'
      ? const PedidosPage(cocina: true)
      : modoDispositivo == 'dueno'
      ? const DuenoPage()
      : const MesasPage();

  String? error;

  try {
    await Firebase.initializeApp();
    datos.esDueno = home is DuenoPage;
    await datos.cargar();
    datos.conectar();
  } catch (e) {
    error = 'No se pudo iniciar: $e\nTus datos no se han borrado.';
  }

  runApp(CasaCantonesApp(home: home, error: error));
}

// -----------------------------------------------------------------------------
// UTILIDADES
// -----------------------------------------------------------------------------

String normalizar(String texto) {
  var resultado = texto.trim().toLowerCase();

  const cambios = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
  };

  cambios.forEach((a, b) {
    resultado = resultado.replaceAll(a, b);
  });

  return resultado.replaceAll(RegExp(r'\s+'), ' ');
}

bool categoriaBebida(String nombre) {
  return const {
    'bebida',
    'bebidas',
    'gaseosas',
    'refrescos',
    'jugos',
    'cervezas',
    'licores',
    'cocteles',
  }.contains(normalizar(nombre));
}

const ordenCategorias = [
  'Entradas',
  'Sopas',
  'Pollo',
  'Pato',
  'Res',
  'Cerdo',
  'Mariscos',
  'Tofu y vegetales',
  'Arroz y fideos',
  'Combos',
];

List<String> categoriasDe(Iterable<Producto> productos) {
  final lista = productos.map((p) => p.categoria).toSet().toList();

  lista.sort((a, b) {
    final ia = ordenCategorias.indexOf(a);
    final ib = ordenCategorias.indexOf(b);

    final orden = (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);

    return orden == 0 ? a.compareTo(b) : orden;
  });

  return lista;
}

IconData iconoCategoria(String categoria) {
  switch (categoria) {
    case 'Entradas':
      return Icons.restaurant_menu;
    case 'Sopas':
      return Icons.soup_kitchen;
    case 'Mariscos':
      return Icons.set_meal;
    case 'Tofu y vegetales':
      return Icons.eco;
    case 'Arroz y fideos':
      return Icons.ramen_dining;
    case 'Combos':
      return Icons.groups;
    default:
      return Icons.restaurant;
  }
}

Map<String, dynamic> mapa(dynamic valor) =>
    Map<String, dynamic>.from(valor as Map);

// -----------------------------------------------------------------------------
// MODELOS
// -----------------------------------------------------------------------------

class OpcionPlato {
  final String titulo;
  final List<String> alternativas;

  const OpcionPlato(this.titulo, this.alternativas);

  Map<String, dynamic> toJson() => {
    'titulo': titulo,
    'alternativas': alternativas,
  };

  factory OpcionPlato.fromJson(Map<String, dynamic> json) {
    return OpcionPlato(
      json['titulo'] as String,
      List<String>.from(json['alternativas'] as List),
    );
  }
}

class Producto {
  final String id;
  final String nombre;
  final String categoria;
  final String descripcion;
  final bool disponible;
  final List<OpcionPlato> opciones;

  const Producto(
      this.id,
      this.nombre,
      this.categoria,
      this.disponible, {
        this.descripcion = '',
        this.opciones = const [],
      });

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'categoria': categoria,
    'disponible': disponible,
    'descripcion': descripcion,
    'opciones': opciones.map((o) => o.toJson()).toList(),
  };

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      json['id'] as String,
      json['nombre'] as String,
      json['categoria'] as String,
      json['disponible'] as bool? ?? true,
      descripcion: json['descripcion'] as String? ?? '',
      opciones: (json['opciones'] as List? ?? [])
          .map((o) => OpcionPlato.fromJson(mapa(o)))
          .toList(),
    );
  }
}

class Zona {
  final String id;
  final String nombre;
  final double ancho;
  final double largo;

  const Zona(this.id, this.nombre, this.ancho, this.largo);

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'ancho': ancho,
    'largo': largo,
  };

  factory Zona.fromJson(Map<String, dynamic> json) {
    return Zona(
      json['id'] as String,
      json['nombre'] as String,
      (json['ancho'] as num).toDouble(),
      (json['largo'] as num).toDouble(),
    );
  }
}

class Mesa {
  final String id;
  final String nombre;
  final String zonaId;
  final double lado;

  double x;
  double y;

  Mesa(
      this.id,
      this.nombre,
      this.zonaId,
      this.lado,
      this.x,
      this.y,
      );

  double get ancho => lado;
  double get largo => lado;

  Rect get rect => Rect.fromLTWH(x, y, lado, lado);

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'zonaId': zonaId,
    'lado': lado,
    'x': x,
    'y': y,
  };

  factory Mesa.fromJson(Map<String, dynamic> json) {
    // Las mesas antiguas se convierten usando la medida menor.
    final lado = (json['lado'] as num?)?.toDouble() ??
        math.min(
          (json['ancho'] as num?)?.toDouble() ?? 1.3,
          (json['largo'] as num?)?.toDouble() ?? 1.3,
        );

    return Mesa(
      json['id'] as String,
      json['nombre'] as String,
      json['zonaId'] as String? ?? 'salon',
      lado,
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }

  Mesa copia() => Mesa.fromJson(toJson());
}

Offset limitarPosicion(Mesa mesa, Zona zona, Offset posicion) {
  return Offset(
    posicion.dx
        .clamp(0.0, math.max(0.0, zona.ancho - mesa.lado))
        .toDouble(),
    posicion.dy
        .clamp(0.0, math.max(0.0, zona.largo - mesa.lado))
        .toDouble(),
  );
}

bool chocan(Mesa a, Mesa b) {
  return a.id != b.id &&
      a.zonaId == b.zonaId &&
      a.rect.deflate(0.001).overlaps(b.rect.deflate(0.001));
}

Offset? lugarLibre(Mesa mesa, Zona zona, List<Mesa> mesas) {
  for (var y = 0.0; y <= zona.largo - mesa.lado; y += 0.25) {
    for (var x = 0.0; x <= zona.ancho - mesa.lado; x += 0.25) {
      final rect = Rect.fromLTWH(x, y, mesa.lado, mesa.lado)
          .deflate(0.001);

      final ocupado = mesas.any(
            (otra) =>
        otra.id != mesa.id &&
            otra.zonaId == zona.id &&
            rect.overlaps(otra.rect),
      );

      if (!ocupado) return Offset(x, y);
    }
  }

  return null;
}

class LineaPedido {
  final String productoId;
  final String nombre;
  final String detalle;
  final int cantidad;

  const LineaPedido(
      this.productoId,
      this.nombre,
      this.cantidad,
      this.detalle,
      );

  LineaPedido conCantidad(int numero) =>
      LineaPedido(productoId, nombre, numero, detalle);

  Map<String, dynamic> toJson() => {
    'productoId': productoId,
    'nombre': nombre,
    'cantidad': cantidad,
    'detalle': detalle,
  };

  factory LineaPedido.fromJson(Map<String, dynamic> json) {
    return LineaPedido(
      json['productoId'] as String? ?? '',
      json['nombre'] as String? ?? 'Comida',
      (json['cantidad'] as num?)?.toInt() ?? 1,
      json['detalle'] as String? ?? '',
    );
  }
}

const estados = [
  'pendiente',
  'preparando',
  'listo',
  'entregado',
];

String nombreEstado(String estado) {
  return const {
    'pendiente': 'Pendiente',
    'preparando': 'Preparando',
    'listo': 'Listo',
    'entregado': 'Entregado',
  }[estado] ??
      estado;
}

class Pedido {
  final String id;
  final String numero;
  final String mesaId;
  final String mesaNombre;
  final String zonaNombre;
  final String nota;
  final String estado;
  final DateTime? hora;
  final List<LineaPedido> lineas;

  Pedido(this.id, Map<String, dynamic> json)
      : numero =
  '${json['numero'] ?? id.substring(0, math.min(6, id.length))}',
        mesaId = json['mesaId'] as String? ?? '',
        mesaNombre = json['mesaNombre'] as String? ?? '',
        zonaNombre = json['zonaNombre'] as String? ?? '',
        nota = json['nota'] as String? ?? '',
        estado = json['estado'] as String? ?? 'pendiente',
        hora = json['hora'] is Timestamp
            ? (json['hora'] as Timestamp).toDate()
            : null,
        lineas = (json['lineas'] as List? ?? [])
            .map((l) => LineaPedido.fromJson(mapa(l)))
            .toList();
}

// -----------------------------------------------------------------------------
// FIREBASE, CONFIGURACIÓN Y ENVÍO SIN DUPLICADOS
// -----------------------------------------------------------------------------

class Datos extends ChangeNotifier {
  final _prefs = SharedPreferencesAsync();

  static const _clave = 'cantones_config_local_v1';
  static const _envio = 'cantones_envio_pendiente_v1';

  final _db = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _escuchaPedidos;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _escuchaConfig;

  List<Producto> productos = menuDeLasFotos();

  List<Zona> zonas = [
    const Zona('salon', 'Salón', 12, 8),
    const Zona('afuera', 'Afuera', 10, 6),
  ];

  List<Mesa> mesas = [
    Mesa('m1', 'Mesa 1', 'salon', 1.3, 1, 1),
    Mesa('m2', 'Mesa 2', 'salon', 1.3, 4.5, 1),
    Mesa('m3', 'Mesa 3', 'salon', 1.3, 8, 1),
    Mesa('m4', 'Mesa 4', 'salon', 1.3, 1, 4.5),
    Mesa('m5', 'Mesa 5', 'salon', 1.3, 4.5, 4.5),
    Mesa('m6', 'Mesa 6', 'salon', 1.3, 8, 4.5),
  ];

  List<Pedido> pedidos = [];
  Map<String, dynamic>? envioPendiente;

  bool esDueno = false;
  bool enviando = false;
  bool cargandoPedidos = true;
  bool desdeCache = true;
  bool configConfirmada = false;
  bool publicada = false;

  int revision = 0;

  String? errorPedidos;
  String? errorConfig;
  String? avisoLocal;

  DocumentReference<Map<String, dynamic>> get _config =>
      _db.collection('configuracion').doc('restaurante');

  Future<void> cargar() async {
    final texto = await _prefs.getString(_clave);

    if (texto != null) {
      final json = mapa(jsonDecode(texto));

      if (json['version'] != 3 &&
          await _prefs.getString('${_clave}_respaldo_cuadradas') ==
              null) {
        await _prefs.setString(
          '${_clave}_respaldo_cuadradas',
          texto,
        );
      }

      _aplicar(json);
    }

    final pendiente = await _prefs.getString(_envio);

    if (pendiente != null) {
      envioPendiente = mapa(jsonDecode(pendiente));
    }
  }

  void _aplicar(Map<String, dynamic> json) {
    final menu = (json['productos'] as List)
        .map((p) => Producto.fromJson(mapa(p)))
        .where((p) => !categoriaBebida(p.categoria))
        .toList();

    if (json['menuFotos'] != 1) {
      for (final producto in menuDeLasFotos()) {
        final existe = menu.any(
              (p) =>
          p.id == producto.id ||
              normalizar(p.nombre) == normalizar(producto.nombre),
        );

        if (!existe) menu.add(producto);
      }
    }

    final areas = (json['zonas'] as List?)
        ?.map((z) => Zona.fromJson(mapa(z)))
        .toList() ??
        [...zonas];

    final plano = (json['mesas'] as List).map((valor) {
      final mesa = Mesa.fromJson(mapa(valor));

      if (json['zonas'] == null) {
        mesa.x *= 12 / 1000;
        mesa.y *= 8 / 620;
      }

      return mesa;
    }).toList();

    if (areas.isEmpty ||
        areas.any(
              (z) =>
          !z.ancho.isFinite ||
              !z.largo.isFinite ||
              z.ancho < 3 ||
              z.largo < 3,
        )) {
      throw const FormatException('Medidas de zona inválidas');
    }

    for (final mesa in plano) {
      final zona = areas.firstWhere((z) => z.id == mesa.zonaId);

      if (!mesa.lado.isFinite ||
          mesa.lado < 0.5 ||
          mesa.lado > math.min(zona.ancho, zona.largo) ||
          !mesa.x.isFinite ||
          !mesa.y.isFinite) {
        throw const FormatException('Mesa inválida');
      }

      final posicion = limitarPosicion(
        mesa,
        zona,
        Offset(mesa.x, mesa.y),
      );

      mesa.x = posicion.dx;
      mesa.y = posicion.dy;
    }

    productos = menu;
    zonas = areas;
    mesas = plano;
  }

  void conectar() {
    _escuchaPedidos = _db
        .collection('pedidos')
        .where(
      'estado',
      whereIn: ['pendiente', 'preparando', 'listo'],
    )
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
        try {
          pedidos = snapshot.docs
              .map((documento) => Pedido(
            documento.id,
            documento.data(),
          ))
              .toList()
            ..sort(
                  (a, b) => (a.hora ?? DateTime(2100))
                  .compareTo(b.hora ?? DateTime(2100)),
            );

          desdeCache = snapshot.metadata.isFromCache;
          cargandoPedidos = false;
          errorPedidos = null;
        } catch (e) {
          errorPedidos = 'Revisá los datos de pedidos: $e';
        }

        notifyListeners();
      },
      onError: (Object error) {
        cargandoPedidos = false;
        errorPedidos = 'No se pudieron leer los pedidos: $error';
        notifyListeners();
      },
    );

    _escuchaConfig =
        _config.snapshots(includeMetadataChanges: true).listen(
              (snapshot) {
            try {
              if (!snapshot.metadata.isFromCache) {
                configConfirmada = true;
              }

              publicada = snapshot.exists;

              if (snapshot.exists) {
                final recibida =
                    (snapshot.data()!['revision'] as num?)?.toInt() ?? 0;

                if (recibida >= revision) {
                  _aplicar(snapshot.data()!);
                  revision = recibida;
                }
              }

              errorConfig = null;
            } catch (e) {
              errorConfig =
              'No se pudo cargar el menú/plano compartido: $e';
            }

            notifyListeners();
          },
          onError: (Object error) {
            errorConfig =
            'No se pudo leer la configuración: $error';
            notifyListeners();
          },
        );
  }

  Zona zonaDe(Mesa mesa) =>
      zonas.firstWhere((zona) => zona.id == mesa.zonaId);

  bool conPedido(String mesaId) =>
      pedidos.any((pedido) => pedido.mesaId == mesaId);

  Future<void> guardar({
    List<Producto>? menu,
    List<Mesa>? plano,
    List<Zona>? areas,
    int? revisionEsperada,
  }) async {
    if (!esDueno) {
      throw StateError(
        'Esta vista no permite editar la configuración',
      );
    }

    final esperado = revisionEsperada ?? revision;

    final json = <String, dynamic>{
      'version': 3,
      'menuFotos': 1,
      'productos':
      (menu ?? productos).map((p) => p.toJson()).toList(),
      'mesas': (plano ?? mesas).map((m) => m.toJson()).toList(),
      'zonas': (areas ?? zonas).map((z) => z.toJson()).toList(),
    };

    final nuevaRevision = await _db.runTransaction<int>(
          (transaccion) async {
        final actual = await transaccion.get(_config);
        final numero =
            (actual.data()?['revision'] as num?)?.toInt() ?? 0;

        if (numero != esperado) {
          throw StateError(
            'Otro equipo modificó la configuración. '
                'Volvé a abrir el editor.',
          );
        }

        transaccion.set(_config, {
          ...json,
          'revision': numero + 1,
          'actualizado': FieldValue.serverTimestamp(),
        });

        return numero + 1;
      },
    );

    if (nuevaRevision >= revision) {
      _aplicar(json);
      revision = nuevaRevision;
    }

    publicada = true;

    try {
      await _prefs.setString(_clave, jsonEncode(json));
    } catch (_) {
      avisoLocal =
      'Guardado en Firebase; no se pudo actualizar la copia local.';
    }

    notifyListeners();
  }

  Future<String> enviar(
      Mesa mesa,
      List<LineaPedido> lineas,
      String nota,
      ) async {
    if (enviando) {
      throw StateError('Ya hay un envío en curso');
    }

    enviando = true;
    notifyListeners();

    try {
      envioPendiente ??= {
        'id': _db.collection('pedidos').doc().id,
        'mesa': mesa.toJson(),
        'zonaNombre': zonaDe(mesa).nombre,
        'nota': nota,
        'lineas': lineas.map((linea) => linea.toJson()).toList(),
      };

      final pendiente = envioPendiente!;

      if ((pendiente['lineas'] as List).isEmpty) {
        throw StateError('El pedido está vacío');
      }

      // Guardar antes de enviar permite reutilizar el mismo ID.
      await _prefs.setString(
        _envio,
        jsonEncode(pendiente),
      );

      final referencia = _db
          .collection('pedidos')
          .doc(pendiente['id'] as String);

      final contador =
      _db.collection('contadores').doc('pedidos_v2');

      final numero = await _db.runTransaction<String>(
            (transaccion) async {
          final existente = await transaccion.get(referencia);

          // Si ya llegó al servidor, no crea otro ni modifica su estado.
          if (existente.exists) {
            return '${existente.data()!['numero']}';
          }

          final documentoContador =
          await transaccion.get(contador);

          final siguiente =
              ((documentoContador.data()?['ultimo'] as num?)
                  ?.toInt() ??
                  0) +
                  1;

          final folio =
              'CC-${siguiente.toString().padLeft(6, '0')}';

          final mesaGuardada = mapa(pendiente['mesa']);

          transaccion.set(contador, {'ultimo': siguiente});

          transaccion.set(referencia, {
            'numero': folio,
            'mesaId': mesaGuardada['id'],
            'mesaNombre': mesaGuardada['nombre'],
            'zonaId': mesaGuardada['zonaId'],
            'zonaNombre': pendiente['zonaNombre'],
            'nota': pendiente['nota'],
            'lineas': pendiente['lineas'],
            'estado': 'pendiente',
            'hora': FieldValue.serverTimestamp(),
          });

          return folio;
        },
        timeout: const Duration(seconds: 20),
        maxAttempts: 3,
      );

      envioPendiente = null;

      try {
        await _prefs.remove(_envio);
      } catch (_) {
        avisoLocal =
        'Pedido confirmado. La copia local pendiente '
            'se verificará al volver a abrir.';
      }

      return numero;
    } finally {
      enviando = false;
      notifyListeners();
    }
  }

  Future<void> avanzar(Pedido pedido) async {
    final referencia =
    _db.collection('pedidos').doc(pedido.id);

    await _db.runTransaction<void>(
          (transaccion) async {
        final documento = await transaccion.get(referencia);

        if (!documento.exists) {
          throw StateError('El pedido ya no existe');
        }

        final estado = documento.data()!['estado'] as String;

        // Evita saltar dos estados si dos equipos tocan a la vez.
        if (estado != pedido.estado) return;

        final indice = estados.indexOf(estado);

        if (indice < 0 || indice >= 3) return;

        transaccion.update(referencia, {
          'estado': estados[indice + 1],
          'actualizado': FieldValue.serverTimestamp(),
        });
      },
      timeout: const Duration(seconds: 20),
      maxAttempts: 3,
    );
  }

  @override
  void dispose() {
    _escuchaPedidos?.cancel();
    _escuchaConfig?.cancel();
    super.dispose();
  }
}

// -----------------------------------------------------------------------------
// MENÚ: SIN PRECIOS NI BEBIDAS
// -----------------------------------------------------------------------------

List<Producto> menuDeLasFotos() {
  const secciones = <String, List<String>>{
    'Entradas': [
      'Cerdo rostizado',
      'Tacos chinos',
      'Wantan frito',
      'Calamar en salsa de soya',
      'Wantons al vapor con salsa de soya',
    ],
    'Sopas': [
      'Sopa de maíz con pollo',
      'Sopa agri-picante con tarro',
      'Sopa de buche de pescado',
      'Sopa de mariscos',
      'Sopa de wantan',
      'Sopa de aleta de tiburón',
    ],
    'Pollo': [
      'Pollo al curry',
      'Pollo al estilo Kung Pao',
      'Pollo en salsa naranja',
      'Pollo agridulce con piña',
      'Pollo al vapor con cebollín y jengibre',
      'Pollo salteado con hongos chinos',
      'Pollo a la plancha con salsa de pimienta',
      'Pollo salteado con salsa judías',
      'Pollo a la plancha con vegetales',
    ],
    'Pato': [
      'Pato al estilo cantonés',
      'Pato asado al estilo Pekín',
    ],
    'Res': [
      'Carne de res salteada con vegetales',
      'Carne de res en salsa naranja',
      'Carne de res en salsa judía',
      'Carne de res en salsa de ostión',
      'Carne de res salteada con jalapeños',
      'Carne de res a la plancha al estilo Szechuan',
    ],
    'Cerdo': [
      'Cerdo agridulce',
      'Costilla de cerdo en salsa judía al vapor',
      'Costilla de cerdo frita con ajo',
      'Fajitas de cerdo salteadas con vegetales',
      'Cerdo salteado con salsa judías',
    ],
    'Mariscos': [
      'Filete de pescado con vegetales',
      'Filete de pescado al vapor',
      'Pescado entero al vapor con jengibre',
      'Pescado entero en salsa de ostión',
      'Pescado frito con salsa picante',
      'Pescado entero frito con salsa agridulce',
      'Bolitas de pescado con vegetales',
      'Langosta a la plancha al estilo Szechuan',
      'Langosta con jengibre y cebollín',
      'Langosta en salsa judía',
      'Mariscada a la plancha',
      'Camarones salteados con semilla de marañón',
      'Camarones al estilo Kung Pao',
      'Camarones fritos al estilo chino',
      'Camarones medianos a la plancha al estilo Szechuan',
      'Camarones medianos con salsa agridulce',
      'Calamar en salsa judía',
      'Calamar frito al estilo chino',
      'Calamar a la plancha al estilo Szechuan',
    ],
    'Tofu y vegetales': [
      'Tofu al estilo mapo con carne de res molida',
      'Tofu crocante con salsa agridulce',
      'Lo han chai vegetales con tofu',
      'Tofu al vapor con filete de pescado',
      'Tofu frito en salsa de hongo y cerdo',
      'Vegetales con ajo',
      'Vegetales con salsa de ostión',
      'Vegetales con hongos chinos',
      'Brócoli salteado con ajo',
    ],
    'Arroz y fideos': [
      'Arroz al vapor con salsa de ostión',
      'Arroz frito al estilo cantonés',
      'Chow mein de la casa',
      'Chop suey de la casa',
      'Fideo de arroz al estilo Singapur',
    ],
  };

  final menu = <Producto>[];
  var indice = 1;

  for (final seccion in secciones.entries) {
    for (final nombre in seccion.value) {
      menu.add(
        Producto('carta_${indice++}', nombre, seccion.key, true),
      );
    }
  }

  const opcionesGrandes = [
    OpcionPlato('Pollo', ['Agridulce', 'Kung Pao']),
    OpcionPlato('Camarones', ['Agridulces', 'Al estilo chino']),
    OpcionPlato('Entrada', ['Tacos chinos', 'Domplis']),
  ];

  menu.addAll(const [
    Producto(
      'combo_deluxe',
      'Combo Deluxe · 10 personas',
      'Combos',
      true,
      descripcion:
      'Arroz chino, chop suey, sopa wantan, pollo, '
          'costilla de cerdo con ajo, carne con vegetales, '
          'cerdo en salsa judía, camarones y entrada.',
      opciones: opcionesGrandes,
    ),
    Producto(
      'combo_super',
      'Super Combo · 8 personas',
      'Combos',
      true,
      descripcion:
      'Arroz chino, chop suey, sopa wantan, '
          'carne con vegetales, pollo, camarones y entrada.',
      opciones: opcionesGrandes,
    ),
    Producto(
      'combo_familiar',
      'Combo Familiar · 6 personas',
      'Combos',
      true,
      descripcion:
      'Res con vegetales, arroz cantonés, chop suey, '
          'pollo agridulce y 6 wantan.',
      opciones: [
        OpcionPlato('Wantan', ['Fritos', 'Al vapor']),
      ],
    ),
  ]);

  return menu;
}

// -----------------------------------------------------------------------------
// TEMA Y COMPONENTES COMUNES
// -----------------------------------------------------------------------------

class CasaCantonesApp extends StatelessWidget {
  final Widget home;
  final String? error;

  const CasaCantonesApp({
    super.key,
    required this.home,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'La Casa Cantones',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: rojo,
          brightness: Brightness.dark,
        ).copyWith(
          primary: dorado,
          onPrimary: negro,
          secondary: verde,
          surface: superficie,
        ),
        scaffoldBackgroundColor: negro,
        appBarTheme: const AppBarThemeData(
          backgroundColor: negro,
          foregroundColor: Colors.white,
          toolbarHeight: 76,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: superficie,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: superficie,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(56, 56),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(52, 52),
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18),
          bodyMedium: TextStyle(fontSize: 16),
          titleLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      home: error == null
          ? home
          : Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(error!),
          ),
        ),
      ),
    );
  }
}

void abrir(BuildContext context, Widget pantalla) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => pantalla),
  );
}

void aviso(BuildContext context, String texto) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
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
  ) ??
      false;
}

class Logotipo extends StatelessWidget {
  final double lado;

  const Logotipo({super.key, this.lado = 48});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        logo,
        width: lado,
        height: lado,
        fit: BoxFit.contain,
        errorBuilder: (_, error, stack) {
          return Icon(
            Icons.restaurant,
            size: lado,
            color: dorado,
          );
        },
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Logotipo(),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                titulo,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        actions: acciones,
      ),
      body: SafeArea(
        child: Column(
          children: [
            ListenableBuilder(
              listenable: datos,
              builder: (context, _) {
                final mensaje = datos.errorPedidos ??
                    datos.errorConfig ??
                    datos.avisoLocal ??
                    (datos.desdeCache
                        ? 'Datos en caché · El envío necesita '
                        'confirmación de internet.'
                        : null);

                if (mensaje == null) {
                  return const SizedBox.shrink();
                }

                return Container(
                  width: double.infinity,
                  color: const Color(0xFF382C1D),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    mensaje,
                    style: const TextStyle(
                      color: amarillo,
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class ConfirmarSalida extends StatefulWidget {
  final bool cambios;
  final bool bloqueado;
  final Widget child;

  const ConfirmarSalida({
    super.key,
    required this.cambios,
    required this.child,
    this.bloqueado = false,
  });

  @override
  State<ConfirmarSalida> createState() =>
      _ConfirmarSalidaState();
}

class _ConfirmarSalidaState extends State<ConfirmarSalida> {
  bool salir = false;
  bool preguntando = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.bloqueado && (!widget.cambios || salir),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || preguntando || widget.bloqueado) return;

        preguntando = true;

        final aceptar = await confirmar(
          context,
          '¿Salir sin guardar?',
          'Se perderán los cambios que todavía no enviaste.',
        );

        if (!mounted) return;

        preguntando = false;

        if (!aceptar) return;

        setState(() => salir = true);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      },
      child: widget.child,
    );
  }
}

// -----------------------------------------------------------------------------
// DUEÑO
// -----------------------------------------------------------------------------

class DuenoPage extends StatefulWidget {
  const DuenoPage({super.key});

  @override
  State<DuenoPage> createState() => _DuenoPageState();
}

class _DuenoPageState extends State<DuenoPage> {
  bool guardando = false;

  @override
  Widget build(BuildContext context) {
    return Marco(
      titulo: 'Administración',
      child: ListenableBuilder(
        listenable: datos,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'LA CASA CANTONES',
                style: TextStyle(
                  color: dorado,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Menú y salón compartidos con las tablets.',
              ),
              const SizedBox(height: 24),
              if (!datos.publicada)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: FilledButton.icon(
                    onPressed: guardando || !datos.configConfirmada
                        ? null
                        : () async {
                      setState(() => guardando = true);

                      try {
                        await datos.guardar();

                        if (context.mounted) {
                          aviso(
                            context,
                            'Menú y plano publicados',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          aviso(context, '$e');
                        }
                      } finally {
                        if (mounted) {
                          setState(() => guardando = false);
                        }
                      }
                    },
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      guardando
                          ? 'Publicando…'
                          : 'Publicar menú y plano de este equipo',
                    ),
                  ),
                ),
              for (final opcion
              in <(String, String, IconData, Widget)>[
                (
                'Menú de comidas',
                'Platos, categorías, disponibilidad y combos',
                Icons.restaurant_menu,
                const ProductosPage(),
                ),
                (
                'Zonas y mesas',
                'Salón, exterior y mesas cuadradas',
                Icons.dashboard_customize,
                const EditorMapaPage(),
                ),
                (
                'Pedidos en vivo',
                'Supervisar cocina',
                Icons.receipt_long,
                const PedidosPage(
                  cocina: false,
                  soloLectura: true,
                ),
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(24),
                      leading: Icon(
                        opcion.$3,
                        color: dorado,
                        size: 36,
                      ),
                      title: Text(
                        opcion.$1,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(opcion.$2),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: guardando
                          ? null
                          : () => abrir(context, opcion.$4),
                    ),
                  ),
                ),
              const Text(
                'Las vistas separadas no sustituyen '
                    'los permisos de Firebase.',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// EDITOR DE PRODUCTOS
// -----------------------------------------------------------------------------

class ProductosPage extends StatefulWidget {
  const ProductosPage({super.key});

  @override
  State<ProductosPage> createState() => _ProductosPageState();
}

class _ProductosPageState extends State<ProductosPage> {
  bool guardando = false;
  String? categoria;
  String busqueda = '';

  Future<void> guardar(
      List<Producto> lista, {
        int? revisionBase,
      }) async {
    if (guardando) return;

    setState(() => guardando = true);

    try {
      await datos.guardar(
        menu: lista,
        revisionEsperada: revisionBase,
      );

      if (mounted) {
        if (!lista.any((p) => p.categoria == categoria)) {
          categoria = null;
        }

        aviso(context, 'Menú guardado');
      }
    } catch (e) {
      if (mounted) {
        aviso(context, 'No se pudo guardar: $e');
      }
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Future<void> editar([Producto? producto]) async {
    final revisionBase = datos.revision;

    final nuevo = await showDialog<Producto>(
      context: context,
      builder: (_) => FormularioProducto(
        producto: producto,
        categoriaInicial: categoria,
      ),
    );

    if (nuevo == null || !mounted) return;

    final lista = [...datos.productos];
    final indice = lista.indexWhere((p) => p.id == nuevo.id);

    if (indice < 0) {
      lista.add(nuevo);
    } else {
      lista[indice] = nuevo;
    }

    await guardar(lista, revisionBase: revisionBase);
  }

  @override
  Widget build(BuildContext context) {
    return Marco(
      titulo: 'Menú de cocina · Dueño',
      acciones: [
        IconButton(
          tooltip: 'Agregar plato',
          onPressed: guardando ? null : () => editar(),
          icon: const Icon(Icons.add_circle, color: dorado),
        ),
      ],
      child: ListenableBuilder(
        listenable: datos,
        builder: (context, _) {
          final lista = datos.productos.where((producto) {
            return (categoria == null ||
                producto.categoria == categoria) &&
                normalizar(
                  '${producto.nombre} ${producto.categoria}',
                ).contains(normalizar(busqueda));
          }).toList();

          return Column(
            children: [
              if (guardando) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  onChanged: (valor) {
                    setState(() => busqueda = valor);
                  },
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar comida',
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Todas'),
                        selected: categoria == null,
                        onSelected: (_) {
                          setState(() => categoria = null);
                        },
                      ),
                    ),
                    for (final nombre in categoriasDe(datos.productos))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(nombre),
                          selected: categoria == nombre,
                          onSelected: (_) {
                            setState(() => categoria = nombre);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: lista.isEmpty
                    ? const Center(
                  child: Text('No hay platos en esta selección'),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: lista.length,
                  itemBuilder: (context, indice) {
                    final producto = lista[indice];

                    return Card(
                      child: ListTile(
                        leading: Icon(
                          producto.disponible
                              ? iconoCategoria(producto.categoria)
                              : Icons.visibility_off,
                          color: dorado,
                        ),
                        title: Text(producto.nombre),
                        subtitle: Text(
                          '${producto.categoria} · '
                              '${producto.disponible ? "Disponible" : "Oculto"}',
                        ),
                        onTap: guardando
                            ? null
                            : () => editar(producto),
                        trailing: IconButton(
                          tooltip: 'Quitar plato',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: guardando
                              ? null
                              : () async {
                            final aceptar = await confirmar(
                              context,
                              '¿Quitar ${producto.nombre}?',
                              'Se quitará del menú. Los pedidos '
                                  'ya creados conservan su contenido.',
                            );

                            if (aceptar && mounted) {
                              await guardar(
                                datos.productos
                                    .where(
                                      (p) =>
                                  p.id != producto.id,
                                )
                                    .toList(),
                              );
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class EdicionOpcion {
  final TextEditingController titulo;
  final TextEditingController alternativas;

  EdicionOpcion([OpcionPlato? opcion])
      : titulo = TextEditingController(
    text: opcion?.titulo ?? '',
  ),
        alternativas = TextEditingController(
          text: opcion?.alternativas.join('\n') ?? '',
        );

  void dispose() {
    titulo.dispose();
    alternativas.dispose();
  }
}

class FormularioProducto extends StatefulWidget {
  final Producto? producto;
  final String? categoriaInicial;

  const FormularioProducto({
    super.key,
    this.producto,
    this.categoriaInicial,
  });

  @override
  State<FormularioProducto> createState() =>
      _FormularioProductoState();
}

class _FormularioProductoState extends State<FormularioProducto> {
  final form = GlobalKey<FormState>();

  late final nombre = TextEditingController(
    text: widget.producto?.nombre ?? '',
  );

  late final categoria = TextEditingController(
    text: widget.producto?.categoria ??
        widget.categoriaInicial ??
        'Entradas',
  );

  late final descripcion = TextEditingController(
    text: widget.producto?.descripcion ?? '',
  );

  late bool disponible = widget.producto?.disponible ?? true;

  late final opciones = (widget.producto?.opciones ?? [])
      .map((o) => EdicionOpcion(o))
      .toList();

  final retiradas = <EdicionOpcion>[];

  String? errorOpciones;

  @override
  void dispose() {
    nombre.dispose();
    categoria.dispose();
    descripcion.dispose();

    for (final opcion in [...opciones, ...retiradas]) {
      opcion.dispose();
    }

    super.dispose();
  }

  void guardar() {
    if (!form.currentState!.validate()) return;

    final nuevasOpciones = <OpcionPlato>[];

    for (final opcion in opciones) {
      final alternativas = opcion.alternativas.text
          .split('\n')
          .map((texto) => texto.trim())
          .where((texto) => texto.isNotEmpty)
          .toList();

      if (opcion.titulo.text.trim().isEmpty ||
          alternativas.length < 2 ||
          alternativas.length > 8 ||
          alternativas.map(normalizar).toSet().length !=
              alternativas.length ||
          nuevasOpciones.any(
                (o) =>
            normalizar(o.titulo) ==
                normalizar(opcion.titulo.text),
          )) {
        setState(() {
          errorOpciones =
          'Cada opción necesita un título distinto y '
              'de 2 a 8 alternativas sin repetir.';
        });
        return;
      }

      nuevasOpciones.add(
        OpcionPlato(
          opcion.titulo.text.trim(),
          alternativas,
        ),
      );
    }

    var categoriaFinal = categoria.text.trim();

    for (final actual in categoriasDe(datos.productos)) {
      if (normalizar(actual) == normalizar(categoriaFinal)) {
        categoriaFinal = actual;
        break;
      }
    }

    Navigator.pop(
      context,
      Producto(
        widget.producto?.id ?? nuevoId(),
        nombre.text.trim(),
        categoriaFinal,
        disponible,
        descripcion: descripcion.text.trim(),
        opciones: nuevasOpciones,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.producto == null ? 'Nuevo plato' : 'Editar plato',
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: nombre,
                  maxLength: 90,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la comida',
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Escribí el nombre';
                    }

                    if (datos.productos.any(
                          (p) =>
                      p.id != widget.producto?.id &&
                          normalizar(p.nombre) == normalizar(valor),
                    )) {
                      return 'Ese plato ya existe';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: categoria,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    hintText: 'Pollo, Entradas, Sopas...',
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Escribí la categoría';
                    }

                    if (categoriaBebida(valor)) {
                      return 'Este menú es para comidas de cocina';
                    }

                    return null;
                  },
                ),
                Wrap(
                  spacing: 6,
                  children: categoriasDe(datos.productos).map((c) {
                    return ActionChip(
                      label: Text(c),
                      onPressed: () {
                        setState(() => categoria.text = c);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descripcion,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText:
                    'Descripción o contenido del combo (opcional)',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Disponible para pedir'),
                  value: disponible,
                  onChanged: (valor) {
                    setState(() => disponible = valor);
                  },
                ),
                const Divider(),
                const Text(
                  'Opciones que elegirá el mesero',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: dorado,
                  ),
                ),
                const Text(
                  'Ejemplo: tipo de pollo → agridulce o Kung Pao.',
                ),
                for (final opcion in opciones)
                  Card(
                    key: ObjectKey(opcion),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: opcion.titulo,
                                  maxLength: 40,
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre de la opción',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Quitar opción',
                                onPressed: () {
                                  setState(() {
                                    opciones.remove(opcion);
                                    retiradas.add(opcion);
                                  });
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          TextField(
                            controller: opcion.alternativas,
                            maxLength: 500,
                            minLines: 2,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              labelText: 'Una alternativa por renglón',
                              hintText: 'Agridulce\nKung Pao',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (errorOpciones != null)
                  Text(
                    errorOpciones!,
                    style: const TextStyle(color: urgente),
                  ),
                TextButton.icon(
                  onPressed: opciones.length >= 6
                      ? null
                      : () {
                    setState(() {
                      opciones.add(EdicionOpcion());
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar opción'),
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
          onPressed: guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// ZONAS Y EDITOR DEL PLANO
// -----------------------------------------------------------------------------

class SelectorZonas extends StatelessWidget {
  final List<Zona> zonas;
  final List<Mesa> mesas;
  final String seleccion;
  final ValueChanged<String> alElegir;

  const SelectorZonas({
    super.key,
    required this.zonas,
    required this.mesas,
    required this.seleccion,
    required this.alElegir,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      child: Row(
        children: [
          for (final zona in zonas)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ChoiceChip(
                avatar: Icon(
                  normalizar(zona.nombre).contains('afuera')
                      ? Icons.deck
                      : Icons.meeting_room,
                  size: 20,
                ),
                label: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '${zona.nombre} · '
                        '${mesas.where((m) => m.zonaId == zona.id).length} mesas',
                  ),
                ),
                selected: seleccion == zona.id,
                onSelected: (_) => alElegir(zona.id),
              ),
            ),
        ],
      ),
    );
  }
}

class EditorMapaPage extends StatefulWidget {
  const EditorMapaPage({super.key});

  @override
  State<EditorMapaPage> createState() => _EditorMapaPageState();
}

class _EditorMapaPageState extends State<EditorMapaPage> {
  int revisionEdicion = 0;

  late final List<Mesa> mesas =
  datos.mesas.map((mesa) => mesa.copia()).toList();

  late final List<Zona> zonas = [...datos.zonas];
  late String zonaId = zonas.first.id;

  String? seleccion;

  bool cambios = false;
  bool guardando = false;
  bool mover = true;

  @override
  void initState() {
    super.initState();
    revisionEdicion = datos.revision;
  }

  Zona get zona => zonas.firstWhere((z) => z.id == zonaId);

  Mesa? get elegida {
    for (final mesa in mesas) {
      if (mesa.id == seleccion && mesa.zonaId == zonaId) {
        return mesa;
      }
    }

    return null;
  }

  Future<void> editarZona([Zona? anterior]) async {
    final nueva = await showDialog<Zona>(
      context: context,
      builder: (_) => FormularioZona(
        zona: anterior,
        zonas: zonas,
        mesas: mesas,
      ),
    );

    if (nueva == null || !mounted) return;

    setState(() {
      if (anterior == null) {
        zonas.add(nueva);
      } else {
        zonas[zonas.indexWhere((z) => z.id == nueva.id)] = nueva;

        for (final mesa
        in mesas.where((m) => m.zonaId == nueva.id)) {
          final dx = anterior.ancho - mesa.ancho;
          final dy = anterior.largo - mesa.largo;

          final posicion = limitarPosicion(
            mesa,
            nueva,
            Offset(
              dx > 0
                  ? mesa.x / dx * (nueva.ancho - mesa.ancho)
                  : 0,
              dy > 0
                  ? mesa.y / dy * (nueva.largo - mesa.largo)
                  : 0,
            ),
          );

          mesa.x = posicion.dx;
          mesa.y = posicion.dy;
        }
      }

      zonaId = nueva.id;
      seleccion = null;
      cambios = true;
    });
  }

  Future<void> quitarZona() async {
    if (zonas.length == 1) {
      aviso(context, 'Dejá al menos una zona');
      return;
    }

    if (mesas.any((m) => m.zonaId == zonaId)) {
      aviso(
        context,
        'Primero mové las mesas a otra zona o quitalas.',
      );
      return;
    }

    final id = zonaId;

    final aceptar = await confirmar(
      context,
      '¿Quitar ${zona.nombre}?',
      'Se quitará al guardar los cambios.',
    );

    if (!aceptar || !mounted) return;

    setState(() {
      zonas.removeWhere((z) => z.id == id);
      zonaId = zonas.first.id;
      seleccion = null;
      cambios = true;
    });
  }

  Future<void> editarMesa([Mesa? anterior]) async {
    if (anterior != null && datos.conPedido(anterior.id)) {
      aviso(
        context,
        'Terminá los pedidos de esta mesa antes de editarla.',
      );
      return;
    }

    final nueva = await showDialog<Mesa>(
      context: context,
      builder: (_) => FormularioMesa(
        mesa: anterior,
        mesas: mesas,
        zonas: zonas,
        zonaInicial: zonaId,
      ),
    );

    if (nueva == null || !mounted) return;

    setState(() {
      final indice = mesas.indexWhere((m) => m.id == nueva.id);

      if (indice < 0) {
        mesas.add(nueva);
      } else {
        mesas[indice] = nueva;
      }

      zonaId = nueva.zonaId;
      seleccion = nueva.id;
      cambios = true;
    });
  }

  Future<void> quitarMesa() async {
    final mesa = elegida;

    if (mesa == null) return;

    if (datos.conPedido(mesa.id)) {
      aviso(context, 'Esta mesa tiene pedidos pendientes');
      return;
    }

    final aceptar = await confirmar(
      context,
      '¿Quitar ${mesa.nombre}?',
      'Se quitará al guardar los cambios.',
    );

    if (!aceptar || !mounted) return;

    setState(() {
      mesas.removeWhere((m) => m.id == mesa.id);
      seleccion = null;
      cambios = true;
    });
  }

  Future<void> guardar() async {
    if (guardando) return;

    for (var i = 0; i < mesas.length; i++) {
      for (var j = i + 1; j < mesas.length; j++) {
        if (chocan(mesas[i], mesas[j])) {
          setState(() {
            zonaId = mesas[i].zonaId;
            seleccion = mesas[i].id;
          });

          aviso(
            context,
            'Separá ${mesas[i].nombre} y ${mesas[j].nombre}: '
                'están superpuestas.',
          );

          return;
        }
      }
    }

    setState(() => guardando = true);

    try {
      await datos.guardar(
        plano: mesas.map((m) => m.copia()).toList(),
        areas: [...zonas],
        revisionEsperada: revisionEdicion,
      );

      revisionEdicion = datos.revision;

      if (mounted) {
        setState(() => cambios = false);
        aviso(context, 'Zonas y mesas guardadas');
      }
    } catch (e) {
      if (mounted) {
        aviso(context, 'No se pudo guardar: $e');
      }
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmarSalida(
      cambios: cambios,
      bloqueado: guardando,
      child: Marco(
        titulo: 'Zonas y mesas · Dueño',
        child: AbsorbPointer(
          absorbing: guardando,
          child: Column(
            children: [
              SelectorZonas(
                zonas: zonas,
                mesas: mesas,
                seleccion: zonaId,
                alElegir: (id) {
                  setState(() {
                    zonaId = id;
                    seleccion = null;
                  });
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${zona.nombre} · ${zona.ancho} m de ancho '
                          '× ${zona.largo} m de largo',
                      style: const TextStyle(
                        color: dorado,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => editarZona(zona),
                      icon: const Icon(Icons.straighten),
                      label: const Text('Medidas y nombre'),
                    ),
                    TextButton.icon(
                      onPressed: () => editarZona(),
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva zona'),
                    ),
                    IconButton(
                      tooltip: 'Quitar zona vacía',
                      onPressed: quitarZona,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => editarMesa(),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar mesa'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                      elegida == null ? null : () => editarMesa(elegida),
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar mesa'),
                    ),
                    OutlinedButton.icon(
                      onPressed: elegida == null ? null : quitarMesa,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Quitar mesa'),
                    ),
                    FilledButton.icon(
                      onPressed: !cambios || guardando ? null : guardar,
                      icon: const Icon(Icons.save),
                      label: Text(
                        guardando ? 'Guardando...' : 'Guardar cambios',
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Mover mesas'),
                    selected: mover,
                    onSelected: (_) => setState(() => mover = true),
                  ),
                  ChoiceChip(
                    label: const Text('Acercar plano'),
                    selected: !mover,
                    onSelected: (_) => setState(() => mover = false),
                  ),
                  Text(
                    cambios ? 'Cambios sin guardar' : 'Guardado',
                    style: TextStyle(
                      color: cambios ? dorado : verde,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: MapaMesas(
                  key: ValueKey(
                    '${zona.id}_${zona.ancho}_${zona.largo}',
                  ),
                  zona: zona,
                  mesas: mesas
                      .where((mesa) => mesa.zonaId == zonaId)
                      .toList(),
                  seleccion: seleccion,
                  mostrarPedidos: false,
                  alTocar: (mesa) {
                    setState(() => seleccion = mesa.id);
                  },
                  alMover: mover
                      ? (mesa, posicion) {
                    setState(() {
                      mesa.x = posicion.dx;
                      mesa.y = posicion.dy;
                      seleccion = mesa.id;
                      cambios = true;
                    });
                  }
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  mover
                      ? 'Arrastrá una mesa. Tocá Editar mesa '
                      'para cambiar lado o zona.'
                      : 'Pellizcá para acercar y arrastrá el fondo '
                      'para recorrer el plano.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double? leerMedida(String? texto) {
  final numero = double.tryParse(
    (texto ?? '').trim().replaceAll(',', '.'),
  );

  return numero != null && numero.isFinite ? numero : null;
}

Widget campoMedida(
    TextEditingController controller,
    String nombre,
    double min,
    double max,
    ) {
  return TextFormField(
    controller: controller,
    maxLength: 6,
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
    ),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    ],
    decoration: InputDecoration(
      labelText: nombre,
      suffixText: 'm',
    ),
    validator: (valor) {
      final numero = leerMedida(valor);

      return numero == null || numero < min || numero > max
          ? 'Entre $min y $max metros'
          : null;
    },
  );
}

class FormularioZona extends StatefulWidget {
  final Zona? zona;
  final List<Zona> zonas;
  final List<Mesa> mesas;

  const FormularioZona({
    super.key,
    this.zona,
    required this.zonas,
    required this.mesas,
  });

  @override
  State<FormularioZona> createState() => _FormularioZonaState();
}

class _FormularioZonaState extends State<FormularioZona> {
  final form = GlobalKey<FormState>();

  late final nombre = TextEditingController(
    text: widget.zona?.nombre ?? '',
  );

  late final ancho = TextEditingController(
    text: '${widget.zona?.ancho ?? 12}',
  );

  late final largo = TextEditingController(
    text: '${widget.zona?.largo ?? 8}',
  );

  String? error;

  @override
  void dispose() {
    nombre.dispose();
    ancho.dispose();
    largo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.zona == null ? 'Nueva zona' : 'Editar zona',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nombre,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    hintText: 'Salón, Afuera, Terraza...',
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Escribí un nombre';
                    }

                    return widget.zonas.any(
                          (z) =>
                      z.id != widget.zona?.id &&
                          normalizar(z.nombre) == normalizar(valor),
                    )
                        ? 'Ya existe esa zona'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                campoMedida(ancho, 'Ancho (horizontal)', 3, 40),
                const SizedBox(height: 10),
                campoMedida(largo, 'Largo (vertical)', 3, 40),
                const Text(
                  'Usá medidas aproximadas del espacio. '
                      'Las mesas se acomodan dentro del nuevo borde.',
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error!,
                      style: const TextStyle(color: urgente),
                    ),
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

            final nuevoAncho = leerMedida(ancho.text)!;
            final nuevoLargo = leerMedida(largo.text)!;

            if (widget.mesas.any(
                  (m) =>
              m.zonaId == widget.zona?.id &&
                  (m.ancho > nuevoAncho || m.largo > nuevoLargo),
            )) {
              setState(() {
                error = 'Hay una mesa más grande que esas medidas. '
                    'Editá primero la mesa.';
              });
              return;
            }

            Navigator.pop(
              context,
              Zona(
                widget.zona?.id ?? nuevoId(),
                nombre.text.trim(),
                nuevoAncho,
                nuevoLargo,
              ),
            );
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// MESAS CUADRADAS: UNA ÚNICA MEDIDA
// -----------------------------------------------------------------------------

class FormularioMesa extends StatefulWidget {
  final Mesa? mesa;
  final List<Mesa> mesas;
  final List<Zona> zonas;
  final String zonaInicial;

  const FormularioMesa({
    super.key,
    this.mesa,
    required this.mesas,
    required this.zonas,
    required this.zonaInicial,
  });

  @override
  State<FormularioMesa> createState() => _FormularioMesaState();
}

class _FormularioMesaState extends State<FormularioMesa> {
  final form = GlobalKey<FormState>();

  late final nombre = TextEditingController(
    text: widget.mesa?.nombre ?? sugerirNombre(),
  );

  late final lado = TextEditingController(
    text: '${widget.mesa?.lado ?? 1.3}',
  );

  late String zonaId =
      widget.mesa?.zonaId ?? widget.zonaInicial;

  String? error;

  String sugerirNombre() {
    var numero = 1;

    while (widget.mesas.any(
          (mesa) => normalizar(mesa.nombre) == 'mesa $numero',
    )) {
      numero++;
    }

    return 'Mesa $numero';
  }

  @override
  void dispose() {
    nombre.dispose();
    lado.dispose();
    super.dispose();
  }

  void aplicar() {
    if (!form.currentState!.validate()) return;

    final zona = widget.zonas.firstWhere((z) => z.id == zonaId);

    final mesa = Mesa(
      widget.mesa?.id ?? nuevoId(),
      nombre.text.trim(),
      zonaId,
      leerMedida(lado.text)!,
      widget.mesa?.x ?? 0,
      widget.mesa?.y ?? 0,
    );

    if (mesa.lado > math.min(zona.ancho, zona.largo)) {
      setState(() => error = 'La mesa no cabe en esta zona.');
      return;
    }

    final anterior = limitarPosicion(
      mesa,
      zona,
      Offset(mesa.x, mesa.y),
    );

    mesa.x = anterior.dx;
    mesa.y = anterior.dy;

    final conservar = widget.mesa != null &&
        widget.mesa!.zonaId == zonaId &&
        !widget.mesas.any((otra) => chocan(mesa, otra));

    final posicion =
    conservar ? anterior : lugarLibre(mesa, zona, widget.mesas);

    if (posicion == null) {
      setState(() {
        error = 'No hay espacio libre. Ampliá la zona o reducí el lado.';
      });
      return;
    }

    mesa.x = posicion.dx;
    mesa.y = posicion.dy;

    Navigator.pop(context, mesa);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.mesa == null ? 'Nueva mesa cuadrada' : 'Editar mesa',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nombre,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: 'Nombre o número',
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Escribí un nombre';
                    }

                    return widget.mesas.any(
                          (m) =>
                      m.id != widget.mesa?.id &&
                          normalizar(m.nombre) == normalizar(valor),
                    )
                        ? 'Ese nombre ya existe'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: zonaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Zona',
                  ),
                  items: widget.zonas.map((zona) {
                    return DropdownMenuItem(
                      value: zona.id,
                      child: Text(zona.nombre),
                    );
                  }).toList(),
                  onChanged: (valor) {
                    if (valor != null) {
                      setState(() => zonaId = valor);
                    }
                  },
                ),
                const SizedBox(height: 16),
                campoMedida(lado, 'Lado', 0.5, 5),
                const Text(
                  'Todas las mesas son cuadradas. '
                      'Sin sillas ni capacidad fija.',
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: urgente),
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
          onPressed: aplicar,
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// PLANO TÁCTIL
// -----------------------------------------------------------------------------

class MapaMesas extends StatefulWidget {
  final Zona zona;
  final List<Mesa> mesas;
  final String? seleccion;
  final bool mostrarPedidos;
  final ValueChanged<Mesa> alTocar;
  final void Function(Mesa, Offset)? alMover;

  const MapaMesas({
    super.key,
    required this.zona,
    required this.mesas,
    required this.alTocar,
    this.seleccion,
    this.alMover,
    this.mostrarPedidos = true,
  });

  @override
  State<MapaMesas> createState() => _MapaMesasState();
}

class _MapaMesasState extends State<MapaMesas> {
  final transformacion = TransformationController();

  Offset punteroInicial = Offset.zero;
  Offset mesaInicial = Offset.zero;

  @override
  void dispose() {
    transformacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, limites) {
          final menor = widget.mesas.isEmpty
              ? 1.3
              : widget.mesas.map((m) => m.lado).reduce(math.min);

          final ajuste = math.min(
            limites.maxWidth /
                (widget.zona.ancho * unidadesPorMetro),
            limites.maxHeight /
                (widget.zona.largo * unidadesPorMetro),
          );

          // Mantiene las mesas grandes al abrir el plano.
          final escala = math.max(
            ajuste,
            112 / (menor * unidadesPorMetro),
          );

          final unidad = unidadesPorMetro * escala;
          final ancho = widget.zona.ancho * unidad;
          final alto = widget.zona.largo * unidad;

          if (!escala.isFinite || limites.maxHeight <= 0) {
            return const SizedBox.shrink();
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    transformationController: transformacion,
                    constrained: false,
                    alignment: Alignment.topLeft,
                    minScale: 0.01,
                    maxScale: 4,
                    panEnabled: widget.alMover == null,
                    scaleEnabled: widget.alMover == null,
                    child: SizedBox(
                      width: ancho,
                      height: alto,
                      child: CustomPaint(
                        painter: PlanoPainter(paso: unidad),
                        child: Stack(
                          children: [
                            if (widget.mesas.isEmpty)
                              const Center(
                                child: Text('Zona sin mesas'),
                              ),
                            for (final mesa in widget.mesas)
                              Positioned(
                                key: ValueKey(mesa.id),
                                left: mesa.x * unidad,
                                top: mesa.y * unidad,
                                width: mesa.lado * unidad,
                                height: mesa.lado * unidad,
                                child: Semantics(
                                  button: true,
                                  label:
                                  '${mesa.nombre}, '
                                      '${datos.conPedido(mesa.id) ? "Con pedido" : "Libre"}',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => widget.alTocar(mesa),
                                    onPanStart: widget.alMover == null
                                        ? null
                                        : (evento) {
                                      punteroInicial =
                                          evento.globalPosition;
                                      mesaInicial =
                                          Offset(mesa.x, mesa.y);
                                      widget.alTocar(mesa);
                                    },
                                    onPanUpdate: widget.alMover == null
                                        ? null
                                        : (evento) {
                                      final factor = unidad *
                                          transformacion.value
                                              .getMaxScaleOnAxis();

                                      final posicion = mesaInicial +
                                          (evento.globalPosition -
                                              punteroInicial) /
                                              factor;

                                      widget.alMover!(
                                        mesa,
                                        limitarPosicion(
                                          mesa,
                                          widget.zona,
                                          posicion,
                                        ),
                                      );
                                    },
                                    child: tarjeta(mesa),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: superficie,
                    borderRadius: BorderRadius.circular(14),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Ver plano completo',
                          icon: const Icon(Icons.fit_screen),
                          onPressed: () {
                            final factor = math.min(
                              limites.maxWidth / ancho,
                              limites.maxHeight / alto,
                            );

                            transformacion.value =
                                Matrix4.diagonal3Values(
                                  factor,
                                  factor,
                                  1,
                                );
                          },
                        ),
                        IconButton(
                          tooltip: 'Mesas grandes',
                          icon: const Icon(Icons.zoom_in),
                          onPressed: () {
                            transformacion.value = Matrix4.identity();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget tarjeta(Mesa mesa) {
    final ocupada =
        widget.mostrarPedidos && datos.conPedido(mesa.id);

    final cruza = !widget.mostrarPedidos &&
        widget.mesas.any((otra) => chocan(mesa, otra));

    final color = cruza
        ? urgente
        : widget.seleccion == mesa.id
        ? Colors.white
        : ocupada
        ? verde
        : dorado;

    return Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2.5),
        color: ocupada
            ? const Color(0xFF19372F)
            : const Color(0xFF30281B),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mesa.nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              cruza
                  ? 'SUPERPUESTA'
                  : ocupada
                  ? 'CON PEDIDO'
                  : 'LIBRE',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlanoPainter extends CustomPainter {
  final double paso;

  const PlanoPainter({required this.paso});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFF171B1E),
    );

    final pintura = Paint()
      ..color = const Color(0xFF292E33)
      ..strokeWidth = 1;

    for (var x = 0.0; x < size.width; x += paso) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        pintura,
      );
    }

    for (var y = 0.0; y < size.height; y += paso) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        pintura,
      );
    }

    canvas.drawRect(
      rect.deflate(2),
      Paint()
        ..color = dorado
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant PlanoPainter oldDelegate) =>
      oldDelegate.paso != paso;
}

// -----------------------------------------------------------------------------
// MESERO: MESA → CATEGORÍAS → COMANDA
// -----------------------------------------------------------------------------

class MesasPage extends StatefulWidget {
  const MesasPage({super.key});

  @override
  State<MesasPage> createState() => _MesasPageState();
}

class _MesasPageState extends State<MesasPage> {
  String? zonaId;

  void tomar(Mesa mesa) {
    final pendiente = datos.envioPendiente;

    abrir(
      context,
      TomarPedidoPage(
        mesa: pendiente == null
            ? mesa
            : Mesa.fromJson(mapa(pendiente['mesa'])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Marco(
      titulo: 'La Casa Cantones · Mesas',
      acciones: [
        IconButton(
          tooltip: 'Pedidos en vivo',
          icon: const Icon(
            Icons.receipt_long,
            color: dorado,
          ),
          onPressed: () {
            abrir(context, const PedidosPage(cocina: false));
          },
        ),
      ],
      child: ListenableBuilder(
        listenable: datos,
        builder: (context, _) {
          final zona = datos.zonas.firstWhere(
                (z) => z.id == zonaId,
            orElse: () => datos.zonas.first,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Tocá una mesa',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${datos.pedidos.length} pedidos',
                      style: const TextStyle(color: verde),
                    ),
                  ],
                ),
              ),
              SelectorZonas(
                zonas: datos.zonas,
                mesas: datos.mesas,
                seleccion: zona.id,
                alElegir: (id) {
                  setState(() => zonaId = id);
                },
              ),
              if (datos.envioPendiente != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: FilledButton.icon(
                    onPressed: () {
                      tomar(
                        Mesa.fromJson(
                          mapa(datos.envioPendiente!['mesa']),
                        ),
                      );
                    },
                    icon: const Icon(Icons.sync_problem),
                    label: const Text(
                      'Recuperar envío sin confirmar',
                    ),
                  ),
                ),
              const Wrap(
                spacing: 24,
                children: [
                  Text(
                    '● Libre',
                    style: TextStyle(
                      color: dorado,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '● Con pedido',
                    style: TextStyle(
                      color: verde,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: MapaMesas(
                  key: ValueKey(
                    '${zona.id}_${zona.ancho}_${zona.largo}',
                  ),
                  zona: zona,
                  mesas: datos.mesas
                      .where((m) => m.zonaId == zona.id)
                      .toList(),
                  alTocar: tomar,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Deslizá el plano · Pellizcá para acercar',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class TomarPedidoPage extends StatefulWidget {
  final Mesa mesa;

  const TomarPedidoPage({
    super.key,
    required this.mesa,
  });

  @override
  State<TomarPedidoPage> createState() => _TomarPedidoPageState();
}

class _TomarPedidoPageState extends State<TomarPedidoPage> {
  final lineas = <LineaPedido>[];
  final notas = TextEditingController();
  final buscar = TextEditingController();

  String? categoria;
  Producto? configurando;

  final elecciones = <String, String>{};

  bool enviando = false;

  bool get fijo => enviando || datos.envioPendiente != null;

  int get unidades =>
      lineas.fold(0, (total, linea) => total + linea.cantidad);

  @override
  void initState() {
    super.initState();

    final pendiente = datos.envioPendiente;

    if (pendiente != null) {
      lineas.addAll(
        (pendiente['lineas'] as List)
            .map((l) => LineaPedido.fromJson(mapa(l))),
      );

      notas.text = pendiente['nota'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    notas.dispose();
    buscar.dispose();
    super.dispose();
  }

  void sumar(Producto producto, [String detalle = '']) {
    if (fijo) return;

    setState(() {
      final indice = lineas.indexWhere(
            (linea) =>
        linea.productoId == producto.id &&
            linea.detalle == detalle,
      );

      if (indice < 0) {
        lineas.add(
          LineaPedido(
            producto.id,
            producto.nombre,
            1,
            detalle,
          ),
        );
      } else if (lineas[indice].cantidad < 99) {
        lineas[indice] = lineas[indice].conCantidad(
          lineas[indice].cantidad + 1,
        );
      }
    });
  }

  void tocarPlato(Producto producto) {
    if (fijo) return;

    if (producto.opciones.isEmpty) {
      sumar(producto);
      return;
    }

    setState(() {
      configurando = producto;
      elecciones.clear();
    });
  }

  void cantidad(int indice, int cambio) {
    if (fijo) return;

    setState(() {
      final nuevaCantidad = lineas[indice].cantidad + cambio;

      if (nuevaCantidad <= 0) {
        lineas.removeAt(indice);
      } else if (nuevaCantidad <= 99) {
        lineas[indice] =
            lineas[indice].conCantidad(nuevaCantidad);
      }
    });
  }

  Future<void> notaLinea(int indice) async {
    if (fijo) return;

    final original = lineas[indice];

    final texto = await showDialog<String>(
      context: context,
      builder: (_) => NotaPlato(
        nombre: original.nombre,
        texto: original.detalle,
      ),
    );

    if (!mounted || texto == null || fijo) return;

    setState(() {
      lineas[indice] = LineaPedido(
        original.productoId,
        original.nombre,
        original.cantidad,
        texto,
      );
    });
  }

  Future<void> enviar() async {
    if (enviando || lineas.isEmpty) return;

    // Bloqueo inmediato: antes de cualquier espera.
    setState(() => enviando = true);
    FocusScope.of(context).unfocus();

    try {
      final folio = await datos.enviar(
        widget.mesa,
        List.unmodifiable(lineas),
        notas.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        lineas.clear();
        notas.clear();
        configurando = null;
      });

      aviso(context, '$folio confirmado en Firebase.');
    } catch (e) {
      if (mounted) {
        aviso(
          context,
          'Envío sin confirmar. Conservamos la comanda: $e',
        );
      }
    } finally {
      if (mounted) setState(() => enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmarSalida(
      cambios:
      !fijo && (lineas.isNotEmpty || notas.text.trim().isNotEmpty),
      bloqueado: enviando,
      child: Marco(
        titulo: '${widget.mesa.nombre} · Nueva comanda',
        child: ListenableBuilder(
          listenable: datos,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, limites) {
                if (limites.maxWidth >= 760) {
                  return Row(
                    children: [
                      Expanded(child: menu()),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: math.min(
                          390.0,
                          limites.maxWidth * .4,
                        ),
                        child: carrito(),
                      ),
                    ],
                  );
                }

                return Stack(
                  children: [
                    Positioned.fill(
                      child: menu(),
                    ),
                    DraggableScrollableSheet(
                      initialChildSize: 0.22,
                      minChildSize: 0.14,
                      maxChildSize: 0.86,
                      snap: true,
                      snapSizes: const [0.22, 0.50, 0.86],

                      builder: (context, scrollController) {
                        return Material(
                          elevation: 18,
                          color: superficie,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 55,
                                height: 6,
                                margin: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white38,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              Expanded(
                                child: carrito(
                                  controlador: scrollController,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget menu() {
    if (configurando != null) {
      return opciones(configurando!);
    }

    final disponibles = datos.productos
        .where(
          (p) => p.disponible && !categoriaBebida(p.categoria),
    )
        .toList();

    final consulta = normalizar(buscar.text);
    final verCategorias = categoria == null && consulta.isEmpty;
    final categorias = categoriasDe(disponibles);

    final platos = disponibles.where((producto) {
      return (categoria == null || producto.categoria == categoria) &&
          normalizar(
            '${producto.nombre} ${producto.categoria}',
          ).contains(consulta);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: buscar,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar comida',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: buscar.text.isEmpty
                  ? null
                  : IconButton(
                tooltip: 'Borrar búsqueda',
                onPressed: () {
                  setState(() => buscar.clear());
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
        if (categoria != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  categoria = null;
                  buscar.clear();
                });
              },
              icon: const Icon(Icons.arrow_back),
              label: Text('Categorías / $categoria'),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: verCategorias ? 230 : 300,
              mainAxisExtent: verCategorias ? 152 : 174,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: verCategorias
                ? categorias.length
                : platos.length,
            itemBuilder: (context, indice) {
              final titulo = verCategorias
                  ? categorias[indice]
                  : platos[indice].nombre;

              final producto = verCategorias ? null : platos[indice];

              final cuantos = producto == null
                  ? disponibles
                  .where((p) => p.categoria == titulo)
                  .length
                  : lineas
                  .where((l) => l.productoId == producto.id)
                  .fold<int>(
                0,
                    (numero, linea) => numero + linea.cantidad,
              );

              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: fijo
                      ? null
                      : () {
                    if (producto == null) {
                      setState(() => categoria = titulo);
                    } else {
                      tocarPlato(producto);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              producto == null
                                  ? iconoCategoria(titulo)
                                  : Icons.restaurant,
                              color: producto == null ? dorado : verde,
                              size: 28,
                            ),
                            const Spacer(),
                            if (producto != null && cuantos > 0)
                              Text(
                                '$cuantos',
                                style: const TextStyle(
                                  color: verde,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Text(
                            titulo,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                        Text(
                          producto == null
                              ? '$cuantos platos →'
                              : producto.opciones.isEmpty
                              ? '+ Agregar'
                              : 'Elegir opciones →',
                          style: TextStyle(
                            color: producto == null ? dorado : verde,
                            fontWeight: FontWeight.w700,
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

  Widget opciones(Producto producto) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() => configurando = null);
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Volver'),
          ),
        ),
        Text(
          producto.nombre,
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (producto.descripcion.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(producto.descripcion),
          ),
        for (final opcion in producto.opciones) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: 16,
              bottom: 8,
            ),
            child: Text(
              opcion.titulo,
              style: const TextStyle(
                color: dorado,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: opcion.alternativas.map((alternativa) {
              return ChoiceChip(
                label: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(alternativa),
                ),
                selected: elecciones[opcion.titulo] == alternativa,
                onSelected: fijo
                    ? null
                    : (_) {
                  setState(() {
                    elecciones[opcion.titulo] = alternativa;
                  });
                },
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: fijo ||
              !producto.opciones.every(
                    (o) => elecciones.containsKey(o.titulo),
              )
              ? null
              : () {
            sumar(
              producto,
              producto.opciones
                  .map(
                    (opcion) =>
                '${opcion.titulo}: '
                    '${elecciones[opcion.titulo]}',
              )
                  .join('\n'),
            );

            setState(() => configurando = null);
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar a la comanda'),
        ),
      ],
    );
  }

  Widget carrito({ScrollController? controlador}) =>
      Container(
      color: superficie,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, limites) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long, color: dorado),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Comanda · $unidades',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: lineas.isEmpty
                      ? const Center(
                    child: Text(
                      'Tocá una comida\npara agregarla aquí.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 20,
                      ),
                    ),
                  )
                      : ListView.separated(
                    controller: controlador,
                    itemCount: lineas.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, indice) {
                      final linea = lineas[indice];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            linea.nombre,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (linea.detalle.isNotEmpty)
                            Text(
                              linea.detalle,
                              style: const TextStyle(
                                color: dorado,
                                fontSize: 15,
                              ),
                            ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Restar ${linea.nombre}',
                                onPressed: fijo
                                    ? null
                                    : () => cantidad(indice, -1),
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 30,
                                ),
                              ),
                              Text(
                                '${linea.cantidad}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Sumar ${linea.nombre}',
                                onPressed: fijo || linea.cantidad >= 99
                                    ? null
                                    : () => cantidad(indice, 1),
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  color: verde,
                                  size: 30,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Nota del plato',
                                onPressed: fijo
                                    ? null
                                    : () => notaLinea(indice),
                                icon: const Icon(
                                  Icons.edit_note,
                                  color: dorado,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (limites.maxHeight >= 350)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: TextField(
                      controller: notas,
                      readOnly: fijo,
                      maxLength: 300,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Nota general (opcional)',
                        counterText: '',
                        prefixIcon: Icon(Icons.notes),
                      ),
                    ),
                  ),
                if (datos.envioPendiente != null && !enviando)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Sin confirmar. Reintentá esta misma comanda.',
                      style: TextStyle(
                        color: amarillo,
                        fontSize: 14,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: limites.maxHeight < 320 ? 60 : 76,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: rojo,
                      foregroundColor: Colors.white,
                    ),
                    onPressed:
                    enviando || lineas.isEmpty ? null : enviar,
                    icon: enviando
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : const Icon(
                      Icons.send_rounded,
                      size: 28,
                    ),
                    label: Text(
                      enviando
                          ? 'Confirmando…'
                          : datos.envioPendiente != null
                          ? 'Reintentar envío'
                          : 'Enviar a Cocina',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }


class NotaPlato extends StatefulWidget {
  final String nombre;
  final String texto;

  const NotaPlato({
    super.key,
    required this.nombre,
    required this.texto,
  });

  @override
  State<NotaPlato> createState() => _NotaPlatoState();
}

class _NotaPlatoState extends State<NotaPlato> {
  late final texto = TextEditingController(text: widget.texto);

  @override
  void dispose() {
    texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.nombre),
      content: SizedBox(
        width: 450,
        child: TextField(
          controller: texto,
          minLines: 2,
          maxLines: 6,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Indicaciones',
            hintText: 'Sin cebolla…',
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
            Navigator.pop(context, texto.text.trim());
          },
          child: const Text('Guardar nota'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// COCINA: PEDIDOS Y CRONÓMETROS EN TIEMPO REAL
// -----------------------------------------------------------------------------

class PedidosPage extends StatefulWidget {
  final bool cocina;
  final bool soloLectura;

  const PedidosPage({
    super.key,
    required this.cocina,
    this.soloLectura = false,
  });

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage> {
  final reloj = ValueNotifier<DateTime>(DateTime.now());
  Timer? timer;

  @override
  void initState() {
    super.initState();

    // Un solo reloj para todas las tarjetas.
    // No vuelve a consultar Firebase cada segundo.
    timer = Timer.periodic(
      const Duration(seconds: 1),
          (_) => reloj.value = DateTime.now(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Marco(
      titulo: widget.cocina
          ? 'Cocina · Comandas'
          : 'Pedidos en vivo',
      child: ListenableBuilder(
        listenable: datos,
        builder: (context, _) {
          if (datos.cargandoPedidos) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (datos.errorPedidos != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  datos.errorPedidos!,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (datos.pedidos.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Logotipo(lado: 120),
                  SizedBox(height: 24),
                  Text(
                    'Sin pedidos activos',
                    style: TextStyle(fontSize: 28),
                  ),
                  SizedBox(height: 10),
                  Text('Las nuevas comandas aparecerán aquí.'),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final estado in estados.take(3))
                    Chip(
                      label: Text(
                        '${nombreEstado(estado)}: '
                            '${datos.pedidos.where((p) => p.estado == estado).length}',
                      ),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Más antiguos primero · Verde <10 min · '
                      'Amarillo 10–20 min · Rojo >20 min',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
              LayoutBuilder(
                builder: (context, limites) {
                  final columnas = limites.maxWidth >= 1180
                      ? 3
                      : limites.maxWidth >= 760
                      ? 2
                      : 1;

                  final ancho =
                      (limites.maxWidth - (columnas - 1) * 16) /
                          columnas;

                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: datos.pedidos.map((pedido) {
                      return SizedBox(
                        key: ValueKey(pedido.id),
                        width: ancho,
                        child: TarjetaPedido(
                          pedido: pedido,
                          reloj: reloj,
                          cocina: widget.cocina,
                          soloLectura: widget.soloLectura,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class TarjetaPedido extends StatefulWidget {
  final Pedido pedido;
  final ValueNotifier<DateTime> reloj;
  final bool cocina;
  final bool soloLectura;

  const TarjetaPedido({
    super.key,
    required this.pedido,
    required this.reloj,
    required this.cocina,
    required this.soloLectura,
  });

  @override
  State<TarjetaPedido> createState() => _TarjetaPedidoState();
}

class _TarjetaPedidoState extends State<TarjetaPedido> {
  bool cambiando = false;

  Future<void> avanzar() async {
    if (cambiando) return;

    setState(() => cambiando = true);

    try {
      await datos.avanzar(widget.pedido);
    } catch (e) {
      if (mounted) {
        aviso(context, 'No se confirmó el cambio: $e');
      }
    } finally {
      if (mounted) setState(() => cambiando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;

    final puedeCambiar = !widget.soloLectura &&
        (widget.cocina
            ? pedido.estado == 'pendiente' ||
            pedido.estado == 'preparando'
            : pedido.estado == 'listo');

    final boton = pedido.estado == 'pendiente'
        ? 'Preparar'
        : pedido.estado == 'preparando'
        ? 'Marcar listo'
        : 'Marcar entregado';

    return RepaintBoundary(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pedido.mesaNombre,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Icon(Icons.restaurant, color: dorado),
                ],
              ),
              Text(
                '${pedido.zonaNombre} · ${pedido.numero}',
                style: const TextStyle(
                  color: dorado,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<DateTime>(
                valueListenable: widget.reloj,
                builder: (context, ahora, _) {
                  final segundos = pedido.hora == null
                      ? null
                      : math.max(
                    0,
                    ahora.difference(pedido.hora!).inSeconds,
                  );

                  final color = segundos == null
                      ? Colors.grey
                      : segundos < 600
                      ? verde
                      : segundos <= 1200
                      ? amarillo
                      : urgente;

                  final alerta =
                      segundos != null && segundos > 1200;

                  final parpadeo = alerta &&
                      !MediaQuery.of(context).disableAnimations;

                  final texto = segundos == null
                      ? 'Confirmando hora…'
                      : '${(segundos ~/ 60).toString().padLeft(2, '0')}:'
                      '${(segundos % 60).toString().padLeft(2, '0')}';

                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 350),
                    opacity:
                    parpadeo && ahora.second.isOdd ? .65 : 1,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        border: Border.all(
                          color: color,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            alerta
                                ? Icons.priority_high
                                : Icons.timer_outlined,
                            color: color,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              texto,
                              style: TextStyle(
                                color: color,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (alerta)
                            Text(
                              'URGENTE',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  nombreEstado(pedido.estado).toUpperCase(),
                  style: TextStyle(
                    color: pedido.estado == 'listo'
                        ? verde
                        : Colors.white70,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Divider(),
              for (final linea in pedido.lineas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${linea.cantidad} × ${linea.nombre}',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (linea.detalle.isNotEmpty)
                        Text(
                          linea.detalle,
                          style: const TextStyle(
                            fontSize: 18,
                            color: dorado,
                          ),
                        ),
                    ],
                  ),
                ),
              if (pedido.nota.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF342B1E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'NOTA: ${pedido.nota}',
                    style: const TextStyle(
                      color: dorado,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (puedeCambiar)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 62,
                    child: FilledButton.icon(
                      onPressed: cambiando ? null : avanzar,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(
                        cambiando ? 'Confirmando…' : boton,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
