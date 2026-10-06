import test from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {checkPlan, leanInput} from './check.mjs';
import {completeCheckerFixture} from './checker-plan-fixture.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));

test('the unchanged model checks every real-Git full-catalog requirement with the production timeout', () => {
  const fixture = completeCheckerFixture(root);
  assert.equal(fixture.required.length, 30);
  assert(fixture.applications.every(application => !application.reused && !application.closed));
  assert.equal(checkPlan(fixture.required, fixture.applications).accepted, true);
  const source = leanInput(fixture.required, fixture.applications);
  assert(source.includes('apply IncrementalEvidence.checker_complete'));
  assert(!source.includes('native_decide'));
});

test('direct kernel proofs still refuse every application premise and both list-length mismatches', () => {
  const required = {action: 'session-js', candidate: 'a'.repeat(40), kind: 'tested-refinement', target: 'js',
    scope: 'b'.repeat(64), premises: 'c'.repeat(64), inputs: 'd'.repeat(64), minimumUnits: 1};
  const application = {action: required.action, origin: 'e'.repeat(40), kind: required.kind,
    target: required.target, scope: required.scope, premises: required.premises, inputs: required.inputs,
    units: 1, authenticated: true, successful: true, reused: true, closed: true, mainOrigin: true};
  for (const patch of [
    {authenticated: false}, {successful: false}, {action: 'different-action'}, {kind: 'formal-model'},
    {target: 'native'}, {scope: 'f'.repeat(64)}, {premises: 'f'.repeat(64)}, {inputs: 'f'.repeat(64)},
    {units: 0}, {closed: false}, {mainOrigin: false}, {reused: false},
  ]) assert.throws(() => checkPlan([required], [{...application, ...patch}]), /Lean rejected action plan/u);
  assert.throws(() => checkPlan([required], []), /Lean rejected action plan/u);
  assert.throws(() => checkPlan([required], [application, application]), /Lean rejected action plan/u);
});
