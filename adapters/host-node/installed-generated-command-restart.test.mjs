// Actual SERIALIZE runs only in the first process. Later processes restore the
// original approved request and actual Host Store bytes; no Source or encoder
// is called again. Unknown receiver writes retain their original custody.
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
const expectedCid = 'sha256:11af3859185fd4b8e2cef2ba824fdddf63b8a6fbfa26aea783660fefda5459de';
const expectedBytes = Buffer.from('name\n"approved.csv"\n');
async function processFixture(root, entrance, fault, modelCommand = false,
  modelApprovalRequired = false, sourceFormat = 'program', retainSerializationMetadata = false,
  exposeAttachmentResult = false, preserveOrder = false) {
  const keys = generateKeyPairSync('ed25519');
  const path = join(root, 'fixture.json');
  await writeFile(path, JSON.stringify({root, entrance, fault, generatedCommand: true, modelCommand,
    modelApprovalRequired, sourceFormat, retainSerializationMetadata, exposeAttachmentResult, preserveOrder,
    expiresAt: new Date(Date.now() + 120000).toISOString(),
    privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'}),
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}));
  return async phase => {
    // Opt-in diagnostics stay in this owned fixture directory. They do not
    // alter the approval path, deadlines, execution work or expected bytes.
    const diagnostics = process.env.ACTQL_CONTENT_CPU_PROFILE === '1' &&
      phase === 'approve-model' ? ['--cpu-prof', '--cpu-prof-dir', root,
        '--cpu-prof-name', 'approve-model.cpuprofile'] : [];
    const {stdout} = await child(process.execPath,
      [...diagnostics, fileURLToPath(new URL('./fixtures/content-command-restart.mjs', import.meta.url)), path, phase],
      {cwd: fileURLToPath(new URL('../../', import.meta.url)), timeout: 30000, maxBuffer: 1024 * 1024});
    return JSON.parse(stdout.trim().split('\n').at(-1));
  };
}
const assertRows = rows => {
  assert.equal(rows.length, 1);
  assert.deepEqual(Object.keys(rows[0]), ['destination', 'name', 'content']);
  assert.deepEqual(rows[0].destination, resource('d'));
  assert.equal(rows[0].name, 'approved.csv');
  assert.equal(rows[0].content.media_type, 'text/csv');
  assert.equal(rows[0].content.metadata.content_cid, expectedCid);
  assert.equal(rows[0].content.metadata.size_bytes, expectedBytes.length);
};
for (const entrance of ['Local', 'HTTPS']) {
  for (const preserveOrder of entrance === 'Local' ? [false, true] : [false]) {
  test(`public ${entrance} intermediate SERIALIZE Result survives separate-process COMMAND approval and read (${preserveOrder ? 'PRESERVE ORDER' : 'ORDER BY'})`, async t => {
    const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix: 'serialization-root-restart-', label: 'Intermediate SERIALIZE Result process recovery'});
    const invoke = await processFixture(scratch.path, entrance, undefined,
      false, false, 'program', false, true, preserveOrder);
    const first = await invoke('capture');
    assert.equal(first.status, 'waiting_checkpoint');
    assert.deepEqual([first.reads, first.generations, first.sends, first.writeGrants], [1, 1, 0, 0]);
    const approved = await invoke('approve');
    const reread = await invoke('read');
    assert.equal(new Set([first.pid, approved.pid, reread.pid]).size, 3);
    for (const [phase, sends, grants] of [[approved, 1, 1], [reread, 0, 0]]) {
      assert.deepEqual(phase.ref, first.ref);
      assert.equal(phase.status, 'succeeded');
      assert.deepEqual([phase.reads, phase.generations, phase.sends, phase.writeGrants], [0, 0, sends, grants]);
      assertRows(phase.rows);
      assert.equal(phase.attachmentRows.length, 1);
      const row = phase.attachmentRows[0];
      assert.deepEqual(Object.keys(row), ['name', 'content', 'media_type', 'size_bytes', 'row_count']);
      assert.equal(row.name, 'approved.csv');
      assert.equal(row.media_type, 'text/csv');
      assert.equal(row.size_bytes, 20);
      assert.equal(row.row_count, 1);
      assert.equal(row.content.media_type, 'text/csv');
      assert.equal(row.content.metadata.content_cid, expectedCid);
      assert.equal(row.content.metadata.size_bytes, 20);
    }
    assert.deepEqual(approved.rows, reread.rows);
    assert.deepEqual(approved.attachmentRows, reread.attachmentRows,
      'the original intermediate generation remains a distinct public Result after restart');
    assert.deepEqual(approved.attachmentRows[0].content, approved.rows[0].content,
      'the intermediate Result and COMMAND terminal retain the same issued ContentRef');
    assert.deepEqual(await readFile(join(scratch.path, 'approved.csv')), expectedBytes);
    const receipt = JSON.parse(await readFile(join(scratch.path, 'receiver-receipt.json'), 'utf8'));
    assert.equal(receipt.content_cid, expectedCid);
    scratch.passed();
  });
  }
  test(`public ${entrance} complete SERIALIZE row survives separate-process COMMAND approval and read`, async t => {
    const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix: 'serialization-row-restart-', label: 'Complete SERIALIZE row process recovery'});
    const invoke = await processFixture(scratch.path, entrance, undefined,
      false, false, 'program', true);
    const first = await invoke('capture');
    assert.equal(first.status, 'waiting_checkpoint');
    assert.deepEqual([first.reads, first.generations, first.sends, first.writeGrants], [1, 1, 0, 0]);
    const approved = await invoke('approve');
    const reread = await invoke('read');
    assert.equal(new Set([first.pid, approved.pid, reread.pid]).size, 3);
    for (const [phase, sends, grants] of [[approved, 1, 1], [reread, 0, 0]]) {
      assert.deepEqual(phase.ref, first.ref);
      assert.equal(phase.status, 'succeeded');
      assert.deepEqual([phase.reads, phase.generations, phase.sends, phase.writeGrants], [0, 0, sends, grants]);
      assert.equal(phase.rows.length, 1);
      const row = phase.rows[0];
      assert.deepEqual(Object.keys(row), ['destination', 'name', 'content', 'media_type', 'size_bytes', 'row_count']);
      assert.deepEqual(row.destination, resource('d'));
      assert.equal(row.name, 'approved.csv');
      assert.equal(row.media_type, 'text/csv');
      assert.equal(row.size_bytes, 20);
      assert.equal(row.row_count, 1);
      assert.equal(row.content.media_type, 'text/csv');
      assert.equal(row.content.metadata.content_cid, expectedCid);
      assert.equal(row.content.metadata.size_bytes, 20);
    }
    assert.deepEqual(approved.rows, reread.rows,
      'a new process reads the same issued Ref and every saved serializer field');
    assert.deepEqual(await readFile(join(scratch.path, 'approved.csv')), expectedBytes);
    const receipt = JSON.parse(await readFile(join(scratch.path, 'receiver-receipt.json'), 'utf8'));
    assert.equal(receipt.content_cid, expectedCid);
    scratch.passed();
  });
}
test('public Local intermediate SERIALIZE Result lost COMMAND reply remains unknown without resend', async t => {
  const parent = fileURLToPath(new URL('../../_build/', import.meta.url));
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'serialization-root-unknown-'));
  t.after(() => t.diagnostic(`Unknown intermediate Content COMMAND custody retained: ${root}`));
  const invoke = await processFixture(root, 'Local', 'lost_reply',
    false, false, 'program', false, true);
  const first = await invoke('capture');
  assert.equal(first.status, 'waiting_checkpoint');
  assert.deepEqual([first.reads, first.generations, first.sends, first.writeGrants], [1, 1, 0, 0]);
  const approved = await invoke('approve');
  const reread = await invoke('read');
  assert.equal(new Set([first.pid, approved.pid, reread.pid]).size, 3);
  for (const [phase, sends, grants] of [[approved, 1, 1], [reread, 0, 0]]) {
    assert.deepEqual(phase.ref, first.ref);
    assert.equal(phase.status, 'needs_reconciliation');
    assert.deepEqual([phase.reads, phase.generations, phase.sends, phase.writeGrants], [0, 0, sends, grants]);
  }
  assert.deepEqual(await readFile(join(root, 'approved.csv')), expectedBytes);
  const receipt = JSON.parse(await readFile(join(root, 'receiver-receipt.json'), 'utf8'));
  assert.equal(receipt.content_cid, expectedCid);
});

// Complement the existing JSON recovery matrix with real text submissions.
// Every phase runs in a new process; later phases are denied Source read access.
for (const [entrance, format, fault] of [
  ['Local', 'sql', undefined], ['HTTPS', 'aql-text', undefined],
  ['Local', 'aql-text', 'lost_reply'], ['HTTPS', 'sql', 'lost_reply'],
]) {
  test(`public ${entrance} ${format} generated COMMAND separate-process ${fault ?? 'approval'} recovery`, async t => {
    const parent = fileURLToPath(new URL('../../_build/', import.meta.url));
    const unknown = fault === 'lost_reply';
    let scratch, root;
    if (unknown) {
      await mkdir(parent, {recursive: true});
      root = await mkdtemp(join(parent, 'text-command-unknown-'));
      t.after(() => t.diagnostic(`Unknown text COMMAND custody retained: ${root}`));
    } else {
      scratch = await createOwnedScratch({parent, prefix: 'text-command-restart-',
        label: 'Text Command process recovery'});
      root = scratch.path;
    }
    const invoke = await processFixture(root, entrance, fault, false, false, format);
    const first = await invoke('capture');
    assert.equal(first.status, 'waiting_checkpoint');
    assert.deepEqual([first.reads, first.generations, first.sends, first.writeGrants], [1, 1, 0, 0]);
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
    assert.deepEqual(await readFile(join(root, 'approved.csv')), expectedBytes);
    const receipt = JSON.parse(await readFile(join(root, 'receiver-receipt.json'), 'utf8'));
    assert.equal(receipt.content_cid, expectedCid);
    assert.match(receipt.request_cid, /^sha256:[0-9a-f]{64}$/u);
    if (unknown) {
      assert.equal(second.result_available, false);
      assert.equal(third.result_available, false);
      await writeFile(join(root, 'process-evidence.json'), JSON.stringify({first, second, third}));
    } else {
      assertRows(second.rows);
      assert.deepEqual(second.rows, third.rows);
      scratch.passed();
    }
  });
}
for (const entrance of ['Local', 'HTTPS']) {
  test(`public ${entrance} Model approval before generated COMMAND survives separate processes without input replay`, async t => {
    const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix: 'generated-model-approval-restart-', label: 'Generated Model then COMMAND approval recovery'});
    const invoke = await processFixture(scratch.path, entrance, undefined, true, true);
    const capture = await invoke('capture');
    assert.equal(capture.status, 'waiting_checkpoint');
    assert.deepEqual([capture.reads, capture.generations, capture.modelCalls, capture.sends,
      capture.writeGrants], [1, 1, 0, 0, 0]);
    const model = await invoke('approve-model');
    t.diagnostic(JSON.stringify({phase: 'approve-model', persistenceTrace: model.persistenceTrace,
      computeTrace: model.computeTrace, observationProgress: model.observationProgress}));
    assert.notEqual(model.pid, capture.pid);
    assert.deepEqual(model.ref, capture.ref);
    assert.equal(model.status, 'waiting_checkpoint');
    assert.deepEqual([model.reads, model.generations, model.modelCalls, model.sends,
      model.writeGrants], [0, 0, 1, 0, 0]);
    const command = await invoke('approve');
    assert.notEqual(command.pid, model.pid);
    assert.deepEqual(command.ref, capture.ref);
    assert.equal(command.status, 'succeeded');
    assert.deepEqual([command.reads, command.generations, command.modelCalls, command.sends,
      command.writeGrants], [0, 0, 0, 1, 1]);
    const read = await invoke('read');
    assert.notEqual(read.pid, command.pid);
    assert.deepEqual(read.ref, capture.ref);
    assert.equal(read.status, 'succeeded');
    assert.deepEqual([read.reads, read.generations, read.modelCalls, read.sends,
      read.writeGrants], [0, 0, 0, 0, 0]);
    assertRows(command.rows);
    assert.deepEqual(command.rows, read.rows);
    assert.deepEqual(await readFile(join(scratch.path, 'approved.csv')), expectedBytes);
    const receipt = JSON.parse(await readFile(join(scratch.path, 'receiver-receipt.json'), 'utf8'));
    assert.equal(receipt.content_cid, expectedCid);
    assert.match(receipt.request_cid, /^sha256:[0-9a-f]{64}$/u);
    scratch.passed();
  });
  for (const {modelCommand, fault} of [false, true].flatMap(modelCommand =>
    (modelCommand ? [undefined, 'lost_reply'] : [undefined, 'lost_reply', 'stop_projection'])
      .map(fault => ({modelCommand, fault})))) {
    test(`public ${entrance} ${modelCommand ? 'mixed Model ' : ''}generated COMMAND separate-process ${fault ?? 'approval'} recovery retains original bytes and never resends`, async t => {
      const parent = fileURLToPath(new URL('../../_build/', import.meta.url));
      const unknown = fault === 'lost_reply';
      let scratch, root;
      if (unknown) {
        await mkdir(parent, {recursive: true});
        root = await mkdtemp(join(parent, 'generated-command-unknown-'));
        t.after(() => t.diagnostic(`Unknown generated COMMAND custody retained: ${root}`));
      } else {
        scratch = await createOwnedScratch({parent, prefix: 'generated-command-restart-',
          label: 'Generated Command process recovery'});
        root = scratch.path;
      }
      const invoke = await processFixture(root, entrance, fault, modelCommand);
      const first = await invoke('capture');
      assert.equal(first.status, 'waiting_checkpoint');
      assert.equal(first.reads, 1);
      assert.equal(first.sends, 0);
      assert.equal(first.writeGrants, 0);
      if (modelCommand) assert.deepEqual([first.modelCalls, first.generations], [1, 1]);
      const second = await invoke('approve');
      assert.notEqual(second.pid, first.pid);
      assert.deepEqual(second.ref, first.ref);
      assert.equal(second.status, fault === undefined ? 'succeeded' : 'needs_reconciliation');
      assert.equal(second.reads, 0);
      assert.equal(second.sends, 1);
      assert.equal(second.writeGrants, 1);
      if (modelCommand) assert.deepEqual([second.modelCalls, second.generations], [0, 0]);
      const third = await invoke('read');
      assert.notEqual(third.pid, second.pid);
      assert.deepEqual(third.ref, first.ref);
      assert.equal(third.status, unknown ? 'needs_reconciliation' : 'succeeded');
      assert.equal(third.reads, 0);
      assert.equal(third.sends, 0);
      assert.equal(third.writeGrants, 0);
      if (modelCommand) assert.deepEqual([third.modelCalls, third.generations], [0, 0]);
      assert.deepEqual(await readFile(join(root, 'approved.csv')), expectedBytes);
      const receipt = JSON.parse(await readFile(join(root, 'receiver-receipt.json'), 'utf8'));
      assert.equal(receipt.content_cid, expectedCid);
      assert.match(receipt.request_cid, /^sha256:[0-9a-f]{64}$/u);
      if (unknown) {
        assert.equal(second.result_available, false);
        assert.equal(third.result_available, false);
        await writeFile(join(root, 'process-evidence.json'), JSON.stringify({first, second, third}));
      } else {
        assertRows(third.rows);
        if (fault === undefined) assert.deepEqual(second.rows, third.rows);
        if (fault === 'stop_projection') {
          const response = [{useCid: cid({write: 1}), statusCode: 201, body: '{}'}];
          assert.deepEqual(second.projections, response);
          assert.deepEqual(third.projections, response);
        }
        scratch.passed();
      }
    });
  }
}
