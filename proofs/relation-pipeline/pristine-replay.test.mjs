import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pristineAction, pristineCases, validatePristineReport} from './pristine-replay.mjs';
import {logicalMutationNamesByPart as mutationNamesByPart, plan} from './proof-parts.mjs';

test('the registered pristine phase covers all assigned independent fixed minima without changing full obligations', () => {
  const original = JSON.parse(readFileSync(new URL('./regressions.json', import.meta.url)));
  const cases = pristineCases();
  assert.equal(cases.length, 4);
  assert.deepEqual(cases.map(entry => entry.name), mutationNamesByPart['L-M0']);
  for (const entry of cases) assert.deepEqual(entry.testCase, original.find(item => item.name === entry.name).testCase);
  assert.equal(pristineAction.target, 'js'); assert.equal(pristineAction.phase, 'pristine');
  for (const id of plan.logicalAliases['L-M0']) {
    assert.deepEqual(plan.parts[id].replayTargets, ['js', 'wasm', 'native']);
    assert.deepEqual(plan.parts[id].modes, ['fixed', 'explore']);
  }
});

test('successful labels, missing executions and broadened phase scope are not pristine evidence', () => {
  const source = {digest: 'a'.repeat(64), sources: {}};
  const report = {version: 'actql-pipeline-pristine-phase/0.1', action: pristineAction,
    source, units: 4, sourcePreserved: true, reuseAuthorized: false, observations: [], receipts: []};
  assert.throws(() => validatePristineReport(report, source, {}));
  for (const action of [{...pristineAction, target: 'native'}, {...pristineAction, part: 'L-M1'},
    {...pristineAction, phase: 'post-restore'}])
    assert.throws(() => validatePristineReport({...report, action}, source, {}));
  assert.throws(() => validatePristineReport({...report, reuseAuthorized: true}, source, {}));
});
