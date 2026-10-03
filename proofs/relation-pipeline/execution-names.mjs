// Producer-time identities: lossless compact timestamp/PID encoding keeps the
// actual scientific label intact while fitting the unchanged USTAR name field.
import assert from 'node:assert/strict';
export const receiptSuffixes = Object.freeze(['.json', '.inputs.json', '.fixture.mbt', '.log']);
export function invocationIdentity(part = '', now = Date.now(), pid = process.pid) {
  assert(part === '' || /^L-[CM][01]$/u.test(part), 'Unknown pipeline part');
  assert(Number.isSafeInteger(now) && now >= 0 && Number.isSafeInteger(pid) && pid > 0, 'Invalid invocation identity');
  return part ? `${part}-${now.toString(36)}-${pid.toString(36)}` : `${now}-${pid}`;
}
export function receiptBasename(invocation, serial, label, target) {
  assert(/^[A-Za-z0-9-]+$/u.test(invocation));
  assert(Number.isSafeInteger(serial) && serial >= 0 && serial <= 99999, 'Invalid receipt serial');
  assert(/^[A-Za-z0-9_-]+$/u.test(label), 'Invalid receipt label');
  assert(['js', 'wasm', 'native'].includes(target), 'Invalid receipt target');
  const name = `${invocation}-${String(serial).padStart(4, '0')}-${label}-${target}`;
  assert(receiptSuffixes.every(suffix => Buffer.byteLength(name + suffix) <= 100), 'Receipt basename exceeds USTAR name field');
  return name;
}
