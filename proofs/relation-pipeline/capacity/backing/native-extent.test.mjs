import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fieldLayout, admittedMapExtent, distinctMapExtent } from './native-extent.mjs';
import { checkNativeRuntime } from './source.mjs';
test('declared field order includes internal and trailing padding', () => {
  assert.deepEqual(fieldLayout(['i32', 'ref', 'i32', 'i32', 'ref', 'i32']),
    { offsets: [0, 8, 16, 20, 24, 32], payloadBytes: 40 });
  assert.equal(admittedMapExtent(0), 120n); assert.equal(admittedMapExtent(3), 264n);
  assert.throws(() => admittedMapExtent(7));
});
test('three ordinal tables exclude the tuple Array snapshot', () => {
  for (const w of [1, 2, 3]) {
    assert.equal(distinctMapExtent(w), 360n + 96n * BigInt(w));
  }
  assert.throws(() => distinctMapExtent(4));
});
test('a matching compiler name does not replace installed runtime source identity', () => {
  const home = process.env.MOON_HOME; assert(home);
  const pin = JSON.parse(readFileSync(new URL('../../../../toolchain.json', import.meta.url)));
  checkNativeRuntime(home, pin);
  assert.throws(() => checkNativeRuntime(home, pin, p => p.endsWith('moonbit.h')
    ? Buffer.from('another object header') : readFileSync(p)));
});
