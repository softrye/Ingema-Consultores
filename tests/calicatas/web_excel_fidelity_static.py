"""Static layout regression for native Android Calicatas XLSX.

Usage: python tests/calicatas/web_excel_fidelity_static.py
No build, no installed APK. Source contract anchored to ZIP web golden.
"""
from pathlib import Path
import re
import zipfile
import io
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
INC=(ROOT/"calicatawebpagedexcel.inc").read_text(encoding="utf-8")
CPP=(ROOT/"androidcalicataexporter.cpp").read_text(encoding="utf-8")
QXH=(ROOT/"thirdparty/QXlsx/header/xlsxworksheet.h").read_text(encoding="utf-8")
QXC=(ROOT/"thirdparty/QXlsx/source/xlsxworksheet.cpp").read_text(encoding="utf-8")
PDF=(ROOT/"calicatawebpagedpdf.inc").read_text(encoding="utf-8")

start=CPP.index("QString AndroidCalicataExporter::exportStateToXlsx(")
end=CPP.index("QString AndroidCalicataExporter::exportGenericWorkbookToXlsx(",start)
excel_method=CPP[start:end]

assert "QXlsx::Document xlsx;" in excel_method, "Must start from a blank Web workbook"
assert "xlsx.addSheet(name)" in excel_method
assert "copyOfficialTemplate(" not in excel_method, "Do not reuse legacy template"
assert "QXlsx::Document xlsx(workingTemplatePath)" not in excel_method
assert "fillWebPaginatedSheet(xlsx, state, reportImages, page" in excel_method

assert "setCalicataA3PrintLayout()" in QXH
assert "void Worksheet::setCalicataA3PrintLayout()" in QXC
assert "inge-cal-a3" in QXC and 'QStringLiteral("fitToWidth")' in QXC
assert "setGridLinesVisible(false)" in INC
assert "setCalicataA3PrintLayout()" in INC
assert "xlsx.setRowHeight(22, 81, 21.75)" in INC
assert "xlsx.setRowHeight(1, 89, 15.75)" in INC
assert "xlsx.setColumnWidth(span.from, span.to, span.width)" in INC
assert "const CalicataExportPages::Page &page" in INC
assert "webPageCell({},false,10)" in INC
assert "webSheetGeometry(xlsx)" in INC
assert "copyOfficialTemplate(" not in INC

# Compare every native column width to the Web golden file. No hardcoded
# fallback to the legacy template's original sheet geometry.
spans=[
    (int(x),int(y),float(w)) for x,y,w
    in re.findall(r"\{(\d+),(\d+),([\d.]+)\}",INC.split("static const Span spans[]",1)[1].split("};",1)[0])
]
widths={}
for first,last,width in spans:
    for col in range(first,last+1):
        assert col not in widths,(col,"overlap")
        widths[col]=width
assert set(widths)==set(range(1,56)),("columns",len(widths))
webzip=Path.home()/"Downloads"/"ingeplus-main (1).zip"
if not webzip.exists():
    webzip=Path(r"C:\Users\PC-02\Downloads\ingeplus-main (1).zip")
assert webzip.is_file(),webzip
with zipfile.ZipFile(webzip) as outer:
    member=next(n for n in outer.namelist() if n.endswith("calicata-export-fidelity-20260923/calicata-1_5m.xlsx"))
    with zipfile.ZipFile(io.BytesIO(outer.read(member))) as gold:
        ns={"m":"http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
        sheet=ET.fromstring(gold.read("xl/worksheets/sheet1.xml"))
        colNodes=sheet.findall(".//m:cols/m:col",ns)
        goldWidths={}
        for x in colNodes:
            for n in range(int(x.attrib["min"]),int(x.attrib["max"])+1):
                goldWidths[n]=float(x.attrib["width"])
        assert len(goldWidths)>=55
        for i in range(1,56):
            assert abs(widths[i]-goldWidths[i])<0.000001,(i,widths[i],goldWidths[i])

        goldMerges={x.attrib["ref"] for x in sheet.findall(".//m:mergeCell",ns)}
        for block in ("AG1:BC3","AG4:BC6","AH9:AI9","AJ9:AP9",
                      "B13:D20","E13:I20","J13:P20","Q13:Q20",
                      "R13:U15","V13:Y15","Z13:AC15","AD13:AF15",
                      "AI13:AT15","AI16:AM17","AN16:AO17","AP16:AP17",
                      "AQ16:AT17","AU13:BC20","AH84:BC89",
                      "AU42:BC42","AU62:BC62","AU82:BC82","C22:D22"):
            assert block in goldMerges,block

for code in ("if(!put(1,33,3,55,","if(!put(4,33,6,55,",
             "put(13,33,20,33","put(13,34,20,34",
             "put(16,35,17,39","put(16,40,17,41",
             "put(16,42,17,42","put(16,43,17,46",
             "put(84,34,89,55","put(to+1,47,to+1,55",
             "put(row,3,row,4","put(82,3,82,4"):
    assert code in INC,("missing Web block",code)
assert "QColor soilFill" in INC
assert "f.firstPart()" not in INC or "fragment.firstPart()" in INC
assert "fragment.firstPart()" in INC
assert "insertImageFitted(xlsx,1,2,12,15,images[1],false)" in INC
assert "insertImageFitted(xlsx,1,16,12,32,images[0],false)" in INC

# PDF was already accepted by user. Its generator must still use the existing
# A3 renderer and cannot accidentally pick up the new workbook API.
assert 'QPdfWriter pdf(&output)' in PDF
assert 'paintWebCalicataPdfPage(' in PDF
assert 'renderWebCalicataPdf(state,resourcesBase,defaultExportDir(),code,&error)' in CPP

print("PASS Web golden column widths (A..BC), title, header, group, lab, images, depth and footer contracts.")
print("PASS Native fresh XLSX workbook, A3 landscape print, shared pagination; accepted PDF unchanged.")
