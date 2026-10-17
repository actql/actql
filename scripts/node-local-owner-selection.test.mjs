// Actual public Node/Local entry bytes with an explicit physical Host double.
// This tests only option routing, not Host/Account/Run or mock-profile support.
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, symlink, writeFile} from 'node:fs/promises';
import {pathToFileURL, fileURLToPath} from 'node:url';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
async function entries(t) {
  const scratch = await createOwnedScratch({parent: join(repository, '_build'),
    prefix: 'node-local-owner-', label: 'public Local owner selection component'});
  const packages = join(scratch.path, 'node_modules/@actql');
  await mkdir(join(packages, 'node'), {recursive: true});
  await mkdir(join(packages, 'local-node/adapters/host-node'), {recursive: true});
  await symlink(join(repository, 'packages/sdk'), join(packages, 'sdk'), 'dir');
  for (const name of ['node', 'local-node']) {
    for (const file of ['index.mjs', 'package.json']) {
      const original = join(repository, 'packages', name, file);
      const copied = join(packages, name, file);
      await copyFile(original, copied);
      assert.deepEqual(await readFile(copied), await readFile(original));
    }
  }
  // No provider, key, Store or Run is opened by this explicit Host double.
  await writeFile(join(packages, 'local-node/adapters/host-node/embedded-local.mjs'), `
export const calls = [];
export function connectEmbeddedLocal(options) {
  calls.push(options);
  return Promise.resolve(Object.freeze({selected: options}));
}
export const publishInstalledSource = () => { throw new Error('Not selected'); };
export const publishInstalledEffect = () => { throw new Error('Not selected'); };
`);
  await writeFile(join(packages, 'local-node/adapters/host-node/installed-connectors.mjs'),
    'export const createInstalledConnectorTable = () => {throw new Error("Not selected");};\n');
  const node = await import(pathToFileURL(join(packages, 'node/index.mjs')));
  const local = await import(pathToFileURL(join(packages, 'local-node/index.mjs')));
  const physical = await import(pathToFileURL(join(packages,
    'local-node/adapters/host-node/embedded-local.mjs')));
  t.after(() => scratch.passed());
  return {node, local, calls: physical.calls};
}

test('public Node embedded Local omission selects only the existing Local owner', async t => {
  const {node, calls} = await entries(t);
  const authorization = {original: 'explicit caller selection, not a grant'};
  const input = {mode: 'local', installation: {directory: '.actql', authorization}};
  const client = await node.connect(input);
  assert.equal(client.selected.mode, 'local');
  assert.equal(client.selected.owner, 'local');
  assert.equal(calls.length, 1);
  assert.strictEqual(calls[0].installation.authorization, authorization);
  assert.equal(Object.hasOwn(input, 'owner'), false, 'do not mutate caller configuration');
  assert.deepEqual(Object.keys(calls[0]).sort(), ['installation', 'mode', 'owner']);
});

test('direct Local provider omission and explicit original owner produce the same selection', async t => {
  const {local, calls} = await entries(t);
  await local.connect({mode: 'local'});
  await local.connect({mode: 'local', owner: 'local'});
  assert.deepEqual(calls, [{mode: 'local', owner: 'local'},
    {mode: 'local', owner: 'local'}]);
});

test('Local default never replaces null foreign or hybrid ownership', async t => {
  const {node, local, calls} = await entries(t);
  for (const owner of [null, 'cloud', 'remote', false, 0]) {
    assert.throws(() => local.connect({mode: 'local', owner}),
      {code: 'LocalHybridUnavailable'});
    await assert.rejects(node.connect({mode: 'local', owner}),
      {code: 'LocalHybridUnavailable'});
  }
  for (const mode of [undefined, 'hybrid', 'remote', 'other']) {
    assert.throws(() => local.connect({mode, owner: 'local'}),
      {code: 'LocalHybridUnavailable'});
  }
  await assert.rejects(node.connect({mode: 'hybrid', owner: 'local'}),
    {code: 'LocalHybridUnavailable'});
  assert.deepEqual(calls, []);
});

test('connected Local and Remote retain existing SDK selection and validation', async t => {
  const {node, calls} = await entries(t);
  await assert.rejects(node.connect({mode: 'local', endpoint: 'not-an-origin',
    token: 'not-a-secret-fixture'}), {code: 'InvalidConnectionOptions'});
  await assert.rejects(node.connect({mode: 'remote', endpoint: 'not-an-origin',
    token: 'not-a-secret-fixture'}), {code: 'InvalidConnectionEndpoint'});
  assert.deepEqual(calls, []);
});

test('Local selector reads admitted mode and owner once before copying other options', async t => {
  const {local, calls} = await entries(t);
  let modes = 0, owners = 0;
  const input = {get mode() { return ++modes === 1 ? 'local' : 'remote'; },
    get owner() { owners++; return undefined; }};
  const selected = await local.connect(input);
  assert.equal(selected.selected.mode, 'local');
  assert.equal(selected.selected.owner, 'local');
  assert.equal(modes, 1);
  assert.equal(owners, 1);
  assert.equal(calls.length, 1);
});

test('public short open keeps its existing explicit Local selection', async t => {
  const {node, calls} = await entries(t);
  const client = await node.open({stateDir: '.actql-owner-fixture'});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].mode, 'local');
  assert.equal(calls[0].owner, 'local');
  assert.equal(client.info.stateDir, calls[0].installation.directory);
});
