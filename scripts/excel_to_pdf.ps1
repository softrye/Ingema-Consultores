param(
  [Parameter(Mandatory=$true)][string]$xlsx,
  [Parameter(Mandatory=$false)][string]$pdf,
  [Parameter(Mandatory=$false)][string]$outDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Sanitize-FileName([string]$name) {
  $invalid = [IO.Path]::GetInvalidFileNameChars()
  foreach ($c in $invalid) { $name = $name.Replace([string]$c, "_") }
  $name = $name.Trim()
  if ([string]::IsNullOrWhiteSpace($name)) { $name = "Sheet" }
  return $name
}

function EnsureDirForFile([string]$path) {
  $dir = [IO.Path]::GetDirectoryName($path)
  if (![string]::IsNullOrWhiteSpace($dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
}

function Release-Com($o) {
  if ($null -ne $o) {
    try { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($o) } catch {}
  }
}

function Log-Com([string]$tag, $ex) {
  $hr = ("0x{0:X8}" -f $ex.HResult)
  [Console]::Error.WriteLine("$tag|COMException|HR=$hr|MSG=$($ex.Message)")
}

function WriteCleanTempCopy([string]$src) {
  $tmp = Join-Path $env:TEMP ("excelprev_clean_" + [guid]::NewGuid().ToString("N") + ".xlsx")
  # Escribir bytes => NO conserva ADS (Zone.Identifier)
  $bytes = [IO.File]::ReadAllBytes($src)
  [IO.File]::WriteAllBytes($tmp, $bytes)
  return $tmp
}

function OpenWorkbookClean($excel, [string]$path) {
  # Intento 1: abrir el original (mínimo de params)
  try {
    [Console]::Error.WriteLine("OPEN|try|$path")
    return $excel.Workbooks.Open($path, 0, $true) # UpdateLinks=0, ReadOnly=true
  } catch [System.Runtime.InteropServices.COMException] {
    Log-Com "OPEN_FAIL_1" $_.Exception
  }

  # Intento 2: abrir copia limpia en TEMP
  $clean = WriteCleanTempCopy $path
  try {
    [Console]::Error.WriteLine("OPEN|clean_copy|$clean")
    $wb = $excel.Workbooks.Open($clean, 0, $true)
    return @{ wb = $wb; clean = $clean }
  } catch [System.Runtime.InteropServices.COMException] {
    Log-Com "OPEN_FAIL_2" $_.Exception
    try { Remove-Item -Force $clean -ErrorAction SilentlyContinue } catch {}
  }

  throw "No se pudo abrir el Excel por COM. (original y clean copy fallaron)"
}

# Validación de modo
if ([string]::IsNullOrWhiteSpace($pdf) -and [string]::IsNullOrWhiteSpace($outDir)) {
  throw "Debes pasar -pdf (un solo PDF) o -outDir (PDF por hoja)."
}

$xlsx = [IO.Path]::GetFullPath($xlsx)

if (-not [string]::IsNullOrWhiteSpace($pdf)) {
  $pdf = [IO.Path]::GetFullPath($pdf)
  EnsureDirForFile $pdf
}

if (-not [string]::IsNullOrWhiteSpace($outDir)) {
  $outDir = [IO.Path]::GetFullPath($outDir)
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

# (opcional) intenta quitar Mark-of-the-Web si existiera
try { Unblock-File -Path $xlsx -ErrorAction SilentlyContinue } catch {}

$excel = $null
$wb    = $null
$cleanCopyPath = $null

try {
  [Console]::Error.WriteLine("EXCEL|create")

  $excel = New-Object -ComObject Excel.Application
  $excel.Visible = $false
  $excel.DisplayAlerts = $false
  $excel.ScreenUpdating = $false
  try { $excel.EnableEvents = $false } catch {}
  try { $excel.Interactive  = $false } catch {}
  try { $excel.AskToUpdateLinks = $false } catch {}
  try { $excel.AutomationSecurity = 3 } catch {} # ForceDisable macros

  $opened = OpenWorkbookClean $excel $xlsx
  if ($opened -is [hashtable]) {
    $wb = $opened.wb
    $cleanCopyPath = $opened.clean
  } else {
    $wb = $opened
  }

  $xlTypePDF         = 0
  $xlQualityStandard = 0

  # MODO: un solo PDF
  if (-not [string]::IsNullOrWhiteSpace($pdf)) {
    [Console]::Error.WriteLine("EXPORT|workbook|$pdf")
    $wb.ExportAsFixedFormat($xlTypePDF, $pdf, $xlQualityStandard, $true, $false) | Out-Null
    if (-not (Test-Path $pdf)) { throw "No se creó el PDF: $pdf" }
    Write-Output $pdf
    return
  }

  # MODO: PDF por hoja
  $baseName = [IO.Path]::GetFileNameWithoutExtension($xlsx)
  $result   = [ordered]@{}
  $errors   = New-Object System.Collections.Generic.List[string]

  foreach ($ws in $wb.Worksheets) {
    $sheetName = [string]$ws.Name
    $safeSheet = Sanitize-FileName $sheetName

    $pdfPath = Join-Path $outDir ("{0}__{1}.pdf" -f $baseName, $safeSheet)
    $i = 1
    while (Test-Path $pdfPath) {
      $pdfPath = Join-Path $outDir ("{0}__{1}_{2}.pdf" -f $baseName, $safeSheet, $i)
      $i++
    }

    try {
      [Console]::Error.WriteLine("EXPORT|sheet|$sheetName|$pdfPath")
      $ws.ExportAsFixedFormat($xlTypePDF, $pdfPath, $xlQualityStandard, $true, $false) | Out-Null
      if (Test-Path $pdfPath) { $result[$sheetName] = $pdfPath }
      else { $errors.Add(("Hoja '{0}': no se creó el PDF" -f $sheetName)) | Out-Null }
    }
    catch {
      $errors.Add(("Hoja '{0}' falló: {1}" -f $sheetName, $_.Exception.Message)) | Out-Null
    }
    finally {
      Release-Com $ws
    }
  }

  if ($result.Count -eq 0) {
    throw ("No se pudo exportar ninguna hoja a PDF. Errores: " + ($errors -join " | "))
  }

  if ($errors.Count -gt 0) {
    [Console]::Error.WriteLine("WARN: Algunas hojas fallaron: " + ($errors -join " | "))
  }

  $result | ConvertTo-Json -Depth 4 -Compress
}
finally {
  if ($wb)    { try { $wb.Close($false) | Out-Null } catch {} }
  if ($excel) { try { $excel.Quit()     | Out-Null } catch {} }

  Release-Com $wb
  Release-Com $excel

  if ($cleanCopyPath -and (Test-Path $cleanCopyPath)) {
    try { Remove-Item -Force $cleanCopyPath } catch {}
  }

  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
