import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as runtime from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {sourceFreeInferEffectPublicationPlan} from './local-values-plan.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const hash = body => `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;

// An issued Result names a retention policy, whose original is a separate
// dependency from the installed clock/retention contracts and Data Policy.
test('source-free Model Effect retains the exact issued retention policy closure', () => {
  const control = runtimeCore(runtime).publicationControl;
  const at = '2026-10-04T00:00:00.000Z';
  const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
  const resultPolicy = {kind: 'data_policy',
    cid: 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563',
    wire: policyWire};
  const programCid = cid('b');
  const runDefinition = {identity: cid('c'), wire: JSON.stringify({
    created_at: at, valid_until: '2026-10-05T00:00:00.000Z'})};
  const observation = {wire: JSON.stringify({data_policy_cid: resultPolicy.cid,
    captured_input_artifact_cids: []})};
  const compiled = {}, issued = {};
  // Stub opaque invocation ownership only. Policy seals and dependency-body
  // admission below use the actual common runtime. Packed acceptance checks closure.
  const plan = sourceFreeInferEffectPublicationPlan({
    acquired: {moon: {clientProgramEffectDefinitionCid: () => programCid,
      clientProgramEffectCompilationResultNames: () => ['updates'],
      clientProgramEffectCompilationResultTransformation: () => ({$tag: 1, _0: undefined})},
      control: {...control,
        checkedClientEffectInferInvocation: () => ({observation, invocation: {}, owner: {}}),
        compiledInferSourceFreeResultPolicy: actual => {
          assert.equal(actual, compiled); return resultPolicy;
        }},
      prepared: {}, compilation: {}, admission: {}, runDefinition,
      compiledPlan: {identity: cid('d')}, authorityScopeCid: cid('a'),
      namespaceId: 'local', storeAuthorityCid: cid('e'), now: () => at},
    compiled, operation: {bindIssuedInvocation: () => issued}, issuance: {}, modelEvidence: [],
  }).plan;
  const installed = (kind, name) => {
    const body = {name, version: 'actql-installed-local-policy/0.1'};
    return {kind, cid: hash(body), wire: canonicalText(body)};
  };
  const dependencies = [installed('retention_contract', 'local-result-retention'),
    installed('metadata_retention_policy', 'local-result-metadata'),
    installed('clock_contract', 'local-clock')];
  const expected = {available_until: '2026-10-05T00:00:00.000Z',
    clock_contract_cid: dependencies[2].cid, delete_by: '2026-10-05T01:00:00.000Z',
    effective_data_policy_cid: resultPolicy.cid,
    extension_ceiling_at: '2026-10-11T00:00:00.000Z',
    metadata_delete_by: '2026-10-11T00:00:00.000Z',
    metadata_retention_policy_cid: dependencies[1].cid,
    retention_contract_cid: dependencies[0].cid,
    version: 'actql-result-retention-policy/0.1'};
  const expectedCid = hash(expected);
  const expectedWire = canonicalText({...expected, effective_retention_policy_cid: expectedCid});
  const retained = plan.localEvidenceContext.retentionDependencies;
  assert.deepEqual(retained.find(body => body.kind === 'result_retention_policy'),
    {kind: 'result_retention_policy', cid: expectedCid, wire: expectedWire});
  const admit = body => checked(runtime.clientProgramAdmitEffectDependencyBody(
    body.kind, body.cid, body.wire, 100000, 10000, 64));
  for (const body of [...retained, resultPolicy]) {
    assert.equal(runtime.clientProgramEffectDependencyBodyCid(admit(body)), body.cid,
      'each original is admitted by the real dependency-body owner');
  }
});
