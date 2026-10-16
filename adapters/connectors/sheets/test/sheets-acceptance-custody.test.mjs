import assert from 'node:assert/strict';
import {mkdtemp, open, readFile, rm, stat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {closeSheetsAcceptanceCustody} from './sheets-public-acceptance.fixture.mjs';

async function custody(t) {
  const root = await mkdtemp(join(tmpdir(), 'sheets-custody-control-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'synthetic-state');
  await writeFile(path, 'independent fixture bytes', {mode: 0o600});
  return {root, path, before: await stat(path)};
}

test('explicit preservation closes handles in reverse order and retains exact original files', async t => {
  const {root, path, before} = await custody(t);
  const handle = await open(path, 'r');
  const order = [];
  const diagnostics = [];
  await closeSheetsAcceptanceCustody({root, preserveScratch: true,
    closers: [async () => {order.push('first'); await handle.close();}, async () => order.push('last')],
    diagnostic: message => diagnostics.push(message)});
  assert.deepEqual(order, ['last', 'first']);
  await assert.rejects(handle.stat(), {code: 'EBADF'});
  assert.equal(await readFile(path, 'utf8'), 'independent fixture bytes');
  const after = await stat(path);
  assert.equal(after.ino, before.ino);
  assert.equal(after.mode, before.mode);
  assert.deepEqual(diagnostics, [`Retained Sheets acceptance custody: ${root}`]);
});

test('default cleanup still removes disposable completed or nonrange custody after close', async t => {
  for (const rangeCommand of [false, true]) {
    const {root, path} = await custody(t);
    let closed = false;
    await closeSheetsAcceptanceCustody({root, rangeCommand, acceptanceComplete: true,
      preserveScratch: false, closers: [async () => {
        assert.equal(await readFile(path, 'utf8'), 'independent fixture bytes');
        closed = true;
      }]});
    assert.equal(closed, true);
    await assert.rejects(stat(root), {code: 'ENOENT'});
  }
});

test('uncertain range custody remains retained without explicit preservation', async t => {
  const {root, path} = await custody(t);
  const diagnostics = [];
  await closeSheetsAcceptanceCustody({root, rangeCommand: true, preserveScratch: false,
    diagnostic: message => diagnostics.push(message)});
  assert.equal(await readFile(path, 'utf8'), 'independent fixture bytes');
  assert.deepEqual(diagnostics, [`Retained range acceptance custody: ${root}`]);
});

test('preservation retains custody while propagating the original closer failure', async t => {
  const {root, path} = await custody(t);
  const failure = new Error('original synthetic cleanup failure');
  await assert.rejects(closeSheetsAcceptanceCustody({root, preserveScratch: true,
    closers: [async () => {throw failure;}]}), error => error === failure);
  assert.equal(await readFile(path, 'utf8'), 'independent fixture bytes');
});

test('the existing environment flag preserves TLS-shaped custody without changing other flag values', async t => {
  const previous = process.env.ACTQL_TEST_PRESERVE_SCRATCH;
  try {
    for (const value of ['1', '0', undefined]) {
      const {root, path} = await custody(t);
      if (value === undefined) delete process.env.ACTQL_TEST_PRESERVE_SCRATCH;
      else process.env.ACTQL_TEST_PRESERVE_SCRATCH = value;
      await closeSheetsAcceptanceCustody({root});
      if (value === '1') assert.equal(await readFile(path, 'utf8'), 'independent fixture bytes');
      else await assert.rejects(stat(root), {code: 'ENOENT'});
    }
  } finally {
    if (previous === undefined) delete process.env.ACTQL_TEST_PRESERVE_SCRATCH;
    else process.env.ACTQL_TEST_PRESERVE_SCRATCH = previous;
  }
});
