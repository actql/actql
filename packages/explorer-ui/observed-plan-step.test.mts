import assert from 'node:assert/strict';
import test from 'node:test';
import {validWireRunViewShape} from '@actql/client-wire';
import {paused} from '../../scripts/fixtures/interactive-run-control-vectors.mjs';
import {runObservationModel, observedPlanStep} from './run-observation.mjs';
import {observationCid as cid, observationRef as ref,
  runObservationFixture as view} from './run-observation.fixture.mjs';

test('a Step observation requires the same Run, compiled Plan, Map and original step', () => {
  const original = ref(), stepId = cid('d');
  const wire: unknown = {...view(), compiled_plan_cid: cid('1'), logical_map_cid: cid('2'),
    run_state: {...paused, boundary: {...paused.boundary, position: 'before', step_id: stepId}}};
  assert.ok(validWireRunViewShape(wire));
  const admitted = runObservationModel(wire, null, original);
  const plan = {compiledPlanCid: cid('1'), logicalMapCid: cid('2'),
    nodes: [{id: cid('a')}, {id: stepId}]};
  assert.deepEqual(observedPlanStep(admitted, original, plan), {stepId, number: 2, position: 'before'});
  for (const key of ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']) {
    assert.equal(observedPlanStep(admitted, {...original, [key]: 'foreign'}, plan), undefined);
  }
  for (const key of ['compiledPlanCid', 'logicalMapCid']) {
    assert.equal(observedPlanStep(admitted, original, {...plan, [key]: cid('f')}), undefined);
  }
  assert.equal(observedPlanStep(admitted, original, {...plan, nodes: [{id: cid('a')}]}), undefined);
  const unbound = {...admitted, planBinding: {...admitted.planBinding, logicalMapCid: null}};
  assert.equal(observedPlanStep(unbound, original, plan), undefined);
});
