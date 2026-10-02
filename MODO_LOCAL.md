# Pruebas gratuitas en PC y tablet Android

No requiere Blaze, tarjeta, login de Firebase CLI ni desplegar funciones. Usa `demo-cantones`: no toca Firebase real.

Esta modalidad es un entorno de pruebas. Los emuladores no implementan todas las protecciones de producción y no deben exponerse a Internet ni usarse para ventas reales sin sustituirlos por un servidor adecuado. Usar solo una red Wi-Fi de confianza. La PC debe estar encendida; no apagarla ni suspenderla mientras se prueba.

## Inicio

Abrir PowerShell en esta carpeta y ejecutar:

```powershell
powershell -ExecutionPolicy Bypass -File .\iniciar-servidor-local.ps1
```

Esperar «All emulators ready». Mantener esa ventana abierta. En otra terminal:

```powershell
powershell -ExecutionPolicy Bypass -File .\preparar-dueno-local.ps1
powershell -ExecutionPolicy Bypass -File .\abrir-pos-local.ps1 -Modo dueno
```

El primer comando muestra el correo y la contraseña de prueba, guardados en `.local/cuenta-dueno.json`. No usar una contraseña de otro servicio. En Dueño, configurar precios, stock y PIN. El catálogo inicial tiene precios y existencias en cero.

Para mesero en PC:

```powershell
powershell -ExecutionPolicy Bypass -File .\abrir-pos-local.ps1 -Modo mesero
```

Usar perfiles de Chrome distintos para Dueño y Mesero; cada terminal debe tener una sesión separada. Autorizar las terminales en Dueño → Gestión.

## Tablet Android

PC y tablet en la misma red. Obtener la IPv4 de la PC con `ipconfig`. Conectar la tablet por USB para instalar; obtener su ID con `flutter devices`.

```powershell
powershell -ExecutionPolicy Bypass -File .\abrir-pos-local.ps1 -Modo mesero -Servidor 192.168.1.10 -Dispositivo ID_DE_LA_TABLET
```

Reemplazar IP e ID. En Android Studio: `lib/main.dart`, argumentos `--dart-define=MODO=mesero --dart-define=LOCAL=true --dart-define=LOCAL_HOST=IP_DE_LA_PC`. El modo local es solo debug. No basta Hot Reload al cambiar estos argumentos: detener y ejecutar de nuevo.

Si Windows bloquea la conexión, revisar permisos del firewall solo para esta red privada y puertos 9099, 8080, 5001. No abrir puertos del router. No se cambió el firewall automáticamente. Si cambia la IP de la PC, reinstalar la ejecución con la nueva IP.

## Guardar datos

Detener el servidor con Ctrl+C y esperar la exportación final antes de cerrar. Al volver a iniciar se importa `.local/datos`. Un corte de luz o terminar el proceso a la fuerza puede perder los cambios desde el último export. Para guardar durante la sesión, desde otra terminal:

```powershell
node functions/node_modules/firebase-tools/lib/bin/firebase.js emulators:export .local/datos --project demo-cantones --config firebase.local.json --force
```

Respaldar `.local` completa; contiene datos y credenciales locales y está excluida de Git. No eliminarla al limpiar el proyecto.

Referencia: https://firebase.google.com/docs/emulator-suite/install_and_configure

IP Wi-Fi de la PC verificada al preparar esta guía: `192.168.1.27`. Puede cambiar; comprobar con ipconfig.

