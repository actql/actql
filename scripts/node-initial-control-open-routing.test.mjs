// Actual public facade bytes with an explicit private dispatch port fixture.
// This does not issue startup coverage or establish an actual Host positive.
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
    type: 'module', exports: './index.mjs'}));
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

test('selected public open forwards omitted input synchronously before constructing a default packet', async t => {
  const f = await facade(t), client = Object.freeze({originalClient: true});
  let finish;
  f.port.setBehavior(() => new Promise(resolve => {finish = resolve;}));
  const pending = f.entry.open();
  assert.equal(f.port.calls.length, 1);
  assert.equal(f.port.calls[0].receiver, f.port);
  assert.equal(f.port.calls[0].kind, 'open');
  assert.equal(f.port.calls[0].raw, undefined);
  assert.equal(f.provider.calls.length, 0);
  finish(client); assert.equal(await pending, client);
  assert.equal(f.port.calls.length, 1); assert.equal(f.provider.calls.length, 0);
});

test('selected refusal precedes Proxy observation and preserves the original pending cleanup', async t => {
  const f = await facade(t);
  let observations = 0;
  const raw = new Proxy({}, {get() {observations++;}, ownKeys() {observations++;},
    getOwnPropertyDescriptor() {observations++;}, getPrototypeOf() {observations++;}});
  const cleanupHandle = Object.freeze({status() {return {pending: true};}, retry() {}});
  const cause = Object.freeze(Object.assign(new Error('NodeInitialControlInputUnavailable'),
    {code: 'NodeInitialControlInputUnavailable', cleanupHandle}));
  f.port.setBehavior((kind, original) => {
    assert.equal(kind, 'open'); assert.equal(original, raw); throw cause;
  });
  await assert.rejects(f.entry.open(raw), error => error === cause && error.cleanupHandle === cleanupHandle);
  assert.equal(observations, 0); assert.equal(f.port.calls.length, 1);
  assert.equal(f.provider.calls.length, 0); assert.equal(cleanupHandle.status().pending, true);
});

test('selected forwarding retains the exact original object and callback without copying or reading them', async t => {
  const f = await facade(t);
  let reads = 0;
  const callback = () => {}, raw = Object.defineProperty({installation: {resolveSourceSecret: callback}},
    'stateDir', {get() {reads++; throw new Error('UnadmittedGetter');}, enumerable: true});
  f.port.setBehavior((kind, original) => {
    assert.equal(kind, 'open'); assert.equal(original, raw);
    return Promise.reject(Object.freeze(new Error('OriginalSupplierUnavailable')));
  });
  await assert.rejects(f.entry.open(raw), {message: 'OriginalSupplierUnavailable'});
  assert.equal(reads, 0); assert.equal(raw.installation.resolveSourceSecret, callback);
  assert.equal(f.port.calls.length, 1); assert.equal(f.provider.calls.length, 0);
});

test('the public facade retains its original callback and receiver after a late cache export replacement', async t => {
  const f = await facade(t);
  let replacementCalls = 0;
  f.require.cache[f.portPath].exports = Object.freeze({selectedInitialControlHostPreparation() {
    replacementCalls++; return Promise.resolve({replacement: true});
  }});
  const client = Object.freeze({sameOriginal: true});
  f.port.setBehavior(() => Promise.resolve(client));
  assert.equal(await f.entry.open(), client);
  assert.equal(f.port.calls.length, 1); assert.equal(f.port.calls[0].receiver, f.port);
  assert.equal(replacementCalls, 0); assert.equal(f.provider.calls.length, 0);
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
