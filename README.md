# La Casa Cantones POS - versión inicial

Aplicación modular Flutter 3.47.4 / Dart 3.13.3. Tres modos: mesero, cocina y dueño. Firebase Auth, Firestore y Cloud Functions protegen las operaciones de stock y facturación.

Leé **GUIA_INSTALACION.md** antes de ejecutar. Todos los archivos del paquete son completos; no hay fragmentos que debas ensamblar.

## Qué incluye

- Mesero: mapa por zonas, menú por categorías, comanda fija, notas rápidas, comida/bebidas, para llevar/delivery y cuentas abiertas.
- Mesas activas admiten nuevas comandas. Cocina recibe solo los nuevos platos de cada envío, con su propio temporizador.
- Cocina: tiempo real, semáforo de 10/20 minutos, pendiente/preparando/listo y retiro de comandas listas.
- Dueño: email/contraseña con claim owner, dashboard, catálogo, recetas, inventario, plano, autorización/revocación de terminales, datos del negocio y PIN.
- Inventario: recetas, stock directo, empaque por artículo, transacciones, control de edición concurrente y mermas con PIN.
- Caja: cobros por artículos, distribución exacta entre N personas, efectivo/tarjeta/transferencia, IVA, descuento con PIN, propina opcional y cierres X/Z.
- Facturación: folio correlativo, PDF de 80 mm, impresión del sistema, compartir PDF y reporte mensual.
- Recuperación: envíos, cobros, mermas y cierres usan identificadores persistidos para reintentar sin duplicación.

## Estructura

```
lib/
  main.dart
  core/                 modelos, repositorio, tema y teclado numérico
  features/
    auth/               login y autorización del terminal
    pos/                mesas, menú y comanda
    kitchen/            KDS
    owner/              dashboard, catálogo y administración
    billing/            cobro y PDF
functions/
  src/                  operaciones callable y cálculo puro
  scripts/set-owner.cjs administrador del claim owner
  test/                 pruebas de dominio y emulador
firestore.rules         lecturas por rol; escrituras solo desde backend
firebase.json           despliegue y emuladores
web/                    proyecto web para computadoras Windows
```

## Alcance comprobado y límites de esta entrega

La compilación web y las pruebas se detallan en **VERIFICACION.md**. El código Android está incluido, pero la compilación APK no se pudo confirmar porque el SDK Android devolvió acceso denegado en esta sesión.

Windows se utiliza mediante Chrome/Edge con la versión Web. No se entrega un ejecutable nativo Windows probado. La impresora utiliza PDF y el diálogo del sistema; ESC/POS queda pendiente del modelo, tal como se pidió.

Dividir entre N personas muestra cuotas exactas y registra un pago completo. Para registrar pagos independientes, seleccioná artículos y cobrá cada selección. Unir mesas agrega mesas libres a una cuenta; no fusiona cuentas que ya tengan pedidos independientes.

El stock se descuenta al enviar, nunca nuevamente al cobrar. Para llevar y delivery usan un empaque por artículo; esta política es explícita y editable en `functions/src/domain.js` si el restaurante usa otro criterio.

No se envían pedidos ni pagos sin conexión. Un envío cuya confirmación se perdió queda bloqueado y se recupera con el mismo identificador. Los borradores aún no enviados no se conservan al cerrar la app.

El dashboard y el reporte mensual leen el historial completo de facturas, adecuado para esta versión inicial. Para años de historial o muchos locales, conviene paginar y mantener agregados diarios desde backend.

## Fuentes técnicas

- [Funciones callable de Firebase](https://firebase.google.com/docs/functions/callable)
- [Transacciones Firestore](https://firebase.google.com/docs/firestore/manage-data/transactions)
- [Printing](https://pub.dev/packages/printing)
- [PDF](https://pub.dev/packages/pdf)
- Noto Sans: [fuente y licencia OFL](https://github.com/notofonts/noto-fonts), incluidas en `assets/fonts/`.

## Pruebas sin facturación
Ver MODO_LOCAL.md para iniciar Firebase local y conectar PC y tablet Android. No requiere Blaze. Es un entorno de pruebas; las ventas reales necesitan un servidor de producción adecuado.

