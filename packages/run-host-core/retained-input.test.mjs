import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {residentSourceEnvironment} from '../../scripts/fixtures/resident-source.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import * as transfer from '../transfer-core/index.mjs';
import {admitDispatchJson, createJournal, prepareIntent, admissionDurableJson,
  admitDurableJson, commitIntent, admitResponseJson, prepareResponseObservation,
  responseDurableJson, commitTransition} from '../coordinator-core/index.mjs';
import {admitEnvironment, prepare, compileTasks, taskExecutionShape, taskKeys,
  issueAllowedTaskRun, issueTaskRunDefinition, privateRunDefinition,
  prepareRetainedTaskInputEdge, retainedTaskInputEdgeFacts, taskInputBinding,
  prepareTaskRequest, issueTaskDispatch, prepareRetainedInputProducer,
  retainedInputProducerAvailable, retainedInputProducerFacts,
  prepareRetainedInputIntent, admitRetainedInputIntent, retainedInputIntentFacts,
  retainedInputPlanEnvelope, admitRetainedInputPlan, validateRetainedInputPlan,
  retainedInputPlanFacts, retainedInputTransferEnvelope, admitRetainedInputResult,
  retainedInputResultFacts,
  prepareRetainedTaskInput, admitRetainedTaskInput, validateRetainedTaskInput,
  retainedTaskInputFacts, issueRetainedTaskDispatch}
  from './index.mjs';

// The ordinary two-stage Program has one checked Source producer and one
// dependent Compute consumer. Expected physical schema is authored separately.
const document = JSON.stringify({version: 'actql/0.1',
  id: 'retained-source-compute', stages: [{id: 'acquire',
    inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{filter: 'id > 0', as: 'filtered'},
      {select: ['id'], as: 'captured'}],
    results: {rows: {from: 'captured', fields: ['id']}}},
  {id: 'compute', inputs: {input: {result: {stage: 'acquire', result: 'rows'}}},
    steps: [{filter: 'id > 2', as: 'filtered'},
      {select: ['id'], as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['id']}}}],
  results: {answer: {from: {stage: 'compute', result: 'rows'}}}});
const cid = fill => `sha256:${fill.repeat(64)}`;
const fixture = await residentSourceEnvironment(fileURLToPath(new URL('../../', import.meta.url)));
const environment = admitEnvironment(fixture.wire, fixture.cid, {rela: true});

function run(body = document) {
  const prepared = prepare(body, 'json', environment);
  const compilation = compileTasks(prepared);
  const allowed = issueAllowedTaskRun(prepared, compilation, {
    executionContextCid: cid('a'), hostPolicyCid: cid('b'),
    expiresAt: '2099-01-01T00:00:00.000Z',
  });
  const definition = issueTaskRunDefinition(prepared, compilation,
    allowed.admission, 'retained-scope', 'original-run',
    '2026-10-06T00:00:00.000Z', '2099-01-01T00:00:00.000Z');
  const edge = (task = 1, input = 0, selected = definition) =>
    prepareRetainedTaskInputEdge(prepared, compilation,
      allowed.admission, selected, task, input);
  return {prepared, compilation, admission: allowed.admission, definition, edge};
}

test('retained edge comes from the original two checked tasks and keeps both schema domains', () => {
  const original = run();
  assert.deepEqual(taskExecutionShape(original.prepared, original.compilation),
    {taskCount: 2, acquisitionCount: 1});
  const keys = taskKeys(original.prepared, original.compilation);
  const edge = original.edge();
  const facts = retainedTaskInputEdgeFacts(edge);
  assert.equal(facts.runDefinitionCid, privateRunDefinition(original.definition).cid);
  assert.equal(facts.producerTaskKey, keys[0]);
  assert.equal(facts.consumerTaskKey, keys[1]);
  assert.notEqual(facts.producerLogicalCid, facts.consumerLogicalCid);
  assert.equal(facts.consumerInputPort, 'input');
  assert.equal(facts.carrierContractCid,
    'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c');
  const schema = '{"id":{"nullable":false,"type":"number"}}';
  assert.equal(facts.physicalSchemaCid,
    `sha256:${createHash('sha256').update(schema).digest('hex')}`);
  assert.notEqual(facts.physicalSchemaCid, facts.carrierContractCid);
  assert(Object.isFrozen(edge));
  assert(Object.isFrozen(facts));
  assert.deepEqual(retainedTaskInputEdgeFacts(original.edge()), facts);
  // Topology is not physical custody: the old consumer binding issuer must
  // still refuse until producer completion and Transfer have been admitted.
  assert.throws(() => taskInputBinding(original.prepared, 1),
    {code: 'RunHostTaskBindingRejected'});
});

test('retained edge rejects absent edges, foreign Run owners and forged handles', () => {
  const original = run();
  for (const [task, input] of [[0, 0], [1, 1], [2, 0]]) {
    assert.throws(() => original.edge(task, input),
      {code: 'RunHostRetainedInputEdgeRejected'});
  }
  for (const [task, input] of [[-1, 0], [1, -1], [1.5, 0], [1, Infinity], [2 ** 31, 0]]) {
    assert.throws(() => original.edge(task, input),
      {message: 'InvalidRunHostRetainedInputEdge'});
  }
  const foreign = run(document.replace('id > 2', 'id > 1'));
  assert.throws(() => original.edge(1, 0, foreign.definition),
    {code: 'RunHostRetainedInputEdgeRejected'});
  assert.throws(() => prepareRetainedTaskInputEdge(foreign.prepared,
    original.compilation, original.admission, original.definition, 1, 0),
  {message: 'ForeignRunHostCompilation'});
  for (const forged of [{kind: 'retained-input-edge'},
    retainedTaskInputEdgeFacts(original.edge()), original.definition]) {
    assert.throws(() => retainedTaskInputEdgeFacts(forged),
      {message: 'ForeignRunHostHandle'});
  }
});

function coordinatorProducerFixture(original, taskAttempt = 1, manifestCid = cid('7')) {
  const authority = cid('c');
  const selection = {taskAttempt, dispatchId: `producer-${taskAttempt}`,
    siteKey: 'site-a', siteGeneration: 1, runtimeBundleCid: cid('a'),
    connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1', obligationsCid: cid('1'),
    budgetCid: cid('2'), evidenceIssuerCapabilityCid: cid('3'), grantCid: cid('4')};
  const issued = issueTaskDispatch(original.prepared, original.compilation,
    original.admission, original.definition,
    prepareTaskRequest(original.prepared, original.compilation, authority,
      'original-request'), 0, selection);
  const request = admitDispatchJson(issued.wire, issued.cid);
  const intent = prepareIntent(createJournal(authority), request);
  let durableRecordWire = admissionDurableJson(intent);
  const record = commitIntent(intent);
  // Independently authored protocol facts exercise admission and current
  // Coordinator custody. They are not Native execution or physical payload
  // evidence, and never substitute for the public integration acceptance.
  const identified = body => {
    const wire = canonicalText(body);
    return {wire, cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`};
  };
  const holding = identified({dispatch_request_cid: issued.cid,
    material_generation: 'producer-material', retained_bytes: '8',
    site_generation: 1, site_key: 'site-a', version: 'actql-remote-output-holding/0.1'});
  const measurement = identified({admission_nodes: 0, admission_text_bytes: 0,
    admission_work: 0, columns: [{admitted_depth: 10, bytes: 1,
      max_value_bytes: 1, nodes: 1, null_rows: 0, rows: 1}], row_count: 1,
    version: 'actql-remote-managed-output-measurement/0.1'});
  const subject = identified({dispatch_request_cid: issued.cid,
    holding_evidence_cid: holding.cid, logical_view_cid: cid('5'),
    managed_profile_cid: cid('6'), material_generation: 'producer-material',
    measurement_evidence_cid: measurement.cid, physical_manifest_cid: manifestCid,
    representation_codec_cid: cid('8'), result_schema_cid:
      'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513',
    retained_bytes: '8', row_count: 1, version: 'actql-remote-managed-output-subject/0.1'});
  const evidence = identified({connector_registration: 'local', connector_revision: 'local/1',
    dispatch_request_cid: issued.cid, evidence_kind: 'actql.remote.managed-output/0.1',
    evidence_subject_cid: subject.cid, holding_evidence_cid: holding.cid,
    issuer_capability_cid: selection.evidenceIssuerCapabilityCid,
    material_generation: 'producer-material', obligations_cid: selection.obligationsCid,
    runtime_bundle_cid: selection.runtimeBundleCid, site_generation: 1,
    site_key: 'site-a', strategy_revision: 'strategy/1',
    version: 'actql-remote-execution-evidence/0.1'});
  const observe = (state, revision, includeProof = true) => {
    const response = admitResponseJson(JSON.stringify({
      version: includeProof ? 'actql-remote-dispatch-status/0.1' :
        'actql-remote-dispatch-response/0.1', dispatch_request_cid: issued.cid,
      revision, state, ...(includeProof ? {evidence, subject, measurement} : {}),
    }), request, includeProof);
    const transition = prepareResponseObservation(record, response);
    const next = responseDurableJson(admitDurableJson(durableRecordWire),
      transition, response);
    admitDurableJson(next);
    durableRecordWire = next;
    commitTransition(transition);
  };
  return {current: () => ({authority, durableRecordWire}), observe,
    issued, evidence, subject, selection, authority};
}

test('retained producer uses exact durable Coordinator evidence and rechecks current cleanup', () => {
  const original = run();
  const edge = original.edge();
  const fixture = coordinatorProducerFixture(original);
  assert.throws(() => prepareRetainedInputProducer(edge, fixture.current),
    {code: 'RunHostRetainedProducerRejected'});
  fixture.observe([3, 2, 0, 1, 0], 5, false);
  assert.throws(() => prepareRetainedInputProducer(edge, fixture.current),
    {code: 'RunHostRetainedProducerRejected'});
  fixture.observe([3, 2, 0, 1, 0], 6);
  const producer = prepareRetainedInputProducer(edge, fixture.current);
  assert.equal(retainedInputProducerAvailable(producer), true);
  assert.deepEqual(retainedInputProducerFacts(producer), {
    dispatch: fixture.issued, evidence: fixture.evidence, subject: fixture.subject,
  });
  fixture.observe([3, 2, 1, 1, 0], 7);
  assert.equal(retainedInputProducerAvailable(producer), false);
  fixture.observe([3, 2, 2, 0, 0], 8);
  assert.equal(retainedInputProducerAvailable(producer), false);
  assert.deepEqual(retainedInputProducerFacts(producer).dispatch, fixture.issued);
});

test('retained producer rejects replaced attempts, foreign authority and missing current records', () => {
  const original = run();
  const fixture = coordinatorProducerFixture(original);
  fixture.observe([3, 2, 0, 1, 0], 5);
  let current = fixture.current();
  const producer = prepareRetainedInputProducer(original.edge(), () => current);
  assert.equal(retainedInputProducerAvailable(producer), true);
  const replacement = coordinatorProducerFixture(original, 2);
  replacement.observe([3, 2, 0, 1, 0], 5);
  let reads = 0;
  assert.throws(() => prepareRetainedInputProducer(original.edge(), () =>
    ++reads === 1 ? fixture.current() : replacement.current()),
  {code: 'RunHostRetainedProducerRejected'});
  assert.equal(reads, 2);
  current = replacement.current();
  assert.equal(retainedInputProducerAvailable(producer), false);
  current = {...fixture.current(), authority: cid('f')};
  assert.equal(retainedInputProducerAvailable(producer), false);
  for (const durableRecordWire of ['', '{}', ' '.repeat(1048577)]) {
    current = {...fixture.current(), durableRecordWire};
    assert.equal(retainedInputProducerAvailable(producer), false);
  }
  current = fixture.current();
  assert.equal(retainedInputProducerAvailable(producer), true);
  const foreign = coordinatorProducerFixture(run(document.replace('id > 2', 'id > 1')));
  foreign.observe([3, 2, 0, 1, 0], 5);
  current = foreign.current();
  assert.equal(retainedInputProducerAvailable(producer), false);
  assert.throws(() => prepareRetainedInputProducer(original.edge(), () => current),
    {code: 'RunHostRetainedProducerRejected'});
  for (const forged of [{kind: 'retained-input-producer'},
    retainedInputProducerFacts(producer), original.edge()]) {
    assert.throws(() => retainedInputProducerAvailable(forged),
      {message: 'ForeignRunHostHandle'});
    assert.throws(() => retainedInputProducerFacts(forged),
      {message: 'ForeignRunHostHandle'});
  }
  for (const read of [null, {}, () => undefined, () => ({authority: 'a'}),
    () => ({...fixture.current(), extra: 'ignored'}),
    () => ({authority: 1, durableRecordWire: ''})]) {
    assert.throws(() => prepareRetainedInputProducer(original.edge(), read),
      {message: 'InvalidRunHostRetainedProducerCurrent'});
  }
});


const identified = body => {
  const wire = canonicalText(body);
  return {wire, cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`};
};
const inputLimits = {maxChunks: 1, maxManifestBytes: 4096,
  maxReferencedBytes: 8n, maxBindingBytes: 32768};

function retainedTransferFixture(original) {
  const manifest = identified({chunks: [{byte_length: 8, cid: cid('a'), row_count: 1}],
    codec_contract_cid: cid('8'), row_count: 1,
    schema_contract_cid: retainedTaskInputEdgeFacts(original.edge()).physicalSchemaCid,
    version: 'actql-managed-physical-manifest/0.1', view_contract_cid: cid('5')});
  const completed = coordinatorProducerFixture(original, 1, manifest.cid);
  completed.observe([3, 2, 0, 1, 0], 5);
  const producer = prepareRetainedInputProducer(original.edge(), completed.current);
  const requestWire = identified({codec_contract_cid: cid('8'),
    coordinator_authority: completed.authority, destination_grant_cid: cid('b'),
    destination_site_generation: 1, destination_site_key: 'site-a',
    expires_unix_ms: '2000000000000', max_bytes: '8', physical_manifest_cid: manifest.cid,
    route: 'direct', route_capability_cid: cid('c'),
    schema_contract_cid: JSON.parse(manifest.wire).schema_contract_cid,
    source_grant_cid: cid('d'), source_material_generation: 'producer-material',
    source_site_generation: 1, source_site_key: 'site-a', transfer_attempt: 'transfer-1',
    version: 'actql-remote-transfer-request/0.1', view_contract_cid: cid('5')});
  const request = transfer.admitEnvelopeJson(canonicalText({manifest: manifest.wire,
    request: requestWire.wire}), requestWire.cid, manifest.cid, inputLimits);
  const record = transfer.openRecord(request);
  let durable = transfer.recordDurableJson(record);
  const persist = transition => {
    const next = transfer.transitionDurableJson(transition);
    transfer.admitDurableJson(next, inputLimits);
    durable = next;
    transfer.commitTransition(transition);
  };
  // These are protocol Owner tests only. Independent receipt/manifest values
  // do not claim Native bytes, physical holding or execution acceptance.
  const receipt = identified({destination_grant_cid: cid('b'),
    destination_material_generation: 'receiver-material', destination_site_generation: 1,
    destination_site_key: 'site-a', physical_manifest_cid: manifest.cid,
    request_cid: requestWire.cid, version: 'actql-remote-transfer-destination-receipt/0.1'});
  let siteCurrent = true, authorized = true, now = 1900000000000n;
  const current = {
    readTransfer: () => durable,
    siteBindingCurrent: (key, generation, bundle) => siteCurrent && key === 'site-a' &&
      generation === 1 && bundle === completed.selection.runtimeBundleCid,
    authority: () => completed.authority,
    nowUnixMs: () => now,
    authorized: (producerCid, wire) => authorized && producerCid === completed.issued.cid &&
      wire === requestWire.wire,
  };
  return {completed, producer, record, requestWire, manifest, receipt, current, persist,
    commit: () => {
      persist(transfer.prepareStart(record));
      persist(transfer.prepareSourceSettled(record, true, false));
      persist(transfer.prepareDestinationCommit(record));
    },
    siteCurrent: value => {siteCurrent = value;}, authorized: value => {authorized = value;},
    clock: value => {now = value;}, wire: () => durable};
}

// These protocol bodies have ASCII keys and primitive values. Sort keys while
// preserving every string byte; configuration NFC canonicalization is not the
// retained-input wire contract. This independent helper is test input only.
const identifyRetainedWire = body => {
  const wire = JSON.stringify(Object.fromEntries(Object.entries(body)
    .sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)));
  return {wire, cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`};
};
const transferPolicy = {destinationGrantCid: cid('b'), routeCapabilityCid: cid('c'),
  sourceGrantCid: cid('d'), transferAttempt: 'transfer-1',
  transferExpiresUnixMs: 2000000000000n, transferMaxBytes: 8n};
const planLimits = {maxChunks: 1, maxManifestBytes: 4096, maxReferencedBytes: 8n};
function retainedPlanFixture(original) {
  const fixture = retainedTransferFixture(original);
  const intent = prepareRetainedInputIntent(fixture.producer, transferPolicy);
  const savedIntent = retainedInputIntentFacts(intent);
  // Independently authored Site protocol response, not Native execution or
  // physical bytes. The actual Native planning entry has separate acceptance.
  const reply = identifyRetainedWire({dispatch_request_cid: fixture.completed.issued.cid,
    evidence_cid: fixture.completed.evidence.cid, evidence_json: fixture.completed.evidence.wire,
    intent_cid: savedIntent.cid, physical_manifest_cid: fixture.manifest.cid,
    physical_manifest_json: fixture.manifest.wire, subject_cid: fixture.completed.subject.cid,
    subject_json: fixture.completed.subject.wire, transfer_request_cid: fixture.requestWire.cid,
    transfer_request_json: fixture.requestWire.wire, version: 'actql-remote-retained-input-plan/0.1'});
  const {readTransfer: _unused, ...current} = fixture.current;
  return {...fixture, intent, savedIntent, reply, planCurrent: current};
}

test('retained planning restores original intent and checks the current producer before poll', () => {
  const original = run();
  const fixture = retainedPlanFixture(original);
  const envelope = retainedInputPlanEnvelope(fixture.intent);
  const body = JSON.parse(envelope);
  assert.equal(body.version, 'actql-remote-poll-retained-input-plan/0.1');
  assert.equal(body.request_json, fixture.completed.issued.wire);
  assert.equal(body.dispatch_request_cid, fixture.completed.issued.cid);
  assert.equal(body.intent_json, fixture.savedIntent.wire);
  assert.equal(body.intent_cid, fixture.savedIntent.cid);
  // Reconstruction uses a fresh admitted checked edge and Coordinator port.
  const rebuilt = run();
  const producer = prepareRetainedInputProducer(rebuilt.edge(), fixture.completed.current);
  const restored = admitRetainedInputIntent(producer, fixture.savedIntent);
  assert.deepEqual(retainedInputIntentFacts(restored), fixture.savedIntent);
  assert.equal(retainedInputPlanEnvelope(restored), envelope);
  for (const change of [{consumer_task_key: 'another-consumer'},
    {producer_output_port: 'other-output'}, {producer_subject_cid: cid('f')},
    {dispatch_request_cid: cid('f')}]) {
    const wrong = identifyRetainedWire({...JSON.parse(fixture.savedIntent.wire), ...change});
    assert.throws(() => admitRetainedInputIntent(producer, wrong),
      {code: 'RunHostRetainedInputIntentRejected'});
  }
  fixture.completed.observe([3, 2, 1, 1, 0], 6);
  assert.throws(() => retainedInputPlanEnvelope(restored),
    {code: 'RunHostRetainedInputIntentRejected'});
  assert.throws(() => admitRetainedInputIntent(producer, fixture.savedIntent),
    {code: 'RunHostRetainedInputIntentRejected'});
  assert.deepEqual(retainedInputIntentFacts(restored), fixture.savedIntent);
});

test('retained intent keeps raw Unicode and line endings distinct across restoration', () => {
  const fixture = retainedTransferFixture(run());
  const raw = prepareRetainedInputIntent(fixture.producer,
    {...transferPolicy, transferAttempt: 'e\u0301\r\n'});
  const composed = prepareRetainedInputIntent(fixture.producer,
    {...transferPolicy, transferAttempt: 'é\n'});
  const saved = retainedInputIntentFacts(raw);
  assert.equal(JSON.parse(saved.wire).transfer_attempt, 'e\u0301\r\n');
  assert.notEqual(saved.cid, retainedInputIntentFacts(composed).cid);
  assert.deepEqual(retainedInputIntentFacts(admitRetainedInputIntent(fixture.producer, saved)), saved);
  assert.equal(JSON.parse(retainedInputPlanEnvelope(raw)).intent_json, saved.wire);
});

test('retained Native plan is checked before commit and reads live grants, generation and lifetime', () => {
  const fixture = retainedPlanFixture(run());
  const before = fixture.wire();
  const plan = admitRetainedInputPlan(fixture.intent, fixture.reply, fixture.planCurrent, planLimits);
  validateRetainedInputPlan(plan);
  assert.deepEqual(retainedInputPlanFacts(plan), {...fixture.reply,
    transfer: fixture.requestWire, manifest: fixture.manifest});
  assert.equal(fixture.wire(), before); // no fabricated receiver commit
  for (const change of [{dispatch_request_cid: cid('f')}, {intent_cid: cid('f')},
    {transfer_request_cid: cid('f')}, {physical_manifest_cid: cid('f')}]) {
    const wrong = identifyRetainedWire({...JSON.parse(fixture.reply.wire), ...change});
    assert.throws(() => admitRetainedInputPlan(fixture.intent, wrong, fixture.planCurrent, planLimits),
      {code: 'RunHostRetainedInputPlanRejected'});
  }
  for (const [set, value] of [[fixture.siteCurrent, false], [fixture.authorized, false],
    [fixture.clock, 2000000000000n]]) {
    set(value);
    let sent = 0;
    assert.throws(() => {validateRetainedInputPlan(plan); sent++;},
      {code: 'RunHostRetainedInputPlanRejected'});
    assert.equal(sent, 0);
    assert.throws(() => admitRetainedInputPlan(fixture.intent, fixture.reply,
      fixture.planCurrent, planLimits), {code: 'RunHostRetainedInputPlanRejected'});
    fixture.siteCurrent(true); fixture.authorized(true); fixture.clock(1900000000000n);
  }
  assert.throws(() => admitRetainedInputPlan(fixture.intent, fixture.reply,
    {...fixture.planCurrent, authority: () => cid('f')}, planLimits),
  {code: 'RunHostRetainedInputPlanRejected'});
  // Port replacement is not an authorization refresh: installed functions
  // continue reading the original live Owner, not the new object properties.
  fixture.planCurrent.authorized = () => true;
  fixture.authorized(false);
  assert.throws(() => validateRetainedInputPlan(plan), {code: 'RunHostRetainedInputPlanRejected'});
  assert.deepEqual(retainedInputPlanFacts(plan).transfer, fixture.requestWire);
  assert.equal(fixture.wire(), before);
});

test('retained plan refuses producer cleanup observed during trusted authorization', () => {
  const fixture = retainedPlanFixture(run());
  let checked = 0, sent = 0;
  assert.throws(() => {
    admitRetainedInputPlan(fixture.intent, fixture.reply,
      {...fixture.planCurrent, authorized: (...args) => {
        checked++;
        fixture.completed.observe([3, 2, 1, 1, 0], 6);
        return fixture.planCurrent.authorized(...args);
      }}, planLimits);
    sent++;
  }, {code: 'RunHostRetainedInputPlanRejected'});
  assert.equal(checked, 1);
  assert.equal(sent, 0);
});

test('retained planning refuses forged handles and invalid Int64 or current ports', () => {
  const fixture = retainedPlanFixture(run());
  for (const bad of [0n, -1n, 1, 9223372036854775808n]) {
    for (const key of ['transferExpiresUnixMs', 'transferMaxBytes']) {
      assert.throws(() => prepareRetainedInputIntent(fixture.producer,
        {...transferPolicy, [key]: bad}), {message: 'InvalidRunHostRetainedInputPolicy'});
    }
  }
  for (const forged of [{kind: 'retained-input-intent'}, fixture.savedIntent, fixture.producer]) {
    assert.throws(() => retainedInputPlanEnvelope(forged), {message: 'ForeignRunHostHandle'});
    assert.throws(() => retainedInputIntentFacts(forged), {message: 'ForeignRunHostHandle'});
  }
  const plan = admitRetainedInputPlan(fixture.intent, fixture.reply, fixture.planCurrent, planLimits);
  for (const forged of [fixture.intent, fixture.reply, retainedInputPlanFacts(plan)]) {
    assert.throws(() => validateRetainedInputPlan(forged), {message: 'ForeignRunHostHandle'});
  }
  for (const current of [{}, {...fixture.planCurrent, authorized: true},
    {...fixture.planCurrent, readTransfer: () => fixture.wire()}]) {
    assert.throws(() => admitRetainedInputPlan(fixture.intent, fixture.reply, current, planLimits),
      {message: 'InvalidRunHostRetainedPlanCurrent'});
  }
  for (const limits of [{...planLimits, maxChunks: 0}, {...planLimits, maxReferencedBytes: 8},
    {...planLimits, maxReferencedBytes: 9223372036854775808n}]) {
    assert.throws(() => admitRetainedInputPlan(fixture.intent, fixture.reply, fixture.planCurrent, limits),
      {message: 'InvalidRunHostRetainedPlanLimits'});
  }
  for (const current of [{...fixture.planCurrent, nowUnixMs: () => 1},
    {...fixture.planCurrent, authority: () => null},
    {...fixture.planCurrent, authorized: () => 'yes'}]) {
    assert.throws(() => admitRetainedInputPlan(fixture.intent, fixture.reply, current, planLimits), TypeError);
  }
});

const issueConsumer = (original, fixture, input, selection = fixture.completed.selection) =>
  issueRetainedTaskDispatch(original.prepared, original.compilation, original.admission,
    original.definition, prepareTaskRequest(original.prepared, original.compilation,
      fixture.completed.authority, 'original-request'), 1,
    {...selection, dispatchId: 'consumer-1'}, input);

test('retained consumer dispatch joins exact committed destination and restores current custody', () => {
  const original = run();
  const fixture = retainedTransferFixture(original);
  const prepareInput = (receipt = fixture.receipt, current = fixture.current) =>
    prepareRetainedTaskInput(fixture.producer, receipt, 'receiver-use', current, inputLimits);
  assert.throws(() => prepareInput(), {code: 'RunHostRetainedTaskInputRejected'});
  fixture.commit();
  for (const changes of [{destination_material_generation: 'producer-material'},
    {destination_site_generation: 2}, {request_cid: cid('f')}]) {
    assert.throws(() => prepareInput(identified({...JSON.parse(fixture.receipt.wire), ...changes})),
      {code: 'RunHostRetainedTaskInputRejected'});
  }
  assert.throws(() => prepareInput(fixture.receipt,
    {...fixture.current, authority: () => cid('f')}),
  {code: 'RunHostRetainedTaskInputRejected'});
  const input = prepareInput();
  validateRetainedTaskInput(input);
  const saved = retainedTaskInputFacts(input);
  const dispatch = issueConsumer(original, fixture, input);
  const body = JSON.parse(dispatch.wire);
  assert.equal(body.run_definition_cid, privateRunDefinition(original.definition).cid);
  assert.equal(body.task_key, taskKeys(original.prepared, original.compilation)[1]);
  assert.notEqual(dispatch.cid, fixture.completed.issued.cid);
  // New restored ports read the re-admitted existing record: no new Transfer,
  // producer execution, borrow or reservation is created by binding admission.
  const recovered = transfer.restoreDurable(transfer.admitDurableJson(fixture.wire(), inputLimits));
  const restored = admitRetainedTaskInput(fixture.producer, saved, fixture.receipt,
    'receiver-use', {...fixture.current, readTransfer: () => transfer.recordDurableJson(recovered)},
    inputLimits);
  assert.deepEqual(retainedTaskInputFacts(restored), saved);
  assert.deepEqual(issueConsumer(original, fixture, restored), dispatch);
  assert.throws(() => admitRetainedTaskInput(fixture.producer,
    {...saved, wire: saved.wire.replace('receiver-use', 'foreign-use')}, fixture.receipt,
    'receiver-use', fixture.current, inputLimits), {code: 'RunHostRetainedTaskInputRejected'});
  for (const [set, value] of [[fixture.siteCurrent, false], [fixture.authorized, false],
    [fixture.clock, 2000000000000n]]) {
    set(value);
    assert.throws(() => validateRetainedTaskInput(input), {code: 'RunHostRetainedTaskInputRejected'});
    assert.throws(() => issueConsumer(original, fixture, input),
      {code: 'RunHostRetainedTaskDispatchRejected'});
    fixture.siteCurrent(true); fixture.authorized(true); fixture.clock(1900000000000n);
  }
  for (const selected of [{...fixture.completed.selection, siteGeneration: 2},
    {...fixture.completed.selection, siteKey: 'other-site'}]) {
    assert.throws(() => issueConsumer(original, fixture, input, selected),
      {code: 'RunHostRetainedTaskDispatchRejected'});
  }
  const foreign = run(document.replace('id > 2', 'id > 1'));
  assert.throws(() => issueConsumer(foreign, fixture, input),
    {code: 'RunHostRetainedTaskDispatchRejected'});
  fixture.completed.observe([3, 2, 1, 1, 0], 6);
  assert.throws(() => issueConsumer(original, fixture, input),
    {code: 'RunHostRetainedTaskDispatchRejected'});
  assert.deepEqual(retainedTaskInputFacts(input), saved);
});

test('retained input refuses disappearing Transfer custody across admission and dispatch', () => {
  const original = run();
  const fixture = retainedTransferFixture(original);
  fixture.commit();
  let reads = 0;
  assert.throws(() => prepareRetainedTaskInput(fixture.producer, fixture.receipt,
    'receiver-use', {...fixture.current, readTransfer: () =>
      ++reads === 1 ? fixture.wire() : '{}'}, inputLimits),
  {code: 'RunHostRetainedTaskInputRejected'});
  assert.equal(reads, 2);
  const input = prepareRetainedTaskInput(fixture.producer, fixture.receipt,
    'receiver-use', fixture.current, inputLimits);
  let currentWire = fixture.wire();
  let stopDuringDispatch = false;
  const inputWithPort = prepareRetainedTaskInput(fixture.producer, fixture.receipt,
    'receiver-use', {...fixture.current, readTransfer: () => currentWire,
      authorized: (...args) => {
        const allowed = fixture.current.authorized(...args);
        if (stopDuringDispatch) currentWire = '{}';
        return allowed;
      }}, inputLimits);
  stopDuringDispatch = true;
  assert.throws(() => issueConsumer(original, fixture, inputWithPort),
    {code: 'RunHostRetainedTaskDispatchRejected'});
  for (const forged of [fixture.producer, retainedTaskInputFacts(input), {}]) {
    assert.throws(() => validateRetainedTaskInput(forged), {message: 'ForeignRunHostHandle'});
  }
  // A registered current port returning a Promise cannot silently authorize.
  assert.throws(() => prepareRetainedTaskInput(fixture.producer, fixture.receipt,
    'receiver-use', {...fixture.current, authorized: () => Promise.resolve(true)}, inputLimits),
  {message: 'InvalidRunHostRetainedAuthorization'});
});


// Independent protocol response only: actual receiver bytes and cleanup have
// separate Native evidence. This fixture cannot establish current custody.
function retainedResultFixture(fixture, changes = {}) {
  const body = {destination_receipt_cid: fixture.receipt.cid,
    destination_receipt_json: fixture.receipt.wire,
    dispatch_request_cid: fixture.completed.issued.cid,
    intent_cid: fixture.savedIntent.cid, plan_cid: fixture.reply.cid,
    transfer_reply_json: identifyRetainedWire({requestCid: fixture.requestWire.cid,
      state: [3, 2, 0, 1, 0, 1, 1, 1, 1]}).wire,
    transfer_request_cid: fixture.requestWire.cid,
    version: 'actql-remote-retained-input-result/0.1', ...changes};
  return identifyRetainedWire(body);
}

test('retained transfer envelope joins original plan and refuses revoked delivery before send', () => {
  const fixture = retainedPlanFixture(run());
  const plan = admitRetainedInputPlan(fixture.intent, fixture.reply, fixture.planCurrent, planLimits);
  const before = fixture.wire();
  const body = JSON.parse(retainedInputTransferEnvelope(plan));
  assert.deepEqual(body, {dispatch_request_cid: fixture.completed.issued.cid,
    intent_cid: fixture.savedIntent.cid, intent_json: fixture.savedIntent.wire,
    plan_cid: fixture.reply.cid, plan_json: fixture.reply.wire,
    request_json: fixture.completed.issued.wire,
    version: 'actql-remote-poll-retained-input-transfer/0.1'});
  assert.equal(fixture.wire(), before);
  let sent = 0;
  fixture.authorized(false);
  assert.throws(() => {retainedInputTransferEnvelope(plan); sent++;},
    {code: 'RunHostRetainedInputPlanRejected'});
  assert.equal(sent, 0);
  fixture.authorized(true);
  fixture.completed.observe([3, 2, 1, 1, 0], 6);
  assert.throws(() => {retainedInputTransferEnvelope(plan); sent++;},
    {code: 'RunHostRetainedInputPlanRejected'});
  assert.equal(sent, 0);
});

test('retained result restores exact immutable receipt without authorizing current input', () => {
  const fixture = retainedPlanFixture(run());
  const plan = admitRetainedInputPlan(fixture.intent, fixture.reply, fixture.planCurrent, planLimits);
  const saved = retainedResultFixture(fixture);
  const before = fixture.wire();
  const result = admitRetainedInputResult(plan, saved);
  const facts = retainedInputResultFacts(result);
  assert.equal(facts.cid, saved.cid);
  assert.equal(facts.wire, saved.wire);
  assert.equal(facts.planCid, fixture.reply.cid);
  assert.deepEqual(facts.receipt, fixture.receipt);
  assert.equal(facts.transferReply.requestCid, fixture.requestWire.cid);
  assert.equal(fixture.wire(), before);
  assert(Object.isFrozen(result));
  assert(Object.isFrozen(facts));
  assert(Object.isFrozen(facts.transferReply));
  assert(Object.isFrozen(facts.receipt));
  // A committed historical report does not replace the current Transfer Owner.
  assert.throws(() => prepareRetainedTaskInput(fixture.producer, facts.receipt,
    'receiver-use', fixture.current, inputLimits), {code: 'RunHostRetainedTaskInputRejected'});
  fixture.authorized(false);
  assert.deepEqual(retainedInputResultFacts(admitRetainedInputResult(plan, saved)), facts);
  assert.throws(() => retainedInputTransferEnvelope(plan), {code: 'RunHostRetainedInputPlanRejected'});
  assert.throws(() => validateRetainedTaskInput(result), {message: 'ForeignRunHostHandle'});
  assert.equal(fixture.wire(), before);
});

test('retained result refuses uncommitted and substituted reports and forged handles', () => {
  const fixture = retainedPlanFixture(run());
  const plan = admitRetainedInputPlan(fixture.intent, fixture.reply, fixture.planCurrent, planLimits);
  const saved = retainedResultFixture(fixture);
  for (const changes of [{plan_cid: cid('f')}, {intent_cid: cid('f')},
    {dispatch_request_cid: cid('f')}, {transfer_request_cid: cid('f')},
    {destination_receipt_cid: cid('f')},
    {transfer_reply_json: identifyRetainedWire({requestCid: fixture.requestWire.cid,
      state: [0, 0, 0, 0, 0, 0, 0, 1, 0]}).wire}]) {
    assert.throws(() => admitRetainedInputResult(plan, retainedResultFixture(fixture, changes)),
      {code: 'RunHostRetainedInputResultRejected'});
  }
  assert.throws(() => admitRetainedInputResult(plan, {...saved, wire: saved.wire + ' '}),
    {code: 'RunHostRetainedInputResultRejected'});
  for (const malformed of [{}, {...saved, extra: true}, {...saved, cid: 1}]) {
    assert.throws(() => admitRetainedInputResult(plan, malformed),
      {message: 'InvalidRunHostRetainedInputResultWire'});
  }
  for (const forged of [fixture.intent, fixture.reply, retainedInputPlanFacts(plan)]) {
    assert.throws(() => retainedInputTransferEnvelope(forged), {message: 'ForeignRunHostHandle'});
  }
  for (const forged of [plan, saved, retainedInputResultFacts(admitRetainedInputResult(plan, saved))]) {
    assert.throws(() => retainedInputResultFacts(forged), {message: 'ForeignRunHostHandle'});
  }
});
