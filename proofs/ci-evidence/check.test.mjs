import test from 'node:test';
import assert from 'node:assert/strict';
import {checkPlan, leanInput} from './check.mjs';

const requirement = {action: 'session-js', candidate: 'a'.repeat(40), kind: 'tested-refinement', target: 'js',
  scope: 'b'.repeat(64), premises: 'c'.repeat(64), inputs: 'd'.repeat(64), minimumUnits: 1};
const application = {action: requirement.action, origin: 'e'.repeat(40), kind: requirement.kind,
  target: requirement.target, scope: requirement.scope, premises: requirement.premises, inputs: requirement.inputs,
  units: 7, authenticated: true, successful: true, reused: true, closed: true, mainOrigin: true};

test('the executed Lean checker accepts a closed reuse and a current fresh application', () => {
  assert.equal(checkPlan([requirement], [application]).accepted, true);
  assert.equal(checkPlan([requirement], [{...application, reused: false, origin: requirement.candidate,
    closed: false, mainOrigin: false}]).accepted, true);
});

test('the executed Lean checker rejects an internally consistent other target and a missing obligation', () => {
  assert.throws(() => checkPlan([requirement], [{...application, target: 'native'}]), /Lean rejected/u);
  assert.throws(() => checkPlan([requirement], []), /Lean rejected/u);
});

test('only bounded identity data is emitted as Lean source', () => {
  assert.throws(() => leanInput([requirement], [{...application, action: 'x"\naxiom forged : False'}]), /Invalid checker identity/u);
  assert.throws(() => leanInput([], []), /empty checker input/u);
  assert.throws(() => leanInput([requirement], [{...application, units: -1}]), /Invalid checker count/u);
});
