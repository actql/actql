import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

for (const loseReply of [false, true]) {
  test(`actual Host named submission survives a new process${loseReply ? ' after lost reply' : ''} without recomputing`, async t => {
    const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-a-named-host-',
      label: 'actual scoped-name Host process recovery'});
    t.diagnostic(`Original named Host state and evidence: ${scratch.path}`);
    const keys = generateKeyPairSync('ed25519');
    await writeFile(join(scratch.path, 'keys.json'), JSON.stringify({
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'}),
      privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}), {mode: 0o600, flag: 'wx'});
    const fixture = fileURLToPath(new URL('./fixtures/named-submission-host.fixture.mjs', import.meta.url));
    const run = async phase => {
      const child = spawnSync(process.execPath, [fixture], {input: JSON.stringify({root: scratch.path, phase, loseReply}),
        encoding: 'utf8', timeout: 30000, killSignal: 'SIGTERM', maxBuffer: 4 * 1024 * 1024});
      assert.equal(child.error, undefined);
      assert.equal(child.status, 0, child.stderr);
      assert.equal(child.signal, null);
      return JSON.parse(await readFile(join(scratch.path, phase + '.json'), 'utf8'));
    };
    const first = await run('first');
    const second = await run('second');
    assert.notEqual(first.pid, second.pid);
    assert.notDeepEqual(first.request.submissionRef.epoch, second.request.submissionRef.epoch);
    assert.deepEqual(second.outcome.submissionRef, first.outcome.submissionRef);
    assert.deepEqual(second.outcome.admission.ref, first.outcome.admission.ref);
    assert.deepEqual(second.rows, first.rows);
    assert.equal(first.computes, 1);
    assert.equal(second.computes, 0);
    assert.equal(first.unknown, loseReply);
    assert.equal(second.unknown, false);
    const db = new DatabaseSync(join(scratch.path, 'host/requests/client-requests.sqlite3'), {readOnly: true});
    try {
      for (const table of ['client_requests', 'client_submitted_intents', 'client_submission_names']) {
        assert.equal(db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 1);
      }
    } finally {db.close();}
    scratch.passed();
  });
}
