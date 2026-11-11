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
  for (const changed of ['arraycore_nonjs.mbt', 'linked_hash_map.mbt']) {
    assert.throws(() => checkCore(core, pin, path => path.endsWith(changed)
      ? Buffer.from('unreviewed growth rule') : readFileSync(path)));
  }
});

// Exercise the auditor's actual model-log block, not a duplicate validator.
// The independent Lean inventory and existing producer each declare THREE
// conditional native Map propositions; this is not a complete capacity seal.
test('capacity audit requires the actual three native Map extent propositions', () => {
  const lean = readFileSync(new URL('./NativeMapExtent.lean', import.meta.url), 'utf8');
  assert.deepEqual([...lean.matchAll(/^theorem\s+(\w+)/gm)].map(([, name]) => name),
    ['table_bound', 'empty_extent', 'current_distinct']);
  const producer = readFileSync(new URL('./check.mjs', import.meta.url), 'utf8');
  assert(producer.includes("const nativeNames = ['table_bound', 'empty_extent', 'current_distinct'];"));
  assert(producer.includes("console.log('3 conditional native Map extent propositions checked;"));
  const source = readFileSync(new URL('../audit.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('    assert.deepEqual(report.backingModel.command,');
  const end = source.indexOf('\n  }\n  admitClaim(report.claim);', start);
  assert(start > 0 && end > start);
  const consume = Function('assert', 'hash', 'read', 'report', 'current', source.slice(start, end));
  const log = ['6 array backing model propositions checked',
    '4 restricted Map model propositions checked',
    '3 conditional native Map extent propositions checked',
    '3 selected native Array extent propositions checked'].join('\n');
  const hash = value => String(value);
  const current = {digest: 'original fixture Source digest'};
  const report = {backingModel: {command: ['node', 'proofs/relation-pipeline/capacity/backing/check.mjs'],
    exit: 0, sourceDigest: current.digest, logPath: 'same-model.log', logDigest: hash(log)}};
  const verify = (value, original = report) => consume(assert, hash, path => {
    assert.equal(path, 'same-model.log'); return Buffer.from(value);
  }, original, current);
  verify(log);
  for (const changed of [
    log.replace('3 conditional native Map', '4 conditional native Map'),
    log.replace('3 selected native Array', '2 selected native Array'),
    log.replace('4 restricted Map', '3 restricted Map'),
  ]) assert.throws(() => verify(changed, {backingModel: {...report.backingModel, logDigest: hash(changed)}}));
  assert.throws(() => verify(log, {backingModel: {...report.backingModel, exit: 1}}));
  assert.throws(() => verify(log, {backingModel: {...report.backingModel, sourceDigest: 'foreign'}}));
  assert.throws(() => verify(log, {backingModel: {...report.backingModel, logDigest: 'foreign'}}));
});
