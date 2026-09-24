import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {runCapturedStrategy, runPublishedCapturedStrategy} from './entry.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from './result-access.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {inspectAuthorizedRunState, installRunStateAuthority,
  installRunStateService} from '../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {connect as connectClient} from '../../packages/sdk/index.mjs';
import {validRunState} from '../../packages/client-wire/index.mjs';

const fixture = new URL('../../packages/sdk/fixtures/', import.meta.url);
const scratch = new URL('../../_build/client-program-bridge-tests/', import.meta.url);
const cid = digit => `sha256:${digit.repeat(64)}`;
const hashWithoutSelf = (value, selfKey) => {
  const body = {...value};
  delete body[selfKey];
  return `sha256:${createHash('sha256').update(JSON.stringify(body))
    .digest('hex')}`;
};
const evidenceCid =
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904';
const programCid =
  'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c';
const parametersCid =
  'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52';
const publicationLimits = Object.freeze({
  maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64,
});
const outputLimits = Object.freeze({
  maxResultFields: 10, maxResultMappingWork: 1000,
  maxResultOrderWork: 10000, maxResultWorkspaceEntries: 100,
  maxRows: 100, maxValueNodes: 10000, maxValueTextBytes: 100000,
  maxValueDepth: 64, maxValueWork: 100000, maxWireBytes: 100000,
  maxWireNodes: 10000, maxWireDepth: 64, maxColumns: 10,
  maxOrderWork: 10000, maxLogicalWireBytes: 100000,
  maxLogicalWireNodes: 10003, maxLogicalWireDepth: 66,
  maxSchemaFields: 10, maxSchemaBytes: 100000,
  maxSchemaNodes: 10000, maxSchemaDepth: 64, maxBatchBytes: 4096,
});

async function checkedFixture() {
  const [document, environmentBody] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
  ]);
  const environment = moon.clientProgramCheckEnvironment(
    environmentBody.trimEnd(), evidenceCid,
    false, false, true, false, false, false, false,
  );
  assert.ok(environment);
  return {document, environment};
}

test('private Plan binding uses the escaped checked Unit Result name', async () => {
  const {document, environment} = await checkedFixture();
  const renamed = JSON.parse(document);
  renamed.stages[0].results['a~/b'] = renamed.stages[0].results.rows;
  delete renamed.stages[0].results.rows;
  renamed.results.answer.from.result = 'a~/b';
  const prepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(renamed), 'json', environment);
  assert.ok(prepared);
  const body = checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 0));
  const binding = JSON.parse(body);
  assert.deepEqual([
    binding.target.unit_definition_cid,
    binding.target.result_name,
    binding.subject_ref,
    binding.resolved_limit_cid,
    binding.binding_cid,
  ], [
    'sha256:20cfb6440b10bee12f7647df2286cb63eca491c608df0ecbf1c13c21089eeb43',
    'a~/b',
    'unit:sha256:20cfb6440b10bee12f7647df2286cb63eca491c608df0ecbf1c13c21089eeb43#/results/a~0~1b/rows',
    'sha256:ee1d282f8b184e1f2202d5a70bf411a1a097fafe06b99e2ba87520206be820fc',
    'sha256:8b311359a8abfa4ef16ac3237daef1bdcc26ba8d753107afa074cab36feac400',
  ]);
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationRowsBinding(prepared, 0, 0, body)));
});

test('binding set covers every checked Unit Result port', async () => {
  const {document, environment} = await checkedFixture();
  const doubled = JSON.parse(document);
  doubled.stages[0].results.second =
    structuredClone(doubled.stages[0].results.rows);
  doubled.results.second = {from: {stage: 'source', result: 'second'}};
  const prepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(doubled), 'json', environment);
  assert.ok(prepared);
  const bindings = [0, 1].flatMap(index => [
    checked(moon.clientProgramPublicationRowsBindingJson(
      prepared, 0, index)),
    checked(moon.clientProgramPublicationBytesBindingJson(
      prepared, 0, index)),
  ]);
  const limits = [0, 1].flatMap(index => [
    checked(moon.clientProgramPublicationRowsLimitJson(prepared, 0, index)),
    checked(moon.clientProgramPublicationBytesLimitJson(prepared, 0, index)),
  ]);
  const issued = checked(moon.clientProgramIssuePublicationPlanFacts(prepared));
  assert.deepEqual(moon.clientProgramPublicationPlanFactLimits(issued), limits);
  assert.deepEqual(moon.clientProgramPublicationPlanFactBindings(issued),
    bindings);
  const entries = limits.map(body =>
    `{"kind":"resolved_limit","value":${body}}`);
  assert.deepEqual(moon.clientProgramPublicationPlanFactEntries(issued),
    entries);
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationFactEntries(prepared,
      entries.toReversed())));
  const manifestBody = {
    plan_facts: entries.map(entry => JSON.parse(entry)),
    version: 'actql-plan-fact-manifest/0.1',
  };
  const manifestCid = hashWithoutSelf(manifestBody,
    'plan_fact_manifest_cid');
  const manifest = JSON.stringify({...manifestBody,
    plan_fact_manifest_cid: manifestCid});
  const encodedManifest = checked(
    moon.clientProgramEncodePlanFactManifestIdentity(
      JSON.stringify(manifestBody.plan_facts)));
  assert.equal(moon.clientProgramPlanFactManifestCid(encodedManifest),
    manifestCid);
  assert.deepEqual(JSON.parse(moon.clientProgramPlanFactManifestWire(
    encodedManifest)), JSON.parse(manifest));
  assert.equal(checked(moon.clientProgramCheckPlanFactManifestIdentity(
    manifest, JSON.stringify(manifestBody.plan_facts))), manifestCid);
  assert.throws(() => checked(
    moon.clientProgramCheckPlanFactManifestIdentity(manifest,
      JSON.stringify(manifestBody.plan_facts.slice(1)))),
  {code: 'MoonBitHostFailure'});
  assert.equal(new Set(bindings.map(body => JSON.parse(body).binding_cid))
    .size, 4);
  assert.equal(new Set(limits.map(body => JSON.parse(body).resolved_limit_cid))
    .size, 4);
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationBindingSet(prepared,
      bindings.toReversed())));
  const admitFacts = (limitBodies, bindingBodies) => checked(
    moon.clientProgramAdmitPublicationPlanFacts(
      prepared, limitBodies, bindingBodies));
  assert.doesNotThrow(() => admitFacts(
    limits.toReversed(), bindings.toReversed()));
  for (const omitted of [0, 1, 2, 3]) {
    assert.throws(() => checked(
      moon.clientProgramAdmitPublicationFactEntries(prepared,
        entries.filter((_, index) => index !== omitted))),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => admitFacts(
      limits.filter((_, index) => index !== omitted), bindings),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => admitFacts(
      limits, bindings.filter((_, index) => index !== omitted)),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => checked(
      moon.clientProgramAdmitPublicationBindingSet(prepared,
        bindings.filter((_, index) => index !== omitted))),
    {code: 'MoonBitHostFailure'});
  }
});

// Test-only evidence isolates checked Program binding. Product admission must
// derive every other evidence CID from its real compiler and Host authority.
function publicationEvidence(program, parameters, semantics,
  checkEnvironmentCid, aoaLogicalCid = cid('9')) {
  const limits = [100000, 10000, 64];
  const evidence = (name, body) => checked(moon.strategyRunEvidenceSeal(
    name, JSON.stringify(body), ...limits));
  const template = evidence('bound_invocation_template', {
    version: 'actql-bound-invocation-template/0.1',
    program_definition_cid: program,
    parameter_values_cid: parameters,
    invocation_bindings_cid: cid('3'),
    check_environment_cid: checkEnvironmentCid,
    grammar_manifest_cid: cid('5'),
    required_profile_contracts: [],
    barrier_contract_manifest_cid: cid('6'),
    source_evidence: 'unbound',
  });
  const plan = checked(moon.strategyPublicationSeal('compiled_plan',
    JSON.stringify({
      version: 'actql-compiled-plan/0.1',
      compiler_version: 'compiler-test-0.1',
      aoa_ir_version: 'aoa-ir-test-0.1',
      executable_plan_cid: cid('7'),
      program_definition_cid: program,
      program_semantics_cid: semantics,
      aoa_contract_cid: cid('8'),
      aoa_logical_cid: aoaLogicalCid,
    }), ...limits));
  const prepared = evidence('prepared_invocation', {
    version: 'actql-prepared-invocation/0.1',
    invocation_template_cid: moon.strategyRunEvidenceIdentity(template),
    compiled_plan_cid: moon.strategyPublicationContractIdentity(plan),
    execution_context_cid: cid('a'),
    host_policy_cid: cid('b'),
    policy_decision: 'allow',
    expires_at: '2099-01-01T00:00:00.000Z',
  });
  const authorization = evidence('run_authorization', {
    version: 'actql-run-authorization/0.1',
    prepared_invocation_cid: moon.strategyRunEvidenceIdentity(prepared),
    execution_context_cid: cid('a'),
    host_policy_cid: cid('b'),
    decision: 'allowed',
  });
  return [template, prepared, authorization, plan];
}

// This fixture provides missing compiler/Host policy evidence. Its checked
// Program identity and the physical Result bytes come from product owners.
function checkedValuesPublicationPlan(prepared, control) {
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'published-values-request', cid('b'));
  const aoa = checked(
    moon.clientProgramIssueLocalValuesAoAIdentity(prepared, 0));
  const evidence = publicationEvidence(
    moon.clientRequestProgramCid(request),
    moon.clientRequestParametersCid(request),
    moon.clientProgramSemanticsCid(prepared),
    moon.clientProgramCheckEnvironmentCid(prepared),
    moon.clientProgramLocalValuesAoACid(aoa));
  const [template, preparedEvidence, authorization] = evidence
    .slice(0, 3).map((value, index) => control.admitRunEvidence(
      ['bound_invocation_template', 'prepared_invocation',
        'run_authorization'][index],
      moon.strategyRunEvidenceJson(value), publicationLimits));
  const compiledPlan = control.admit('compiled_plan',
    moon.strategyPublicationContractJson(evidence[3]), publicationLimits);
  const admission = control.admitCheckedClientRunPublication(
    prepared, template, preparedEvidence, authorization, compiledPlan);
  const runDefinition = control.issueRunDefinition(admission, {
    scopeId: 'tenant-a-scope', runId: 'checked-values-published',
    inputArtifactSetCid: cid('c'),
    createdAt: '2026-09-24T00:00:00.000Z',
    validUntil: '2027-01-01T00:00:00.000Z',
  }, publicationLimits);
  const effectiveDataPolicyCid = cid('d');
  const observation = control.sealRunEvidence('observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [], captured_input_artifact_cids: [],
      consistency: 'no_external_sources', capture_started_at: null,
      capture_completed_at: null,
      replayability: {materialized: false, availability_evidence_cids: []},
      data_policy_cid: effectiveDataPolicyCid,
    }), publicationLimits);
  const invocation = control.issueRunInvocation(
    template, observation, publicationLimits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('e'),
    effective_data_policy_cid: effectiveDataPolicyCid,
    available_until: '2026-09-24T01:00:00.000Z',
    delete_by: '2026-09-24T02:00:00.000Z',
    extension_ceiling_at: '2026-09-24T03:00:00.000Z',
    metadata_retention_policy_cid: cid('f'),
    metadata_delete_by: '2026-09-24T04:00:00.000Z',
    clock_contract_cid: cid('0'),
  }), publicationLimits);
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal', JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: cid('1'), entries: [],
    }), publicationLimits);
  const authoringContext = control.sealRunEvidence('authoring_context',
    JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: moon.clientRequestProgramCid(request),
      annotations: [],
    }), publicationLimits);
  return Object.freeze({
    admission, runDefinition, invocation, observation,
    normalizationJournal, authoringContext,
    results: Object.freeze([Object.freeze({
      retention,
      evidenceContext: Object.freeze({
        computationContractCid: cid('2'), inputRelationCids: [],
        scopeCid: cid('3'), effectiveDataPolicyCid,
        authorityScopeCid: cid('a'),
      }),
    })]),
    receiptEvidence: Object.freeze({bindings: [], sourceEvidence: [],
      modelEvidence: [], barrierAttemptReceiptCids: []}),
    captureEvidence: Object.freeze({pendingSourceStateAdvances: [],
      modelEvidence: []}),
    request: Object.freeze({
      tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      publicationPolicyCid: cid('4'), publicationTargetCid: cid('5'),
      requestedAt: '2026-09-24T00:00:00.000Z',
    }),
    attempt: Object.freeze({
      attemptId: 'published-values-attempt', fenceCid: cid('6'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-24T00:00:01.000Z',
    }),
    outputLimits, contractLimits: publicationLimits,
    now: () => '2026-09-24T00:02:00.000Z',
  });
}

test('Node ABI derives the checked named Result and request identity', async () => {
  const {document, environment} = await checkedFixture();
  const prepared = moon.clientProgramPrepareEffectFree(
    document, 'json', environment);
  assert.ok(prepared);
  assert.equal(moon.clientProgramResultCount(prepared), 1);
  assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
  assert.equal(moon.clientProgramResultName(prepared, 1), undefined);
  assert.equal(moon.clientProgramCheckEnvironmentCid(prepared), evidenceCid);
  const steps = checked(moon.clientProgramLocalAoASteps(prepared, 0));
  assert.deepEqual(JSON.parse(steps), [{
    id: 'values_0', in: [], op: 'REL.values',
    params: {rows: [{id: 1}, {id: 2}],
      schema: {id: {nullable: false, type: 'number'}}},
  }]);
  const pipeline = checked(
    moon.clientProgramLocalValuesPipelineJson(prepared, 0));
  assert.equal(pipeline, JSON.stringify({
    output: 'values_0', sources: {}, steps: JSON.parse(steps),
    version: 'aoa-pipeline/0.1',
  }));
  const aoa = checked(
    moon.clientProgramIssueLocalValuesAoAIdentity(prepared, 0));
  assert.equal(moon.clientProgramLocalValuesAoAWire(aoa), pipeline);
  assert.equal(moon.clientProgramLocalValuesAoACid(aoa),
    'sha256:5e502ceb8e7f0833fd2491ac223453d9204e99a3c29642cad6d782cee9ff7723');
  const unitSource = checked(
    moon.clientProgramLocalValuesUnitSourceJson(prepared, 0));
  assert.deepEqual(JSON.parse(unitSource), {
    id: 'source', inputs: {},
    results: {rows: {fields: ['id'], from: 'selected'}},
    steps: [{as: 'selected', values: {
      rows: [{id: 1}, {id: 2}],
      schema: {id: {nullable: false, type: 'number'}},
    }}],
    version: 'actql/0.1',
  });
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitLocalValuesAoAIdentity(prepared, 0,
      pipeline, moon.clientProgramLocalValuesAoACid(aoa))));
  assert.throws(() => checked(
    moon.clientProgramAdmitLocalValuesAoAIdentity(prepared, 0,
      pipeline.replace('"id":2', '"id":3'),
      moon.clientProgramLocalValuesAoACid(aoa))),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramLocalValuesPipelineJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramLocalValuesUnitSourceJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramLocalAoASteps(prepared, 1)),
    {code: 'MoonBitHostFailure'});
  const semanticDocument = checked(
    moon.clientProgramSemanticDocumentJson(prepared));
  assert.deepEqual(JSON.parse(semanticDocument), JSON.parse(document));
  const annotated = JSON.parse(document);
  annotated.meta = {note: 'root'};
  annotated.stages[0].meta = {note: 'stage'};
  annotated.stages[0].steps[0].meta = {note: 'step'};
  const annotatedPrepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(annotated), 'json', environment);
  assert.ok(annotatedPrepared);
  assert.equal(checked(
    moon.clientProgramSemanticDocumentJson(annotatedPrepared)),
  semanticDocument);
  assert.equal(checked(
    moon.clientProgramLocalValuesUnitSourceJson(annotatedPrepared, 0)),
  unitSource);
  const semanticsCid = moon.clientProgramSemanticsCid(prepared);
  assert.match(semanticsCid, /^sha256:[a-f0-9]{64}$/u);
  const definition = checked(moon.clientProgramDefinitionJson(prepared));
  assert.deepEqual(JSON.parse(definition), {
    id: 'client-values', program_semantics_cid: semanticsCid,
    version: 'actql-program-definition/0.1',
  });
  assert.equal(`sha256:${createHash('sha256').update(definition)
    .digest('hex')}`, programCid);
  const semantics = checked(moon.clientProgramSemanticsJson(prepared));
  assert.equal(`sha256:${createHash('sha256').update(semantics)
    .digest('hex')}`, semanticsCid);
  const stageSemantics = checked(
    moon.clientProgramStageSemanticsJson(prepared, 0));
  assert.equal(`sha256:${createHash('sha256').update(stageSemantics)
    .digest('hex')}`,
  JSON.parse(semantics).program_template.stages[0].stage_semantics_cid);
  assert.throws(() => checked(
    moon.clientProgramStageSemanticsJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  const rowsLimitBody = checked(
    moon.clientProgramPublicationRowsLimitJson(prepared, 0, 0));
  const bytesLimitBody = checked(
    moon.clientProgramPublicationBytesLimitJson(prepared, 0, 0));
  const rowsLimit = JSON.parse(rowsLimitBody);
  const bytesLimit = JSON.parse(bytesLimitBody);
  const unit =
    'unit:sha256:61072398472dcda269c10498c3af97a2853703344a33e6471d31aec3ea0a554d';
  assert.deepEqual([rowsLimit.subject_ref, bytesLimit.subject_ref],
    [`${unit}#/results/rows/rows`, `${unit}#/results/rows/bytes`]);
  assert.deepEqual([rowsLimit.unit, rowsLimit.effective_max,
    bytesLimit.unit, bytesLimit.effective_max],
  ['rows', 2, 'bytes', 1000]);
  assert.deepEqual(rowsLimit.candidates.map(candidate => candidate.role),
    ['host_ceiling', 'proven_upper_bound']);
  for (const limit of [rowsLimit, bytesLimit]) {
    assert.equal(limit.version, 'actql-resolved-limit/0.1');
    assert.equal(limit.resolved_limit_cid,
      hashWithoutSelf(limit, 'resolved_limit_cid'));
    for (const witness of limit.candidates) {
      assert.equal(witness.witness_cid,
        hashWithoutSelf(witness, 'witness_cid'));
    }
  }
  const rowsBindingBody = checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 0));
  const bytesBindingBody = checked(
    moon.clientProgramPublicationBytesBindingJson(prepared, 0, 0));
  const issuedFacts = checked(
    moon.clientProgramIssuePublicationPlanFacts(prepared));
  assert.deepEqual(moon.clientProgramPublicationPlanFactLimits(issuedFacts),
    [rowsLimitBody, bytesLimitBody]);
  assert.deepEqual(moon.clientProgramPublicationPlanFactBindings(issuedFacts),
    [rowsBindingBody, bytesBindingBody]);
  const factEntries = [rowsLimitBody, bytesLimitBody].map(body =>
    `{"kind":"resolved_limit","value":${body}}`);
  assert.deepEqual(moon.clientProgramPublicationPlanFactEntries(issuedFacts),
    factEntries);
  assert.throws(() => checked(
    moon.clientProgramAdmitPublicationFactEntries(prepared,
      [factEntries[0], factEntries[0]])),
  {code: 'MoonBitHostFailure'});
  const rowsBinding = JSON.parse(rowsBindingBody);
  const bytesBinding = JSON.parse(bytesBindingBody);
  assert.deepEqual([
    rowsLimit.resolved_limit_cid, bytesLimit.resolved_limit_cid,
    rowsBinding.binding_cid, bytesBinding.binding_cid,
  ], [
    'sha256:d1dce9ccb30a076ebe729616043a663dddb85ba29c8de3f8f964bd8c71fbf1c0',
    'sha256:4cdf56db345268d69b01d9b3216a5fbc8f8a7c648e8ae9176dde762f1d64e8b3',
    'sha256:bd732ffbc9c3a523e3dffbb6e1ffd28a9696e12779ca32f099de040cd0d2cee2',
    'sha256:33d623c5108cff887acbb28ef6b7fda20615a217b7d55e8bd898b2e10f65da3f',
  ]);
  for (const [binding, limit, measure] of [
    [rowsBinding, rowsLimit, 'rows'],
    [bytesBinding, bytesLimit, 'bytes'],
  ]) {
    assert.deepEqual(binding, {
      binding_cid: binding.binding_cid,
      effective_max: limit.effective_max,
      resolved_limit_cid: limit.resolved_limit_cid,
      subject_ref: `${unit}#/results/rows/${measure}`,
      target: {
        kind: 'result_publication', measure, result_name: 'rows',
        unit_definition_cid: unit.slice('unit:'.length),
      },
      unit: measure,
      version: 'actql-execution-limit-binding/0.1',
    });
    assert.equal(binding.binding_cid, hashWithoutSelf(binding, 'binding_cid'));
    assert.notEqual(binding.binding_cid, hashWithoutSelf({
      ...binding, target: {...binding.target, result_name: 'answer'},
    }, 'binding_cid'));
  }
  const admitRows = body => checked(
    moon.clientProgramAdmitPublicationRowsBinding(prepared, 0, 0, body));
  const admitBytes = body => checked(
    moon.clientProgramAdmitPublicationBytesBinding(prepared, 0, 0, body));
  const admitSet = bodies => checked(
    moon.clientProgramAdmitPublicationBindingSet(prepared, bodies));
  const admitFacts = (limits, bindings) => checked(
    moon.clientProgramAdmitPublicationPlanFacts(prepared, limits, bindings));
  assert.doesNotThrow(() => admitRows(rowsBindingBody));
  assert.doesNotThrow(() => admitBytes(bytesBindingBody));
  assert.doesNotThrow(() => admitSet([bytesBindingBody, rowsBindingBody]));
  assert.doesNotThrow(() => admitFacts(
    [bytesLimitBody, rowsLimitBody],
    [bytesBindingBody, rowsBindingBody]));
  for (const invalid of [
    [rowsLimitBody],
    [rowsLimitBody, rowsLimitBody],
    [rowsLimitBody, '{}'],
    [rowsLimitBody, JSON.stringify({...bytesLimit,
      effective_max: bytesLimit.effective_max + 1})],
  ]) assert.throws(() => admitFacts(invalid,
    [rowsBindingBody, bytesBindingBody]),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => admitFacts(
    [rowsLimitBody, bytesLimitBody], [rowsBindingBody]),
  {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => admitSet([JSON.stringify({
    version: rowsBinding.version, target: rowsBinding.target,
    unit: rowsBinding.unit, subject_ref: rowsBinding.subject_ref,
    resolved_limit_cid: rowsBinding.resolved_limit_cid,
    effective_max: rowsBinding.effective_max,
    binding_cid: rowsBinding.binding_cid,
  }), bytesBindingBody]));
  for (const invalid of [
    [rowsBindingBody],
    [rowsBindingBody, rowsBindingBody],
    [rowsBindingBody, JSON.stringify({...bytesBinding,
      binding_cid: cid('f')})],
    [bytesBindingBody, '{}'],
  ]) assert.throws(() => admitSet(invalid),
    {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => admitRows(JSON.stringify({
    version: rowsBinding.version,
    target: rowsBinding.target,
    unit: rowsBinding.unit,
    subject_ref: rowsBinding.subject_ref,
    resolved_limit_cid: rowsBinding.resolved_limit_cid,
    effective_max: rowsBinding.effective_max,
    binding_cid: rowsBinding.binding_cid,
  })));
  const wrongPort = {
    ...rowsBinding,
    target: {...rowsBinding.target, result_name: 'answer'},
  };
  wrongPort.binding_cid = hashWithoutSelf(wrongPort, 'binding_cid');
  for (const invalid of [
    JSON.stringify(wrongPort),
    JSON.stringify({...rowsBinding, target: {
      ...rowsBinding.target, unit_definition_cid: cid('f'),
    }}),
    JSON.stringify({...rowsBinding, resolved_limit_cid: cid('f')}),
    JSON.stringify({...rowsBinding, binding_cid: cid('f')}),
    JSON.stringify({...rowsBinding, unknown: true}),
    rowsBindingBody.replace('"unit":"rows","version"',
      '"unit":"rows","unit":"rows","version"'),
  ]) assert.throws(() => admitRows(invalid), {code: 'MoonBitHostFailure'});
  assert.throws(() => admitBytes(rowsBindingBody),
    {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramPublicationRowsLimitJson(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'saved-request', cid('b'));
  assert.ok(request);
  assert.equal(moon.clientRequestProgramCid(request), programCid);
  assert.equal(moon.clientRequestParametersCid(request), parametersCid);
  assert.equal(moon.clientRequestScopeCid(request),
    'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3');
  assert.equal(moon.clientRequestIntentCid(request),
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  const yaml = await readFile(new URL('values.yaml', fixture), 'utf8');
  const yamlPrepared = moon.clientProgramPrepareEffectFree(
    yaml, 'yaml', environment);
  assert.ok(yamlPrepared);
  assert.equal(moon.clientRequestProgramCid(
    moon.clientProgramRequestIdentity(
      yamlPrepared, cid('a'), 'saved-request', cid('b'))),
  programCid);
  assert.equal(moon.clientProgramSemanticsCid(yamlPrepared), semanticsCid);
  assert.equal(checked(moon.clientProgramDefinitionJson(yamlPrepared)),
    definition);
  assert.equal(checked(
    moon.clientProgramSemanticDocumentJson(yamlPrepared)), semanticDocument);
  assert.equal(checked(moon.clientProgramSemanticsJson(yamlPrepared)),
    semantics);
  assert.equal(checked(moon.clientProgramStageSemanticsJson(yamlPrepared, 0)),
    stageSemantics);
  assert.equal(checked(
    moon.clientProgramPublicationRowsLimitJson(yamlPrepared, 0, 0)),
  rowsLimitBody);
  assert.equal(checked(
    moon.clientProgramPublicationBytesLimitJson(yamlPrepared, 0, 0)),
  bytesLimitBody);
  assert.equal(checked(
    moon.clientProgramPublicationRowsBindingJson(yamlPrepared, 0, 0)),
  rowsBindingBody);
  assert.equal(checked(
    moon.clientProgramPublicationBytesBindingJson(yamlPrepared, 0, 0)),
  bytesBindingBody);
  assert.equal(checked(moon.clientProgramLocalAoASteps(yamlPrepared, 0)), steps);
  assert.equal(checked(
    moon.clientProgramLocalValuesPipelineJson(yamlPrepared, 0)), pipeline);
  assert.equal(moon.clientProgramPrepareEffectFree(document, 'auto', environment),
    undefined);
  assert.equal(moon.clientProgramPrepareEffectFree(
    document.replace('actql/0.1', 'actql/9.9'), 'json', environment),
  undefined);
  assert.equal(moon.clientProgramCheckEnvironment(
    '{}', evidenceCid, false, false, true, false, false, false, false),
  undefined);
});

test('Node ABI binds separately supplied Parameters through the shared checker',
  async t => {
    const {environment} = await checkedFixture();
    const [json, yaml] = await Promise.all([
      readFile(new URL('parameter-values.json', fixture), 'utf8'),
      readFile(new URL('parameter-values.yaml', fixture), 'utf8'),
    ]);
    const prepare = (document, format, parameters) =>
      moon.clientProgramPrepareEffectFreeWithParameters(
        document, format, environment, parameters);
    const issue = outcome => moon.clientProgramPreparationIssueCode(outcome);
    const ready = outcome => moon.clientProgramPreparationReady(outcome);
    assert.equal(issue(prepare(json, 'json', undefined)), 'needs_inputs');
    assert.equal(issue(prepare(json, 'json', '{"n":"bad"}')),
      'check_invalid_input');
    assert.equal(issue(prepare(json, 'json', '{"n":null}')),
      'check_invalid_input');
    assert.equal(issue(prepare(json, 'json', '{"n":2')),
      'supplied_syntax');
    assert.equal(issue(prepare(json, 'json', `{"n":"${'x'.repeat(65536)}"}`)),
      'supplied_too_large');
    assert.equal(issue(prepare(json, 'auto', '{"n":2}')),
      'invalid_format');
    const supplied = ready(prepare(json, 'json', '{"n":2}'));
    const repeated = ready(prepare(json, 'json', '{"n":2}'));
    const yamlSupplied = ready(prepare(yaml, 'yaml', '{"n":2}'));
    const changed = ready(prepare(json, 'json', '{"n":3}'));
    for (const value of [supplied, repeated, yamlSupplied, changed]) {
      assert.ok(value);
      assert.equal(moon.clientProgramResultName(value, 0), 'answer');
    }
    const identity = value => moon.clientProgramRequestIdentity(
      value, cid('a'), 'parameter-request', cid('b'));
    const first = identity(supplied);
    const same = identity(repeated);
    const yamlIdentity = identity(yamlSupplied);
    const other = identity(changed);
    assert.equal(moon.clientRequestProgramCid(first),
      moon.clientRequestProgramCid(yamlIdentity));
    assert.equal(moon.clientProgramSemanticsCid(supplied),
      moon.clientProgramSemanticsCid(yamlSupplied));
    assert.equal(moon.clientRequestParametersCid(first),
      moon.clientRequestParametersCid(yamlIdentity));
    assert.equal(moon.clientRequestIntentCid(first),
      moon.clientRequestIntentCid(same));
    assert.notEqual(moon.clientRequestParametersCid(first),
      moon.clientRequestParametersCid(other));
    assert.notEqual(moon.clientRequestIntentCid(first),
      moon.clientRequestIntentCid(other));
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'parameters-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const admission = {tenantId: 'tenant-a', runDefinitionCid: cid('c'),
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
    assert.equal(journal.accept(first, admission, moon).inserted, true);
    assert.equal(journal.accept(same, admission, moon).inserted, false);
    assert.throws(() => journal.accept(other, admission, moon),
      {code: 'ClientRequestIntentConflict'});
    const withDefault = json.replace('"n": {"type": "number"}',
      '"n": {"type": "number", "default": 5}');
    assert.notEqual(withDefault, json);
    assert.ok(ready(prepare(withDefault, 'json', undefined)));
  });

test('public submit rejects checker failures before Run admission', async () => {
  const {environment} = await checkedFixture();
  const document = await readFile(new URL('parameter-values.json', fixture),
    'utf8');
  const prepareSubmit = installNodeClientProgramPreparation({
    moon, environment});
  let admissions = 0;
  let admittedIdentity;
  const server = createServer(createClientHttpHandler({
    authenticate: header => header === 'Bearer scoped-token'
      ? 'principal-a' : undefined,
    authorizeConnection: () => true,
    negotiate: () => ({
      version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'volatile', scopeRef: 'principal-a', capabilities: [],
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
        maxRows: 100, maxBatchRows: 10,
        maxBatchRetainedValueBytes: 2048},
    }),
    prepareSubmit,
    maxRequestBytes: 100000,
    submit: ({preparedProgram, requestId}) => {
      admissions++;
      admittedIdentity = moon.clientProgramRequestIdentity(preparedProgram,
        cid('a'), requestId, cid('b'));
      return {ref: {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
        runDefinitionCid: cid('c')}, durability: 'volatile', revision: 0};
    },
  }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const origin = `http://127.0.0.1:${server.address().port}/`;
    const submit = parameters => fetch(new URL('actql/client/0.1/submit',
      origin), {
      method: 'POST', headers: {authorization: 'Bearer scoped-token',
        'content-type': 'application/json'},
      body: JSON.stringify({connection: {mode: 'local', owner: 'local',
        runners: [], consentRefs: []}, requestId: 'saved-parameter-id',
      kind: 'aql', input: {text: document, format: 'json'}, parameters}),
    });
    for (const [parameters, status, code] of [
      [null, 422, 'ClientProgramNeedsInputs'],
      [{n: null}, 422, 'ClientProgramRejected'],
      [{n: 'bad'}, 422, 'ClientProgramRejected'],
      [{n: 2, extra: true}, 422, 'ClientProgramRejected'],
      [{n: 'x'.repeat(65536)}, 413, 'ClientParametersTooLarge'],
    ]) {
      const response = await submit(parameters);
      assert.equal(response.status, status);
      assert.deepEqual(await response.json(), {code});
    }
    assert.equal(admissions, 0);
    const client = await connectClient({mode: 'local', owner: 'local',
      endpoint: origin, token: 'scoped-token'});
    try {
      await assert.rejects(client.aql(document, {format: 'json',
        requestId: 'sdk-invalid-parameter', parameters: {n: null}}),
      {code: 'ClientProgramRejected'});
      assert.equal(admissions, 0);
    } finally {
      client.close();
    }
    const prepared = prepareSubmit({kind: 'aql',
      input: {text: document, format: 'json'}, parameters: {n: 2}});
    assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
    const objectPrepared = prepareSubmit({kind: 'program',
      input: JSON.parse(document), parameters: {n: 2}});
    assert.equal(moon.clientProgramSemanticsCid(objectPrepared),
      moon.clientProgramSemanticsCid(prepared));
    const accepted = await submit({n: 2});
    assert.equal(accepted.status, 200);
    assert.equal(admissions, 1);
    assert.equal(moon.clientRequestParametersCid(admittedIdentity),
      moon.clientRequestParametersCid(moon.clientProgramRequestIdentity(
        prepared, cid('a'), 'saved-parameter-id', cid('b'))));
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('Node publication admission rejects evidence from another checked Program',
  async t => {
    const {document, environment} = await checkedFixture();
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    assert.ok(prepared);
    const identity = moon.clientProgramRequestIdentity(
      prepared, cid('a'), 'saved-request', cid('b'));
    const evidence = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity),
      moon.clientProgramSemanticsCid(prepared),
      moon.clientProgramCheckEnvironmentCid(prepared));
    assert.ok(moon.clientProgramAdmitPublication(prepared, ...evidence));
    const control = runtimeCore(moon).publicationControl;
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const bound = evidence.slice(0, 3).map((value, index) =>
      control.admitRunEvidence(
        ['bound_invocation_template', 'prepared_invocation',
          'run_authorization'][index],
        moon.strategyRunEvidenceJson(value), limits));
    const plan = control.admit('compiled_plan',
      moon.strategyPublicationContractJson(evidence[3]), limits);
    const admitted = control.admitCheckedClientRunPublication(
      prepared, ...bound, plan);
    assert.equal(admitted.kind, 'run-publication-admission');
    const definition = control.issueRunDefinition(admitted, {
      scopeId: 'tenant-a-scope',
      runId: 'checked-values-run',
      inputArtifactSetCid: cid('c'),
      createdAt: '2026-09-24T00:00:00.000Z',
      validUntil: '2027-01-01T00:00:00.000Z',
    }, limits);
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'admission-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    const accepted = journal.acceptDefinition(identity, {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control);
    assert.equal(accepted.inserted, true);
    assert.equal(accepted.ref.runDefinitionCid, definition.identity);
    journal.close(); // Lose the acceptance reply before using the Run ref.
    const restarted = openClientRequestJournal(path);
    t.after(() => restarted.close());
    const retained = restarted.resolveDefinition(identity,
      {tenantId: 'tenant-a'}, moon, control);
    assert.equal(retained.runDefinition.wire, definition.wire);
    const changed = moon.clientProgramPrepareEffectFree(
      document.replace('"id": 2', '"id": 3'), 'json', environment);
    assert.ok(changed);
    assert.equal(moon.clientProgramAdmitPublication(changed, ...evidence),
      undefined);
    assert.throws(() => control.admitCheckedClientRunPublication(
      changed, ...bound, plan),
    /Publication evidence differs from checked Program/u);
    const changedRequest = moon.clientProgramRequestIdentity(
      changed, cid('a'), 'saved-request', cid('b'));
    assert.throws(() => restarted.resolveDefinition(changedRequest,
      {tenantId: 'tenant-a'}, moon, control),
    {code: 'ClientRequestIntentConflict'});
    assert.throws(() => restarted.acceptDefinition(changedRequest, {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control), {code: 'ClientRequestIntentConflict'});
    const foreignSemantics = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity), cid('f'), evidenceCid);
    assert.equal(moon.clientProgramAdmitPublication(
      prepared, ...foreignSemantics), undefined);
    const foreignEnvironment = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity),
      moon.clientProgramSemanticsCid(prepared), cid('f'));
    assert.equal(moon.clientProgramAdmitPublication(
      prepared, ...foreignEnvironment), undefined);
  });

test('durable request deduplication uses checked Program identity', async t => {
  const {document, environment} = await checkedFixture();
  const prepared = moon.clientProgramPrepareEffectFree(
    document, 'json', environment);
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'saved-request', cid('b'));
  await mkdir(scratch, {recursive: true});
  const path = await mkdtemp(join(scratch.pathname, 'case-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  const admission = {
    tenantId: 'tenant-a',
    runDefinitionCid: cid('d'),
    lookupExpiresAt: '2099-01-01T00:00:00.000Z',
  };
  assert.equal(journal.accept(request, admission, moon).inserted, true);
  assert.equal(journal.accept(request, {...admission,
    runDefinitionCid: cid('e')}, moon).inserted, false);
  const changed = moon.clientProgramPrepareEffectFree(
    document.replace('"id": 2', '"id": 3'), 'json', environment);
  assert.ok(changed);
  const changedRequest = moon.clientProgramRequestIdentity(
    changed, cid('a'), 'saved-request', cid('b'));
  assert.equal(moon.clientRequestRelation(request, changedRequest), 2);
  assert.throws(() => journal.accept(changedRequest, {...admission,
    runDefinitionCid: cid('e')}, moon),
  {code: 'ClientRequestIntentConflict'});
  assert.equal(journal.lookup({tenantId: 'tenant-a',
    authorityScopeCid: cid('a'), requestId: 'saved-request'}, moon)
    .ref.runDefinitionCid, cid('d'));
});

test('checked source-free Program executes through the standard Local Host',
  async () => {
    const {document, environment} = await checkedFixture();
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    assert.equal(moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry.replace('"REL.values"', '"REL.changed"'),
      values, 1n, 0n, 0n, 0n), undefined);
    assert.equal(moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry, values, -1n, 0n, 0n, 0n), undefined);
    const setup = moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(setup);
    const execution = await runCapturedStrategy(setup);
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.deepEqual(execution.resultInventory.map(result => result.name),
        ['answer']);
      assert.equal(execution.completed.length, 1);
      assert.equal(execution.completed[0].task, 0);
      assert.equal(execution.completed[0].outputRows, 2);
    } finally {
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

test('public Values submit computes and reads its real Local Result',
  async t => {
    const {document, environment} = await checkedFixture();
    const expected = JSON.parse(await readFile(new URL('values.expected.json',
      fixture), 'utf8'));
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    assert.ok(prepared);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const control = runtimeCore(moon).publicationControl;
    let plan;
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'result-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
    };
    const journalDirectory = join(directory, 'requests');
    await mkdir(journalDirectory);
    const identity = moon.clientProgramRequestIdentity(
      prepared, cid('a'), 'published-values-request', cid('b'));
    let store = await openLocalPublicationStore(configuration, control);
    let published;
    try {
      const journal = openClientRequestJournal(journalDirectory);
      let issues = 0;
      let computes = 0;
      const submitServer = createServer(createClientHttpHandler({
        authenticate: header => header === 'Bearer scoped-token'
          ? 'principal-before-restart' : undefined,
        authorizeConnection: facts => facts.connection.mode === 'local' &&
          facts.connection.owner === 'local',
        negotiate: () => ({
          version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'principal-before-restart',
          capabilities: ['result-jsonl'],
          limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024,
            maxRetainedValueBytes: 4096, maxRows: 100,
            maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
        }),
        prepareSubmit: installNodeClientProgramPreparation({
          moon, environment}),
        submit: async ({preparedProgram, requestId}) => {
          const requested = moon.clientProgramRequestIdentity(
            preparedProgram, cid('a'), requestId, cid('b'));
          const accepted = await journal.admitOrLookupDefinition(requested, {
            tenantId: 'tenant-a',
            lookupExpiresAt: '2099-01-01T00:00:00.000Z',
            issueDefinition: () => {
              issues++;
              plan = checkedValuesPublicationPlan(preparedProgram, control);
              return plan.runDefinition;
            },
          }, moon, control);
          if (accepted.inserted) {
            const setup = moon.clientProgramOpenSourceFreeLocalHost(
              preparedProgram, registry, values, 1n, 0n, 0n, 0n);
            assert.ok(setup);
            computes++;
            published = await runPublishedCapturedStrategy(setup,
              {store, plan});
          }
          return {ref: accepted.ref, durability: accepted.durability,
            revision: accepted.revision};
        },
      }));
      await new Promise(resolve => submitServer.listen(0, '127.0.0.1',
        resolve));
      try {
        const client = await connectClient({
          mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${submitServer.address().port}/`,
          token: 'scoped-token', durability: 'durable',
        });
        try {
          const submitted = await client.aql(document, {format: 'json',
            requestId: 'published-values-request'});
          assert.equal(submitted.profile.durability, 'durable');
          assert.equal(submitted.ref.runDefinitionCid,
            plan.runDefinition.identity);
          const repeated = await client.aql(document, {format: 'json',
            requestId: 'published-values-request'});
          assert.deepEqual(repeated.ref, submitted.ref);
        } finally { client.close(); }
      } finally {
        await new Promise(resolve => submitServer.close(resolve));
        journal.close();
      }
      assert.equal(issues, 1);
      assert.equal(computes, 1);
      assert.equal(published.status, 'published');
      assert.equal(published.execution.status, 'host-tasks-completed');
      assert.deepEqual(published.execution.resultInventory.map(
        result => result.name), ['answer']);
      assert.equal(published.execution.completed[0].outputRows,
        expected.length);
      assert.equal(published.publication.publication.state, 'succeeded');
      await published.close();
      assert.equal(published.cleanupPending(), false);
      assert.equal(await published.cleanup(), true);
      published = undefined;
      await store.close();
      store = await openLocalPublicationStore(configuration, control);
      const reopened = openClientRequestJournal(journalDirectory);
      let ref;
      try {
        const retained = await reopened.admitOrLookupDefinition(identity, {
          tenantId: 'tenant-a',
          lookupExpiresAt: '2099-01-01T00:00:00.000Z',
          issueDefinition: () => {
            throw new Error('Duplicate request reissued Run authority');
          },
        }, moon, control);
        assert.equal(retained.inserted, false);
        assert.equal(retained.runDefinition.wire, plan.runDefinition.wire);
        ref = retained.ref;
      } finally {
        reopened.close();
      }
      const authority = installResultAccessAuthority({
        authorizeResultReadRequest: () => true,
        admitResultRead: facts => ({
          authorizationContextCid: `sha256:${createHash('sha256')
            .update(facts.attemptId).digest('hex')}`,
          dataCeilingCid: cid('9'),
          egressAdmissionCid: cid('a'),
          expiresAt: '2026-09-24T01:00:00.000Z',
          maxBytes: 100000, maxUses: 1,
        }),
        authorizeResultRead: () => true,
        authorizeDeliveryAttemptLookup: () => true,
      });
      const service = installNodeResultAccessService({
        store, control, authority,
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
        frameLimits: {maxRowBytes: 4096, maxDepth: 32,
          maxFrameBytes: 4096},
      });
      const stateService = installRunStateService({
        store, control,
        authority: installRunStateAuthority({
          authorizeRunState: () => true,
          resultPolicyAvailable: () => true,
        }),
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
      });
      const server = createServer(createClientHttpHandler({
        authenticate: header => header === 'Bearer scoped-token'
          ? 'principal-after-restart' : undefined,
        authorizeConnection: facts => facts.connection.mode === 'local' &&
          facts.connection.owner === 'local' &&
          (facts.ref === undefined || facts.ref.tenantId === 'tenant-a'),
        negotiate: () => ({
          version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'principal-after-restart',
          capabilities: ['result-jsonl'],
          limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024,
            maxRetainedValueBytes: 4096, maxRows: 100,
            maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
        }),
        attach: async ({ref: requested, principalId}) => {
          await inspectAuthorizedRunState(stateService, {
            indexKey: requested, principalId, purpose: 'inspect',
          });
          return {ref: requested, durability: 'durable', revision: 0};
        },
        stateService, resultService: service,
      }));
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      try {
        const client = await connectClient({
          mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${server.address().port}/`,
          token: 'scoped-token',
        });
        const execution = await client.attach(ref);
        assert.equal(execution.profile.durability, 'durable');
        const state = await execution.status();
        assert.equal(validRunState(state), true);
        assert.equal(state.status, 'succeeded');
        assert.deepEqual(await execution.result('answer').all(), expected);
        const reader = execution.result('answer').rows();
        assert.deepEqual(await Array.fromAsync(reader), expected);
        assert.equal(reader.state(), 'complete');
        let attempt = await execution.result('answer')
          .deliveryAttempt(reader.attemptId);
        assert.equal(attempt.kind, 'found');
        for (let tries = 0; tries < 100 &&
          attempt.record?.state !== 'succeeded'; tries++) {
          await new Promise(resolve => setTimeout(resolve, 10));
          attempt = await execution.result('answer')
            .deliveryAttempt(reader.attemptId);
        }
        assert.equal(attempt.record.state, 'succeeded');
        client.close();
      } finally {
        await new Promise(resolve => server.close(resolve));
      }
    } finally {
      await published?.close();
      await store.close();
    }
  });
