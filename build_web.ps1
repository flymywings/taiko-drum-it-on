param([switch]$WorkerOnly)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutterSdk = if ($env:FLUTTER_SDK) { $env:FLUTTER_SDK } else { 'C:\src\flutter' }
$dart = Join-Path $flutterSdk 'bin\cache\dart-sdk\bin\dart.exe'
$flutter = Join-Path $flutterSdk 'bin\flutter.bat'

if (-not (Test-Path -LiteralPath $dart) -or -not (Test-Path -LiteralPath $flutter)) {
  throw 'Set FLUTTER_SDK to your Flutter SDK directory before running this script.'
}

Push-Location $projectRoot
try {
  & $flutter --suppress-analytics pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
  & $dart compile js -O4 -o 'web\import_worker.js' 'import_worker.dart'
  if ($LASTEXITCODE -ne 0) { throw 'Import worker build failed.' }
  if (-not $WorkerOnly) {
    & $flutter --suppress-analytics build web --release
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
  }
} finally {
  Pop-Location
}
