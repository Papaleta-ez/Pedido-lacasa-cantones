$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$nodeExe = 'C:\Users\luisv\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
if (!(Test-Path -LiteralPath $nodeExe)) { $nodeExe = 'node' }
& $nodeExe 'functions/scripts/local-owner.cjs'
if ($LASTEXITCODE -ne 0) { throw 'Primero iniciar el servidor local y esperar a que las funciones estén listas.' }
Get-Content -LiteralPath '.local/cuenta-dueno.json'
