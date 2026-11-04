// Use the installed Host without replacing its cancellation or dispatch owner.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {setTimeout as delay} from 'node:timers/promises';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect, explainCancellation, formatCancellation, getSubmissionAttempt} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const {directory, entrance, phase, loss, output, cancelRef: originalRef,
  submissionRef: originalSubmission, boundary = 'publication'} = JSON.parse(process.argv[2]);
const requestId = 'original-cancel-successful-run';
const cancelId = 'original-cancel-operation';
const keys = generateKeyPairSync('ed25519');
let computes = 0;
let publicationReached, releasePublication;
const publicationReady = new Promise(resolve => { publicationReached = resolve; });
const publicationHeld = new Promise(resolve => { releasePublication = resolve; });
const authorization = {
  accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'cancel-operation-fixture', entries: [{entry_id: 'owner-read', outcome: 'allow',
      principal: {any_of: [userInfo().username]}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'write', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  observe(name, detail) {
    if (name === 'computed') computes++;
    console.log('INSTALLED_CANCEL_OWNER', name, detail?.code ?? '', new Date().toISOString());
  },
  async faultInjection(name) {
    if (['initial', 'typed-initial'].includes(phase) && name === (boundary === 'physical-start' ? 'physical_start_reserved' : 'computed')) {
      // Hold the real dispatch after its physical start reservation, or
      // after Store publication, without claiming stop or cleanup success.
      publicationReached();
      await publicationHeld;
    }
  },
};
const installation = {directory: join(directory, 'host'), authorization};
const originalCAs = getCACertificates('default');
const originalExec = DatabaseSync.prototype.exec;
let client, host, server, database, faults = 0;
const snapshot = () => ({
  operations: database.prepare(`SELECT namespace_id, authority_scope_cid, cancel_id,
    run_definition_cid, expected_revision, intent_fingerprint_cid, outcome_wire,
    outcome_cid FROM client_cancellation_operations ORDER BY cancel_id`).all().map(row => ({...row})),
  issued: database.prepare('SELECT issued_count FROM client_cancellation_custody').get().issued_count,
  requests: database.prepare(`SELECT caller_request_id, run_definition_cid,
    revision, cancellation_requested, physical_close_confirmed,
    observed_terminal_outcome FROM client_requests`).all().map(row => ({...row})),
});
try {
  console.log('INSTALLED_CANCEL_PHASE', 'opening', phase, new Date().toISOString());
  if (entrance === 'local') client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation});
  else {
    const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(directory, name))));
    setDefaultCACertificates([...originalCAs, cert.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation, authenticate: () => userInfo().username});
    server = createServer({key, cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', token: 'fixture-token',
      endpoint: `https://127.0.0.1:${server.address().port}/`});
  }
  database = new DatabaseSync(join(installation.directory, 'requests/client-requests.sqlite3'), {readOnly: true});
  console.log('INSTALLED_CANCEL_PHASE', 'connected', new Date().toISOString());
  if (phase === 'typed-initial') {
    const program = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'));
    const submissionRef = client.newSubmission({nonce: requestId});
    const run = await client.start(program, {submissionRef});
    await publicationReady;
    const before = await run.status();
    assert.equal(before.status, 'running');
    const revision = before.control.revision;
    const conflict = await run.cancel({cancelId: 'stale-operation', expectedRevision: revision - 1,
      attemptId: 'stale-invocation'});
    assert.deepEqual(conflict, {kind: 'conflict', reason: 'control_revision',
      attemptRef: {operation: 'cancel', attemptId: 'stale-invocation'},
      cancelRef: {...run.ref, cancelId: 'stale-operation', expectedRevision: revision - 1}});
    assert.deepEqual(snapshot().operations, []);
    // These public operations overlap while the original physical task is
    // held. Submission replay must retain the original Run, and observation
    // progress cannot replace the cancellation's control revision.
    const [replayed, accepted, observations] = await Promise.all([
      client.start(program, {submissionRef, attemptId: 'concurrent-submission-invocation'}),
      run.cancel({cancelId, expectedRevision: revision, attemptId: 'accepted-invocation'}),
      run.observeOwners(),
    ]);
    const replayAttempt = getSubmissionAttempt(replayed);
    assert.equal(replayAttempt.kind, 'already_satisfied');
    assert.deepEqual(replayAttempt.attemptRef,
      {operation: 'submit', attemptId: 'concurrent-submission-invocation'});
    assert.deepEqual(replayed.ref, run.ref);
    assert.deepEqual(observations.ref, run.ref);
    assert.equal(observations.consistency, 'non_atomic');
    assert.equal(observations.revision, undefined);
    assert.equal(observations.owners[0].history.kind, 'not_provided');
    assert.equal(database.prepare('SELECT COUNT(*) AS count FROM client_requests').get().count, 1);
    assert.equal(database.prepare('SELECT COUNT(*) AS count FROM client_submitted_intents').get().count, 1);
    const cancelRef = {...run.ref, cancelId, expectedRevision: revision};
    assert.deepEqual(accepted, {kind: 'accepted', attemptRef: {operation: 'cancel', attemptId: 'accepted-invocation'},
      cancellation: {kind: 'accepted', ref: run.ref, cancelRef, revision: revision + 1}});
    const already = await run.cancel({cancelId: 'already-operation', expectedRevision: revision + 1,
      attemptId: 'already-invocation'});
    assert.deepEqual(already, {kind: 'already_satisfied',
      attemptRef: {operation: 'cancel', attemptId: 'already-invocation'},
      cancellation: {kind: 'already_requested', ref: run.ref,
        cancelRef: {...run.ref, cancelId: 'already-operation', expectedRevision: revision + 1}, revision: revision + 1}});
    const originalLookup = await run.lookupCancellation(cancelRef);
    assert.deepEqual(originalLookup, {kind: 'found', cancellation: accepted.cancellation});
    releasePublication();
    const stopSignal = AbortSignal.timeout(15000);
    let stopped;
    do {
      stopped = await run.status();
      if (stopped.control.physical_stop === 'confirmed') break;
      await delay(10, undefined, {signal: stopSignal});
    } while (true);
    assert.equal(stopped.status, 'cancelled');
    assert.equal(stopped.result_available, false);
    assert.equal(computes, 0);
    await writeFile(output, JSON.stringify({ref: run.ref, submissionRef, cancelRef,
      before, conflict, accepted, already, replayAttempt, replayedRef: replayed.ref,
      observations, originalLookup, stopped, computes, snapshot: snapshot()}));
  } else if (phase === 'initial') {
    const program = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'));
    const submissionRef = client.newSubmission({nonce: requestId});
    await writeFile(join(directory, 'submission-ref.json'), JSON.stringify(submissionRef),
      {flag: 'wx', mode: 0o600});
    const run = await client.start(program, {submissionRef});
    console.log('INSTALLED_CANCEL_PHASE', 'submitted', new Date().toISOString());
    await publicationReady;
    const publishedBeforeStop = await run.status();
    assert.equal(publishedBeforeStop.status, boundary === 'physical-start' ? 'running' : 'succeeded');
    assert.equal(publishedBeforeStop.result_available, boundary !== 'physical-start');
    assert.equal(publishedBeforeStop.control.physical_stop, 'unknown');
    const status = publishedBeforeStop;
    console.log('INSTALLED_CANCEL_PHASE', 'terminal', status.status, new Date().toISOString());
    assert.equal(status.status, boundary === 'physical-start' ? 'running' : 'succeeded');
    const rows = boundary === 'physical-start' ? [] : await run.result('answer').all();
    console.log('INSTALLED_CANCEL_PHASE', 'read', rows.length);
    assert.deepEqual(rows, boundary === 'physical-start' ? [] : [{id: 1}, {id: 2}]);
    const cancelRef = {...run.ref, cancelId, expectedRevision: status.control.revision};
    await writeFile(join(directory, 'cancel-ref.json'), JSON.stringify(cancelRef),
      {flag: 'wx', mode: 0o600});
    // Select this operation's final transaction, not a numbered COMMIT from
    // another journal. Pending identity custody is committed before this point.
    DatabaseSync.prototype.exec = function(sql) {
      let finalOperation = false;
      if (sql === 'COMMIT' && faults === 0) {
        try {
          finalOperation = this.prepare(`SELECT outcome_wire FROM client_cancellation_operations
            WHERE cancel_id = ?`).get(cancelId)?.outcome_wire != null;
        } catch { /* Other existing Owner databases have no such table. */ }
      }
      if (finalOperation) {
        faults++;
        if (loss === 'after-commit') originalExec.call(this, sql);
        throw new Error('CANCELLATION_FINAL_COMMIT_REPLY_LOST');
      }
      return originalExec.call(this, sql);
    };
    let failure, explanation;
    try { await run.cancel({cancelId, expectedRevision: cancelRef.expectedRevision}); }
    catch (error) {
      failure = {code: error.code, cancelRef: error.cancelRef};
      explanation = explainCancellation(error);
    }
    finally { DatabaseSync.prototype.exec = originalExec; }
    console.log('INSTALLED_CANCEL_PHASE', 'cancel-returned', failure?.code);
    assert.deepEqual(failure, {code: 'CancellationUnknown', cancelRef});
    assert.equal(faults, 1);
    const afterCancellationBeforeStop = await run.status();
    if (boundary === 'physical-start') {
      assert.equal(afterCancellationBeforeStop.status, 'running');
      assert.deepEqual(afterCancellationBeforeStop.control, {
        revision: cancelRef.expectedRevision + (loss === 'after-commit' ? 1 : 0),
        cancellation_requested: loss === 'after-commit', physical_stop: 'unknown'});
    } else {
      assert.deepEqual(afterCancellationBeforeStop.control, publishedBeforeStop.control,
        'a committed Result wins while its physical owner is still held');
      assert.equal(afterCancellationBeforeStop.status, 'succeeded');
    }
    const originalLookup = await run.lookupCancellation(cancelRef);
    assert.deepEqual(originalLookup, loss === 'after-commit'
      ? {kind: 'found', cancellation: {ref: run.ref, cancelRef,
        kind: boundary === 'physical-start' ? 'accepted' : 'already_terminal',
        revision: cancelRef.expectedRevision + (boundary === 'physical-start' ? 1 : 0)}}
      : {kind: 'unknown', cancelRef});
    releasePublication();
    const stopSignal = AbortSignal.timeout(15000);
    let stopped;
    try {
      do {
        stopped = await run.status();
        if (stopped.control.physical_stop === 'confirmed') break;
        await delay(10, undefined, {signal: stopSignal});
      } while (true);
    } catch (failure) {
      // Retain independent journal facts before reporting the failed boundary.
      // A timeout is neither a stop receipt nor a successful mutation check.
      await writeFile(output, JSON.stringify({ref: run.ref, submissionRef, cancelRef,
        status, afterCancellationBeforeStop, lastObserved: stopped, originalLookup,
        faults, computes, boundary, snapshot: snapshot(), stopUnconfirmed: true}));
      throw failure;
    }
    const cancellationCommitted = boundary === 'physical-start' && loss === 'after-commit';
    assert.equal(stopped.status, cancellationCommitted ? 'cancelled' : 'succeeded');
    assert.equal(stopped.control.cancellation_requested, cancellationCommitted);
    assert.deepEqual(await run.lookupCancellation(cancelRef), originalLookup,
      'later physical-stop observation cannot rewrite the original cancel outcome');
    await writeFile(output, JSON.stringify({ref: run.ref, submissionRef, cancelRef, status, rows,
      publishedBeforeStop, afterCancellationBeforeStop, stopped, originalLookup,
      failure, explanation, faults, computes, boundary, snapshot: snapshot()}));
  } else {
    const request = await client.lookupSubmission(originalSubmission);
    console.log('INSTALLED_CANCEL_PHASE', 'request-found');
    assert.equal(request.kind, 'ready');
    const run = await client.attach(request.admission.ref);
    const before = snapshot();
    const callerRef = {...originalRef};
    const lookup = await run.lookupCancellation(callerRef);
    callerRef.cancelId = 'edited-after-lookup';
    const repeated = await run.lookupCancellation(originalRef);
    console.log('INSTALLED_CANCEL_PHASE', 'looked-up', lookup.kind);
    assert.deepEqual(repeated, lookup);
    assert.deepEqual(snapshot(), before);
    const status = await run.status();
    const explanation = explainCancellation(lookup);
    const formats = Object.fromEntries(['text', 'html', 'json'].map(format =>
      [format, formatCancellation(lookup, {format})]));
    await writeFile(output, JSON.stringify({ref: run.ref, request, lookup, repeated,
      explanation, repeatedExplanation: explainCancellation(repeated), formats,
      copiedExplanationAbsent: explainCancellation({...lookup}) === undefined,
      status, computes, snapshot: snapshot()}));
  }
} finally {
  releasePublication();
  DatabaseSync.prototype.exec = originalExec;
  database?.close();
  await client?.close();
  if (server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
  await host?.close();
  setDefaultCACertificates(originalCAs);
}
