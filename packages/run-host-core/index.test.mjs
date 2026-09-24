import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {admitEnvironment, admitRequestFields,
  admitSourceFreeRequestFields, admitRun, compileValues,
  issueRunDefinition, prepare, prepareRequest, prepareSourceFreeRequest,
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

test('portable Host package compiles the ordinary Values Program', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
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
    admitSourceFreeRequestFields(fields)), 'same_request');
  const explicitEmpty = cid({version: 'actql-caller-input-intent/0.1',
    selection: 'explicit', inputs: []});
  const altered = prepareRequest(prepared, scope, fields.requestId,
    explicitEmpty);
  assert.equal(requestRelation(request, altered), 'changed_intent');
  assert.throws(() => admitSourceFreeRequestFields(requestFields(altered)),
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
  const definition = privateRunDefinition(issueRunDefinition(admission,
    'tenant-scope', 'values-run', `sha256:${'c'.repeat(64)}`,
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z'));
  const body = JSON.parse(definition.wire);
  assert.equal(body.run_id, 'values-run');
  assert.equal(body.compiled_plan_cid, compiled.compiled_plan_cid);
  assert.equal(body.invocation_template_cid,
    template.bound_invocation_template_cid);
  assert.equal(definition.cid, without(body, 'run_definition_cid'));
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
