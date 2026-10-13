"""Genera Templates/Calicata_Formato_Paginado.xlsx a partir de la plantilla oficial.

Contrato Web (CALICATAS_EXPORTACION_EXCEL_PDF_V01): 3.00 m por hoja (60 filas x 0.05 m);
una calicata más profunda se pagina en hojas "Calicata 1", "Calicata 2", ... con el mismo
formato aprobado. QXlsx no copia altos de fila ni anchos de columna al duplicar una hoja
(Worksheet::copy), así que cada hoja de esta plantilla es una copia byte a byte de la hoja
oficial. El exportador elimina las hojas que no necesita.

Uso: python Templates/make_paginated_template.py
"""
import os
import re
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "Calicata_Formato.xlsx")
TARGET = os.path.join(HERE, "Calicata_Formato_Paginado.xlsx")
SHEETS = 10   # 30 m: límite documentado del exportador Android


def main():
    src = zipfile.ZipFile(SOURCE)
    parts = {name: src.read(name) for name in src.namelist()}
    sheet = parts["xl/worksheets/sheet1.xml"].decode("utf-8")
    sheet_rels = parts["xl/worksheets/_rels/sheet1.xml.rels"].decode("utf-8")
    printer = parts["xl/printerSettings/printerSettings1.bin"]

    out = {}
    for name, data in parts.items():
        if name.startswith("xl/worksheets/") or name.startswith("xl/printerSettings/"):
            continue
        out[name] = data

    sheet_entries, rel_entries, overrides, defined = [], [], [], []
    for i in range(1, SHEETS + 1):
        body = sheet if i == 1 else re.sub(r'\s+tabSelected="1"', "", sheet)
        out["xl/worksheets/sheet%d.xml" % i] = body.encode("utf-8")
        out["xl/worksheets/_rels/sheet%d.xml.rels" % i] = sheet_rels.replace(
            "printerSettings1.bin", "printerSettings%d.bin" % i).encode("utf-8")
        out["xl/printerSettings/printerSettings%d.bin" % i] = printer
        rid = "rIdSheet%d" % i
        sheet_entries.append('<sheet name="Calicata %d" sheetId="%d" r:id="%s"/>' % (i, i, rid))
        rel_entries.append('<Relationship Id="%s" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                           'relationships/worksheet" Target="worksheets/sheet%d.xml"/>' % (rid, i))
        overrides.append('<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/'
                         'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' % i)
        # Sin área de impresión por hoja: QXlsx reescribe como globales los nombres de las
        # hojas eliminadas (Workbook::deleteSheet). El exportador la define para cada hoja
        # que conserva (Document::defineName con ámbito de hoja).
    defined.append("<definedName name=\"TITULO_TESTIFICACION\">'Calicata 1'!$AG$4</definedName>")

    workbook = parts["xl/workbook.xml"].decode("utf-8")
    workbook = re.sub(r"<sheets>.*?</sheets>", "<sheets>" + "".join(sheet_entries) + "</sheets>", workbook, flags=re.S)
    workbook = re.sub(r"<definedNames>.*?</definedNames>", "<definedNames>" + "".join(defined) + "</definedNames>",
                      workbook, flags=re.S)
    workbook = re.sub(r"<mc:AlternateContent.*?</mc:AlternateContent>", "", workbook, flags=re.S)
    out["xl/workbook.xml"] = workbook.encode("utf-8")

    rels = parts["xl/_rels/workbook.xml.rels"].decode("utf-8")
    rels = re.sub(r'<Relationship Id="rId1"[^>]*worksheets/sheet1.xml"/>', "".join(rel_entries), rels)
    out["xl/_rels/workbook.xml.rels"] = rels.encode("utf-8")

    types = parts["[Content_Types].xml"].decode("utf-8")
    types = re.sub(r'<Override PartName="/xl/worksheets/sheet1.xml"[^>]*/>', "".join(overrides), types)
    out["[Content_Types].xml"] = types.encode("utf-8")

    titles = "".join("<vt:lpstr>Calicata %d</vt:lpstr>" % i for i in range(1, SHEETS + 1))
    app = parts["docProps/app.xml"].decode("utf-8")
    app = re.sub(r"<HeadingPairs>.*?</HeadingPairs>",
                 '<HeadingPairs><vt:vector size="2" baseType="variant"><vt:variant><vt:lpstr>Hojas de cálculo'
                 '</vt:lpstr></vt:variant><vt:variant><vt:i4>%d</vt:i4></vt:variant></vt:vector></HeadingPairs>'
                 % SHEETS, app, flags=re.S)
    app = re.sub(r"<TitlesOfParts>.*?</TitlesOfParts>",
                 '<TitlesOfParts><vt:vector size="%d" baseType="lpstr">%s</vt:vector></TitlesOfParts>'
                 % (SHEETS, titles), app, flags=re.S)
    out["docProps/app.xml"] = app.encode("utf-8")

    order = ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels"]
    names = order + sorted(n for n in out if n not in order)
    with zipfile.ZipFile(TARGET, "w", zipfile.ZIP_DEFLATED) as dst:
        for name in names:
            dst.writestr(name, out[name])
    print("OK", TARGET, SHEETS, "hojas")


if __name__ == "__main__":
    main()
