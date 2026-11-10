const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
// Execute the shared C++ session-finalization decisions; adapt Qt JSON/date syntax only.
const cpp = fs.readFileSync('authsession.cpp', 'utf8');
const finalizer = cpp.match(/void AuthSession::finishGoogleAuthSession\([^]*?^}/m);
assert.ok(finalizer, 'Native and PKCE must finish through the same profile/MFA path');
const finalizeCode = finalizer[0]
  .replace(/void AuthSession::finishGoogleAuthSession\([^)]*\)/, 'function finalize(session)')
  .replace(/QStringLiteral\(("[^"]*")\)/g, '$1')
  .replace(/\.toString\(\)\.isEmpty\(\)/g, '.toString() === ""')
  .replace(/const QString /g, 'const ')
  .replace(/mfaFactor\.isEmpty\(\)/g, '(mfaFactor.length === 0)')
  .replace(/QString\(\)/g, '""').replace(/QDateTime\(\)/g, 'null')
  .replace(/m_loginEmailExact\.clear\(\)/g, 'm_loginEmailExact = ""')
  .replace(/QDateTime::currentDateTimeUtc\(\)\.addDays\(30\)/g, '30')
  .replace(/^\s*qInfo\(\)\.noquote\(\).*;$/gm, '')
  .replace(/\bemit /g, '');
function jsonObject(object) {
  return {value: key => ({toString: () => typeof object?.[key] === 'string' ? object[key] : '',
    toObject: () => jsonObject(object?.[key] || {})}), raw: object};
}
function finalize(session, remember) {
  const events = [];
  const state = vm.createContext({m_rememberFor30Days: remember, m_rememberUntilUtc: -1,
    m_loginEmailExact: 'Previous@Example.invalid', m_mfaPendingSession: null, m_mfaPendingFactor: '',
    failOAuth: code => events.push(code), setOAuthInProgress: () => {}, setLastLoginFailure: () => {},
    verifiedTotpFactor: user => user.raw.factor || '', mfaChanged: () => events.push('mfaChanged'),
    mfaRequired: () => events.push('mfaRequired'), finishAuthSuccess: data => events.push(['finish',data.raw])});
  vm.runInContext(finalizeCode, state); state.finalize(jsonObject(session));
  return {events, state};
}
const valid = {access_token: 'test-access', refresh_token: 'test-refresh',
  user: {id: 'existing-user', email: 'ExactCase@Example.invalid'}};
for (const missing of ['access_token', 'refresh_token', 'user']) {
  const data = {...valid}; delete data[missing];
  assert.deepEqual(finalize(data, true).events, ['INVALID_RESPONSE']);
}
let result = finalize(valid, true);
assert.deepEqual(result.events, [['finish', valid]]); assert.equal(result.state.m_rememberUntilUtc, 30);
result = finalize({...valid,user:{...valid.user,factor:'verified-factor'}}, false);
assert.deepEqual(result.events, ['mfaChanged','mfaRequired']);
assert.equal(result.state.m_mfaPendingFactor, 'verified-factor');
assert.equal(result.state.m_rememberUntilUtc, null);
console.log('PASS: malformed session rejection, exact server email, remember policy and MFA gate');
