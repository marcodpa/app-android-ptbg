param([string]$FlutterCommand = 'flutter')

$ErrorActionPreference = 'Stop'

if ($FlutterCommand -eq 'flutter') {
    foreach ($candidate in @(
        'C:\flutter\bin\flutter.bat',
        "$env:USERPROFILE\Documents\Codex\.tools\flutter\bin\flutter.bat",
        "$env:USERPROFILE\Documents\Codex\.tools\flutter_git\bin\flutter.bat"
    )) {
        if (Test-Path -LiteralPath $candidate) { $FlutterCommand = $candidate }
    }
}

Push-Location $PSScriptRoot
try {
    py -3 (Join-Path $PSScriptRoot 'actualizar_catalogo_apk.py')
    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudo actualizar el catalogo desde MariaDB. No se generara un APK antiguo.'
    }
    & $FlutterCommand build apk --debug --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) {
        throw 'Flutter no pudo compilar el APK USB.'
    }

    $apkPath = Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "Flutter no genero el APK USB esperado: $apkPath"
    }

    Write-Host "APK USB generado: $apkPath"
}
finally {
    Pop-Location
}
