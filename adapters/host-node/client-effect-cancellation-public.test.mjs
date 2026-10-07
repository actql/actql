// Preserve the original cancel operation without settling or resending an
// applied Effect whose reply was lost. Expected provider records are authored
// independently in the existing Source/Compute/Effect fixture.
import assert from 'node:assert/strict';
import {execFile, execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {expectedOrgAfterSuccess, readComputeEffectInstallation} from
  '../connectors/salesforce/test/read-compute-effect.fixture.mjs';

const child = fileURLToPath(new URL('../../scripts/fixtures/client-effect-cancellation.child.mjs', import.meta.url));
const observe = (path, action, transport) => new Promise((resolve, reject) => {
  execFile(process.execPath, [child, path, action, transport], {timeout: 30_000},
    (error, stdout, stderr) => {
      if (error) { reject(Object.assign(error, {stdout, stderr})); return; }
      try { resolve(JSON.parse(stdout.trim().split('\n').at(-1))); }
      catch (cause) { reject(cause); }
    });
});
function cancellationCustody(directory) {
  const database = new DatabaseSync(join(directory, 'requests/client-requests.sqlite3'), {readOnly: true});
  try {
    return {operations: database.prepare(`SELECT cancel_id, expected_revision,
      outcome_wire, outcome_cid FROM client_cancellation_operations`).all().map(row => ({...row})),
    issued: database.prepare('SELECT issued_count FROM client_cancellation_custody').get().issued_count,
    requested: database.prepare('SELECT cancellation_requested FROM client_requests').get().cancellation_requested};
  } finally { database.close(); }
}

for (const transport of ['local', 'https']) {
  test(`${transport}: original cancellation cannot resolve an unknown Effect after restart`, async t => {
    const setup = await readComputeEffectInstallation(t, {org: {loseReplyAfterApply: [2]}});
    const requestId = `cancel-unknown-effect-${transport}`;
    const step = await setup.embedded(requestId, setup.program());
    assert.deepEqual(await step('submit'), {held: true});
    assert.equal(setup.writes().length, 0);
    assert.equal(setup.queries(), 1);
    assert.deepEqual(await step('answer'), {answered: ['committed']});
    assert.deepEqual(await step('resume'), {status: 'needs_reconciliation'});
    assert.equal(setup.writes().length, 2);
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
    if (transport === 'https') execFileSync('openssl', ['req', '-x509', '-nodes',
      '-newkey', 'rsa:2048', '-keyout', 'cancel-host.key', '-out', 'cancel-host.crt',
      '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: setup.root, stdio: 'ignore'});
    const path = join(setup.root, `embedded-${requestId}.json`);
    const {directory} = JSON.parse(await readFile(path, 'utf8'));
    const initial = await observe(path, 'cancel', transport);
    const cancelRef = JSON.parse(await readFile(`${path}.cancel-ref.json`, 'utf8'));
    const expected = {kind: 'found', cancellation: {ref: initial.ref, cancelRef,
      kind: 'accepted', revision: cancelRef.expectedRevision + 1}};
    assert.deepEqual(initial.first, expected);
    assert.deepEqual(initial.second, expected);
    assert.equal(initial.state.status, 'needs_reconciliation');
    assert.deepEqual(initial.state.next_action, {kind: 'reconcile', effects: ['save']});
    assert.equal(initial.state.control.physical_stop, 'confirmed');
    assert.equal(initial.state.control.cancellation_requested, true);
    assert.equal(initial.state.result_available, false);
    const custody = cancellationCustody(directory);
    assert.equal(custody.issued, 1);
    assert.equal(custody.requested, 1);
    assert.equal(custody.operations.length, 1);
    assert.deepEqual(JSON.parse(custody.operations[0].outcome_wire), expected.cancellation);
    const counts = {writes: setup.writes().length, queries: setup.queries(), targetReads: setup.targetReads()};
    // The original cancellation child has exited: both its Host and execution
    // owner are stopped before this fresh process performs read-only lookup.
    const restored = await observe(path, 'lookup', transport);
    assert.deepEqual(restored.ref, initial.ref);
    assert.deepEqual(restored.cancelRef, cancelRef);
    assert.equal(restored.state.run_id, initial.state.run_id);
    assert.equal(restored.state.status, 'needs_reconciliation');
    assert.deepEqual(restored.state.next_action, {kind: 'reconcile', effects: ['save']});
    assert.equal(restored.state.control.physical_stop, 'confirmed');
    assert.deepEqual(restored.first, expected);
    assert.deepEqual(restored.second, expected);
    if (transport === 'https') assert.equal(restored.deniedLookupCode, 'ClientConnectionDenied');
    assert.deepEqual(cancellationCustody(directory), custody);
    assert.deepEqual({writes: setup.writes().length, queries: setup.queries(), targetReads: setup.targetReads()}, counts);
    assert.deepEqual(setup.org.records(), expectedOrgAfterSuccess);
  });
}
