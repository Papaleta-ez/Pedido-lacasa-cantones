# Verificación de la entrega

Fecha: 30 de septiembre de 2026, America/Managua.

## Resultado

- Flutter 3.47.4, Dart 3.13.3: dependencias resueltas con `flutter pub get`.
- `flutter analyze`: sin problemas.
- `flutter test`: 5 pruebas aprobadas.
- Backend de cálculo: 4 pruebas aprobadas.
- Firestore Emulator, proyecto `demo-cantones`: 9 pruebas de integración aprobadas.
- Web release: compilaciones de `MODO=mesero`, `MODO=cocina` y `MODO=dueno` aprobadas.
- PDF: ticket de 80 mm y reporte A4 renderizados con Poppler y revisados visualmente. Logo, acentos, artículos largos, importes y paginación comprobados. Reporte de 50 facturas: 2 páginas.

18 pruebas en total. Las pruebas de backend usaron Node 24.19.0 del entorno; el despliegue está configurado para Node 22 y utiliza APIs compatibles con ese runtime.

## Casos comprobados con Firestore real del emulador

1. Escrituras directas de clientes denegadas, incluso con claim owner; cocina sin acceso a cuentas completas.
2. Dos envíos simultáneos con el mismo ID generan un solo pedido y un solo descuento de stock.
3. Las bebidas se cobran pero no aparecen en la comanda de cocina.
4. Cobros simultáneos con el mismo ID producen una sola factura; un cobro parcial conserva la mesa ocupada.
5. Stock insuficiente revierte la operación sin crear pedido ni ocupar mesa.
6. Descartar un envío impide que una ejecución tardía lo cree.
7. Agregar artículos a una cuenta es idempotente y crea otra comanda de cocina.
8. Una cancelación después de iniciar preparación no permite reponer ingredientes.
9. Un cierre Z repetido abre un solo turno nuevo; edición de inventario desactualizada es rechazada.
10. PIN incorrecto impide la operación y cinco intentos bloquean temporalmente.
11. Revocar el dispositivo bloquea funciones y lecturas posteriores.

Los casos se agrupan en nueve pruebas de integración.

## Android: no verificado hasta generar APK en tu sesión

La revisión encontró que `android/app/build.gradle.kts` usaba el bloque `kotlin { compilerOptions ... }` pero no aplicaba el plugin Kotlin, mientras `android.builtInKotlin=false` estaba activo. Se agregó `org.jetbrains.kotlin.android` y se ordenó Google Services después del plugin Android. Se conservaron los flags legacy del proyecto.

Después de esa corrección, Gradle avanzó hasta la resolución del NDK y falló en `NdkLocator.getNdkVersionedFolders`: esta sesión no puede listar el SDK/NDK Android. El directorio devuelve acceso denegado aun después de conceder lectura. Por eso **no se entrega una APK ni se afirma que Android compiló**. La guía incluye los comandos para verificarlo con tu usuario de Windows.

Referencia para la configuración de Kotlin: [guía oficial de Flutter](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers).

## Integración pendiente con tu proyecto real

No se ejecutó una sesión completa contra tu Firebase de producción. Primero debés activar los proveedores Auth, asignar owner, desplegar funciones/reglas, registrar la app Web y configurar precios/stock. Tampoco se probó una impresora física, cuyo modelo todavía no está definido.

Las compilaciones Web comprueban que los tres modos compilan; para conectarlos se requieren los valores Firebase de tu app Web indicados en la guía.

El `main.dart` anterior está conservado en el respaldo previo. Su SHA-256 al comenzar era:

`5D3977609B50BAB33E58491EB6A5F7B5AD2233AA86B026F5B085113B3F06323B`

La entrega no publicó commits ni desplegó recursos externos.

Los cambios se aplicaron directamente en `C:\Users\luisv\StudioProjects\ pedidos_casa_cantones`. Se conservaron la configuración Firebase Android, el logo y las rutas locales del SDK.


Comprobación posterior en la carpeta local: `flutter pub get --offline` completado; `flutter analyze --no-pub` sin problemas; `flutter test --no-pub` con 5 pruebas aprobadas.
