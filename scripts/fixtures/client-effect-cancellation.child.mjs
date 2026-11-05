// Public cancellation over an existing uncertain Effect. Each invocation owns
// its real Host and execution process; the parent owns only the HTTPS provider.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {join} from 'node:path';
import {connect} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from '../../adapters/host-node/embedded-local.mjs';
import {openInstalledRemoteHttpHost} from '../../adapters/host-node/embedded-local.mjs';

const [path, action, transport] = process.argv.slice(2);
assert.ok(['cancel', 'lookup'].includes(action));
assert.ok(['local', 'https'].includes(transport));
const read = file => JSON.parse(readFileSync(file, 'utf8'));
const installed = read(path);
const ref = read(`${path}.ref.json`);
const submissionRef = read(`${path}.submission-ref.json`);
const cancelPath = `${path}.cancel-ref.json`;
const installation = {directory: installed.directory,
  sourceProfilePath: installed.sourceProfilePath,
  effectProfilePath: installed.effectProfilePath,
  resolveSourceSecret: async () => 'test-only-secret',
  resolveEffectSecret: async () => 'test-only-secret',
  authorization: installed.authorization};
let host, server, client;
let credential = 'fixture-owner';
let cancelRef, lost = false;
const originalExec = DatabaseSync.prototype.exec;
// The Journal captures this connection's original SQLite methods while the
// Host opens. Install the hook before that capture, but arm it only after the
// SAME cancellation reference is saved. Lookup and other COMMITs stay intact.
if (action === 'cancel') DatabaseSync.prototype.exec = function(sql) {
  const outcome = cancelRef !== undefined && sql === 'COMMIT' && !lost && this.prepare(
    "SELECT name FROM sqlite_master WHERE name = 'client_cancellation_operations'").get() !== undefined
    ? this.prepare('SELECT outcome_wire FROM client_cancellation_operations WHERE cancel_id = ?')
      .get(cancelRef.cancelId)?.outcome_wire : undefined;
  const result = originalExec.call(this, sql);
  if (outcome != null) {
    lost = true;
    throw new Error('FixtureEffectCancellationCommitReplyLost');
  }
  return result;
};
try {
  if (transport === 'https') {
    const cert = readFileSync(join(installed.directory, '..', 'cancel-host.crt'));
    setDefaultCACertificates([...getCACertificates('default'), cert.toString()]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer fixture-owner' ? userInfo().username :
        header === 'Bearer fixture-other' ? 'fixture-other-principal' : undefined});
    server = createServer({key: readFileSync(join(installed.directory, '..', 'cancel-host.key')),
      cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', durability: 'durable', token: () => credential,
      endpoint: `https://127.0.0.1:${server.address().port}/`});
  } else {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      durability: 'durable', installation});
  }
  const lookup = await client.lookupSubmission(submissionRef);
  assert.equal(lookup.kind, 'ready');
  assert.deepEqual(lookup.admission.ref, ref);
  const run = await client.attach(ref);
  const before = await run.status();
  assert.equal(before.status, 'needs_reconciliation');
  assert.equal(before.control.physical_stop, 'confirmed');
  if (action === 'cancel') {
    cancelRef = {...ref, cancelId: 'original-unknown-effect-cancel',
      expectedRevision: before.control.revision};
    writeFileSync(cancelPath, JSON.stringify(cancelRef) + '\n', {flag: 'wx', mode: 0o600});
    await assert.rejects(run.cancel({cancelId: cancelRef.cancelId,
      expectedRevision: cancelRef.expectedRevision}), error => {
      assert.equal(error.code, 'CancellationUnknown');
      assert.deepEqual(error.cancelRef, cancelRef);
      return true;
    });
    assert.equal(lost, true, 'the original cancellation committed before its reply was lost');
  } else cancelRef = read(cancelPath);
  const first = await run.lookupCancellation(cancelRef);
  const second = await run.lookupCancellation(cancelRef);
  assert.deepEqual(first, second);
  let deniedLookupCode;
  if (action === 'lookup' && transport === 'https') {
    // Original custody is not current authority. Change the authenticated
    // actor on the actual connection without allocating another operation.
    credential = 'fixture-other';
    await assert.rejects(run.lookupCancellation(cancelRef), error => {
      assert.equal(error.code, 'ClientConnectionDenied');
      deniedLookupCode = error.code;
      return true;
    });
    credential = 'fixture-owner';
    assert.deepEqual(await run.lookupCancellation(cancelRef), first);
  }
  const state = await run.status();
  assert.equal(state.status, 'needs_reconciliation');
  assert.equal(state.control.cancellation_requested, true);
  assert.equal(state.result_available, false);
  console.log(JSON.stringify({ref, cancelRef, first, second, state, deniedLookupCode}));
} finally {
  try {
    await client?.close();
    if (server !== undefined) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    await host?.close();
  } finally { DatabaseSync.prototype.exec = originalExec; }
}
// The installed Local Host lives for this process, beyond Client disconnect.
// The parent waits for exit before starting the recovery process.
process.exit(0);
