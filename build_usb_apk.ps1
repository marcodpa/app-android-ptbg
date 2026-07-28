$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
    flutter build apk --debug --target-platform android-arm64

    $apkPath = Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "Flutter no genero el APK USB esperado: $apkPath"
    }

    Write-Host "APK USB generado: $apkPath"
}
finally {
    Pop-Location
}
