import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {plan, planDigest, partIds, partJobs, partStages, capacityPartIds, mutationPartIds,
  mutationNamesByPart, logicalMutationNamesByPart, capacityObligationsByPart,
  logicalCapacityObligationsByPart, capacityMutationNames, partFamily, partRole} from './proof-parts.mjs';
import {variants} from './mutation-registry.mjs';

test('eight hosted proof owners keep exact independent atoms and full logical mutation aliases', () => {
  assert.deepEqual(partIds, ['L-C2', 'L-C3', 'L-C4', 'L-C5', 'L-M2', 'L-M3', 'L-M4', 'L-M5']);
  assert.deepEqual(Object.values(mutationNamesByPart).flat(), variants.map(variant => variant.name));
  assert(Object.values(mutationNamesByPart).every(names => names.length === 2));
  assert.deepEqual(logicalMutationNamesByPart, {
    'L-M0': ['handoff-wrong-port', 'stable-tie-reversed', 'rename-nullability-widened', 'rename-type-changed'],
    'L-M1': ['rename-swap-wrong-input', 'distinct-first-column-only', 'distinct-reversed-survivors', 'distinct-handoff-wrong-port'],
  });
  assert.equal(new Set(Object.values(partJobs)).size, partIds.length);
  assert.deepEqual(Object.values(plan.logicalAliases).flat(), partIds);
  for (const id of mutationPartIds) {
    assert.equal(partFamily(id), 'mutations');
    assert.deepEqual(partStages[id], ['source', 'baseline', 'mutations']);
  }
  for (const id of ['L-M0', 'L-M1', 'L-C0', 'L-C1', 'L-M6', 'foreign'])
    assert.throws(() => partFamily(id), /Unknown proof part/u);
  assert.equal(planDigest, createHash('sha256').update(JSON.stringify(plan)).digest('hex'));
  assert.throws(() => plan.parts['L-M2'].variants.push('extra'), TypeError);
});

test('capacity hosted roles retain complete normal tuple support receipts and all five mutant atoms', () => {
  assert.deepEqual(capacityPartIds.map(partRole), ['capacity-normal', 'capacity-support', 'capacity-mutants', 'capacity-mutants']);
  const normal = capacityObligationsByPart['L-C2'];
  assert.deepEqual(normal.normal, {caseCount: 28, targets: ['js', 'wasm', 'native']});
  assert.deepEqual(normal.boundaries, {values: [-1, 0, 1], caseCount: 28, targets: ['js', 'wasm', 'native']});
  assert.deepEqual(normal.finalNormal, {caseCount: 114, targets: ['js', 'wasm', 'native']});
  assert.deepEqual(capacityObligationsByPart['L-C3'], {backingCore: ['js', 'wasm', 'native'],
    backingModel: true, structuralModel: true, custody: {healthy: 9, negative: 2}, nativeParentStartup: true});
  assert.deepEqual(capacityMutationNames, ['missing-index-reservation', 'premature-keep-release',
    'duplicate-index-release', 'handoff-copy-without-accounting', 'oversized-metadata-map']);
  assert.deepEqual(logicalCapacityObligationsByPart['L-C1'].mutations, capacityMutationNames);
  assert.equal(logicalCapacityObligationsByPart['L-C1'].healthy, 15);
  for (const id of ['L-C4', 'L-C5']) {
    const value = capacityObligationsByPart[id];
    assert.equal(value.healthy, value.mutations.length * value.replayTargets.length);
    assert.equal(value.ownerLocalRestoration.caseCount, value.mutations.length);
  }
});
