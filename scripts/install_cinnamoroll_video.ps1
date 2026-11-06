param(
    [string]$Source = "$env:USERPROFILE\Downloads\gemini_generated_video_c322b325.mp4"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repo 'images\kawaii\cinnamoroll-knock-clean-10s.mp4'
$expectedHash = '449F8BE37E480F248CFFEC5E59D09814019DF1E5A7CE1F40D1495004605CC9E1'
$expectedLength = 3996670
if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "No se encuentra el MP4 original: $Source. Descargalo primero a Descargas."
}
$sourceInfo = Get-Item -LiteralPath $Source
$sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
if ($sourceInfo.Length -ne $expectedLength -or $sourceHash -ne $expectedHash) {
    throw "El MP4 es diferente al archivo Gemini aprobado. No se copiara ni convertira."
}
if ($Source -ne $target) {
    Copy-Item -LiteralPath $Source -Destination $target -Force
}
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'La comprobacion SHA-256 de destino fallo.'
}
Write-Output 'ORIGINAL_MP4_INSTALLED (H264 1280x720/24fps + AAC stereo 48kHz, bit-identical)'
Write-Output $target
Write-Output 'Ejecuta Reconfigure CMake antes de compilar Android.'
