'use strict';
// Teselas SUCS idénticas a Web (feature/calicatas-cloud-media-04a,
// src/lib/calicatas/sucsSymbols.ts). Este módulo reproduce el mismo ensamblado
// de cadenas; la prueba web_lab_parity.cjs exige que SUCS/web/*.svg coincidan
// byte a byte. `node tests/calicatas/web_sucs_symbols.cjs --write` regenera.
const fs = require('fs');
const path = require('path');

const CODES = ['GW', 'GP', 'GM', 'GC', 'SW', 'SP', 'SM', 'SC', 'ML', 'CL', 'OL', 'MH', 'CH', 'OH', 'PT'];
const diagonal = '<path d="M-6 6L6-6M0 24L24 0M18 30L30 18"/>';
const vertical = '<path d="M6 0V24M18 0V24"/>';
const dots = (radius) => `<circle cx="4" cy="5" r="${radius}"/><circle cx="15" cy="10" r="${radius}"/><circle cx="7" cy="20" r="${radius}"/><circle cx="22" cy="21" r="${radius}"/>`;
const stones = '<path d="M3 4L7 2L10 5L8 9L4 10L2 7ZM16 15L20 13L23 17L21 21L17 20L15 18Z"/>';
const beads = (radius) => `<circle cx="6" cy="7" r="${radius}"/><circle cx="18" cy="18" r="${radius}"/>`;
const inclinedBeads = (radius) => `<circle cx="6" cy="18" r="${radius}"/><circle cx="18" cy="6" r="${radius}"/>`;
function symbols(dotRadius, beadRadius) {
  return {
    GW: `<g fill="none">${stones}</g>${dots(dotRadius)}`,
    GP: `<g>${stones}</g>${dots(dotRadius)}`,
    GM: `${vertical}${beads(beadRadius)}`,
    GC: `${diagonal}${inclinedBeads(beadRadius)}`,
    SW: dots(dotRadius),
    SP: `${dots(dotRadius)}<circle cx="4" cy="13" r="${dotRadius}"/><circle cx="15" cy="23" r="${dotRadius}"/><circle cx="22" cy="4" r="${dotRadius}"/>`,
    SM: `${vertical}${beads(beadRadius)}`,
    SC: `${diagonal}${inclinedBeads(beadRadius)}`,
    ML: vertical,
    CL: diagonal,
    OL: '<path d="M6 0V24M18 0V24" stroke-dasharray="6 4"/>',
    MH: '<path d="M3 0V24M9 0V24M15 0V24M21 0V24"/>',
    CH: `${diagonal}<path d="M-6 18L18-6M6 30L30 6"/>`,
    OH: `<g stroke-dasharray="5 4">${diagonal}<path d="M-6 18L18-6M6 30L30 6"/></g>`,
    PT: '<path fill="none" d="M0 7L3 2L6 12L9 2L12 12L15 2L18 12L21 2L24 7M0 19L3 14L6 24L9 14L12 24L15 14L18 24L21 14L24 19"/>',
  };
}
function svg(code, strokeWidth, dotRadius, beadRadius) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g stroke="#111827" fill="#111827" stroke-width="${strokeWidth}">${symbols(dotRadius, beadRadius)[code]}</g></svg>`;
}
// sucsSymbolUrl / sucsExportSymbolUrl (mismos parámetros que Web).
const display = (code) => svg(code, '1.1', '.7', '1.8');
const exported = (code) => svg(code, '2.3', '1.8', '2.8');

module.exports = { CODES, display, exported };

if (require.main === module && process.argv.includes('--write')) {
  const root = path.join(__dirname, '..', '..', 'SUCS', 'web');
  fs.mkdirSync(path.join(root, 'export'), { recursive: true });
  for (const code of CODES) {
    fs.writeFileSync(path.join(root, `${code}.svg`), display(code));
    fs.writeFileSync(path.join(root, 'export', `${code}.svg`), exported(code));
  }
  console.log(`SUCS/web: ${CODES.length} teselas + ${CODES.length} de exportación`);
}
