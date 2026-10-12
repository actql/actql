import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {cid, resource} from './fixtures/file-listing-source.fixture.mjs';

const child = promisify(execFile);
async function processFixture(root, entrance, fault, sourceFormat = 'program') {
  const keys = generateKeyPairSync('ed25519');
  const path = join(root, 'fixture.json');
  await writeFile(path, JSON.stringify({root, entrance, fault, sourceFormat,
    expiresAt: new Date(Date.now() + 120000).toISOString(),
    privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'}),
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}));
  return async phase => {
    const {stdout} = await child(process.execPath,
      [fileURLToPath(new URL('./fixtures/content-command-restart.mjs', import.meta.url)), path, phase],
      {cwd: fileURLToPath(new URL('../../', import.meta.url)), timeout: 30000, maxBuffer: 1024 * 1024});
    return JSON.parse(stdout.trim().split('\n').at(-1));
  };
}
// Text submits the same normal Source/COMMAND contract without a SERIALIZE
// step. This is issued-Content consumer recovery, not keyed capture acceptance.
for (const [entrance, format, fault] of [
  ['Local', 'sql', undefined], ['HTTPS', 'aql-text', 'lost_reply'],
]) {
  test(`public ${entrance} ${format} Content COMMAND process recovery retains issued bytes without regeneration`, async t => {
    const parent = fileURLToPath(new URL('../../_build/', import.meta.url));
    const unknown = fault === 'lost_reply';
    let root, scratch;
    if (unknown) {
      await mkdir(parent, {recursive: true});
      root = await mkdtemp(join(parent, 'source-text-command-unknown-'));
      t.after(() => t.diagnostic(`Unknown Source text COMMAND custody retained: ${root}`));
    } else {
      scratch = await createOwnedScratch({parent, prefix: 'source-text-command-restart-',
        label: 'Issued Content text COMMAND recovery'});
      root = scratch.path;
    }
    const invoke = await processFixture(root, entrance, fault, format);
    const first = await invoke('capture');
    assert.equal(first.status, 'waiting_checkpoint');
    assert.deepEqual([first.reads, first.generations, first.sends, first.writeGrants], [1, 0, 0, 0]);
    const second = await invoke('approve');
    assert.notEqual(second.pid, first.pid);
    assert.deepEqual(second.ref, first.ref);
    assert.equal(second.status, unknown ? 'needs_reconciliation' : 'succeeded');
    assert.deepEqual([second.reads, second.generations, second.sends, second.writeGrants], [0, 0, 1, 1]);
    const third = await invoke('read');
    assert.notEqual(third.pid, second.pid);
    assert.deepEqual(third.ref, first.ref);
    assert.equal(third.status, unknown ? 'needs_reconciliation' : 'succeeded');
    assert.deepEqual([third.reads, third.generations, third.sends, third.writeGrants], [0, 0, 0, 0]);
    assert.deepEqual(await readFile(join(root, 'approved.csv')), Buffer.from('id\n'));
    const receipt = JSON.parse(await readFile(join(root, 'receiver-receipt.json'), 'utf8'));
    const saved = JSON.parse(await readFile(join(root, 'content-custody.json'), 'utf8'));
    assert.equal(receipt.content_cid, saved.description.contentCid);
    assert.match(receipt.request_cid, /^sha256:[0-9a-f]{64}$/u);
    if (unknown) {
      assert.equal(second.result_available, false);
      assert.equal(third.result_available, false);
      await writeFile(join(root, 'process-evidence.json'), JSON.stringify({first, second, third}));
    } else {
      const expected = [{destination: resource('d'), name: 'approved.csv',
        content: JSON.parse(saved.description.wire)}];
      assert.deepEqual(second.rows, expected);
      assert.deepEqual(third.rows, expected);
      scratch.passed();
    }
  });
}
for (const entrance of ['Local', 'HTTPS']) {
  test(`public ${entrance} Content COMMAND recovers approval in a different process without recapture`, async () => {
    const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix: 'content-command-restart-', label: 'Content Command process recovery'});
    const invoke = await processFixture(scratch.path, entrance);
    const first = await invoke('capture');
    assert.equal(first.status, 'waiting_checkpoint');
    assert.equal(first.reads, 1);
    assert.equal(first.sends, 0);
    const second = await invoke('approve');
    assert.notEqual(second.pid, first.pid, 'the first Host process actually exited');
    assert.deepEqual(second.ref, first.ref);
    assert.equal(second.status, 'succeeded');
    assert.equal(second.reads, 0);
    assert.equal(second.sends, 1);
    const third = await invoke('read');
    assert.notEqual(third.pid, second.pid);
    assert.equal(third.reads, 0);
    assert.equal(third.sends, 0);
    assert.deepEqual(third.ref, first.ref);
    const saved = JSON.parse(await readFile(join(scratch.path, 'content-custody.json'), 'utf8'));
    const expected = [{destination: resource('d'), name: 'approved.csv',
      content: JSON.parse(saved.description.wire)}];
    assert.deepEqual(second.rows, expected);
    assert.deepEqual(third.rows, expected);
    assert.deepEqual(await readFile(join(scratch.path, 'approved.csv')), Buffer.from('id\n'));
    scratch.passed();
  });
  test(`public ${entrance} Content COMMAND lost reply remains unknown after process recovery without resend`, async t => {
    // Unknown responsibility deliberately remains unresolved. Keep the original
    // Run/Ledger, workspace holding and provider receipt, rather than declaring
    // cleanup complete or deleting authority evidence when the assertion passes.
    const parent = fileURLToPath(new URL('../../_build/', import.meta.url));
    await mkdir(parent, {recursive: true});
    const root = await mkdtemp(join(parent, 'content-command-unknown-'));
    t.after(() => t.diagnostic(`Unknown Command custody and receipt retained: ${root}`));
    const invoke = await processFixture(root, entrance, 'lost_reply');
    const first = await invoke('capture');
    assert.equal(first.status, 'waiting_checkpoint');
    assert.equal(first.sends, 0);
    const second = await invoke('approve');
    assert.notEqual(second.pid, first.pid);
    assert.deepEqual(second.ref, first.ref);
    assert.equal(second.status, 'needs_reconciliation');
    assert.equal(second.result_available, false);
    assert.equal(second.reads, 0);
    assert.equal(second.sends, 1);
    const third = await invoke('read');
    assert.notEqual(third.pid, second.pid);
    assert.deepEqual(third.ref, first.ref);
    assert.equal(third.status, 'needs_reconciliation');
    assert.equal(third.result_available, false);
    assert.equal(third.reads, 0);
    assert.equal(third.sends, 0);
    assert.deepEqual(await readFile(join(root, 'approved.csv')), Buffer.from('id\n'));
    const receipt = JSON.parse(await readFile(join(root, 'receiver-receipt.json'), 'utf8'));
    const custody = JSON.parse(await readFile(join(root, 'content-custody.json'), 'utf8'));
    assert.equal(receipt.content_cid, custody.description.contentCid);
    assert.match(receipt.request_cid, /^sha256:[0-9a-f]{64}$/u);
    await writeFile(join(root, 'process-evidence.json'), JSON.stringify({first, second, third}));
  });
  test(`public ${entrance} Content COMMAND reuses its saved response after process recovery without another write grant`, async () => {
    const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix: 'content-command-response-', label: 'Content Command saved response recovery'});
    const invoke = await processFixture(scratch.path, entrance, 'stop_projection');
    const first = await invoke('capture');
    assert.equal(first.status, 'waiting_checkpoint');
    assert.equal(first.sends, 0);
    assert.equal(first.writeGrants, 0);
    const second = await invoke('approve');
    assert.notEqual(second.pid, first.pid);
    assert.deepEqual(second.ref, first.ref);
    assert.equal(second.status, 'needs_reconciliation');
    assert.equal(second.result_available, false);
    assert.equal(second.reads, 0);
    assert.equal(second.sends, 1);
    assert.equal(second.writeGrants, 1);
    const expectedResponse = [{useCid: cid({write: 1}), statusCode: 201, body: '{}'}];
    assert.deepEqual(second.projections, expectedResponse);
    const third = await invoke('read');
    assert.notEqual(third.pid, second.pid);
    assert.deepEqual(third.ref, first.ref);
    assert.equal(third.status, 'succeeded');
    assert.equal(third.reads, 0);
    assert.equal(third.sends, 0);
    assert.equal(third.writeGrants, 0, 'a saved response is not a new write authorization');
    assert.deepEqual(third.projections, expectedResponse);
    const saved = JSON.parse(await readFile(join(scratch.path, 'content-custody.json'), 'utf8'));
    assert.deepEqual(third.rows, [{destination: resource('d'), name: 'approved.csv',
      content: JSON.parse(saved.description.wire)}]);
    assert.deepEqual(await readFile(join(scratch.path, 'approved.csv')), Buffer.from('id\n'));
    scratch.passed();
  });
}
