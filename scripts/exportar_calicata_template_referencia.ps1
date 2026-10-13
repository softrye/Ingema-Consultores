param(
    [string]$Template = ".\docs\templates\Calicata_Formato.xlsx",
    [string]$Output = ".\CT_DEMO_EXPORTADO.xlsx"
)

# Script referencial para escritorio.
# La app Android V19 genera el mismo estilo desde C++/QXlsx y guarda en Descargas/InGePlus.
# Este script sirve para presentar cómo se llenan celdas base del formato original.

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$wb = $excel.Workbooks.Open((Resolve-Path $Template))
$ws = $wb.Worksheets.Item("Calicata")

$ws.Range("AX10").Value2 = "CT12-85+745"
$ws.Range("AI8").Value2 = "XXX"
$ws.Range("AI9").Value2 = "Manual"
$ws.Range("AI10").Value2 = "Derecho"
$ws.Range("AO9").Value2 = "304779"
$ws.Range("AO10").Value2 = "8178274"
$ws.Range("AU8").Value2 = "08/01/2025"
$ws.Range("AU9").Value2 = "08/01/2025"
$ws.Range("AU10").Value2 = "19K"

# Ejemplo de estratos: profundidad, descripción, clasificación y laboratorio.
$ws.Range("A22").Value2 = "0.00"
$ws.Range("A41").Value2 = "0.50"
$ws.Range("F26").Value2 = "Arena gravosa en matriz arcillosa, compacidad media, plasticidad baja, humedad baja, color marrón claro."

$ws.Range("A42").Value2 = "0.50"
$ws.Range("A63").Value2 = "2.10"
$ws.Range("F48").Value2 = "Grava arenosa en matriz limoarcillosa, compacidad media, plasticidad baja, humedad baja, color marrón claro."

$ws.Range("A64").Value2 = "2.10"
$ws.Range("A72").Value2 = "2.50"
$ws.Range("F68").Value2 = "Grava arenosa en matriz limoarcillosa, compacidad alta, humedad baja, color marrón claro."

$wb.SaveAs((Resolve-Path ".").Path + "\" + $Output)
$wb.Close($true)
$excel.Quit()

Write-Host "Exportado:" $Output
