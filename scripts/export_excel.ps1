param(
  [Parameter(Mandatory=$true)][string]$xlsx,
  [Parameter(Mandatory=$true)][string]$json
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

trap {
  Write-Host ("PS ERROR: " + $_.Exception.Message)
  if ($_.InvocationInfo) {
    Write-Host ("Line " + $_.InvocationInfo.ScriptLineNumber + ": " + $_.InvocationInfo.Line)
  }
  exit 1
}

Add-Type -AssemblyName System.Drawing

# Constantes Excel (COM)
$XL_NONE = -4142                 # xlNone / xlLineStyleNone / xlColorIndexNone
$XL_EDGE_LEFT = 7
$XL_EDGE_TOP = 8
$XL_EDGE_BOTTOM = 9
$XL_EDGE_RIGHT = 10
$XL_INSIDE_VERTICAL = 11
$XL_INSIDE_HORIZONTAL = 12
$XL_DIAGONAL_DOWN = 5
$XL_DIAGONAL_UP = 6

# Constantes Office (ZOrder)
$msoBringToFront = 0
$msoSendToBack   = 1
# Constantes Office (Shapes)
$msoShapeRectangle = 1
$msoTrue  = -1
$msoFalse = 0
$msoAlignCenter = 2
$msoAnchorMiddle = 3
# Constantes extra
$msoTextOrientationHorizontal = 1


# -------------------------
# CONFIG NUEVO FORMATO 3.00 m
# -------------------------
$script:BASE_ROW       = 22
$script:ROWS_PER_METER = 20.0
$script:MAX_DATA_ROW   = 81
$script:OBS_ADDR       = "AH84"

$script:PHOTO1_ADDR = "AU21:BC41"
$script:PHOTO2_ADDR = "AU43:BC61"
$script:PHOTO3_ADDR = "AU63:BC82"

# Columnas / rangos lógicos del formato
$script:DESC_LEFT_COL   = "J"
$script:DESC_RIGHT_COL  = "P"
$script:SUCS_COL        = "AH"

$script:FIN_LEFT_COL    = "Q"
$script:FIN_RIGHT_COL   = "AT"
$script:FIN_CLEAR_LEFT  = "R"
$script:FIN_CLEAR_RIGHT = "AS"

$script:PERFIL_LEFT_COL  = "E"
$script:PERFIL_RIGHT_COL = "I"

$script:HUM_COLS = @("R","S","T","U")
$script:EXC_COLS = @("V","W","X","Y")
$script:EST_COLS = @("Z","AA","AB","AC")


function Fit-MergedRangeFontToText(
  $ws,
  [string]$addr,            # ej: "J48:P50"
  [int]$baseSize = 14,      # tamaño normal
  [int]$minSize  = 12,      # solo bajar hasta 12
  [double]$padL = 2,
  [double]$padT = 1,
  [double]$padR = 2,
  [double]$padB = 1,
  [double]$slackPt = 4.0    # <-- TOLERANCIA (sube/baja si quieres)
) {
  if ($ws -eq $null -or [string]::IsNullOrWhiteSpace($addr)) { return }

  $rg = $null
  try { $rg = Unwrap-Com ($ws.Range($addr)) } catch { return }
  if ($rg -eq $null) { return }

  try { if ($rg.MergeCells) { $rg = Unwrap-Com $rg.MergeArea } } catch {}
  if ($rg -eq $null) { return }

  $cell = $null
  try { $cell = Unwrap-Com ($rg.Cells.Item(1,1)) } catch { $cell = $rg }
  if ($cell -eq $null) { return }

  $text = ""
  try { $text = [string](Scalar $cell.Value2) } catch { $text = "" }
  $text = ($text -replace "`r","").Trim()
  if ([string]::IsNullOrWhiteSpace($text)) { return }

  # Wrap sí o sí
  try { $cell.WrapText = $true } catch {}
  try { $rg.WrapText   = $true } catch {}

  # Medir en PUNTOS usando tu rect por grilla (lo más estable)
  $rc = Get-RectFromAddr $ws $addr
  $W = [double]$rc.W - ($padL + $padR)
  $H = [double]$rc.H - ($padT + $padB)

  if ($W -le 6 -or $H -le 6) { return }



  # Fuente actual (nombre/bold)
  $fontName = "Calibri"
  $isBold   = $false
  try { $fontName = [string](Scalar $cell.Font.Name) } catch { $fontName = "Calibri" }
  try { $isBold   = ([bool](Scalar $cell.Font.Bold)) } catch { $isBold = $false }

  # Siempre intentar base primero
  $startSize = $baseSize
  if ($startSize -lt $minSize) { $startSize = $minSize }

  $tmpName = "__TMP_DESCMEAS_" + ([guid]::NewGuid().ToString("N"))
  $tb = $null

  # textbox alto para medir sin “cap”
  $measureH = [Math]::Max(2000.0, $H * 25.0)

  try {
    $tb = $ws.Shapes.AddTextbox(
      $msoTextOrientationHorizontal,
      [single]([double]$rg.Left + $padL),
      [single]([double]$rg.Top  + $padT),
      [single]$W,
      [single]$measureH
    )
    $tb = Unwrap-Com $tb
    $tb.Name = $tmpName

    try { $tb.Line.Visible = $msoFalse } catch {}
    try { $tb.Fill.Visible = $msoTrue } catch {}
    try { $tb.Fill.Transparency = 1.0 } catch {}
    try { $tb.Placement = 3 } catch {}  # xlFreeFloating
    try { $tb.ZOrder($msoSendToBack) } catch {}

    $tb.TextFrame2.WordWrap = $msoTrue
    try { $tb.TextFrame2.AutoSize = 0 } catch {}
    $tb.TextFrame2.MarginLeft = 0
    $tb.TextFrame2.MarginRight = 0
    $tb.TextFrame2.MarginTop = 0
    $tb.TextFrame2.MarginBottom = 0

    $tb.TextFrame2.TextRange.Text = $text
    $tb.TextFrame2.TextRange.Font.Name = $fontName
    $tb.TextFrame2.TextRange.Font.Bold = $isBold
    $tb.TextFrame2.TextRange.Font.Fill.Solid()
    $tb.TextFrame2.TextRange.Font.Fill.ForeColor.RGB = 0

    # 👇 IMPORTANTE: quitar espacios de párrafo (Excel es más “apretado” que TextFrame2)
    try { $tb.TextFrame2.TextRange.ParagraphFormat.SpaceBefore = 0 } catch {}
    try { $tb.TextFrame2.TextRange.ParagraphFormat.SpaceAfter  = 0 } catch {}
    try { $tb.TextFrame2.TextRange.ParagraphFormat.SpaceWithin = 1 } catch {}

    # --- PRECHECK: si a 14 entra (con slack), NO tocar (se queda 14) ---
    $tb.TextFrame2.TextRange.Font.Size = $baseSize
    Start-Sleep -Milliseconds 10
    $need14 = 0.0
    try { $need14 = [double]$tb.TextFrame2.TextRange.BoundHeight } catch { $need14 = 0.0 }

    if ($need14 -le ($H + $slackPt)) {
      try { $rg.Font.Size = $baseSize } catch { try { $cell.Font.Size = $baseSize } catch {} }
      Write-Host ("DESC FIT " + $addr + " => KEEP " + $baseSize + " needH=" + [math]::Round($need14,2) + " H=" + [math]::Round($H,2) + " slack=" + $slackPt)
      return
    }

    # --- si NO entra a 14, recién ahí bajar ---
    $fit = $minSize
    $finalNeedH = $need14

    for ($sz = $startSize; $sz -ge $minSize; $sz--) {
      $tb.TextFrame2.TextRange.Font.Size = $sz
      Start-Sleep -Milliseconds 10

      $needH = 0.0
      try { $needH = [double]$tb.TextFrame2.TextRange.BoundHeight } catch { $needH = 0.0 }
      $finalNeedH = $needH

      if ($needH -le ($H + $slackPt)) {
        $fit = $sz
        break
      }
    }

    try { $rg.Font.Size = $fit } catch { try { $cell.Font.Size = $fit } catch {} }

    Write-Host ("DESC FIT " + $addr + " base=" + $baseSize + " min=" + $minSize + " fit=" + $fit + " needH=" + [math]::Round($finalNeedH,2) + " H=" + [math]::Round($H,2) + " slack=" + $slackPt)
  }
  finally {
    try { if ($tb -ne $null) { $tb.Delete() | Out-Null } } catch {}
  }
}




function AutoShrink-DescripcionBlocks(
  $wsMain, $j,
  [string]$defaultSheet,
  [int]$baseRow = $script:BASE_ROW,
  [int]$maxRow  = $script:MAX_DATA_ROW
) {
  if ($wsMain -eq $null -or $j -eq $null) { return }

  $blocks = @(Get-DescBlocksSmart $wsMain $j $defaultSheet $baseRow $maxRow $script:DESC_LEFT_COL $script:DESC_RIGHT_COL | Where-Object { $_ -ne $null })
  if ($blocks.Count -eq 0) { Write-Host "DESC SHRINK: sin bloques J:P"; return }

  $n = 0
  foreach ($b in $blocks) {
    if ($b.Sheet -ne $wsMain.Name) { continue }
    $r1 = [int]$b.R1
    $r2 = [int]$b.R2
    $addr = ("{0}{1}:{2}{3}" -f $script:DESC_LEFT_COL, $r1, $script:DESC_RIGHT_COL, $r2)

    Fit-MergedRangeFontToText $wsMain $addr 14 12 2 1 2 1
    $n++
  }

  Write-Host ("DESC SHRINK: bloques procesados=" + $n)
  try { Remove-ShapesByPrefix $wsMain "__TMP_DESCMEAS_" } catch {}
}


function Resolve-PathSmart([string]$p, [string]$baseDir) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $null }
  $p = $p.Trim()
  if ($p.StartsWith(":/")) { return $null } # recursos Qt no
  if ([System.IO.Path]::IsPathRooted($p)) { return [System.IO.Path]::GetFullPath($p) }
  return [System.IO.Path]::GetFullPath((Join-Path $baseDir $p))
}

function Test-FileLocked([string]$path) {
  try {
    $fs = [System.IO.File]::Open($path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    $fs.Close(); return $false
  } catch { return $true }
}
function Wait-FileUnlocked([string]$path, [int]$timeoutMs = 15000) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while (Test-FileLocked $path) {
    if ($sw.ElapsedMilliseconds -ge $timeoutMs) { throw "El archivo está en uso/bloqueado: $path. Cierra Excel (y cualquier EXCEL.EXE) y reintenta." }
    Start-Sleep -Milliseconds 200
  }
}
function Clear-ReadOnlyAttribute([string]$path) {
  try {
    $it = Get-Item -LiteralPath $path -ErrorAction Stop
    if (($it.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
      $it.Attributes = ($it.Attributes -bxor [System.IO.FileAttributes]::ReadOnly)
    }
  } catch {}
}

function Scalar($v) {
  while ($v -is [System.Array]) { $v = $v.GetValue(0) }
  if ($v -is [pscustomobject]) {
    $names = $v.PSObject.Properties.Name
    if ($names -contains 'text') { return $v.text }
    if ($names -contains 'value') { return $v.value }
    if ($names -contains 'currentText') { return $v.currentText }
    if ($names -contains 'date') { return $v.date }
    return $v.ToString()
  }
  return $v
}

function To-ExcelValue($v) {
  $v = Scalar $v
  if ($null -eq $v) { return $null }

  if ($v -is [bool]) { return ($(if ($v) {"true"} else {"false"})) }

  if ($v -is [double] -or $v -is [int] -or $v -is [long] -or $v -is [decimal]) { return $v }

  $s = [string]$v
  $t = $s.Trim()


  # Soportar valores tipo "48.1%" o "100 %"
  if ($t -match '^-?\d+(?:[.,]\d+)?\s*%$') {
    $num = ($t -replace '%','').Trim()
    $num = ($num -replace ',', '.')
    $d = 0.0
    if ([double]::TryParse($num,[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$d)) {
      return ($d / 100.0)
    }
  }


  if ($t -match '^-?\d+(?:[.,]\d+)?$') {
    $t2 = ($t -replace ',', '.')
    $d = 0.0
    if ([double]::TryParse($t2,[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$d)) {
      return $d
    }
  }
  return $s
}


function Unwrap-Com($o) {
  while ($o -is [System.Array]) { $o = $o.GetValue(0) }
  return $o
}


function Split-Key([string]$k, [string]$defaultSheet) {
  $k = [string]$k
  $k = $k.Trim()

  # 1) Formato: Sheet|Addr
  if ($k -match '^(.*)\|(.*)$') {
    return @{ Sheet=$matches[1].Trim(); Addr=$matches[2].Trim() }
  }

  # 2) Formato: Sheet!Addr
  if ($k -match '^\s*([^!]+)!(.+)$') {
    return @{ Sheet=$matches[1].Trim(); Addr=$matches[2].Trim() }
  }

  # 3) Formato: "Sheet Addr" (tu caso actual)
  #    ej: "xxx AU21:BC37"
  if ($k -match '^\s*([^\s]+)\s+([A-Za-z]{1,3}\d+(?::[A-Za-z]{1,3}\d+)?)\s*$') {
    return @{ Sheet=$matches[1].Trim(); Addr=$matches[2].Trim() }
  }

  # 4) Solo Addr => usa default sheet
  return @{ Sheet=$defaultSheet; Addr=$k }
}


# -------------------------
# OBSERVACIONES (rango objetivo)
# -------------------------
function Get-ObservacionesRange($wb, $wsMain) {
  if ($null -eq $wb -or $null -eq $wsMain) { return $null }

  $namesToTry = @("OBSERVACIONES","OBSERVACIONES_TXT","TXT_OBSERVACIONES","RNG_OBSERVACIONES","OBS_TXT")

  foreach ($nm in $namesToTry) {
    try {
      $rr = $wb.Names.Item($nm).RefersToRange
      $rr = Unwrap-Com $rr
      if ($rr -ne $null) { return $rr }
    } catch {}
    try {
      $rr = $wsMain.Names.Item($nm).RefersToRange
      $rr = Unwrap-Com $rr
      if ($rr -ne $null) { return $rr }
    } catch {}
  }

  # Fallback fijo (tu plantilla actual)
  try {
    $r = Unwrap-Com ($wsMain.Range($OBS_ADDR))
    try { if ($r.MergeCells) { $r = Unwrap-Com $r.MergeArea } } catch {}
    return $r
  } catch { return $null }
}



function Fix-ObservacionesHeader($wb, $wsMain) {
  if ($null -eq $wb -or $null -eq $wsMain) { return }

  $rg = Get-ObservacionesRange $wb $wsMain
  $rg = Unwrap-Com $rg
  if ($rg -eq $null) { Write-Host "OBS FIX: rango no encontrado"; return }

  # trabajar con la celda top-left
  $cell = $null
  try { $cell = Unwrap-Com ($rg.Cells.Item(1,1)) } catch { $cell = $rg }
  $cell = Unwrap-Com $cell

  $txt = ""
  try { $txt = [string](Scalar $cell.Value2) } catch { $txt = "" }
  $txt = ($txt -replace "`r","").Trim()

  if ([string]::IsNullOrWhiteSpace($txt)) { Write-Host "OBS FIX: vacío"; return }

  if ($txt -notmatch '^(?i)\s*OBSERVACIONES(\s|$)') {
    $new = "OBSERVACIONES`n$txt"
    try {
      $cell.Value2 = $new
    } catch {
      try { $cell.NumberFormat = "@" } catch {}
      $cell.Value2 = $new
    }

    try { $cell.WrapText = $true } catch {}
    try { $cell.Characters(1,13).Font.Bold = $true } catch {}

    Write-Host "OBS FIX: encabezado agregado"
  } else {
    Write-Host "OBS FIX: ya tenía encabezado"
  }
}




# --- A1 parsing para rect SIN MergeArea ---
function ColToIndex([string]$letters) {
  $letters = $letters.Trim().ToUpper()
  $n = 0
  foreach ($ch in $letters.ToCharArray()) { $n = $n*26 + ([int][char]$ch - [int][char]'A' + 1) }
  return $n
}
function Parse-A1([string]$a1) {
  $a1 = $a1.Trim().ToUpper()
  if ($a1 -notmatch '^([A-Z]+)(\d+)$') { throw "A1 inválido: $a1" }
  return @{ Col=(ColToIndex $matches[1]); Row=([int]$matches[2]) }
}
function Get-RectFromAddr($ws, [string]$addr) {
  $addr = $addr.Trim().ToUpper()
  $a = $addr; $b = $addr
  if ($addr -match ":") { $a, $b = $addr.Split(":", 2) }

  $p1 = Parse-A1 $a
  $p2 = Parse-A1 $b

  $r1 = [Math]::Min($p1.Row, $p2.Row)
  $r2 = [Math]::Max($p1.Row, $p2.Row)
  $c1 = [Math]::Min($p1.Col, $p2.Col)
  $c2 = [Math]::Max($p1.Col, $p2.Col)

  $left   = [double]($ws.Columns.Item($c1).Left)
  $top    = [double]($ws.Rows.Item($r1).Top)
  $right  = [double]($ws.Columns.Item($c2).Left + $ws.Columns.Item($c2).Width)
  $bottom = [double]($ws.Rows.Item($r2).Top + $ws.Rows.Item($r2).Height)

  $w = [Math]::Max(2.0, $right  - $left)
  $h = [Math]::Max(2.0, $bottom - $top)

  return @{ L=[single]$left; T=[single]$top; W=[single]$w; H=[single]$h }
}

function Set-Cell($ws, [string]$addr, $val) {
  $addr = [string]$addr
  if ($null -eq $val) { return }

  $r = $null
  try { $r = $ws.Range($addr) } catch { return }

  # Trabajar SIEMPRE con la celda top-left (si está mergeado)
  $cell = $r
  try {
    if ($r.MergeCells) { $cell = $r.MergeArea.Cells.Item(1,1) }
    else              { $cell = $r.Cells.Item(1,1) }
  } catch {
    try { $cell = $r.Cells.Item(1,1) } catch { $cell = $r }
  }
  $cell = Unwrap-Com $cell

  # -------------------------
  # OBSERVACIONES: asegurar encabezado
  # -------------------------
  $isObs = $false
  try {
    if (-not [string]::IsNullOrWhiteSpace($script:OBS_RANGE_ADDR)) {
      $thisAddr = $null
      try { $thisAddr = [string]$cell.Address } catch { $thisAddr = $null }
      if ($thisAddr) { $thisAddr = ($thisAddr -replace '\$','') }

      if ($thisAddr -and ($thisAddr.ToUpper() -eq $script:OBS_RANGE_ADDR.ToUpper())) {
        $isObs = $true

        $s = [string](Scalar $val)
        $s = ($s -replace "`r","").Trim()
        if ($s.Length -eq 0) { return }

        if ($s -notmatch '^(?i)\s*OBSERVACIONES(\s|$)') {
          $val = "OBSERVACIONES`n$s"
        } else {
          $val = $s
        }
      }
    }
  } catch {}

  $v2 = To-ExcelValue $val
  if ($null -eq $v2) { return }

  # Si la celda ES porcentaje y te mandan 48.1 o 100, conviértelo a 0.481 / 1.0
  try {
    $nf = [string]$cell.NumberFormat
    if ($nf -like "*%*") {
      if ($v2 -is [double] -or $v2 -is [int] -or $v2 -is [long] -or $v2 -is [decimal]) {
        if ([double]$v2 -gt 1.0) { $v2 = [double]$v2 / 100.0 }
      }
    }
  } catch {}

  # Si es número y la celda está en formato Texto, pásala a General (quita triángulo)
  try {
    if (($v2 -is [double] -or $v2 -is [int] -or $v2 -is [long] -or $v2 -is [decimal]) -and ($cell.NumberFormat -eq "@")) {
      $cell.NumberFormat = "General"
    }
  } catch {}

  # Escribir valor SIN forzar NumberFormat
  try {
    $cell.Value2 = $v2
  } catch {
    $cell.Value2 = [string]$v2
  }

  if ($isObs) {
    try { $cell.WrapText = $true } catch {}
    try { $cell.Characters(1,13).Font.Bold = $true } catch {}
  }
}





# -------------------------
# Helpers CORTES (filas + sombreado)
# -------------------------
function As-Double($v) {
  $v = Scalar $v
  if ($null -eq $v) { return $null }
  if ($v -is [double] -or $v -is [int] -or $v -is [long] -or $v -is [decimal]) { return [double]$v }
  $s = ([string]$v).Trim()
  if ($s.Length -eq 0) { return $null }
  $s = ($s -replace ',', '.')
  $d = 0.0
  if ([double]::TryParse($s,[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$d)) { return $d }
  return $null
}


function Get-Cortes($j) {
  if ($null -eq $j) { return $null }

  try {
    if ($j.PSObject.Properties.Name -contains "cortes" -and $j.cortes -ne $null) { return $j.cortes }
  } catch {}

  try {
    if ($j.PSObject.Properties.Name -contains "excel" -and $j.excel -ne $null) {
      if ($j.excel.PSObject.Properties.Name -contains "cortes" -and $j.excel.cortes -ne $null) { return $j.excel.cortes }
    }
  } catch {}

  return $null
}


function Fix-GranulometriaFormats($ws, [int]$r1=$script:BASE_ROW, [int]$r2=$script:MAX_DATA_ROW) {
  if ($ws -eq $null) { return }
  try { $ws.Range(("AI{0}:AI{1}" -f $r1,$r2)).NumberFormat = "0%" } catch {}        # max.
  try { $ws.Range(("AJ{0}:AL{1}" -f $r1,$r2)).NumberFormat = "0.0%" } catch {}      # 2mm/0.4/0.08
  try { $ws.Range(("AP{0}:AP{1}" -f $r1,$r2)).NumberFormat = "0.00%" } catch {}     # Humedad
}




function Depth-ToRow([double]$m, [int]$baseRow, [double]$rowsPerMeter) {
  $n = [int][Math]::Round($m * $rowsPerMeter, 0, [MidpointRounding]::AwayFromZero)
  return ($baseRow + $n)
}

function Merge-Vert($ws, [string]$col, [int]$r1, [int]$r2) {
  if ($r2 -lt $r1) { return }
  $addr = ("{0}{1}:{0}{2}" -f $col, $r1, $r2)
  try { $ws.Range($addr).UnMerge() | Out-Null } catch {}
  $rg = $ws.Range($addr)
  $rg.Merge() | Out-Null
  try { $rg.HorizontalAlignment = -4108 } catch {} # xlCenter
  try { $rg.VerticalAlignment   = -4108 } catch {} # xlCenter
}

function Clear-Fill($rng) {
  try { $rng.Interior.Pattern = $XL_NONE } catch {}
  try { $rng.Interior.ColorIndex = $XL_NONE } catch {}
}

function Fill-Gray50($rng) {
  try { $rng.Interior.Pattern = 1 } catch {}        # xlSolid
  try { $rng.Interior.Color = 8421504 } catch {}    # RGB(128,128,128)
}


function Apply-HES-Shading(
  $ws, $j,
  [int]$baseRow = $script:BASE_ROW,
  [double]$rowsPerMeter = $script:ROWS_PER_METER,
  [int]$maxRow = $script:MAX_DATA_ROW
) {

  $cortes = Get-Cortes $j
  if ($null -eq $cortes) {
    Write-Host "HES: no hay cortes en JSON (ni j.cortes ni j.excel.cortes)."
    return
  }

  foreach ($c in $cortes) {
    if ($null -eq $c) { continue }

    $combo = $null
    try { $combo = $c.combo_boxes } catch { $combo = $null }

    $de = $null; $a = $null
    if ($combo -ne $null) {
      try { $de = As-Double $combo.txtDE } catch {}
      try { $a  = As-Double $combo.txtA  } catch {}
    }

    if ($null -eq $de -or $null -eq $a) { continue }
    if ($a -le $de) { continue }

    $r1 = Depth-ToRow $de $baseRow $rowsPerMeter
    $r2 = (Depth-ToRow $a $baseRow $rowsPerMeter) - 1

    if ($r1 -lt $baseRow) { $r1 = $baseRow }
    if ($r2 -gt $maxRow)  { $r2 = $maxRow }
    if ($r2 -lt $r1) { continue }

  foreach ($col in ($script:HUM_COLS + $script:EXC_COLS + $script:EST_COLS)) {
    Merge-Vert $ws $col $r1 $r2
  }

    Clear-Fill ($ws.Range(("R{0}:U{1}" -f $r1,$r2)))
    Clear-Fill ($ws.Range(("V{0}:Y{1}" -f $r1,$r2)))
    Clear-Fill ($ws.Range(("Z{0}:AC{1}" -f $r1,$r2)))

    $humIdx = $null; $excIdx = $null; $estIdx = $null
    try { $humIdx = [int](Scalar $combo.cbHumedad.index) } catch {}
    try { $excIdx = [int](Scalar $combo.cbExcavabilidad.index) } catch {}
    try { $estIdx = [int](Scalar $combo.cbEstabilidad.index) } catch {}

    $humCols = $script:HUM_COLS
    $excCols = $script:EXC_COLS
    $estCols = $script:EST_COLS

    if ($humIdx -ge 1 -and $humIdx -le $humCols.Count) {
      $col = $humCols[$humIdx-1]
      Fill-Gray50 ($ws.Range(("{0}{1}:{0}{2}" -f $col, $r1, $r2)))
    }
    if ($excIdx -ge 1 -and $excIdx -le $excCols.Count) {
      $col = $excCols[$excIdx-1]
      Fill-Gray50 ($ws.Range(("{0}{1}:{0}{2}" -f $col, $r1, $r2)))
    }
    if ($estIdx -ge 1 -and $estIdx -le $estCols.Count) {
      $col = $estCols[$estIdx-1]
      Fill-Gray50 ($ws.Range(("{0}{1}:{0}{2}" -f $col, $r1, $r2)))
    }

    # -------------------------------------------------
    # BORDES: separador inferior de corte + split SUCS
    # -------------------------------------------------

    # 1) split vertical SOLO si SUCS es compuesto (GC-GM, etc.)
    $sucsText = Get-CorteSucsText $ws $c $r1 $r2
    $codes = @(Get-SucsCodes $sucsText)
    Set-SucsSplitBorder $ws $r1 $r2 ($codes.Count -ge 2) 2

    # 2) separador inferior al final del corte (incluye SUCS + todo lo demás)
    Set-CorteBottomBorder $ws $r1 $r2 "E" "AP" 2
  }

  Write-Host "HES: OK"
}


# -------------------------
# FIN DE LA CALICATA
# -------------------------
function Clear-RangeFormat($rng) {
  if ($rng -eq $null) { return }
  foreach ($i in @($XL_DIAGONAL_DOWN,$XL_DIAGONAL_UP,$XL_EDGE_LEFT,$XL_EDGE_TOP,$XL_EDGE_BOTTOM,$XL_EDGE_RIGHT,$XL_INSIDE_VERTICAL,$XL_INSIDE_HORIZONTAL)) {
    try { $rng.Borders.Item($i).LineStyle = $XL_NONE } catch {}
  }
  try { $rng.Interior.Pattern = $XL_NONE } catch {}
  try { $rng.Interior.ColorIndex = $XL_NONE } catch {}
}

function Remove-DefinedNameSafe($wb, $ws, [string]$name) {
  if ([string]::IsNullOrWhiteSpace($name)) { return }
  try { $ws.Names.Item($name).Delete() } catch {}
  try { $wb.Names.Item($name).Delete() } catch {}
}

function Get-LastCorteEndRow($j, [int]$baseRow, [double]$rowsPerMeter, [int]$maxEndRow) {
  $max = $baseRow - 1

  $cortes = Get-Cortes $j
  if ($null -ne $cortes) {
    foreach ($c in $cortes) {
      $a = $null
      try { $a = As-Double $c.combo_boxes.txtA } catch {}
      if ($a -eq $null) { continue }
      $end = (Depth-ToRow $a $baseRow $rowsPerMeter) - 1
      if ($end -gt $max) { $max = $end }
    }
  }

  if ($max -lt ($baseRow - 1)) { $max = $baseRow - 1 }
  if ($max -gt $maxEndRow) { $max = $maxEndRow }
  return $max
}


function Set-Border($rng, [int]$edge, [int]$weight=2) {
  try {
    $b = $rng.Borders.Item($edge)
    $b.LineStyle = 1
    $b.Weight    = $weight
    try { $b.Color = 0 } catch {}
  } catch {}
}


function Clear-BorderEdge($rng, [int]$edge) {
  try {
    $b = $rng.Borders.Item($edge)
    $b.LineStyle = $XL_NONE
  } catch {}
}




# Borde inferior del corte (robusto con merges: se aplica al rango completo r1:r2)
function Set-CorteBottomBorder($ws, [int]$r1, [int]$r2, [string]$fromCol="E", [string]$toCol="AP", [int]$weight=2) {
  if ($ws -eq $null) { return }
  if ($r2 -lt $r1) { return }
  $addr = ("{0}{1}:{2}{3}" -f $fromCol, $r1, $toCol, $r2)
  $rg = $ws.Range($addr)
  Set-Border $rg $XL_EDGE_BOTTOM $weight
}

# Borde vertical de separación para SUCS compuesto: línea entre G | H
function Set-SucsSplitBorder($ws, [int]$r1, [int]$r2, [bool]$enable, [int]$weight=2) {
  if ($ws -eq $null) { return }
  if ($r2 -lt $r1) { return }

  $rngL = $ws.Range(("E{0}:G{1}" -f $r1,$r2))  # bloque izquierdo
  $rngR = $ws.Range(("H{0}:I{1}" -f $r1,$r2))  # bloque derecho

  if ($enable) {
    # línea sólida a la derecha de G (y también a la izquierda de H para asegurar que se vea)
    Set-Border $rngL $XL_EDGE_RIGHT $weight
    Set-Border $rngR $XL_EDGE_LEFT  $weight
  } else {
    # si NO es compuesto, quita esa línea (por si quedó de un export anterior)
    Clear-BorderEdge $rngL $XL_EDGE_RIGHT
    Clear-BorderEdge $rngR $XL_EDGE_LEFT
  }
}


function Create-FinDeCalicata($ws, $j, $wb, [int]$maxClearRow = $script:MAX_DATA_ROW) {
  $rowsPerMeter = $script:ROWS_PER_METER
  $baseRow      = $script:BASE_ROW
  $finMaxRow = $maxClearRow + 1

  Remove-DefinedNameSafe $wb $ws "FIN_CALICATA"

  $lastEnd = Get-LastCorteEndRow $j $baseRow $rowsPerMeter $maxClearRow
  $finRow  = $lastEnd + 1

  if ($finRow -lt $baseRow)   { $finRow = $baseRow }
  if ($finRow -gt $finMaxRow) { $finRow = $finMaxRow }

  $isAtLimit = ($finRow -eq $finMaxRow)

  $finAddr = ("{0}{1}:{2}{1}" -f $script:FIN_LEFT_COL, $finRow, $script:FIN_RIGHT_COL)
  $finRng  = $ws.Range($finAddr)

  # 1) Descombinar y limpiar contenido
  try { $finRng.UnMerge() | Out-Null } catch {}
  try { $finRng.ClearContents() } catch {}

  # 2) Limpiar SOLO lo que controla FIN
  foreach ($i in @(
    $XL_DIAGONAL_DOWN, $XL_DIAGONAL_UP,
    $XL_EDGE_TOP,
    $XL_INSIDE_VERTICAL, $XL_INSIDE_HORIZONTAL
  )) {
    try { $finRng.Borders.Item($i).LineStyle = $XL_NONE } catch {}
  }

  if (-not $isAtLimit) {
    try { $finRng.Borders.Item($XL_EDGE_BOTTOM).LineStyle = $XL_NONE } catch {}
  }

  try { $finRng.Interior.Pattern = $XL_NONE } catch {}
  try { $finRng.Interior.ColorIndex = $XL_NONE } catch {}

  # 3) Limpiar la zona de abajo ANTES de dibujar bordes de FIN
  $startClear = $finRow + 1
  if ($startClear -le $maxClearRow) {
    $clr = $ws.Range(("{0}{1}:{2}{3}" -f $script:FIN_CLEAR_LEFT, $startClear, $script:FIN_CLEAR_RIGHT, $maxClearRow))
    Clear-RangeFormat $clr
  }

  # 4) Dibujar bordes de FIN cuando ya no habrá más limpieza debajo
  Set-Border $finRng $XL_EDGE_TOP 2

  if (-not $isAtLimit) {
    Set-Border $finRng $XL_EDGE_BOTTOM 2
  }

  # 5) Recién ahora hacer merge
  try { $finRng.Merge() | Out-Null } catch {}

  # 6) Texto y formato
  try { $finRng.Value2 = "FIN DE LA CALICATA" } catch {}
  try { $finRng.HorizontalAlignment = -4108 } catch {}
  try { $finRng.VerticalAlignment   = -4108 } catch {}
  try { $finRng.Font.Bold = $true } catch {}
  try { $finRng.Font.Size = 14 } catch {}

  Write-Host ("FIN OK: finRow=" + $finRow +
            " | finRange=" + $finAddr +
            " | atLimit=" + $isAtLimit +
            " | clear=" + $script:FIN_CLEAR_LEFT + ($finRow+1) + ":" + $script:FIN_CLEAR_RIGHT + $maxClearRow)
}

# -------------------------
# Imágenes (logos/fotos) + helper
# -------------------------
function Get-ImageSize([string]$path) {
  $img = $null
  try {
    $img = [System.Drawing.Image]::FromFile($path)

    $pxW = [double]$img.Width
    $pxH = [double]$img.Height

    $dpiX = [double]$img.HorizontalResolution
    $dpiY = [double]$img.VerticalResolution

    # fallback típico si viene 0/1 o valores raros
    if ($dpiX -le 1) { $dpiX = 96.0 }
    if ($dpiY -le 1) { $dpiY = 96.0 }

    # Excel usa puntos (pt). 1 in = 72 pt
    $ptW = $pxW * 72.0 / $dpiX
    $ptH = $pxH * 72.0 / $dpiY

    return @{ W=[double]$ptW; H=[double]$ptH; DpiX=$dpiX; DpiY=$dpiY; PxW=$pxW; PxH=$pxH }
  }
  finally {
    if ($img -ne $null) { $img.Dispose() }
  }
}


function Is-SingleCellAddr([string]$addr) {
  $a = ([string]$addr).Trim()
  return ($a -notmatch ":")
}

function Get-RectSmart($ws, [string]$addr) {
  $a = ([string]$addr).Trim()
  if ([string]::IsNullOrWhiteSpace($a)) { throw "Addr vacío" }

  # RANGOS (A1:B2): usar SIEMPRE cálculo por grilla (estable incluso con merges)
  if (-not (Is-SingleCellAddr $a)) {
    return Get-RectFromAddr $ws $a
  }

  # CELDA ÚNICA: si está mergeada, usar MergeArea
  $rng = $ws.Range($a)
  while ($rng -is [System.Array]) { $rng = $rng.GetValue(0) }
  try { if ($rng.MergeCells) { $rng = $rng.MergeArea } } catch {}
  while ($rng -is [System.Array]) { $rng = $rng.GetValue(0) }

  return @{
    L=[single]([double]$rng.Left)
    T=[single]([double]$rng.Top)
    W=[single]([double]$rng.Width)
    H=[single]([double]$rng.Height)
  }
}


function Upsert-MeasureBox(
  $ws,
  [string]$addrPerfil,    # Ej: "E22:I31"
  [string]$text,          # Ej: "0.50"
  [string]$shapeName,     # Ej: "MEAS_PF_1"
  [double]$boxW = 32.0,
  [double]$boxH = 14.5
) {
  try {
    if ($ws -eq $null) { return }

    # borrar si ya existe
    try { $ws.Shapes.Item($shapeName).Delete() | Out-Null } catch {}

    # rect del perfil (E:I del corte)
    $rc = Get-RectFromAddr $ws $addrPerfil

    # centro
    $L = [double]$rc.L + ([double]$rc.W - $boxW) / 2.0
    $T = [double]$rc.T + ([double]$rc.H - $boxH) / 2.0

    # clamp para que no se salga del bloque
    $L = [Math]::Max([double]$rc.L + 1.0, [Math]::Min([double]$rc.L + [double]$rc.W - $boxW - 1.0, $L))
    $T = [Math]::Max([double]$rc.T + 1.0, [Math]::Min([double]$rc.T + [double]$rc.H - $boxH - 1.0, $T))

    Write-Host ("MEAS " + $shapeName + " boxW=" + $boxW + " boxH=" + $boxH)


    $sh = $ws.Shapes.AddShape(
      $msoShapeRectangle,
      [single]([math]::Round($L,2)),
      [single]([math]::Round($T,2)),
      [single]([math]::Round($boxW,2)),
      [single]([math]::Round($boxH,2))
    )
    while ($sh -is [System.Array]) { $sh = $sh.GetValue(0) }

    $sh.Name = $shapeName

    # estilo como tu “formato” (caja blanca con borde negro)
    try { $sh.Fill.Visible = $msoTrue } catch {}
    try { $sh.Fill.ForeColor.RGB = 16777215 } catch {}   # blanco
    try { $sh.Line.Visible = $msoTrue } catch {}
    try { $sh.Line.ForeColor.RGB = 0 } catch {}          # negro
    try { $sh.Line.Weight = 0.5 } catch {}
    try { $sh.Shadow.Visible = $msoFalse } catch {}

    # texto centrado
    try {
      $sh.TextFrame2.TextRange.Text = $text

      # Color de fuente negro
      $sh.TextFrame2.TextRange.Font.Fill.Solid()
      $sh.TextFrame2.TextRange.Font.Fill.ForeColor.RGB = 0   # negro
      $sh.TextFrame2.TextRange.ParagraphFormat.Alignment = $msoAlignCenter
      $sh.TextFrame2.VerticalAnchor = $msoAnchorMiddle
      $sh.TextFrame2.TextRange.Font.Size = 9
      $sh.TextFrame2.TextRange.Font.Name = "Calibri"
    } catch {
      try { $sh.TextFrame.Characters().Text = $text } catch {}
    }

    try { $sh.Placement = 1 } catch {}   # xlMoveAndSize
    try { $sh.ZOrder($msoBringToFront) } catch {}
  }
  catch {
    Write-Host ("MEASURE BOX ERROR " + $shapeName + ": " + $_.Exception.Message)
  }
}

function Apply-PerfilMedidasBoxes(
  $wsMain, $j,
  [int]$baseRow = $script:BASE_ROW,
  [double]$rowsPerMeter = $script:ROWS_PER_METER,
  [int]$maxRow = $script:MAX_DATA_ROW
) {
  if ($wsMain -eq $null -or $j -eq $null) { return }

  Remove-ShapesByPrefix $wsMain "MEAS_PF_"

  $cortes = Get-Cortes $j
  if ($null -eq $cortes) { Write-Host "MEDIDAS: no hay cortes"; return }

  $idx = 0

  foreach ($c in $cortes) {
    $de = $null
    $a  = $null
    try { $de = As-Double $c.combo_boxes.txtDE } catch {}
    try { $a  = As-Double $c.combo_boxes.txtA  } catch {}

    if ($de -eq $null -or $a -eq $null) { continue }
    if ($a -le $de) { continue }

    $r1 = Depth-ToRow $de $baseRow $rowsPerMeter
    $r2 = (Depth-ToRow $a $baseRow $rowsPerMeter) - 1

    if ($r1 -lt $baseRow) { $r1 = $baseRow }
    if ($r2 -gt $maxRow)  { $r2 = $maxRow }
    if ($r2 -lt $r1) { continue }

    $idx++

    $esp = [Math]::Round(([double]$a - [double]$de), 2)
    $txt = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:0.00}", $esp)

    $addr = ("{0}{1}:{2}{3}" -f $script:PERFIL_LEFT_COL, $r1, $script:PERFIL_RIGHT_COL, $r2)

    Upsert-MeasureBox $wsMain $addr $txt ("MEAS_PF_{0}" -f $idx) 32 14.5
  }

  Write-Host ("MEDIDAS: boxes creados=" + $idx)
}


function Shrink-ShapeCenter($sh, [double]$factor = 0.99) {
  $sh = Unwrap-Com $sh
  if ($null -eq $sh) { return }

  $w0 = [double]$sh.Width
  $h0 = [double]$sh.Height
  if ($w0 -le 2 -or $h0 -le 2) { return }

  $w1 = [Math]::Max(2.0, $w0 * $factor)
  $h1 = [Math]::Max(2.0, $h0 * $factor)

  $dx = ($w0 - $w1) / 2.0
  $dy = ($h0 - $h1) / 2.0

  try { $sh.Left  = [double]$sh.Left + $dx } catch {}
  try { $sh.Top   = [double]$sh.Top  + $dy } catch {}
  try { $sh.Width = $w1 } catch {}
  try { $sh.Height= $h1 } catch {}
}

function Shrink-PicturesByPrefix($ws, [string]$prefix = "APP_IMG_", [double]$factor = 0.99) {
  if ($ws -eq $null) { return }
  try {
    for ($i = 1; $i -le $ws.Shapes.Count; $i++) {
      $sh = Unwrap-Com ($ws.Shapes.Item($i))
      $nm = ""
      try { $nm = [string]$sh.Name } catch { $nm = "" }

      if ($nm.StartsWith($prefix)) {
        Shrink-ShapeCenter $sh $factor
      }
    }
  } catch {}
}

function Nudge-ShapeByName($ws, [string]$shapeName, [double]$dx=0, [double]$dy=0) {
  if ($ws -eq $null -or [string]::IsNullOrWhiteSpace($shapeName)) { return }
  try {
    $sh = Unwrap-Com ($ws.Shapes.Item($shapeName))
    if ($null -eq $sh) { return }
    if ($dx -ne 0) { try { $sh.Left = [double]$sh.Left + $dx } catch {} }
    if ($dy -ne 0) { try { $sh.Top  = [double]$sh.Top  + $dy } catch {} }
  } catch {}
}

function Upsert-Picture(
  $ws,
  [string]$addr,
  [string]$imgPath,
  [string]$shapeName,
  [string]$mode  = "fit",        # "fit" | "stretch"
  [string]$align = "center",     # "center" | "topleft" | "leftcenter" | "topcenter"
  [int]$zOrder   = 0,            # 0=msoBringToFront, 1=msoSendToBack
  [double]$padL  = 0,
  [double]$padT  = 0,
  [double]$padR  = 0,
  [double]$padB  = 0,
  [int]$placement = 1,           # 1=xlMoveAndSize, 3=xlFreeFloating
  [double]$nudgeX = 0,           # empujón fino (derecha +)
  [double]$nudgeY = 0            # empujón fino (abajo +)
) {
  try {
    if ([string]::IsNullOrWhiteSpace($imgPath)) { $global:PicSkipped++; return }
    $imgPath = $imgPath.Trim()

    if (!(Test-Path -LiteralPath $imgPath)) {
      $global:PicSkipped++
      Write-Host ("PIC SKIP (no existe): " + $imgPath)
      return
    }

    try { $ws.Shapes.Item($shapeName).Delete() | Out-Null } catch {}

    function Get-InnerRect {
      $rc = Get-RectSmart $ws $addr
      $L2 = [double]$rc.L + $padL + $nudgeX
      $T2 = [double]$rc.T + $padT + $nudgeY
      $W2 = [double]$rc.W - ($padL + $padR)
      $H2 = [double]$rc.H - ($padT + $padB)
      $W2 = [Math]::Max(4.0, $W2)
      $H2 = [Math]::Max(4.0, $H2)
      return @{ L=$L2; T=$T2; W=$W2; H=$H2 }
    }

    $inner = Get-InnerRect
    if ($inner.W -le 5 -or $inner.H -le 5) {
      $global:PicSkipped++
      Write-Host ("PIC SKIP (rect pequeño) " + $addr)
      return
    }

    $sz = Get-ImageSize $imgPath
    if ($sz.W -le 0 -or $sz.H -le 0) { $global:PicSkipped++; return }

    # Calcular geom final
    $finalW = $inner.W; $finalH = $inner.H
    $finalL = $inner.L; $finalT = $inner.T

    if ($mode -eq "fit") {
      $scaleW = $inner.W / $sz.W
      $scaleH = $inner.H / $sz.H
      $scale  = [Math]::Min($scaleW, $scaleH)

      $finalW = [double]($sz.W * $scale)
      $finalH = [double]($sz.H * $scale)

      switch ($align.ToLower()) {
        "topleft"     { $finalL = $inner.L; $finalT = $inner.T }
        "leftcenter"  { $finalL = $inner.L; $finalT = $inner.T + (($inner.H - $finalH) / 2.0) }
        "topcenter"   { $finalL = $inner.L + (($inner.W - $finalW) / 2.0); $finalT = $inner.T }
        default       { $finalL = $inner.L + (($inner.W - $finalW) / 2.0); $finalT = $inner.T + (($inner.H - $finalH) / 2.0) }
      }
    } else {
      # stretch
      $finalW = $inner.W; $finalH = $inner.H
      $finalL = $inner.L; $finalT = $inner.T
    }

    # Insertar
    $pic = $ws.Shapes.AddPicture(
      [string]$imgPath,
      0,   # LinkToFile
      -1,  # SaveWithDocument
      [single]([math]::Round($finalL,2)),
      [single]([math]::Round($finalT,2)),
      [single]([math]::Round($finalW,2)),
      [single]([math]::Round($finalH,2))
    )
    while ($pic -is [System.Array]) { $pic = $pic.GetValue(0) }
    if ($null -eq $pic) { throw "AddPicture devolvió null." }

    $pic.Name = $shapeName

    # Bloquear o no aspecto
    if ($mode -eq "fit") { try { $pic.LockAspectRatio = -1 } catch {} }
    else                 { try { $pic.LockAspectRatio = 0 } catch {} }

    # Placement primero (Excel a veces reubica)
    try { $pic.Placement = $placement } catch {}

    # --- RECENTRADO FINAL (la clave) ---
    # Recalcular rect real una vez que Excel ya “acomodó” la forma.
    $inner2 = Get-InnerRect

    if ($mode -eq "fit") {
      $scaleW = $inner2.W / $sz.W
      $scaleH = $inner2.H / $sz.H
      $scale  = [Math]::Min($scaleW, $scaleH)

      $w = [double]($sz.W * $scale)
      $h = [double]($sz.H * $scale)

      try { $pic.Width  = [single]([math]::Round($w,2)) } catch {}
      try { $pic.Height = [single]([math]::Round($h,2)) } catch {}

      $L = $inner2.L; $T = $inner2.T
      switch ($align.ToLower()) {
        "topleft"     { }
        "leftcenter"  { $T = $inner2.T + (($inner2.H - $h) / 2.0) }
        "topcenter"   { $L = $inner2.L + (($inner2.W - $w) / 2.0) }
        default       { $L = $inner2.L + (($inner2.W - $w) / 2.0); $T = $inner2.T + (($inner2.H - $h) / 2.0) }
      }

      try { $pic.Left = [single]([math]::Round($L,2)) } catch {}
      try { $pic.Top  = [single]([math]::Round($T,2)) } catch {}
    }
    else {
      try { $pic.Left   = [single]([math]::Round($inner2.L,2)) } catch {}
      try { $pic.Top    = [single]([math]::Round($inner2.T,2)) } catch {}
      try { $pic.Width  = [single]([math]::Round($inner2.W,2)) } catch {}
      try { $pic.Height = [single]([math]::Round($inner2.H,2)) } catch {}
    }

    try { $pic.ZOrder($zOrder) } catch {}

    $global:PicInserted++
    Write-Host ("PIC OK: " + $addr + " pad=[$padL,$padT,$padR,$padB] nudge=[$nudgeX,$nudgeY] mode=" + $mode + " align=" + $align + " place=" + $placement)
  }
  catch {
    $global:PicErrors++
    Write-Host ("PIC ERROR en " + $addr + ": " + $_.Exception.Message)
  }
}



function Get-DescBlocksFromJsonMerges(
  $j,
  [string]$defaultSheet,
  [int]$baseRow = $script:BASE_ROW,
  [int]$maxRow  = $script:MAX_DATA_ROW,
  [string]$descLeftCol  = $script:DESC_LEFT_COL,
  [string]$descRightCol = $script:DESC_RIGHT_COL
) {
  $blocks = @()
  $mergesObj = $null
  try { $mergesObj = $j.excel.merges } catch {}
  if ($mergesObj -eq $null) { return $blocks }

  $cL = ColToIndex $descLeftCol
  $cR = ColToIndex $descRightCol

  foreach ($p in $mergesObj.PSObject.Properties) {
    $k = Split-Key $p.Name $defaultSheet
    $addr = ([string]$k.Addr).Trim().ToUpper()
    $addr = ($addr -replace '\$','')
    if ($addr -notmatch ":") { continue }

    $a,$b = $addr.Split(":",2)
    try { $p1 = Parse-A1 $a; $p2 = Parse-A1 $b } catch { continue }

    $r1 = [Math]::Min($p1.Row,$p2.Row)
    $r2 = [Math]::Max($p1.Row,$p2.Row)
    $c1 = [Math]::Min($p1.Col,$p2.Col)
    $c2 = [Math]::Max($p1.Col,$p2.Col)

    if ($r2 -lt $baseRow -or $r1 -gt $maxRow) { continue }
    if ($c1 -ne $cL) { continue }
    if ($c2 -lt $cR) { continue }

    $blocks += [pscustomobject]@{ Sheet=$k.Sheet; R1=$r1; R2=$r2 }
  }

  $blocks = $blocks | Sort-Object Sheet,R1,R2 -Unique
  return $blocks
}



function Get-DescBlocksFromSheetMerges(
  $wsMain,
  [int]$baseRow = $script:BASE_ROW,
  [int]$maxRow  = $script:MAX_DATA_ROW,
  [string]$descLeftCol  = $script:DESC_LEFT_COL,
  [string]$descRightCol = $script:DESC_RIGHT_COL
) {
  $blocks = @()
  if ($wsMain -eq $null) { return $blocks }

  $cL = ColToIndex $descLeftCol
  $cR = ColToIndex $descRightCol
  $seen = @{}

  for ($r = $baseRow; $r -le $maxRow; $r++) {
    $cell = $null
    try { $cell = Unwrap-Com ($wsMain.Cells.Item($r, $cL)) } catch { $cell = $null }
    if ($cell -eq $null) { continue }

    $mc = $null
    try { $mc = Scalar $cell.MergeCells } catch { $mc = $null }
    $isMerged = ($mc -eq $true -or $mc -eq -1)
    if (-not $isMerged) { continue }

    $ma = $null
    try { $ma = Unwrap-Com $cell.MergeArea } catch { $ma = $null }
    if ($ma -eq $null) { continue }

    $addr = ""
    try { $addr = ([string]$ma.Address -replace '\$','') } catch { $addr = "" }
    if ([string]::IsNullOrWhiteSpace($addr)) { continue }
    if ($seen.ContainsKey($addr)) { continue }
    $seen[$addr] = $true

    $r1 = 0; $r2 = 0; $col1 = 0; $col2 = 0
    try { $r1 = [int]$ma.Row; $r2 = $r1 + [int]$ma.Rows.Count - 1 } catch { continue }
    try { $col1 = [int]$ma.Column; $col2 = $col1 + [int]$ma.Columns.Count - 1 } catch { continue }

    if ($r2 -lt $baseRow -or $r1 -gt $maxRow) { continue }
    if ($col1 -ne $cL) { continue }
    if ($col2 -lt $cR) { continue }

    $blocks += [pscustomobject]@{ Sheet=$wsMain.Name; R1=$r1; R2=$r2 }
  }

  $blocks = $blocks | Sort-Object R1,R2 -Unique
  return $blocks
}


function Get-DescBlocksSmart(
  $wsMain,
  $j,
  [string]$defaultSheet,
  [int]$baseRow = $script:BASE_ROW,
  [int]$maxRow  = $script:MAX_DATA_ROW,
  [string]$descLeftCol  = $script:DESC_LEFT_COL,
  [string]$descRightCol = $script:DESC_RIGHT_COL
) {
  $blocks = @()
  try { $blocks = @(Get-DescBlocksFromJsonMerges $j $defaultSheet $baseRow $maxRow $descLeftCol $descRightCol) } catch { $blocks = @() }

  if ($blocks.Count -eq 0) {
    $blocks = @(Get-DescBlocksFromSheetMerges $wsMain $baseRow $maxRow $descLeftCol $descRightCol)
    if ($blocks.Count -gt 0) {
      Write-Host ("DESC BLOCKS: usando merges de la PLANTILLA (sheet) -> " + $blocks.Count)
    }
  } else {
    Write-Host ("DESC BLOCKS: usando j.excel.merges -> " + $blocks.Count)
  }

  return $blocks
}




function Get-SucsTextFromRows($wsMain, [int]$r1, [int]$r2, [string]$col=$script:SUCS_COL) {
  for ($r=$r1; $r -le $r2; $r++) {
    $v = $null
    try { $v = $wsMain.Range(("{0}{1}" -f $col,$r)).Value2 } catch { $v = $null }
    $t = [string](Scalar $v)
    if (-not [string]::IsNullOrWhiteSpace($t)) { return $t.Trim() }
  }
  return ""
}




# -------------------------
# PERFIL (TRAMAS) - FIX IMPORTANTE: leer SUCS en el rango, no solo rowStart
# -------------------------

function Remove-ShapesByPrefix($ws, [string]$prefix) {
  if ($ws -eq $null -or [string]::IsNullOrWhiteSpace($prefix)) { return }
  try {
    for ($i = $ws.Shapes.Count; $i -ge 1; $i--) {
      $nm = ""
      try { $nm = [string]$ws.Shapes.Item($i).Name } catch { $nm = "" }
      if ($nm.StartsWith($prefix)) {
        try { $ws.Shapes.Item($i).Delete() | Out-Null } catch {}
      }
    }
  } catch {}
}

function Ensure-SheetVisible([object]$ws) {
  $old = $null
  try { $old = [int]$ws.Visible } catch { $old = $null }
  try { if ($old -ne $null -and $old -ne -1) { $ws.Visible = -1 } } catch {}
  try { $ws.Activate() | Out-Null } catch {}
  return $old
}
function Restore-SheetVisible([object]$ws, $oldVisible) {
  if ($oldVisible -eq $null) { return }
  try { $ws.Visible = $oldVisible } catch {}
}






function Normalize-Token([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return "" }
  return (([string]$s).ToUpper() -replace '[^A-Z0-9]', '')
}

function Find-SucsShapeName($wsSucs, [string]$codeText) {
  if ($wsSucs -eq $null) { return $null }
  $codeNorm = Normalize-Token $codeText
  if ([string]::IsNullOrWhiteSpace($codeNorm)) { return $null }

  $best = $null
  $bestScore = 999999
  $bestLen = 999999

  try {
    for ($i = 1; $i -le $wsSucs.Shapes.Count; $i++) {
      $nm = ""
      try { $nm = [string]$wsSucs.Shapes.Item($i).Name } catch { $nm = "" }
      if ([string]::IsNullOrWhiteSpace($nm)) { continue }

      $nmNorm = Normalize-Token $nm
      if ([string]::IsNullOrWhiteSpace($nmNorm)) { continue }

      $score = $null
      if ($nmNorm -eq ("SUCS" + $codeNorm)) { $score = 0 }
      elseif ($nmNorm.EndsWith($codeNorm))   { $score = 1 }
      elseif ($nmNorm.Contains($codeNorm))   { $score = 2 }

      if ($score -ne $null) {
        if ($score -lt $bestScore -or ($score -eq $bestScore -and $nmNorm.Length -lt $bestLen)) {
          $best = $nm
          $bestScore = $score
          $bestLen = $nmNorm.Length
        }
      }
    }
  } catch {}

  return $best
}

# FIX: busca SUCS en TODAS las filas del intervalo (AH rowStart..rowEnd)
function Get-CorteSucsText($wsMain, $c, [int]$rowStart, [int]$rowEnd) {

  # 1) Desde JSON si existe
  $s = ""
  try { $s = [string](Scalar $c.line_edits.txtSUCS) } catch { $s = "" }
  $s = $s.Trim()
  if ($s.Length -gt 0) { return $s }

  # 2) Escanear columna AH dentro del rango del corte (por si el valor está en una fila intermedia)
  try {
    for ($r = $rowStart; $r -le $rowEnd; $r++) {
      $v = $null
      try { $v = $wsMain.Range(("AH{0}" -f $r)).Value2 } catch { $v = $null }
      $t = [string](Scalar $v)
      if (-not [string]::IsNullOrWhiteSpace($t)) {
        return $t.Trim()
      }
    }
  } catch {}

  return ""
}

function SucsPngPath([string]$code) {
  $c = ([string]$code).Trim().ToUpper()
  if ([string]::IsNullOrWhiteSpace($c)) { return $null }

  # 1) exacto: "GC.png"
  $p = Join-Path $script:SucsDir ($c + ".png")
  if (Test-Path -LiteralPath $p) { return $p }

  # 2) tolerante: buscar coincidencias en el nombre
  try {
    $hit = Get-ChildItem -LiteralPath $script:SucsDir -Filter "*.png" -ErrorAction SilentlyContinue |
      Where-Object {
        ($_.BaseName.ToUpper() -replace '[^A-Z0-9]','') -like ("*" + ($c -replace '[^A-Z0-9]','') + "*")
      } |
      Select-Object -First 1
    if ($hit) { return $hit.FullName }
  } catch {}

  return $null
}



function Get-SucsCodes([string]$sucsText) {
  $t = ($sucsText.Trim().ToUpper() -replace '\s+', '')
  if ($t.Length -eq 0) { return @() }
  $parts = @($t -split '[-/]' | Where-Object { $_ -match '^[A-Z]{1,2}$' })
  if ($parts.Count -eq 0) {
    $m = [regex]::Matches($t, '[A-Z]{1,2}')
    $parts = @()
    foreach ($x in $m) { $parts += $x.Value }
    $parts = @($parts | Select-Object -First 2)
  }
  return $parts
}

function Export-SucsShapeToPng($wsSucs, [string]$shapeName, [string]$pngPath) {
  $oldVis = Ensure-SheetVisible $wsSucs
  try {
    $sh = $null
    try { $sh = $wsSucs.Shapes.Item($shapeName) } catch { $sh = $null }
    if ($sh -eq $null) { throw "No existe shape '$shapeName' en la hoja 'sucs'." }

    try { Remove-Item -LiteralPath $pngPath -ErrorAction SilentlyContinue } catch {}

    try { $sh.Export($pngPath, "PNG") } catch { $sh.Export($pngPath) }

    if (!(Test-Path -LiteralPath $pngPath)) { throw "No se generó el PNG exportando '$shapeName'." }
    try {
      $fi = Get-Item -LiteralPath $pngPath -ErrorAction Stop
      if ($fi.Length -lt 200) { throw "PNG vacío/pequeño para '$shapeName' (bytes=$($fi.Length))." }
    } catch { throw }
  }
  finally {
    Restore-SheetVisible $wsSucs $oldVis
  }
}

function Paste-SucsShapeToRange(
  $wsMain, $wsSucs,
  [string]$srcShapeName,
  [string]$addr,
  [string]$shapeName,
  [double]$padL = 4,
  [double]$padT = 8,
  [double]$padR = 2,
  [double]$padB = 2,
  [double]$nudgeX = 0,
  [double]$nudgeY = 0,
  [int]$zOrder = $msoSendToBack
) {
  $oldVis = Ensure-SheetVisible $wsSucs
  try {
    $src = $null
    try { $src = $wsSucs.Shapes.Item($srcShapeName) } catch { $src = $null }
    if ($src -eq $null) { throw "No existe shape '$srcShapeName' para fallback-paste." }

    try { $wsMain.Shapes.Item($shapeName).Delete() | Out-Null } catch {}

    $rc = Get-RectSmart $wsMain $addr

    # aplicar padding y mantener dentro del rect
    $L = [double]$rc.L + $padL + $nudgeX
    $T = [double]$rc.T + $padT + $nudgeY
    $W = [double]$rc.W - ($padL + $padR)
    $H = [double]$rc.H - ($padT + $padB)

    $W = [Math]::Max(4.0, $W)
    $H = [Math]::Max(4.0, $H)

    $cnt0 = 0
    try { $cnt0 = [int]$wsMain.Shapes.Count } catch { $cnt0 = 0 }

    $src.Copy() | Out-Null
    Start-Sleep -Milliseconds 120
    $wsMain.Paste() | Out-Null
    Start-Sleep -Milliseconds 120

    $cnt1 = 0
    try { $cnt1 = [int]$wsMain.Shapes.Count } catch { $cnt1 = 0 }
    if ($cnt1 -le $cnt0) { throw "Fallback-paste no creó shape nuevo." }

    $p = $wsMain.Shapes.Item($cnt1)
    $p.Name = $shapeName

    try { $p.LockAspectRatio = 0 } catch {}

    $p.Left   = [single]([math]::Round($L,2))
    $p.Top    = [single]([math]::Round($T,2))
    $p.Width  = [single]([math]::Round($W,2))
    $p.Height = [single]([math]::Round($H,2))

    try { $p.Placement = 1 } catch {}  # xlMoveAndSize
    try { $p.ZOrder($zOrder) } catch {}

    Write-Host ("PERFIL PASTE OK: " + $srcShapeName + " -> " + $addr + " pad=[$padL,$padT,$padR,$padB] nudge=[$nudgeX,$nudgeY]")
  }
  finally {
    Restore-SheetVisible $wsSucs $oldVis
  }
}


function Apply-SucsShapesToPerfilMergedCells(
  $wsMain, $wsSucs, $j,
  [int]$baseRow = $script:BASE_ROW,
  [double]$rowsPerMeter = $script:ROWS_PER_METER,
  [int]$maxRow = $script:MAX_DATA_ROW
) {
  if ($wsMain -eq $null -or $wsSucs -eq $null -or $j -eq $null) {
    Write-Host "SUCS SHAPES: wsMain/wsSucs/j null -> skip"
    return
  }

  Remove-ShapesByPrefix $wsMain "SUCS_PF_"
  try { $wsMain.DisplayPageBreaks = $false } catch {}

  $idx = 0
  $ok = 0
  $skipNoText = 0
  $noShape = 0

  $cortes = Get-Cortes $j
  if ($null -eq $cortes) { Write-Host "SUCS SHAPES: no hay cortes"; return }

  foreach ($c in $cortes) {
    $de = $null
    $a  = $null
    try { $de = As-Double $c.combo_boxes.txtDE } catch {}
    try { $a  = As-Double $c.combo_boxes.txtA  } catch {}
    if ($de -eq $null -or $a -eq $null) { continue }
    if ($a -le $de) { continue }

    $r1 = Depth-ToRow $de $baseRow $rowsPerMeter
    $r2 = (Depth-ToRow $a $baseRow $rowsPerMeter) - 1

    if ($r1 -lt $baseRow) { $r1 = $baseRow }
    if ($r2 -gt $maxRow)  { $r2 = $maxRow }
    if ($r2 -lt $r1) { continue }

    $idx++

    $sucsText = Get-CorteSucsText $wsMain $c $r1 $r2
    $full = (($sucsText.Trim().ToUpper()) -replace '\s+','')
    if ([string]::IsNullOrWhiteSpace($full)) { $skipNoText++; continue }

    $addrFull = ("{0}{1}:{2}{3}" -f $script:PERFIL_LEFT_COL, $r1, $script:PERFIL_RIGHT_COL, $r2)
    $addrL    = ("{0}{1}:G{2}" -f $script:PERFIL_LEFT_COL, $r1, $r2)
    $addrR    = ("H{0}:{1}{2}" -f $r1, $script:PERFIL_RIGHT_COL, $r2)

    $codes = Get-SucsCodes $sucsText

    if ($codes.Count -ge 2) {
      $shL = Find-SucsShapeName $wsSucs $codes[0]
      $shR = Find-SucsShapeName $wsSucs $codes[1]

      if ($shL) { Paste-SucsShapeToRange $wsMain $wsSucs $shL $addrL ("SUCS_PF_{0}_L" -f $idx) 2 8 0 2 0 0 $msoSendToBack; $ok++ }
      else { $noShape++ }

      if ($shR) { Paste-SucsShapeToRange $wsMain $wsSucs $shR $addrR ("SUCS_PF_{0}_R" -f $idx) 0 8 2 2 0 0 $msoSendToBack; $ok++ }
      else { $noShape++ }

    } else {
      $shape = Find-SucsShapeName $wsSucs $full
      if ($shape) { Paste-SucsShapeToRange $wsMain $wsSucs $shape $addrFull ("SUCS_PF_{0}_FULL" -f $idx) 2 8 2 2 0 0 $msoSendToBack; $ok++ }
      else { $noShape++ }
    }
  }

  Write-Host ("SUCS SHAPES (NO MERGE) OK: cortes=" + $idx + " ok=" + $ok + " skipNoText=" + $skipNoText + " noShape=" + $noShape)
}


function Apply-SucsPngToPerfilByCortes(
  $wsMain, $j,
  [int]$baseRow = $script:BASE_ROW,
  [double]$rowsPerMeter = $script:ROWS_PER_METER,
  [int]$maxRow = $script:MAX_DATA_ROW
) {
  if ($wsMain -eq $null -or $j -eq $null) { return }

  Remove-ShapesByPrefix $wsMain "SUCS_PF_"
  try { $wsMain.DisplayPageBreaks = $false } catch {}

  $cortes = Get-Cortes $j
  if ($null -eq $cortes) { Write-Host "SUCS PNG: no hay cortes"; return }

  $idx=0; $ok=0; $skipNoText=0; $skipNoPng=0

  foreach ($c in $cortes) {
    $de = $null
    $a  = $null
    try { $de = As-Double $c.combo_boxes.txtDE } catch {}
    try { $a  = As-Double $c.combo_boxes.txtA  } catch {}
    if ($de -eq $null -or $a -eq $null) { continue }
    if ($a -le $de) { continue }

    $r1 = Depth-ToRow $de $baseRow $rowsPerMeter
    $r2 = (Depth-ToRow $a $baseRow $rowsPerMeter) - 1

    if ($r1 -lt $baseRow) { $r1 = $baseRow }
    if ($r2 -gt $maxRow)  { $r2 = $maxRow }
    if ($r2 -lt $r1) { continue }

    $idx++

    $sucsText = Get-CorteSucsText $wsMain $c $r1 $r2
    $full = (($sucsText.Trim().ToUpper()) -replace '\s+','')
    if ([string]::IsNullOrWhiteSpace($full)) { $skipNoText++; continue }

    $addrFull = ("{0}{1}:{2}{3}" -f $script:PERFIL_LEFT_COL, $r1, $script:PERFIL_RIGHT_COL, $r2)
    $addrL    = ("{0}{1}:G{2}" -f $script:PERFIL_LEFT_COL, $r1, $r2)
    $addrR    = ("H{0}:{1}{2}" -f $r1, $script:PERFIL_RIGHT_COL, $r2)

    $codes = @(Get-SucsCodes $sucsText)

    if ($codes.Count -ge 2) {
      $pL = SucsPngPath $codes[0]
      $pR = SucsPngPath $codes[1]

      if ($pL) {
        Upsert-Picture $wsMain $addrL $pL ("SUCS_PF_{0}_L" -f $idx) "stretch" "topleft" $msoBringToFront 2 2 2 2 1 0 0
        $ok++
      } else { $skipNoPng++ }

      if ($pR) {
        Upsert-Picture $wsMain $addrR $pR ("SUCS_PF_{0}_R" -f $idx) "stretch" "topleft" $msoBringToFront 2 2 2 2 1 0 0
        $ok++
      } else { $skipNoPng++ }

    } else {
      $p = SucsPngPath $full
      if (-not $p) { $skipNoPng++; continue }

      Upsert-Picture $wsMain $addrFull $p ("SUCS_PF_{0}_FULL" -f $idx) "stretch" "topleft" $msoBringToFront 2 2 2 2 1 0 0
      $ok++
    }
  }

  Write-Host ("SUCS PNG (POR CORTES) OK: cortes=" + $idx + " ok=" + $ok + " skipNoText=" + $skipNoText + " skipNoPng=" + $skipNoPng)
}



function Apply-SucsPngToPerfilMergedCells(
  $wsMain, $j,
  [int]$baseRow = $script:BASE_ROW,
  [double]$rowsPerMeter = $script:ROWS_PER_METER,
  [int]$maxRow = $script:MAX_DATA_ROW
) {
  if ($wsMain -eq $null -or $j -eq $null) { return }

  Remove-ShapesByPrefix $wsMain "SUCS_PF_"
  try { $wsMain.DisplayPageBreaks = $false } catch {}

  $blocks = @(Get-DescBlocksSmart $wsMain $j $wsMain.Name $baseRow $maxRow $script:DESC_LEFT_COL $script:DESC_RIGHT_COL | Where-Object { $_ -ne $null })

  if ($blocks.Count -eq 0) {
    Write-Host "SUCS PNG: no encontré bloques desc J:P (ni JSON ni plantilla)."
    return
  }

  $idx=0; $ok=0; $skipNoText=0; $skipNoPng=0

  foreach ($b in $blocks) {
    if ($b.Sheet -ne $wsMain.Name) { continue }

    $idx++
    $r1 = [int]$b.R1
    $r2 = [int]$b.R2

    $sucsText = Get-SucsTextFromRows $wsMain $r1 $r2 $script:SUCS_COL
    $full = ($sucsText.Trim().ToUpper() -replace '\s+','')
    if ([string]::IsNullOrWhiteSpace($full)) { $skipNoText++; continue }

    $addrFull = ("{0}{1}:{2}{3}" -f $script:PERFIL_LEFT_COL, $r1, $script:PERFIL_RIGHT_COL, $r2)
    $addrL    = ("{0}{1}:G{2}" -f $script:PERFIL_LEFT_COL, $r1, $r2)
    $addrR    = ("H{0}:{1}{2}" -f $r1, $script:PERFIL_RIGHT_COL, $r2)

    $codes = Get-SucsCodes $sucsText

    try {
      if ($codes.Count -ge 2) {
        $pL = SucsPngPath $codes[0]
        $pR = SucsPngPath $codes[1]

        if ($pL) {
          Upsert-Picture $wsMain $addrL $pL ("SUCS_PF_{0}_L" -f $idx) "stretch" "topleft" $msoBringToFront 2 2 2 2 1 0 0
          $ok++
        } else { $skipNoPng++ }

        if ($pR) {
          Upsert-Picture $wsMain $addrR $pR ("SUCS_PF_{0}_R" -f $idx) "stretch" "topleft" $msoBringToFront 2 2 2 2 1 0 0
          $ok++
        } else { $skipNoPng++ }

      } else {
        $p = SucsPngPath $full
        if (-not $p) { $skipNoPng++; continue }

        Upsert-Picture $wsMain $addrFull $p ("SUCS_PF_{0}_FULL" -f $idx) "stretch" "topleft" $msoBringToFront 2 2 2 2 1 0 0
        $ok++
      }
    } catch {
      $skipNoPng++
      Write-Host ("SUCS PNG: error insertando en bloque " + $idx + ": " + $_.Exception.Message)
    }
  }

  Write-Host ("SUCS PNG (NO MERGE) OK: blocks=" + $idx + " ok=" + $ok + " skipNoText=" + $skipNoText + " skipNoPng=" + $skipNoPng)
}



# -------------------------
# Leer JSON
# -------------------------
$raw = Get-Content -LiteralPath $json -Raw -Encoding UTF8
$j = $raw | ConvertFrom-Json

# Contadores para Upsert-Picture (NECESARIO con StrictMode)
$global:PicInserted = 0
$global:PicSkipped  = 0
$global:PicErrors   = 0



# --- baseDir real (para fotos/logos): preferir excel.baseDir ---
$baseDir = Split-Path -Parent $json
try {
  if ($j.excel -and $j.excel.baseDir) {
    $baseDir = [string]$j.excel.baseDir
  }
} catch {}
$baseDir = [System.IO.Path]::GetFullPath($baseDir)

# --- SUCS: preferir carpeta del JSON temporal (donde C++ exporta SUCS hoy) ---
$jsonDir = [System.IO.Path]::GetFullPath((Split-Path -Parent $json))

$sucsTemp = Join-Path $jsonDir "SUCS"
$sucsReal = Join-Path $baseDir "SUCS"

function Has-Png([string]$dir) {
  try {
    return (Test-Path -LiteralPath $dir) -and `
      ((Get-ChildItem -LiteralPath $dir -Filter *.png -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null)
  } catch { return $false }
}

if (Has-Png $sucsTemp)      { $script:SucsDir = $sucsTemp }
elseif (Has-Png $sucsReal)  { $script:SucsDir = $sucsReal }
else                        { $script:SucsDir = $sucsReal }  # fallback


Write-Host ("BASE DIR (real): " + $baseDir)
Write-Host ("JSON DIR: " + $jsonDir)
Write-Host ("SUCS DIR (chosen): " + $script:SucsDir)

try {
  $cnt = (Get-ChildItem -LiteralPath $script:SucsDir -Filter *.png -ErrorAction SilentlyContinue | Measure-Object).Count
  Write-Host ("SUCS PNG count: " + $cnt)
} catch {}





# -------------------------
# TÍTULO (excel_title) desde JSON
# -------------------------
$excelTitle = ""

try {
  if ($j.PSObject.Properties.Name -contains "excel_title") {
    $excelTitle = [string]$j.excel_title
  }
  elseif ($j.PSObject.Properties.Name -contains "header" -and $j.header -ne $null) {
    if ($j.header.PSObject.Properties.Name -contains "excel_title") {
      $excelTitle = [string]$j.header.excel_title
    }
  }
} catch { $excelTitle = "" }

$excelTitle = ($excelTitle -replace "`r","").Trim()

Write-Host ("EXCEL TITLE = [" + $excelTitle + "] LEN=" + $excelTitle.Length)

$defaultSheet = "Calicata"
try { if ($j.excel -and $j.excel.sheetName) { $defaultSheet = [string]$j.excel.sheetName } } catch {}
if ([string]::IsNullOrWhiteSpace($defaultSheet)) { $defaultSheet = "Calicata" }

if (!(Test-Path -LiteralPath $xlsx)) { throw "No existe el XLSX destino: $xlsx" }
Clear-ReadOnlyAttribute $xlsx
Wait-FileUnlocked $xlsx 15000

$excel = $null; $wb = $null
$wsCache = @{}

$script:OBS_RANGE_ADDR = $null


function Get-WS($name) {
  if ($wsCache.ContainsKey($name)) { return $wsCache[$name] }
  $ws = $null
  try { $ws = $wb.Worksheets.Item($name) } catch { $ws = $null }
  if ($ws -ne $null) {
    try { if ($ws.ProtectContents) { $ws.Unprotect("") } } catch {}
  }
  $wsCache[$name] = $ws
  return $ws
}

try {
  $excel = New-Object -ComObject Excel.Application
  $excel.Visible = $false
  $excel.DisplayAlerts = $false
  try { $excel.ScreenUpdating = $false } catch {}
  try { $excel.EnableEvents = $false } catch {}
  try { $excel.AskToUpdateLinks = $false } catch {}

  $missing = [Type]::Missing
  $wb = $excel.Workbooks.Open($xlsx, 0, $false, $missing, $missing, $missing, $true)
  $script:wb = $wb

  if ($wb.ReadOnly) { try { $wb.Close($false) } catch {}; throw "El Excel destino se abrió en SOLO LECTURA. Cierra Excel y reintenta." }

  try { if ($wb.ProtectStructure) { $wb.Unprotect("") } } catch {}

  # -------------------------
  # MERGES desde JSON (desc/center)
  # -------------------------
  function Apply-Merge($ws, [string]$addr, [string]$mode) {
    $addr = $addr.Trim()
    if ([string]::IsNullOrWhiteSpace($addr)) { return }

    try { $ws.Range($addr).UnMerge() | Out-Null } catch {}
    $rng = $ws.Range($addr)
    $rng.Merge() | Out-Null

    if ($mode -eq "desc") {
      try { $rng.WrapText = $true } catch {}
      try { $rng.HorizontalAlignment = -4131 } catch {} # xlLeft
      try { $rng.VerticalAlignment   = -4108 } catch {} # xlCenter
    } else {
      try { $rng.HorizontalAlignment = -4108 } catch {} # xlCenter
      try { $rng.VerticalAlignment   = -4108 } catch {} # xlCenter
    }
  }

  $mergesObj = $null
  try { $mergesObj = $j.excel.merges } catch {}

  if ($mergesObj -ne $null) {
    foreach ($p in $mergesObj.PSObject.Properties) {
      $k = Split-Key $p.Name $defaultSheet
      $ws = Get-WS $k.Sheet
      if ($ws -eq $null) { continue }

      $mode = [string](Scalar $p.Value)
      if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "center" }

      Apply-Merge $ws $k.Addr $mode
    }
  }

# -------------------------
# Detectar rango OBSERVACIONES (luego de merges)
# -------------------------
$wsMainObs = Get-WS $defaultSheet
try {
  $obsRng = Get-ObservacionesRange $wb $wsMainObs
  if ($obsRng -ne $null) {
    $tl = $null
    try { $tl = Unwrap-Com ($obsRng.Cells.Item(1,1)) } catch { $tl = $obsRng }
    $script:OBS_RANGE_ADDR = ([string]$tl.Address -replace '\$','')
    Write-Host ("OBS RANGE (top-left): " + $script:OBS_RANGE_ADDR)
  } else {
    $script:OBS_RANGE_ADDR = $null
    Write-Host "OBS RANGE: (no encontrado)"
  }
}
catch {
  $script:OBS_RANGE_ADDR = $null
  Write-Host ("OBS RANGE: error detectando rango: " + $_.Exception.Message)
}




  # -------------------------
  # CELDAS desde JSON
  # -------------------------
  $cellsObj = $null
  try { $cellsObj = $j.excel.cells } catch {}

  if ($cellsObj -ne $null) {
    foreach ($p in $cellsObj.PSObject.Properties) {
      $k = Split-Key $p.Name $defaultSheet
      $ws = Get-WS $k.Sheet
      if ($ws -ne $null) { Set-Cell $ws $k.Addr $p.Value }
    }
  }

  # --- Ajustar tamaño de fuente SOLO en descripciones J:P para que el texto quepa ---
  $wsMainDesc = Get-WS $defaultSheet
  AutoShrink-DescripcionBlocks $wsMainDesc $j $defaultSheet $script:BASE_ROW $script:MAX_DATA_ROW

  # -------------------------
  # FIX FINAL: forzar encabezado en OBSERVACIONES (post-proceso)
  # -------------------------
  $wsMainAfterCells = Get-WS $defaultSheet
  Fix-ObservacionesHeader $wb $wsMainAfterCells


function Fit-TitleFontToRange(
  $ws,
  $rng,
  [string]$title,
  [int]$baseSize = 28,
  [int]$minSize = 10,
  [string]$measureAddr = "AG3:BC6",
  [double]$padL = 4,
  [double]$padT = 2,
  [double]$padR = 4,
  [double]$padB = 2,
  [double]$slackPt = 2.0
) {
  if ($ws -eq $null -or $rng -eq $null) { return }

  $title = ($title -replace "`r","").Trim()
  if ([string]::IsNullOrWhiteSpace($title)) { return }

  $rng = Unwrap-Com $rng
  if ($rng -eq $null) { return }

  $cell = $null
  try { $cell = Unwrap-Com ($rng.Cells.Item(1)) } catch { $cell = $rng }
  if ($cell -eq $null) { return }

  try { $cell.WrapText = $true } catch {}
  try { $rng.WrapText = $true } catch {}
  try { $rng.HorizontalAlignment = -4108 } catch {} # xlCenter
  try { $rng.VerticalAlignment   = -4108 } catch {} # xlCenter

  # ------------------------------------------------------------
  # MEDICIÓN REAL DEL BLOQUE VISUAL DEL TÍTULO
  # No usamos $rng.Height porque con el Named Range devuelve 11.75 pt.
  # Usamos el rectángulo real de la franja azul grande.
  # ------------------------------------------------------------
  $W = 0.0
  $H = 0.0

  try {
    $rc = Get-RectFromAddr $ws $measureAddr
    $W = [double]$rc.W - ($padL + $padR)
    $H = [double]$rc.H - ($padT + $padB)
  } catch {
    Write-Host ("TITLE FIT ERROR: no pude medir " + $measureAddr + " => " + $_.Exception.Message)
    return
  }

  if ($W -le 6 -or $H -le 6) {
    Write-Host ("TITLE FIT SKIP: rect pequeño W=" + $W + " H=" + $H)
    return
  }

  $fontName = "Arial Narrow"
  $isBold = $true

  try { $fontName = [string](Scalar $cell.Font.Name) } catch { $fontName = "Arial Narrow" }
  try { $isBold = ([bool](Scalar $cell.Font.Bold)) } catch { $isBold = $true }

  $tmpName = "__TMP_TITLE_MEASURE_" + ([guid]::NewGuid().ToString("N"))
  $tb = $null

  $measureH = [Math]::Max(2000.0, $H * 30.0)

  try {
    $tb = $ws.Shapes.AddTextbox(
      $msoTextOrientationHorizontal,
      [single]([double]$rc.L + $padL),
      [single]([double]$rc.T + $padT),
      [single]$W,
      [single]$measureH
    )

    $tb = Unwrap-Com $tb
    $tb.Name = $tmpName

    try { $tb.Line.Visible = $msoFalse } catch {}
    try { $tb.Fill.Visible = $msoTrue } catch {}
    try { $tb.Fill.Transparency = 1.0 } catch {}
    try { $tb.Placement = 3 } catch {}
    try { $tb.ZOrder($msoSendToBack) } catch {}

    $tb.TextFrame2.WordWrap = $msoTrue
    try { $tb.TextFrame2.AutoSize = 0 } catch {}

    $tb.TextFrame2.MarginLeft = 0
    $tb.TextFrame2.MarginRight = 0
    $tb.TextFrame2.MarginTop = 0
    $tb.TextFrame2.MarginBottom = 0

    $tb.TextFrame2.TextRange.Text = $title
    $tb.TextFrame2.TextRange.Font.Name = $fontName
    $tb.TextFrame2.TextRange.Font.Bold = $isBold

    try { $tb.TextFrame2.TextRange.ParagraphFormat.Alignment = $msoAlignCenter } catch {}
    try { $tb.TextFrame2.VerticalAnchor = $msoAnchorMiddle } catch {}

    try { $tb.TextFrame2.TextRange.ParagraphFormat.SpaceBefore = 0 } catch {}
    try { $tb.TextFrame2.TextRange.ParagraphFormat.SpaceAfter  = 0 } catch {}
    try { $tb.TextFrame2.TextRange.ParagraphFormat.SpaceWithin = 1 } catch {}

    $fit = $minSize
    $finalNeedH = 0.0

    for ($sz = $baseSize; $sz -ge $minSize; $sz--) {
      $tb.TextFrame2.TextRange.Font.Size = $sz
      Start-Sleep -Milliseconds 10

      $needH = 0.0
      try { $needH = [double]$tb.TextFrame2.TextRange.BoundHeight } catch { $needH = 0.0 }

      $finalNeedH = $needH

      # Usamos solo una parte de la altura disponible
      # para dejar aire visual y obligar a bajar más el tamaño.
      $usableH = [Math]::Max(6.0, $H * 0.82)

      if ($needH -le ($usableH + $slackPt)) {
        $fit = $sz
        break
      }
    }

    try { $rng.Font.Size = $fit } catch { try { $cell.Font.Size = $fit } catch {} }
    try { $rng.Font.Bold = $true } catch {}
    try { $rng.WrapText = $true } catch {}

    Write-Host ("TITLE FIT: size=" + $fit +
                " needH=" + [math]::Round($finalNeedH,2) +
                " H=" + [math]::Round($H,2) +
                " W=" + [math]::Round($W,2) +
                " measure=" + $measureAddr)
  }
  finally {
    try { if ($tb -ne $null) { $tb.Delete() | Out-Null } } catch {}
  }
}


function Get-InitialTitleSize([string]$title) {
  $t = ($title -replace "`r","").Trim()

  if ([string]::IsNullOrWhiteSpace($t)) {
    return 28
  }

  $lines = @($t -split "`n")
  $lineCount = [Math]::Max(1, $lines.Count)

  $totalLen = ($t -replace "`n"," ").Length

  # Títulos cortos
  if ($lineCount -le 1 -and $totalLen -le 45)  { return 28 }
  if ($lineCount -le 2 -and $totalLen -le 90)  { return 26 }
  if ($lineCount -le 3 -and $totalLen -le 140) { return 24 }

  # Títulos medianos
  if ($totalLen -le 220) { return 22 }
  if ($totalLen -le 320) { return 20 }
  if ($totalLen -le 430) { return 18 }

  # Títulos largos como el que probaste
  if ($totalLen -le 650) { return 14 }

  # Casos extremos
  if ($totalLen -le 850) { return 12 }

  return 10
}

# -------------------------
# ESCRIBIR TÍTULO EN FRANJA (excel_title)
# -------------------------
function Set-TitleByNamedRangeOrFallback($wb, $wsMain, [string]$title) {
  if ([string]::IsNullOrWhiteSpace($title)) {
    Write-Host "TITLE SKIP: titulo vacío"
    return
  }

  if ($wsMain -eq $null) {
    Write-Host "TITLE ERROR: wsMain null"
    return
  }

  $title = ($title -replace "`r","").Trim()

  try {
    $r = $null

    try {
      $r = $wsMain.Range("TITULO_TESTIFICACION")
    } catch {
      $r = $null
    }

    if ($r -eq $null) {
      try {
        $r = $wb.Names.Item("TITULO_TESTIFICACION").RefersToRange
      } catch {
        $r = $null
      }
    }

    if ($r -eq $null) {
      Write-Host "TITLE ERROR: no se encontró el rango TITULO_TESTIFICACION"
      return
    }

    $r = Unwrap-Com $r

    $cell = $null
    try {
      $cell = Unwrap-Com ($r.Cells.Item(1))
    } catch {
      $cell = $r
    }

    try {
      $cell.Value = $title
    } catch {
      try {
        $cell.Value2 = $title
      } catch {
        Write-Host ("TITLE VALUE ERROR: " + $_.Exception.Message)
        return
      }
    }

    try { $r.WrapText = $true } catch {}
    try { $r.HorizontalAlignment = -4108 } catch {}
    try { $r.VerticalAlignment   = -4108 } catch {}

    try { $r.Font.Bold = $true } catch {}
    try { $r.Font.Color = 16777215 } catch {}
    try { $r.Font.Name = "Arial Narrow" } catch {}

    $startSize = Get-InitialTitleSize $title
    try { $r.Font.Size = $startSize } catch {}

    $minTitleSize = 10
    if ($title.Length -le 650) {
      $minTitleSize = 14
    }

    Fit-TitleFontToRange $wsMain $r $title $startSize $minTitleSize "AG3:BC6" 4 2 4 2 0.5

    $addrReal = ""
    try { $addrReal = ([string]$r.Address -replace '\$','') } catch {}

    Write-Host ("TITLE WRITE OK: TITULO_TESTIFICACION " + $addrReal + " => " + $title)
  }
  catch {
    Write-Host ("TITLE WRITE ERROR TITULO_TESTIFICACION: " + $_.Exception.Message)
  }
}
# Llamada (usa wsMain del sheet por defecto)
$wsMainForTitle = Get-WS $defaultSheet
Set-TitleByNamedRangeOrFallback $wb $wsMainForTitle $excelTitle

# -------------------------
# CORTES: Formatos + Sombreado H/E/S + FIN DE LA CALICATA
# -------------------------
$wsMain = Get-WS $defaultSheet

Fix-GranulometriaFormats $wsMain $script:BASE_ROW $script:MAX_DATA_ROW
Apply-HES-Shading        $wsMain $j $script:BASE_ROW $script:ROWS_PER_METER $script:MAX_DATA_ROW
Create-FinDeCalicata     $wsMain $j $wb $script:MAX_DATA_ROW



  # -------------------------
  # CORTES: HES shading + FIN + PERFIL TRAMAS (FIX)
  # -------------------------

  $wsMain = Get-WS $defaultSheet

  $wsSucs = Get-WS "sucs"
  if ($wsSucs -eq $null) { $wsSucs = Get-WS "SUCS" }
  if ($wsSucs -eq $null) { $wsSucs = Get-WS "Sucs" }

  $hasSucsPng = $false
  try {
    $hasSucsPng = (Test-Path -LiteralPath $script:SucsDir) -and `
      ((Get-ChildItem -LiteralPath $script:SucsDir -Filter *.png -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null)
  } catch { $hasSucsPng = $false }

  if ($hasSucsPng) {
    Apply-SucsPngToPerfilByCortes $wsMain $j $script:BASE_ROW $script:ROWS_PER_METER $script:MAX_DATA_ROW
  } elseif ($wsSucs -ne $null) {
    Apply-SucsShapesToPerfilMergedCells $wsMain $wsSucs $j $script:BASE_ROW $script:ROWS_PER_METER $script:MAX_DATA_ROW
  } else {
  Write-Host "SUCS: no hay carpeta SUCS (PNG) y tampoco hoja 'sucs' (shapes)."
  }

Apply-PerfilMedidasBoxes $wsMain $j $script:BASE_ROW $script:ROWS_PER_METER $script:MAX_DATA_ROW




  $wb.Save()

  # -------------------------
  # IMÁGENES desde JSON (logos/fotos)
  # -------------------------
  $imgsObj = $null
  try { $imgsObj = $j.excel.images } catch {}

  $global:PicInserted = 0
  $global:PicSkipped  = 0
  $global:PicErrors   = 0

  $logoNames = @()
  $fotoNames = @()

  if ($imgsObj -ne $null) {

    foreach ($p in $imgsObj.PSObject.Properties) {

      $k = Split-Key $p.Name $defaultSheet
      $ws = Get-WS $k.Sheet
      if ($ws -eq $null) { continue }

      $addr = [string]$k.Addr
      $path = Resolve-PathSmart ([string](Scalar $p.Value)) $baseDir

      # nombre único de shape para Excel (estable y repetible)
      $shapeName = "APP_IMG_" + (Normalize-Token ($k.Sheet + "_" + $addr))
      if ($shapeName.Length -gt 240) { $shapeName = $shapeName.Substring(0,240) }


      $mode  = "fit"
      $align = "center"
      $z     = $msoBringToFront

    # --- clasificar bien ---
    $isLogo = ($addr.ToUpper() -in @("B1:O12","P1:AF12"))
    $isFoto = ($addr.ToUpper() -in @($PHOTO1_ADDR,$PHOTO2_ADDR,$PHOTO3_ADDR))
    $file   = ""

    if (-not [string]::IsNullOrWhiteSpace($path)) {
    $isFoto = $isFoto -or ($path -match '(?i)[\\/]fotos[\\/]|fotograf')
      $file   = [System.IO.Path]::GetFileName($path)

      $isLogo = (-not $isFoto) -and (
        $path -match '(?i)[\\/]recursos[\\/]' -or
        $file -match '(?i)\blogo\b' -or
        $file -match '(?i)mtc' -or
        $file -match '(?i)aldesa'
      )
    }

    Write-Host ("IMG CLASS: addr="+$addr+" file='"+$file+"' isFoto="+$isFoto+" isLogo="+$isLogo)


    # --- insertar (FOTO primero) ---
    if ($isFoto) {
      Upsert-Picture $ws $addr $path $shapeName "fit" "center" $msoBringToFront 2 2 2 2 1 0 0
    }
    elseif ($isLogo) {
      Upsert-Picture $ws $addr $path $shapeName "fit" "leftcenter" $msoBringToFront 2 0 2 0 1 0 0
    }
    else {
      Upsert-Picture $ws $addr $path $shapeName "fit" "center" $msoBringToFront 2 2 2 2 1 0 0
    }





      if ($isLogo) { $logoNames += @(@{ ws=$ws; name=$shapeName; path=$path }) }
      if ($isFoto) { $fotoNames += @(@{ ws=$ws; name=$shapeName; path=$path }) }
    }

    $wsSet = @{}
    foreach ($it in $logoNames) { try { $wsSet[[string]$it.ws.Name] = $it.ws } catch {} }
    foreach ($it in $fotoNames) { try { $wsSet[[string]$it.ws.Name] = $it.ws } catch {} }
    #foreach ($w in $wsSet.Values) { Shrink-PicturesByPrefix $w "APP_IMG_" 0.99 }
  }

  Write-Host ("PIC SUMMARY: inserted=" + $global:PicInserted + " skipped=" + $global:PicSkipped + " errors=" + $global:PicErrors)

  if ($imgsObj -ne $null -and $global:PicInserted -eq 0) {
    throw "No se insertó ninguna imagen. Revisa rangos y rutas. (skipped=$global:PicSkipped)"
  }

  $wb.Save()
}
finally {
  try { if ($wb -ne $null) { $wb.Close($true) } } catch {}
  try { if ($excel -ne $null) { $excel.Quit() } } catch {}

  foreach ($k in @($wsCache.Keys)) {
    try { $w = $wsCache[$k]; if ($w -ne $null) { [void][System.Runtime.Interopservices.Marshal]::FinalReleaseComObject($w) } } catch {}
  }
  try { if ($wb -ne $null) { [void][System.Runtime.Interopservices.Marshal]::FinalReleaseComObject($wb) } } catch {}
  try { if ($excel -ne $null) { [void][System.Runtime.Interopservices.Marshal]::FinalReleaseComObject($excel) } } catch {}

  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}

exit 0
