import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {openFundedClientPreparation} from './funded-client-preparation.fixture.mjs';
import * as runtime from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {sourceFreeInferEffectPublicationPlan} from './local-values-plan.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const hash = body => `sha256:${createHash('sha256').update(canonicalText(body)).digest('hex')}`;

// An issued Result names a retention policy, whose original is a separate
// dependency from the installed clock/retention contracts and Data Policy.
for (const resultNames of [[], ['updates']]) {
test(`source-free Model Effect retains the exact issued retention policy closure (${resultNames.length} public Results)`, () => {
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
      clientProgramEffectCompilationResultNames: () => resultNames,
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
  assert.equal(plan.results.length, resultNames.length);
  assert.equal(plan.effectInputRetention.identity, expectedCid);
  assert.equal(plan.effectInputRetention.wire, expectedWire,
    'Private Effect retention does not require a fabricated public Result');
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
}

// Keep this real Common boundary in the existing runtime-coupled workload.
// The lighter capability tests must not reconstruct private manager functions.
test('funded caller passes the same installed mode to one original Request compiler and ModuleBody', async () => {
  const document = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'));
  const environmentWire = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8'));
  for (const mode of [false, true]) for (const valuesMaxRows of [undefined, 2])
    for (const sourceFreeMaxWork of [undefined, 30000000]) {
      const calls = [];
      let native, module, fixture;
      const moon = {...runtime,
        clientProgramPrepareRequestNativeComputation(...args) {
          assert.strictEqual(this, moon); calls.push('check'); native = args;
          return Reflect.apply(runtime.clientProgramPrepareRequestNativeComputation, runtime, args);
        },
        clientProgramFinishRequestComputation(...args) {
          assert.strictEqual(this, moon); calls.push('compiler');
          assert.strictEqual(args[0], native[0]); assert.strictEqual(args[1], native[1]);
          return Reflect.apply(runtime.clientProgramFinishRequestComputation, runtime, args);
        },
        clientProgramBorrowRequestProgramPlanInput(...args) {
          assert.strictEqual(this, moon); calls.push('borrow');
          assert.strictEqual(args[0], native[0]); assert.strictEqual(args[1], native[1]);
          return Reflect.apply(runtime.clientProgramBorrowRequestProgramPlanInput, runtime, args);
        },
        clientProgramPrepareRequestProgramModuleBody(...args) {
          assert.strictEqual(this, moon); calls.push('body'); module = args;
          assert.strictEqual(args[0], native[0]); assert.strictEqual(args[1], native[1]);
          return Reflect.apply(runtime.clientProgramPrepareRequestProgramModuleBody, runtime, args);
        },
        clientProgramRequestParametersOriginal(...args) {
          assert.strictEqual(this, moon); calls.push('parameters');
          assert.strictEqual(args[0], native[0]); assert.strictEqual(args[1], native[1]);
          return Reflect.apply(runtime.clientProgramRequestParametersOriginal, runtime, args);
        },
      };
      const environment = moon.clientProgramCheckEnvironment(
        canonicalText(environmentWire), environmentWire.evidence_bundle_cid,
        false, false, true, false, false, false, false);
      assert.ok(environment);
      fixture = await openFundedClientPreparation({moon, environment,
        retainedRelationOutput: mode, valuesMaxRows, sourceFreeMaxWork});
      try {
        const request = {kind: 'program', input: document};
        const prepared = await fixture.prepare(request);
        fixture.prepare.assertOwned(prepared);
        const cached = await fixture.manager.fundedPreparation(request, environment);
        assert.strictEqual(cached.prepared, prepared);
        assert.strictEqual(cached.originalInputs.environment, environment);
        assert.equal(cached.kind, 'effect_free');
        assert.equal(Object.isFrozen(cached), true);
        assert.equal(Object.isFrozen(cached.originalInputs), true);
        assert.deepEqual(native[2], document);
        assert.strictEqual(native[4], environment);
        assert.strictEqual(native[6], valuesMaxRows);
        assert.strictEqual(module[2], fixture.installedContracts);
        assert.deepEqual(module.slice(3), [mode, undefined, sourceFreeMaxWork]);
        assert.deepEqual(calls, ['check', 'compiler', 'borrow', 'body', 'parameters']);
      } finally {await fixture.close();}
    }
});
