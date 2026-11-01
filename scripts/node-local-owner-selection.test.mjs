// Actual public Node/Local entry bytes with an explicit physical Host double.
// This tests only option routing, not Host/Account/Run or mock-profile support.
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, symlink, writeFile} from 'node:fs/promises';
import {pathToFileURL, fileURLToPath} from 'node:url';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
async function entries(t, protocol = false) {
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
  await copyFile(join(repository, 'adapters/host-node/compile-cache.mjs'),
    join(packages, 'local-node/adapters/host-node/compile-cache.mjs'));
  // No provider, key, Store or Run is opened by this explicit Host double.
  await writeFile(join(packages, 'local-node/adapters/host-node/embedded-local.mjs'), `
import {connectInProcess} from '@actql/sdk/host-port';
export const calls = [];
export const requests = [];
export let closes = 0;
export function connectEmbeddedLocal(options) {
  calls.push(options);
  if (${JSON.stringify(protocol)}) {
    const {installation, ...clientOptions} = options;
    void installation;
    return connectInProcess(clientOptions, {
      perform(operation, request) {
        if (operation !== 'connect') throw new Error('Unexpected operation');
        requests.push(request);
        return {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'fixture-scope', capabilities: [],
          limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
            maxRows: 256, maxBatchRows: 3, maxBatchRetainedValueBytes: 4096}};
      }, close() { closes++; },
    });
  }
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
  return {node, local, calls: physical.calls, physical};
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

test('default selection preserves other original descriptors without reading their getters', async t => {
  const {local, calls} = await entries(t);
  const prototype = {original: true};
  const symbolic = Symbol('original-installation-metadata');
  let reads = 0;
  const readInstallation = () => { reads++; return {original: true}; };
  const options = Object.create(prototype, {
    mode: {value: 'local', enumerable: true},
    installation: {get: readInstallation, enumerable: false},
    [symbolic]: {value: 'original', enumerable: false},
  });
  await local.connect(options);
  assert.equal(reads, 0, 'the selector is not the installation reader');
  assert.strictEqual(Object.getPrototypeOf(calls[0]), prototype);
  assert.strictEqual(Object.getOwnPropertyDescriptor(calls[0], 'installation').get,
    readInstallation);
  assert.equal(calls[0][symbolic], 'original');
  assert.equal(Object.getOwnPropertyDescriptor(calls[0], symbolic).enumerable, false);
  assert.equal(Object.hasOwn(options, 'owner'), false);
});

test('explicit original Local options keep their physical identity', async t => {
  const {local, calls} = await entries(t);
  const original = Object.freeze({mode: 'local', owner: 'local'});
  await local.connect(original);
  assert.strictEqual(calls[0], original);
});

test('foreign owner refusal does not inspect installation or remaining descriptors', async t => {
  const {local, calls} = await entries(t);
  const options = new Proxy({mode: 'local', owner: 'cloud'}, {
    ownKeys() { assert.fail('foreign ownership must refuse before copying'); },
  });
  assert.throws(() => local.connect(options), {code: 'LocalHybridUnavailable'});
  assert.equal(calls.length, 0);
});

test('real SDK admits the same closed Local wire and awaited Client close after default selection', async t => {
  const {node, physical} = await entries(t, true);
  const client = await node.connect({mode: 'local', installation: {directory: '.actql'}});
  assert.deepEqual(physical.requests.map(request => request.connection), [{
    mode: 'local', owner: 'local', consentRefs: [], runners: [],
  }]);
  assert.equal(client.profile.mode, 'local');
  assert.equal(client.profile.owner, 'local');
  await client.close();
  await client.close();
  assert.equal(physical.closes, 1);
});
