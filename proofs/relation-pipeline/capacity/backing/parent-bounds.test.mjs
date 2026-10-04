import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { retainedParentCoreBound, checkParentCensus, inspectParentCorePhases } from '../parent-control/bounds.mjs';
import { admitClaim, subject, unresolved } from '../model.mjs';
const root = fileURLToPath(new URL('../../../../', import.meta.url));
const read = path => readFileSync(join(root, path));
test('retained core composes source-ABI groups with input-derived growth overlap', () => {
  const two = retainedParentCoreBound(2);
  assert.equal(two.slots, 8n); assert.equal(two.bytes, 808n);
  const ten = retainedParentCoreBound(10);
  assert.equal(ten.slots, 20n); assert.equal(ten.bytes, 1000n);
  assert(retainedParentCoreBound(2147483647).bytes < 9223372036854775807n);
  for (const n of [0, 1, -1, 2147483648, 1.5]) assert.throws(() => retainedParentCoreBound(n));
  assert.equal(two.fullParentUpper, false); assert.equal(two.completePipelineUpper, false);
  assert.throws(() => admitClaim({ subject, kind: 'structural-model-and-finite-correspondence',
    units: 'filled entries and numeric content octets', unresolved: [...unresolved],
    unconditionalAllocationBytes: true }));
});
// Validator inputs only: these are not execution/refinement evidence.
function lifecycle() {
  const base = { kind: 'parent core observation', parent: '1', environment: '30', count: 2,
    position: 0, pending: 0, terminal: 0, reclaimed: 0, children: 1, childrenSlots: 1,
    array: '31', backing: '32', staticBacking: false, backingStorageBytes: 16,
    dynamicBackingBytes: 16, indexedBytes: 496, scalarRefs: 7, reportedScalar: true,
    roots: Array.from({ length: 11 }, (_, i) => String(i + 1)),
    callbacks: Array.from({ length: 5 }, (_, i) => String(i + 20)) };
  const terminal = { position: 1, terminal: 1, children: 2, childrenSlots: 8,
    backingStorageBytes: 72, dynamicBackingBytes: 72 };
  const reclaimed = { ...terminal, reclaimed: 1, children: 0, childrenSlots: 0,
    array: '33', backing: '34', staticBacking: true, backingStorageBytes: 8, dynamicBackingBytes: 0 };
  return [{ phase: 5 }, { phase: 6 }, { phase: 1 }, { phase: 2, ...terminal },
    { phase: 1, ...terminal }, { phase: 2, ...terminal }, { phase: 5, ...terminal },
    { phase: 6, ...reclaimed }, { phase: 5, ...reclaimed }, { phase: 6, ...reclaimed }]
    .map(f => ({ ...structuredClone(base), ...f }));
}
test('parent phase validation binds identities, callback pairs and input-derived capacity', () => {
  const testCase = { steps: [{}, {}] }, startup = { parent: '1', count: 2 };
  const inspect = (facts, target = 'native') => inspectParentCorePhases(testCase, startup, facts, target);
  const result = inspect(lifecycle());
  assert.equal(result.recipe.bytes, '808'); assert.equal(result.actualPhases, 10);
  assert.equal(result.completePipelineUpper, false);
  assert.throws(() => inspect(lifecycle(), 'wasm'), /native only/);
  const alias = lifecycle(); alias[0].array = alias[0].roots[1];
  assert.throws(() => inspect(alias), /alias unexpectedly/);
  const changed = lifecycle(); changed[2].callbacks[0] = '40';
  assert.throws(() => inspect(changed), /captures changed/);
  const oversized = lifecycle(); oversized[3].childrenSlots = 9;
  assert.throws(() => inspect(oversized), /input-derived capacity/);
  const unpaired = lifecycle(); unpaired[1].phase = 4;
  assert.throws(() => inspect(unpaired), /before\/after/);
  const lost = lifecycle(); lost[1].children = 0;
  assert.throws(() => inspect(lost), /holders disappeared/);
  assert.throws(() => inspect(lifecycle().slice(0, 8)), /cleanup\/retry/);
});
test('the source census includes transitive selection and unchanged retained control after cleanup', () => {
  const inventory = checkParentCensus(read);
  assert.equal(inventory.providerConstructors.length, 11);
  assert(inventory.included.find(r => r.id === 'retirement-and-custody').phases.includes('retained-owner-after-cleanup'));
  assert(inventory.included.find(r => r.id === 'selected-step-context').objects.includes('traversal ceilings'));
  const generated = 'src/execution_relation/generated_sequence.mbt';
  assert.throws(() => checkParentCensus(p => p === generated ? read(p).toString().replace(
    'traversal_ceilings : Array[(Int, Int64, Int64)]',
    'traversal_ceilings : Array[(Int, String, Int64)]') : read(p)), /Unreviewed parent\/edge field or type/);
  const path = 'src/connectors/local/managed_provider.mbt';
  assert.throws(() => checkParentCensus(p => p === path ? read(p).toString().replace(
    'mut reported_work : Result[Int64, ManagedProviderWorkIssue]', 'mut reported_work : Array[Int64]') : read(p)), /Unreviewed parent\/edge field or type/);
  const selected = 'src/connectors/local/selected_relation_provider.mbt';
  assert.throws(() => checkParentCensus(p => p === selected ? read(p).toString().replace(
    '      values_provider(execution, measurement),', '') : read(p)), /Unreviewed provider-selection allocation/);
});
