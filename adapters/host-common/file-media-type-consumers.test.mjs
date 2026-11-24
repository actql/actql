// Exercise the emitted Local installer with explicit Common and native ports.
// File enumeration, metadata and contents come from actual Node filesystem I/O.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, writeFile, readdir, stat, mkdtemp, rm} from 'node:fs/promises';
import {registerHooks} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {defaultFileMediaType} from './file-media-type.mjs';

const localURL = new URL('../connectors/local/host/installed-project-files.mjs', import.meta.url);
const names = ['txt', 'constructor', 'README.md'];
const expected = ['application/octet-stream', 'application/octet-stream', 'text/markdown'];
let sequence = 0;

async function localConsumers(t, mediaType) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-file-mime-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  for (const name of names) await writeFile(join(directory, name), 'original bytes\n');

  const entry = {connection: 'local', connectorId: 'local', scopeCid: 'sha256:' + 'a'.repeat(64),
    declaration: {}, queryAliases: [], wire: '{"views":[]}', rootPath: directory, versionMode: 'metadata',
    tables: Object.freeze([]), csvTransports: Object.freeze({}),
    limits: {maxEntries: 10, maxDepth: 2, maxPathBytes: 200, maxFiles: 10, maxFileBytes: 1000,
      maxReadBytes: 10000, maxPages: 10, maxPageBytes: 100000, maxPageRows: 10}};
  const bundle = {sources: [entry], realizationKey:'installed-multi-acquired'}, prepared = {}, managedRun = {}, requestIdentity = {};
  const ok = _0 => ({$tag: 1, _0});
  let readPort;
  const modules = {
    '../../../host-node/installed-row-source.mjs': {
      createInstalledRowSource(options) {
        assert.equal(Object.hasOwn(options,'originalReadTransports'),false);
        readPort = options;
        return {connectorBindings: [], admitsSource: () => true};
      },
      rowSourceCheckEnvironment: () => ({wire: '{}'}),
    },
    '../../../host-node/installed-check-environment.mjs': {
      composeInstalledCheckEnvironment: () => '{}',
    },
    '../site/root-filesystem.mjs': {
      openLocalFileRoot() {assert.fail('Fixture uses its explicit filesystem port');},
      physicalReadChild({path, assertCurrent}) {
        assert.equal(path, directory);
        return {start() {
          assertCurrent();
          return {
            async list({onFile}) {
              for (const name of (await readdir(directory)).sort()) {
                const s = await stat(join(directory, name), {bigint: true});
                await onFile({path: name, version: 'fixture-version', metadata: {size: s.size,
                  modifiedSeconds: s.mtimeNs / 1000000000n, modifiedNanos: s.mtimeNs % 1000000000n}});
              }
            },
            async read(name, {expectedVersion}) {
              assert.equal(expectedVersion, 'fixture-version');
              return {bytes: await readFile(join(directory, name)), version: expectedVersion};
            },
          };
        }, async close() {return {pending: false};}};
      },
    },
  };
  if (mediaType) modules['../../../host-common/file-media-type.mjs'] = {defaultFileMediaType: mediaType};

  const selected = new URL(localURL);
  const key = `actql.test.file-media-type.${++sequence}`;
  selected.searchParams.set('fixture', key);
  globalThis[Symbol.for(key)] = modules;
  const loader = registerHooks({resolve(specifier, context, next) {
    if (context.parentURL !== selected.href || !Object.hasOwn(modules, specifier))
      return next(specifier, context);
    const bindings = `globalThis[Symbol.for(${JSON.stringify(key)})][${JSON.stringify(specifier)}]`;
    const body = Object.keys(modules[specifier])
      .map(name => `export const ${name} = ${bindings}.${name};`).join('\n');
    return {url: `data:text/javascript,${encodeURIComponent(body)}`, shortCircuit: true};
  }});
  let install;
  try {
    ({installPreparedProjectLocalFiles: install} = await import(selected.href));
  } finally {
    loader.deregister();
    delete globalThis[Symbol.for(key)];
  }

  const current = (actual, owner, request) => {
    assert.equal(actual, managedRun);
    assert.equal(owner, prepared);
    assert.equal(request, requestIdentity);
    return ok(true);
  };
  const raw = () => ({retainChild(child) {assert.equal(typeof child.start, 'function');},
    async close() {return {pending: false};}});
  const profile = await install({
    moon: {
      clientProgramResourceReferenceIssuer: () => ({}),
      clientProgramInstalledEffectManagedRunCheck: current,
      clientProgramInstalledSourceReadCheckCurrent: () => ok(true),
      clientProgramInstalledKeyedSourceReadCheckCurrent: () => ok(true),
      clientProgramLocalFileTimestamp: () => '2026-10-28T00:00:00.000Z',
      clientProgramKeyedAcquisitionMatchesEffectProgram: () => true,
      clientProgramInstalledManagedEffectKeyedSourceRead: () => ok({}),
      clientProgramInstalledKeyedSourceReadRetire: () => ok(true),
    },
    preparation: {originalsForRuntime: () => bundle},
    sourceManaged: {assertCurrent() {}, prepareRead: raw, prepareKeyedRead: raw},
    baseEnvironmentWire: '{}', nativeFilesystem: {},
    authorizationFor: async () => ({context: {contextCid: 'sha256:' + 'b'.repeat(64)}, assertAccountCurrent() {}}),
  });
  try {
    const originalRead = {};
    readPort.prepareSourceRead({checkedOwner: prepared, effectful: true, declaration: entry.declaration,
      occurrence: {stage: 0, input: 0, task: 0}, managedRun, originalRead, requestIdentity});
    const listed = [], contents = [], captured = [];
    await readPort.readPages({resource: 'files', rowRun: {originalRead},
      verifyRead: async () => {}, chargePage: body => ({body}), listing: {
        beginRequest: async () => {}, async consumePage(body) {listed.push(...JSON.parse(body).items);},
      }});
    for (const path of names) {
      const {resource, version} = listed.find(row => row.path === path);
      const originalKeyedRead = readPort.prepareKeyedSourceRead({checkedOwner: prepared, keyedAcquisition: {},
        request: {}, declaration: entry.declaration, managedRun, rowLimits: {}});
      await readPort.readPages({resource: 'contents', rowRun: {originalKeyedRead},
        capturedResourcePath: async () => path, requestWire: JSON.stringify({resource, version}),
        verifyRead: async () => {}, beginRequest: async () => {}, chargePage: body => ({body}),
        consumeObservation() {}, async captureContent(value) {
          assert.deepEqual(value.bytes, Buffer.from('original bytes\n'));
          captured.push(value.mediaType);
          return {fixtureContent: path};
        }, async consumePage(rows) {contents.push(...rows);}});
    }
    assert.deepEqual(names.map(path => listed.find(row => row.path === path).media_type), expected);
    assert.deepEqual(contents.map(row => row.media_type), expected);
    assert.deepEqual(captured, expected);
  } finally {
    await profile.close();
  }
}

test('actual Local listing and Content defaults handle bare names prototype keys and Markdown', async t => {
  await localConsumers(t);
});

test('Local listing and Content resolve one helper and use it for every default', async t => {
  const calls = [];
  await localConsumers(t, path => {calls.push(path); return defaultFileMediaType(path);});
  assert.deepEqual(calls.sort(), [...names, ...names].sort());
});

test('shared default profile uses own ASCII suffix entries without altering caller media facts', async () => {
  const shared = defaultFileMediaType;
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
