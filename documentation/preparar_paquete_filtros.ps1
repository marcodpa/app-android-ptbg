param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$destination = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $destination) { throw 'El destino ya existe. Use una carpeta nueva para no sobrescribir entregas.' }
New-Item -ItemType Directory -Path $destination | Out-Null
$uploader = Join-Path $destination 'uploader_seguro'
New-Item -ItemType Directory -Path $uploader | Out-Null
# Explicit allowlist: never package .env, credentials, database backups or logs.
foreach ($name in @('tablet_uploader.py','filter_sync.py','separator_cleaning.py',
    'abrir_subidor_seguro.py','abrir_subidor_usb.bat','requirements_tablet_uploader.txt',
    'black_start_report.py','compressor_checklist_report.py','equipment_report.py',
    'official_form_report.py','reporte_texto.py','verificar_filtros_bd.py','VERIFICAR_FILTROS_BD.bat')) {
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $uploader
}
foreach ($name in @('formatos_pdf_nuevos','formatos_pdf')) {
    $source = Join-Path $repo $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $uploader -Recurse }
}
New-Item -ItemType Directory -Path (Join-Path $uploader 'assets/data') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'assets/data/filter_catalog.json') -Destination (Join-Path $uploader 'assets/data')
Copy-Item -LiteralPath (Join-Path $repo 'documentation/FILTROS_PRUEBA_TABLET.md') -Destination (Join-Path $destination 'LEEME.md')
Copy-Item -LiteralPath (Join-Path $repo 'build/app/outputs/flutter-apk/app-debug.apk') -Destination (Join-Path $destination 'STER-filtros-prueba.apk')
Compress-Archive -LiteralPath $uploader -DestinationPath (Join-Path $destination 'uploader_seguro.zip')
Get-FileHash -LiteralPath (Join-Path $destination 'STER-filtros-prueba.apk'), (Join-Path $destination 'uploader_seguro.zip') -Algorithm SHA256
