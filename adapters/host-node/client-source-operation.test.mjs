import assert from 'node:assert/strict';
import fs from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {bindClientSourceOperation, bindClientSourceOperationRowRun}
  from './client-source-operation.mjs';
import {request, requestControl, controls, definition, options}
  from './fixtures/original-plan-journal.mjs';

// Real same-file SQLite/COMMIT/reopen, with explicit semantic-control stand-ins.
// These cases do not replace the separate actual Common binding counter.
function fixture(t, limits = {maxRecords: 8, maxWireBytes: 4096}) {
  const parent = fileURLToPath(new URL('../../_build/source-operation-fixtures/', import.meta.url));
  fs.mkdirSync(parent, {recursive: true});
  const directory = fs.mkdtempSync(join(parent, 'case-'));
  t.diagnostic(`Fresh source-operation Journal retained at ${directory}`);
  const {publication: previous} = controls();
  const program = Object.freeze({}), compiled = Object.freeze({}), prepared = Object.freeze({});
  const publication = Object.freeze({...previous,
    checkClientCompiledRunOwner(value, owner) {assert.equal(value, compiled); assert.equal(owner, program);},
    checkClientCompiledRunDefinition(value, run) {assert.equal(value, compiled); assert.equal(run.identity, definition.identity);}});
  const control = Object.freeze({...requestControl,
    clientProgramMatchesRequestIdentity: (value, identity) => value === program && identity === request,
    clientRunStartAction: (_identity, _retained, _run, _cid, reserved, current) => !current ? 5 : reserved ? 1 : 0,
    clientRunPhysicalStartWithCancellationAction: (_identity, _retained, _run, _cid, reserved, fresh, current, cancelled) =>
      !current ? 5 : reserved && fresh && !cancelled ? 1 : 0});
  let journal = openClientRequestJournal(directory, {sourceOperationLimits: limits});
  const accepted = journal.acceptDefinition(request, options, control, publication);
  journal.reserveDispatch(request, {namespaceId: options.namespaceId, currentAuthorization: true}, control, publication);
  const ref = accepted.ref;
  let scope;
  const capture = {program, compiled, capture(value) {assert.equal(this, capture); scope = value;}};
  const start = (selection = capture) => journal.reservePhysicalStart(request,
    {namespaceId: options.namespaceId, ref, currentAuthorization: true,
      captureSourceOperation: selection}, control, publication);
  t.after(() => journal.close());
  const frame = Object.freeze({run: {}, acquisition: {}, requestId: 'original-attempt',
    runInvocationCid: 'sha256:' + '6'.repeat(64), dispatchRequestCid: 'sha256:' + '7'.repeat(64)});
  const jobRead = {}, firstRequest = {}, record = {};
  const wire = '{"body":"original","format":"actql.bigquery-job-original/0.1"}';
  const moon = Object.freeze({
    clientProgramBigQueryJobReadMatchesRowRun: (job, run, acquisition) => job === jobRead && run === frame.run && acquisition === frame.acquisition,
    clientProgramBigQueryJobOriginalRecordMatchesRequest: (job, issued, original) => job === jobRead && issued === firstRequest && original === record,
    clientProgramBigQueryJobOriginalRecordWire: value => {assert.equal(value, record); return wire;}});
  const occurrence = {stage: 0, input: 0, task: 0};
  const original = Object.freeze({jobRead, request: firstRequest, record, wire, frame});
  return {directory, ref, program, compiled, prepared, control, publication, frame, moon, occurrence, original,
    get journal() {return journal;}, get scope() {return scope;}, start,
    source(value = occurrence, selected = prepared) {return bindClientSourceOperation(scope, program, selected, value);},
    port(value) {return bindClientSourceOperationRowRun(value, moon, program, prepared, frame);},
    reopen() {journal.close(); journal = openClientRequestJournal(directory, {sourceOperationLimits: limits});},
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
  assert.equal(f.start({program: f.program, compiled: f.compiled, capture() {captured++;}}), false);
  assert.equal(captured, 0);
  assert.throws(() => f.port(source), {code: 'ClientRequestJournalClosed'});
});

test('copied scope and different original Program or prepared Source cannot bind a RowRun', t => {
  const f = fixture(t); f.start();
  assert.throws(() => bindClientSourceOperation({...f.scope}, f.program, f.prepared, f.occurrence), {code: 'ForeignClientSourceOperation'});
  assert.throws(() => bindClientSourceOperation(f.scope, {}, f.prepared, f.occurrence), {code: 'ForeignClientSourceOperation'});
  const source = f.source();
  assert.throws(() => bindClientSourceOperationRowRun(source, f.moon, f.program, {...f.prepared}, f.frame), {code: 'ForeignClientSourceOperation'});
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
  const f = fixture(t); f.start(); const source = f.source();
  const {clientProgramBigQueryJobReadMatchesRowRun: _missing, ...moon} = f.moon;
  const port = bindClientSourceOperationRowRun(source, moon, f.program, f.prepared, f.frame);
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

test('same-Run sibling original Sources retain separate keys without releasing their parent or each other', t => {
  const f = fixture(t); f.start(); let sent = 0;
  const first = f.source(), secondAt = {stage: 1, input: 0, task: 1}, prepared = {};
  const second = f.source(secondAt, prepared);
  const frame = Object.freeze({...f.frame, run: {}, acquisition: {}, requestId: 'sibling-attempt'});
  const original = Object.freeze({...f.original, jobRead: {}, request: {}, record: {}, frame, wire: 'sibling-original'});
  const moon = Object.freeze({
    clientProgramBigQueryJobReadMatchesRowRun: (job, run, acquisition) => job === original.jobRead && run === frame.run && acquisition === frame.acquisition,
    clientProgramBigQueryJobOriginalRecordMatchesRequest: (job, request, record) => job === original.jobRead && request === original.request && record === original.record,
    clientProgramBigQueryJobOriginalRecordWire: record => {assert.equal(record, original.record); return original.wire;}});
  f.port(first)(f.original, () => sent++);
  bindClientSourceOperationRowRun(second, moon, f.program, prepared, frame)(original, () => sent++);
  assert.equal(sent, 2);
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, f.occurrence).originalWire, f.original.wire);
  assert.equal(f.journal.lookupOriginalSourceOperation(f.ref, secondAt).originalWire, original.wire);
});
