import assert from 'node:assert/strict';
import fs from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {openLocalPublicationStore, prepareLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership}
  from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture}
  from '../host-common/publication-contract-control.fixture.mjs';
import {bindClientSourceOperation, bindClientSourceOperationRowRun}
  from './client-source-operation.mjs';
import {request, requestControl, controls, definition, options}
  from './fixtures/original-plan-journal.mjs';

// Real same-file SQLite/COMMIT/reopen, with explicit semantic-control stand-ins.
// These cases do not replace the separate actual Common binding counter.
function fixture(t, limits = {maxRecords: 8, maxWireBytes: 4096}, missingJobProjection = false,
  journalOptions = {}) {
  const parent = fileURLToPath(new URL('../../_build/source-operation-fixtures/', import.meta.url));
  fs.mkdirSync(parent, {recursive: true});
  const directory = fs.mkdtempSync(join(parent, 'case-'));
  t.diagnostic(`Fresh source-operation Journal retained at ${directory}`);
  const {publication: previous} = controls();
  const program = Object.freeze({}), compiled = Object.freeze({}), prepared = Object.freeze({});
  const publication = Object.freeze({...previous,
    checkClientCompiledRunOwner(value, owner) {assert.equal(value, compiled); assert.equal(owner, program);},
    checkClientCompiledRunDefinition(value, run) {assert.equal(value, compiled); assert.equal(run.identity, definition.identity);}});
  const jobs = new WeakMap(), records = new WeakMap();
  const control = Object.freeze({...requestControl,
    ...(missingJobProjection ? {} : {clientProgramBigQueryJobReadMatchesRowRun: (job, run, acquisition) =>
      jobs.get(job)?.frame.run === run && jobs.get(job)?.frame.acquisition === acquisition}),
    clientProgramBigQueryJobOriginalRecordMatchesRequest: (job, issued, record) => jobs.get(job)?.request === issued && jobs.get(job)?.record === record,
    clientProgramBigQueryJobOriginalRecordWire: record => records.get(record),
    clientProgramMatchesRequestIdentity: (value, identity) => value === program && identity === request,
    clientRunStartAction: (_identity, _retained, _run, _cid, reserved, current) => !current ? 5 : reserved ? 1 : 0,
    clientRunPhysicalStartWithCancellationAction: (_identity, _retained, _run, _cid, reserved, fresh, current, cancelled) =>
      !current ? 5 : reserved && fresh && !cancelled ? 1 : 0});
  let journal = openClientRequestJournal(directory, {...journalOptions, sourceOperationLimits: limits});
  const accepted = journal.acceptDefinition(request, options, control, publication);
  journal.reserveDispatch(request, {namespaceId: options.namespaceId, currentAuthorization: true}, control, publication);
  const ref = accepted.ref;
  let scope, storeClosed = false;
  const store = Object.freeze({privateEvidenceWireLimit() {
    assert.equal(this, store);
    if (storeClosed) throw Object.assign(new Error('PublicationStoreClosed'), {code: 'PublicationStoreClosed'});
    return 4096;
  }});
  const capture = {program, compiled, store, capture(value) {assert.equal(this, capture); scope = value;}};
  const start = (selection = capture) => journal.reservePhysicalStart(request,
    {namespaceId: options.namespaceId, ref, currentAuthorization: true,
      captureSourceOperation: selection}, control, publication);
  t.after(() => journal.close());
  const frame = Object.freeze({run: {}, acquisition: {}, requestId: 'original-attempt',
    runInvocationCid: 'sha256:' + '6'.repeat(64), dispatchRequestCid: 'sha256:' + '7'.repeat(64)});
  const jobRead = {}, firstRequest = {}, record = {};
  const recordWire = jobId => JSON.stringify({
    body: JSON.stringify({configuration: {query: {query: 'SELECT 1', useLegacySql: false}},
      jobReference: {jobId, location: 'EU', projectId: 'acme-project'}}),
    format: 'actql.bigquery-job-original/0.1', jobId, location: 'EU', method: 'POST',
    path: '/bigquery/v2/projects/acme-project/jobs', project: 'acme-project'});
  const wire = recordWire(frame.requestId);
  const moon = control;
  const occurrence = {stage: 0, input: 0, task: 0};
  const original = Object.freeze({jobRead, request: firstRequest, record, wire, frame});
  const registerJob = original => {jobs.set(original.jobRead, original); records.set(original.record, original.wire);};
  registerJob(original);
  return {directory, ref, program, compiled, prepared, control, publication, frame, moon, occurrence, original, store,
    get journal() {return journal;}, get scope() {return scope;}, start,
    source(value = occurrence, selected = prepared) {return bindClientSourceOperation(scope, journal, store, program, selected, value);},
    port(value) {return bindClientSourceOperationRowRun(value, moon, program, prepared, frame);},
    reopen() {journal.close(); journal = openClientRequestJournal(directory, {sourceOperationLimits: limits});},
    reopenWithoutSourceOperations() {journal.close(); journal = openClientRequestJournal(directory);},
    closeStore() {storeClosed = true;}, registerJob, recordWire,
    mutate(sql) {const db = new DatabaseSync(join(directory, 'client-requests.sqlite3')); try {db.exec(sql);} finally {db.close();}}};
}

test('confirmed same-Journal physical claim issues one original scope and commits exact material before send', t => {
  const f = fixture(t); assert.equal(f.scope, undefined); assert.equal(f.start(), true);
  const source = f.source(), port = f.port(source); let sent = 0;
  assert.equal(port(f.original, () => {
    sent++;
    assert.deepEqual(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), {
      kind: 'unresolved_original', originalWire: f.original.wire, sourceAttemptId: f.frame.requestId,
      runInvocationCid: f.frame.runInvocationCid, dispatchRequestCid: f.frame.dispatchRequestCid});
    return 'original-result';
  }), 'original-result');
  assert.equal(sent, 1);
  assert.equal(f.source(), source); assert.equal(f.port(source), port);
  assert.throws(() => port(f.original, () => sent++), {code: 'ClientSourceOperationAlreadyEntered'});
  assert.equal(sent, 1);
  f.reopen();
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence).originalWire, f.original.wire);
  let captured = 0;
  assert.equal(f.start({program: f.program, compiled: f.compiled, store: f.store, capture() {captured++;}}), false);
  assert.equal(captured, 0);
  assert.throws(() => f.port(source), {code: 'ClientRequestJournalClosed'});
});

test('bounded Journal facade remains the exact same Source operation owner without accepting a copy', t => {
  const f = fixture(t, undefined, false, {primaryCurrent() {},
    maxDatabaseBytes: 1024 * 1024,
    primarySqlLimits: {maxPreparedStatements: 1000,
      maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024},
    primaryExecutionLimits: {maxParameters: 64,
      maxParameterBytes: 65536, maxResultRows: 1000}});
  assert.equal(f.start(), true);
  const source = f.source();
  assert.throws(() => bindClientSourceOperation(f.scope, {...f.journal}, f.store,
    f.program, f.prepared, f.occurrence), {code: 'ForeignClientSourceOperation'});
  let sends = 0;
  f.port(source)(f.original, () => {sends++;});
  assert.equal(sends, 1);
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence).originalWire,
    f.original.wire);
});

test('copied scope and different original Program or prepared Source cannot bind a RowRun', t => {
  const f = fixture(t); f.start();
  assert.throws(() => bindClientSourceOperation({...f.scope}, f.journal, f.store, f.program, f.prepared, f.occurrence), {code: 'ForeignClientSourceOperation'});
  assert.throws(() => bindClientSourceOperation(f.scope, f.journal, f.store, {}, f.prepared, f.occurrence), {code: 'ForeignClientSourceOperation'});
  assert.throws(() => bindClientSourceOperation(f.scope, {}, f.store, f.program, f.prepared, f.occurrence), {code: 'ForeignClientSourceOperation'});
  assert.throws(() => bindClientSourceOperation(f.scope, f.journal, {}, f.program, f.prepared, f.occurrence), {code: 'ForeignClientSourceOperation'});
  const source = f.source();
  assert.throws(() => bindClientSourceOperationRowRun(source, f.moon, f.program, {...f.prepared}, f.frame), {code: 'ForeignClientSourceOperation'});
  assert.throws(() => bindClientSourceOperationRowRun(source, {...f.moon}, f.program, f.prepared, f.frame), {code: 'ForeignClientSourceOperation'});
  assert.throws(() => f.source(f.occurrence, {}), {code: 'ForeignClientSourceOperation'});
  f.port(source);
  assert.throws(() => bindClientSourceOperationRowRun(source, f.moon, f.program, f.prepared, {...f.frame, run: {}}), {code: 'ForeignClientSourceOperation'});
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), undefined);
});

test('foreign nominal Job/read/request/record and changed wire refuse before CAS or send', t => {
  const f = fixture(t); f.start(); const port = f.port(f.source()); let sent = 0;
  for (const key of ['jobRead', 'request', 'record', 'wire']) {
    assert.throws(() => port({...f.original, [key]: key === 'wire' ? 'changed' : {}}, () => sent++), {code: 'ForeignClientSourceOperation'});
  }
  assert.throws(() => port({...f.original, frame: {...f.frame, acquisition: {}}}, () => sent++), {code: 'ForeignClientSourceOperation'});
  assert.equal(sent, 0); assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), undefined);
  port(f.original, () => sent++); assert.equal(sent, 1);
});

test('an unavailable Common original Job/RowRun projection cannot be replaced by frame DATA', t => {
  const f = fixture(t, undefined, true); f.start(); const source = f.source();
  const port = bindClientSourceOperationRowRun(source, f.moon, f.program, f.prepared, f.frame);
  assert.throws(() => port(f.original, () => assert.fail('No physical send')), {code: 'ClientSourceOperationBindingUnavailable'});
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), undefined);
});

test('lost original-record COMMIT reply keeps the saved material and never enters or replaces the send', t => {
  const f = fixture(t); f.start(); const port = f.port(f.source());
  const exec = DatabaseSync.prototype.exec; let injected = false, sent = 0;
  DatabaseSync.prototype.exec = function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (sql === 'COMMIT' && !injected) {injected = true; throw new Error('OriginalRecordCommitReplyLost');}
    return result;
  };
  try {assert.throws(() => port(f.original, () => sent++), {code: 'ClientSourceOperationUnknown', outcome: 'unknown'});}
  finally {DatabaseSync.prototype.exec = exec;}
  assert.equal(injected, true); assert.equal(sent, 0);
  assert.throws(() => port(f.original, () => sent++), {code: 'ClientSourceOperationAlreadyEntered'});
  f.reopen();
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence).originalWire, f.original.wire);
  assert.equal(f.start(), false); assert.equal(sent, 0);
});

test('lost first physical-start COMMIT reply cannot issue a live Source scope', t => {
  const f = fixture(t); const exec = DatabaseSync.prototype.exec; let injected = false;
  DatabaseSync.prototype.exec = function(sql) {
    const result = Reflect.apply(exec, this, [sql]);
    if (sql === 'COMMIT' && !injected) {injected = true; throw new Error('PhysicalStartCommitReplyLost');}
    return result;
  };
  try {assert.throws(() => f.start(), {code: 'ClientRunPhysicalStartUnknown', outcome: 'unknown'});}
  finally {DatabaseSync.prototype.exec = exec;}
  assert.equal(f.scope, undefined); f.reopen(); assert.equal(f.start(), false);
  assert.equal(f.scope, undefined); assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), undefined);
});

test('current cancellation after scope issue refuses before recording or physical send', t => {
  const f = fixture(t); f.start(); const port = f.port(f.source());
  f.mutate('UPDATE client_requests SET cancellation_requested = 1');
  assert.throws(() => port(f.original, () => assert.fail('No physical send')), {code: 'ClientSourceOperationOriginalChanged'});
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), undefined);
});

test('the same original Store retirement refuses before original-record CAS or send', t => {
  const f = fixture(t); f.start(); const port = f.port(f.source()); f.closeStore();
  assert.throws(() => port(f.original, () => assert.fail('No physical send')), {code: 'PublicationStoreClosed'});
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), undefined);
});

test('same-Run sibling original Sources retain separate keys without releasing their parent or each other', t => {
  const f = fixture(t); f.start(); let sent = 0;
  const first = f.source(), secondAt = {stage: 1, input: 0, task: 1}, prepared = {};
  const second = f.source(secondAt, prepared);
  const frame = Object.freeze({...f.frame, run: {}, acquisition: {}, requestId: 'sibling-attempt'});
  const original = Object.freeze({...f.original, jobRead: {}, request: {}, record: {}, frame, wire: f.recordWire(frame.requestId)});
  f.registerJob(original);
  f.port(first)(f.original, () => sent++);
  bindClientSourceOperationRowRun(second, f.moon, f.program, prepared, frame)(original, () => sent++);
  assert.equal(sent, 2);
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence).originalWire, f.original.wire);
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, secondAt).originalWire, original.wire);
});

test('missing original-operation storage bounds refuse before the physical-start CAS', t => {
  const f = fixture(t); f.reopenWithoutSourceOperations();
  assert.equal(f.journal.sourceOperationConfigured, false);
  assert.throws(() => f.start(), {code: 'ClientSourceOperationUnavailable'});
  assert.equal(f.scope, undefined);
  assert.equal(f.journal.lookupRunDefinition(f.ref, f.control, f.publication).physicalStartReserved, false);
});

test('record capacity refusal cannot fall back or rebind another attempt at the same original occurrence', t => {
  const f = fixture(t, {maxRecords: 1, maxWireBytes: 16}); f.start(); const source = f.source(), port = f.port(source);
  assert.throws(() => port(f.original, () => assert.fail('No physical send')), {code: 'ClientSourceOperationCapacity'});
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), undefined);
  assert.equal(f.source(), source);
  assert.throws(() => f.port(source)(f.original, () => assert.fail('No retry')), {code: 'ClientSourceOperationAlreadyEntered'});
  assert.throws(() => f.source({stage: 1, input: 0, task: 1}, {}), {code: 'ClientSourceOperationCapacity'});
});

test('oversized retained original wire refuses as corruption without issuing another live operation', t => {
  const f = fixture(t); f.start(); const port = f.port(f.source()); port(f.original, () => {});
  f.mutate("UPDATE client_source_operation_originals SET original_wire = printf('%.*c', 10000, 'x')");
  assert.throws(() => f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), {code: 'ClientSourceOperationCorrupt'});
  assert.throws(() => port(f.original, () => assert.fail('No resend')), {code: 'ClientSourceOperationAlreadyEntered'});
  f.reopen(); assert.equal(f.start(), false);
  assert.throws(() => f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence), {code: 'ClientSourceOperationCorrupt'});
});

test('private source-operation bounds refuse accessors and unknown fields before opening a database', t => {
  const parent = fileURLToPath(new URL('../../_build/source-operation-fixtures/', import.meta.url));
  fs.mkdirSync(parent, {recursive: true}); let reads = 0;
  const cases = [null, {maxRecords: 1, maxWireBytes: 0}, {maxRecords: 1, maxWireBytes: 2_147_483_648},
    {maxRecords: 1, maxWireBytes: 1024, extra: 1}, {maxRecords: 1, maxWireBytes: 1024, [Symbol('extra')]: 1},
    {maxRecords: 1, get maxWireBytes() {reads++; return 1024;}}];
  for (const sourceOperationLimits of cases) {
    const directory = fs.mkdtempSync(join(parent, 'invalid-'));
    assert.throws(() => openClientRequestJournal(directory, {sourceOperationLimits}), {code: 'InvalidClientSourceOperationLimits'});
    assert.deepEqual(fs.readdirSync(directory), []);
  }
  assert.equal(reads, 0);
});


// Physical SQLite/Store originals are real; semantic compiler controls below
// are explicit stand-ins. Public process-kill tests separately exercise Common.
async function localOwnerFixture(t, {legacy = false, beforeOpen} = {}) {
  const parent = fileURLToPath(new URL('../../_build/local-owner-journal-fixtures/', import.meta.url));
  fs.mkdirSync(parent, {recursive: true});
  const root = fs.mkdtempSync(join(parent, 'case-'));
  const publicationDirectory = join(root, 'publication'), directory = join(root, 'requests');
  fs.mkdirSync(publicationDirectory, {mode: 0o700});
  const storeConfiguration = {directory: publicationDirectory,
    storeAuthorityCid: 'sha256:' + 'a'.repeat(64), capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024, maxObjects: 100, maxContractNodes: 4096, maxContractDepth: 64};
  const storeControl = createPublicationContractControlFixture();
  const program = {}, compiled = {}, inventory = {acquisitions: 0, infer: [], serialization: [], effects: false, graphCarrier: false};
  const {publication: previous} = controls();
  const publication = {...previous,
    checkClientCompiledRunOwner(value, actual) {assert.equal(value, compiled); assert.equal(actual, program);},
    checkClientCompiledRunDefinition(value, actual) {assert.equal(value, compiled); assert.equal(actual.identity, definition.identity);},
    checkClientCompiledLocalExecutionOwner(value, actual) {
      assert.equal(value, compiled); assert.equal(actual.identity, definition.identity);
      assert.equal(inventory.effects, false); assert.equal(inventory.graphCarrier, false);
    }};
  const control = {...requestControl,
    clientProgramMatchesRequestIdentity: (actual, identity) => actual === program && identity === request,
    clientProgramAcquisitionCount: actual => {assert.equal(actual, program); return inventory.acquisitions;},
    clientProgramSerializationOccurrences: actual => {assert.equal(actual, program); return inventory.serialization;},
    clientProgramComposedInferOccurrences: actual => {assert.equal(actual, program); return {$tag: 1, _0: inventory.infer};},
    clientRunStartAction: (_identity, _retained, _run, _cid, reserved, current) => !current ? 5 : reserved ? 1 : 0,
    clientRunPhysicalStartWithCancellationAction: (_identity, _retained, _run, _cid, reserved, fresh, current, cancelled) =>
      !current ? 5 : reserved && fresh && !cancelled ? 1 : 0};
  if (beforeOpen !== undefined) await beforeOpen(publicationDirectory);
  let owner = await prepareLocalPublicationStoreOwnership(publicationDirectory);
  let journal = openClientRequestJournal(directory, {}, legacy ? undefined : owner);
  let store = await openLocalPublicationStore(storeConfiguration, storeControl,
    undefined, undefined, owner);
  const accepted = journal.acceptDefinition(request, options, control, publication);
  journal.reserveDispatch(request, {namespaceId: options.namespaceId, currentAuthorization: true}, control, publication);
  const ref = accepted.ref;
  t.after(async () => {journal.close(); await store.close();
    assert.equal((await closePreparedLocalPublicationStoreOwnership(owner)).pending, false);});
  return {root, directory, ref, program, compiled, inventory, control, publication,
    get journal() {return journal;},
    start(value = {program, compiled}) {return journal.reservePhysicalStart(request,
      {namespaceId: options.namespaceId, ref, currentAuthorization: true, localExecutionOwner: value}, control, publication);},
    frame() {return journal.lookupRunDefinition(ref, control, publication);},
    rows() {const db = new DatabaseSync(join(directory, 'client-requests.sqlite3'));
      try {return db.prepare('SELECT * FROM client_local_execution_owners').all();} finally {db.close();}},
    mutate(sql) {const db = new DatabaseSync(join(directory, 'client-requests.sqlite3'));
      try {db.exec(sql);} finally {db.close();}},
    async reopen(beforeReopen) {journal.close(); await store.close();
      assert.equal((await closePreparedLocalPublicationStoreOwnership(owner)).pending, false);
      if (beforeReopen !== undefined) await beforeReopen(publicationDirectory);
      owner = await prepareLocalPublicationStoreOwnership(publicationDirectory);
      journal = openClientRequestJournal(directory, {}, owner);
      store = await openLocalPublicationStore(storeConfiguration, storeControl,
        undefined, undefined, owner);}};
}

test('local execution owner receipt atomically binds the original start and only a successor can observe it stopped', async t => {
  const f = await localOwnerFixture(t);
  assert.equal(f.start(), true); assert.equal(f.rows().length, 1);
  const frame = f.frame();
  assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, frame), false);
  assert.throws(() => f.journal.observeStoppedLocalExecutionOwner(f.ref, {...frame}), {code: 'ForeignRunStateObservation'});
  assert.throws(() => f.journal.observeStoppedLocalExecutionOwner({...f.ref, namespaceId: 'foreign'}, frame), {code: 'ForeignRunStateObservation'});
  assert.equal(f.start(), false); assert.equal(f.rows().length, 1);
  await f.reopen();
  const restored = f.frame();
  assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, restored), true);
  assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, restored), true);
  assert.equal(f.frame().revision, restored.revision);
  assert.equal(f.frame().physicalCloseConfirmed, false);
  assert.equal(f.frame().observedTerminalOutcome, null);
});

test('local execution owner receipt rejects foreign and external-work originals before the physical claim', async t => {
  const f = await localOwnerFixture(t);
  for (const value of [{program: {}, compiled: f.compiled}, {program: f.program, compiled: {}}]) {
    assert.throws(() => f.start(value), {code: 'ForeignClientLocalExecutionOwner'});
  }
  for (const [key, value] of [['acquisitions', 1], ['infer', [{}]], ['serialization', [[0, 0]]], ['effects', true], ['graphCarrier', true]]) {
    const previous = f.inventory[key]; f.inventory[key] = value;
    assert.throws(() => f.start(), {code: 'ForeignClientLocalExecutionOwner'});
    f.inventory[key] = previous;
  }
  assert.equal(f.frame().physicalStartReserved, false); assert.equal(f.rows().length, 0);
});

test('local execution owner receipt rolls back with an uncommitted physical-start claim', async t => {
  const f = await localOwnerFixture(t);
  f.mutate("CREATE TRIGGER refuse_physical_start BEFORE UPDATE OF physical_start_reserved ON client_requests BEGIN SELECT RAISE(ABORT, 'fixture'); END");
  assert.throws(() => f.start());
  assert.equal(f.frame().physicalStartReserved, false); assert.equal(f.rows().length, 0);
  f.mutate('DROP TRIGGER refuse_physical_start');
  assert.equal(f.start(), true); assert.equal(f.rows().length, 1);
});

test('legacy started originals have no local execution owner proof after lease adoption', async t => {
  const f = await localOwnerFixture(t, {legacy: true});
  assert.equal(f.start(), true); await f.reopen();
  assert.equal(f.rows().length, 0);
  assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, f.frame()), false);
});

test('local execution owner observation rejects a changed retained frame instead of overwriting a stop', async t => {
  const f = await localOwnerFixture(t); f.start(); await f.reopen();
  const frame = f.frame(); assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, frame), true);
  f.journal.markPhysicalClose(f.ref, 'failed', frame);
  assert.throws(() => f.journal.observeStoppedLocalExecutionOwner(f.ref, frame), {code: 'ClientRunStopObservationChanged'});
  assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, f.frame()), false);
});


test('a different stored anchor cannot certify the original local execution stopped', async t => {
  const f = await localOwnerFixture(t); f.start();
  f.mutate("UPDATE client_local_execution_owners SET anchor_identity = '00000000-0000-0000-0000-000000000000'");
  await f.reopen();
  assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, f.frame()), false);
  assert.equal(f.frame().physicalCloseConfirmed, false);
});


test('partial and malformed unqualified anchors preserve ordinary opening without issuing an owner receipt', async t => {
  for (const contents of ['', 'partial', 'z'.repeat(36)]) {
    await t.test(`anchor length ${contents.length}`, async t => {
      const f = await localOwnerFixture(t);
      // Only a genuinely initialized, cleanly released Store can exercise
      // qualification fallback. A lease-only fresh directory is not a format.
      await f.reopen(directory => {
        fs.writeFileSync(join(directory, 'owner-lease'), contents, {mode: 0o600});
      });
      assert.equal(f.start(), true);
      assert.equal(f.rows().length, 0);
      assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, f.frame()), false);
      await f.reopen();
      assert.equal(f.rows().length, 0);
      assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, f.frame()), false);
      assert.equal(f.frame().physicalCloseConfirmed, false);
    });
  }
});

test('missing or replaced historical anchors cannot certify the original execution stopped', async t => {
  for (const replacement of [false, true]) {
    await t.test(replacement ? 'replaced inode with same identity' : 'missing anchor', async t => {
      const f = await localOwnerFixture(t);
      assert.equal(f.start(), true);
      const [original] = f.rows();
      assert.ok(original);
      await f.reopen(directory => {
        const anchor = join(directory, 'owner-lease');
        const contents = fs.readFileSync(anchor);
        // Retain the old inode outside the Store so replacement cannot reuse it.
        fs.renameSync(anchor, join(f.root, 'historical-owner-lease'));
        if (replacement) fs.writeFileSync(anchor, contents, {mode: 0o600});
      });
      assert.deepEqual(f.rows(), [original]);
      assert.equal(f.journal.observeStoppedLocalExecutionOwner(f.ref, f.frame()), false);
      assert.equal(f.frame().physicalCloseConfirmed, false);
      assert.equal(f.frame().observedTerminalOutcome, null);
    });
  }
});
