import test from 'node:test';
import assert from 'node:assert/strict';
import {mutationIds, mutationContracts} from './mutation-inventory.mjs';
import {mutationObservation} from './mutation-observation.mjs';

const fixture = () => ({source: {digest: 'a'.repeat(64)}, revision: 'b'.repeat(40), sourceRestored: true,
  results: mutationIds.map(id => ({id, ...mutationContracts[id], target: 'js', killed: true, failureCount: 1}))});

test('scientific observations preserve every registered location, selection and detection result', () => {
  const result = fixture(), before = JSON.stringify(result), observed = mutationObservation(result);
  assert.equal(observed.observations.length, 13); assert.equal(JSON.stringify(result), before);
  const changedContext = {...result, revision: 'c'.repeat(40), source: {digest: 'd'.repeat(64)}};
  assert.equal(mutationObservation(changedContext).digest, observed.digest);
  // Context is excluded from scientific projection only; its independent
  // source/revision/receipt authentication is still mandatory at the caller.
  const changedDetection = structuredClone(result); changedDetection.results[0].failureCount = 2;
  assert.notEqual(mutationObservation(changedDetection).digest, observed.digest);
});

test('the same total cannot conceal wrong experiments or a non-assertion detection', () => {
  for (const alter of [
    result => result.results[0].path = result.results[4].path,
    result => result.results[0].suite = 'src/unrelated',
    result => result.results[0].filter = 'unrelated*',
    result => result.results[0].target = 'native',
    result => result.results[0].killed = false,
    result => result.results[0].failureCount = 0,
    result => result.results[0].failureCount = 1.5,
    result => result.results[0].id = result.results[1].id,
  ]) {
    const result = fixture(); alter(result); assert.throws(() => mutationObservation(result));
  }
});
