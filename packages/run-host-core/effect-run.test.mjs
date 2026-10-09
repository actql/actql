import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {buildSync} from 'esbuild';
import {admitEnvironment, prepare, compileValues, prepareEffect, compileEffect,
  prepareRequest, requestFields, prepareEffectRequest, effectSourceInputBinding,
  issueEffectSourceDispatch, prepareEffectRetainedTaskInputEdge, retainedTaskInputEdgeFacts,
  effectExecutionShape, privateEffectCompilationWires, issueAllowedEffectRun,
  effectTaskKeys, effectResultDefinitions, effectResultSchema, effectSourceEvidenceFacts,
  privateEffectRunEvidence, issueEffectRunDefinition, privateRunDefinition,
  issueEffectRunMaterials, admitEffectRunMaterials, effectRunStartCurrent} from '@actql/run-host-core';

// Original authoring fixture used by the resident Source/Effect boundary.
// This suite admits and restores real Owners; it does not run physical I/O.
const read = name => readFileSync(new URL('./fixtures/' + name, import.meta.url), 'utf8').trimEnd();
const document = read('source-compute-effect.program.json');
const environmentWire = read('source-compute-effect.environment.json');
const profiles = {rela: true};
const environment = admitEnvironment(environmentWire,
  JSON.parse(environmentWire).evidence_bundle_cid, profiles);
const fixed = character => 'sha256:' + character.repeat(64);
const originalPolicy = {executionContextCid: fixed('a'), hostPolicyCid: fixed('b'),
  expiresAt: '2099-01-01T00:00:00.000Z'};

function issued(program = document, withRequest = false) {
  const prepared = prepareEffect(program, 'json', environment);
  const compilation = compileEffect(prepared);
  const allowed = issueAllowedEffectRun(prepared, compilation, originalPolicy);
  const definition = issueEffectRunDefinition(allowed, 'resident-effect', 'original-run',
    '2026-10-09T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const retained = {document: program, format: 'json', environment, environmentWire};
  const request = withRequest ? prepareEffectRequest(prepared, compilation, fixed('c'), 'original-effect-caller') : undefined;
  const wire = issueEffectRunMaterials(allowed, definition, retained, request);
  return {prepared, compilation, allowed, definition, retained, wire, request};
}

test('formal Effect preparation retains the two-task owner and pure refusal', () => {
  const prepared = prepareEffect(document, 'json', environment);
  const compilation = compileEffect(prepared);
  assert.deepEqual(effectExecutionShape(prepared, compilation),
    {taskCount: 2, acquisitionCount: 1, effectCount: 1});
  assert.throws(() => prepare(document, 'json', environment),
    {code: 'RunHostPreparationRejected'});
  assert.throws(() => compileValues(prepared), /ForeignRunHostHandle/u);
  assert.throws(() => compileEffect({...prepared}), /ForeignRunHostHandle/u);
  const second = prepareEffect(document, 'json', environment);
  assert.throws(() => effectExecutionShape(second, compilation), /ForeignRunHostCompilation/u);
  assert.throws(() => issueAllowedEffectRun(second, compilation, originalPolicy), /ForeignRunHostCompilation/u);
});

test('saved Effect materials restore the original Run, evidence and expiry', () => {
  const original = issued();
  const definition = privateRunDefinition(original.definition);
  const savedEvidence = privateEffectRunEvidence(original.allowed);
  const body = JSON.parse(original.wire);
  assert.equal(body.program, document);
  assert.equal(body.check_environment, environmentWire);
  assert.equal(body.prepared_invocation, savedEvidence.preparedInvocationWire);
  assert.equal(body.run_authorization, savedEvidence.authorizationWire);
  assert.equal(body.run_id, 'original-run');
  assert.equal(body.created_at, '2026-10-09T00:00:00.000Z');
  assert.equal(body.valid_until, '2098-01-01T00:00:00.000Z');
  const restored = admitEffectRunMaterials(original.wire, definition.cid, profiles);
  assert.deepEqual(privateRunDefinition(restored.definition), definition);
  assert.deepEqual(privateEffectRunEvidence(restored.allowed), savedEvidence);
  assert.deepEqual(privateEffectCompilationWires(restored.compilation),
    privateEffectCompilationWires(original.compilation));
  assert.deepEqual(effectExecutionShape(restored.prepared, restored.compilation),
    {taskCount: 2, acquisitionCount: 1, effectCount: 1});
  assert.equal(issueEffectRunMaterials(restored.allowed, restored.definition, original.retained), original.wire);
  assert.equal(effectRunStartCurrent(restored.allowed, restored.definition, '2026-10-09T00:01:00.000Z'), true);
  assert.equal(effectRunStartCurrent(restored.allowed, restored.definition, '2098-01-01T00:00:01.000Z'), false);
});

test('Effect materials reject foreign Run, changed original value and expiry', () => {
  const original = issued();
  const cid = privateRunDefinition(original.definition).cid;
  assert.throws(() => admitEffectRunMaterials(original.wire, fixed('c'), profiles),
    {code: 'RunHostEffectRestorationRejected'});
  const program = JSON.parse(document);
  program.stages[1].steps[0].filter = 'id > 1';
  assert.throws(() => issueEffectRunMaterials(original.allowed, original.definition,
    {...original.retained, document: JSON.stringify(program)}),
  {code: 'RunHostEffectRunMaterialsRejected'});
  for (const alter of [
    body => { body.run_id = 'another-run'; },
    body => { body.valid_until = '2099-01-01T00:00:00.000Z'; },
    body => { body.program = JSON.stringify(program); },
    body => { body.run_authorization = body.run_authorization.replace(fixed('b'), fixed('d')); },
  ]) {
    const body = JSON.parse(original.wire);
    alter(body);
    assert.notDeepEqual(body, JSON.parse(original.wire));
    assert.throws(() => admitEffectRunMaterials(JSON.stringify(body), cid, profiles),
      {code: 'RunHostEffectRestorationRejected'});
  }
  assert.throws(() => admitEffectRunMaterials(original.wire, cid, {rela: false}),
    {code: 'RunHostEffectRestorationRejected'});
});

test('shared input parsing preserves a pure Values caller and supplied parameters', () => {
  const fixture = name => readFileSync(new URL('../sdk/fixtures/' + name,
    import.meta.url), 'utf8');
  const wire = fixture('values.environment.json').trimEnd();
  const pureEnvironment = admitEnvironment(wire, JSON.parse(wire).evidence_bundle_cid, profiles);
  const program = fixture('parameter-values.json');
  const prepareFields = parameters => requestFields(prepareRequest(
    prepare(program, 'json', pureEnvironment, parameters), fixed('c'),
    'parameter-run', fixed('d')));
  assert.deepEqual(prepareFields('{"n":3}'), prepareFields(' { "n" : 3 } '));
  assert.notDeepEqual(prepareFields('{"n":3}'), prepareFields('{"n":4}'));
  compileValues(prepare(program, 'json', pureEnvironment, '{"n":3}'));
});

test('Effect input parsing preserves the bounded Parameter Values rejection', () => {
  for (const parameters of ['{', JSON.stringify({n: 'x'.repeat(65536)})]) {
    assert.throws(() => prepareEffect(document, 'json', environment, parameters),
      {code: 'RunHostEffectPreparationRejected'});
    assert.throws(() => prepare(document, 'json', environment, parameters),
      {code: 'RunHostPreparationRejected'});
  }
  assert.throws(() => prepareEffect(document, 'sql', environment), /InvalidRunHostPreparation/u);
  assert.throws(() => admitEffectRunMaterials('{}', fixed('a'), {unknown: true}), /InvalidRunHostProfiles/u);
});

test('formal Effect exports bundle for a Worker without a physical runtime', () => {
  const result = buildSync({stdin: {contents:
    "export {prepareEffect, compileEffect, admitEffectRunMaterials, issueEffectSourceDispatch, issueEffectRetainedTaskDispatch, effectTaskKeys, effectResultDefinitions, effectResultSchema, effectSourceEvidenceFacts} from '@actql/run-host-core';",
  resolveDir: import.meta.dirname}, bundle: true, write: false,
  platform: 'browser', format: 'esm', target: 'es2022', metafile: true});
  const inputs = Object.keys(result.metafile.inputs);
  assert(inputs.some(path => path.endsWith('/dist/client_values_host_abi.js')));
  assert(inputs.every(path => !path.includes('host-node') &&
    !path.includes('local-node') && !path.startsWith('node:')));
});

const effectSelection = {taskAttempt: 1, dispatchId: 'original-producer',
  siteKey: 'site-a', siteGeneration: 1, runtimeBundleCid: fixed('a'),
  connectorRegistration: 'local', connectorRevision: 'local/1',
  strategyRevision: 'strategy/1', obligationsCid: fixed('1'), budgetCid: fixed('2'),
  evidenceIssuerCapabilityCid: fixed('3'), grantCid: fixed('4')};

test('Effect execution inventory selects the original dispatch graph and Result contract', () => {
  const original = issued();
  const keys = effectTaskKeys(original.prepared, original.compilation);
  assert.equal(keys.length, 2);
  assert(Object.isFrozen(keys));
  const edge = retainedTaskInputEdgeFacts(prepareEffectRetainedTaskInputEdge(
    original.allowed, original.definition));
  assert.deepEqual(keys, [edge.producerTaskKey, edge.consumerTaskKey]);
  const caller = prepareEffectRequest(original.prepared, original.compilation,
    fixed('c'), 'inventory-caller');
  const dispatch = JSON.parse(issueEffectSourceDispatch(original.allowed,
    original.definition, caller, effectSelection).wire);
  assert.equal(dispatch.task_key, keys[0]);
  const definitions = effectResultDefinitions(original.prepared, original.compilation);
  assert(Object.isFrozen(definitions));
  assert.equal(definitions.length, 1);
  assert(Object.isFrozen(definitions[0]));
  const programCid = requestFields(caller).programDefinitionCid;
  const preimage = JSON.stringify({program_definition_cid: programCid,
    result_name: 'answer', version: 'actql-result-definition/0.1'});
  const resultCid = 'sha256:' + createHash('sha256').update(preimage).digest('hex');
  assert.deepEqual(definitions[0], {name: 'answer', cid: resultCid,
    wire: JSON.stringify({program_definition_cid: programCid,
      result_definition_cid: resultCid, result_name: 'answer',
      version: 'actql-result-definition/0.1'})});
  const schema = effectResultSchema(original.prepared, original.compilation, 'answer');
  assert.equal(schema.wire, '{"id":{"nullable":false,"type":"number"}}');
  assert.deepEqual(schema.fields, ['id']);
  assert.equal(schema.cid, 'sha256:' + createHash('sha256').update(schema.wire).digest('hex'));
  assert(Object.isFrozen(schema));
  const source = effectSourceEvidenceFacts(original.prepared, original.compilation, 0, 0);
  const catalog = JSON.parse(environmentWire).connector_catalogs[0];
  const view = catalog.source_views[0];
  assert.deepEqual(source, {sourceRef: 'connector://crm/main/r#v',
    sourceContractCid: view.contract_cid, sourceViewContractCid: view.contract_cid,
    carrierSchemaContractCid: view.output.schema.cid,
    sourceDataPolicyCid: view.output.data_policy.cid, dataClassification: 'unknown'});
  assert(Object.isFrozen(source));
  assert.equal(effectSourceEvidenceFacts(original.prepared, original.compilation, 1, 0), undefined);
});

test('Effect inventory survives exact original materials reconstruction', () => {
  const original = issued();
  const restored = admitEffectRunMaterials(original.wire,
    privateRunDefinition(original.definition).cid, profiles);
  for (const method of [effectTaskKeys, effectResultDefinitions]) {
    assert.deepEqual(method(restored.prepared, restored.compilation),
      method(original.prepared, original.compilation));
  }
  assert.deepEqual(effectResultSchema(restored.prepared, restored.compilation, 'answer'),
    effectResultSchema(original.prepared, original.compilation, 'answer'));
  assert.deepEqual(effectSourceEvidenceFacts(restored.prepared, restored.compilation, 0, 0),
    effectSourceEvidenceFacts(original.prepared, original.compilation, 0, 0));
});

test('Effect inventory rejects another preparation, copied handles and foreign selections', () => {
  const original = issued();
  const other = issued(document.replace('id > 2', 'id > 1'));
  for (const [method, args] of [[effectTaskKeys, []], [effectResultDefinitions, []],
    [effectResultSchema, ['answer']], [effectSourceEvidenceFacts, [0, 0]]]) {
    assert.throws(() => method(other.prepared, original.compilation, ...args),
      /ForeignRunHostCompilation/u);
    assert.throws(() => method(original.prepared, {...original.compilation}, ...args),
      /ForeignRunHostHandle/u);
  }
  assert.throws(() => effectResultSchema(original.prepared, original.compilation, 'r'),
    /UnknownRunHostResult/u);
  for (const coordinate of [-1, 1.5, 2147483648]) {
    assert.throws(() => effectSourceEvidenceFacts(original.prepared, original.compilation,
      coordinate, 0), /InvalidRunHostSourceSelection/u);
  }
});

test('formal Effect Source dispatch preserves original caller Run and checked edge on reconstruction', () => {
  const original = issued();
  const request = prepareEffectRequest(original.prepared, original.compilation,
    fixed('c'), 'original-caller');
  const dispatch = issueEffectSourceDispatch(original.allowed, original.definition,
    request, effectSelection);
  const body = JSON.parse(dispatch.wire);
  const edge = prepareEffectRetainedTaskInputEdge(original.allowed, original.definition);
  const facts = retainedTaskInputEdgeFacts(edge);
  assert.equal(body.run_definition_cid, privateRunDefinition(original.definition).cid);
  assert.equal(body.task_key, facts.producerTaskKey);
  assert.equal(facts.consumerInputPort, 'x');
  assert.notEqual(facts.producerTaskKey, facts.consumerTaskKey);
  assert.equal(facts.runDefinitionCid, body.run_definition_cid);
  assert.deepEqual(JSON.parse(effectSourceInputBinding(original.compilation)), {
    source_ref: 'connector://crm/main/r#v',
    source_contract_cid: 'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
  });
  const restored = admitEffectRunMaterials(original.wire, body.run_definition_cid, profiles);
  const restoredCaller = prepareEffectRequest(restored.prepared, restored.compilation,
    fixed('c'), 'original-caller');
  assert.deepEqual(requestFields(restoredCaller), requestFields(request));
  assert.deepEqual(issueEffectSourceDispatch(restored.allowed, restored.definition,
    restoredCaller, effectSelection), dispatch);
  assert.deepEqual(retainedTaskInputEdgeFacts(prepareEffectRetainedTaskInputEdge(
    restored.allowed, restored.definition)), facts);
  assert.equal(effectSourceInputBinding(restored.compilation), effectSourceInputBinding(original.compilation));
  assert.equal(JSON.parse(issueEffectSourceDispatch(original.allowed, original.definition,
    request, {...effectSelection, siteGeneration: 0}).wire).site_generation, 0);
});

test('formal Effect dispatch rejects foreign Program bindings and lossy Site selection before delivery', () => {
  const original = issued();
  const other = issued(document.replace('id > 2', 'id > 1'));
  assert.throws(() => prepareEffectRequest(other.prepared, original.compilation,
    fixed('c'), 'original-caller'), /ForeignRunHostCompilation/u);
  assert.throws(() => effectSourceInputBinding({...original.compilation}), /ForeignRunHostHandle/u);
  assert.throws(() => prepareEffectRetainedTaskInputEdge({...original.allowed}, original.definition),
    /ForeignRunHostHandle/u);
  const request = prepareEffectRequest(original.prepared, original.compilation,
    fixed('c'), 'original-caller');
  const different = issueEffectRunDefinition(original.allowed, 'resident-effect',
    'another-run', '2026-10-09T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  assert.throws(() => issueEffectSourceDispatch(other.allowed, different,
    request, effectSelection), {code: 'RunHostEffectSourceDispatchRejected'});
  for (const change of [{taskAttempt: 0}, {taskAttempt: 2147483648},
    {siteGeneration: -1}, {siteGeneration: 1.5}, {extra: 'unchecked'}]) {
    assert.throws(() => issueEffectSourceDispatch(original.allowed,
      original.definition, request, {...effectSelection, ...change}), /InvalidRunHostSiteSelection/u);
  }
});


test('Effect Site selection validates the same snapshot that reaches dispatch', () => {
  const original = issued();
  const request = prepareEffectRequest(original.prepared, original.compilation,
    fixed('c'), 'original-caller');
  let reads = 0;
  const selection = {...effectSelection, get taskAttempt() {
    return ++reads <= 3 ? 1 : 2147483648;
  }};
  const actual = issueEffectSourceDispatch(original.allowed, original.definition,
    request, selection);
  const expected = issueEffectSourceDispatch(original.allowed, original.definition,
    request, effectSelection);
  assert.deepEqual(actual, expected);
  assert.equal(reads, 1);
});


test('Effect schema keeps canonical numeric field order across the JS boundary', () => {
  const program = JSON.parse(document);
  program.stages[1].steps[1].select = ['id', {'10': 'id'}, {'2': 'id'}];
  program.stages[1].results.r.fields = ['id', '10', '2'];
  const original = issued(JSON.stringify(program));
  const schema = effectResultSchema(original.prepared, original.compilation, 'answer');
  assert.deepEqual(schema.fields, ['10', '2', 'id']);
  assert.equal(schema.wire, '{"10":{"nullable":false,"type":"number"},"2":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"}}');
  assert.equal(schema.cid, 'sha256:' + createHash('sha256').update(schema.wire).digest('hex'));
});
test('Effect review materials retain the original request through actual package restoration', () => {
  const original = issued(document, true);
  const definition = privateRunDefinition(original.definition);
  const restored = admitEffectRunMaterials(original.wire, definition.cid, profiles);
  assert.deepEqual(requestFields(restored.request), requestFields(original.request));
  assert.equal(issueEffectRunMaterials(restored.allowed, restored.definition,
    original.retained, restored.request), original.wire);
  assert.deepEqual(privateEffectRunEvidence(restored.allowed), privateEffectRunEvidence(original.allowed));
  const body = JSON.parse(original.wire);
  const record = JSON.parse(body.client_request_identity);
  assert.equal(record.caller_request_id, 'original-effect-caller');
  assert.equal(record.authority_scope_cid, fixed('c'));
  for (const mutate of [record => { record.caller_request_id = 'another-caller'; },
    record => { record.intent_fingerprint_cid = fixed('d'); },
    record => { record.extra = true; }]) {
    const changed = {...record}; mutate(changed);
    assert.throws(() => admitEffectRunMaterials(JSON.stringify({...body,
      client_request_identity: JSON.stringify(changed)}), definition.cid, profiles),
    {code: 'RunHostEffectRestorationRejected'});
  }
  assert.equal(admitEffectRunMaterials(issued().wire, definition.cid, profiles).request, undefined);
});
