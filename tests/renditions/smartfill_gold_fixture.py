"""Synthetic E001-884 evidence for the real job bus; not the original invoice."""
import base64
import json
import fitz

TEXT = """JORGE ZANABRIA ROLY
RUC: 10459805597
FACTURA ELECTRONICA E001-884
FECHA DE EMISION: 28/05/2026
CLIENTE: INGEMA CONSULTORES S.A.C.
RUC CLIENTE: 20601789800
MONEDA: SOLES PEN
CONCEPTO: EPP / herramientas
SUBTOTAL 238.14
IGV 42.86
TOTAL S/ 281.00
CONDICION: CONTADO
"""

if __name__ == '__main__':
    doc = fitz.open()
    doc.new_page().insert_text((50, 60), TEXT, fontsize=12)
    print(json.dumps({
        'evidences': [{'id': 'gold-e001-884', 'name': 'synthetic-e001-884.pdf',
                       'data': base64.b64encode(doc.tobytes()).decode()}],
        'context': {'module': 'renditions', 'rules': {
            'period_start': '2026-09-01', 'period_end': '2026-09-30',
            'categories': [{'code': 'EPP', 'name': 'EPP y herramientas'}],
            'support_types': [{'code': 'FACTURA', 'name': 'Factura'}],
            'payment_methods': [{'code': 'EFECTIVO', 'name': 'Efectivo'}]}}
    }))
