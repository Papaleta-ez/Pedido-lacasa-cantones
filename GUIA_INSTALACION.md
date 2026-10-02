# Instalación paso a paso

## 1. Abrí tu proyecto local actualizado

Los cambios ya se aplicaron directamente en `C:\Users\luisv\StudioProjects\ pedidos_casa_cantones`. El nombre de la carpeta tiene un espacio antes de `pedidos`. Esta es la carpeta principal para las siguientes modificaciones.

Se guardó un respaldo previo en `C:\Users\luisv\Documents\Codex\2026-09-30\gol\outputs\Respaldo-proyecto-local-antes-de-actualizar.zip`. Se conservaron el logo, `google-services.json`, `local.properties` y la configuración de identidad Android.

Abrí esta misma carpeta en Android Studio. Para comprobarla desde PowerShell:

```powershell
Set-Location -LiteralPath 'C:\Users\luisv\StudioProjects\ pedidos_casa_cantones'
flutter pub get
flutter analyze
flutter test
```
## 2. Prepará Firebase

En tu proyecto Firebase existente:

1. Authentication > Sign-in method: activá **Anonymous** y **Email/Password**.
2. Authentication > Users: creá la cuenta email/contraseña del dueño y copiá su UID.
3. Conservá `android/app/google-services.json`. Debe corresponder al mismo proyecto donde vas a desplegar funciones y reglas.
4. Para Web: Project settings > Your apps > agregá una app Web. Copiá apiKey, appId, messagingSenderId, projectId, authDomain y storageBucket.
5. Verificá que Firestore esté creado. Para desplegar Cloud Functions habilitá facturación/plan Blaze cuando Firebase lo solicite.

La aplicación antigua usa `pedidos` y `configuracion/restaurante`. La nueva usa `orders`, `products`, `inventory`, etc. **No se migran automáticamente los pedidos antiguos ni se reemplazan tus datos anteriores.** Terminá las cuentas abiertas de la versión antigua antes de usar la nueva. Las nuevas reglas bloquean el acceso de la aplicación anterior a sus colecciones: respaldá Firestore y programá el cambio de reglas cuando las terminales estén listas.

## 3. Instalá y desplegá el backend

Necesitás Node.js **22** y npm en tu sesión de Windows. Usá una terminal normal de tu usuario.

```powershell
npm install -g firebase-tools
firebase login
firebase use --add
```

En la selección elegí tu proyecto Firebase, y asignale el alias `default`.

```powershell
Set-Location functions
npm install
npm test
Set-Location ..
firebase deploy --only functions,firestore:rules,firestore:indexes
```

Estos comandos son para que los ejecutes vos: esta entrega no desplegó reglas ni funciones en tu proyecto.

Las funciones están en `us-central1`, igual que `lib/core/repository.dart`. Si elegís otra región, cambiá ambos archivos antes de desplegar.

## 4. Asigná el rol del dueño

El rol `owner` lo asigna un administrador con Firebase Admin SDK, nunca Flutter.

En Firebase Console > Project settings > Service accounts, generá una clave privada de administración. Guardala fuera del proyecto y no la subas a GitHub. Alternativamente, usá Application Default Credentials de tu cuenta administradora con gcloud.

Desde la raíz del proyecto:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\admin-firebase.json'
node functions/scripts/set-owner.cjs TU_PROJECT_ID UID_DEL_DUENO
```

Reemplazá `TU_PROJECT_ID` y `UID_DEL_DUENO` por los valores reales. El script conserva otros claims existentes y agrega `owner: true`.

Después de asignar el claim, iniciá sesión de nuevo o usá **Actualizar autorización** si la pantalla todavía muestra el UID sin permiso.

## 5. Arrancá al dueño e inicializá

Android con `google-services.json`:

```powershell
flutter run --dart-define=MODO=dueno
```

Iniciá sesión con el email/contraseña del dueño. En **Gestión**:

1. Tocá **Inicializar negocio y menú (una sola vez)**. La función se niega a sobreescribir un negocio existente.
2. Configurá nombre, RUC, dirección, teléfono, moneda, IVA y empaque.
3. Configurá tu PIN de cuatro dígitos.
4. En Catálogo, ingresá los precios reales y las cantidades disponibles. Los productos iniciales tienen precio y stock cero; no se venden hasta configurarlos.
5. Cargá recetas por ingrediente, o usá stock directo por plato. Una receta reemplaza el descuento del stock directo del producto.
6. Cargá stock al insumo de empaque para poder usar Para llevar y Delivery.
7. En Plano, editá Salón/Terraza/Afuera, sus dimensiones, mesas, lado y coordenadas.

El IVA se guarda en puntos básicos: **1500 significa 15%**. Los precios son antes de IVA. El descuento reduce el subtotal antes de IVA y propina; la propina opcional es 10% de ese subtotal descontado.

El teclado monetario usa centavos: escribí `25000` para C$250.00. Cantidades, ingredientes y dimensiones se ingresan multiplicadas por 100: `125` significa 1.25 unidades, kg o metros según el campo. El campo IVA recibe directamente puntos básicos.

El inventario contado requiere PIN si bajás el saldo. Si otro terminal cambió el stock mientras editabas, el servidor pide reabrir el insumo; así no se pierden consumos concurrentes.

## 6. Arrancá y autorizá los terminales

En la tablet del mesero:

```powershell
flutter run --dart-define=MODO=mesero
```

En el dispositivo de cocina:

```powershell
flutter run --dart-define=MODO=cocina
```

Inician de forma anónima y muestran su UID hasta que el dueño los autoriza. En Dueño > Gestión > Dispositivos, verificá el UID y asigná el rol correspondiente. La pantalla cambia automáticamente cuando llega la autorización.

Usá dispositivos o perfiles de navegador separados para cada rol. Firebase Auth comparte la sesión dentro de un mismo perfil/origen; abrir dueño y cocina en pestañas del mismo perfil puede cambiar la sesión de ambas.

Si borrás los datos de la app, reinstalás o limpiás el almacenamiento del navegador, el terminal puede obtener otro UID y requerirá autorización otra vez. Revocá el UID anterior desde el dueño.

## 7. Compilá las APK

```powershell
flutter build apk --release --dart-define=MODO=mesero
Copy-Item build/app/outputs/flutter-apk/app-release.apk mesero.apk
flutter build apk --release --dart-define=MODO=cocina
Copy-Item build/app/outputs/flutter-apk/app-release.apk cocina.apk
flutter build apk --release --dart-define=MODO=dueno
Copy-Item build/app/outputs/flutter-apk/app-release.apk dueno.apk
```

Cada compilación abre directamente su modo. Comparten applicationId: instalá cada APK en su dispositivo correspondiente; instalar otra en el mismo dispositivo reemplaza la anterior.

El proyecto conserva la firma debug que ya tenía tu configuración release. Para distribuir fuera de una instalación interna, configurá tu keystore de producción en `android/app/build.gradle.kts`.

## 8. PC Windows mediante Web

Copiá `firebase-config.example.json` como `firebase-config.json` y reemplazá los seis valores con los de **la app Web**, no el appId Android.

```powershell
Copy-Item firebase-config.example.json firebase-config.json
flutter run -d chrome --dart-define=MODO=mesero --dart-define-from-file=firebase-config.json
```

Para cocina o dueño cambiá el valor de `MODO`. Para generar Web:

```powershell
flutter build web --release --dart-define=MODO=mesero --dart-define-from-file=firebase-config.json
```

`build/web` contiene el sitio. Si querés publicarlo en tu Firebase Hosting, ejecutá cuando lo tengas configurado:

```powershell
firebase deploy --only hosting
```

Este `firebase.json` configura un solo sitio. Para publicar los tres modos simultáneamente, creá tres sitios/targets de Hosting y asigná a cada uno su compilación; no publiques consecutivamente tres modos sobre el mismo sitio porque la última compilación reemplaza la anterior. Para una PC Windows dedicada, el modo mesero Web es suficiente y evita depender de FlutterFire nativo Windows.

## 9. Operación diaria

- Tocá una mesa libre: se abre su menú y la comanda permanece a la derecha en horizontal.
- Tocá una mesa activa: podés agregar otra comanda; **Ver cuenta / Cobrar** abre su cuenta.
- Para llevar/Delivery: ingresá el nombre del cliente; no ocupa mesa.
- Bebidas: el mesero puede venderlas y cobrarlas, pero solo `esComida: true` llega a cocina.
- Enviar: el botón se bloquea inmediatamente. El servidor valida precio y stock, y descuenta todo en una transacción.
- Si la confirmación se pierde: reintentá la misma comanda. **Verificar envío / corregir rechazo** consulta el servidor y, si no existe, descarta de forma atómica la solicitud para bloquear un envío tardío.
- En cocina: Pendiente > Preparando > Listo. Cada envío adicional tiene temporizador propio. **Retirar de pantalla** archiva una comanda lista sin borrar la cuenta.
- Cobrar por artículos: activá división, seleccioná cantidades y registrá el pago. La mesa sigue ocupada mientras quede algo por cobrar.
- Entre N personas: distribuye hasta el último centavo y registra un pago completo. Para pagos distintos, usá división por artículos.
- Unir mesas: agrega mesas libres a esta cuenta. No fusiona dos cuentas que ya tienen pedidos.
- Descuentos/cancelaciones/mermas: requieren PIN. Cinco intentos incorrectos bloquean 15 minutos a esa identidad.
- Cancelar antes de preparar: podés devolver stock. Si alguna comanda ya inició preparación, cancelar registra el consumo sin devolver ingredientes. No se cancelan pedidos cobrados parcial o totalmente.
- Cierre X: fotografía del turno, sin reiniciarlo. Cierre Z: compara el efectivo contado y abre el siguiente turno con su fondo. Antes de Z, cobrá o cancelá todas las cuentas abiertas.
- Cierres/mermas interrumpidos: usá los botones de reintentar o verificar en la barra del dueño. Conservan el mismo identificador incluso después de reiniciar la app.

## 10. PDF, impresión y WhatsApp

Después de cobrar, elegí **Imprimir** o **Compartir PDF**. También podés recuperar una factura desde el historial del dueño o desde la cuenta cerrada.

La impresión usa el diálogo del sistema. Instalá el controlador de la impresora USB y seleccioná papel de 80 mm. El documento pagina en 80 × 297 mm para cuentas largas; no hay comandos ESC/POS ni apertura de cajón en esta entrega.

En Android, Compartir permite elegir WhatsApp si está instalado. En Web/Windows, el soporte de compartir depende del navegador: guardá el PDF y adjuntalo en WhatsApp si el sistema descarga el archivo.

En Dueño > Resumen > Reporte mensual PDF, elegí cualquier día del mes requerido. El reporte consolida las facturas ya emitidas. Los documentos usan el logo existente y Noto Sans incluido, sin descargar fuentes al imprimir.

## 11. Pruebas en emulador

Necesitás un JDK compatible con el emulador; se usó el JBR de Android Studio.

```powershell
Set-Location functions
npm test
npm run test:emulator
```

Para evitar depender del alias de tu proyecto real, usá directamente:

```powershell
npx firebase emulators:exec --project demo-cantones --only firestore "node --test test/emulator.test.js"
```

Las pruebas borran únicamente los datos del proyecto `demo-cantones` en el emulador. Nunca las dirijas a tu Firestore de producción.

## Archivos de servidor y responsabilidades

`functions/src/domain.js`: importes, reparto y receta/empaque.

`functions/src/index.js`: registro/autorización de terminales, PIN, catálogo, pedidos/comandas adicionales, cocina, cobros, cancelaciones, mermas, cierres y recuperación.

`functions/src/seed.json`: menú inicial recuperado del proyecto; sin precios inventados y sin stock ficticio.

`firestore.rules`: lecturas por rol y prohibición de todas las escrituras del cliente. PIN, contadores, solicitudes descartadas e insumos consumidos solo se modifican desde Admin SDK en funciones.

Antes de ampliar el uso fuera de terminales dedicados, podés activar Firebase App Check para las callable siguiendo la documentación oficial y configurar el proveedor en Flutter. Esta versión verifica Auth, owner y dispositivos autorizados; no exige App Check todavía.





## Proyecto Firebase Web nuevo
Se registró POS Web en `la-casa-cantones-pos-5eb4c`. Chrome usa su configuración de forma predeterminada, sin argumentos adicionales. La configuración Android todavía corresponde al proyecto anterior y debe registrarse también en el proyecto nuevo antes de usar celulares. Authentication, Firestore y Cloud Functions del nuevo proyecto siguen pendientes de configurar.

