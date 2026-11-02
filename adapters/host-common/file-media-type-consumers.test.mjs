// Exact installed Local readPages source with explicit
// Core/reference/native ports. Local file bytes/stat are real new Node FS I/O;
// this is not a Native binary, Common authority or ordinary Host qualification.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, writeFile, readdir, stat, mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {parse} from 'acorn';
import {checked} from './runtime-result.mjs';
import {AcquisitionOpenError} from './acquisition-outcome.mjs';

const localURL = new URL('../connectors/local/host/installed-project-files.mjs', import.meta.url);
async function originalSource(url) {
  const text = await readFile(url, 'utf8');
  return {text, tree: parse(text, {ecmaVersion: 'latest', sourceType: 'module'})};
}
function all(node, predicate, found = []) {
  if (Array.isArray(node)) node.forEach(value => all(value, predicate, found));
  else if (node && typeof node === 'object') {
    if (predicate(node)) found.push(node);
    for (const value of Object.values(node)) all(value, predicate, found);
  }
  return found;
}
async function mimeBinding(url, source) {
  const old = source.tree.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'mime'));
  if (old) return new Function(source.text.slice(old.start, old.end) + ';return mime;')();
  const owner = source.tree.body.find(node => node.type === 'ImportDeclaration' &&
    node.specifiers.some(value => value.local.name === 'mime'));
  assert.ok(owner, 'actual consumer must bind the shared default');
  const selected = owner.specifiers.find(value => value.local.name === 'mime');
  return (await import(new URL(owner.source.value, url).href))[selected.imported.name];
}

async function localConsumers(t, mime) {
  const source = await originalSource(localURL);
  const methods = all(source.tree, node => node.type === 'Property' && node.key?.name === 'readPages');
  assert.equal(methods.length, 1);
  const method = methods[0], directory = await mkdtemp(join(tmpdir(), 'actql-file-mime-'));
  const names = ['txt', 'constructor', 'README.md'];
  for (const name of names) await writeFile(join(directory, name), 'original bytes\n');
  t.diagnostic('Retained MIME filesystem fixture: ' + directory);
  const prepared = {}, run = {prepared}, reads = new Map(), listed = [], contents = [], captured = [];
  const entry = {rootPath: directory, versionMode: 'content', limits: {maxEntries: 10,
    maxDepth: 2, maxPathBytes: 200, maxFiles: 10, maxFileBytes: 1000, maxReadBytes: 10000,
    maxPageBytes: 100000, maxPageRows: 10}};
  const resourceFor = path => Object.freeze({path});
  const sameRun = value => {assert.equal(value, prepared);};
  const ok = value => ({$tag: 1, _0: value});
  const moon = {clientProgramInstalledSourceReadCheckCurrent: () => ok(true),
    clientProgramInstalledKeyedSourceReadCheckCurrent: () => ok(true),
    clientProgramLocalFileTimestamp: () => '2026-10-28T00:00:00.000Z'};
  const physicalReadChild = () => ({start() {return {
    async list({onFile}) {
      for (const name of (await readdir(directory)).sort()) {
        const s = await stat(join(directory, name), {bigint: true});
        await onFile({path: name, version: 'fixture-version', metadata: {size: s.size,
          modifiedSeconds: s.mtimeNs / 1000000000n, modifiedNanos: s.mtimeNs % 1000000000n}});
      }
    },
    async read(path, {expectedVersion}) {
      assert.equal(expectedVersion, 'fixture-version');
      return {bytes: await readFile(join(directory, path)), version: expectedVersion};
    },
  };}, async close() {return {pending: false};}});
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const factory = new Function('reads', 'sharedRuns', 'entry', 'sameRun', 'moon', 'physicalReadChild',
    'nativeFilesystem', 'checked', 'acknowledged', 'text', 'canonical', 'resourceFor',
    'createHash', 'AcquisitionOpenError', 'fail', 'mime',
    'return ({' + source.text.slice(method.start, method.end) + '});');
  const caller = factory(reads, new WeakMap(), entry, sameRun, moon, physicalReadChild, {}, checked,
    value => value?.pending === false, value => typeof value === 'string' && value.length > 0,
    JSON.stringify, resourceFor, createHash, AcquisitionOpenError, fail, mime);
  function originalRead(keyed) {
    const original = {}, read = {entry, keyed, closed: false, attempted: false, raw: {},
      retain(child) {assert.ok(child);}};
    reads.set(original, {run, read});return {original, read};
  }
  const list = originalRead(false);
  await caller.readPages({resource: 'files', rowRun: {originalRead: list.original},
    verifyRead: async () => {}, chargePage: body => ({body}), listing: {
      beginRequest: async () => {}, async consumePage(body) {listed.push(...JSON.parse(body).items);},
    }});
  await list.read.physical.close();
  for (const path of names) {
    const original = originalRead(true);
    await caller.readPages({resource: 'contents', rowRun: {originalKeyedRead: original.original},
      capturedResourcePath: async () => path,
      requestWire: JSON.stringify({resource: resourceFor(path), version: 'fixture-version'}),
      verifyRead: async () => {}, beginRequest: async () => {}, chargePage: body => ({body}),
      consumeObservation() {}, async captureContent(value) {captured.push([path, value.mediaType]);
        return {fixtureContent: path};}, async consumePage(rows) {contents.push(...rows);}});
  }
  return {listed: names.map(path => listed.find(row => row.path === path).media_type),
    contents: contents.map(row => row.media_type), captured};
}

test('actual Local listing and Content defaults handle bare names prototype keys and Markdown', async t => {
  const source = await originalSource(localURL), mime = await mimeBinding(localURL, source);
  const result = await localConsumers(t, mime);
  const expected = ['application/octet-stream', 'application/octet-stream', 'text/markdown'];
  assert.deepEqual(result.listed, expected);
  assert.deepEqual(result.contents, expected);
  assert.deepEqual(result.captured.map(value => value[1]), expected);
});

test('Local listing and Content resolve one helper and use it for every default', async t => {
  const shared = (await import('./file-media-type.mjs')).defaultFileMediaType;
  const local = await originalSource(localURL);
  assert.equal(await mimeBinding(localURL, local), shared);
  const calls = [], counted = path => {calls.push(path);return shared(path);};
  const result = await localConsumers(t, counted);
  const expected = ['application/octet-stream', 'application/octet-stream', 'text/markdown'];
  assert.deepEqual(result.listed, expected);assert.deepEqual(result.contents, expected);
  assert.equal(calls.length, 6);
  for (const path of ['txt', 'constructor', 'README.md']) assert.equal(calls.filter(value => value === path).length, 2);
});

test('shared default profile uses own ASCII suffix entries without altering caller media facts', async () => {
  const shared = (await import('./file-media-type.mjs')).defaultFileMediaType;
  const cases = [['a.txt', 'text/plain'], ['a.MD', 'text/markdown'], ['a.csv', 'text/csv'],
    ['a.json', 'application/json'], ['a.jsonl', 'application/x-ndjson'], ['a.pdf', 'application/pdf'],
    ['a.PNG', 'image/png'], ['a.jpg', 'image/jpeg'], ['a.jpeg', 'image/jpeg'], ['a.xml', 'application/xml'],
    ['txt', 'application/octet-stream'], ['dir.json/name', 'application/octet-stream'],
    ['a.constructor', 'application/octet-stream'], ['__proto__', 'application/octet-stream'],
    ['a.', 'application/octet-stream'], ['a.unknown', 'application/octet-stream']];
  for (const [path, expected] of cases) assert.equal(shared(path), expected, path);
  const caller = Object.freeze({path: 'a.txt', reported: 'application/vendor+json', configured: 'text/custom'});
  assert.equal(shared(caller.path), 'text/plain');
  assert.deepEqual(caller, {path: 'a.txt', reported: 'application/vendor+json', configured: 'text/custom'});
  let coerced = false;
  assert.throws(() => shared({toString() {coerced = true;return 'a.txt';}}), TypeError);
  assert.equal(coerced, false);
});
