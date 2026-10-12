// Independent physical-journal fixtures. The control stand-in supplies closed
// metadata only; this is not compiler issuance or public Host acceptance.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonicalText} from '../../../scripts/check-canonical-json.mjs';
import {mapBody, planBody, planCid, cid} from
  '../../../scripts/fixtures/interactive-run-control-vectors.mjs';

const hash = body => `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;
export const originalPlanWire = names => {
  const body = structuredClone(mapBody);
  if (names !== undefined) body.steps[0].names = names;
  return JSON.stringify({version: 'actql-plan-view/0.1', compiled_plan_cid: planCid,
    logical_map: {...body, self_cid: hash(body)}, observation: 'static', provider_io: 0,
    quantities: [{kind: 'unknown', unit: 'work', reason: 'not_observed'}],
    capabilities: {static_plan: true, inspect: false, durable_control: false,
      sample_capture: [], full_intermediate_retention: [], cost_guard: false,
      execution_batch: false, policy_revision_cid: cid('9')}});
};
export const planOriginal = Object.freeze({compiledPlanWire:
  canonicalText({...planBody, compiled_plan_cid: planCid}), planViewWire: originalPlanWire()});
export const request = Object.freeze({authorityScopeCid: cid('a'), requestId: 'original-request',
  programDefinitionCid: planBody.program_definition_cid, parameterValuesCid: cid('b'),
  callerInputIntentCid: cid('c'), logicalRequestScopeCid: cid('d'), intentFingerprintCid: cid('e')});
const runBody = {version: 'actql-run-definition/0.1', scope_id: 'original', run_id: 'original-run',
  compiled_plan_cid: planCid, invocation_template_cid: cid('2'), authorization_context_cid: cid('3'),
  input_artifact_set_cid: cid('4'), created_at: '2026-10-12T00:00:00.000Z',
  valid_until: '2099-01-01T00:00:00.000Z'};
export const definition = Object.freeze({name: 'run_definition', identity: hash(runBody),
  wire: canonicalText({...runBody, run_definition_cid: hash(runBody)})});
export const evidence = Object.freeze({prepared: 'original-prepared', authorization: 'original-authorization'});
export const options = Object.freeze({namespaceId: 'original', runDefinition: definition,
  runAdmissionEvidence: evidence, lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
export const requestControl = Object.freeze({
  clientRequestAuthorityScopeCid: value => value.authorityScopeCid,
  clientRequestCallerId: value => value.requestId,
  clientRequestProgramCid: value => value.programDefinitionCid,
  clientRequestParametersCid: value => value.parameterValuesCid,
  clientRequestInputCid: value => value.callerInputIntentCid,
  clientRequestScopeCid: value => value.logicalRequestScopeCid,
  clientRequestIntentCid: value => value.intentFingerprintCid,
  clientRequestAdmitRecord: (authorityScopeCid, requestId, programDefinitionCid,
    parameterValuesCid, callerInputIntentCid, logicalRequestScopeCid, intentFingerprintCid) =>
    ({authorityScopeCid, requestId, programDefinitionCid, parameterValuesCid,
      callerInputIntentCid, logicalRequestScopeCid, intentFingerprintCid}),
  clientRequestRelation: (left, right) => Object.keys(request).every(key => left[key] === right[key]) ? 1 : 2,
});
export function controls() {
  const tickets = new WeakMap();
  const counts = {captureReads: 0, storedReads: 0};
  const ticket = (original = planOriginal) => {
    const result = Object.freeze({}); tickets.set(result, original); return result;
  };
  const publication = Object.freeze({
    admit(kind, wire) {
      assert.equal(kind, 'run_definition'); assert.equal(wire, definition.wire); return definition;
    },
    originalRunPlanAdmissionEvidence(selected, run, programCid, admitted) {
      counts.captureReads++;
      if (!tickets.has(selected)) throw new TypeError('Foreign original compiler plan');
      assert.equal(run.identity, definition.identity);
      assert.equal(programCid, request.programDefinitionCid); assert.deepEqual(admitted, evidence);
      return tickets.get(selected);
    },
    readStoredRunPlanOriginal(original, run, programCid) {
      counts.storedReads++;
      assert.equal(run.identity, definition.identity); assert.equal(programCid, request.programDefinitionCid);
      assert.equal(original.compiledPlanWire, planOriginal.compiledPlanWire);
      return original.planViewWire;
    },
  });
  return {ticket, publication, counts};
}
