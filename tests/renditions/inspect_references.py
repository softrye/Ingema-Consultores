from pathlib import Path
import json, openpyxl
from pypdf import PdfReader
root=Path(__file__).resolve().parents[2]
book=openpyxl.load_workbook(root/'artifacts/rendition-v1.xlsx',data_only=False)
report={'source':'Existing defective exporter fixture; NOT approved template','sheets':[]}
for sheet in book:
 report['sheets'].append({'name':sheet.title,'size':[sheet.max_row,sheet.max_column],
  'cells':[{ 'cell':c.coordinate,'value':c.value,'style':c.style_id,'format':c.number_format} for row in sheet for c in row if c.value is not None],
  'merges':[str(v) for v in sheet.merged_cells.ranges], 'images':len(sheet._images),
  'print_area':str(sheet.print_area),'orientation':sheet.page_setup.orientation})
pdf=PdfReader(root/'artifacts/rendition-v1.pdf')
report['pdf']=[{'page':i+1,'size':[float(v) for v in page.mediabox],'text':page.extract_text()} for i,page in enumerate(pdf.pages)]
dest=root/'docs/RENDITIONS_REFERENCE_INSPECTION_20260914.json'
dest.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'sheets':book.sheetnames,'pdf_pages':len(pdf.pages),'classification':report['source']}))
