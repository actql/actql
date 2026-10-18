import assert from 'node:assert/strict';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {bigqueryHttpsFixture} from '../connectors/bigquery/test/bigquery-https.fixture.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {acquiredTaskRunAdmission, sourceFreePlanOriginal} from './local-values-plan.mjs';
import {bindClientSourceOperation, bindClientSourceOperationRowRun} from './client-source-operation.mjs';

// Actual Common compilation, same-file SQLite original claim, encrypted Store,
// Account/Credential and loopback HTTPS. Capacity/permission inputs are explicit
// fixture originals, not a normal installed supplier or public Host acceptance.
async function fixture(t) {
  const f = await bigqueryHttpsFixture(t);
  const control = runtimeCore(f.moon).publicationControl;
  const program = f.row.originals.program;
  const authorityScopeCid = 'sha256:' + 'a'.repeat(64), namespaceId = 'original-bigquery';
  const plan = acquiredTaskRunAdmission({moon: f.moon, control, preparedProgram: program,
    authorityScopeCid, namespaceId, now: () => new Date().toISOString()});
  const request = f.moon.clientProgramRequestIdentity(program, authorityScopeCid,
    f.row.requestId, f.moon.clientProgramSourceFreeInputIntentCid());
  assert.ok(request);
  const directory = join(f.root, 'request-journal');
  const configuration = {sourceOperationLimits: {maxRecords: 8, maxWireBytes: 65536}};
  let journal = openClientRequestJournal(directory, configuration);
  const store = await openLocalPublicationStore({directory: join(f.root, 'publication-store'),
    storeAuthorityCid: 'sha256:' + 'd'.repeat(64), capacityBytes: 64 * 1024 * 1024,
    maxObjectBytes: 1024 * 1024, maxObjects: 100, maxContractNodes: 10000,
    maxContractDepth: 64}, control);
  t.after(async () => {journal.close(); await store.close();});
  const accepted = journal.acceptDefinition(request, {namespaceId,
    runDefinition: plan.runDefinition, lookupExpiresAt: JSON.parse(plan.runDefinition.wire).valid_until,
    runAdmissionEvidence: {prepared: plan.preparedEvidence.wire,
      authorization: plan.authorization.wire}, originalPlan: sourceFreePlanOriginal(plan)}, f.moon, control);
  assert.equal(accepted.inserted, true);
  assert.equal(journal.reserveDispatch(request, {namespaceId, currentAuthorization: true},
    f.moon, control).kind, 'reserved');
  let scope;
  const capture = {program, compiled: plan.compiled, store, capture(value) {
    assert.equal(this, capture); scope = value;
  }};
  const start = () => journal.reservePhysicalStart(request, {namespaceId, ref: accepted.ref,
    currentAuthorization: true, captureSourceOperation: capture}, f.moon, control);
  assert.equal(start(), true); assert.ok(scope);
  const occurrence = Object.freeze({stage: 0, input: 0, task: 0});
  const source = bindClientSourceOperation(scope, journal, store, program, f.row.prepared, occurrence);
  const withOriginalJob = bindClientSourceOperationRowRun(source, f.moon,
    program, f.row.prepared, f.frame);
  return {...f, control, request, plan, store, occurrence, start, withOriginalJob, ref: accepted.ref,
    get requestJournal() {return journal;},
    reopen() {journal.close(); journal = openClientRequestJournal(directory, configuration);}};
}

test('actual Common Job is committed in the original Run Journal before its single HTTPS POST', async t => {
  const f = await fixture(t);
  let original;
  const result = await f.read({withOriginalJob: (value, send) => {
    original = value;
    return f.withOriginalJob(value, () => {
      assert.equal(f.state.requests.length, 0);
      assert.equal(f.moon.clientProgramBigQueryJobReadMatchesRowRun(value.jobRead,
        f.row.run, f.row.acquisition), true);
      assert.equal(f.requestJournal.lookupOriginalSourceOperation(f.ref, f.occurrence).originalWire, value.wire);
      return send();
    });
  }});
  assert.equal(result.rows, 2n);
  assert.equal(f.state.requests.filter(x => x.method === 'POST').length, 1);
  assert.equal(JSON.parse(original.wire).body, f.state.requests[0].body);
  const captured = f.row.captureRows();
  assert.equal(captured.length, 2);
  assert.ok(captured[0].includes('-9223372036854775808'));
  assert.ok(captured[1].includes('9223372036854775807'));
  f.reopen();
  const saved = f.requestJournal.lookupOriginalSourceOperation(f.ref, f.occurrence);
  assert.equal(saved.kind, 'unresolved_original');
  assert.equal(saved.originalWire, original.wire);
  assert.equal(saved.sourceAttemptId, f.row.requestId);
  assert.equal(f.requestJournal.lookupRunDefinition(f.ref, f.moon, f.control).runDefinition.identity,
    f.plan.runDefinition.identity);
  assert.equal(f.start(), false, 'the same saved Run cannot issue a replacement live Source scope');
});

test('actual original-record COMMIT reply loss retains the same Job without secret resolution or POST', async t => {
  const f = await fixture(t);
  const exec = DatabaseSync.prototype.exec;
  let original, injected = false;
  await assert.rejects(f.read({withOriginalJob: (value, send) => {
    original = value;
    DatabaseSync.prototype.exec = function(sql) {
      const result = Reflect.apply(exec, this, [sql]);
      if (sql === 'COMMIT' && !injected) {injected = true; throw new Error('OriginalCommitReplyLost');}
      return result;
    };
    try {return f.withOriginalJob(value, send);}
    finally {DatabaseSync.prototype.exec = exec;}
  }}), {code: 'ClientSourceOperationUnknown', outcome: 'unknown'});
  assert.equal(injected, true);
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  f.row.assertNoCapture();
  f.reopen();
  assert.equal(f.requestJournal.lookupOriginalSourceOperation(f.ref, f.occurrence).originalWire, original.wire);
  assert.equal(f.start(), false);
  assert.throws(() => f.withOriginalJob(original, () => assert.fail('No replacement POST')),
    {code: 'ClientSourceOperationAlreadyEntered'});
});

test('actual same-Journal cancellation fences the original Job before CAS and physical I/O', async t => {
  const f = await fixture(t);
  const cancelled = f.requestJournal.requestCancellation(f.ref,
    {currentAuthorization: true, publicationCommitted: false}, f.moon, f.control);
  assert.equal(cancelled.kind, 'accepted');
  await assert.rejects(f.read({withOriginalJob: f.withOriginalJob}),
    {code: 'ClientSourceOperationOriginalChanged', outcome: 'unknown'});
  assert.equal(f.requestJournal.lookupOriginalSourceOperation(f.ref, f.occurrence), undefined);
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  f.row.assertNoCapture();
});

test('actual retired original Store cannot hand a Job to the same Journal or resolve a credential', async t => {
  const f = await fixture(t);
  await f.store.close();
  await assert.rejects(f.read({withOriginalJob: f.withOriginalJob}), {code: 'PublicationStoreClosed'});
  assert.equal(f.requestJournal.lookupOriginalSourceOperation(f.ref, f.occurrence), undefined);
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
  f.row.assertNoCapture();
});
