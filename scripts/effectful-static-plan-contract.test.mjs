import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';
import {buildControlRegistry} from './interactive-run-control-contract.mjs';
import {validWireEffectfulStaticPlanViewShape, validWirePlanViewShape} from
  '../packages/client-wire/interactive-control.generated.js';
import {effectfulStaticPlan, computationPlan, commandMember,
  positiveEffectfulPlans, negativeEffectfulPlans} from './fixtures/effectful-static-plan-vectors.mjs';

test('Effectful static envelope preserves the independent original Plan/map schemas', () => {
  const registry = buildControlRegistry();
  assert.equal(registry.schema_cids.plan_view,
    'sha256:51856c457b3eae9724d9626319ad865f38baee748f341f179d3575b2558c5bf4');
  assert.equal(validWireEffectfulStaticPlanViewShape(effectfulStaticPlan), true);
  assert.equal(validWirePlanViewShape(computationPlan), true);
  assert.equal(validWirePlanViewShape(effectfulStaticPlan), false);
  assert.equal(Object.hasOwn(registry.identity_domains, 'effectful_static_plan_view'), false);
  assert.equal(JSON.parse(canonicalText(effectfulStaticPlan)).computation.scope, 'computation_component');
});

test('declared minimum none/required and Command not-represented remain separate from permission', () => {
  for (const value of positiveEffectfulPlans) {
    assert.equal(validWireEffectfulStaticPlanViewShape(value), true);
    assert.deepEqual(value.observations.permission, {state: 'unknown', reason: 'not_observed'});
    assert.deepEqual(value.observations.preview, {state: 'unavailable', reason: 'not_sealed'});
  }
  assert.deepEqual(commandMember.minimum_approval, {kind: 'not_represented'});
});

test('independent closed negatives refuse physical, approval and input-namespace inventions', () => {
  for (const value of negativeEffectfulPlans) assert.equal(validWireEffectfulStaticPlanViewShape(value), false);
});

test('independent envelope canonical bytes stay fixed and validation does not mutate them', () => {
  const value = structuredClone(effectfulStaticPlan), before = canonicalText(value);
  assert.equal(Buffer.byteLength(before), 3344);
  assert.equal(createHash('sha256').update(before).digest('hex'),
    '3517c301ab1ade01b82ac5dcefbd2b00420e9a6b103a7fea7ee6ba94bda278e6');
  assert.equal(validWireEffectfulStaticPlanViewShape(value), true);
  assert.equal(canonicalText(value), before);
});
