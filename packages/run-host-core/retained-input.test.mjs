import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {readFileSync} from 'node:fs';
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
  prepareSubmittedIntent, prepareSourceProgram, sourceProgramMaterialInput, requestFields, admitRequestFields, prepareRequest,
  retainedInputProducerAvailable, retainedInputProducerFacts,
  prepareRetainedInputIntent, admitRetainedInputIntent, retainedInputIntentFacts,
  retainedInputPlanEnvelope, admitRetainedInputPlan, validateRetainedInputPlan,
  retainedInputPlanFacts, retainedInputTransferEnvelope, admitRetainedInputResult,
  retainedInputResultFacts, prepareRetainedInputCurrentQuery, retainedInputCurrentEnvelope,
  admitRetainedInputCurrentReply, retainedInputCurrentReplyFacts,
  prepareRetainedTaskInput, admitRetainedTaskInput, validateRetainedTaskInput,
  retainedTaskInputFacts, issueRetainedTaskDispatch, inspectTaskProgress, projectTaskSiteRun, projectSiteRun,
  prepareTaskPhysicalStart, prepareEffect, compileEffect, issueAllowedEffectRun,
  issueEffectRunDefinition, prepareEffectRequest, prepareEffectRetainedTaskInputEdge,
  issueEffectSourceDispatch, issueEffectRetainedTaskDispatch, inspectEffectTaskProgress,
  prepareEffectTaskPhysicalStart}
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

function run(body = document, sourcePrepared) {
  const prepared = sourcePrepared ?? prepare(body, 'json', environment);
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

function coordinatorProducerFixture(original, taskAttempt = 1, manifestCid = cid('7'), issuedOverride) {
  const authority = cid('c');
  const selection = {taskAttempt, dispatchId: `producer-${taskAttempt}`,
    siteKey: 'site-a', siteGeneration: 1, runtimeBundleCid: cid('a'),
    connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1', obligationsCid: cid('1'),
    budgetCid: cid('2'), evidenceIssuerCapabilityCid: cid('3'), grantCid: cid('4')};
  const issued = issuedOverride ?? original.issueSourceDispatch?.(selection) ?? issueTaskDispatch(original.prepared, original.compilation,
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

test('checked remote task progress separates producer completion from Run and cleanup completion', () => {
  const original = run();
  const fixture = retainedTransferFixture(original);
  const progress = (...records) => inspectTaskProgress(original.prepared, original.compilation,
    original.admission, original.definition, fixture.completed.authority,
    records.map(value => value.current().durableRecordWire));
  const empty = progress();
  assert.equal(empty.nextTask, 0);
  assert.equal(empty.executionComplete, false);
  assert.equal(empty.cleanupComplete, false);
  assert.deepEqual(empty.resultTasks, [1]);
  const producer = progress(fixture.completed);
  assert.equal(producer.nextTask, 1);
  assert.equal(producer.executionComplete, false);
  assert.equal(producer.cleanupComplete, false);
  assert.deepEqual(producer.tasks.map(value => value.execution), ['settled', 'unobserved']);
  assert.equal(producer.tasks[0].dispatchCid, fixture.completed.issued.cid);
  fixture.commit();
  const input = prepareRetainedTaskInput(fixture.producer, fixture.receipt,
    'receiver-use', fixture.current, inputLimits);
  const consumer = coordinatorProducerFixture(original, 1, cid('7'), issueConsumer(original, fixture, input));
  assert.equal(progress(fixture.completed, consumer).nextTask, undefined,
    'persisted consumer intent is reconciled, never selected for another start');
  consumer.observe([3, 2, 0, 1, 0], 5, false);
  assert.equal(progress(fixture.completed, consumer).executionComplete, false,
    'physical settlement without admitted output evidence cannot finish the checked graph');
  consumer.observe([3, 2, 0, 1, 0], 6);
  let complete = progress(consumer, fixture.completed);
  assert.equal(complete.executionComplete, true);
  assert.equal(complete.cleanupComplete, false);
  assert.equal(complete.nextTask, undefined);
  assert(Object.isFrozen(complete));
  assert(Object.isFrozen(complete.tasks));
  assert(Object.isFrozen(complete.tasks[0].executionScope));
  for (const record of [fixture.completed, consumer]) {
    record.observe([3, 2, 1, 1, 0], 7);
    assert.equal(progress(fixture.completed, consumer).cleanupComplete, false);
    record.observe([3, 2, 2, 0, 0], 8);
  }
  complete = progress(fixture.completed, consumer);
  assert.equal(complete.executionComplete, true);
  assert.equal(complete.cleanupComplete, true);
  assert.deepEqual(complete.tasks.map(value => value.cleanup), ['released', 'released']);
});

test('checked remote task progress rejects foreign and competing observations and does not restart unknown work', () => {
  const original = run();
  const fixture = coordinatorProducerFixture(original);
  const inspect = (records, authority = fixture.authority) => inspectTaskProgress(
    original.prepared, original.compilation, original.admission, original.definition,
    authority, records);
  const saved = fixture.current().durableRecordWire;
  assert.equal(inspect([saved]).nextTask, undefined, 'unobserved original intent has a reconciliation owner');
  assert.throws(() => inspect([saved], cid('f')), {code: 'RunHostTaskProgressRejected'});
  assert.throws(() => inspect([saved, saved]), {code: 'RunHostTaskProgressRejected'});
  const otherAttempt = coordinatorProducerFixture(original, 2).current().durableRecordWire;
  assert.throws(() => inspect([saved, otherAttempt]), {code: 'RunHostTaskProgressRejected'});
  const foreign = coordinatorProducerFixture(run(document.replace('id > 2', 'id > 1')));
  assert.throws(() => inspect([foreign.current().durableRecordWire]), {code: 'RunHostTaskProgressRejected'});
  fixture.observe([6, 0, 3, 0, 0], 1, false);
  const unknown = inspect([fixture.current().durableRecordWire]);
  assert.equal(unknown.nextTask, undefined);
  assert.equal(unknown.executionComplete, false);
  assert.equal(unknown.cleanupComplete, false);
  assert.equal(unknown.tasks[0].execution, 'unknown');
  assert.equal(unknown.tasks[0].cleanup, 'unknown');
  for (const records of [null, ['invalid'], [saved, 1]]) {
    assert.throws(() => inspect(records));
  }
});

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


const projectionAt = '2026-10-06T01:00:00.000Z';
const projectionFixture = () => {
  const original = run();
  const fixture = retainedTransferFixture(original);
  fixture.commit();
  const input = prepareRetainedTaskInput(fixture.producer, fixture.receipt,
    'receiver-use', fixture.current, inputLimits);
  const consumer = coordinatorProducerFixture(original, 1, cid('7'),
    issueConsumer(original, fixture, input));
  const keys = taskKeys(original.prepared, original.compilation);
  const project = (records, cancellationRequested = false, claims = keys) =>
    projectTaskSiteRun(original.prepared, original.compilation, original.admission,
      original.definition, fixture.completed.authority,
      records.map(value => value.current().durableRecordWire), projectionAt,
      cancellationRequested, claims);
  return {original, fixture, consumer, keys, project};
};

test('checked whole Run projection requires both task proofs and keeps cleanup separate from publication', () => {
  const {fixture, consumer, keys, project} = projectionFixture();
  const producer = project([fixture.completed], false, [keys[0]]);
  assert.equal(producer.publicationReady, false);
  assert.equal(producer.executionComplete, false);
  assert.equal(producer.nextTask, 1);
  assert.equal(JSON.parse(producer.stateWire).status, 'running');
  assert.deepEqual(producer.tasks.map(task => task.nextWork), ['none', 'none']);
  let pending = project([fixture.completed, consumer]);
  assert.equal(pending.execution, 'unknown');
  assert.equal(pending.nextTask, undefined);
  assert.equal(JSON.parse(pending.stateWire).status, 'needs_reconciliation');
  assert.equal(pending.tasks[1].nextWork, 'reconcile');
  consumer.observe([3, 2, 0, 1, 0], 5, false);
  pending = project([fixture.completed, consumer]);
  assert.equal(pending.publicationReady, false);
  assert.equal(pending.tasks[1].nextWork, 'reconcile');
  consumer.observe([3, 2, 0, 1, 0], 6);
  let complete = project([consumer, fixture.completed]);
  assert.equal(complete.execution, 'settled');
  assert.equal(complete.publicationReady, true);
  assert.equal(complete.cleanupComplete, false);
  assert.equal(JSON.parse(complete.stateWire).status, 'running',
    'settled execution is still unpublished until the existing publication Owner commits');
  assert(complete.stateWire.includes('not_published'));
  assert.deepEqual(complete.resultTasks, [1]);
  assert.deepEqual(complete.tasks.map(task => task.nextWork), ['none', 'publication']);
  for (const record of [fixture.completed, consumer]) {
    record.observe([3, 2, 1, 1, 0], 7);
    assert.equal(project([fixture.completed, consumer]).cleanupComplete, false);
    record.observe([3, 2, 2, 0, 0], 8);
  }
  complete = project([fixture.completed, consumer]);
  assert.equal(complete.executionComplete, true);
  assert.equal(complete.cleanupComplete, true);
  assert.deepEqual(complete.tasks.map(task => task.cleanup), ['released', 'released']);
  // Producer: settlement + release-start + release-confirmed. Consumer also
  // admitted a separate proofless settlement before its full evidence.
  assert.deepEqual(complete.tasks.map(task => task.revision), [3, 4]);
  assert(Object.isFrozen(complete));
  assert(Object.isFrozen(complete.tasks));
  assert(Object.isFrozen(complete.tasks[0]));
});

test('checked whole Run projection preserves unknown claims and refuses foreign task ownership', () => {
  const {original, fixture, keys, project} = projectionFixture();
  const preparing = project([], false, []);
  assert.equal(preparing.execution, 'unobserved');
  assert.equal(JSON.parse(preparing.stateWire).status, 'preparing');
  assert.equal(preparing.nextTask, 0);
  assert.equal(preparing.publicationReady, false);
  const absent = project([], false, [keys[0]]);
  assert.equal(absent.execution, 'unknown');
  assert.equal(absent.nextTask, undefined);
  assert.equal(absent.publicationReady, false);
  assert.equal(absent.cleanupComplete, false);
  assert.equal(absent.tasks[0].nextWork, 'reconcile');
  assert.equal(JSON.parse(absent.stateWire).status, 'needs_reconciliation');
  for (const claims of [[keys[0], keys[0]], ['foreign-task'], [keys[1], 'foreign-task']]) {
    assert.throws(() => project([], false, claims), {code: 'RunHostTaskRunProjectionRejected'});
  }
  assert.throws(() => project([], false, [1]), {message: 'InvalidRunHostTaskRunProjection'});
  const foreign = coordinatorProducerFixture(run(document.replace('id > 2', 'id > 1')));
  assert.throws(() => project([foreign]), {code: 'RunHostTaskProgressRejected'});
  assert.throws(() => project([fixture.completed, fixture.completed]),
    {code: 'RunHostTaskProgressRejected'});
  assert.throws(() => projectTaskSiteRun(original.prepared, original.compilation,
    original.admission, original.definition, fixture.completed.authority, [], 'invalid', false, []),
  {code: 'RunHostTaskRunProjectionRejected'});
  assert.throws(() => projectSiteRun(original.prepared, original.compilation, original.admission,
    original.definition, fixture.completed.authority,
    fixture.completed.current().durableRecordWire, projectionAt),
  {code: 'RunHostSiteProjectionRejected'}, 'the old one-task projection guard remains intact');
});

test('checked whole Run projection retains failure and cancellation cleanup without claiming a request is terminal', () => {
  const failed = projectionFixture();
  failed.consumer.observe([4, 0, 0, 0, 0], 1, false);
  const failure = failed.project([failed.fixture.completed, failed.consumer]);
  assert.equal(failure.execution, 'failed');
  assert.equal(JSON.parse(failure.stateWire).status, 'failed');
  assert.equal(failure.nextTask, undefined);
  assert.equal(failure.publicationReady, false);
  assert.equal(failure.cleanupComplete, false);
  assert.deepEqual(failure.tasks.map(task => task.nextWork), ['release', 'cleanup']);
  const cancelled = projectionFixture();
  const requested = cancelled.project([cancelled.fixture.completed], true, [cancelled.keys[0]]);
  assert.notEqual(JSON.parse(requested.stateWire).status, 'cancelled');
  assert.equal(requested.nextTask, undefined);
  assert.equal(requested.publicationReady, false);
  assert.equal(requested.cleanupComplete, false);
  cancelled.consumer.observe([5, 0, 0, 0, 0], 1, false);
  let pending = cancelled.project([cancelled.fixture.completed, cancelled.consumer], true);
  assert.notEqual(pending.execution, 'cancelled');
  assert.equal(pending.cleanupComplete, false);
  assert.deepEqual(pending.tasks.map(task => task.nextWork), ['release', 'cleanup']);
  cancelled.fixture.completed.observe([3, 2, 1, 1, 0], 6);
  cancelled.fixture.completed.observe([3, 2, 2, 0, 0], 7);
  cancelled.consumer.observe([5, 0, 1, 0, 0], 2, false);
  cancelled.consumer.observe([5, 0, 2, 0, 0], 3, false);
  const complete = cancelled.project([cancelled.fixture.completed, cancelled.consumer], true);
  assert.equal(complete.execution, 'cancelled');
  assert.equal(JSON.parse(complete.stateWire).status, 'cancelled');
  assert.equal(complete.cleanupComplete, true);
  assert.equal(complete.publicationReady, false);
  assert.deepEqual(complete.tasks.map(task => task.nextWork), ['none', 'none']);
});

test('checked whole Run projection cancels a fenced unclaimed consumer after exact producer cleanup', () => {
  const {original, fixture, keys, project} = projectionFixture();
  let state = project([fixture.completed], true, [keys[0]]);
  assert.equal(state.cleanupComplete, false);
  assert.notEqual(state.execution, 'cancelled');
  fixture.completed.observe([3, 2, 1, 1, 0], 6);
  assert.equal(project([fixture.completed], true, [keys[0]]).cleanupComplete, false);
  fixture.completed.observe([3, 2, 2, 0, 0], 7);
  // Raw graph progress still requires both checked task observations. Only
  // the cancellation projection discharges the never-started task obligation.
  assert.equal(inspectTaskProgress(original.prepared, original.compilation, original.admission,
    original.definition, fixture.completed.authority,
    [fixture.completed.current().durableRecordWire]).cleanupComplete, false);
  state = project([fixture.completed], true, [keys[0]]);
  assert.equal(state.cleanupComplete, true);
  assert.equal(state.execution, 'cancelled');
  assert.equal(JSON.parse(state.stateWire).status, 'cancelled');
  assert.equal(state.executionComplete, false);
  assert.equal(state.publicationReady, false);
  assert.equal(state.nextTask, undefined);
  assert.deepEqual(state.tasks.map(task => task.nextWork), ['none', 'none']);
  assert.deepEqual(state.tasks.map(task => task.cleanup), ['released', 'unobserved']);
});

test('checked whole Run projection keeps missing claimed consumer and unfenced absence unresolved', () => {
  const {fixture, keys, project} = projectionFixture();
  fixture.completed.observe([3, 2, 1, 1, 0], 6);
  fixture.completed.observe([3, 2, 2, 0, 0], 7);
  const claimed = project([fixture.completed], true, keys);
  assert.equal(claimed.execution, 'unknown');
  assert.equal(claimed.cleanupComplete, false);
  assert.equal(claimed.tasks[1].nextWork, 'reconcile');
  assert.notEqual(JSON.parse(claimed.stateWire).status, 'cancelled');
  const unfenced = project([fixture.completed], false, [keys[0]]);
  assert.equal(unfenced.cleanupComplete, false);
  assert.notEqual(unfenced.execution, 'cancelled');
  assert.equal(unfenced.nextTask, 1);
});

test('checked whole Run projection requires terminal and cleanup proof from every dispatched consumer', () => {
  const {fixture, consumer, keys, project} = projectionFixture();
  fixture.completed.observe([3, 2, 1, 1, 0], 6);
  fixture.completed.observe([3, 2, 2, 0, 0], 7);
  // Even without a Host start claim, a persisted consumer dispatch has
  // custody. Historical Accepted is not proof of physical stop or cleanup.
  let state = project([fixture.completed, consumer], true, [keys[0]]);
  assert.equal(state.cleanupComplete, false);
  assert.notEqual(state.execution, 'cancelled');
  assert.equal(state.tasks[1].nextWork, 'cancel');
  consumer.observe([5, 0, 0, 0, 0], 1, false);
  state = project([fixture.completed, consumer], true, [keys[0]]);
  assert.equal(state.cleanupComplete, false);
  assert.notEqual(state.execution, 'cancelled');
  consumer.observe([5, 0, 1, 0, 0], 2, false);
  assert.equal(project([fixture.completed, consumer], true, [keys[0]]).cleanupComplete, false);
  consumer.observe([5, 0, 2, 0, 0], 3, false);
  state = project([fixture.completed, consumer], true, [keys[0]]);
  assert.equal(state.cleanupComplete, true);
  assert.equal(state.execution, 'cancelled');
});


test('checked whole Run projection distinguishes recovered custody from normal Released', () => {
  const {fixture, consumer, project} = projectionFixture();
  consumer.observe([3, 2, 0, 1, 0], 5);
  fixture.completed.observe([3, 2, 4, 0, 1], 6);
  let state = project([fixture.completed, consumer]);
  assert.equal(state.cleanupComplete, false);
  assert.equal(state.tasks[0].cleanup, 'force_lost');
  assert.equal(state.tasks[1].cleanup, 'active');
  fixture.completed.observe([3, 2, 5, 0, 0], 7);
  state = project([fixture.completed, consumer]);
  assert.equal(state.cleanupComplete, false);
  assert.equal(state.tasks[0].cleanup, 'recovered_after_loss');
  consumer.observe([3, 2, 1, 1, 0], 6);
  consumer.observe([3, 2, 2, 0, 0], 7);
  state = project([fixture.completed, consumer]);
  assert.equal(state.cleanupComplete, true);
  assert.deepEqual(state.tasks.map(task => task.cleanup), ['recovered_after_loss', 'released']);
  assert.notDeepEqual(state.tasks.map(task => task.cleanup), ['released', 'released']);
  // Formal recovery can discharge its owner, but never proves normal release
  // or resolves an unrelated historical Run such as the #88 recovery ledger.
});


const taskStartFixture = () => {
  const original = run();
  const producer = coordinatorProducerFixture(original);
  const request = prepareTaskRequest(original.prepared, original.compilation,
    producer.authority, 'original-request');
  const keys = taskKeys(original.prepared, original.compilation);
  const claim = {taskKey: keys[0], dispatchCid: producer.issued.cid,
    definitionCid: privateRunDefinition(original.definition).cid,
    reserved: true, unstarted: true, authorized: true, cancelled: false, failed: false};
  const start = (records = [producer], changes = {}, requested = request, retained = request) =>
    prepareTaskPhysicalStart(original.prepared, original.compilation, original.admission,
      original.definition, producer.authority, records.map(value => value.current().durableRecordWire),
      requested, retained, {...claim, ...changes});
  return {original, producer, request, keys, claim, start};
};

test('checked task physical start requires exact saved intent and retains exclusive claim responsibility', () => {
  const {producer, start} = taskStartFixture();
  const before = producer.current().durableRecordWire;
  assert.equal(start([]), false, 'no missing intent may authorize a start');
  assert.equal(start(), true, 'the unobserved original intent is eligible for one Host CAS claim');
  for (const changes of [{reserved: false}, {unstarted: false}, {cancelled: true}, {failed: true}]) {
    assert.equal(start([producer], changes), false);
  }
  assert.throws(() => start([producer], {authorized: false}), {code: 'RunHostTaskStartRejected'});
  assert.equal(producer.current().durableRecordWire, before,
    'eligibility never commits a claim, starts execution or changes custody');
});

test('checked task physical start rejects foreign task dispatch Run and matching foreign request pairs', () => {
  const {original, producer, keys, start} = taskStartFixture();
  for (const changes of [{taskKey: 'foreign-task'}, {dispatchCid: cid('f')},
    {definitionCid: cid('f')}]) {
    assert.throws(() => start([producer], changes), {code: 'RunHostTaskStartRejected'});
  }
  const changed = run(document.replace('id > 2', 'id > 1'));
  const foreign = prepareTaskRequest(changed.prepared, changed.compilation,
    producer.authority, 'original-request');
  assert.throws(() => start([producer], {}, foreign, foreign), {code: 'RunHostTaskStartRejected'});
  const otherRequest = prepareTaskRequest(original.prepared, original.compilation,
    producer.authority, 'another-request');
  assert.throws(() => start([producer], {}, otherRequest), {code: 'RunHostTaskStartRejected'});
  const otherScope = prepareTaskRequest(original.prepared, original.compilation,
    cid('f'), 'original-request');
  assert.throws(() => start([producer], {}, otherScope, otherScope), {code: 'RunHostTaskStartRejected'});
  assert.equal(start([], {taskKey: keys[1]}), false);
});

test('checked task physical start never treats historical Accepted running or unknown as unstarted', () => {
  for (const state of [[1, 0, 0, 0, 0], [2, 0, 0, 0, 0], [6, 0, 3, 0, 0]]) {
    const {producer, start} = taskStartFixture();
    producer.observe(state, 1, false);
    assert.equal(start(), false, 'observation overrides an erroneous Host unstarted assertion');
  }
});

test('checked task physical start uses producer proof for the exact dependent consumer', () => {
  const {original, producer, keys, start} = taskStartFixture();
  const fixture = retainedTransferFixture(original);
  fixture.commit();
  const input = prepareRetainedTaskInput(fixture.producer, fixture.receipt,
    'receiver-use', fixture.current, inputLimits);
  const consumer = coordinatorProducerFixture(original, 1, cid('7'),
    issueConsumer(original, fixture, input));
  const changes = {taskKey: keys[1], dispatchCid: consumer.issued.cid};
  assert.equal(start([producer, consumer], changes), false, 'unsettled producer prevents consumer start');
  producer.observe([3, 2, 0, 1, 0], 1, false);
  assert.equal(start([producer, consumer], changes), false, 'settlement without admitted proof is insufficient');
  producer.observe([3, 2, 0, 1, 0], 2);
  assert.equal(start([producer, consumer], changes), true);
  assert.equal(start([producer, consumer], {...changes, unstarted: false}), false);
  assert.equal(start([producer, consumer], {...changes, cancelled: true}), false);
  consumer.observe([1, 0, 0, 0, 0], 1, false);
  assert.equal(start([producer, consumer], changes), false);
});

function retainedCurrentReplyFixture(fixture, queryId, changes = {}) {
  return identifyRetainedWire({destination_receipt_cid: fixture.receipt.cid,
    destination_receipt_json: fixture.receipt.wire,
    dispatch_request_cid: fixture.completed.issued.cid,
    plan_cid: fixture.reply.cid, query_id: queryId,
    transfer_record_json: fixture.wire(),
    version: 'actql-remote-retained-input-current-reply/0.1', ...changes});
}

test('retained current query joins actual durable protocol record and rejects stale challenges', () => {
  const fixture = retainedPlanFixture(run());
  const plan = admitRetainedInputPlan(fixture.intent, fixture.reply, fixture.planCurrent, planLimits);
  const query = prepareRetainedInputCurrentQuery(plan, 'e\u0301\r\n');
  assert.deepEqual(JSON.parse(retainedInputCurrentEnvelope(query)), {
    dispatch_request_cid: fixture.completed.issued.cid,
    handoff_json: retainedInputTransferEnvelope(plan), plan_cid: fixture.reply.cid,
    query_id: 'e\u0301\r\n', version: 'actql-remote-poll-retained-input-current/0.1'});
  const incomplete = retainedCurrentReplyFixture(fixture, 'e\u0301\r\n');
  assert.throws(() => admitRetainedInputCurrentReply(query, incomplete, planLimits),
    {code: 'RunHostRetainedInputCurrentRejected'});
  fixture.commit();
  const before = fixture.wire();
  const saved = retainedCurrentReplyFixture(fixture, 'e\u0301\r\n');
  const reply = admitRetainedInputCurrentReply(query, saved, planLimits);
  assert.deepEqual(retainedInputCurrentReplyFacts(reply), {...saved,
    transferRecordWire: before, receipt: fixture.receipt});
  assert.equal(fixture.wire(), before);
  const newer = prepareRetainedInputCurrentQuery(plan, 'next-live-query');
  assert.throws(() => admitRetainedInputCurrentReply(newer, saved, planLimits),
    {code: 'RunHostRetainedInputCurrentRejected'});
  for (const change of [{plan_cid: cid('f')}, {dispatch_request_cid: cid('f')},
    {destination_receipt_cid: cid('f')}]) {
    assert.throws(() => admitRetainedInputCurrentReply(query,
      retainedCurrentReplyFixture(fixture, 'e\u0301\r\n', change), planLimits),
    {code: 'RunHostRetainedInputCurrentRejected'});
  }
  for (const forged of [plan, {}, retainedInputPlanFacts(plan)]) {
    assert.throws(() => retainedInputCurrentEnvelope(forged), {message: 'ForeignRunHostHandle'});
  }
  assert.throws(() => prepareRetainedInputCurrentQuery(plan, 'x'.repeat(257)),
    {code: 'RunHostRetainedInputCurrentRejected'});
  for (const [set, value] of [[fixture.siteCurrent, false], [fixture.authorized, false],
    [fixture.clock, 2000000000000n]]) {
    set(value);
    assert.throws(() => retainedInputCurrentEnvelope(query), {code: 'RunHostRetainedInputCurrentRejected'});
    assert.throws(() => admitRetainedInputCurrentReply(query, saved, planLimits),
      {code: 'RunHostRetainedInputCurrentRejected'});
    fixture.siteCurrent(true); fixture.authorized(true); fixture.clock(1900000000000n);
  }
  for (const limits of [{...planLimits, maxChunks: 2147483648},
    {...planLimits, maxReferencedBytes: 8}, {...planLimits, extra: 1}]) {
    assert.throws(() => admitRetainedInputCurrentReply(query, saved, limits),
      {message: 'InvalidRunHostRetainedInputCurrentLimits'});
  }
  assert.deepEqual(retainedInputCurrentReplyFacts(reply).transferRecordWire, before);
});


function effectRunFixture() {
  const read = name => readFileSync(new URL('./fixtures/' + name, import.meta.url), 'utf8').trimEnd();
  const environmentWire = read('source-compute-effect.environment.json');
  const effectEnvironment = admitEnvironment(environmentWire,
    JSON.parse(environmentWire).evidence_bundle_cid, {rela: true});
  const prepared = prepareEffect(read('source-compute-effect.program.json'), 'json', effectEnvironment);
  const compilation = compileEffect(prepared);
  const allowed = issueAllowedEffectRun(prepared, compilation, {
    executionContextCid: cid('a'), hostPolicyCid: cid('b'), expiresAt: '2099-01-01T00:00:00.000Z',
  });
  const definition = issueEffectRunDefinition(allowed, 'retained-effect', 'original-run',
    '2026-10-09T00:00:00.000Z', '2099-01-01T00:00:00.000Z');
  const caller = prepareEffectRequest(prepared, compilation, cid('c'), 'original-request');
  const original = {prepared, compilation, allowed, caller, definition, edge: () => prepareEffectRetainedTaskInputEdge(allowed, definition),
    issueSourceDispatch: selection => issueEffectSourceDispatch(allowed, definition, caller, selection)};
  return original;
}

test('Effect retained dispatch uses the original checked edge and current committed Transfer owner', () => {
  const original = effectRunFixture();
  const {allowed, definition, caller} = original;
  // Reuse the actual common Coordinator and Transfer admission/transition
  // owners. Their explicit protocol fixtures do not claim physical Site I/O.
  const fixture = retainedTransferFixture(original);
  const prepareInput = () => prepareRetainedTaskInput(fixture.producer, fixture.receipt,
    'effect-receiver-use', fixture.current, inputLimits);
  assert.throws(prepareInput, {code: 'RunHostRetainedTaskInputRejected'});
  fixture.commit();
  const input = prepareInput();
  const saved = retainedTaskInputFacts(input);
  const selection = {...fixture.completed.selection, dispatchId: 'original-effect-consumer'};
  const dispatch = issueEffectRetainedTaskDispatch(allowed, definition, caller, selection, input);
  const facts = retainedTaskInputEdgeFacts(original.edge());
  const body = JSON.parse(dispatch.wire);
  assert.equal(body.run_definition_cid, facts.runDefinitionCid);
  assert.equal(body.task_key, facts.consumerTaskKey);
  assert.equal(body.input_binding_cid, saved.cid);
  const restored = admitRetainedTaskInput(fixture.producer, saved, fixture.receipt,
    'effect-receiver-use', fixture.current, inputLimits);
  assert.deepEqual(issueEffectRetainedTaskDispatch(allowed, definition, caller, selection, restored), dispatch);
  for (const [change, denied] of [[fixture.siteCurrent, false], [fixture.authorized, false],
    [fixture.clock, 2000000000000n]]) {
    change(denied);
    assert.throws(() => issueEffectRetainedTaskDispatch(allowed, definition, caller, selection, input),
      {code: 'RunHostEffectRetainedTaskDispatchRejected'});
    fixture.siteCurrent(true); fixture.authorized(true); fixture.clock(1900000000000n);
  }
  assert.throws(() => issueEffectRetainedTaskDispatch(allowed, definition, caller,
    {...selection, siteGeneration: 2}, input), {code: 'RunHostEffectRetainedTaskDispatchRejected'});
  assert.throws(() => issueEffectRetainedTaskDispatch(allowed, definition, caller,
    selection, {...input}), /ForeignRunHostHandle/u);
  fixture.completed.observe([3, 2, 1, 1, 0], 6);
  assert.throws(() => issueEffectRetainedTaskDispatch(allowed, definition, caller, selection, input),
    {code: 'RunHostEffectRetainedTaskDispatchRejected'});
  assert.deepEqual(retainedTaskInputFacts(input), saved);
});

test('Effect checked progress advances the original computation without projecting Effect completion', () => {
  const original = effectRunFixture();
  const {allowed, definition, caller} = original;
  const inspect = (...records) => inspectEffectTaskProgress(allowed, definition,
    cid('c'), records.map(record => record.current().durableRecordWire));
  const empty = inspect();
  assert.equal(empty.nextTask, 0);
  assert.equal(empty.computationComplete, false);
  assert.equal(empty.taskCleanupComplete, false);
  assert.deepEqual(empty.resultTasks, [1]);
  const fixture = retainedTransferFixture(original);
  assert.equal(inspect(fixture.completed).nextTask, 1);
  fixture.commit();
  const input = prepareRetainedTaskInput(fixture.producer, fixture.receipt,
    'effect-progress-use', fixture.current, inputLimits);
  const dispatch = issueEffectRetainedTaskDispatch(allowed, definition, caller,
    {...fixture.completed.selection, dispatchId: 'effect-progress-consumer'}, input);
  const consumer = coordinatorProducerFixture(original, 1, cid('7'), dispatch);
  assert.equal(inspect(fixture.completed, consumer).nextTask, undefined,
    'a saved consumer intent is reconciled rather than selected again');
  const facts = retainedTaskInputEdgeFacts(original.edge());
  const claim = {taskKey: facts.consumerTaskKey, dispatchCid: dispatch.cid,
    definitionCid: facts.runDefinitionCid, reserved: true, unstarted: true,
    authorized: true, cancelled: false, failed: false};
  const records = [fixture.completed, consumer].map(record => record.current().durableRecordWire);
  assert.equal(prepareEffectTaskPhysicalStart(allowed, definition, cid('c'), records,
    caller, caller, claim), true);
  assert.equal(prepareEffectTaskPhysicalStart(allowed, definition, cid('c'), records,
    caller, caller, {...claim, cancelled: true}), false);
  consumer.observe([3, 2, 0, 1, 0], 5, false);
  assert.equal(inspect(fixture.completed, consumer).computationComplete, false,
    'physical settlement without output proof does not complete computation');
  consumer.observe([3, 2, 0, 1, 0], 6);
  const complete = inspect(fixture.completed, consumer);
  assert.equal(complete.computationComplete, true);
  assert.equal(complete.taskCleanupComplete, false);
  for (const name of ['executionComplete', 'publicationReady', 'stateWire']) {
    assert.equal(name in complete, false, 'no Pure Run completion/publication projection escapes');
  }
  assert(Object.isFrozen(complete)); assert(Object.isFrozen(complete.tasks));
  assert(Object.isFrozen(complete.tasks[0])); assert(Object.isFrozen(complete.tasks[0].executionScope));
  for (const record of [fixture.completed, consumer]) {
    record.observe([3, 2, 1, 1, 0], 7);
    record.observe([3, 2, 2, 0, 0], 8);
  }
  assert.equal(inspect(fixture.completed, consumer).taskCleanupComplete, true,
    'task cleanup says nothing about Checkpoint/Effect/borrower/Result custody');
});

test('Effect task start uses the original request and never restarts accepted running or unknown work', () => {
  for (const observed of [undefined, [1, 0, 0, 0, 0], [2, 0, 0, 0, 0], [6, 0, 3, 0, 0]]) {
    const original = effectRunFixture();
    const producer = coordinatorProducerFixture(original);
    const facts = retainedTaskInputEdgeFacts(original.edge());
    const claim = {taskKey: facts.producerTaskKey, dispatchCid: producer.issued.cid,
      definitionCid: facts.runDefinitionCid, reserved: true, unstarted: true,
      authorized: true, cancelled: false, failed: false};
    const start = (changes = {}, requested = original.caller, retained = original.caller) =>
      prepareEffectTaskPhysicalStart(original.allowed, original.definition, cid('c'),
        [producer.current().durableRecordWire], requested, retained, {...claim, ...changes});
    if (observed) producer.observe(observed, 1, false);
    const before = producer.current().durableRecordWire;
    assert.equal(start(), observed === undefined);
    for (const changes of [{reserved: false}, {unstarted: false}, {cancelled: true}, {failed: true}]) {
      assert.equal(start(changes), false);
    }
    for (const changes of [{authorized: false}, {taskKey: 'foreign'},
      {dispatchCid: cid('f')}, {definitionCid: cid('f')}]) {
      assert.throws(() => start(changes), {code: 'RunHostEffectTaskStartRejected'});
    }
    const foreign = run(document.replace('id > 2', 'id > 1'));
    const request = prepareTaskRequest(foreign.prepared, foreign.compilation, cid('c'), 'original-request');
    assert.throws(() => start({}, request, request), {code: 'RunHostEffectTaskStartRejected'});
    assert.equal(producer.current().durableRecordWire, before, 'claim eligibility does not commit or start');
  }
});

test('Effect progress rejects foreign Run authority competing attempts and forged family handles', () => {
  const original = effectRunFixture();
  const producer = coordinatorProducerFixture(original);
  const saved = producer.current().durableRecordWire;
  const inspect = (records, authority = cid('c'), definition = original.definition) =>
    inspectEffectTaskProgress(original.allowed, definition, authority, records);
  assert.equal(inspect([saved]).nextTask, undefined);
  assert.throws(() => inspect([saved], cid('f')), {code: 'RunHostEffectTaskProgressRejected'});
  assert.throws(() => inspect([saved, saved]), {code: 'RunHostEffectTaskProgressRejected'});
  const other = coordinatorProducerFixture(original, 2).current().durableRecordWire;
  assert.throws(() => inspect([saved, other]), {code: 'RunHostEffectTaskProgressRejected'});
  const foreign = issueEffectRunDefinition(original.allowed, 'retained-effect', 'other-run',
    '2026-10-09T00:00:00.000Z', '2099-01-01T00:00:00.000Z');
  assert.throws(() => inspect([saved], cid('c'), foreign), {code: 'RunHostEffectTaskProgressRejected'});
  const pure = run();
  assert.throws(() => inspect([], cid('c'), pure.definition), {code: 'RunHostEffectTaskProgressRejected'});
  for (const records of [null, ['invalid'], [saved, 1]]) assert.throws(() => inspect(records));
  for (const forged of [{...original.allowed}, original.prepared, inspect([])]) {
    assert.throws(() => inspectEffectTaskProgress(forged, original.definition, cid('c'), []),
      {message: 'ForeignRunHostHandle'});
  }
});

// Static original-Source dispatch/retained-custody composition only. These
// protocol fixtures do not establish physical Source, capacity or a grant.
const sourceDispatchText = 'SELECT id FROM records WHERE id > 0 ORDER BY id';
function originalSourceRun(text = sourceDispatchText) {
  const snapshot = JSON.parse(fixture.wire).schema_snapshots.find(value => value.source_ref === 'connector://crm/main/r#v');
  const publication = JSON.stringify({environmentCid: fixture.cid, aliases: [{
    name: 'records', sourceRef: snapshot.source_ref, sourceViewContractCid: snapshot.source_view_contract_cid,
    schemaContractCid: snapshot.carrier_schema_contract_cid,
  }]});
  const intent = prepareSubmittedIntent(JSON.stringify({kind: 'aql', input: {text, format: 'sql'}, parameters: null}),
    {maxWireBytes: 65536, maxNodes: 8192, maxDepth: 64});
  const selected = prepareSourceProgram(intent, environment, publication);
  assert.equal(selected.kind, 'effect_free');
  const original = run(undefined, selected.prepared);
  assert.deepEqual(taskExecutionShape(original.prepared, original.compilation), {taskCount: 2, acquisitionCount: 1});
  return original;
}

test('original Source initial dispatch preserves authored input and rejects copied or wrong requests', () => {
  const original = originalSourceRun();
  const producer = coordinatorProducerFixture(original);
  const request = prepareTaskRequest(original.prepared, original.compilation, producer.authority, 'original-request');
  const fields = requestFields(request);
  assert.notEqual(fields.callerInputIntentCid, cid('f'));
  const retained = admitRequestFields(fields);
  assert.deepEqual(issueTaskDispatch(original.prepared, original.compilation, original.admission,
    original.definition, retained, 0, producer.selection), producer.issued);
  const wrongSource = originalSourceRun(sourceDispatchText + ' ');
  const wrongRequest = prepareTaskRequest(wrongSource.prepared, wrongSource.compilation, producer.authority, 'original-request');
  assert.notEqual(requestFields(wrongRequest).callerInputIntentCid, fields.callerInputIntentCid);
  assert.throws(() => issueTaskDispatch(original.prepared, original.compilation, original.admission,
    original.definition, wrongRequest, 0, producer.selection), {code: 'RunHostDispatchRejected'});
  assert.throws(() => issueTaskDispatch({...original.prepared}, original.compilation,
    original.admission, original.definition, retained, 0, producer.selection), /ForeignRunHostHandle/u);
  assert.throws(() => issueTaskDispatch(original.prepared, original.compilation,
    original.admission, original.definition, {...retained}, 0, producer.selection), /ForeignRunHostHandle/u);
  const material = sourceProgramMaterialInput(original.prepared, fixture.wire);
  const missing = run(material.document);
  const arbitrary = prepareRequest(missing.prepared, producer.authority, 'original-request', fields.callerInputIntentCid);
  assert.throws(() => issueTaskDispatch(missing.prepared, missing.compilation, missing.admission,
    missing.definition, arbitrary, 0, producer.selection), {code: 'RunHostDispatchRejected'});
});

test('original Source retained dispatch preserves current committed input and rejects a foreign source request', () => {
  const original = originalSourceRun();
  const saved = retainedTransferFixture(original);
  saved.commit();
  const input = prepareRetainedTaskInput(saved.producer, saved.receipt, 'original-source-receiver', saved.current, inputLimits);
  const facts = retainedTaskInputFacts(input);
  const dispatch = issueConsumer(original, saved, input);
  assert.equal(JSON.parse(dispatch.wire).run_definition_cid, privateRunDefinition(original.definition).cid);
  assert.deepEqual(retainedTaskInputFacts(input), facts);
  const foreign = originalSourceRun(sourceDispatchText + ' ');
  const wrong = prepareTaskRequest(foreign.prepared, foreign.compilation, saved.completed.authority, 'original-request');
  assert.throws(() => issueRetainedTaskDispatch(original.prepared, original.compilation, original.admission,
    original.definition, wrong, 1, {...saved.completed.selection, dispatchId: 'consumer-1'}, input),
  {code: 'RunHostRetainedTaskDispatchRejected'});
  assert.throws(() => issueConsumer({...original, prepared: {...original.prepared}}, saved, input), /ForeignRunHostHandle/u);
  assert.throws(() => issueConsumer(original, saved, {...input}), /ForeignRunHostHandle/u);
  assert.throws(() => issueConsumer(original, saved, input, {...saved.completed.selection, siteGeneration: 2}),
    {code: 'RunHostRetainedTaskDispatchRejected'});
  saved.authorized(false);
  assert.throws(() => issueConsumer(original, saved, input), {code: 'RunHostRetainedTaskDispatchRejected'});
});
