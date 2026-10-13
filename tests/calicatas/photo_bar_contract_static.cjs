'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const form = fs.readFileSync(path.resolve(__dirname, '../../qml/Mobile/pages/CalicataFormPage.qml'), 'utf8');
assert.match(form, /component PhotoBar:\s*Item\s*\{/);
for (const property of ['onDark', 'barRadius', 'absorbTaps']) {
  assert.match(form, new RegExp('property\\s+\\w+\\s+' + property + '\\s*:'));
}
assert.doesNotMatch(form, /(?:^|\n)\s*(?:rimColor|veilColor)\s*:/m,
  'PhotoBar is a flat material; obsolete glass-only properties must not be assigned');
console.log('PASS photo_bar_contract_static');
