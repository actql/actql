import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {admitDispatchJson, dispatchCid} from '../coordinator-core/index.mjs';
import {admitEnvironment, admitRequestFields, admitRunDefinition,
  admitPublicationContract, validatePublicationChain,
  validatePublicationRecordTransition,
  issueResultManifest,
  issueResultOccurrenceEvidence, issueCompleteResultArtifact,
  issueDurableResultBinding,
  inspectCanonicalResultRows,
  admitSourceFreeRequestFields, admitRun, compileValues,
  checkRunBinding, issueAllowedRun, issueRunDefinition, prepare, prepareRequest,
  issueSourceFreeDispatch,
  executionShape,
  resultDefinitions,
  prepareRunStart,
  prepareSourceFreeRequest,
  privateCompilationWires,
  privateRunDefinition, requestFields, requestRelation} from './index.mjs';

const read = name => readFileSync(new URL(`../sdk/fixtures/${name}`,
  import.meta.url), 'utf8');
const environmentWire = read('values.environment.json').trimEnd();
const evidenceCid = JSON.parse(environmentWire).evidence_bundle_cid;
const cid = body => `sha256:${createHash('sha256')
  .update(canonicalText(body)).digest('hex')}`;
const without = (value, key) => {
  const body = {...value};
  delete body[key];
  return cid(body);
};

test('portable Host re-admits exact publication evidence', () => {
  const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const definition = resultDefinitions(prepared, compileValues(prepared))[0];
  const admitted = admitPublicationContract('result_definition',
    definition.wire, limits);
  assert.equal(admitted.cid, definition.cid);
  assert.equal(admitted.wire, definition.wire);
  const altered = JSON.parse(definition.wire);
  altered.result_name = 'different';
  assert.throws(() => admitPublicationContract('result_definition',
    JSON.stringify(altered), limits),
  {code: 'RunHostPublicationContractRejected'});
  assert.throws(() => admitPublicationContract('result_artifact',
    definition.wire, limits),
  {code: 'RunHostPublicationContractRejected'});
  assert.throws(() => validatePublicationChain(admitted, admitted,
    [admitted], [admitted], admitted, limits),
  {code: 'RunHostPublicationChainRejected'});
  assert.throws(() => validatePublicationRecordTransition(undefined,
    admitted, false),
  {code: 'RunHostPublicationTransitionRejected'});
  assert.throws(() => admitPublicationContract('result_definition',
    definition.wire, {maxWireBytes: 0, maxNodes: 100, maxDepth: 10}),
  {name: 'TypeError', message: 'InvalidRunHostPublicationLimits'});
});

test('portable Host derives logical identity from exact ordered rows', () => {
  const limits = {maxWireBytes: 4096, maxNodes: 100, maxDepth: 16};
  const rows = '[{"id":1},{"id":2}]';
  assert.deepEqual(inspectCanonicalResultRows(rows, ['id'], limits), {
    logicalRelationCid:
      'sha256:ffd3ea44b8fb5324bbdc17735e31f10e00f60e5debddd3be1957f712204f331f',
    rowCount: 2,
  });
  for (const body of ['[{"id":1}, {"id":2}]',
    '[{"id":1},{"other":2}]', '{"id":1}']) {
    assert.throws(() => inspectCanonicalResultRows(body, ['id'], limits),
    {code: 'RunHostResultRowsRejected'});
  }
  assert.throws(() => inspectCanonicalResultRows(rows, ['other'], limits),
    {code: 'RunHostResultRowsRejected'});
});

test('portable Host issues a Manifest for exact admitted Result evidence',
  () => {
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const fixed = value => `sha256:${value.repeat(64)}`;
    const admit = (name, body, identityField) => {
      const complete = {...body, [identityField]: cid(body)};
      return admitPublicationContract(name, JSON.stringify(complete), limits);
    };
    const run = admit('run_definition', {
      version: 'actql-run-definition/0.1', scope_id: 'scope', run_id: 'run',
      compiled_plan_cid: fixed('3'), invocation_template_cid: fixed('1'),
      authorization_context_cid: fixed('4'),
      input_artifact_set_cid: fixed('5'),
      created_at: '2026-09-18T00:00:00.000Z',
      valid_until: '2026-09-18T01:00:00.000Z',
    }, 'run_definition_cid');
    const invocation = admit('run_invocation', {
      version: 'actql-run-invocation/0.1',
      invocation_template_cid: fixed('1'),
      observation_set_cid: fixed('2'),
    }, 'invocation_cid');
    const definition = admit('result_definition', {
      version: 'actql-result-definition/0.1',
      program_definition_cid: fixed('6'), result_name: 'answer',
    }, 'result_definition_cid');
    const schemaWire = JSON.stringify({value: {nullable: false,
      type: 'integer'}});
    const schemaCid = cid(JSON.parse(schemaWire));
    const occurrence = issueResultOccurrenceEvidence(definition, {
      logicalValueCid: fixed('7'), resultSchemaCid: schemaCid,
      computationContractCid: fixed('3'), inputRelationCids: [],
      scopeCid: fixed('5'),
      effectiveDataPolicyCid: fixed('a'),
      issuerId: 'common-host', authorityScopeCid: fixed('d'),
    }, limits);
    const retention = admit('result_retention_policy', {
      version: 'actql-result-retention-policy/0.1',
      retention_contract_cid: fixed('b'),
      effective_data_policy_cid: fixed('a'),
      available_until: '2026-09-18T01:00:00.000Z',
      delete_by: '2026-09-18T02:00:00.000Z',
      extension_ceiling_at: '2026-09-18T03:00:00.000Z',
      metadata_retention_policy_cid: fixed('c'),
      metadata_delete_by: '2026-09-18T04:00:00.000Z',
      clock_contract_cid: fixed('d'),
    }, 'effective_retention_policy_cid');
    const artifact = issueCompleteResultArtifact(definition, invocation,
      occurrence, retention, 1, limits);
    assert.equal(JSON.parse(artifact.wire).ordering_evidence_cid,
      occurrence.ordering.cid);
    const physical = {codecContractCid: fixed('d'),
      resultFields: ['value'], resultSchemaWire: schemaWire,
      materialGenerationCid: fixed('e'), storeAuthorityCid: fixed('f'),
      rowCount: 1, byteCount: 10, physicalSha256: 'e'.repeat(64)};
    const binding = issueDurableResultBinding(run, definition,
      invocation, artifact, occurrence.ordering, retention, physical, limits);
    assert.equal(JSON.parse(binding.wire).run_definition_cid, run.cid);
    assert.equal(JSON.parse(binding.wire).logical_result_cid, fixed('7'));
    assert.throws(() => issueDurableResultBinding(run, definition,
      invocation, artifact, occurrence.ordering, retention,
      {...physical, rowCount: 2}, limits),
    {code: 'RunHostDurableBindingRejected'});
    const {effective_retention_policy_cid: _identity,
      ...retentionBody} = JSON.parse(retention.wire);
    assert.throws(() => issueCompleteResultArtifact(definition, invocation,
      occurrence, admit('result_retention_policy', {
        ...retentionBody, effective_data_policy_cid: fixed('f'),
      }, 'effective_retention_policy_cid'), 1, limits),
    {code: 'RunHostResultArtifactRejected'});
    const manifest = issueResultManifest(run, invocation, [definition],
      [artifact], limits);
    validatePublicationChain(run, invocation, [definition], [artifact],
      manifest, limits);
    assert.equal(JSON.parse(manifest.wire).results.answer
      .result_artifact_cid, artifact.cid);
    assert.throws(() => issueResultManifest(run, invocation, [definition],
      [], limits), {code: 'RunHostResultManifestRejected'});
    assert.throws(() => validatePublicationChain(run, invocation,
      [definition], [], manifest, limits),
    {code: 'RunHostPublicationChainRejected'});
    assert.throws(() => validatePublicationChain(run, invocation,
      [definition], [artifact], definition, limits),
    {code: 'RunHostPublicationChainRejected'});
  });

test('portable Host package compiles the ordinary Values Program', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  assert.deepEqual(executionShape(compilation), {
    planNodeId: 'values_0',
    outputContractCid:
      'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c',
    resultNames: ['answer'],
  });
  const definitions = resultDefinitions(prepared, compilation);
  const programCid = requestFields(prepareSourceFreeRequest(prepared,
    compilation, `sha256:${'a'.repeat(64)}`, 'inventory-request'))
    .programDefinitionCid;
  const definitionCid = cid({version: 'actql-result-definition/0.1',
    program_definition_cid: programCid, result_name: 'answer'});
  assert.deepEqual(definitions, [{
    name: 'answer',
    cid: definitionCid,
    wire: JSON.stringify({program_definition_cid: programCid,
      result_definition_cid: definitionCid,
      result_name: 'answer', version: 'actql-result-definition/0.1'}),
  }]);
  assert.throws(() => resultDefinitions(prepare(read('values.json'),
    'json', environment), compilation),
  {name: 'TypeError', message: 'ForeignRunHostCompilation'});
  const wires = privateCompilationWires(compilation);
  const plan = JSON.parse(wires.executablePlan);
  const facts = JSON.parse(wires.factManifest);
  const template = JSON.parse(wires.boundTemplate);
  const compiled = JSON.parse(wires.compiledPlan);
  assert.equal(plan.version, 'actql-executable-plan/0.1');
  assert.equal(plan.executable_plan_cid, without(plan, 'executable_plan_cid'));
  assert.equal(facts.plan_fact_manifest_cid,
    without(facts, 'plan_fact_manifest_cid'));
  assert.deepEqual(plan.plan_facts, facts.plan_facts);
  assert.deepEqual(plan.root_refs.map(root => root.name), ['answer']);
  assert.deepEqual(plan.execution_material.result_plan_logical_cids,
    {answer: 'sha256:db7320fcd0090a93ced0c41a6936103a1d2ab02f87beb95d8c99733c95713d53'});
  assert.equal(template.bound_invocation_template_cid,
    without(template, 'bound_invocation_template_cid'));
  assert.equal(compiled.compiled_plan_cid,
    without(compiled, 'compiled_plan_cid'));
  assert.equal(compiled.executable_plan_cid, plan.executable_plan_cid);
  assert.equal(compiled.aoa_contract_cid,
    'sha256:26fbe956d369ada84612a9c93414c8c04bd20f3e11dccf3308f4b5e2a296658d');
  assert.throws(() => compileValues({kind: 'prepared-program'}),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
});

test('portable Host rejects unadmitted environment and invalid Program', () => {
  assert.throws(() => admitEnvironment(environmentWire, evidenceCid,
    {rela: true, future: true}),
  {name: 'TypeError', message: 'InvalidRunHostEnvironment'});
  assert.throws(() => admitEnvironment(environmentWire,
    `sha256:${'0'.repeat(64)}`, {rela: true}),
  {code: 'RunHostEnvironmentRejected'});
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  assert.throws(() => prepare('{"version":"actql/0.1"}', 'json',
    environment), {code: 'RunHostPreparationRejected'});
  assert.throws(() => prepare(read('values.json'), 'future', environment),
    {name: 'TypeError', message: 'InvalidRunHostPreparation'});
});

test('portable Host owns the exact checked logical request relation', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const document = read('values.json');
  const prepared = prepare(document, 'json', environment);
  const scope = `sha256:${'a'.repeat(64)}`;
  const input = `sha256:${'b'.repeat(64)}`;
  const first = prepareRequest(prepared, scope, 'saved-request', input);
  const fields = requestFields(first);
  assert.equal(fields.authorityScopeCid, scope);
  assert.equal(fields.requestId, 'saved-request');
  assert.equal(fields.callerInputIntentCid, input);
  assert.equal(fields.logicalRequestScopeCid, cid({
    version: 'actql-logical-request/0.1',
    authority_scope_cid: scope, caller_request_id: 'saved-request',
  }));
  assert.equal(fields.intentFingerprintCid, cid({
    version: 'actql-logical-request-intent/0.1',
    caller_input_intent_cid: input,
    parameter_values_cid: fields.parameterValuesCid,
    program_definition_cid: fields.programDefinitionCid,
  }));
  const restored = admitRequestFields(fields);
  assert.equal(requestRelation(first, restored), 'same_request');
  assert.deepEqual(requestFields(restored), fields);
  const changed = prepare(document.replace('"id": 2', '"id": 3'),
    'json', environment);
  assert.equal(requestRelation(prepareRequest(changed, scope,
    'saved-request', input), restored), 'changed_intent');
  assert.equal(requestRelation(prepareRequest(prepared, scope,
    'other-request', input), restored), 'different_request');
  assert.throws(() => admitRequestFields({...fields,
    intentFingerprintCid: `sha256:${'0'.repeat(64)}`}),
  {code: 'RunHostRequestRecordRejected'});
  assert.throws(() => admitRequestFields({...fields, extra: true}),
    {name: 'TypeError', message: 'InvalidRunHostRequestRecord'});
  assert.throws(() => requestRelation({}, restored),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
});

test('source-free request admission pins no input, not explicit empty', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  const scope = `sha256:${'a'.repeat(64)}`;
  const request = prepareSourceFreeRequest(prepared, compilation,
    scope, 'no-input-request');
  const fields = requestFields(request);
  assert.equal(fields.callerInputIntentCid, cid({
    version: 'actql-caller-input-intent/0.1', selection: 'none',
  }));
  assert.equal(requestRelation(request,
    admitSourceFreeRequestFields(prepared, compilation, fields)),
  'same_request');
  const explicitEmpty = cid({version: 'actql-caller-input-intent/0.1',
    selection: 'explicit', inputs: []});
  const altered = prepareRequest(prepared, scope, fields.requestId,
    explicitEmpty);
  assert.equal(requestRelation(request, altered), 'changed_intent');
  assert.throws(() => admitSourceFreeRequestFields(prepared, compilation,
    requestFields(altered)),
    {code: 'RunHostRequestRecordRejected'});
  const otherProgram = prepare(read('values.json').replace('"id": 2',
    '"id": 3'), 'json', environment);
  assert.throws(() => admitSourceFreeRequestFields(otherProgram,
    compileValues(otherProgram), fields),
  {code: 'RunHostRequestRecordRejected'});
  assert.throws(() => prepareSourceFreeRequest(prepared,
    compileValues(prepare(read('values.json'), 'json', environment)),
    scope, 'no-input-request'),
  {name: 'TypeError', message: 'ForeignRunHostCompilation'});
});

test('portable Host admits exact policy evidence before Run Definition', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  const wires = privateCompilationWires(compilation);
  const template = JSON.parse(wires.boundTemplate);
  const compiled = JSON.parse(wires.compiledPlan);
  // The test Host supplies bounded policy evidence. This fixture does not
  // establish a product authorization policy or input selection contract.
  const contextCid = `sha256:${'a'.repeat(64)}`;
  const policyCid = `sha256:${'b'.repeat(64)}`;
  const evidence = (body, self) => JSON.stringify({...body,
    [self]: cid(body)});
  const preparedBody = {
    version: 'actql-prepared-invocation/0.1',
    invocation_template_cid: template.bound_invocation_template_cid,
    compiled_plan_cid: compiled.compiled_plan_cid,
    execution_context_cid: contextCid,
    host_policy_cid: policyCid,
    policy_decision: 'allow',
    expires_at: '2099-01-01T00:00:00.000Z',
  };
  const authorizationBody = {
    version: 'actql-run-authorization/0.1',
    prepared_invocation_cid: cid(preparedBody),
    execution_context_cid: contextCid,
    host_policy_cid: policyCid,
    decision: 'allowed',
  };
  const admit = (p = preparedBody, a = authorizationBody) => admitRun(
    prepared, compilation, evidence(p, 'prepared_invocation_cid'),
    evidence(a, 'run_authorization_cid'));
  const admission = admit();
  const issued = issueAllowedRun(prepared, compilation, {
    executionContextCid: contextCid, hostPolicyCid: policyCid,
    expiresAt: '2099-01-01T00:00:00.000Z',
  });
  assert.deepEqual(JSON.parse(issued.preparedInvocationWire),
    JSON.parse(evidence(preparedBody, 'prepared_invocation_cid')));
  assert.deepEqual(JSON.parse(issued.authorizationWire),
    JSON.parse(evidence(authorizationBody, 'run_authorization_cid')));
  assert.deepEqual(privateRunDefinition(issueRunDefinition(issued.admission,
    'tenant-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z')),
  privateRunDefinition(issueRunDefinition(admission,
    'tenant-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z')));
  assert.throws(() => issueAllowedRun(prepared, compilation, {
    executionContextCid: `sha256:${'0'.repeat(64)}`,
    hostPolicyCid: 'not-a-cid',
    expiresAt: '2099-01-01T00:00:00.000Z',
  }), {code: 'RunHostAdmissionRejected'});
  const definition = privateRunDefinition(issueRunDefinition(admission,
    'tenant-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z'));
  const body = JSON.parse(definition.wire);
  assert.equal(body.run_id, 'values-run');
  assert.equal(body.compiled_plan_cid, compiled.compiled_plan_cid);
  assert.equal(body.invocation_template_cid,
    template.bound_invocation_template_cid);
  assert.equal(definition.cid, without(body, 'run_definition_cid'));
  const restoredDefinition = admitRunDefinition(definition.wire);
  assert.deepEqual(privateRunDefinition(restoredDefinition), definition);
  checkRunBinding(prepared, admission, restoredDefinition);
  assert.throws(() => checkRunBinding(
    prepare(read('values.json'), 'json', environment), admission,
    restoredDefinition),
  {name: 'TypeError', message: 'ForeignRunHostAdmission'});
  const request = prepareSourceFreeRequest(prepared, compilation, contextCid,
    'durable-run-request');
  const restoredRequest = admitSourceFreeRequestFields(prepared, compilation,
    requestFields(request));
  assert.equal(prepareRunStart(request, restoredRequest,
    restoredDefinition, definition.cid, false, true), 'reserve_dispatch');
  assert.equal(prepareRunStart(request, restoredRequest,
    restoredDefinition, definition.cid, true, true),
  'reconcile_reserved_dispatch');
  assert.throws(() => prepareRunStart(request, restoredRequest,
    restoredDefinition, definition.cid, false, false),
  {code: 'RunHostStartRejected'});
  assert.throws(() => prepareRunStart(request, restoredRequest,
    restoredDefinition, `sha256:${'0'.repeat(64)}`, false, true),
  {code: 'RunHostStartRejected'});
  assert.throws(() => admitRunDefinition(JSON.stringify({...body,
    run_id: 'foreign'})), {code: 'RunHostDefinitionRejected'});
  assert.throws(() => admit({...preparedBody,
    compiled_plan_cid: `sha256:${'0'.repeat(64)}`}),
  {code: 'RunHostAdmissionRejected'});
  assert.throws(() => admit(preparedBody, {...authorizationBody,
    decision: 'denied'}), {code: 'RunHostAdmissionRejected'});
  assert.throws(() => issueRunDefinition(admission,
    'tenant-scope', 'late-run', `sha256:${'c'.repeat(64)}`,
    '2099-01-01T00:00:00.000Z', '2100-01-01T00:00:00.000Z'),
  {code: 'RunHostDefinitionRejected'});
  assert.throws(() => issueRunDefinition({}, 'tenant-scope', 'foreign',
    `sha256:${'c'.repeat(64)}`, '2026-09-24T00:00:00.000Z',
    '2027-01-01T00:00:00.000Z'),
  {name: 'TypeError', message: 'ForeignRunHostHandle'});
});

test('checked Run issues one source-free Site dispatch identity', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  const scope = `sha256:${'a'.repeat(64)}`;
  const policy = {executionContextCid: `sha256:${'b'.repeat(64)}`,
    hostPolicyCid: `sha256:${'c'.repeat(64)}`,
    expiresAt: '2099-01-01T00:00:00.000Z'};
  const admission = issueAllowedRun(prepared, compilation, policy).admission;
  const definition = issueRunDefinition(admission, 'site-scope', 'site-run',
    `sha256:${'d'.repeat(64)}`, '2026-09-25T00:00:00.000Z',
    '2027-01-01T00:00:00.000Z');
  const request = prepareSourceFreeRequest(prepared, compilation,
    scope, 'site-request');
  const selection = {taskAttempt: 1, dispatchId: 'site-dispatch',
    siteKey: 'site-a', siteGeneration: 1,
    runtimeBundleCid: `sha256:${'1'.repeat(64)}`,
    connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    obligationsCid: `sha256:${'2'.repeat(64)}`,
    budgetCid: `sha256:${'3'.repeat(64)}`,
    evidenceIssuerCapabilityCid: `sha256:${'4'.repeat(64)}`,
    grantCid: `sha256:${'5'.repeat(64)}`};
  const issued = issueSourceFreeDispatch(prepared, compilation, admission,
    definition, request, selection);
  const wire = JSON.parse(issued.wire);
  assert.equal(wire.run_definition_cid,
    privateRunDefinition(definition).cid);
  assert.equal(wire.task_key, 'values_0');
  assert.equal(wire.coordinator_authority, scope);
  assert.equal(wire.input_binding_cid, cid({}));
  assert.equal(dispatchCid(admitDispatchJson(issued.wire, issued.cid)),
    issued.cid);
  assert.throws(() => admitDispatchJson(issued.wire,
    `sha256:${'f'.repeat(64)}`), {code: 'CoordinatorOwnerRejected'});
  assert.throws(() => issueSourceFreeDispatch(prepared, compilation,
    admission, definition, prepareRequest(prepared, scope, 'site-request',
      `sha256:${'e'.repeat(64)}`), selection),
  {code: 'RunHostDispatchRejected'});
  assert.throws(() => issueSourceFreeDispatch(prepared, compilation,
    admission, definition, request,
    {...selection, connectorRegistration: 'duckdb'}),
  {code: 'RunHostDispatchRejected'});
  const foreign = prepare(read('values.json').replace('"id": 2', '"id": 3'),
    'json', environment);
  const foreignCompilation = compileValues(foreign);
  const foreignAdmission = issueAllowedRun(foreign, foreignCompilation,
    policy).admission;
  const foreignDefinition = issueRunDefinition(foreignAdmission,
    'site-scope', 'foreign-run', `sha256:${'d'.repeat(64)}`,
    '2026-09-25T00:00:00.000Z', '2027-01-01T00:00:00.000Z');
  assert.throws(() => issueSourceFreeDispatch(prepared, compilation,
    admission, foreignDefinition, request, selection),
  {code: 'RunHostDispatchRejected'});
});
