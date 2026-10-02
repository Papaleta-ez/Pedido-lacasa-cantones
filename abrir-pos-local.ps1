param([ValidateSet('mesero','dueno','cocina')][string]$Modo='mesero',[string]$Servidor='127.0.0.1',[string]$Dispositivo='chrome')
Set-Location -LiteralPath $PSScriptRoot
$flutterExe = 'C:\Users\luisv\develop\flutter\bin\flutter.bat'
if (!(Test-Path -LiteralPath $flutterExe)) { $flutterExe = 'flutter' }
& $flutterExe run -d $Dispositivo "--dart-define=MODO=$Modo" '--dart-define=LOCAL=true' "--dart-define=LOCAL_HOST=$Servidor"
