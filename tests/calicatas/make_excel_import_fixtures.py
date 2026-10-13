"""Genera fixtures JSON (celdas de texto + rangos combinados) para
tests/calicatas/excel_import.cjs a partir de libros .xlsx reales, con el mismo
contrato que AndroidCalicataExporter::readWorkbookCells (sin imágenes).

Uso: python make_excel_import_fixtures.py <libro.xlsx> <salida.json>
"""
import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
      'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}


def number_text(raw):
    try:
        value = float(raw)
    except ValueError:
        return raw
    if value.is_integer() and abs(value) < 1e15:
        return str(int(value))
    return format(value, '.15g')


def read(path):
    z = zipfile.ZipFile(path)
    shared = []
    if 'xl/sharedStrings.xml' in z.namelist():
        root = ET.fromstring(z.read('xl/sharedStrings.xml'))
        for si in root.findall('m:si', NS):
            shared.append(''.join(t.text or '' for t in si.iter('{%s}t' % NS['m'])))
    wb = ET.fromstring(z.read('xl/workbook.xml'))
    rels = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
    relmap = {r.get('Id'): r.get('Target') for r in rels}
    sheets = []
    for s in wb.find('m:sheets', NS):
        target = relmap[s.get('{%s}id' % NS['r'])].lstrip('/')
        if not target.startswith('xl/'):
            target = 'xl/' + target
        root = ET.fromstring(z.read(target))
        cells = {}
        for c in root.iter('{%s}c' % NS['m']):
            t, v = c.get('t'), c.find('m:v', NS)
            if t == 's' and v is not None:
                text = shared[int(v.text)]
            elif t == 'inlineStr':
                text = ''.join(x.text or '' for x in c.iter('{%s}t' % NS['m']))
            elif t == 'str' and v is not None:
                text = v.text or ''
            elif v is not None:
                text = number_text(v.text)
            else:
                continue
            if text.strip():
                cells[c.get('r')] = text
        merges = [m.get('ref') for m in root.iter('{%s}mergeCell' % NS['m'])]
        sheets.append({'name': s.get('name'), 'cells': cells, 'merges': merges, 'truncated': False})
    return {'ok': True, 'fileName': re.split(r'[\\/]', path)[-1], 'sha256': 'fixture', 'sheets': sheets}


if __name__ == '__main__':
    with open(sys.argv[2], 'w', encoding='utf-8') as out:
        json.dump(read(sys.argv[1]), out, ensure_ascii=False, indent=1, sort_keys=True)
