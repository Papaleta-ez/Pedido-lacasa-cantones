$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$nodeBin = 'C:\Users\luisv\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin'
if (Test-Path -LiteralPath $nodeBin) { $env:Path = $nodeBin + ';' + $env:Path }
$javaDir = 'C:\Program Files\Android\Android Studio\jbr'
if (Test-Path -LiteralPath $javaDir) { $env:JAVA_HOME = $javaDir; $env:Path = (Join-Path $javaDir 'bin') + ';' + $env:Path }
$cli = Join-Path $PSScriptRoot 'functions\node_modules\firebase-tools\lib\bin\firebase.js'
if (!(Test-Path -LiteralPath $cli)) { throw 'Faltan dependencias de functions. Ejecutar npm install en functions.' }
$exportDir = Join-Path $PSScriptRoot '.local\datos'
$firebaseArgs = @($cli, 'emulators:start', '--config', 'firebase.local.json', '--project', 'demo-cantones', '--only', 'auth,firestore,functions', '--export-on-exit', $exportDir)
if (Test-Path -LiteralPath (Join-Path $exportDir 'firebase-export-metadata.json')) { $firebaseArgs += @('--import', $exportDir) }
Write-Host 'Servidor de PRUEBAS local. No cerrar esta ventana. Detener con Ctrl+C para guardar datos.'
Write-Host 'No abrir estos puertos a Internet. Solo PC y tablet en tu red de confianza.'
& node @firebaseArgs
