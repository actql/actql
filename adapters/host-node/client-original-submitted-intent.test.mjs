import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync, StatementSync} from 'node:sqlite';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installClientControlOperationLookup, installClientRunSample} from './client-run-plan.mjs';
import {installClientRunInspect} from './client-run-inspect.mjs';
import {createLocalReadAuthorizations} from './local-result-authorization.mjs';
import {sourceReadAccountConfiguration} from './local-account-config.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {connect} from '../../packages/sdk/index.mjs';
import {createLocalResultReadWorkspace} from './local-result-read-workspace.mjs';
import {installNodeClientDispatchOwner, installNodeRelationSampleDebugEntry} from './client-dispatch-owner.mjs';

const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ?? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url).href);

const cid = digit => `sha256:${digit.repeat(64)}`;
const hash = value => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
const fields = Object.freeze({authorityScopeCid: cid('a'), namespaceId: 'original-content',
  currentAuthorization: true});
const publication = runtimeCore(moon).publicationControl;

function controlReference(original) {
  const command = JSON.parse(original.wire);
  return {run_ref: command.run_ref, operation_id: command.operation_id,
    command_cid: original.identity, accepted_from_revision: command.expected_control_revision};
}

const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const receiptOriginal = (d, reserve = bytes => assert.ok(bytes > 0)) =>
  ({runDefinition: d.f.accepted.runDefinition, logicalMapCid: cid('5'), reserve});
function lookupRetainedResume(d, command, reserveConstruction = peak => assert.ok(peak > 0), current = d.current) {
  const operation = controlReference(command);
  return d.f.journal.lookupDebugResume(d.ref, {operationId: operation.operation_id,
    commandCid: operation.command_cid, acceptedFromRevision: operation.accepted_from_revision,
    current, reserve: bytes => assert.ok(bytes > 0),
    reserveConstruction}, publication);
}
async function assertRecoveredDebugReceiptOnSdk(d, command, recovered, table) {
  const operation = controlReference(command);
  const workspace = createLocalResultReadWorkspace({runtime: moon,
    requestMemory: Object.freeze({retainedBytes: 4 * 1024 * 1024, executionBytes: 4 * 1024 * 1024}),
    assertCurrent() {}});
  const dispatcher = installNodeClientDispatchOwner({moon, journal: d.f.journal, control: publication,
    hostConnection: actor => actor.principalId === 'original' &&
      actor.ref.namespaceId === d.ref.namespaceId && actor.ref.authorityScopeCid === d.ref.authorityScopeCid &&
      actor.ref.runDefinitionCid === d.ref.runDefinitionCid});
  const ingress = createNodeInProcessClientHost({
    authenticate: () => 'original',
    authorizeConnection: () => true,
    negotiate: () => ({version: 'actql-client-host/0.1', mode: 'local', owner: 'local', durability: 'volatile',
      scopeRef: d.ref.authorityScopeCid, capabilities: [], limits: {maxReadWireBytes: 65536,
        maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
        maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}}),
    maxRowBytes: 1024,
    attach: ({ref}) => ({ref, durability: 'volatile', revision: recovered.revision}),
    lookupControlOperation: installClientControlOperationLookup({
      authorize: d.current, lookupOriginal: dispatcher.lookupDebugResume, readWorkspace: workspace,
    }),
  });
  const sdk = await connectInProcess({mode: 'local', owner: 'local'}, ingress);
  try {
    const run = await sdk.attach(d.ref);
    const writer = new DatabaseSync(join(d.f.path, 'client-requests.sqlite3'));
    try {
      assert.equal(writer.prepare('PRAGMA journal_mode').get().journal_mode, 'wal');
      writer.exec('BEGIN IMMEDIATE');
      assert.equal(writer.prepare('UPDATE ' + table + ' SET resume_accepted_at = resume_accepted_at + 1')
        .run().changes, 1);
      assert.deepEqual(await run.lookupControlOperation(operation), {state: 'found', receipt: recovered.receipt,
        observation: {original_receipt_cid: recovered.receipt.self_cid, operation_ref: operation,
          outcome: 'accepted', observed_at: recovered.receipt.observed_state.updated_at}});
      assert.equal(writer.isTransaction, true);
    } finally {
      if (writer.isTransaction) writer.exec('ROLLBACK');
      writer.close();
    }
    for (const changed of [{command_cid: cid('e')}, {accepted_from_revision: operation.accepted_from_revision - 1}]) {
      assert.deepEqual(await run.lookupControlOperation({...operation, ...changed}),
        {state: 'unknown', reason: 'control_operation_unobserved'});
    }
  } finally {
    await sdk.close();
    assert.deepEqual(await workspace.closeAll(), {pending: false});
  }
}
const evidence = Object.freeze({prepared: 'original-prepared-wire', authorization: 'original-authorization-wire'});

async function fixture(t, {selected = true, readOnly = false, link = true, debug = false,
  journalOptions, shared, runName = 'same-original', inspect = false} = {}) {
  const path = shared?.path ?? await mkdtemp(join(tmpdir(), 'actql-original-submitted-intent-'));
  let journal = shared?.journal ?? openClientRequestJournal(path, journalOptions);
  if (shared === undefined) {
    t.after(async () => {journal.close(); await rm(path, {recursive: true, force: true});});
  }
  const getJournal = () => shared?.journal ?? journal;
  const epoch = journal.issueSubmissionEpoch(fields, moon);
  const reference = {epoch, nonce: runName + '-content'};
  const intent = moon.clientSubmittedIntent(JSON.stringify({kind: 'program', input: {},
    parameters: null, ...(selected ? {stopBefore: 'commit'} : {}),
    ...(debug ? {executionProfile: 'debug'} : {}),
    ...(readOnly ? {readOnly: true} : {})}), 4096, 128, 16);
  assert.ok(intent);
  const recorded = journal.recordSubmittedIntent(reference, intent, fields, moon);
  const requestId = recorded.requestId;
  const request = (parameters = cid('2')) => moon.clientRequestAdmitRecord(
    fields.authorityScopeCid, requestId, cid('1'), parameters, cid('3'),
    hash({version: 'actql-logical-request/0.1', authority_scope_cid: fields.authorityScopeCid,
      caller_request_id: requestId}),
    hash({version: 'actql-logical-request-intent/0.1', program_definition_cid: cid('1'),
      parameter_values_cid: parameters, caller_input_intent_cid: cid('3')}));
  const identity = request();
  assert.ok(identity);
  const definition = publication.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1', scope_id: inspect ? fields.namespaceId : 'original-content-scope',
    run_id: runName + '-run',
    compiled_plan_cid: cid('4'), invocation_template_cid: cid('5'), authorization_context_cid: cid('6'),
    input_artifact_set_cid: cid('7'), created_at: '2026-09-25T00:00:00.000Z',
    valid_until: '2098-01-01T00:00:00.000Z',
  }), limits);
  const submission = {...reference, intentCid: moon.clientSubmittedIntentCid(intent), currentAuthorization: true};
  let runAdmissionEvidence = evidence;
  if (inspect) {
    const prepared = publication.sealRunEvidence('prepared_invocation', JSON.stringify({
      version: 'actql-prepared-invocation/0.1', invocation_template_cid: cid('5'),
      compiled_plan_cid: cid('4'), execution_context_cid: cid('6'), host_policy_cid: cid('9'),
      policy_decision: 'allow', expires_at: '2098-01-01T00:00:00.000Z',
    }), limits);
    const authorization = publication.sealRunEvidence('run_authorization', JSON.stringify({
      version: 'actql-run-authorization/0.1', prepared_invocation_cid: prepared.identity,
      execution_context_cid: cid('6'), host_policy_cid: cid('9'), decision: 'allowed',
    }), limits);
    runAdmissionEvidence = {prepared: prepared.wire, authorization: authorization.wire};
  }
  const accepted = journal.acceptDefinition(identity, {namespaceId: fields.namespaceId,
    runDefinition: definition, runAdmissionEvidence,
    lookupExpiresAt: '2099-01-01T00:00:00.000Z', ...(link ? {submission} : {})}, moon, publication);
  const readRow = () => {
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    try {return database.prepare('SELECT * FROM client_requests WHERE run_definition_cid = ?').get(definition.identity);}
    finally {database.close();}
  };
  const mutate = transform => {
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    try {
      const row = database.prepare('SELECT run_admission_evidence_json FROM client_requests WHERE run_definition_cid = ?')
        .get(definition.identity);
      const material = JSON.parse(row.run_admission_evidence_json);
      transform(material);
      database.prepare('UPDATE client_requests SET run_admission_evidence_json = ? WHERE run_definition_cid = ?')
        .run(JSON.stringify(material), definition.identity);
    } finally {database.close();}
  };
  return {path, reference, intent, request, identity, accepted, readRow, mutate,
    update(sql, ...parameters) {
      const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
      try {return database.prepare(sql).run(...parameters);}
      finally {database.close();}
    },
    get journal() {return getJournal();},
    read: (requestControl = moon, publicationControl = publication) =>
      getJournal().originalSubmittedIntent(identity, fields, requestControl, publicationControl),
    reopen() {
      if (shared !== undefined) shared.reopen();
      else {journal.close(); journal = openClientRequestJournal(path, journalOptions);}
    }};
}

async function debugEntryFixture(t, debug = true, journalOptions, inspect = false) {
  let now = Date.parse('2026-11-22T06:00:00Z');
  const f = await fixture(t, {debug, selected: false, inspect,
    journalOptions: {...journalOptions, submissionEpochNow: () => now}});
  f.journal.reserveDispatch(f.identity, fields, moon, publication);
  const ref = f.accepted.ref, expectedRevision = f.readRow().revision, current = () => true;
  const pausedAt = now, expiresAt = now + 1000;
  const command = (changes = {}) => publication.sealRunEvidence('control_command', JSON.stringify({
    version: 'actql-control-command/0.1', operation: 'resume', run_ref: ref,
    expected_control_revision: expectedRevision + 1, operation_id: 'resume-original-entry',
    interval: {until: 'step', guards: null}, ...changes,
  }), limits);
  const park = (overrides = {}) => f.journal.parkDebugEntry(f.identity, {
    ref, expectedRevision, expiresAt, current, ...overrides,
  }, moon, publication);
  const resume = (wire = command().wire, check = current) =>
    f.journal.acceptDebugEntryResume(ref, {commandWire: wire, current: check}, publication);
  const start = (debugResume, currentAuthorization = true) => f.journal.reservePhysicalStart(f.identity, {
    namespaceId: ref.namespaceId, ref, currentAuthorization,
    ...(debugResume === undefined ? {} : {debugResume: {
      capture() {assert.fail('A refused start cannot deliver a Driver handoff');}, ...debugResume,
    }}),
  }, moon, publication);
  return {f, ref, expectedRevision, expiresAt, pausedAt, command, current, park, resume, start,
    advanceClock: offset => {now += offset;},
    lookup: (check = current) => f.journal.lookupDebugEntry(ref, {current: check}, publication),
    expire: () => {now = expiresAt;}, restoreClock: () => {now = expiresAt - 1;}};
}

test('a retained Debug entry requires one exact resume across Journal reopen', async t => {
  const {default: support} = await import('./host-journal-schema-support.cjs');
  const d = await debugEntryFixture(t, true, {
    maxDatabaseBytes: 4194304,
    primarySchemaLimits: {maxSchemaBytes: 65536, maxSchemaEntries: 128,
      maxSchemaPages: 256, maxWalFrames: 8192},
    primarySchemaSqlSupport: support.sql,
  });
  const parked = {kind: 'parked', revision: d.expectedRevision + 1, expiresAt: d.expiresAt, pausedAt: d.pausedAt};
  assert.deepEqual(d.park(), parked);
  assert.equal(d.f.readRow().revision, parked.revision);
  assert.equal(d.f.readRow().physical_start_reserved, 0);
  assert.equal(d.start(), false);
  d.advanceClock(19);
  d.f.reopen();
  assert.deepEqual(d.lookup(), parked);
  assert.deepEqual(d.park(), parked, 'retry must keep the time from the first acknowledged park');
  assert.equal(d.start(), false);
  const command = d.command();
  assert.equal(d.start({commandCid: command.identity, current: d.current}), false);
  assert.throws(() => d.resume(d.command({expected_control_revision: d.expectedRevision}).wire),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.throws(() => d.resume(d.command({run_ref: {...d.ref, runDefinitionCid: cid('f')}}).wire),
    {code: 'ClientRunDebugEntryForeignCommand'});
  assert.throws(() => d.resume(d.command({interval: {until: 'breakpoint', guards: null}}).wire),
    {code: 'ClientRunDebugEntryUnsupportedCommand'});

  let authorizationChecks = 0;
  assert.throws(() => d.resume(command.wire, () => ++authorizationChecks === 1),
    {code: 'ClientRunDebugEntryDenied'});
  assert.deepEqual(d.lookup(), parked);
  assert.equal(d.f.readRow().revision, parked.revision);
  const accepted = {kind: 'resume_accepted', revision: parked.revision + 1,
    commandCid: command.identity, until: 'step', acceptedAt: d.pausedAt + 19};
  assert.deepEqual(d.resume(command.wire), accepted);
  assert.throws(() => d.park(), {code: 'ClientRunDebugEntryRevisionConflict'});
  d.advanceClock(25);
  d.f.reopen();
  assert.deepEqual(d.lookup(), accepted);
  assert.deepEqual(d.resume(command.wire), accepted);
  assert.throws(() => d.resume(d.command({interval: {until: 'terminal', guards: null}}).wire),
    {code: 'ClientRunDebugEntryResumeConflict'});
  assert.equal(d.start(), false);
  assert.throws(() => d.start({commandCid: cid('c'), current: d.current}),
    {code: 'ClientRunDebugEntryForeignCommand'});
  authorizationChecks = 0;
  assert.throws(() => d.start({commandCid: command.identity, current: () => ++authorizationChecks === 1}),
    {code: 'ClientRunDebugEntryDenied'});
  assert.equal(d.f.readRow().physical_start_reserved, 0);
  assert.equal(d.f.readRow().revision, accepted.revision);
  const received = [];
  const selected = {commandCid: command.identity, current: d.current, capture(witness) {
    assert.equal(d.f.readRow().physical_start_reserved, 1, 'The independent reader sees the acknowledged commit');
    assert.ok(Object.isFrozen(witness));
    received.push(witness);
  }};
  assert.equal(d.start(selected), true);
  assert.equal(d.start(selected), false);
  assert.deepEqual(received, [{commandCid: command.identity, until: 'step',
    acceptedRevision: accepted.revision, physicalStartRevision: accepted.revision + 1}]);
  assert.equal(d.f.readRow().physical_start_reserved, 1);
  assert.equal(d.f.readRow().revision, accepted.revision + 1);
  assert.deepEqual(d.lookup(), accepted);
});

test('the installed entry waiter accepts one committed command before the original physical claim', async t => {
  for (const outcome of ['acknowledged', 'lost-reply', 'host-detached', 'account-denied']) {
    const d = await debugEntryFixture(t);
    const setup = {}, run = {}, profile = {}, account = {};
    const actor = {ref: d.ref, principalId: 'original'};
    const stopped = new AbortController();
    const actions = [];
    const installedMoon = {...moon,
      clientProgramRelationSampleDebugResumeAllowed(original, owner, actual, current, principal, site) {
        assert.strictEqual(original, profile); assert.strictEqual(owner, run);
        assert.strictEqual(actual, setup); assert.strictEqual(current, account);
        assert.equal(principal, 'original'); assert.equal(site, 'local');
        return outcome !== 'account-denied';
      },
      clientProgramAdvanceRelationSampleDebugEntry(original, owner, actual, current, principal, site, command, revision) {
        assert.strictEqual(original, profile); assert.strictEqual(owner, run);
        assert.strictEqual(actual, setup); assert.strictEqual(current, account);
        assert.equal(principal, 'original'); assert.equal(site, 'local');
        actions.push([command, revision]);
        return {$tag: 1, _0: undefined};
      },
    };
    const prepare = installNodeRelationSampleDebugEntry(installedMoon, () => account,
      selected => selected === actor, 'local', {journal: d.f.journal, control: publication,
        now: () => '2026-11-22T06:00:00.000Z'});
    const receiver = prepare(setup, run, actor, profile, stopped.signal);
    t.after(() => receiver.close());
    const waiting = receiver.parkEntry(d.f.identity, d.expectedRevision, d.expiresAt);
    assert.deepEqual(receiver.observePause(d.current), {
      revision: d.expectedRevision + 1, expiresAt: d.expiresAt, pausedAt: d.pausedAt,
    });
    assert.equal(d.f.readRow().physical_start_reserved, 0);
    assert.deepEqual(actions, [['prepare', 0]]);
    const command = d.command();
    if (outcome === 'account-denied') {
      const before = d.f.readRow();
      assert.throws(() => receiver.resumeTask(command.wire, d.current), {code: 'ClientRunDebugEntryDenied'});
      assert.deepEqual(d.f.readRow(), before);
      assert.deepEqual(d.lookup(), {kind: 'parked', revision: d.expectedRevision + 1, expiresAt: d.expiresAt, pausedAt: d.pausedAt});
      assert.deepEqual(receiver.observePause(d.current), {revision: d.expectedRevision + 1, expiresAt: d.expiresAt, pausedAt: d.pausedAt});
      receiver.close();
      await assert.rejects(waiting, {message: 'ClientRunDebugEntryOriginalUnavailable'});
    } else if (outcome === 'host-detached') {
      receiver.close();
      await assert.rejects(waiting, {message: 'ClientRunDebugEntryOriginalUnavailable'});
      d.f.reopen();
      assert.deepEqual(d.lookup(), {
        kind: 'parked', revision: d.expectedRevision + 1, expiresAt: d.expiresAt, pausedAt: d.pausedAt,
      });
      assert.equal(d.f.readRow().physical_start_reserved, 0);
      assert.equal(d.f.readRow().cancellation_requested, 0);
    } else if (outcome === 'lost-reply') {
      const exec = DatabaseSync.prototype.exec;
      let injected = false;
      DatabaseSync.prototype.exec = function(sql) {
        const result = Reflect.apply(exec, this, [sql]);
        if (sql === 'COMMIT' && !injected) {injected = true; throw new Error('OriginalEntryAckLost');}
        return result;
      };
      try {
        assert.throws(() => receiver.resumeTask(command.wire, d.current),
          {code: 'ClientRunDebugEntryUnknown', outcome: 'unknown'});
      } finally {DatabaseSync.prototype.exec = exec;}
      assert.equal(injected, true);
      assert.equal(receiver.observePause(d.current), undefined);
      assert.throws(() => receiver.resumeTask(command.wire, d.current), {code: 'ClientRunDebugEntryReconciliationRequired'});
      assert.equal(d.lookup().commandCid, command.identity);
      assert.equal(d.f.readRow().physical_start_reserved, 0);
      assert.deepEqual(actions, [['prepare', 0]]);
      const reason = new Error('original entry cancelled');
      stopped.abort(reason);
      await assert.rejects(waiting, cause => cause === reason);
    } else {
      const receipt = receiver.resumeTask(command.wire, d.current);
      assert.equal(await waiting, command.identity);
      assert.equal(d.f.readRow().revision, receipt.revision);
      assert.equal(d.f.readRow().physical_start_reserved, 0);
      assert.deepEqual(actions, [['prepare', 0]]);
      assert.throws(() => d.park(), {code: 'ClientRunDebugEntryRevisionConflict'});
      assert.equal(d.start({commandCid: command.identity, current: d.current,
        capture(witness) {receiver.activate(witness);}}), true);
      assert.deepEqual(actions, [['prepare', 0], ['step', receipt.revision + 1]]);
    }
    receiver.close();
  }
});

test('the original control lookup reports unsealed history without waking the Driver', async t => {
  const d = await debugEntryFixture(t);
  d.park();
  const command = d.command();
  assert.equal(d.resume(command.wire).kind, 'resume_accepted');
  d.f.reopen();
  const original = d.f.readRow();
  const connection = {mode: 'local', owner: 'local'};
  const dispatcher = installNodeClientDispatchOwner({moon, journal: d.f.journal, control: publication,
    hostConnection: actor => actor.connection === connection && actor.principalId === 'original' &&
      actor.ref.runDefinitionCid === d.ref.runDefinitionCid});
  const memory = Object.freeze({retainedBytes: 4 * 1024 * 1024, executionBytes: 4 * 1024 * 1024});
  const workspace = createLocalResultReadWorkspace({runtime: moon, requestMemory: memory, assertCurrent() {}});
  let allowed = true, changeAt, reservations = 0, delivered = 0;
  const lookup = installClientControlOperationLookup({
    authorize: () => allowed,
    lookupOriginal(operation, actor) {
      const selected = dispatcher.lookupDebugResume(operation, actor);
      if (changeAt === 'egress') allowed = false;
      return selected;
    },
    readWorkspace: {...workspace, metadata(request, bytes) {
      workspace.metadata(request, bytes);
      reservations++;
      if (changeAt === 'quote') allowed = false;
    }},
  });
  const request = Object.freeze({connection, ref: d.ref, operationRef: controlReference(command),
    principalId: 'original', ...limits});
  const consume = answer => {delivered++; return answer;};
  assert.deepEqual(await lookup(request, consume),
    {state: 'history_unavailable', reason: 'control_receipt_not_retained'});
  assert.deepEqual(await lookup({...request, operationRef: {...request.operationRef,
    command_cid: cid('e')}}, consume), {state: 'unknown', reason: 'control_operation_unobserved'});
  await assert.rejects(lookup({...request, connection: {...connection}}, consume),
    {code: 'RunObservationAccessDenied'});
  assert.equal(reservations, 2, 'foreign actor refused before quote or Journal');
  for (const point of ['quote', 'egress']) {
    changeAt = point;
    allowed = true;
    await assert.rejects(lookup(request, consume), {code: 'RunObservationAccessDenied'});
  }
  assert.equal(delivered, 2);
  assert.deepEqual(d.f.readRow(), original);
  assert.deepEqual(await workspace.closeAll(), {pending: false});
});

test('the Debug entry gate respects current authority, expiry and the ordinary start path', async t => {
  const d = await debugEntryFixture(t);
  assert.throws(() => d.park({current: () => false}), {code: 'ClientRunDebugEntryDenied'});
  assert.throws(() => d.lookup(() => Promise.resolve(true)), {code: 'ClientRunDebugEntryDenied'});
  assert.deepEqual(d.lookup(), {kind: 'unobserved'});
  d.park();
  d.expire();
  assert.deepEqual(d.resume(), {kind: 'expired'});
  d.restoreClock();
  d.f.reopen();
  assert.deepEqual(d.lookup(), {kind: 'expired'});
  assert.equal(d.start({commandCid: d.command().identity, current: d.current}), false);
  assert.equal(d.f.readRow().physical_start_reserved, 0);
  const normal = await debugEntryFixture(t, false);
  assert.throws(normal.park, {code: 'ClientRunDebugEntryOriginalUnavailable'});
  assert.equal(normal.start(), true);
});

test('lost Debug resume COMMIT acknowledgement recovers only the retained command', async t => {
  for (const committed of [true, false]) {
    const d = await debugEntryFixture(t, true, undefined, true);
    const parked = d.park(), command = d.command();
    d.advanceClock(17);
    let delivered = 0, reserved = 0;
    const accept = reserve => d.f.journal.acceptDebugEntryResume(d.ref, {
      commandWire: command.wire, current: d.current, receiptOriginal: receiptOriginal(d, reserve),
      capture() {delivered++;},
    }, publication);
    const refusal = new Error('No Debug receipt construction capacity');
    assert.throws(() => accept(() => {throw refusal;}), error => error === refusal);
    assert.deepEqual(d.lookup(), parked);
    assert.deepEqual(lookupRetainedResume(d, command), {kind: 'unobserved'});
    const exec = DatabaseSync.prototype.exec;
    let injected = false;
    DatabaseSync.prototype.exec = function(sql) {
      if (sql === 'COMMIT' && !injected) {
        injected = true;
        if (committed) Reflect.apply(exec, this, [sql]);
        throw new Error('DebugResumeCommitReplyLost');
      }
      return Reflect.apply(exec, this, [sql]);
    };
    try {
      assert.throws(() => accept(bytes => {reserved = bytes;}),
        {code: 'ClientRunDebugEntryUnknown', outcome: 'unknown'});
    } finally { DatabaseSync.prototype.exec = exec; }
    assert.equal(injected, true);
    assert.ok(reserved > 1024 && reserved < 4 * 1024 * 1024, 'the original command requested finite construction');
    assert.equal(delivered, 0);
    d.advanceClock(23);
    d.f.reopen();
    const retained = d.lookup();
    assert.deepEqual(retained, committed ? {kind: 'resume_accepted', revision: parked.revision + 1,
      commandCid: command.identity, until: 'step', acceptedAt: d.pausedAt + 17} : parked);
    const recovered = lookupRetainedResume(d, command);
    if (committed) {
      assert.deepEqual(recovered.receipt.operation_ref, controlReference(command));
      assert.equal(recovered.receipt.observed_state.control_revision, parked.revision + 1);
      assert.equal(recovered.receipt.observed_state.updated_at, new Date(d.pausedAt + 17).toISOString());
      let exactQuote;
      assert.deepEqual(lookupRetainedResume(d, command, peak => {exactQuote ??= peak;}), recovered);
      let materializations = 0;
      const get = StatementSync.prototype.get;
      StatementSync.prototype.get = function(...args) {
        if (this.sourceSQL.includes('THEN p.receipt_wire') && args[0] > 0) materializations++;
        return Reflect.apply(get, this, args);
      };
      try {
        assert.throws(() => lookupRetainedResume(d, command, peak => {
          if (peak > exactQuote - 1) throw refusal;
        }), error => error === refusal);
        assert.equal(materializations, 0);
      } finally {StatementSync.prototype.get = get;}
      const {self_cid: originalCid, ...body} = recovered.receipt;
      const forged = publication.sealRunEvidence('control_operation_receipt', JSON.stringify({...body,
        observed_state: {...body.observed_state, run_id: 'foreign-run'},
      }), limits);
      const writeReceipt = (wire, identity) => d.f.update(
        'UPDATE client_debug_entry_parks SET receipt_wire = ?, receipt_cid = ? WHERE run_definition_cid = ?',
        wire, identity, d.ref.runDefinitionCid);
      assert.equal(writeReceipt(forged.wire, forged.identity).changes, 1);
      assert.throws(() => lookupRetainedResume(d, command), {code: 'ClientRunDebugEntryCorrupt'});
      assert.equal(writeReceipt(canonicalJson(recovered.receipt), originalCid).changes, 1);
      assert.deepEqual(lookupRetainedResume(d, command), recovered);
      let current = true, selected = false;
      StatementSync.prototype.get = function(...args) {
        const row = Reflect.apply(get, this, args);
        if (this.sourceSQL.includes('THEN p.receipt_wire') && row?.receipt_wire) {
          selected = true;
          current = false;
        }
        return row;
      };
      try {
        assert.throws(() => lookupRetainedResume(d, command, undefined, () => current),
          {code: 'ClientRunDebugEntryDenied'});
        assert.equal(selected, true, 'current authority is revoked after the exact receipt is read');
      } finally {StatementSync.prototype.get = get;}
      assert.deepEqual(accept(), retained, 'an exact replay reads acceptance without issuing a new receipt');
      assert.equal(delivered, 0);
    } else {
      assert.deepEqual(recovered, {kind: 'unobserved'});
    }
    const client = {principalId: 'original', connection: {}, authorize: d.current};
    const owner = installNodeClientDispatchOwner({moon, journal: d.f.journal, control: publication,
      hostConnection: actor => actor.principalId === client.principalId && actor.connection === client.connection});
    const operation = controlReference(command);
    assert.deepEqual(owner.lookupDebugResume(operation, client), committed ? retained : {kind: 'unobserved'});
    assert.deepEqual(owner.lookupDebugResume({...operation, command_cid: cid('e')}, client), {kind: 'unobserved'});
    assert.deepEqual(owner.lookupDebugResume({...operation, operation_id: 'different-operation'}, client),
      {kind: 'unobserved'});
    assert.deepEqual(owner.lookupDebugResume({...operation, accepted_from_revision: parked.revision - 1}, client),
      {kind: 'unobserved'});
    let checks = 0;
    assert.throws(() => owner.lookupDebugResume(operation, {...client, authorize: () => ++checks === 1}),
      {code: 'ClientRunDebugEntryDenied'});
    assert.equal(d.start(), false);
    assert.equal(d.f.readRow().physical_start_reserved, 0);
    if (committed) {
      await assertRecoveredDebugReceiptOnSdk(d, command, recovered, 'client_debug_entry_parks');
      assert.equal(delivered, 0);
      assert.equal(d.f.readRow().physical_start_reserved, 0);
    }
  }
});

test('a lost physical-start ACK never delivers the Debug continuation, even after reopen', async t => {
  for (const committed of [true, false]) {
    const d = await debugEntryFixture(t);
    d.park();
    const command = d.command({interval: {until: 'terminal', guards: null}});
    const accepted = d.resume(command.wire);
    const exec = DatabaseSync.prototype.exec;
    let injected = false;
    DatabaseSync.prototype.exec = function(sql) {
      if (sql === 'COMMIT' && !injected) {
        injected = true;
        if (committed) Reflect.apply(exec, this, [sql]);
        throw new Error('DebugPhysicalStartCommitReplyLost');
      }
      return Reflect.apply(exec, this, [sql]);
    };
    const selected = {commandCid: command.identity, current: d.current};
    try {
      assert.throws(() => d.start(selected), {code: 'ClientRunPhysicalStartUnknown', outcome: 'unknown'});
    } finally {DatabaseSync.prototype.exec = exec;}
    assert.equal(injected, true);
    d.f.reopen();
    assert.deepEqual(d.lookup(), accepted);
    assert.equal(d.f.readRow().physical_start_reserved, committed ? 1 : 0);
    if (committed) assert.equal(d.start(selected), false);
  }
});

test('original submitted content is bound in the same Run acceptance and survives reopen without dispatch', async t => {
  const f = await fixture(t);
  assert.equal(f.accepted.runAdmissionEvidence.submittedIntentCid, moon.clientSubmittedIntentCid(f.intent));
  const row = f.readRow();
  const original = f.read();
  assert.ok(original);
  assert.equal(moon.clientSubmittedIntentCid(original.intent), moon.clientSubmittedIntentCid(f.intent));
  assert.equal(moon.clientSubmittedIntentRequestsCommitStop(original.intent), true);
  assert.deepEqual(JSON.parse(original.referenceWire), f.reference);
  original.assertCurrent();
  assert.equal(Object.isFrozen(original), true);
  assert.deepEqual(f.readRow(), row, 'projection and repeated checks do not change Run, revision or physical claims');
  f.reopen();
  assert.throws(() => original.assertCurrent(), {code: 'ClientRequestJournalClosed'});
  const restored = f.read();
  assert.ok(restored);
  assert.equal(restored.referenceWire, original.referenceWire);
  restored.assertCurrent();
  assert.deepEqual(f.readRow(), row);
});

test('one original submitted-content handle admits each unchanged row once', async t => {
  const f = await fixture(t);
  const counts = {identity: 0, intent: 0, definition: 0};
  const requestControl = {...moon,
    clientRequestAdmitRecord(...args) {
      counts.identity++;
      return Reflect.apply(moon.clientRequestAdmitRecord, moon, args);
    },
    clientSubmittedIntent(...args) {
      counts.intent++;
      return Reflect.apply(moon.clientSubmittedIntent, moon, args);
    },
  };
  const publicationControl = {...publication, admit(name, ...args) {
    if (name === 'run_definition') counts.definition++;
    return Reflect.apply(publication.admit, publication, [name, ...args]);
  }};
  const original = f.read(requestControl, publicationControl);
  assert.deepEqual(counts, {identity: 1, intent: 1, definition: 1});
  original.assertCurrent();
  original.assertCurrent();
  f.update('UPDATE client_submission_epoch_authority SET observed_at=observed_at+1');
  original.assertCurrent();
  assert.deepEqual(counts, {identity: 1, intent: 1, definition: 1},
    'same selected scalar rows reuse the actual admitted originals, not another decode/hash');
  f.read(requestControl, publicationControl).assertCurrent();
  assert.deepEqual(counts, {identity: 2, intent: 2, definition: 2},
    'a distinct original operation has its own initial admission');
  f.mutate(value => {value.authorization = 'changed-valid-authorization-wire';});
  original.assertCurrent();
  assert.deepEqual(counts, {identity: 2, intent: 2, definition: 3},
    'a changed Run row revalidates its Run facts without decoding the unchanged intent');
  assert.deepEqual(Object.keys(f.journal.lookupSubmittedIntent(f.reference, fields, moon)).sort(),
    ['intentCid', 'intentWire', 'outcome', 'phase', 'requestId', 'revision', 'submissionRef'],
    'public submission records do not expose the private admitted intent or row snapshots');
});

for (const entry of ['resolveDefinition', 'admitOrLookupDefinition']) {
  test(`${entry} admits one exact request once before returning its saved Run`, async t => {
    const f = await fixture(t);
    let admissions = 0, issuances = 0;
    const requestControl = {...moon, clientRequestAdmitRecord(...args) {
      admissions++;
      return Reflect.apply(moon.clientRequestAdmitRecord, moon, args);
    }};
    const resolve = original => f.journal[entry](original, {
      namespaceId: fields.namespaceId, lookupExpiresAt: '2099-01-01T00:00:00.000Z',
      issueDefinition() {issuances++; throw new Error('SavedRunMustNotBeReissued');},
    }, requestControl, publication);
    const before = f.readRow();
    const retained = await resolve(f.identity);
    assert.deepEqual(retained.ref, f.accepted.ref);
    assert.equal(admissions, 1, 'one exact request has one Common admission, not repeated stored copies');
    assert.equal(issuances, 0);
    await resolve(f.identity);
    assert.equal(admissions, 2, 'a new public resolution has its own admission');
    const foreign = f.request(cid('b'));
    admissions = 0;
    await assert.rejects(async () => resolve(foreign), {code: 'ClientRequestIntentConflict'});
    assert.equal(admissions, 2, 'distinct requested and saved identities are each admitted once');
    assert.equal(issuances, 0);
    assert.deepEqual(f.readRow(), before, 'resolution and conflict never mutate or reissue the saved Run');
  });
}

test('admit-or-lookup refuses an incomplete request control before issuer callback', async t => {
  const f = await fixture(t);
  let issuances = 0;
  const incomplete = {...moon, clientRequestRelation: undefined};
  await assert.rejects(f.journal.admitOrLookupDefinition(f.identity, {
    namespaceId: 'another-owner', lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    issueDefinition() {issuances++; throw new Error('InvalidControlMustNotReachIssuer');},
  }, incomplete, publication), {code: 'InvalidClientRequestLookup'});
  assert.equal(issuances, 0);
});

for (const [label, sql, expected] of [
  ['intent wire', "UPDATE client_submitted_intents SET intent_wire='{}'", 'ClientSubmittedIntentCorrupt'],
  ['epoch key', "UPDATE client_submission_epoch_authority SET authentication_key='" + '1'.repeat(64) + "'", 'ClientSubmittedIntentCorrupt'],
  ['Run custody', 'UPDATE client_submission_custody SET issued_count=issued_count+1', 'ClientRequestSubmissionCustodyLost'],
  ['intent custody', 'UPDATE client_submitted_intent_custody SET issued_count=issued_count+1', 'ClientSubmittedIntentCustodyLost'],
  ['restart custody', 'UPDATE client_submission_restart_custody SET issued_count=issued_count+1', 'ClientSubmissionRestartCustodyLost'],
]) {
  test(`original submitted-content reuse still observes changed ${label}`, async t => {
    const f = await fixture(t), original = f.read();
    original.assertCurrent();
    f.update(sql);
    assert.throws(() => original.assertCurrent(), {code: expected});
    assert.throws(() => f.read(), {code: expected});
    assert.equal(moon.clientSubmittedIntentRequestsCommitStop(original.intent), true);
  });
}

test('failed original-content observation discards its retained decoded facts', async t => {
  const f = await fixture(t);
  let admissions = 0;
  const requestControl = {...moon, clientSubmittedIntent(...args) {
    admissions++;
    return Reflect.apply(moon.clientSubmittedIntent, moon, args);
  }};
  const original = f.read(requestControl);
  assert.equal(admissions, 1);
  f.mutate(value => {value.submittedIntentCid = cid('f');});
  assert.throws(() => original.assertCurrent(), {code: 'ClientRequestSubmittedIntentMismatch'});
  f.mutate(value => {value.submittedIntentCid = moon.clientSubmittedIntentCid(f.intent);});
  original.assertCurrent();
  assert.equal(admissions, 2, 'after a failed observation the restored bytes require new admission');
});

for (const [label, selected, expected] of [
  ['selected', true, 'ClientRequestSubmittedIntentBindingMissing'],
  ['unselected legacy', false, undefined],
]) {
  test(`original submitted content does not retrofit a ${label} Run from a later intent lookup`, async t => {
    const f = await fixture(t, {selected, link: false});
    const before = f.readRow();
    if (expected === undefined) assert.equal(f.read(), undefined);
    else assert.throws(() => f.read(), {code: expected});
    assert.deepEqual(f.readRow(), before);
  });
}

for (const [label, change, code] of [
  ['missing link', value => {delete value.submittedIntentCid;}, 'ClientRequestSubmittedIntentBindingMissing'],
  ['foreign content', value => {value.submittedIntentCid = cid('f');}, 'ClientRequestSubmittedIntentMismatch'],
]) {
  test(`original submitted content current check refuses ${label} without replacing its original view`, async t => {
    const f = await fixture(t);
    const original = f.read();
    f.mutate(change);
    assert.throws(() => original.assertCurrent(), {code});
    assert.throws(() => f.read(), {code});
    assert.equal(moon.clientSubmittedIntentRequestsCommitStop(original.intent), true);
  });
}

test('original submitted content refuses another namespace or logical request', async t => {
  const f = await fixture(t);
  const before = f.readRow();
  assert.throws(() => f.journal.originalSubmittedIntent(f.identity,
    {...fields, namespaceId: 'another-owner'}, moon, publication), {code: 'ClientRequestSubmittedIntentMismatch'});
  const other = f.request(cid('b'));
  assert.ok(other);
  assert.throws(() => f.journal.originalSubmittedIntent(other, fields, moon, publication),
    {code: 'ClientRequestSubmittedIntentMismatch'});
  assert.deepEqual(f.readRow(), before);
});

test('same-Run original read-only restriction survives material/journal reopen without a dispatch grant', async t => {
  const f = await fixture(t, {selected: false, readOnly: true});
  const before = f.readRow();
  const original = f.read();
  assert.equal(moon.clientSubmittedIntentRequestsReadOnly(original.intent), true);
  assert.equal(moon.clientSubmittedIntentRequestsCommitStop(original.intent), false);
  original.assertCurrent();
  f.reopen();
  assert.throws(() => original.assertCurrent(), {code: 'ClientRequestJournalClosed'});
  const restored = f.read();
  assert.equal(moon.clientSubmittedIntentRequestsReadOnly(restored.intent), true);
  restored.assertCurrent();
  assert.deepEqual(f.readRow(), before);
  f.mutate(value => {delete value.submittedIntentCid;});
  assert.throws(() => restored.assertCurrent(), {code: 'ClientRequestSubmittedIntentBindingMissing'});
  assert.throws(() => f.read(), {code: 'ClientRequestSubmittedIntentBindingMissing'});
});

test('selected Sample reads only the authenticated Debug submission linked to the accepted Run', async t => {
  const f = await fixture(t, {selected: false, debug: true});
  let checks = 0, duringCheck;
  const run = Object.freeze({}), observation = Object.freeze({}), records = Object.freeze({});
  const checkedProfile = Object.freeze({});
  const checked = Object.freeze({profile: checkedProfile,
    controlAdmissionCid: cid('8'), resolvedProfileCid: cid('9'), matchesStart() {return false;}});
  const sampleControl = {...publication, checkClientRelationSampleProfile(...args) {
    checks++;
    assert.deepEqual(args, [run, f.identity, f.accepted.runDefinition, observation,
      canonicalJson(f.reference), records, limits]);
    return duringCheck === undefined ? checked : duringCheck();
  }};
  const sampleRef = (ref = f.accepted.ref) =>
    f.journal.originalSubmittedIntent(f.identity, {...fields, sampleRunRef: ref,
      reserveSampleRead(bytes) {assert.ok(bytes > 0);}}, moon, sampleControl);
  const before = f.readRow();
  assert.equal(f.journal.lookupSubmittedIntent(f.reference, fields, moon).phase, 'preparing',
    'the exact Run is accepted before the outer submission outcome is ready');
  assert.throws(() => sampleRef({...f.accepted.ref, runDefinitionCid: cid('f')}),
    {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.throws(() => sampleRef({...f.accepted.ref, authorityScopeCid: cid('b')}),
    {code: 'ClientRunSampleStartOriginalUnavailable'});
  const original = sampleRef();
  assert.equal(moon.clientSubmittedIntentRequestsDebug(original.intent), true);
  assert.deepEqual(JSON.parse(original.referenceWire), f.reference);
  original.assertCurrent();
  const check = () => original.checkSampleProfile(run, f.accepted.runDefinition, observation, records, limits);
  assert.equal(check().profile, checkedProfile);
  assert.equal(checks, 1);
  assert.deepEqual(f.readRow(), before);
  duringCheck = () => undefined;
  assert.throws(check, {code: 'InvalidClientRunSampleProfileCheck'});
  duringCheck = () => {
    assert.throws(check, {code: 'ClientRunSampleProfileCheckActive'});
    return checked;
  };
  assert.equal(check().profile, checkedProfile);
  duringCheck = () => Promise.reject(new Error('A profile checker must be synchronous'));
  assert.throws(check, {code: 'InvalidClientRunSampleProfileCheck'});
  const changed = {...f.reference.epoch,
    authenticator: `${f.reference.epoch.authenticator[0] === '0' ? '1' : '0'}${f.reference.epoch.authenticator.slice(1)}`};
  duringCheck = () => {
    f.update('UPDATE client_submitted_intents SET epoch_wire = ?', JSON.stringify(changed));
    return checked;
  };
  assert.throws(check, {code: 'ClientSubmittedIntentCorrupt'});
  assert.equal(checks, 5);
  assert.throws(check, {code: 'ClientSubmittedIntentCorrupt'});
  assert.equal(checks, 5, 'a lost original is refused before entering the checker');
  assert.throws(() => original.assertCurrent(), {code: 'ClientSubmittedIntentCorrupt'});
  assert.throws(() => sampleRef(), {code: 'ClientSubmittedIntentCorrupt'});
  assert.deepEqual(f.readRow(), before);
});

test('selected Sample refuses Normal and refuses to retrofit an unlinked Debug intent', async t => {
  const normal = await fixture(t, {selected: false});
  const unlinked = await fixture(t, {selected: false, debug: true, link: false});
  for (const [f, code] of [[normal, 'ClientRunSampleStartOriginalUnavailable'],
    [unlinked, 'ClientRequestSubmittedIntentBindingMissing']]) {
    const before = f.readRow();
    assert.throws(() => f.journal.originalSubmittedIntent(f.identity,
      {...fields, sampleRunRef: f.accepted.ref, reserveSampleRead() {}}, moon, publication), {code});
    assert.deepEqual(f.readRow(), before);
  }
  assert.equal(moon.clientSubmittedIntentRequestsDebug(normal.read().intent), false);
  assert.equal(unlinked.read(), undefined);
});

test('selected Sample funds stored UTF-8 before decoding and refuses growth within the original view', async t => {
  const f = await fixture(t, {selected: false, debug: true});
  f.mutate(value => {value.prepared = '多'.repeat(24);});
  const expected = (() => {
    const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
    try {
      const {reconciliation_state_wire, ...run} = db.prepare('SELECT * FROM client_requests').get();
      const intent = db.prepare('SELECT * FROM client_submitted_intents').get();
      const {authentication_key, observed_at} =
        db.prepare('SELECT * FROM client_submission_epoch_authority').get();
      return [...Object.values(run), ...Object.values(intent), authentication_key, observed_at]
        .filter(value => value !== null).reduce((bytes, value) => bytes + Buffer.byteLength(String(value)), 0);
    } finally {db.close();}
  })();
  const declined = new Error('Original reservation refused');
  let decoded = 0, checked = 0, reservations = 0;
  const selectedControl = {...moon, clientSubmittedIntent(...args) {
    decoded++;
    return moon.clientSubmittedIntent(...args);
  }};
  const selectedPublication = {...publication, checkClientRelationSampleProfile() {
    checked++;
    f.mutate(value => {value.prepared += '多';});
    return Object.freeze({profile: Object.freeze({}),
      controlAdmissionCid: cid('8'), resolvedProfileCid: cid('9'), matchesStart() {return false;}});
  }};
  const read = reserveSampleRead => f.journal.originalSubmittedIntent(f.identity,
    {...fields, sampleRunRef: f.accepted.ref, reserveSampleRead}, selectedControl, selectedPublication);
  assert.throws(() => read(bytes => {
    assert.equal(bytes, expected);
    throw declined;
  }), error => error === declined);
  assert.equal(decoded, 0);
  assert.throws(() => read(bytes => {
    assert.equal(bytes, expected);
    f.mutate(value => {value.prepared += '多';});
  }), {code: 'ClientRunSampleOriginalCapacity'});
  assert.equal(decoded, 0, 'the changed row cannot reach its original decoder');
  const original = read(bytes => {
    reservations++;
    assert.equal(decoded, 0);
    assert.equal(bytes, expected + 3);
  });
  assert.equal(decoded, 1);
  const check = () => original.checkSampleProfile({}, f.accepted.runDefinition, {}, {}, limits);
  assert.throws(check, {code: 'ClientRunSampleOriginalCapacity'});
  assert.throws(check, {code: 'ClientRunSampleOriginalCapacity'});
  assert.equal(checked, 1, 'the oversized replacement was refused before another check');
  assert.equal(reservations, 1, 'freshness checks use the original reserved bound');
});

async function selectedSampleStart(t, journalOptions, {shared, runName, maxArtifacts = 1,
  samplePorts = [cid('7')], inspect = false} = {}) {
  const f = await fixture(t, {selected: false, debug: true, journalOptions, shared, runName, inspect});
  const run = Object.freeze({}), observation = Object.freeze({}), records = Object.freeze({});
  const program = Object.freeze({}), compiled = Object.freeze({}), profile = Object.freeze({});
  // Only this component's native fixture knows which handles represent its
  // committed prefixes. Exercise the actual JS scoped port and SQLite owner.
  const prefixes = new WeakMap();
  const bridge = runtimeCore({...moon,
    clientProgramCheckRelationSampleProfile(owner) {
      assert.equal(owner, run);
      return {$tag: 1, _0: {_0: profile, _1: cid('8'), _2: cid('9'), _3: program, _4: compiled}};
    },
    clientProgramWithRelationSampleJournal(owner, checked, prefix, current, consume) {
      assert.equal(owner, run);
      assert.equal(checked, profile);
      const original = prefixes.get(prefix);
      if (original === undefined || current() !== true) return {$tag: 0, _0: 'RefusedOriginal'};
      const {wires, fundedBytes} = original;
      let active = true;
      try {
        const completed = consume(wires.generation, wires.capture, wires.emission, wires.reference,
          wires.relation, () => active && current(), fundedBytes);
        return completed ? {$tag: 1, _0: undefined} : {$tag: 0, _0: 'VisitorRefused'};
      } finally { active = false; }
    }}).publicationControl;
  const requestControl = {...moon, clientProgramMatchesRequestIdentity(value, request) {
    return value === program && request === f.identity;
  }};
  const publicationControl = {...publication, checkClientRelationSampleProfile(owner, identity, definition,
    actualObservation, referenceWire, actualRecords) {
    assert.equal(owner, run);
    assert.equal(identity, f.identity);
    assert.equal(definition.identity, f.accepted.runDefinition.identity);
    assert.equal(actualObservation, observation);
    assert.equal(referenceWire, canonicalJson(f.reference));
    assert.equal(actualRecords, records);
    const retained = bridge.admit('run_definition', definition.wire, limits);
    const checked = bridge.checkClientRelationSampleProfile(run, identity, retained,
      observation, referenceWire, records, limits);
    return Object.freeze({...checked,
      matchesStart(actualProgram, actualCompiled) {return actualProgram === program && actualCompiled === compiled;},
      matchesAdoption(source, capture) {
        return source.logical_map_cid === cid('5') && samplePorts.includes(source.output_port_id) &&
          capture.max_items === 1 && capture.max_bytes === '1024' && capture.max_artifacts === maxArtifacts &&
          capture.ttl_seconds === 60 && capture.required === false;
      }});
  },
  checkClientCompiledRunOwner(owner, original) {assert.equal(owner, compiled); assert.equal(original, program);},
  checkClientCompiledRunDefinition(owner, definition) {
    assert.equal(owner, compiled);
    assert.equal(definition.identity, f.accepted.runDefinition.identity);
  }};
  f.journal.reserveDispatch(f.identity, fields, requestControl, publicationControl);
  const prepare = () => f.journal.originalSubmittedIntent(f.identity, {...fields,
    sampleRunRef: f.accepted.ref, reserveSampleRead(bytes) {assert.ok(bytes > 0);}},
  requestControl, publicationControl).checkSampleProfile(
    run, f.accepted.runDefinition, observation, records, limits);
  const start = (selection, currentAuthorization = true, debugResume) => f.journal.reservePhysicalStart(f.identity,
    {...fields, ref: f.accepted.ref, currentAuthorization, localExecutionOwner: {program, compiled},
      captureSampleStart: selection, debugResume}, requestControl, publicationControl);
  const selection = (captureRevision, selected = prepare()) =>
    ({program, compiled, startTicket: selected.startTicket, captureRevision});
  const readStart = () => {
    const database = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
    try {
      if (database.prepare("SELECT 1 FROM sqlite_master WHERE name = 'client_relation_sample_starts'").get() === undefined) {
        return undefined;
      }
      return database.prepare('SELECT * FROM client_relation_sample_starts WHERE run_definition_cid = ?')
        .get(f.accepted.ref.runDefinitionCid);
    } finally {database.close();}
  };
  return {f, start, selection, readStart, prepare, committedPrefix(wires, reduction = 0) {
    const prefix = Object.freeze({});
    const metadataLimit = 1024 + 6 * f.accepted.ref.namespaceId.length;
    const fundedBytes = Object.values(wires).reduce((n, wire) => n + Buffer.byteLength(wire, 'utf8'),
      metadataLimit) - reduction;
    prefixes.set(prefix, {wires, fundedBytes});
    return prefix;
  }};
}

test('the checked Debug start seals its original Run revision and profile in the same COMMIT', async t => {
  const {f, start, selection, readStart} = await selectedSampleStart(t);
  const revisions = [];
  const selected = selection(function captureRevision(revision) {
    assert.equal(this, selected);
    assert.equal(f.readRow().physical_start_reserved, 1);
    assert.equal(readStart().start_revision, revision);
    revisions.push(revision);
  });
  assert.throws(() => start({...selected, startTicket: {}}), {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.throws(() => start({...selected, program: {}}), {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.throws(() => start(selection(() => assert.fail('denial cannot hand off')), false),
    {code: 'ClientRunPhysicalStartDenied'});
  assert.equal(readStart(), undefined);
  assert.equal(start(selected), true);
  assert.deepEqual(revisions, [2]);
  assert.deepEqual({...readStart()}, {
    run_definition_cid: f.accepted.ref.runDefinitionCid,
    namespace_id: fields.namespaceId,
    authority_scope_cid: fields.authorityScopeCid,
    submitted_intent_cid: moon.clientSubmittedIntentCid(f.intent),
    control_admission_cid: cid('8'), resolved_profile_cid: cid('9'), start_revision: 2,
  });
  f.update('UPDATE client_requests SET revision = revision + 1');
  f.reopen();
  assert.equal(f.readRow().revision, 3);
  assert.equal(readStart().start_revision, 2);
  assert.throws(() => start(selected), {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.equal(start(selection(() => assert.fail('a start is never reissued'))), false);
  assert.deepEqual(revisions, [2]);
});

test('one physical start commits the original Debug interval and Sample revision, with neither delivered on Unknown', async t => {
  for (const outcome of ['acknowledged', 'lost-committed', 'lost-rolled-back']) {
    const now = Date.parse('2026-11-22T06:00:00Z');
    const {f, start, selection, readStart} = await selectedSampleStart(t, {submissionEpochNow: () => now});
    const ref = f.accepted.ref, current = () => true, expectedRevision = f.readRow().revision;
    const entry = f.journal.parkDebugEntry(f.identity, {ref, expectedRevision, expiresAt: now + 1000, current},
      moon, publication);
    const command = publication.sealRunEvidence('control_command', JSON.stringify({
      version: 'actql-control-command/0.1', operation: 'resume', run_ref: ref,
      expected_control_revision: entry.revision, operation_id: 'resume-sampled-entry',
      interval: {until: 'step', guards: null},
    }), limits);
    const accepted = f.journal.acceptDebugEntryResume(ref, {commandWire: command.wire, current}, publication);
    const before = f.readRow();
    const expected = before.revision + 1;
    const delivered = [];
    const observedCommit = value => {
      assert.equal(readStart().start_revision, expected);
      assert.equal(f.readRow().physical_start_reserved, 1);
      assert.equal(f.readRow().revision, expected);
      delivered.push(value);
    };
    const sample = {...selection(revision => observedCommit(revision)), captureAdoption(writer) {
      assert.equal(typeof writer, 'function');
      observedCommit('writer');
    }};
    const debug = {commandCid: command.identity, current, capture(witness) {observedCommit(witness);}};
    if (outcome === 'acknowledged') {
      assert.equal(start(sample, true, debug), true);
      assert.deepEqual(delivered, [expected, 'writer', {commandCid: command.identity, until: 'step',
        acceptedRevision: accepted.revision, physicalStartRevision: expected}]);
    } else {
      const exec = DatabaseSync.prototype.exec;
      let injected = false;
      DatabaseSync.prototype.exec = function(sql) {
        if (sql !== 'COMMIT' || injected) return Reflect.apply(exec, this, [sql]);
        injected = true;
        if (outcome === 'lost-committed') Reflect.apply(exec, this, [sql]);
        throw new Error('PhysicalStartCommitReplyLost');
      };
      try {
        assert.throws(() => start(sample, true, debug), {code: 'ClientRunPhysicalStartUnknown', outcome: 'unknown'});
      } finally {DatabaseSync.prototype.exec = exec;}
      assert.equal(injected, true);
      assert.deepEqual(delivered, []);
    }
    f.reopen();
    assert.deepEqual(f.journal.lookupDebugEntry(ref, {current}, publication), accepted);
    if (outcome === 'lost-rolled-back') {
      assert.deepEqual(f.readRow(), before);
      assert.equal(readStart(), undefined);
    } else {
      assert.equal(readStart().start_revision, expected);
      assert.equal(start(selection(() => assert.fail('a reopened start cannot hand off')), true,
        {...debug, capture() {assert.fail('retained Debug lookup cannot deliver a continuation');}}), false);
    }
  }
});

async function selectedDebugTask(t, tuning, {retainSample = false, ...sampleOptions} = {}) {
  const {default: support} = await import('./host-journal-schema-support.cjs');
  const now = Date.parse('2026-11-22T06:00:00Z');
  let observedAt = now;
  const options = {maxDatabaseBytes: 4194304,
    primarySchemaLimits: {maxSchemaBytes: 65536, maxSchemaEntries: 128,
      maxSchemaPages: 256, maxWalFrames: 8192},
    primarySchemaSqlSupport: support.sql, submissionEpochNow: () => observedAt, ...tuning};
  const {f, start, selection, prepare, committedPrefix} = await selectedSampleStart(t, options, sampleOptions);
  const ref = f.accepted.ref, current = () => true;
  const command = (revision, operationId, until = 'step') =>
    publication.sealRunEvidence('control_command', JSON.stringify({
      version: 'actql-control-command/0.1', operation: 'resume', run_ref: ref,
      expected_control_revision: revision, operation_id: operationId, interval: {until, guards: null},
    }), limits);
  const paused = f.journal.parkDebugEntry(f.identity, {ref, expectedRevision: f.readRow().revision,
    expiresAt: now + 1000, current}, moon, publication);
  const enter = command(paused.revision, 'enter');
  f.journal.acceptDebugEntryResume(ref, {commandWire: enter.wire, current}, publication);
  const prepared = prepare();
  let sampled, debug, writer;
  const sampleSelection = selection(revision => {sampled = revision;}, prepared);
  if (retainSample) sampleSelection.captureAdoption = handoff => {writer = handoff;};
  assert.equal(start(sampleSelection, true, {
    commandCid: enter.identity, current, capture(witness) {debug = witness;},
  }), true);
  assert.equal(sampled, debug.physicalStartRevision);
  const startRevision = debug.physicalStartRevision, committedGeneration = 7;
  const park = (overrides = {}) => f.journal.parkDebugTask(ref, {startRevision,
    expectedRevision: startRevision, controlRevision: 2, stepId: cid('6'), nextStepId: cid('7'), committedGeneration,
    expiresAt: now + 5000, current, ...overrides}, publication);
  const resume = (original, capture, overrides = {}) => f.journal.acceptDebugTaskResume(ref, {
    commandWire: original.wire, startRevision, current, capture, stepId: cid('6'), nextStepId: cid('7'),
    committedGeneration, ...overrides,
  }, publication);
  const lookup = (original, scope = ref, authorize = current, changes = {}) => {
    const operation = {...controlReference(original), ...changes};
    return f.journal.lookupDebugResume(scope, {operationId: operation.operation_id,
      commandCid: operation.command_cid, acceptedFromRevision: operation.accepted_from_revision,
      current: authorize}, publication);
  };
  const adopt = wires => {
    let receipt;
    prepared.withAdoption(committedPrefix(wires), current, ticket => {receipt = writer(ticket);});
    return receipt;
  };
  return {f, ref, current, startRevision, committedGeneration, command, park, resume, lookup, debug, entry: enter, adopt,
    entryDeadline: paused.expiresAt, startedAt: now,
    advanceClock: offset => {observedAt += offset;},
    now: () => new Date(observedAt).toISOString(), expire() {observedAt = now + 5000;}};
}

test('consecutive committed Step pauses share the original Run revision and each resume hands off once', async t => {
  const d = await selectedDebugTask(t);
  const neverWake = () => assert.fail('unacknowledged or retained history must not wake the Driver');
  const base = d.f.readRow();
  assert.throws(() => d.park({controlRevision: 4}), {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.throws(() => d.park({startRevision: d.startRevision - 1}), {code: 'ClientRunDebugEntryOriginalUnavailable'});
  assert.throws(() => d.resume(d.command(d.startRevision, 'unparked'), neverWake),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  let checks = 0;
  assert.throws(() => d.park({current: () => ++checks === 1}), {code: 'ClientRunDebugEntryDenied'});
  assert.deepEqual(d.f.readRow(), base);

  d.advanceClock(11);
  const first = d.park();
  assert.deepEqual(first, {kind: 'parked', revision: d.startRevision + 1,
    controlRevision: 2, stepId: cid('6'), nextStepId: cid('7'), expiresAt: Date.parse('2026-11-22T06:00:05Z'),
    pausedAt: d.startedAt + 11, committedGeneration: d.committedGeneration});
  d.advanceClock(13);
  d.f.reopen();
  assert.deepEqual(d.park(), first, 'the original Step park time survives reopen and retry');
  const live = parked => d.f.journal.debugPauseCurrent(d.ref, {parked, startRevision: d.startRevision, current: d.current});
  assert.equal(live(first), true);
  assert.equal(live({...first, nextStepId: cid('e')}), false);
  assert.equal(live({...first, nextStepId: null}), false);
  assert.throws(() => d.park({nextStepId: cid('e')}), {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.throws(() => d.park({stepId: cid('e')}), {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.throws(() => d.park({committedGeneration: d.committedGeneration + 1}),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.throws(() => d.resume(d.command(d.startRevision, 'old'), neverWake),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.throws(() => d.resume(d.command(first.revision, 'enter'), neverWake),
    {code: 'ClientRunDebugEntryResumeConflict'});

  const step = d.command(first.revision, 'step-2'), wake = [];
  assert.throws(() => d.resume(step, neverWake, {stepId: cid('e')}),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.throws(() => d.resume(step, neverWake, {nextStepId: cid('e')}),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.throws(() => d.resume(step, neverWake, {committedGeneration: d.committedGeneration + 1}),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.equal(d.f.readRow().revision, first.revision);
  const adopted = d.resume(step, witness => {
    assert.equal(d.f.readRow().revision, first.revision + 1);
    wake.push(witness);
  });
  assert.deepEqual(wake, [{kind: 'resume_accepted', revision: first.revision + 1, controlRevision: 2,
    stepId: first.stepId, nextStepId: first.nextStepId, commandCid: step.identity, until: 'step', committedGeneration: d.committedGeneration,
    acceptedAt: d.startedAt + 24}]);
  assert.equal(adopted, wake[0]);
  assert.throws(() => d.park(), {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.deepEqual(d.resume(step, neverWake), adopted);
  assert.throws(() => d.resume(step, neverWake, {startRevision: d.startRevision + 1}),
    {code: 'ClientRunDebugEntryOriginalUnavailable'});
  assert.throws(() => d.resume(d.command(first.revision, 'step-2', 'terminal'), neverWake),
    {code: 'ClientRunDebugEntryResumeConflict'});
  assert.deepEqual(d.lookup(step, {...d.ref, namespaceId: 'foreign'}), {kind: 'unobserved'});
  assert.throws(() => d.lookup(step, d.ref, () => false), {code: 'ClientRunDebugEntryDenied'});

  const secondBoundary = {expectedRevision: adopted.revision, controlRevision: 4, stepId: cid('7'), nextStepId: null,
    committedGeneration: d.committedGeneration + 1};
  assert.throws(() => d.park({...secondBoundary, committedGeneration: d.committedGeneration}),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  const second = d.park(secondBoundary);
  assert.equal(second.nextStepId, null);
  assert.equal(live(second), true);
  assert.equal(live({...second, nextStepId: cid('8')}), false);
  assert.equal(second.pausedAt, d.startedAt + 24);
  d.advanceClock(12);
  const terminal = d.command(second.revision, 'continue', 'terminal');
  const complete = d.resume(terminal, witness => {
    assert.equal(d.f.readRow().revision, second.revision + 1);
    wake.push(witness);
  }, {stepId: secondBoundary.stepId, nextStepId: null, committedGeneration: secondBoundary.committedGeneration});
  assert.equal(wake.length, 2);
  assert.deepEqual(complete, {kind: 'resume_accepted', revision: first.revision + 3, controlRevision: 4,
    stepId: second.stepId, nextStepId: null, commandCid: terminal.identity, until: 'terminal',
    committedGeneration: secondBoundary.committedGeneration, acceptedAt: d.startedAt + 36});
  assert.throws(() => d.park(secondBoundary), {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.throws(() => d.park({expectedRevision: complete.revision, controlRevision: 6, stepId: cid('8')}),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  d.f.reopen();
  assert.deepEqual(d.lookup(step), adopted);
  assert.deepEqual(d.lookup(terminal), complete);
  assert.equal(d.lookup(d.entry).commandCid, d.entry.identity, 'entry and later commands share the original lookup');
  assert.deepEqual(d.lookup(step, d.ref, d.current, {command_cid: terminal.identity}), {kind: 'unobserved'});
  assert.deepEqual(d.lookup(step, d.ref, d.current, {accepted_from_revision: second.revision}),
    {kind: 'unobserved'});
});

test('control lookup reads the committed original while another WAL writer holds an update', async t => {
  for (const step of [false, true]) {
    const d = await (step ? selectedDebugTask(t) : debugEntryFixture(t));
    const paused = d.park();
    assert.equal(d.f.journal.debugPauseCurrent(d.ref, {parked: paused, startRevision: d.startRevision ?? 0,
      current: d.current, requireEntryDeadline: true}), !step,
    'Inspect accepts the original entry rule and refuses an explicit later deadline');
    const command = step ? d.command(paused.revision, 'original-step') : d.command();
    let delivered = 0;
    const accepted = step ? d.resume(command, () => {delivered++;}) : d.resume(command.wire);
    d.f.reopen();
    const operation = controlReference(command);
    const original = d.f.readRow();
    const writer = new DatabaseSync(join(d.f.path, 'client-requests.sqlite3'));
    try {
      assert.equal(writer.prepare('PRAGMA journal_mode').get().journal_mode, 'wal');
      writer.exec('BEGIN IMMEDIATE');
      const table = step ? 'client_debug_task_pauses' : 'client_debug_entry_parks';
      const update = writer.prepare(`UPDATE ${table} SET resume_accepted_at = resume_accepted_at + 1
        WHERE run_definition_cid = ?`).run(d.ref.runDefinitionCid);
      assert.equal(update.changes, 1);
      const received = d.f.journal.lookupDebugResume(d.ref, {
        operationId: operation.operation_id, commandCid: operation.command_cid,
        acceptedFromRevision: operation.accepted_from_revision, current: d.current,
      }, publication);
      assert.deepEqual(received, accepted, 'read the prior accepted timestamp, not the uncommitted update');
      assert.equal(writer.isTransaction, true);
    } finally {
      if (writer.isTransaction) writer.exec('ROLLBACK');
      writer.close();
    }
    assert.deepEqual(d.f.readRow(), original);
    assert.equal(delivered, Number(step), 'lookup never delivers a new Driver handoff');
  }
});

test('a lost task Continue COMMIT never hands off, including on reopen and exact retry', async t => {
  for (const committed of [true, false]) {
    const d = await selectedDebugTask(t, undefined, {inspect: true});
    const paused = d.park({expiresAt: d.entryDeadline});
    const command = d.command(paused.revision, 'continue', 'terminal');
    d.advanceClock(27);
    const exec = DatabaseSync.prototype.exec;
    let injected = false;
    const neverWake = () => assert.fail('lost reply or recovered history must not wake the Driver');
    DatabaseSync.prototype.exec = function(sql) {
      if (sql !== 'COMMIT' || injected) return Reflect.apply(exec, this, [sql]);
      injected = true;
      if (committed) Reflect.apply(exec, this, [sql]);
      throw new Error('LiveContinueCommitReplyLost');
    };
    try {
      assert.throws(() => d.resume(command, neverWake, {receiptOriginal: receiptOriginal(d)}),
        {code: 'ClientRunDebugEntryUnknown', outcome: 'unknown'});
    } finally { DatabaseSync.prototype.exec = exec; }
    assert.equal(injected, true);
    d.advanceClock(33);
    d.f.reopen();
    const receipt = d.lookup(command);
    const recovered = lookupRetainedResume(d, command);
    assert.equal(d.f.readRow().revision, paused.revision + Number(committed));
    if (committed) {
      assert.equal(receipt.commandCid, command.identity);
      assert.equal(receipt.acceptedAt, d.startedAt + 27);
      assert.deepEqual(recovered.receipt.operation_ref, controlReference(command));
      assert.equal(recovered.receipt.observed_state.control_revision, receipt.revision);
      assert.equal(recovered.receipt.observed_state.updated_at, new Date(receipt.acceptedAt).toISOString());
      assert.deepEqual(d.resume(command, neverWake, {receiptOriginal: receiptOriginal(d)}), receipt);
      assert.deepEqual(lookupRetainedResume(d, command), recovered);
      await assertRecoveredDebugReceiptOnSdk(d, command, recovered, 'client_debug_task_pauses');
      const beforeCorruption = d.f.readRow();
      for (const [column, foreign, original] of [
        ['namespace_id', 'foreign', d.ref.namespaceId],
        ['authority_scope_cid', cid('e'), d.ref.authorityScopeCid],
        ['submitted_intent_cid', cid('e'), moon.clientSubmittedIntentCid(d.f.intent)],
        ['start_revision', d.startRevision + 1, d.startRevision],
      ]) {
        const update = value => d.f.update(`UPDATE client_relation_sample_starts SET ${column} = ?
          WHERE run_definition_cid = ?`, value, d.ref.runDefinitionCid);
        assert.equal(update(foreign).changes, 1);
        assert.throws(() => d.lookup(command), {code: 'ClientRunDebugEntryCorrupt'}, column);
        assert.throws(() => d.resume(command, neverWake), {code: 'ClientRunDebugEntryCorrupt'}, column);
        assert.deepEqual(d.f.readRow(), beforeCorruption);
        assert.equal(update(original).changes, 1);
        assert.deepEqual(d.lookup(command), receipt);
      }
      assert.equal(d.f.update('DELETE FROM client_relation_sample_starts WHERE run_definition_cid = ?',
        d.ref.runDefinitionCid).changes, 1);
      assert.throws(() => d.lookup(command), {code: 'ClientRunDebugEntryCorrupt'}, 'missing original start');
      assert.throws(() => d.resume(command, neverWake), {code: 'ClientRunDebugEntryCorrupt'}, 'missing original start');
      assert.deepEqual(d.f.readRow(), beforeCorruption);
    } else {
      assert.deepEqual(receipt, {kind: 'unobserved'});
      assert.deepEqual(recovered, {kind: 'unobserved'});
      d.expire();
      assert.deepEqual(d.park({expiresAt: d.entryDeadline}), {kind: 'expired'});
      assert.deepEqual(d.resume(command, neverWake), {kind: 'expired'});
    }
  }
});

test('the live Debug waiter wakes on the original Journal ACK and keeps Done and Next distinct', async t => {
  for (const outcome of ['continued', 'lost', 'core-refused', 'historical',
    'drain-before-park', 'drain-after-park', 'account-denied']) {
    const d = await selectedDebugTask(t, undefined, {inspect: true});
    const owner = {}, setup = {}, profile = {}, account = {};
    let installedAccount = account, actorCurrent = true;
    const authority = {ref: d.ref, principalId: 'original'};
    const abort = new AbortController();
    const otherClient = {principalId: 'original', connection: {}};
    const lookupOwner = installNodeClientDispatchOwner({moon, journal: d.f.journal, control: publication,
      hostConnection: actor => actor.ref.namespaceId === d.ref.namespaceId &&
        actor.ref.authorityScopeCid === d.ref.authorityScopeCid &&
        actor.ref.runDefinitionCid === d.ref.runDefinitionCid &&
        actor.principalId === otherClient.principalId && actor.connection === otherClient.connection});
    const command = d.command(d.startRevision + 1, 'continue', 'terminal');
    const operation = controlReference(command);
    const lookup = authorize => lookupOwner.lookupDebugResume(operation, {...otherClient, authorize});
    let runnable = true, coreResumes = 0;
    const ok = value => ({$tag: 1, _0: value});
    const completedStepId = cid('6'), nextStepId = cid('7');
    const installer = installNodeRelationSampleDebugEntry({
      clientProgramRelationSampleDebugResumeAllowed(actualProfile, actualOwner, actualSetup, admitted,
        principal, site) {
        assert.strictEqual(actualProfile, profile); assert.strictEqual(actualOwner, owner);
        assert.strictEqual(actualSetup, setup); assert.strictEqual(admitted, account);
        assert.equal(principal, 'original'); assert.equal(site, 'local');
        return outcome !== 'account-denied';
      },
      clientProgramAdvanceRelationSampleDebugEntry: () => ok(undefined),
      clientProgramRelationSampleDebugEntryRunnable: () => ok(runnable),
      clientProgramRelationSampleDebugTaskPause(actualProfile, actualOwner, actualSetup, revision) {
        assert.strictEqual(actualProfile, profile); assert.strictEqual(actualOwner, owner);
        assert.strictEqual(actualSetup, setup); assert.equal(revision, d.startRevision);
        return ok({_0: 2, _1: completedStepId, _2: nextStepId, _3: d.committedGeneration});
      },
      clientProgramResumeRelationSampleDebugTask(actualProfile, actualOwner, actualSetup,
        admitted, principal, site, startRevision, controlRevision, stepId, resumedNextStep, generation, step) {
        assert.strictEqual(actualProfile, profile); assert.strictEqual(actualOwner, owner);
        assert.strictEqual(actualSetup, setup); assert.strictEqual(admitted, account);
        assert.equal(principal, 'original'); assert.equal(site, 'local');
        assert.equal(startRevision, d.startRevision); assert.equal(controlRevision, 2);
        assert.equal(stepId, completedStepId); assert.equal(resumedNextStep, nextStepId);
        assert.equal(generation, d.committedGeneration);
        assert.equal(step, false);
        assert.equal(d.f.readRow().revision, d.startRevision + 2, 'the same native COMMIT is visible before Core advances');
        coreResumes++;
        if (outcome === 'core-refused') return {$tag: 0, _0: 'OriginalCoreRefusal'};
        runnable = true;
        return ok(undefined);
      },
    }, () => installedAccount, candidate => candidate === authority, 'local',
    {journal: d.f.journal, control: publication, now: d.now});
    const receiver = installer(setup, owner, authority, profile, abort.signal, cid('5'), d.f.accepted.runDefinition);
    t.after(() => receiver.close());
    receiver.activate(d.debug);
    runnable = false;
    if (outcome === 'drain-before-park' || outcome === 'drain-after-park') {
      const beforePark = outcome === 'drain-before-park';
      if (beforePark) {
        receiver.beginDrain();
        assert.throws(() => receiver.taskControl.waitForResume(setup, abort.signal),
          {message: 'ClientRunDebugEntryHostClosing'});
      } else {
        const wait = receiver.taskControl.waitForResume(setup, abort.signal);
        receiver.beginDrain();
        await assert.rejects(wait, {message: 'ClientRunDebugEntryHostClosing'});
      }
      assert.equal(receiver.observePause(d.current), undefined);
      assert.equal(receiver.taskControl.phase(setup), 'paused');
      assert.equal(coreResumes, 0);
      assert.deepEqual(lookup(d.current), {kind: 'unobserved'});
      assert.equal(d.f.readRow().revision, d.startRevision + 1);
      assert.equal(d.f.readRow().cancellation_requested, 0);
      assert.equal(d.f.readRow().physical_close_confirmed, 0, 'detachment alone owns no physical stop acknowledgement');
      assert.equal(d.park({expiresAt: d.entryDeadline}).stepId, completedStepId);
      receiver.close();
      continue;
    }
    const wait = receiver.taskControl.waitForResume(setup, abort.signal);
    assert.equal(receiver.observePause(() => false), undefined);
    const observation = receiver.observePause(d.current);
    assert.deepEqual(observation, {revision: d.startRevision + 1, completedStepId, nextStepId,
      expiresAt: d.entryDeadline, pausedAt: d.startedAt, committedGeneration: d.committedGeneration});
    if (outcome === 'account-denied') {
      const before = d.f.readRow();
      assert.throws(() => receiver.resumeTask(command.wire, d.current), {code: 'ClientRunDebugEntryDenied'});
      assert.deepEqual(d.f.readRow(), before);
      assert.deepEqual(lookup(d.current), {kind: 'unobserved'});
      assert.deepEqual(receiver.observePause(d.current), observation);
      assert.equal(coreResumes, 0);
      receiver.close();
      await assert.rejects(wait, {message: 'ClientRunDebugEntryOriginalUnavailable'});
      continue;
    }
    assert.throws(() => receiver.resumeTask(d.command(observation.revision - 1, 'stale').wire, d.current),
      {code: 'ClientRunDebugEntryRevisionConflict'});
    assert.equal(coreResumes, 0);
    assert.deepEqual(receiver.observePause(d.current), observation, 'a known revision conflict leaves this pause usable');
    if (outcome === 'continued') {
      for (const lost of ['actor', 'account']) {
        const get = StatementSync.prototype.get;
        let selected = false;
        StatementSync.prototype.get = function(...args) {
          const row = Reflect.apply(get, this, args);
          if (row?.current === 1 && this.sourceSQL.startsWith('SELECT 1 AS current')) {
            selected = true;
            if (lost === 'actor') actorCurrent = false;
            else installedAccount = {};
          }
          return row;
        };
        try {
          assert.throws(() => receiver.observePause(() => actorCurrent), {code: 'ClientRunDebugEntryDenied'});
          assert.equal(selected, true, 'authority changes after the exact SQLite pause row returns');
        } finally {
          StatementSync.prototype.get = get;
          actorCurrent = true;
          installedAccount = account;
        }
        assert.deepEqual(receiver.observePause(d.current), observation);
      }
    }
    assert.throws(() => receiver.resumeTask(command.wire, () => false), {code: 'ClientRunDebugEntryDenied'});
    assert.deepEqual(receiver.observePause(d.current), observation, 'a known denial leaves this pause usable');
    if (outcome === 'continued') {
      const workspace = createLocalResultReadWorkspace({runtime: moon,
        requestMemory: Object.freeze({retainedBytes: 4 * 1024 * 1024, executionBytes: 4 * 1024 * 1024}),
        assertCurrent() {}});
      const request = Object.freeze({ref: d.ref});
      workspace.begin(request);
      try {
        assert.equal(receiver.resumeTask(command.wire, d.current, bytes =>
          workspace.construction(request, bytes)).commandCid, command.identity);
      } finally {workspace.close(request);}
      assert.deepEqual(await workspace.closeAll(), {pending: false});
      assert.deepEqual(lookupRetainedResume(d, command).receipt.operation_ref, operation);
      await wait;
      assert.equal(receiver.taskControl.phase(setup), 'runnable');
      assert.equal(coreResumes, 1);
      assert.equal(receiver.observePause(d.current), undefined);
    } else if (outcome === 'core-refused') {
      assert.throws(() => receiver.resumeTask(command.wire, d.current), {code: 'MoonBitHostFailure'});
      await assert.rejects(wait, {code: 'MoonBitHostFailure'});
      assert.equal(receiver.observePause(d.current), undefined);
      assert.equal(receiver.taskControl.phase(setup), 'paused');
      assert.equal(coreResumes, 1);
      assert.equal(lookup(d.current).commandCid, command.identity);
    } else if (outcome === 'historical') {
      assert.equal(d.resume(command, () => {}).commandCid, command.identity);
      assert.equal(receiver.observePause(d.current), undefined, 'durable consumption hides the in-memory pause');
      assert.throws(() => receiver.resumeTask(command.wire, d.current), {code: 'ClientRunDebugEntryReconciliationRequired'});
      assert.equal(lookup(d.current).commandCid, command.identity);
      assert.equal(coreResumes, 0);
      assert.equal(receiver.taskControl.phase(setup), 'paused');
      receiver.close();
      await assert.rejects(wait, {message: 'ClientRunDebugEntryOriginalUnavailable'});
    } else {
      const exec = DatabaseSync.prototype.exec;
      let injected = false;
      DatabaseSync.prototype.exec = function(sql) {
        const result = Reflect.apply(exec, this, [sql]);
        if (sql === 'COMMIT' && !injected) {injected = true; throw new Error('LostContinueAck');}
        return result;
      };
      try {
        assert.throws(() => receiver.resumeTask(command.wire, d.current),
          {code: 'ClientRunDebugEntryUnknown', outcome: 'unknown'});
      } finally {DatabaseSync.prototype.exec = exec;}
      assert.equal(injected, true);
      assert.throws(() => lookup(() => false), {code: 'ClientRunDebugEntryDenied'});
      assert.equal(lookup(d.current).commandCid, command.identity);
      assert.equal(receiver.observePause(d.current), undefined, 'a consumed durable pause is no longer actionable');
      assert.throws(() => receiver.resumeTask(command.wire, () => false), {code: 'ClientRunDebugEntryDenied'});
      assert.throws(() => receiver.resumeTask(command.wire, d.current), {code: 'ClientRunDebugEntryReconciliationRequired'});
      assert.equal(coreResumes, 0);
      assert.equal(receiver.taskControl.phase(setup), 'paused');
      receiver.close();
      await assert.rejects(wait, {message: 'ClientRunDebugEntryOriginalUnavailable'});
    }
  }
});

test('public Resume returns the funded original receipt with one live handoff over Local and HTTP', async t => {
  for (const [transport, outcome] of [['local', 'accepted'], ['http', 'accepted'],
    ['local', 'driver-refused'], ['http', 'lost']]) {
    const d = await selectedDebugTask(t, undefined, {inspect: true});
    const authority = {ref: d.ref, principalId: 'original'};
    const owner = {}, setup = {}, profile = {}, account = {};
    const abort = new AbortController();
    let handoffs = 0, lookups = 0, commands = 0, charged = 0;
    const ok = value => ({$tag: 1, _0: value});
    const install = installNodeRelationSampleDebugEntry({
      clientProgramAdvanceRelationSampleDebugEntry: () => ok(undefined),
      clientProgramRelationSampleDebugEntryRunnable: () => ok(false),
      clientProgramRelationSampleDebugResumeAllowed: () => true,
      clientProgramRelationSampleDebugTaskPause: () =>
        ok({_0: 2, _1: cid('6'), _2: cid('7'), _3: d.committedGeneration}),
      clientProgramResumeRelationSampleDebugTask() {
        ++handoffs;
        return outcome === 'driver-refused' ? {$tag: 0, _0: 'OriginalCoreRefusal'} : ok(undefined);
      },
    }, () => account, selected => selected === authority, 'local',
    {journal: d.f.journal, control: publication, now: d.now});
    const receiver = install(setup, owner, authority, profile, abort.signal, cid('5'), d.f.accepted.runDefinition);
    receiver.activate(d.debug);
    const wait = receiver.taskControl.waitForResume(setup, abort.signal);
    void wait.catch(() => {});
    t.after(() => receiver.close());
    const original = d.f.readRow();
    const command = d.command(original.revision, 'public-original-step', 'step');
    const operation = controlReference(command);
    let mayResume = false;
    const workspace = createLocalResultReadWorkspace({runtime: moon,
      requestMemory: Object.freeze({retainedBytes: 4 * 1024 * 1024, executionBytes: 4 * 1024 * 1024}),
      assertCurrent() {}});
    const matches = selected => selected.principalId === 'original' &&
      selected.ref.runDefinitionCid === d.ref.runDefinitionCid;
    const dispatcher = installNodeClientDispatchOwner({moon, journal: d.f.journal, control: publication,
      hostConnection: matches});
    const read = installClientControlOperationLookup({
      authorize: matches,
      authorizeResume: request => matches(request) && mayResume,
      resumeOriginal(ref, actor, wire) {
        assert.deepEqual(ref, d.ref);
        assert.equal(wire, command.wire);
        ++commands;
        return receiver.resumeTask(wire, actor.authorize, peak => {
          actor.reserve(peak);
          ++charged;
        });
      },
      lookupOriginal(...args) {++lookups; return dispatcher.lookupDebugResume(...args);},
      readWorkspace: workspace,
    });
    const operations = {authenticate: () => 'original', authorizeConnection: () => true,
      negotiate: () => ({version: 'actql-client-host/0.1', mode: 'local', owner: 'local', durability: 'volatile',
        scopeRef: d.ref.authorityScopeCid, capabilities: [], limits: {maxReadWireBytes: 65536,
          maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
          maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}}),
      attach: ({ref}) => ({ref, durability: 'volatile', revision: original.revision}),
      resumeRun: read, lookupControlOperation: read};
    let client, server;
    try {
      if (transport === 'http') {
        server = createServer(createClientHttpHandler({...operations, loopbackHttp: true,
          prepareRequest: (_operation, body) =>
            ({body, bindRequest() {}, finish() {}, beforeReply() {}})}));
        await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
        client = await connect({mode: 'local', owner: 'local', token: 'fixture',
          endpoint: 'http://127.0.0.1:' + server.address().port + '/'});
      } else {
        const ingress = createNodeInProcessClientHost({...operations, maxRowBytes: 1024});
        client = await connectInProcess({mode: 'local', owner: 'local'}, ingress);
      }
      const run = await client.attach(d.ref);
      const wire = await run.prepareResume({operationId: operation.operation_id,
        expectedRevision: operation.accepted_from_revision, until: 'step'});
      assert.deepEqual(wire, JSON.parse(command.wire));
      await assert.rejects(run.resume({...wire, self_cid: cid('e')}), {code: 'InvalidRunControlCommand'});
      await assert.rejects(run.resume(wire), {code: 'RunObservationAccessDenied'});
      assert.deepEqual(d.f.readRow(), original);
      assert.equal(commands, 0);
      mayResume = true;
      let outcomeView, injected = false;
      const exec = DatabaseSync.prototype.exec;
      if (outcome === 'lost') DatabaseSync.prototype.exec = function(sql) {
        const result = Reflect.apply(exec, this, [sql]);
        if (!injected && sql === 'COMMIT') {
          injected = true;
          throw new Error('PublicResumeCommitReplyLost');
        }
        return result;
      };
      try {outcomeView = await run.resume(wire);}
      finally {DatabaseSync.prototype.exec = exec;}
      assert.equal(d.f.readRow().revision, original.revision + 1);
      assert.equal(charged, 1);
      if (outcome === 'lost') {
        assert.equal(injected, true);
        assert.deepEqual(outcomeView, {state: 'unknown', reason: 'control_acceptance_unknown'});
        assert.equal(lookups, 0, 'the mutation does not reconcile an ambiguous COMMIT on its own');
        assert.equal(handoffs, 0);
      } else {
        assert.equal(lookups, 1);
        assert.equal(handoffs, 1);
        assert.equal(outcomeView.state, 'found');
        assert.equal(outcomeView.receipt.outcome, 'accepted');
        if (outcome === 'driver-refused') await assert.rejects(wait, {code: 'MoonBitHostFailure'});
        else await wait;
      }
      mayResume = false;
      const recovered = await run.lookupControlOperation(operation);
      assert.equal(recovered.state, 'found');
      assert.deepEqual(recovered.receipt.operation_ref, operation);
      if (outcome !== 'lost') assert.deepEqual(recovered, outcomeView);
      assert.equal(commands, 1, 'lookup does not resend the operation');
      assert.equal(handoffs, outcome === 'lost' ? 0 : 1);
    } finally {
      receiver.close();
      await client?.close();
      if (server) {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      }
      assert.deepEqual(await workspace.closeAll(), {pending: false});
    }
  }
});

test('task pause history uses the Journal row limit and retires with its original Run', async t => {
  const d = await selectedDebugTask(t, {maxRecords: 2});
  const first = d.park();
  const firstCommand = d.command(first.revision, 'step-2');
  const next = d.resume(firstCommand, () => {});
  const second = d.park({expectedRevision: next.revision, controlRevision: 4, stepId: cid('7'),
    committedGeneration: d.committedGeneration + 1});
  const nextCommand = d.command(second.revision, 'step-3');
  const beyond = d.resume(nextCommand, () => {}, {stepId: second.stepId, nextStepId: second.nextStepId,
    committedGeneration: second.committedGeneration});
  const before = d.f.readRow();
  assert.throws(() => d.park({expectedRevision: beyond.revision, controlRevision: 6, stepId: cid('8'),
    committedGeneration: d.committedGeneration + 2}),
    {code: 'ClientRunDebugEntryCapacity'});
  assert.deepEqual(d.f.readRow(), before);
  assert.deepEqual(d.lookup(firstCommand), next);
  assert.deepEqual(d.lookup(nextCommand), beyond);

  const native = new DatabaseSync(join(d.f.path, 'client-requests.sqlite3'));
  try {
    assert.equal(native.prepare('PRAGMA foreign_keys').get().foreign_keys, 1);
    const inspect = table => native.prepare('SELECT count(*) AS n FROM ' + table +
      ' WHERE run_definition_cid = ?').get(d.ref.runDefinitionCid).n;
    assert.equal(inspect('client_debug_task_pauses'), 2);
    assert.equal(native.prepare('DELETE FROM client_requests WHERE run_definition_cid = ?')
      .run(d.ref.runDefinitionCid).changes, 1);
    assert.equal(inspect('client_debug_task_pauses'), 0);
    assert.equal(inspect('client_debug_entry_parks'), 0);
    assert.equal(inspect('client_relation_sample_starts'), 0);
  } finally {native.close();}
  assert.deepEqual(d.lookup(firstCommand), {kind: 'unobserved'});
});

test('the Debug start rechecks a measured original after profile admission and refuses before writing', async t => {
  const {f, start, selection, readStart} = await selectedSampleStart(t);
  const selected = selection(() => assert.fail('stale original cannot hand off'));
  f.mutate(value => {value.prepared += '多';});
  assert.throws(() => start(selected), {code: 'ClientRunSampleOriginalCapacity'});
  assert.equal(f.readRow().physical_start_reserved, 0);
  assert.equal(readStart(), undefined);
});

test('the Debug start admits the final representable revision and refuses exhaustion atomically', async t => {
  for (const revision of [2147483646, 2147483647]) {
    const {f, start, selection, readStart} = await selectedSampleStart(t);
    f.update('UPDATE client_requests SET revision = ?', revision);
    const revisions = [];
    const selected = selection(value => revisions.push(value));
    if (revision === 2147483646) {
      assert.equal(start(selected), true);
      assert.deepEqual(revisions, [2147483647]);
      assert.equal(readStart().start_revision, 2147483647);
    } else {
      assert.throws(() => start(selected), {code: 'ClientRunSampleStartRevisionExhausted'});
      assert.equal(f.readRow().revision, revision);
      assert.equal(f.readRow().physical_start_reserved, 0);
      assert.equal(readStart(), undefined);
      assert.deepEqual(revisions, []);
    }
  }
});

test('the selected schema boundary rolls back a Debug claim when its optional start row is unsupported', async t => {
  const {default: support} = await import('./host-journal-schema-support.cjs');
  const journalOptions = {maxDatabaseBytes: 4194304,
    primarySchemaLimits: {maxSchemaBytes: 65536, maxSchemaEntries: 128,
      maxSchemaPages: 256, maxWalFrames: 8192},
    primarySchemaSqlSupport: support.sql.filter(sql =>
      !sql.startsWith('CREATE TABLE client_relation_sample_starts ('))};
  const {f, start, selection, readStart} = await selectedSampleStart(t, journalOptions);
  const before = f.readRow();
  assert.throws(() => start(selection(() => assert.fail('rolled back start cannot hand off'))),
    {code: 'ClientRunSampleStartOriginalUnavailable'});
  assert.deepEqual(f.readRow(), before);
  assert.equal(readStart(), undefined);
});

test('a lost Debug start COMMIT reply retains the immutable original without issuing a receiver', async t => {
  const {f, start, selection, readStart} = await selectedSampleStart(t);
  const selected = {...selection(() => assert.fail('unknown start cannot hand off')),
    captureAdoption() {assert.fail('unknown start cannot issue a Sample writer');}};
  const exec = DatabaseSync.prototype.exec;
  let injected = false;
  DatabaseSync.prototype.exec = function(sql) {
    const value = Reflect.apply(exec, this, [sql]);
    if (sql === 'COMMIT' && !injected) {injected = true; throw new Error('PhysicalStartCommitReplyLost');}
    return value;
  };
  try {
    assert.throws(() => start(selected), {code: 'ClientRunPhysicalStartUnknown', outcome: 'unknown'});
  } finally { DatabaseSync.prototype.exec = exec; }
  assert.equal(injected, true);
  f.reopen();
  assert.equal(f.readRow().physical_start_reserved, 1);
  assert.equal(readStart().start_revision, 2);
  assert.equal(start(selection(() => assert.fail('a reopened start cannot hand off'))), false);
});

function committedRelationSample(ref, {revision = 2, attempt = '1', generation: committedGeneration = attempt,
  maxArtifacts = 1, stepId = cid('6'), outputPortId = cid('7'), value = 7} = {}) {
  const seal = (name, body) => publication.sealRunEvidence(name, JSON.stringify({
    ...body, version: `actql-${name.replaceAll('_', '-')}/0.1`,
  }), limits);
  const generation = seal('sample_source_generation', {
    run_ref: ref, compiled_plan_cid: cid('4'), logical_map_cid: cid('5'),
    step_id: stepId, output_port_id: outputPortId, carrier: 'relation', carrier_contract_cid: cid('a'),
    producer_occurrence: {kind: 'first_physical_start', start_revision: String(revision), attempt_sequence: attempt},
    committed_generation: committedGeneration,
  });
  const capture = seal('sample_original_capture', {
    source_generation_cid: generation.identity, control_admission_cid: cid('8'), resolved_profile_cid: cid('9'),
    strategy: 'execution_prefix', max_items: 1, max_bytes: '1024', max_artifacts: maxArtifacts,
    ttl_seconds: 60, required: false,
  });
  const relation = {version: 'actql-sample-relation/0.1', kind: 'relation', schema_cid: cid('b'),
    ordering_evidence_cid: null, columns: [{position: 0, name: 'n', value_contract_cid: cid('c'), required: true}],
    rows: [[{presence: 'present', value_contract_cid: cid('c'), value}]]};
  const emission = seal('sample_emission_provenance', {
    original_capture_cid: capture.identity, source_generation_cid: generation.identity,
    relation_prefix_cid: hash(relation), ordering_evidence_cid: null, sampled_items: '1',
    total: {kind: 'exact', value: '1', unit: 'rows', scope_cid: outputPortId, basis_cid: generation.identity},
    completeness: 'complete', truncation: 'not_truncated',
  });
  const reference = seal('sample_reference', {
    run_ref: ref, output_port_id: outputPortId, original_capture_cid: capture.identity,
    emission_provenance_cid: emission.identity,
  });
  return {cid: reference.identity, wires: {generation: generation.wire, capture: capture.wire,
    emission: emission.wire, reference: reference.wire, relation: canonicalJson(relation)}};
}

async function relationSampleWriter(t, journalOptions, options) {
  const {f, start, selection, prepare, committedPrefix} = await selectedSampleStart(t, journalOptions, options);
  const selected = prepare();
  let writer;
  assert.equal(start({...selection(revision => assert.equal(revision, 2), selected),
    captureAdoption(original) {writer = original;}}), true);
  const ref = f.accepted.ref;
  return {f, writer, ref, committedPrefix, withAdoption: selected.withAdoption, prepare,
    adopt(wires, custody, reduction = 0) {
      let result;
      selected.withAdoption(committedPrefix(wires, reduction), custody.current, ticket => {
        result = writer(ticket);
      });
      return result;
    }, lookup(sampleRefCid, custody) {
    return f.journal.lookupRelationSampleAdoption(ref, sampleRefCid, custody, publication);
    }, retire(sampleRefCid, custody) {
      return f.journal.retireRelationSamplePayload(ref, sampleRefCid, custody, publication);
  }};
}

test('Relation Sample adoption retains one exact prefix and stable receipt under its original start', async t => {
  const {default: support} = await import('./host-journal-schema-support.cjs');
  let now = Date.now();
  const {f, adopt, ref, lookup} = await relationSampleWriter(t, {submissionEpochNow: () => now,
    maxDatabaseBytes: 4194304,
    primarySqlLimits: {maxPreparedStatements: 256, maxSqlBytes: 8192, maxTotalSqlBytes: 262144},
    primaryExecutionLimits: {maxParameters: 32, maxParameterBytes: 262144, maxResultRows: 128},
    primarySchemaLimits: {maxSchemaBytes: 65536, maxSchemaEntries: 128,
      maxSchemaPages: 256, maxWalFrames: 8192},
    primarySchemaSqlSupport: support.sql});
  const sample = committedRelationSample(ref);
  const custody = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  assert.throws(() => adopt(sample.wires, {...custody, current: () => false}),
    {code: 'RunHostRelationSampleJournalRejected'});
  assert.throws(() => adopt(sample.wires, {...custody, current: () => Promise.resolve(true)}),
    {code: 'RunHostRelationSampleJournalRejected'});
  assert.throws(() => adopt(sample.wires, custody, 1), {code: 'ClientRelationSampleCapacity'});
  assert.deepEqual(lookup(sample.cid, custody), {kind: 'unobserved'});
  assert.throws(() => adopt(committedRelationSample(ref, {revision: 3}).wires, custody),
    {code: 'ClientRelationSampleOriginalChanged'});
  assert.throws(() => adopt({...sample.wires, relation: sample.wires.relation.replace('"value":7', '"value":8')}, custody),
    {code: 'ClientRelationSampleOriginalChanged'});
  let currentChecks = 0;
  assert.throws(() => adopt(sample.wires, {...custody, current: () => ++currentChecks < 5}),
    {code: 'ClientRelationSampleDenied'});
  assert.deepEqual(lookup(sample.cid, custody), {kind: 'unobserved'}, 'last authority check rolled the insert back');
  const receipt = adopt(sample.wires, custody);
  assert.equal(receipt.kind, 'adopted');
  assert.equal(receipt.sampleRefCid, sample.cid);
  assert.equal(receipt.expiresAt, now + 60_000);
  const database = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    const rows = database.prepare('SELECT * FROM client_relation_sample_adoptions').all();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].relation_wire, sample.wires.relation);
    assert.equal(JSON.parse(rows[0].receipt_wire).self_cid, receipt.receiptCid);
  } finally { database.close(); }
  now += 120_000;
  assert.deepEqual(adopt(sample.wires, custody), receipt, 'an exact retry never refreshes TTL');
  assert.throws(() => adopt(committedRelationSample(ref, {attempt: '2'}).wires, custody),
    {code: 'ClientRelationSampleCapacity'});
  assert.throws(() => adopt(committedRelationSample(ref, {maxArtifacts: 2}).wires, custody),
    {code: 'ClientRelationSampleOriginalChanged'});
  f.reopen();
  assert.deepEqual(lookup(sample.cid, custody), receipt, 'the private reconciliation receipt survives expiry');
  let reserved = false;
  assert.throws(() => lookup(sample.cid, {current: () => false, reserve() {reserved = true;}}),
    {code: 'ClientRelationSampleDenied'});
  assert.equal(reserved, false);
  let readChecks = 0;
  assert.throws(() => lookup(sample.cid, {...custody, current: () => ++readChecks < 4}),
    {code: 'ClientRelationSampleDenied'});
  assert.equal(readChecks, 4);
  assert.deepEqual(f.journal.lookupRelationSampleAdoption({...ref, namespaceId: 'foreign-scope'},
    sample.cid, custody, publication), {kind: 'unobserved'});
});

test('a live Next Sample reads only the retained generation of its exact paused producer', async t => {
  for (const matching of [true, false]) {
    const d = await selectedDebugTask(t, undefined, {retainSample: true});
    const generation = d.committedGeneration;
    const sample = committedRelationSample(d.ref, {revision: d.startRevision,
      attempt: String(matching ? generation : generation - 1)});
    const receipt = d.adopt(sample.wires);
    const parked = d.park({expiresAt: d.startedAt + 120_000});
    d.f.reopen();

    const selection = {compiledPlanCid: cid('4'), logicalMapCid: cid('5'), stepId: cid('6'),
      outputPortId: cid('7'), carrierContractCid: cid('a'), nextStepId: parked.nextStepId, maxBytes: 1024};
    const producer = Object.freeze({stepId: selection.stepId, outputPortId: selection.outputPortId,
      carrierContractCid: selection.carrierContractCid, generation, attemptSequence: generation});
    const debugPause = Object.freeze({parked, startRevision: d.startRevision, producer});
    const reserve = bytes => {assert.ok(bytes > 0);};
    const read = (selected = selection, custody = {}, pause = debugPause) =>
      d.f.journal.readRetainedRelationSample(d.ref, Object.freeze(selected), {
        current: d.current, reserve, debugPause: pause, ...custody,
      }, publication);
    const before = d.f.readRow();
    assert.throws(() => read({...selection, nextStepId: cid('e')}),
      {code: 'ClientRunDebugEntryInvalidSelection'});
    assert.throws(() => read(selection, {current: () => false, reserve() {assert.fail('denied');}}),
      {code: 'ClientRunDebugEntryDenied'});
    assert.throws(() => read(selection, {}, {...debugPause, parked: Object.freeze({...parked,
      committedGeneration: generation + 1})}), {code: 'ClientRunDebugEntryRevisionConflict'});

    d.f.update('UPDATE client_relation_sample_starts SET submitted_intent_cid = ?', cid('e'));
    assert.throws(() => read(), {code: 'ClientRunDebugEntryRevisionConflict'});
    d.f.update('UPDATE client_relation_sample_starts SET submitted_intent_cid = ?', moon.clientSubmittedIntentCid(d.f.intent));

    const original = read();
    if (matching) {
      assert.equal(original.kind, 'available');
      assert.equal(original.source.committed_generation, String(generation));
      assert.deepEqual(original.source.run_ref, d.ref);
      assert.deepEqual(original.relation, JSON.parse(sample.wires.relation));
      assert.deepEqual(original.receipt, receipt);
    } else {
      assert.deepEqual(original, {kind: 'unobserved'});
    }
    assert.deepEqual(read(selection, {debugPause: undefined}).receipt, receipt,
      'a historical Sample read retains its separate semantics');
    assert.deepEqual(d.f.readRow(), before, 'Next read leaves the Run and its live Step revision alone');
    if (!matching) {
      d.advanceClock(60_000);
      assert.equal(read(selection, {debugPause: undefined}).kind, 'expired');
      assert.deepEqual(read(), {kind: 'unobserved'}, 'an expired receipt cannot prove the current producer generation');
    }

    let notices = 0, funded = 0;
    assert.throws(() => read(selection, {reserve(bytes) {
      reserve(bytes);
      if (++funded === 3) {
        assert.equal(d.resume(d.command(parked.revision, 'leave-while-funding'), () => {notices++;}).kind,
          'resume_accepted');
      }
    }}), {code: 'ClientRunDebugEntryRevisionConflict'});
    assert.equal(funded, 3);
    assert.equal(notices, 1, 'only the separate explicit command wakes the Driver');
    assert.throws(() => read(), {code: 'ClientRunDebugEntryRevisionConflict'});
  }
});

test('the installed Next receiver reads two original input generations and checks their individual attempts', async t => {
  const ports = [cid('b'), cid('7')], steps = [cid('c'), cid('6')];
  const d = await selectedDebugTask(t, undefined, {
    retainSample: true, maxArtifacts: 2, samplePorts: ports, inspect: true,
  });
  const expected = steps.map((stepId, i) => ({
    stepId, outputPortId: ports[i], carrierContractCid: cid('a'),
    generation: d.committedGeneration - 1 + i, attemptSequence: i + 2,
  }));
  const rows = expected.map((producer, i) => committedRelationSample(d.ref, {
    revision: d.startRevision, attempt: String(producer.attemptSequence), generation: String(producer.generation),
    stepId: producer.stepId, outputPortId: producer.outputPortId, maxArtifacts: 2, value: i + 1,
  }));
  const receipts = rows.map(row => d.adopt(row.wires));
  d.f.reopen();
  const account = {}, owner = {}, profile = {}, setup = {}, authority = {ref: d.ref, principalId: 'original'};
  const abort = new AbortController();
  let selectedAttempt, selectedIssue, missing = false, allowed = true, readBridgeCalls = 0, resumes = 0;
  const ok = value => ({$tag: 1, _0: value});
  const bridge = {
    clientProgramAdvanceRelationSampleDebugEntry() {return ok(undefined);},
    clientProgramRelationSampleDebugEntryRunnable() {return ok(false);},
    clientProgramRelationSampleDebugTaskPause() {
      return ok({_0: 2, _1: steps[1], _2: cid('7'), _3: d.committedGeneration});
    },
    clientProgramResumeRelationSampleDebugTask() {resumes++; return ok(undefined);},
    clientProgramRelationSampleDebugResumeAllowed() {return true;},
    clientProgramRelationSampleDebugNextInput(policy, original, actual, start, controlRevision,
      pauseGeneration, next, input, work) {
      ++readBridgeCalls;
      assert.deepEqual([policy, original, actual, start, controlRevision, pauseGeneration, next],
        [profile, owner, setup, d.startRevision, 2, d.committedGeneration, cid('7')]);
      if (selectedIssue !== undefined) return {$tag: 0, _0: selectedIssue};
      assert.ok(work === 255 || work === 256);
      if (work === 255) return {$tag: 0, _0: 'capacity'};
      if (missing) return ok(undefined);
      const producer = expected[input];
      return ok({_0: producer.stepId, _1: producer.outputPortId, _2: producer.carrierContractCid,
        _3: producer.generation, _4: selectedAttempt ?? producer.attemptSequence});
    },
  };
  let retainedSampleReads = 0;
  const journal = {...d.f.journal, readRetainedRelationSample(...args) {
    retainedSampleReads++;
    return d.f.journal.readRetainedRelationSample(...args);
  }};
  const receive = installNodeRelationSampleDebugEntry(bridge, () => account, value => value === authority, 'local',
    {journal, control: publication, now: d.now});
  const controller = receive(setup, owner, authority, profile, abort.signal, cid('5'));
  controller.activate(d.debug);
  const waiting = controller.taskControl.waitForResume(setup, abort.signal);
  t.after(async () => {controller.close(); await waiting.catch(() => {});});
  const before = d.f.readRow();
  const park = controller.observePause(() => allowed);
  const inspectPark = controller.observePause(() => allowed, true);
  assert.deepEqual(inspectPark, {...park, logicalMapCid: cid('5'), startRevision: d.startRevision, controlRevision: 2,
    runRef: d.ref, ttlPolicy: 'original_debug_entry_deadline'});
  const read = (inputOrdinal, afterBinding = () => {}) => controller.readNextSample(Object.freeze({
    revision: park.revision, nextStepId: park.nextStepId, inputOrdinal,
    compiledPlanCid: cid('4'), logicalMapCid: cid('5'), maxWork: 256, maxBytes: 1024,
  }), () => allowed, bytes => {assert.ok(bytes >= 1);}, producer => {
    const same = producer.stepId === steps[inputOrdinal] && producer.outputPortId === ports[inputOrdinal];
    if (same) afterBinding();
    return same;
  });
  for (const index of [0, 1]) {
    const stored = read(index);
    assert.equal(stored.kind, 'available');
    assert.deepEqual(stored.source.run_ref, d.ref);
    assert.equal(stored.source.committed_generation, String(expected[index].generation));
    assert.deepEqual(stored.source.producer_occurrence, {kind: 'first_physical_start',
      start_revision: String(d.startRevision), attempt_sequence: String(expected[index].attemptSequence)});
    assert.deepEqual(stored.relation, JSON.parse(rows[index].wires.relation));
    assert.deepEqual(stored.receipt, receipts[index]);
  }
  selectedAttempt = 4;
  assert.deepEqual(read(0), {kind: 'unobserved'}, 'the exact producer and generation cannot hide a foreign attempt');
  selectedAttempt = undefined;
  allowed = false;
  assert.throws(() => read(0), {code: 'ClientRelationSampleDenied'});
  assert.equal(readBridgeCalls, 3);
  allowed = true;
  assert.deepEqual(d.f.readRow(), before);
  // Use the actual current Account evaluator on the public SDK request, with
  // the installed Next reader and SQLite owner above. The checked Core
  // bridge is independently exercised against the actual managed output.
  const viewer = {siteKey: 'local'};
  const configure = (run, sample, control) => {
    const read = (resource, enabled) => JSON.parse(sourceReadAccountConfiguration({
      connection: 'local', resource, entryId: resource, outcome: enabled ? 'allow' : 'deny',
    })).entries[0];
    const resume = {...read('runs', control), operation: {any_of: ['resume']}};
    viewer.accountConfiguration = canonicalJson({version: 'actql-execution-account-config/0.1',
      account_id: 'local-account', entries: [read('run', run), resume, read('sample', sample)]});
  };
  configure(true, true, false);
  const viewerReads = createLocalReadAuthorizations({moon, authorization: viewer,
    principalId: 'viewer', namespaceId: d.ref.namespaceId, authorityScopeCid: d.ref.authorityScopeCid});
  const inputPorts = [cid('d'), cid('e')];
  const planWire = JSON.stringify({logical_map: {compiled_plan_cid: cid('4'), self_cid: cid('5'), steps: [
    ...expected.map(producer => ({step_id: producer.stepId, ports: [{
      port_id: producer.outputPortId, role: 'output', carrier: 'relation', carrier_contract_cid: cid('a'),
    }]})),
    {step_id: park.nextStepId, ports: inputPorts.map((port_id, port_ordinal) => ({
      port_id, port_ordinal, role: 'input', carrier: 'relation', carrier_contract_cid: cid('a'),
      source: {kind: 'stage_input', stage_ordinal: 2, input_port_ordinal: port_ordinal},
    }))},
  ]}});
  const original = {definitionWire: d.f.accepted.runDefinition.wire, programDefinitionCid: cid('2'),
    admissionEvidenceWire: JSON.stringify({logicalPlanOriginal: {planViewWire: planWire}})};
  let probes = 0;
  const admitted = new Set();
  const runSample = installClientRunSample({
    authorize(request) {
      const access = {principalId: request.principalId, indexKey: request.ref};
      return viewerReads.runImmediate(access, undefined) === true && viewerReads.sampleReadImmediate(access) === true;
    },
    probeOriginal(ref) {
      probes++;
      return ref.runDefinitionCid === d.ref.runDefinitionCid ? {storedBytes: 1024} : undefined;
    },
    lookupOriginal() {return original;},
    readRetained() {assert.fail('an active Next must not fall through to the Saved reader');},
    readNextRetained(request, selected, current, reserve, bind) {
      assert.deepEqual(request.ref, d.ref);
      return controller.readNextSample(selected, current, reserve, bind);
    },
    observeNext(_request, current) {return controller.observePause(current);},
    readWorkspace: {begin(request) {admitted.add(request);},
      metadata(request, bytes) {assert.ok(admitted.has(request) && bytes > 0);},
      close(request) {assert.ok(admitted.delete(request));}},
    control: {admit(name, wire) {assert.equal(name, 'run_definition'); assert.equal(wire, original.definitionWire);
      return {identity: d.ref.runDefinitionCid};},
    readStoredRunPlanOriginal(saved) {assert.equal(saved.planViewWire, planWire); return planWire;}},
  });
  const inspectWorkspace = createLocalResultReadWorkspace({runtime: moon,
    requestMemory: Object.freeze({retainedBytes: 4 * 1024 * 1024, executionBytes: 4 * 1024 * 1024}),
    assertCurrent() {}});
  let afterProjection, inspectFailure, staleSnapshot = false, inspected = 0;
  const runId = JSON.parse(original.definitionWire).run_id;
  const runReader = ({principalId, ref}) =>
    viewerReads.runImmediate({principalId, indexKey: ref}, undefined) === true;
  const inspect = installClientRunInspect({authorize: runReader, authorizeCurrent: runReader,
    lookupOriginal: ref => d.f.journal.lookupRunDefinition(ref, moon, publication),
    async observeOwners({ref}) {
      const row = d.f.readRow();
      const snapshot = {value: {version: 'actql-run-state/0.1', run_id: runId, status: 'running',
        revision: row.state_revision, updated_at: d.now(), next_action: {kind: 'none'},
        result_available: false, result_availability: {}, control: {
          revision: staleSnapshot ? d.startRevision : row.revision,
          cancellation_requested: row.cancellation_requested === 1, physical_stop: 'unknown',
        }}};
      const owner = {kind: 'run', scopeCid: ref.authorityScopeCid, streamCid: ref.runDefinitionCid};
      return {owners: [{kind: 'observed', owner: 'run', snapshot}], revisionVector: [{owner,
        snapshotCid: hash({version: 'actql-owner-snapshot/0.1', ref, owner, snapshot})}]};
    },
    control: {...publication, readCurrentClientRunView(...args) {
      const wire = publication.readCurrentClientRunView(...args);
      afterProjection?.();
      return wire;
    }},
    observeDebugPause(request, current) {
      assert.deepEqual(request.ref, d.ref);
      return controller.observePause(current, true);
    },
    readWorkspace: inspectWorkspace,
  });
  const ingress = createNodeInProcessClientHost({authenticate: () => 'viewer',
    authorizeConnection: () => true,
    negotiate: () => ({version: 'actql-client-host/0.1', mode: 'local', owner: 'local', durability: 'volatile',
      scopeRef: d.ref.authorityScopeCid, capabilities: [], limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10,
        maxBatchRetainedValueBytes: 2048}}),
    maxRowBytes: 1024, attach: ({ref}) => ({ref, durability: 'volatile', revision: park.revision}), runSample,
    async inspectRun(request, consume) {
      try {return await inspect(request, value => {inspected++; return consume(value);});}
      catch (error) {inspectFailure = error.code; throw error;}
    }});
  const client = await connectInProcess({mode: 'local', owner: 'local'}, ingress);
  let closed = false;
  t.after(async () => {
    if (!closed) {
      await client.close();
      await inspectWorkspace.closeAll();
    }
  });
  const execution = await client.attach(d.ref);
  const publicRead = (port, maxNodes = 256, nextRevision = park.revision) => execution.sample({
    step: {by: 'id', step_id: park.nextStepId}, role: 'input', input_port_id: port,
  }, {nextRevision, maxNodes});
  for (const rights of [[false, true, false], [true, false, true]]) {
    configure(...rights);
    assert.deepEqual(await publicRead(inputPorts[0]), {state: 'forbidden'});
  }
  assert.equal(probes, 0, 'both permissions are required before probing Sample existence');
  configure(true, true, false);
  const inspectedRun = await execution.inspect();
  assert.deepEqual(inspectedRun.run_ref, d.ref);
  assert.equal(inspectedRun.compiled_plan_cid, cid('4'));
  assert.equal(inspectedRun.logical_map_cid, cid('5'));
  assert.equal(inspectedRun.run_state.status, 'paused');
  assert.equal(inspectedRun.run_state.control_revision, park.revision);
  assert.equal(inspectedRun.run_state.boundary.position, 'before');
  assert.equal(inspectedRun.run_state.boundary.step_id, park.nextStepId);
  assert.deepEqual(inspectedRun.available_operations, ['inspect']);
  assert.equal(inspectedRun.capabilities.durable_control, false);
  assert.deepEqual(inspectedRun.capabilities.sample_capture, []);
  const sampleReadsBeforeRefusal = retainedSampleReads;
  staleSnapshot = true;
  await assert.rejects(execution.inspect(), {code: 'ClientHostFailure'});
  assert.equal(inspectFailure, 'RunHostInspectRejected');
  staleSnapshot = false;
  assert.equal(inspected, 1);
  assert.equal(retainedSampleReads, sampleReadsBeforeRefusal);
  for (const index of [0, 1]) {
    const view = await publicRead(inputPorts[index]);
    assert.equal(view.state, 'available');
    assert.equal(view.source.port_id, inputPorts[index]);
    assert.deepEqual(view.source.producer,
      {kind: 'logical_output', step_id: steps[index], output_port_id: ports[index]});
    assert.deepEqual(view.data, JSON.parse(rows[index].wires.relation));
  }
  assert.equal(retainedSampleReads - sampleReadsBeforeRefusal, 2,
    'both public inputs read their own retained Sample');
  const foreign = await client.attach({...d.ref, runDefinitionCid: cid('f')});
  assert.deepEqual(await foreign.sample({step: {by: 'id', step_id: park.nextStepId}, role: 'input',
    input_port_id: inputPorts[0]}, {nextRevision: park.revision}), {state: 'unavailable', reason: 'not_retained'});
  selectedAttempt = 4;
  assert.deepEqual(await publicRead(inputPorts[0]), {state: 'unavailable', reason: 'not_retained'});
  selectedAttempt = undefined;
  assert.equal(readBridgeCalls, 6);
  assert.deepEqual(await publicRead(inputPorts[0], 255), {state: 'unavailable', reason: 'capacity'});
  await assert.rejects(publicRead(inputPorts[0], 255, park.revision - 1),
    {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.equal(readBridgeCalls, 7, 'stale revisions are refused before the work check');
  missing = true;
  assert.deepEqual(await publicRead(inputPorts[0]), {state: 'unavailable', reason: 'not_retained'});
  missing = false;
  selectedIssue = 'foreign';
  assert.throws(() => read(0), {code: 'ForeignClientRunSampleOutput'});
  selectedIssue = undefined;
  assert.equal(readBridgeCalls, 9);
  assert.equal(admitted.size, 0);
  const command = d.command(park.revision, 'next-input-resume');
  afterProjection = () => {
    assert.throws(() => read(0, () => {
      assert.equal(controller.resumeTask(command.wire, () => allowed).kind, 'resume_accepted');
    }), {code: 'ClientRunDebugEntryRevisionConflict'}, 'a binder that resumes this pause cannot continue the Sample read');
  };
  const samplesBeforeResume = retainedSampleReads;
  await assert.rejects(execution.inspect(), {code: 'ClientOperationUnavailable'});
  assert.equal(inspectFailure, 'ClientOperationUnavailable');
  await waiting;
  assert.equal(resumes, 1);
  assert.equal(inspected, 1, 'the consumed original cannot reach the Inspect sink');
  assert.equal(controller.observePause(() => allowed, true), undefined);
  assert.throws(() => read(0), {code: 'ClientRunDebugEntryRevisionConflict'});
  await assert.rejects(publicRead(inputPorts[0]), {code: 'ClientRunDebugEntryRevisionConflict'});
  assert.equal(retainedSampleReads, samplesBeforeResume, 'the stale pause cannot read Sample custody');
  assert.equal(readBridgeCalls, 10);
  assert.equal(admitted.size, 0);
  await client.close();
  assert.deepEqual(await inspectWorkspace.closeAll(), {pending: false});
  closed = true;
});

test('cold Relation Sample read checks current access, bound evidence and the original receipt', async t => {
  let now = Date.now();
  const {f, ref, adopt, retire} = await relationSampleWriter(t, {submissionEpochNow: () => now});
  const sample = committedRelationSample(ref);
  const access = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  const receipt = adopt(sample.wires, access);
  f.reopen();

  const selection = {sampleRefCid: sample.cid, compiledPlanCid: cid('4'), logicalMapCid: cid('5'),
    stepId: cid('6'), outputPortId: cid('7'), carrierContractCid: cid('a'), maxBytes: 1024};
  const read = (selected = selection, custody = access, run = ref, control = publication) =>
    f.journal.readRetainedRelationSample(run, selected, custody, control);
  const update = (set, ...arguments_) => f.update(
    `UPDATE client_relation_sample_adoptions SET ${set} WHERE sample_ref_cid = ?`, ...arguments_, sample.cid);

  const byPort = {...selection, sampleRefCid: undefined};
  for (const sampleRefCid of [sample.cid, cid('d'), undefined]) {
    assert.throws(() => read({...selection, sampleRefCid}, {
      current: () => false, reserve() {assert.fail('denied access may not reserve an extent');},
    }), {code: 'ClientRelationSampleDenied'});
  }
  assert.deepEqual(read(selection, access, {...ref, namespaceId: 'foreign-scope'}), {kind: 'unobserved'});

  let live = true;
  assert.throws(() => read(selection, {
    current: () => live, reserve() {live = false;},
  }), {code: 'ClientRelationSampleDenied'});
  let funded = 0;
  const {kind, source, relation, receipt: originalReceipt} = read(selection, {
    current: () => true, reserve(bytes) {funded += bytes;},
  });
  assert.equal(kind, 'available');
  assert.deepEqual(source.run_ref, ref);
  assert.equal(source.output_port_id, selection.outputPortId);
  assert.deepEqual(relation, JSON.parse(sample.wires.relation));
  assert.deepEqual(originalReceipt, receipt);
  assert.deepEqual(read(byPort).receipt, receipt, 'the exact port selects its original receipt after reopening');
  const writer = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    writer.exec('BEGIN IMMEDIATE');
    writer.prepare('UPDATE client_relation_sample_adoptions SET relation_wire = ? WHERE sample_ref_cid = ?')
      .run(sample.wires.relation.replace('"value":7', '"value":8'), sample.cid);
    const observed = read(byPort);
    assert.deepEqual(observed.receipt, receipt, 'another writer cannot hide this committed receipt');
    assert.deepEqual(observed.relation, JSON.parse(sample.wires.relation));
    writer.exec('ROLLBACK');
  } finally {writer.close();}
  assert.deepEqual(read({...byPort, outputPortId: cid('e')}), {kind: 'unobserved'});
  assert.deepEqual(read(byPort, access, {...ref, namespaceId: 'foreign-scope'}), {kind: 'unobserved'});
  let reserves = 0;
  assert.throws(() => read(byPort, {...access, reserve(bytes) {
    assert.ok(bytes > 0);
    if (++reserves === 2) update('original_capture_cid = ?', cid('e'));
  }}), {code: 'ClientRelationSampleOriginalChanged'},
  'the second original proof catches a changed association after funding');
  update('original_capture_cid = ?', JSON.parse(sample.wires.capture).self_cid);
  let storedReceiptBytes;
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    storedReceiptBytes = db.prepare('SELECT length(CAST(receipt_wire AS BLOB)) AS bytes FROM client_relation_sample_adoptions WHERE sample_ref_cid = ?')
      .get(sample.cid).bytes;
  } finally {db.close();}
  assert.equal(funded, storedReceiptBytes + Object.values(sample.wires).reduce((sum, wire) => sum + Buffer.byteLength(wire), 0));
  assert.throws(() => read({...selection, outputPortId: cid('e')}), {code: 'ClientRelationSampleOriginalChanged'});
  update('relation_wire = ?', sample.wires.relation.replace('"value":7', '"value":8'));
  assert.throws(() => read(), {code: 'ClientRelationSampleOriginalChanged'});
  update('source_generation_wire = NULL, capture_wire = NULL, emission_wire = NULL, reference_wire = NULL, relation_wire = NULL');
  assert.throws(() => read(), {code: 'ClientRelationSampleInvalidOriginal'});
  assert.throws(() => read(byPort), {code: 'ClientRelationSampleInvalidOriginal'},
    'the same future-expiry row without payload is corrupt even with a proven output association');
  update('source_generation_wire = ?, capture_wire = ?, emission_wire = ?, reference_wire = ?, relation_wire = ?',
    sample.wires.generation, sample.wires.capture, sample.wires.emission, sample.wires.reference, sample.wires.relation);

  // The clock can reach expiry while the read tariff is admitted. Only the
  // unchanged original receipt is materialized in the subsequent transaction.
  const admittedAfterQuote = [];
  const trackAdmission = (name, ...arguments_) => {
    admittedAfterQuote.push(name);
    return publication.admitRunEvidence(name, ...arguments_);
  };
  assert.deepEqual(read(selection, {current: () => true, reserve() {now = receipt.expiresAt;}},
    ref, {admitRunEvidence: trackAdmission}), {kind: 'expired', sampleRefCid: sample.cid});
  assert.deepEqual(admittedAfterQuote, ['sample_adoption_receipt']);

  // Even before retirement, expiry only loads the receipt, with no step or
  // port status inferred from it. The one-byte payload limit cannot admit
  // the actual retained Relation.
  now = receipt.expiresAt;
  const admitted = [];
  const admitRunEvidence = (...arguments_) => {
    admitted.push(arguments_[0]);
    return publication.admitRunEvidence(...arguments_);
  };
  assert.deepEqual(read({...selection, maxBytes: 1}, {current: () => true,
    reserve(bytes) {assert.equal(bytes, storedReceiptBytes);}}, ref, {admitRunEvidence}),
  {kind: 'expired', sampleRefCid: sample.cid});
  assert.deepEqual(admitted, ['sample_adoption_receipt']);
  assert.equal(retire(sample.cid, access), true);
  f.reopen();
  assert.deepEqual(read(), {kind: 'expired', sampleRefCid: sample.cid});
  const selectedEvidence = [];
  const sealRunEvidence = (name, ...arguments_) => {
    selectedEvidence.push(name);
    return publication.sealRunEvidence(name, ...arguments_);
  };
  assert.deepEqual(read({...byPort, maxBytes: 1}, access, ref, {admitRunEvidence, sealRunEvidence}),
    {kind: 'expired', sampleRefCid: sample.cid});
  assert.deepEqual(selectedEvidence, ['sample_reference', 'sample_reference']);
  assert.deepEqual(admitted, ['sample_adoption_receipt', 'sample_adoption_receipt']);
  update('emission_provenance_cid = ?', cid('e'));
  assert.throws(() => read(byPort), {code: 'ClientRelationSampleOriginalChanged'},
    'an expired receipt alone cannot authenticate a damaged port association');
});

test('Relation Sample adoption with an uncertain COMMIT resolves only the original durable key', async t => {
  for (const committed of [true, false]) {
    const {f, adopt, ref, lookup} = await relationSampleWriter(t);
    const sample = committedRelationSample(ref);
    const custody = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
    const exec = DatabaseSync.prototype.exec;
    let injected = false;
    DatabaseSync.prototype.exec = function(sql) {
      if (sql === 'COMMIT' && !injected) {
        injected = true;
        if (committed) Reflect.apply(exec, this, [sql]);
        throw new Error('SampleAdoptionCommitReplyLost');
      }
      return Reflect.apply(exec, this, [sql]);
    };
    try {
      assert.throws(() => adopt(sample.wires, custody), {
        code: 'ClientRelationSampleAdoptionUnknown', outcome: 'unknown',
      });
    } finally { DatabaseSync.prototype.exec = exec; }
    assert.equal(injected, true);
    f.reopen();
    assert.throws(() => adopt(sample.wires, custody), {code: 'ClientRequestJournalClosed'});
    const retained = lookup(sample.cid, custody);
    assert.equal(retained.kind, committed ? 'adopted' : 'unobserved');
    if (committed) assert.equal(retained.sampleRefCid, sample.cid);
    assert.deepEqual(lookup(cid('f'), custody), {kind: 'unobserved'});
  }
});

test('Relation Sample adoption refuses equal payloads from another scope and asynchronous loans', async t => {
  const {writer, ref, committedPrefix, withAdoption, prepare, lookup, adopt} = await relationSampleWriter(t);
  const first = committedRelationSample(ref);
  const second = committedRelationSample(ref, {attempt: '2'});
  assert.equal(first.wires.relation, second.wires.relation);
  assert.notEqual(first.cid, second.cid);
  assert.throws(() => writer(second.wires), {code: 'ClientRelationSampleForeignLoan'});
  const another = prepare();
  assert.throws(() => another.withAdoption(committedPrefix(second.wires), () => true, loan => {
    writer(loan);
  }), {code: 'ClientRelationSampleForeignLoan'});
  let suspended;
  assert.throws(() => withAdoption(committedPrefix(first.wires), () => true, loan => {
    suspended = Promise.resolve().then(() => {
      assert.throws(() => writer(loan), {code: 'ClientRelationSampleForeignLoan'});
    });
    return suspended;
  }), {message: 'ClientRelationSampleVisitMustBeSynchronous'});
  await suspended;
  const read = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  assert.deepEqual(lookup(first.cid, read), {kind: 'unobserved'});
  assert.deepEqual(lookup(second.cid, read), {kind: 'unobserved'});
  assert.equal(adopt(first.wires, read).sampleRefCid, first.cid);
});

function readSampleRecords(path) {
  const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  try {
    return database.prepare(`SELECT sample_ref_cid, journal_receipt_ordinal, run_receipt_ordinal,
      source_generation_wire IS NOT NULL AS generation,
      capture_wire IS NOT NULL AS capture, emission_wire IS NOT NULL AS emission,
      reference_wire IS NOT NULL AS reference, relation_wire IS NOT NULL AS relation
      FROM client_relation_sample_adoptions ORDER BY sample_ref_cid`).all();
  } finally {database.close();}
}

test('Relation Sample retirement leaves other rows and durable receipt limits intact', async t => {
  const initial = Date.now();
  let now = initial;
  const options = {maxRecords: 4, submissionEpochNow: () => now};
  const a = await relationSampleWriter(t, options, {maxArtifacts: 2});
  const b = await relationSampleWriter(t, options, {shared: a.f, runName: 'second-original', maxArtifacts: 3});
  const access = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  const sample = (owner, attempt, maxArtifacts) => committedRelationSample(owner.ref, {attempt, maxArtifacts});
  const a1 = sample(a, '1', 2), a2 = sample(a, '2', 2), a3 = sample(a, '3', 2);
  const b1 = sample(b, '1', 3), b2 = sample(b, '2', 3), b3 = sample(b, '3', 3);

  const first = a.adopt(a1.wires, access);
  assert.equal(a.retire(a1.cid, access), false);
  now = initial + 1000;
  const next = a.adopt(a2.wires, access);
  const selectedPort = {compiledPlanCid: cid('4'), logicalMapCid: cid('5'), stepId: cid('6'),
    outputPortId: cid('7'), carrierContractCid: cid('a'), maxBytes: 1024};
  assert.deepEqual(a.f.journal.readRetainedRelationSample(a.ref, selectedPort, access, publication),
    {kind: 'ambiguous'}, 'more than one generation cannot select a replacement for this output port');
  assert.throws(() => a.adopt(a3.wires, access), {code: 'ClientRelationSampleCapacity'});
  now = initial + 2000;
  const other = b.adopt(b1.wires, access);
  const before = readSampleRecords(a.f.path);

  now = initial + 60_000;
  assert.equal(b.retire(a1.cid, access), false);
  assert.throws(() => a.retire(a1.cid, {...access, current: () => false}),
    {code: 'ClientRelationSampleDenied'});
  let checks = 0;
  assert.throws(() => a.retire(a1.cid, {...access, current: () => ++checks < 4}),
    {code: 'ClientRelationSampleDenied'});
  assert.deepEqual(readSampleRecords(a.f.path), before, 'authority loss rolled back retirement');

  assert.equal(a.retire(a1.cid, access), true);
  const find = ref => readSampleRecords(a.f.path).find(row => row.sample_ref_cid === ref.cid);
  assert.deepEqual({...find(a1)}, {sample_ref_cid: a1.cid, journal_receipt_ordinal: 1, run_receipt_ordinal: 1,
    generation: 0, capture: 0, emission: 0, reference: 0, relation: 0});
  assert.deepEqual(readSampleRecords(a.f.path).filter(row => row.sample_ref_cid !== a1.cid),
    before.filter(row => row.sample_ref_cid !== a1.cid), 'retirement leaves every other original row unchanged');
  assert.deepEqual(a.lookup(a1.cid, access), first);
  assert.deepEqual(a.lookup(a2.cid, access), next);
  assert.deepEqual(b.lookup(b1.cid, access), other);
  assert.deepEqual(a.adopt(a1.wires, access), first, 'retry of a retired key does not recreate its payload');
  assert.equal(find(a1).relation, 0);
  assert.equal(a.retire(a1.cid, access), false);
  const retired = readSampleRecords(a.f.path);
  assert.throws(() => a.adopt(a3.wires, access), {code: 'ClientRelationSampleCapacity'});
  assert.deepEqual(readSampleRecords(a.f.path), retired, 'expiry does not renew the original Run allowance');
  assert.equal(b.adopt(b2.wires, access).sampleRefCid, b2.cid);
  assert.deepEqual([find(b2).journal_receipt_ordinal, find(b2).run_receipt_ordinal], [4, 2]);
  const full = readSampleRecords(a.f.path);
  assert.throws(() => b.adopt(b3.wires, access), {code: 'ClientRelationSampleCapacity'});
  assert.deepEqual(readSampleRecords(a.f.path), full, 'the durable cap refuses a new key before any mutation');
  assert.deepEqual(b.lookup(b3.cid, access), {kind: 'unobserved'});
  a.f.reopen();
  now = initial;
  assert.equal(a.retire(a1.cid, access), false);
  assert.deepEqual(a.lookup(a1.cid, access), first);
  assert.throws(() => a.adopt(a1.wires, access), {code: 'ClientRequestJournalClosed'});
  assert.deepEqual(readSampleRecords(a.f.path), full);
});

test('Relation Sample retirement releases no observed slot on uncertain COMMIT', async t => {
  let now = Date.now();
  const {f, adopt, ref, retire, lookup} = await relationSampleWriter(t, {submissionEpochNow: () => now});
  const sample = committedRelationSample(ref);
  const access = {current: () => true, reserve(bytes) {assert.ok(bytes > 0);}};
  const receipt = adopt(sample.wires, access);
  now = receipt.expiresAt;
  const exec = DatabaseSync.prototype.exec;
  let injected = false;
  DatabaseSync.prototype.exec = function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (sql === 'COMMIT' && !injected) {
      injected = true;
      throw new Error('RelationSampleRetirementCommitReplyLost');
    }
    return result;
  };
  try {
    assert.throws(() => retire(sample.cid, access), {
      code: 'ClientRelationSampleRetirementUnknown', outcome: 'unknown',
    });
  } finally {DatabaseSync.prototype.exec = exec;}
  assert.equal(injected, true);
  f.reopen();
  assert.equal(readSampleRecords(f.path)[0].relation, 0);
  assert.equal(retire(sample.cid, access), false);
  assert.deepEqual(lookup(sample.cid, access), receipt);
});
