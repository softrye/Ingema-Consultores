// Execute production Java result/cancellation control flow with only type syntax adapted.
// Does not claim to exercise Credential Manager or JNI on an Android device.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = 'android/src/com/ingema/ingeplus/GoogleNativeSignIn.java';
assert.ok(fs.existsSync(path), 'Native account selector result bridge is missing');
const source = fs.readFileSync(path, 'utf8');
function method(name) {
  const signature = new RegExp('(?:private|public) static void ' + name + '\\([^]*?^    }', 'm');
  const body = source.match(signature);
  assert.ok(body, name + ' implementation must exist');
  return body[0].replace(/(?:private|public) static void (\w+)\(([^)]*)\)/,
    (_, name, args) => 'function ' + name + '(' + args.replace(/\b(?:long|String)\s+/g, '') + ')')
    .replace(/CancellationSignal signal =/g, 'let signal =');
}
function context() {
  const calls = []; let cancellations = 0;
  const state = vm.createContext({pendingRequest: 7, cancellation: {cancel: () => ++cancellations},
    nativeResult: (...args) => calls.push(args)});
  vm.runInContext(method('finish') + '\n' + method('cancel'), state);
  return {state, calls, cancellations: () => cancellations};
}
let run = context();
run.state.finish(6, 'stale-token', ''); assert.equal(run.calls.length, 0);
run.state.finish(7, 'current-token', '');
assert.deepEqual(run.calls, [[7, 'current-token', '']]);
run.state.finish(7, 'duplicate-token', ''); assert.equal(run.calls.length, 1);
run = context(); run.state.cancel(6); assert.equal(run.cancellations(), 0);
run.state.cancel(7); assert.equal(run.cancellations(), 1);
run.state.finish(7, 'cancelled-token', ''); assert.equal(run.calls.length, 0);
run.state.cancel(7); assert.equal(run.cancellations(), 1);
run = context(); run.state.finish(7, '', 'GOOGLE_CANCELLED');
assert.deepEqual(run.calls, [[7, '', 'GOOGLE_CANCELLED']]);
assert.equal(run.state.pendingRequest, 0); assert.equal(run.state.cancellation, null);
console.log('PASS: stale, duplicate, cancelled and current native Google callbacks');
