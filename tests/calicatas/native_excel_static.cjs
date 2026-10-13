// Source guard for the reported regression; generated XLSX validation lives in
// native_excel_contract.py and the production-export checks in checks.cpp.
const fs = require('fs');
const assert = require('assert');
const source = fs.readFileSync('androidcalicataexporter.cpp', 'utf8');
const body = source.slice(source.indexOf('bool writeScaledProfile('), source.indexOf('bool fillOfficialCalicataTemplate('));
assert(!body.includes('QPainter') && !body.includes('textInBand'), 'Form data cannot be painted into an image');
assert(!body.includes('BE1') && !body.includes('57 + col'), 'Data cannot be moved into an off-page ledger');
assert(body.includes('xlsx.write(r1, 10, desc'), 'Description belongs in native column J');
assert(body.includes('writeNativeText(31,') && body.includes('writeNativeText(34, sucs)'), 'AE/AH must contain native data');
assert(body.includes('writePercentageTemplateValue(xlsx, QXlsx::CellReference(r1, 35 + col)'), 'Laboratory values must be numeric Excel cells');
assert(!body.includes('insertImageFitted('), 'No full-body bitmap insertion');
console.log('PASS: native form data source guards');
