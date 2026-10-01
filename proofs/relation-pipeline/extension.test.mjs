import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { generate, initialState, inspect } from './engine.mjs';
import { baseRegistry, registry } from './registry.mjs';
import { take } from './take.mjs';
import { hash } from './inventory.mjs';
test('held-out take registration preserves the frozen generator, oracle coordinator, harness and common evidence', () => {
  const extension = JSON.parse(readFileSync(new URL('./extension.json', import.meta.url)));
  assert.deepEqual(Object.keys(extension.postRegistrationCorrections), ['proofs/relation-pipeline/audit.mjs']);
  for (const [path, expected] of Object.entries(extension.frozen)) {
    const correction = extension.postRegistrationCorrections[path];
    if (correction) assert.equal(correction.registrationDigest, expected);
    assert.equal(hash(readFileSync(new URL(`../../${path}`, import.meta.url))), correction?.correctedDigest ?? expected, path);
  }
  assert.deepEqual(registry.slice(0, 3), baseRegistry);
  assert.equal(registry[3], take);
  const pairs = reg => generate(reg).filter(c => c.id.startsWith('pair:')).map(c => c.steps.map(s => s.op).join('/'));
  const initial = pairs(baseRegistry);
  const baseline = JSON.parse(readFileSync(new URL('./baseline.json', import.meta.url)));
  assert.deepEqual(pairs(registry).filter(p => !initial.includes(p)), baseline.extensionMeasurement.newObligations);
  generate(registry).forEach(c => assert.doesNotThrow(() => inspect(c, registry)));
});
test('take requires admitted total order; count and offset stay in the reviewed successful domain', () => {
  const state = initialState();
  assert(!take.enabled({ ...state, order: { total: false } }));
  assert(!take.admits({ ...state, order: { total: false } }, { count: 1, offset: 0 }));
  for (const args of [{ count: 0, offset: 0 }, { count: 1, offset: -1 },
    { count: 1.5, offset: 0 }, { count: 4, offset: 0 }]) assert(!take.admits(state, args));
  const args = generate(registry).flatMap(c => c.steps.filter(s => s.op === 'take').map(s => s.args));
  assert.deepEqual([...new Set(args.map(a => a.count))].sort(), [1, 2, 3]);
  assert.deepEqual([...new Set(args.map(a => a.offset))].sort(), [0, 1, 2]);
});
