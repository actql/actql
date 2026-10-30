import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, writeFile, rm, symlink, realpath, rename} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {resolveExternalRestModules, verifyExternalRestTarballs} from './installed-modules.mjs';
import {externalRestConfiguration} from './configuration.mjs';
import {externalRestProvider} from './provider.fixture.mjs';
import {installedFamilyProviderRoute} from './fixture-source/adapters/host-node/fixtures/installed-family-scenario.fixture.mjs';

async function fixture(t) {
  const root = await mkdtemp(join(await realpath(tmpdir()), 'actql-rest-module-resolution-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const consumerRoot = join(root, 'consumer');await mkdir(consumerRoot);
  await writeFile(join(consumerRoot, 'package.json'), '{"private":true,"type":"module"}');
  const modules = join(consumerRoot, 'node_modules');
  const put = async (name, parent = modules) => {
    const path = join(parent, name);await mkdir(path, {recursive: true});
    await writeFile(join(path, 'package.json'), JSON.stringify({name, version: '0.0.0-test',
      type: 'module', exports: './index.mjs'}));
    await writeFile(join(path, 'index.mjs'), 'throw new Error("A source-only resolver must not import this module");\n');
    return path;
  };
  for (const name of ['@actql/node', '@actql/local-node', '@actql/sdk', '@actql-connectors/acme']) await put(name);
  return {root, consumerRoot, modules, put};
}

async function selectedBlobs(t) {
  const root = await mkdtemp(join(await realpath(tmpdir()), 'actql-rest-tar-preflight-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const packages = [];
  for (const name of ['@actql/client-wire', '@actql/local-node', '@actql/node', '@actql/run-host-core', '@actql/sdk']) {
    // These are digest fixture bytes, not archives or product software.
    const bytes = Buffer.from('independent digest fixture: ' + name);
    const file = name.slice(7) + '.tgz';
    await writeFile(join(root, file), bytes);
    packages.push({name, file, bytes: bytes.length,
      sha256: createHash('sha256').update(bytes).digest('hex'),
      integrity: 'sha512-' + createHash('sha512').update(bytes).digest('base64')});
  }
  return {root, manifestPath: join(root, 'manifest.json'), manifest: {packages}};
}

test('REST selected tar preflight verifies all five exact offered digests without importing or installing software', async t => {
  const f = await selectedBlobs(t);
  assert.deepEqual(await verifyExternalRestTarballs(f.manifest, f.manifestPath),
    f.manifest.packages.map(({name, file, bytes, sha256, integrity}) =>
      ({name, path: join(f.root, file), bytes, sha256, integrity})));
});

test('REST selected tar preflight refuses changed bytes, wrong SRI, escaped paths and incomplete cohorts', async t => {
  const f = await selectedBlobs(t), pkg = f.manifest.packages[0];
  const wrongSri = structuredClone(f.manifest);
  wrongSri.packages[0].integrity = 'sha512-' + Buffer.alloc(64).toString('base64');
  await assert.rejects(verifyExternalRestTarballs(wrongSri, f.manifestPath));
  const escaped = structuredClone(f.manifest);escaped.packages[0].file = '../client-wire.tgz';
  await assert.rejects(verifyExternalRestTarballs(escaped, f.manifestPath));
  await assert.rejects(verifyExternalRestTarballs({packages: f.manifest.packages.slice(1)}, f.manifestPath));
  await writeFile(join(f.root, pkg.file), Buffer.alloc(pkg.bytes));
  await assert.rejects(verifyExternalRestTarballs(f.manifest, f.manifestPath));
});

test('REST ordinary module preflight resolves one installed Node SDK and Host without executing fake exports', async t => {
  const f = await fixture(t);
  const paths = await resolveExternalRestModules({consumerRoot: f.consumerRoot, connectorPackage: '@actql-connectors/acme'});
  assert.deepEqual(paths, {node: join(f.modules, '@actql/node/index.mjs'),
    host: join(f.modules, '@actql/local-node/index.mjs'), sdk: join(f.modules, '@actql/sdk/index.mjs'),
    connector: join(f.modules, '@actql-connectors/acme/index.mjs')});
});

test('REST ordinary preflight refuses a second SDK namespace or workspace entry before imports', async t => {
  const f = await fixture(t), nested = join(f.modules, '@actql/local-node/node_modules');
  await f.put('@actql/sdk', nested);
  await assert.rejects(resolveExternalRestModules({consumerRoot: f.consumerRoot, connectorPackage: '@actql-connectors/acme'}),
    /StandardRestSdkNamespaceMismatch/u);
  await rm(nested, {recursive: true});
  await rm(join(f.modules, '@actql/node'), {recursive: true});
  const outside = await f.put('@actql/node', join(f.root, 'workspace'));
  await symlink(outside, join(f.modules, '@actql/node'));
  await assert.rejects(resolveExternalRestModules({consumerRoot: f.consumerRoot, connectorPackage: '@actql-connectors/acme'}),
    /StandardRestWorkspaceAliasRefused/u);
});

test('REST ordinary preflight refuses a symlinked module root before any product import', async t => {
  const f = await fixture(t), workspace = join(f.root, 'workspace');
  await mkdir(workspace);
  const shared = join(workspace, 'node_modules');
  await rename(f.modules, shared);
  await symlink(shared, f.modules);
  await assert.rejects(resolveExternalRestModules({consumerRoot: f.consumerRoot,
    connectorPackage: '@actql-connectors/acme'}), /StandardRestWorkspaceAliasRefused/u);
});

test('REST application DATA preserves explicit Account and original CA/key paths without tuning or service ports', () => {
  const account = '{"version":"fixture-only","entries":[]}\n';
  const family = {scenario: {id: 'fresh-authored-fixture'},
    paths: {project: '/PREPARED/project', state: '/PREPARED/state', credentialJournal: '/PREPARED/credentials'},
    keys: {credentialAuthority: {privateKeyPath: '/PREPARED/keys/credential.key'}},
    resourceHttps: {origin: 'https://127.0.0.1:1234', caPath: '/PREPARED/tls/ca.crt'},
    accountConfigurationWire: account};
  const data = externalRestConfiguration(family, {connectorId: 'rest-acme', profileVersion: 'actql-installed-acme-rest-source/0.1'});
  assert.deepEqual(Object.keys(data.files['rest-source.json']).sort(),
    ['accountConfigurationWire', 'connectorId', 'siteProfilePath', 'version']);
  assert.equal(data.files['rest-source.json'].accountConfigurationWire, account);
  assert.equal(data.installation.authorization.accountConfiguration, account);
  assert.equal(data.files['rest-site.json'].caPath, family.resourceHttps.caPath);
  assert.equal(data.files['rest-site.json'].credentialPrivateKeyPath, family.keys.credentialAuthority.privateKeyPath);
  assert.equal(data.files['rest-site.json'].apiOrigin, family.resourceHttps.origin);
  for (const name of ['limits', 'maxCaBytes', 'capacity', 'service', 'funder', 'sign']) {
    assert.equal(Object.hasOwn(data.files['rest-source.json'], name), false);
    assert.equal(Object.hasOwn(data.installation, name), false);
  }
});

test('REST provider DATA fits the unchanged shared route and keeps independent paged/error/byte oracles', async () => {
  const provider = externalRestProvider(), route = installedFamilyProviderRoute(provider);
  const first = await route.handle({method: 'GET', path: '/v1/customers', body: ''});
  assert.equal(first.status, 200);
  assert.deepEqual(JSON.parse(first.body), {data: [{id: 'alpha', amount: 7, note: 'e\u0301'},
    {id: 'beta', amount: 2, note: '東京'}], next_cursor: 'page-2'});
  const second = await route.handle({method: 'GET', path: '/v1/customers?after=page-2', body: ''});
  assert.deepEqual(JSON.parse(second.body), {data: [{id: 'gamma', amount: 11, note: ''}], next_cursor: null});
  provider.assertRequests();
  const error = await installedFamilyProviderRoute(externalRestProvider({mode: 'provider-error'}))
    .handle({method: 'GET', path: '/v1/customers', body: ''});
  assert.equal(error.status, 503);assert.equal(error.body, '{"error":"unavailable"}');
  const oversized = await installedFamilyProviderRoute(externalRestProvider({mode: 'oversized'}))
    .handle({method: 'GET', path: '/v1/customers', body: ''});
  assert.equal(Buffer.byteLength(oversized.body), 257);
});
