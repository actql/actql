import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { checkCore } from './source.mjs';
import { maximum, growthCapacity, currentSlotsCeiling, liveSlotsCeiling, admitObservation } from './model.mjs';
test('Int32 fallback preserves the exact requirement instead of wrapping allocation size', () => {
  assert.equal(growthCapacity(1073741824, 1073741824, 1073741825), 1073741825n);
  assert.equal(growthCapacity(1073741825, 1073741825, 1073741826), 1073741826n);
  assert.equal(growthCapacity(maximum - 1n, maximum - 1n, maximum), maximum);
  assert.throws(() => growthCapacity(16, 16, -1));
});
test('a high-water bound survives clear, and does not infer that prior holders vanished', () => {
  assert.equal(currentSlotsCeiling(0), 0n);
  assert.equal(currentSlotsCeiling(1), 8n);
  assert.equal(currentSlotsCeiling(17), 34n);
  assert.equal(currentSlotsCeiling(0, 32), 32n);
  assert.equal(currentSlotsCeiling(1, 32), 32n);
  assert.equal(liveSlotsCeiling(17, 3), 102n);
  assert(liveSlotsCeiling(17, 3) > liveSlotsCeiling(17, 1));
});
test('slot admission rejects whole-target substitution and unsupported byte interpretations', () => {
  const f = { unit: 'MoonBit fixed-buffer slots', capacity: 16, highWater: 9, initialCapacity: 0, allocationBytes: false };
  const c = { highWater: 9, initialCapacity: 0 };
  assert.equal(admitObservation('native', 'native', c, f).slots, '16');
  assert.throws(() => admitObservation('wasm', 'native', c, f));
  assert.throws(() => admitObservation('js', 'js', c, f));
  assert.throws(() => admitObservation('native', 'native', c, { ...f, allocationBytes: true }));
  assert.throws(() => admitObservation('native', 'native', c, { ...f, capacity: 19 }));
  assert.throws(() => admitObservation('native', 'native', c, { ...f, highWater: 100, capacity: 64 }));
});
test('source correspondence requires the installed core, not just a compiler version string', () => {
  const pin = JSON.parse(readFileSync(new URL('../../../../toolchain.json', import.meta.url)));
  const core = process.env.MOON_HOME && process.env.MOON_HOME + '/lib/core';
  assert(core, 'Use the repository-pinned MOON_HOME');
  checkCore(core, pin);
  assert.throws(() => checkCore(core, pin, path => path.endsWith('arraycore_nonjs.mbt')
    ? Buffer.from('unreviewed growth rule') : readFileSync(path)));
});
