"""Read-only Golden contract; fixtures are derived from the workbook, never production defaults."""
import argparse
import json
from copy import copy
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile
import openpyxl

parser = argparse.ArgumentParser()
parser.add_argument('golden', type=Path)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
out = Path('outputs/calicatas-p0').resolve()
out.mkdir(parents=True, exist_ok=True)
g = openpyxl.load_workbook(args.golden)
s = g['Calicata']
ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}

def structure(path):
    with ZipFile(path) as z:
        sheet = ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
        return {key: ET.tostring(sheet.find('s:' + key, ns), encoding='unicode')
                if sheet.find('s:' + key, ns) is not None else ''
                for key in ['dimension','cols','pageMargins','pageSetup','printOptions']}

if not args.output:
    images = {}
    for index, image in enumerate(s._images):
        row, col = image.anchor._from.row, image.anchor._from.col
        key = ('foto1_path' if row == 20 else 'foto2_path' if row == 42 else
               'foto3_path' if row == 62 else 'logo_mtc_path' if row == 5 and col == 1 else
               'logo_proyecto_path' if row == 5 and col == 15 else '')
        if key:
            path = out / (key + '.' + image.format)
            path.write_bytes(image._data())
            images[key] = str(path)
    layers = []
    for row in range(22, 82):
        if s[f'AH{row}'].value:
            a, b = str(s[f'AE{row}'].value).split('-')
            layer = dict(id=f'golden-{row}', de=a, a=b, muestra_desde=a, muestra_hasta=b,
                         descripcion=s[f'J{row}'].value, tipo_muestra=s[f'AD{row}'].value,
                         sucs=s[f'AH{row}'].value, aashto=s[f'AG{row}'].value)
            for key, col in [('gmax','AI'),('g2','AJ'),('g04','AK'),('g008','AL'),('g002','AM'),('wl','AN'),('lp','AO'),('hum2','AP')]:
                if s[f'{col}{row}'].value is not None: layer[key] = s[f'{col}{row}'].value
            layers.append(layer)
    state = dict(header=dict(codigo=s['AY9'].value, project_full_name=s['AG4'].value,
                 supervisor=s['AJ9'].value, maquina=s['AJ10'].value, lado_via=s['AJ11'].value,
                 pk=s['AT8'].value, utm_x=s['AT9'].value, utm_y=s['AT10'].value,
                 utm_z=s['AT11'].value,zona=s['AW10'].value,fecha_inicio='2025-01-08',fecha_fin='2025-01-08'),
                 cortes=layers, images=images)
    (out/'golden-fixture.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'golden-structure.json').write_text(json.dumps(structure(args.golden),indent=2),encoding='utf-8')
    print('GOLDEN', args.golden, 'sheet',s.title,'dimension',s.calculate_dimension(),'print_area',s.print_area,'images',len(s._images))
else:
    w = openpyxl.load_workbook(args.output); t = w['Calicata']
    checks = {}
    checks['sheet_names'] = g.sheetnames == w.sheetnames
    fin = next(row for row in range(82, t.max_row + 1)
               if str(t.cell(row, 17).value).startswith('FIN DE LA CALICATA'))
    delta = fin - 82
    def fixed_merges(sheet, offset=0):
        return {(x.min_row - (offset if x.min_row >= 83 + offset else 0), x.min_col,
                 x.max_row - (offset if x.max_row >= 83 + offset else 0), x.max_col)
                for x in sheet.merged_cells if x.max_row <= 20 or x.min_row >= 83 + offset}
    checks['fixed_merged_ranges'] = fixed_merges(s) == fixed_merges(t, delta)
    checks['print_area'] = t.print_area == "'Calicata'!$B$1:$BC$" + str(89 + delta)
    def height(sheet, first, last):
        return sum(sheet.row_dimensions[row].height or 15 for row in range(first, last + 1))
    checks['printed_height'] = abs(height(s, 1, 89) - height(t, 1, 89 + delta)) < .02
    checks['profile_height'] = abs(height(s, 22, 81) - height(t, 22, fin - 1)) < .02
    checks['column_widths'] = all(s.column_dimensions[k].width == t.column_dimensions[k].width for k in s.column_dimensions)
    def effective_page_setup(sheet):
        setup = dict(sheet.page_setup)
        fit = sheet.sheet_properties.pageSetUpPr.fitToPage
        if not fit:
            setup.pop('fitToHeight', None); setup.pop('fitToWidth', None)
        return setup, bool(fit)
    checks['page_setup'] = effective_page_setup(s) == effective_page_setup(t)
    checks['no_off_page_ledger'] = t['BE1'].value is None
    checks['page_margins'] = dict(s.page_margins) == dict(t.page_margins)
    checks['no_body_bitmap'] = not any(im.anchor._from.row >= 21
        and im.anchor._from.col < 46 and getattr(im.anchor, 'to', im.anchor._from).col > 9
        for im in t._images)
    checks['formulas'] = [(c.coordinate,c.value) for row in s for c in row if c.data_type=='f'] == [(c.coordinate,c.value) for row in t for c in row if c.data_type=='f']
    cells = ['AJ9','AJ10','AJ11','AT8','AT9','AT10','AT11','AW10','AY9','AU8','AU9']
    checks['required_values'] = all(s[c].value == t[c].value for c in cells)
    source_rows = [row for row in range(22, 82) if s[f'AH{row}'].value]
    checks['all_strata_preserved'] = True
    target_rows = [row for row in range(22, fin) if t.cell(row, 34).value]
    checks['all_strata_preserved'] &= len(source_rows) == len(target_rows)
    for row, target_row in zip(source_rows, target_rows):
        start, end = str(s[f'AE{row}'].value).split('-')
        interval = f'{float(start):.2f}-{float(end):.2f}'
        source_desc = str(s[f'J{row}'].value or '')
        checks['all_strata_preserved'] &= (t.cell(target_row, 31).value == interval
            and str(t.cell(target_row, 10).value or '').endswith(source_desc)
            and t.cell(target_row, 34).value == s[f'AH{row}'].value
            and t.cell(target_row, 30).value == s[f'AD{row}'].value
            and t.cell(target_row, 33).value == s[f'AG{row}'].value)
        for old_col, new_col, percent in [('AI',35,True),('AJ',36,True),('AK',37,True),
            ('AL',38,True),('AM',39,True),('AN',40,False),('AO',41,False),('AP',42,True)]:
            expected = s[f'{old_col}{row}'].value
            if expected is None: continue
            actual = t.cell(target_row, new_col).value
            if isinstance(expected, (int, float)):
                number = float(str(actual).replace('%', ''))
                if percent and not isinstance(actual, (int, float)): number /= 100
                checks['all_strata_preserved'] &= abs(number - expected) < 0.0001
            else:
                checks['all_strata_preserved'] &= str(actual) == str(expected)
    checks['fixed_styles'] = all(copy(getattr(s[c],a)) == copy(getattr(t[c],a)) for c in ['B13','J13','AR8','AU13'] for a in ['font','fill','border','alignment','number_format','protection'])
    def anchor_y(sheet, marker):
        return height(sheet, 1, marker.row) + marker.rowOff / 12700
    photo_areas = [(height(s, 1, lo), height(s, 1, hi)) for lo, hi in [(20, 41),(42, 61),(62, 82)]]
    for index, (lo, hi) in enumerate(photo_areas, 1):
        checks[f'photo{index}'] = sum(1 for im in t._images if im.anchor._from.col >= 46
            and lo - .02 <= anchor_y(t, im.anchor._from) < hi) == 1
    checks['logos'] = sum(1 for im in t._images if im.anchor._from.row >= 5 and im.anchor._from.row < 9 and im.anchor._from.col < 32) == 2
    details = {c:[s[c].value,t[c].value] for c in cells if s[c].value != t[c].value}
    result = {'checks':checks,'value_differences':details,'missing_merges':sorted(set(map(str,s.merged_cells))-set(map(str,t.merged_cells))),'extra_merges':sorted(set(map(str,t.merged_cells))-set(map(str,s.merged_cells)))}
    (out/'golden-comparison.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    raise SystemExit(0 if all(checks.values()) else 1)
