import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {mkdir, readdir, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {installLocalSnapshotStore, localSnapshotStore} from '../local-node/retained-store.mjs';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const statements = [];
function collect(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'ExpressionStatement' && node.expression.type === 'AssignmentExpression' &&
      node.expression.left.name === 'localSnapshotConfiguration') statements.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(ast);
assert.equal(statements.length, 1);
const install = compileFunction(`let localSnapshotConfiguration;
  ${source.slice(statements[0].start, statements[0].end)}
  return localSnapshotConfiguration;`, ['installStore', 'mkdir', 'snapshotDirectory',
  'snapshotFactory', 'createLocalRetainedStore', 'authorization']);

// The installed callback is extracted from the actual Host. The first case
// exercises its real filesystem Store; the other cases stop at explicit ports.
// No test here supplies a Run reservation, Host admission or publication Store.
test('Host snapshot installation performs no filesystem work until its original lease is requested', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-host-snapshot-start-', label: 'Host snapshot deferred start'});
  const directory = join(scratch.path, 'carrier-snapshots');
  const configuration = install(installLocalSnapshotStore, mkdir, directory,
    undefined, createLocalRetainedStore, undefined);
  await assert.rejects(stat(directory), {code: 'ENOENT'});
  const create = localSnapshotStore(configuration);
  const store = await create('original carrier', 4096, 1024, undefined);
  try {
    assert.equal((await stat(directory)).isDirectory(), true);
    assert.equal((await readdir(directory)).length, 1);
    assert.equal(store.status().capacityBytes, 4096);
  } finally {
    store.close();
    assert.equal(await store.cleanup(), true);
  }
  assert.deepEqual(await readdir(directory), []);
  scratch.passed();
});

test('Host snapshot factory retains exact arguments after its same directory await', async () => {
  const order = [], original = {}, signal = new AbortController().signal;
  const configuration = install(installLocalSnapshotStore,
    async (path, options) => {order.push('directory'); assert.equal(path, 'original parent');
      assert.deepEqual(options, {recursive: true, mode: 0o700}); await Promise.resolve();
      order.push('directory complete');}, 'original parent', args => {
      order.push('factory');
      assert.deepEqual(args, {key: 'original carrier', bytes: 4096, frame: 1024,
        parentDirectory: 'original parent', signal});
      assert.equal(Object.isFrozen(args), true);
      return original;
    }, () => assert.fail('NoDefaultFactory'), undefined);
  assert.deepEqual(order, []);
  assert.strictEqual(await localSnapshotStore(configuration)(
    'original carrier', 4096, 1024, signal), original);
  assert.deepEqual(order, ['directory', 'directory complete', 'factory']);
});

test('Host snapshot abort before or during directory acquisition never starts a lease', async () => {
  for (const before of [true, false]) {
    const controller = new AbortController(), marker = new Error('OriginalAbort');
    let directories = 0;
    if (before) controller.abort(marker);
    const configuration = install(installLocalSnapshotStore, async () => {
      directories++;
      await Promise.resolve();
      controller.abort(marker);
    }, 'original parent', () => assert.fail('NoLeaseAfterAbort'),
    () => assert.fail('NoDefaultFactory'), undefined);
    await assert.rejects(localSnapshotStore(configuration)(
      'original carrier', 4096, 1024, controller.signal), error => error === marker);
    assert.equal(directories, before ? 0 : 1);
  }
});

test('Host snapshot directory failure retains its original error without a replacement lease', async () => {
  const marker = Object.freeze(new Error('OriginalDirectoryFailure'));
  const configuration = install(installLocalSnapshotStore, async () => {throw marker;},
    'original parent', () => assert.fail('NoLeaseAfterFailure'),
    () => assert.fail('NoDefaultFactory'), undefined);
  await assert.rejects(localSnapshotStore(configuration)('original carrier', 4096, 1024),
    error => error === marker);
});

test('Salesforce Source fixture retries the same Host after failed close without closing its server twice', async () => {
  const fixture = readFileSync(new URL(
    '../connectors/salesforce/test/standard-host.integration.test.mjs', import.meta.url), 'utf8');
  const tree = parse(fixture, {ecmaVersion: 'latest', sourceType: 'module'});
  const selected = [];
  const visit = (node, parents = []) => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'VariableDeclarator' && node.id.name === 'close' &&
        node.init?.type === 'ArrowFunctionExpression' && node.init.async &&
        parents.some(parent => parent.type === 'VariableDeclarator' && parent.id.name === 'open')) {
      selected.push(node.init);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(value => visit(value, [...parents, node]));
      else if (value !== null && typeof value === 'object') visit(value, [...parents, node]);
    }
  };
  visit(tree);assert.equal(selected.length, 1);
  const node = selected[0], marker = new Error('original Host cleanup pending');
  let hostCloses = 0, serverCloses = 0, connectionsClosed = 0, observations = 0;
  const host = {async close() {if (++hostCloses === 1) throw marker;}};
  const server = {closeAllConnections() {connectionsClosed++;}, close(done) {serverCloses++;done();}};
  const close = compileFunction(`let closed = false, serverClosed = false;
    return (${fixture.slice(node.start, node.end)});`, ['host', 'server', 't'])(host, server,
    {diagnostic() {observations++;}});
  await assert.rejects(close(), error => error === marker);
  assert.deepEqual([hostCloses, serverCloses, connectionsClosed, observations], [1, 1, 1, 1]);
  await close();
  await close();
  assert.deepEqual([hostCloses, serverCloses, connectionsClosed], [2, 1, 1]);
  // Explicit original-method ports only: this tests the fixture's retained
  // retry duty, not a real Host's resource release or physical close ACK.
});
