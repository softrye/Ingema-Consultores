"""No-build checks for the native Android Calicata Web XLSX/PDF contract."""
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile
import math

ROOT = Path(__file__).resolve().parents[2]
CPP = (ROOT / "androidcalicataexporter.cpp").read_text(encoding="utf-8")
PAGES = (ROOT / "calicataexportpagination.h").read_text(encoding="utf-8")
EXCEL = (ROOT / "calicatawebpagedexcel.inc").read_text(encoding="utf-8")
PDF = (ROOT / "calicatawebpagedpdf.inc").read_text(encoding="utf-8")
QRC = (ROOT / "resources_mobile_calicatas.qrc").read_text(encoding="utf-8")
CMAKE = (ROOT / "CMakeLists.txt").read_text(encoding="utf-8")

for fn in ("androidcalicataexporter.cpp", "calicatawebpagedexcel.inc", "calicatawebpagedpdf.inc"):
    data = (ROOT / fn).read_bytes()
    assert data and b"\x00" not in data, f"Corrupt source file: {fn}"
assert '#include "calicataexportpagination.h"' in CPP
assert '#include "calicatawebpagedexcel.inc"' in CPP
assert '#include "calicatawebpagedpdf.inc"' in CPP
assert 'CalicataExportPages::paginate' in CPP
assert 'fillWebPaginatedSheet(xlsx, state, reportImages, page' in CPP
assert 'renderWebCalicataPdf(state,resourcesBase,defaultExportDir(),code,&error)' in CPP
# safeFileName() is an instance method, not a free function available
# to the included PDF renderer. Catch the previous clang compilation failure.
assert 'const QString code = safeFileName(canonicalCalicataCode(' in CPP
assert 'const QString code=safeCode;' in PDF
assert 'const QString code=safeFileName(' not in PDF
assert 'setPageOrientation(QPageLayout::Landscape)' in PDF
assert 'QPageSize(QPageSize::A3)' in PDF
assert 'for(int row=22;row<=81;++row)' in PDF
assert 'for(int row=22;row<=81;++row)' in EXCEL
assert 'CALICATA_SHEET' not in CPP or 'calicataexportpagination.h' in CPP
assert 'QXlsx::Document xlsx;' in CPP and 'xlsx.addSheet(name)' in CPP
assert 'resources_mobile_calicatas.qrc' in CMAKE
for template in ("Calicata_Formato.xlsx", "Calicata_Formato_Paginado.xlsx"):
    assert (ROOT / "Templates" / template).is_file()
    assert f'<file alias="{template}">Templates/{template}</file>' in QRC

Z = ROOT / "Templates" / "Calicata_Formato_Paginado.xlsx"
with zipfile.ZipFile(Z) as archive:
    names = archive.namelist()
    for n in range(1, 11):
        assert f"xl/worksheets/sheet{n}.xml" in names
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    root = ET.fromstring(archive.read("xl/workbook.xml"))
    sheet_names = [node.attrib["name"] for node in root.findall(".//m:sheet", ns)]
    assert sheet_names == [f"Calicata {i}" for i in range(1, 11)], sheet_names
    sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
    rows = {int(row.attrib["r"]): row for row in sheet.findall(".//m:sheetData/m:row", ns)}
    assert all(abs(float(rows[n].attrib.get("ht", "0")) - 21.75) < .0001 for n in range(22, 82))
    pagesetup = sheet.find(".//m:pageSetup", ns)
    assert pagesetup is not None and pagesetup.attrib["paperSize"] == "8"
    assert pagesetup.attrib["orientation"] == "landscape"

def paginate(total_m, strata):
    deepest = max((round(end * 100) for _, end in strata), default=0)
    total = max(round(total_m * 100), deepest)
    total = total if total > 0 else 300
    n = math.ceil(total / 300)
    pages = []
    for idx in range(n):
        origin = idx * 300
        fragments = []
        for frm, end in strata:
            a, b = round(frm * 100), round(end * 100)
            x, y = max(a, origin), min(b, origin + 300)
            if y > x:
                fragments.append((22 + (x-origin)//5, 22 + (y-origin)//5 - 1))
        pages.append(fragments)
    return pages

assert len(paginate(1.5, [(0.0,1.5)])) == 1
assert len(paginate(3.0,[(0.0,3.0)])) == 1
assert len(paginate(7.4,[(0.0,7.4)])) == 3
assert paginate(3.5,[(2.5,3.5)]) == [[(72,81)],[(22,31)]]
print("PASS: 10 template worksheets, A3, 60 x 0.05m, QRC, shared source contract, 4 pagination fixtures.")
