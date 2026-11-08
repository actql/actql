import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {createRequire, syncBuiltinESMExports} from 'node:module';
import fs from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {installedSourceIdentity, loadInstalledSource,
  publishInstalledSourceProfile} from './installed-source.mjs';
import {installedRuntimeBundleCid, installedConfigurationChunkBytes} from './source-profile-json.mjs';
import {installedSourceFixtureLifetime} from './fixtures/installed-source-initialization.mjs';
import {retireInstalledSourceInitialization} from './installed-host-services.mjs';
import {captureSourceAliasConstruction, sourceAliasProfileConstructionGeometry} from './source-alias-construction.mjs';
import {sourceJsonWireGeometry} from './installed-source-construction-geometry.mjs';

const byteLimit = 8 * 1024 * 1024;
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' +
      canonical(value[key])).join(',') + '}'
    : JSON.stringify(typeof value === 'string' ? value.normalize('NFC') : value);
const identity = parts => {
  const hash = createHash('sha256');
  for (const part of parts) {
    const text = canonical(part);
    hash.update(String(Buffer.byteLength(text)) + '\0' + text);
  }
  return 'sha256:' + hash.digest('hex');
};
const physicalTarget = {
  version: 'actql-installed-duckdb-target/0.1', database: '/unopened.duckdb',
  schema: 'main', table: 'cafe\u0301',
  utf8_hex: {database: '2f756e6f70656e65642e6475636b6462',
    schema: '6d61696e', table: '63616665cc81'},
};
async function directory(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-source-bounds-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
}
async function profile() {
  const environment = JSON.parse(await readFile(new URL(
    './fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
  const base = JSON.parse(await readFile(new URL(
    '../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  environment.host_policy_profile = base.host_policy_profile;
  delete environment.evidence_bundle_cid;
  environment.evidence_bundle_cid = 'sha256:' + createHash('sha256')
    .update(canonical(environment)).digest('hex');
  return {version: 'actql-installed-duckdb-source/0.1',
    database: '/unopened.duckdb', schema: 'main', table: 'cafe\u0301',
    sourceRef: 'connector://crm/main/r#v',
    checkEnvironmentWire: canonical(environment),
    accountConfigurationWire: canonical({version: 'actql-execution-account-config/0.1',
      account_id: 'source-bounds', entries: [{entry_id: 'read', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['read']}, exclusions: []}]}),
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']}};
}
async function writePadded(path, value, bytes) {
  const text = JSON.stringify(value);
  await writeFile(path, text + ' '.repeat(bytes - Buffer.byteLength(text)));
}
async function writeHuge(path) {
  const handle = await open(path, 'w');
  try {
    await handle.write('{}');
    await handle.truncate(2 ** 30);
  } finally { await handle.close(); }
}
function observeProvider(t) {
  const {DuckDBInstance} = createRequire(new URL(
    '../connectors/duckdb/node/package.json', import.meta.url))('@duckdb/node-api');
  let calls = 0;
  t.mock.method(DuckDBInstance, 'create', () => {
    calls++;
    throw new Error('UnexpectedProviderOperation');
  });
  return () => calls;
}

async function fundedConfiguration(t) {
  // Register actual Source/parent retirement before directory removal.
  const lifetime = installedSourceFixtureLifetime(t), root = await directory(t);
  const runtimeUrl = new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
  const common = await import(runtimeUrl.href), quotes = [];
  const moon = Object.freeze({...common, clientProgramInstalledSourceConstructionCapacity(...counts) {
    assert.strictEqual(this, moon); quotes.push(counts);
    return Reflect.apply(common.clientProgramInstalledSourceConstructionCapacity, common, counts);
  }});
  const opened = lifetime.open({root, moon, installation: Object.freeze({}),
    runtimeBundleCid: await installedRuntimeBundleCid(runtimeUrl)});
  return {path: join(root, 'configuration'), reader: opened.configurationReader,
    services: opened.installationServices, moon, quotes};
}

test('funded Source original text JSON keeps long scalar text separate from structural node demand', async t => {
  const f = await fundedConfiguration(t);
  const expected = {catalog: 'x'.repeat(340000), retained: {fields: ['Id', 'Name']}};
  const wire = JSON.stringify(expected), measured = sourceJsonWireGeometry(wire);
  await writeFile(f.path, wire);
  const original = await f.reader.readText(f.path, {maxBytes: Buffer.byteLength(wire)});
  assert.deepEqual(f.reader.parseJsonText(original), expected);
  assert(measured.nodes < BigInt(wire.length) / 1000n);
  assert(f.quotes.some(q => q[0] === 4n * measured.nodes && q[3] === 4n * measured.nodes &&
    q[4] === 12n * BigInt(wire.length)), 'same four tree roles, complete unchanged decoded-text envelope');
  assert.equal(f.quotes.at(-1)[0], 4n * measured.nodes, 'returned tree stays on the same material');
});

test('funded Source original text JSON retains full whitespace escape and Unicode demand', async t => {
  const f = await fundedConfiguration(t);
  const expected = {catalog: '{"items":[1,2]}', 'e\u0301': '日本語😀\\\"{}[]'};
  const wire = ' '.repeat(4096) + JSON.stringify(expected) + '\n\t'.repeat(128);
  const measured = sourceJsonWireGeometry(wire);
  assert.equal(measured.units, BigInt(wire.length), 'not the Alias-only payload demand profile');
  await writeFile(f.path, wire);
  const original = await f.reader.readText(f.path, {maxBytes: Buffer.byteLength(wire)});
  assert.deepEqual(f.reader.parseJsonText(original), expected);
  assert(f.quotes.some(q => q[3] === 4n * measured.nodes && q[4] === 12n * measured.units));
  const before = f.quotes.length;
  assert.throws(() => f.reader.parseJsonText(original + ' '), {code: 'ForeignInstalledConfigurationText'});
  assert.equal(f.quotes.length, before, 'foreign original refuses before any constructor quote');
});

test('funded Source original text JSON still refuses genuine node demand before the native parser', async t => {
  const f = await fundedConfiguration(t);
  // More real array entries need capacity even though their text is short.
  // Native JSON.parse would throw SyntaxError on this unfinished array; the
  // original finite Resource must refuse its constructor before that parser.
  const wire = '[' + '0,'.repeat(400000), measured = sourceJsonWireGeometry(wire);
  await writeFile(f.path, wire);
  const original = await f.reader.readText(f.path, {maxBytes: Buffer.byteLength(wire)});
  assert.throws(() => f.reader.parseJsonText(original), error =>
    error.code === 'MoonBitHostFailure' &&
    /PreparationCapacityIssue.*Resource$/u.test(error.cause?.constructor?.name ?? ''));
  assert(f.quotes.some(q => q[3] === 4n * measured.nodes && q[4] === 12n * measured.units));
});

test('funded Source Alias profile preserves real string demand and refuses its constructor before allocation', async t => {
  const f = await fundedConfiguration(t);
  const wire = JSON.stringify({value: ' '.repeat(byteLimit / 2)});
  await writeFile(f.path, wire);
  const original = await f.reader.readText(f.path, {maxBytes: byteLimit});
  assert.equal(original, wire);
  const quantity = sourceAliasProfileConstructionGeometry(original);
  assert.equal(quantity.bounds.input.units, BigInt(wire.length), 'inside-string spaces remain actual payload');
  const construct = captureSourceAliasConstruction(f.reader, f.moon);
  let entered = false;
  assert.throws(() => construct(quantity, () => {
    entered = true;
    return Object.freeze(JSON.parse(original));
  }), error => error.message === 'MoonBitHostFailure' &&
    /PreparationCapacityIssue.*Resource$/u.test(error.cause?.constructor?.name ?? ''));
  assert.equal(entered, false, 'the same finite preparation owner refuses before the real parse');
});

test('funded Source text decoder retains one String and exact file limit refusals', async t => {
  const f = await fundedConfiguration(t), bytes = Buffer.from([0xff, 0xc0, 0x00, 0x61]);
  await writeFile(f.path, bytes);
  const text = await f.reader.readText(f.path, {maxBytes: bytes.length});
  assert.equal(text, '\ufffd\ufffd\0a');
  const decoded = BigInt(bytes.length), textBound = 3n * decoded;
  assert(BigInt(Buffer.byteLength(text)) <= textBound, 'replacement UTF8 belongs to the one decoded String');
  assert(f.quotes.some(q => q[0] === 0n && q[1] === textBound && q[2] === decoded && q[3] === 0n &&
    q[4] === 0n && q[5] === 2n * decoded + BigInt(installedConfigurationChunkBytes)));
  assert.equal(f.quotes.at(-1)[1], BigInt(Buffer.byteLength('\ufffd\ufffd\0a')));
  await assert.rejects(f.reader.readText(f.path, {maxBytes: bytes.length - 1}), /InvalidInstalledSourceProfile/);
  // A refused bound does not grant a new read or change the original reader.
  assert.equal(await f.reader.readText(f.path, {maxBytes: bytes.length}), text);
  assert.throws(() => Reflect.apply(f.reader.readText, {...f.reader}, [f.path, {maxBytes: bytes.length}]),
    {code: 'ForeignInstalledConfigurationReader'});
  assert.equal(retireInstalledSourceInitialization(f.services), true);
  await assert.rejects(f.reader.readText(f.path + '.unopened', {maxBytes: bytes.length}),
    /InstalledSourceInitializationClosed/);
});

test('funded Source strict UTF8 and JSON retain their distinct original decode envelopes', async t => {
  const f = await fundedConfiguration(t), text = '\ufeff日本語😀', bytes = Buffer.from(text);
  await writeFile(f.path, bytes);
  assert.equal(await f.reader.readUtf8(f.path, {maxBytes: bytes.length}), text);
  const decoded = BigInt(bytes.length);
  assert(f.quotes.some(q => q[1] === decoded && q[2] === decoded && q[4] === 0n &&
    q[5] === 2n * decoded + BigInt(installedConfigurationChunkBytes)));
  await writeFile(f.path, Buffer.from([0xff]));
  await assert.rejects(f.reader.readUtf8(f.path, {maxBytes: 1}), {code: 'ERR_ENCODING_INVALID_ENCODED_DATA'});
  const body = JSON.stringify({value: '日本語😀'}), size = BigInt(Buffer.byteLength(body));
  const geometry = sourceJsonWireGeometry(body);
  await writeFile(f.path, body);
  assert.deepEqual(await f.reader.readJson(f.path), {value: '日本語😀'});
  assert(f.quotes.some(q => q[3] === 0n && q[4] === 3n * size &&
    q[5] === 2n * size + BigInt(installedConfigurationChunkBytes)), 'decode funds buffers and the same String before JSON values exist');
  assert(f.quotes.some(q => q[3] === 4n * geometry.nodes && q[4] === 12n * geometry.units &&
    q[5] === 8n * size + BigInt(installedConfigurationChunkBytes)), 'the same JSON envelope uses structural nodes and UTF16 units, not bytes as nodes');
  await writeFile(f.path, '{"unfinished":');
  await assert.rejects(f.reader.readJson(f.path), SyntaxError);
});

test('funded Source text decoder keeps the original failed close pending until the same FD acknowledges', async t => {
  const f = await fundedConfiguration(t);
  await writeFile(f.path, 'original');
  const originalOpen = fs.open;
  let allowClose = false, opens = 0, closes = 0, failure;
  fs.open = async (path, ...args) => {
    const handle = await originalOpen(path, ...args);
    if (path !== f.path) return handle;
    opens++;
    return {read: (...values) => handle.read(...values), async close() {
      closes++;
      if (!allowClose) return false;
      await handle.close();
    }};
  };
  syncBuiltinESMExports();
  try {
    await assert.rejects(f.reader.readText(f.path, {maxBytes: 8}), error => {
      failure = error;
      assert.equal(error.cleanupHandle.status().pending, true);
      return true;
    });
    assert.equal(opens, 1); assert.equal(closes, 1);
    const primary = failure.cleanupHandle.primaryFailure;
    assert.equal(primary.message, 'InstalledSourceProfileCleanupPending');
    assert.equal(retireInstalledSourceInitialization(f.services), false);
    allowClose = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(opens, 1); assert.equal(closes, 2);
    assert.strictEqual(failure.cleanupHandle.primaryFailure, primary);
    assert.equal(retireInstalledSourceInitialization(f.services), true);
  } finally {
    allowClose = true;
    if (failure !== undefined) await failure.cleanupHandle.retry();
    fs.open = originalOpen;
    syncBuiltinESMExports();
  }
});

test('installed Source profile preserves identity and loading below and at 8 MiB', async t => {
  const root = await directory(t);
  const path = join(root, 'profile.json');
  const input = await profile();
  const expectedIdentity = identity([input, physicalTarget]);
  for (const bytes of [Buffer.byteLength(JSON.stringify(input)), byteLimit - 1, byteLimit]) {
    await writePadded(path, input, bytes);
    assert.equal(await installedSourceIdentity(path), expectedIdentity);
    const adapter = await loadInstalledSource(path, {root, principalId: 'source-bounds', moon: {}});
    try {
      assert.equal(adapter.environmentWire, input.checkEnvironmentWire);
      assert.equal(adapter.sourceAccess.resource, '/unopened.duckdb');
      assert.equal(adapter.sourceAccess.sourceRef, input.sourceRef);
      assert.deepEqual(adapter.queryAliases, []);
      assert.deepEqual(adapter.connectorBindings, [{connectorId: 'crm/main',
        bindingCid: 'sha256:' + createHash('sha256').update(canonical({
          version: 'actql-installed-duckdb-source-binding/0.1', root,
          principalId: 'source-bounds', physicalBinding: physicalTarget,
          sourceRef: input.sourceRef})).digest('hex')}]);
    } finally { await adapter.close(); }
  }
});

test('installed Source identity bounds each published metadata file', async t => {
  const root = await directory(t);
  const path = join(root, 'profile.json');
  const siteProfilePath = join(root, 'site.json');
  const publicationPath = join(root, 'publication.json');
  const input = {version: 'actql-installed-salesforce-source/0.1', siteProfilePath,
    publicationPath, connectorId: 'crm-main',
    accountConfigurationWire: '{"account_id":"a"}', resources: ['Test_Record__c']};
  const site = {siteGeneration: 1}, publication = {generation: 'a'};
  await writeFile(path, JSON.stringify(input));
  await writeFile(siteProfilePath, JSON.stringify(site));
  await writeFile(publicationPath, JSON.stringify(publication));
  const expected = identity([{...input, accountConfigurationWire: {account_id: 'a'}},
    site, publication]);
  assert.equal(await installedSourceIdentity(path), expected);
  // Site configuration keeps the common 8 MiB bound; a saved Salesforce
  // generation has its own 16,000,000-byte published-format bound.
  for (const [metadataPath, value, limit, error] of [
    [siteProfilePath, site, byteLimit, 'InvalidInstalledSourceProfile'],
    [publicationPath, publication, 16_000_000, 'InvalidSalesforcePublication'],
  ]) {
    await writePadded(metadataPath, value, limit);
    assert.equal(await installedSourceIdentity(path), expected);
    await writePadded(metadataPath, value, limit + 1);
    await assert.rejects(installedSourceIdentity(path), {message: error});
    await writeHuge(metadataPath);
    await assert.rejects(installedSourceIdentity(path), {message: error});
    await writeFile(metadataPath, JSON.stringify(value));
    assert.equal(await installedSourceIdentity(path), expected);
  }
});

test('installed Source refuses oversized profiles before provider or credential operations', async t => {
  const root = await directory(t), path = join(root, 'profile.json');
  const input = await profile();
  const providerCalls = observeProvider(t);
  let providerOperations = 0, credentialOperations = 0;
  const options = {root, principalId: 'source-bounds',
    moon: new Proxy({}, {get() { providerOperations++; throw new Error('UnexpectedProviderOperation'); }}),
    resolveSecret: () => { credentialOperations++; throw new Error('UnexpectedCredentialOperation'); }};
  for (const size of ['one-byte-over', 'huge']) {
    if (size === 'huge') await writeHuge(path);
    else await writePadded(path, input, byteLimit + 1);
    await assert.rejects(installedSourceIdentity(path), {message: 'InvalidInstalledSourceProfile'});
    for (const initialize of [loadInstalledSource, publishInstalledSourceProfile]) {
      await assert.rejects(initialize(path, options), error => {
        assert.equal(error.code, 'InvalidInstalledSourceProfile');
        assert.equal(error.cause.message, 'InvalidInstalledSourceProfile');
        return true;
      });
    }
    assert.equal(providerOperations, 0);
    assert.equal(providerCalls(), 0);
    assert.equal(credentialOperations, 0);
  }
});

test('installed Source preserves parse and read causes without partial initialization', async t => {
  const root = await directory(t), path = join(root, 'profile.json');
  let operations = 0;
  const options = {root, principalId: 'source-bounds',
    moon: new Proxy({}, {get() { operations++; throw new Error('UnexpectedProviderOperation'); }}),
    resolveSecret: () => { operations++; throw new Error('UnexpectedCredentialOperation'); }};
  for (const text of ['', '{"version":']) {
    await writeFile(path, text);
    await assert.rejects(installedSourceIdentity(path), SyntaxError);
    for (const initialize of [loadInstalledSource, publishInstalledSourceProfile]) {
      await assert.rejects(initialize(path, options), error => {
        assert.equal(error.code, 'InvalidInstalledSourceProfile');
        assert.ok(error.cause instanceof SyntaxError);
        return true;
      });
    }
  }
  await rm(path);
  await assert.rejects(installedSourceIdentity(path), {code: 'ENOENT'});
  await assert.rejects(loadInstalledSource(path, options), error => {
    assert.equal(error.code, 'InvalidInstalledSourceProfile');
    assert.equal(error.cause.code, 'ENOENT');
    return true;
  });
  await writeFile(path, JSON.stringify({...await profile(), unexpected: true}));
  await assert.rejects(loadInstalledSource(path, options), {message: 'InvalidInstalledSourceProfile'});
  assert.equal(operations, 0);
});

test('public Local initialization refuses the profile bound and retries the same repaired profile', async t => {
  const root = await directory(t), path = join(root, 'profile.json');
  const input = await profile();
  const providerCalls = observeProvider(t);
  let credentialOperations = 0;
  const options = {mode: 'local', owner: 'local', installation: {
    directory: join(root, 'host'), sourceProfilePath: path,
    hostCapacityPolicy: JSON.parse(input.checkEnvironmentWire).host_policy_profile.capacity,
    resolveSourceSecret: () => { credentialOperations++; throw new Error('UnexpectedCredentialOperation'); }}};
  await writePadded(path, input, byteLimit + 1);
  await assert.rejects(connectEmbeddedLocal(options), {message: 'InvalidInstalledSourceProfile'});
  assert.equal(credentialOperations, 0);
  assert.equal(providerCalls(), 0);
  await writePadded(path, input, byteLimit);
  const client = await connectEmbeddedLocal(options).catch(error => {
    assert.fail(error.primaryFailure?.stack ?? error.stack);
  });
  await client.close();
  await writeFile(path, JSON.stringify(input));
  const reconnected = await connectEmbeddedLocal(options);
  await reconnected.close();
  assert.equal(credentialOperations, 0);
  assert.equal(providerCalls(), 0);
});
