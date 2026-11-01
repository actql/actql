// Actual ordinary public facade with an explicit Local provider fixture.
// This establishes option routing, not an operational Host positive.
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, symlink, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
async function facade(t, selected = true) {
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'node-initial-open-', label: 'public omitted-open dispatch component'});
  const packages = join(scratch.path, 'node_modules/@actql');
  const node = join(packages, 'node'), local = join(packages, 'local-node');
  await mkdir(node, {recursive: true}); await mkdir(local, {recursive: true});
  for (const file of ['index.mjs', 'package.json']) {
    await copyFile(join(root, 'packages/node', file), join(node, file));
    assert.deepEqual(await readFile(join(node, file)), await readFile(join(root, 'packages/node', file)));
  }
  await symlink(join(root, 'packages/sdk'), join(packages, 'sdk'), 'dir');
  // Explicit boundary double only. The operational startup's real receiver
  // admission is tested by its Owner, not authenticated by this fixture.
  const portPath = join(node, 'initial-control-public-dispatch.cjs');
  await writeFile(portPath, `
'use strict';
let behavior = () => Promise.resolve(Object.freeze({fixtureClient:true}));
const calls = [];
const table = Object.freeze({selectedInitialControlHostPreparation: ${selected ? 'function(kind, raw) {calls.push({receiver:this,kind,raw});return behavior(kind,raw);}' : 'undefined'},
  calls, setBehavior(original) {behavior=original;}});
module.exports = table;
`);
  await writeFile(join(local, 'package.json'), JSON.stringify({name: '@actql/local-node',
    type: 'module', exports: {'.': './index.mjs',
      './_internal/compile-cache': './adapters/host-node/compile-cache.mjs'}}));
  await mkdir(join(local, 'adapters/host-node'), {recursive: true});
  await copyFile(join(root, 'adapters/host-node/compile-cache.mjs'),
    join(local, 'adapters/host-node/compile-cache.mjs'));
  await writeFile(join(local, 'index.mjs'), `
export const calls=[];
export function connect(options) {calls.push(options);return Promise.resolve(Object.freeze({selected:options}));}
`);
  const require = createRequire(pathToFileURL(join(node, 'index.mjs')));
  const port = require(portPath), entry = await import(pathToFileURL(join(node, 'index.mjs')));
  const provider = await import(pathToFileURL(join(local, 'index.mjs')));
  t.after(() => scratch.passed());
  return {entry, port, provider, require, portPath};
}

test('ordinary public open ignores an ambient private startup table', async t => {
  const f = await facade(t);
  f.port.setBehavior(() => {assert.fail('ordinary open must use the normal provider');});
  const client = await f.entry.open();
  assert.equal(client.info.stateDir, resolve('.actql'));
  assert.equal(f.port.calls.length, 0);
  assert.equal(f.provider.calls.length, 1);
});

test('ordinary open captures documented options and explicit Mock consent before lazy import', async t => {
  const f = await facade(t);
  const callback = () => 'original';
  let profileReads = 0;
  const input = {stateDir: '.mock-original', get profile() {profileReads++; return 'mock';},
    installation: {resolveSourceSecret: callback}};
  const pending = f.entry.open(input);
  input.stateDir = '.replacement';
  input.installation.resolveSourceSecret = () => 'replacement';
  const client = await pending;
  assert.equal(profileReads, 1);
  assert.equal(client.info.stateDir, resolve('.mock-original'));
  assert.equal(f.provider.calls[0].profile, 'mock');
  assert.strictEqual(f.provider.calls[0].installation.resolveSourceSecret, callback);
  assert.equal(f.port.calls.length, 0);
});

test('ordinary connect retains explicit selection rather than a later caller mutation', async t => {
  const f = await facade(t);
  const input = {mode: 'local', profile: 'mock', installation: {directory: '.original'}};
  const pending = f.entry.connect(input);
  input.profile = 'live'; input.installation.directory = '.replacement';
  await pending;
  assert.equal(f.provider.calls[0].profile, 'mock');
  assert.equal(f.provider.calls[0].installation.directory, '.original');
  assert.equal(f.port.calls.length, 0);
});

test('absent profile stays absent and an inherited profile cannot consent to Mock setup', async t => {
  const f = await facade(t);
  await f.entry.connect({mode: 'local'});
  assert.equal(Object.hasOwn(f.provider.calls[0], 'profile'), false);
  await assert.rejects(f.entry.connect(Object.assign(Object.create({profile: 'mock'}),
    {mode: 'local'})), {code: 'InvalidConnectionOptions'});
  assert.equal(f.provider.calls.length, 1);
});

test('unselected open retains default and explicit Local state-directory behavior', async t => {
  const f = await facade(t, false);
  const first = await f.entry.open();
  assert.equal(first.info.stateDir, resolve('.actql'));
  const second = await f.entry.open({stateDir: '.actql-explicit', durability: 'durable', consentRefs: ['original']});
  assert.equal(second.info.stateDir, resolve('.actql-explicit'));
  assert.deepEqual(f.provider.calls, [
    {mode: 'local', owner: 'local', installation: {directory: resolve('.actql'), hostCapacityPolicy: undefined}},
    {mode: 'local', owner: 'local', durability: 'durable', consentRefs: ['original'],
      installation: {directory: resolve('.actql-explicit'), hostCapacityPolicy: undefined}},
  ]);
  assert.equal(f.port.calls.length, 0);
});

test('unselected open preserves its original closed fields and type refusals before Local dispatch', async t => {
  const f = await facade(t, false);
  for (const raw of [null, [], {unknown: true}, {stateDir: ''}, {stateDir: 1},
    {profile: false}, {profile: null}, {profile: ''}, {[Symbol('unknown')]: true},
    {installation: null}, {installation: []}, {installation: {directory: '/foreign'}}]) {
    await assert.rejects(f.entry.open(raw), {code: 'InvalidOpenOptions'});
  }
  assert.equal(f.provider.calls.length, 0); assert.equal(f.port.calls.length, 0);
});

test('unselected Remote validation never invokes the selected or Local dispatch', async t => {
  const f = await facade(t, false);
  await assert.rejects(f.entry.connect({mode: 'remote', endpoint: 'not-an-origin',
    token: 'not-a-secret-fixture'}), {code: 'InvalidConnectionEndpoint'});
  assert.equal(f.provider.calls.length, 0); assert.equal(f.port.calls.length, 0);
});
