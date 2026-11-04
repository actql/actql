import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {installedSourceIdentity, loadInstalledSource,
  publishInstalledSourceProfile} from './installed-source.mjs';

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
