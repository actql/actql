import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, writeFile, rm, symlink, realpath, rename} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {resolveExternalRestModules, verifyExternalRestTarballs} from './installed-modules.mjs';
import * as normalCohort from './installed-modules.mjs';
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

async function qualifiedArchiveOffer(t) {
  const root = await mkdtemp(join(await realpath(tmpdir()), 'actql-rest-normal-offer-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const artifacts = join(root, 'artifacts');await mkdir(artifacts);
  const source = 'a'.repeat(40), tree = 'b'.repeat(40), tarballs = [], expected = [];
  for (const name of ['client-wire', 'sdk', 'run-host-core', 'local-node', 'node']) {
    const stage = join(root, name), directory = join(stage, 'package');
    await mkdir(directory, {recursive: true});
    const contents = {'index.mjs': 'throw new Error("Synthetic package exports must not execute");\n',
      'package.json': JSON.stringify({name: '@actql/' + name, version: '0.0.0-test', type: 'module'})};
    for (const [file, body] of Object.entries(contents)) await writeFile(join(directory, file), body, {mode: 0o600});
    const file = 'actql-' + name + '-0.0.0-development.tgz';
    execFileSync('tar', ['-czf', join(artifacts, file), '-C', stage, 'package']);
    const bytes = await (await import('node:fs/promises')).readFile(join(artifacts, file));
    tarballs.push({package: name, file, bytes: bytes.length,
      sha256: createHash('sha256').update(bytes).digest('hex'),
      sha512: createHash('sha512').update(bytes).digest('hex')});
    expected.push({name: '@actql/' + name, files: Object.entries(contents).map(([path, body]) => ({
      path, bytes: Buffer.byteLength(body), mode: 0o600,
      sha256: createHash('sha256').update(body).digest('hex')}))});
  }
  const manifestPath = join(artifacts, 'packed-client-packages.json');
  const manifest = JSON.stringify({revision: source,
    tarballs: Object.fromEntries(tarballs.map(row => [row.package, row.sha256]))}, null, 2) + '\n';
  await writeFile(manifestPath, manifest);
  const offer = {source, tree, producerReturnCode: 0, sourceClean: true, manifest: manifestPath,
    manifestBytes: Buffer.byteLength(manifest), manifestSHA256: createHash('sha256').update(manifest).digest('hex'), tarballs};
  const selected = async (value = offer, name = 'qualified-offer.json') => {
    const path = join(root, name), bytes = JSON.stringify(value, null, 2) + '\n';
    await writeFile(path, bytes);
    return {manifestPath: path, manifestSha256: createHash('sha256').update(bytes).digest('hex'),
      sourceSha: source, sourceTree: tree};
  };
  return {root, artifacts, manifestPath, manifest, offer, expected, selected};
}

test('REST normal cohort consumes the original qualified offer and bound producer manifest without importing packages', async t => {
  const f = await qualifiedArchiveOffer(t), selected = await f.selected();
  const cohort = await normalCohort.prepareExternalRestCohort(selected);
  assert.equal(cohort.manifest.sourceSha, selected.sourceSha);
  assert.equal(cohort.manifest.sourceTree, selected.sourceTree);
  assert.equal(cohort.artifactManifestPath, f.manifestPath);
  assert.deepEqual(cohort.manifest.packages.map(({name, files}) => ({name, files})), f.expected);
  assert.equal(await (await import('node:fs/promises')).readFile(f.manifestPath, 'utf8'), f.manifest);
  assert.equal(cohort.originalBindings.length, 2);
});

test('REST normal cohort refuses mismatched source tree manifest digests SRI and package membership', async t => {
  const f = await qualifiedArchiveOffer(t);
  const mutations = [value => {value.source = 'c'.repeat(40);}, value => {value.tree = 'c'.repeat(40);},
    value => {value.manifestSHA256 = '0'.repeat(64);}, value => {value.tarballs[0].sha512 = '0'.repeat(128);},
    value => {value.tarballs.pop();}, value => {value.tarballs[1] = value.tarballs[0];},
    value => {value.tarballs[0].file = '../escaped.tgz';}];
  for (const [index, mutate] of mutations.entries()) {
    const changed = structuredClone(f.offer);mutate(changed);
    await assert.rejects(normalCohort.prepareExternalRestCohort(await f.selected(changed, `bad-${index}.json`)));
  }
});

test('REST normal cohort preserves existing full inventory manifests and refuses changed declared payloads', async t => {
  const f = await qualifiedArchiveOffer(t);
  const full = {sourceSha: f.offer.source, sourceTree: f.offer.tree,
    packages: f.offer.tarballs.map((row, index) => ({name: '@actql/' + row.package, file: row.file,
      bytes: row.bytes, sha256: row.sha256,
      integrity: 'sha512-' + Buffer.from(row.sha512, 'hex').toString('base64'), files: f.expected[index].files}))};
  const path = join(f.artifacts, 'normal-packages.json');
  const select = async value => {
    const bytes = JSON.stringify(value);await writeFile(path, bytes);
    return {manifestPath: path, manifestSha256: createHash('sha256').update(bytes).digest('hex'),
      sourceSha: full.sourceSha, sourceTree: full.sourceTree};
  };
  const actual = await normalCohort.prepareExternalRestCohort(await select(full));
  assert.deepEqual(actual.manifest, full);assert.equal(actual.artifactManifestPath, path);
  full.packages[0].files[0].sha256 = '0'.repeat(64);
  await assert.rejects(normalCohort.prepareExternalRestCohort(await select(full)));
});

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
