// Regression guard for Android foreground transitions (no Android build required).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'graphics', 'InGeGraphicsCore.cpp'),
  'utf8'
);

function section(start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  assert.ok(from >= 0 && to > from, 'section not found: ' + start);
  return source.slice(from, to);
}

const constructor = section(
  'InGeGraphicsCore::InGeGraphicsCore(',
  'QString InGeGraphicsCore::graphicsBackend()'
);
assert.match(constructor, /QGuiApplication::applicationStateChanged/);
assert.match(constructor, /QTimer::singleShot\(0, this, \[this\]/);
assert.doesNotMatch(
  constructor,
  /if \(state == Qt::ApplicationActive\)\s*restoreAfterExternalActivityIfReady\(\)/
);

const completed = section(
  'void InGeGraphicsCore::completeExternalActivity()',
  'void InGeGraphicsCore::restoreAfterExternalActivityIfReady()'
);
assert.match(completed, /QTimer::singleShot\(0, this, \[this\]/);

const restored = section(
  'void InGeGraphicsCore::restoreAfterExternalActivityIfReady()',
  'void InGeGraphicsCore::inspectRuntime('
);
assert.match(restored, /m_externalActivityRestorePending/);
assert.match(restored, /Qt::ApplicationActive/);
assert.match(restored, /!window->isExposed\(\)/);

console.log('PASS: Android lifecycle window restoration stays deferred and surface-guarded');
