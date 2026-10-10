import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const child = promisify(execFile);
for (const entrance of ['Local', 'HTTPS']) {
  test(`public ${entrance} generated Content Model approves the original Run after process exit without recapture`, async () => {
    const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix: 'generated-model-restart-', label: 'Generated Model process recovery'});
    const keys = generateKeyPairSync('ed25519');
    const path = join(scratch.path, 'fixture.json');
    await writeFile(path, JSON.stringify({root: scratch.path, entrance,
      expiresAt: new Date(Date.now() + 120000).toISOString(),
      privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'}),
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}), {mode: 0o600});
    const invoke = async phase => {
      // Await exit, not just output, before reopening the same owned Store.
      const {stdout} = await child(process.execPath,
        [fileURLToPath(new URL('./fixtures/generated-model-restart.mjs', import.meta.url)), path, phase],
        {cwd: fileURLToPath(new URL('../../', import.meta.url)), timeout: 30000, maxBuffer: 1024 * 1024});
      return JSON.parse(stdout.trim().split('\n').at(-1));
    };
    const first = await invoke('capture');
    assert.equal(first.status, 'waiting_checkpoint');
    assert.equal(first.reads, 1);
    assert.equal(first.generations, 1);
    assert.equal(first.calls, 0);
    const second = await invoke('approve');
    assert.notEqual(second.pid, first.pid);
    assert.deepEqual(second.ref, first.ref);
    assert.equal(second.status, 'succeeded');
    assert.equal(second.reads, 0);
    assert.equal(second.generations, 0);
    assert.equal(second.calls, 1);
    const third = await invoke('read');
    assert.notEqual(third.pid, second.pid);
    assert.notEqual(third.pid, first.pid);
    assert.deepEqual(third.ref, first.ref);
    assert.equal(third.status, 'succeeded');
    assert.equal(third.reads, 0);
    assert.equal(third.generations, 0);
    assert.equal(third.calls, 0);
    const expected = [{name: 'out.csv', outcome: 'ok', value: {reason: null, risk: 'high'}}];
    assert.deepEqual(second.rows, expected);
    assert.deepEqual(third.rows, expected);
    assert.equal(first.sends + second.sends + third.sends, 0);
    scratch.passed();
  });
}
