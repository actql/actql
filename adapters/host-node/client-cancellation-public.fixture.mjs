// Use the installed Host without replacing its cancellation or dispatch owner.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect, explainCancellation, formatCancellation} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const {directory, entrance, phase, loss, output, cancelRef: originalRef,
  submissionRef: originalSubmission} = JSON.parse(process.argv[2]);
const requestId = 'original-cancel-successful-run';
const cancelId = 'original-cancel-operation';
const keys = generateKeyPairSync('ed25519');
let computes = 0;
const authorization = {
  accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'cancel-operation-fixture', entries: [{entry_id: 'write', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  observe(name, detail) {
    if (name === 'computed') computes++;
    console.log('INSTALLED_CANCEL_OWNER', name, detail?.code ?? '', new Date().toISOString());
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
    revision, cancellation_requested, physical_close_confirmed FROM client_requests`).all().map(row => ({...row})),
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
  if (phase === 'initial') {
    const program = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'));
    const submissionRef = client.newSubmission({nonce: requestId});
    const run = await client.start(program, {submissionRef});
    console.log('INSTALLED_CANCEL_PHASE', 'submitted', new Date().toISOString());
    const status = await run.wait({signal: AbortSignal.timeout(15000)});
    console.log('INSTALLED_CANCEL_PHASE', 'terminal', status.status, new Date().toISOString());
    assert.equal(status.status, 'succeeded');
    const rows = await run.result('answer').all();
    console.log('INSTALLED_CANCEL_PHASE', 'read', rows.length);
    assert.deepEqual(rows, [{id: 1}, {id: 2}]);
    const cancelRef = {...run.ref, cancelId, expectedRevision: status.control.revision};
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
    await writeFile(output, JSON.stringify({ref: run.ref, submissionRef, cancelRef, status, rows,
      failure, explanation, faults, computes, snapshot: snapshot()}));
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
  DatabaseSync.prototype.exec = originalExec;
  database?.close();
  await client?.close();
  if (server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
  await host?.close();
  setDefaultCACertificates(originalCAs);
}
