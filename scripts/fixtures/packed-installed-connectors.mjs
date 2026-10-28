import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createRequire, syncBuiltinESMExports} from 'node:module';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL, fileURLToPath} from 'node:url';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';

const root = fileURLToPath(new URL('./node_modules/@actql/local-node/', import.meta.url));
const {installedConnectors} = await import(pathToFileURL(join(root,
  'adapters/connectors-builtin/installations.generated.mjs')));
const {providerBundleUrl} = await import(pathToFileURL(join(root,
  'adapters/host-node/installed-connectors.mjs')));
const providers = [];
for (const entry of installedConnectors) {
  const url = providerBundleUrl(entry);
  if (entry.providerBundle === undefined) {
    assert.equal(url, undefined, entry.name);
  } else {
    assert.ok(url.href.startsWith(pathToFileURL(root).href));
    const runtime = await import(url.href);
    assert.ok(Object.keys(runtime).length > 0, entry.name);
  }
  if (entry.source) assert.ok((await entry.source.load()).load instanceof Function);
  if (entry.effect) assert.ok((await entry.effect.load()).load instanceof Function);
  providers.push(entry.name);
}
assert.ok(providers.includes('github'));
const moon = await import('@actql/local-node/runtime');
const {canonicalJson} = await import(pathToFileURL(join(root,
  'adapters/host-node/local-account-config.mjs')));
const {checked} = await import(pathToFileURL(join(root,
  'adapters/host-common/runtime-result.mjs')));
const views = await readFile(join(root, 'src/connectors/github/source-views.json'), 'utf8');
await readFile(join(root, 'src/connectors/github/writes.json'), 'utf8');
// The normal common owner issues the Catalog identity of these authored
// declarations. This fixture grants no real provider access or Run authority.
const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
  'gh-fixture', 'github', 'github/0.1', views, undefined));
const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
const directory = join(process.cwd(), 'installed-fixture');
await mkdir(directory);
const keys = generateKeyPairSync('ed25519');
await writeFile(join(directory, 'fixture.key'), keys.privateKey.export({type: 'pkcs8', format: 'pem'}));
const sitePath = join(directory, 'site.json'), publicationPath = join(directory, 'publication.json');
const apiOrigin = 'https://github.fixture.invalid';
await writeFile(sitePath, JSON.stringify({
  version: 'actql-installed-github-site/0.1', apiOrigin,
  owner: 'fixture', repo: 'repository', namespaceId: 'fixture-namespace',
  environment: 'test', siteKey: 'fixture-site', siteGeneration: 1,
  credentialAuthorityId: 'fixture-authority', credentialKeyId: 'fixture-key',
  credentialPrivateKeyPath: join(directory, 'fixture.key'),
  journalRoot: join(directory, 'credential-journal'),
  tokenEnvironment: 'ACTQL_TEST_UNUSED_PROVIDER_TOKEN',
}));
await writeFile(publicationPath, JSON.stringify({
  version: 'actql-github-publication/0.1', apiOrigin, owner: 'fixture', repo: 'repository',
  repository: {id: 1729, node_id: 'R_fixture'}, catalogCid: declared.catalog_cid,
  connectorId: 'gh-fixture',
}));
const accountConfigurationWire = canonicalJson({
  version: 'actql-execution-account-config/0.1', account_id: 'fixture-account',
  entries: [{entry_id: 'fixture-installation', outcome: 'allow', exclusions: [],
    principal: {all: true}, connection: {all: true}, resource: {all: true},
    operation: {any_of: ['effect', 'read', 'write']}}],
});
const common = {siteProfilePath: sitePath, publicationPath,
  connectorId: 'gh-fixture', accountConfigurationWire};
const sourcePath = join(directory, 'source.json'), effectPath = join(directory, 'effect.json');
await writeFile(sourcePath, JSON.stringify({version: 'actql-installed-github-source/0.1', ...common}));
await writeFile(effectPath, JSON.stringify({version: 'actql-installed-github-effect/0.1', ...common,
  writes: [{resource: 'issue_comments', sources: [
    {target: 'subject_id', field: 'node_id', null_behavior: 'reject'},
    {target: 'body', field: 'comment', null_behavior: 'reject'},
  ]}],
}));
let networkCalls = 0, secretCalls = 0;
const denyNetwork = () => { networkCalls++; throw new Error('NoProviderIOAllowed'); };
globalThis.fetch = denyNetwork;
for (const module of [http, https]) { module.request = denyNetwork; module.get = denyNetwork; }
net.connect = denyNetwork; net.createConnection = denyNetwork; tls.connect = denyNetwork;
syncBuiltinESMExports();
const resolveSecret = () => { secretCalls++; throw new Error('NoProviderCredentialAllowed'); };
const reviewerKeys = generateKeyPairSync('ed25519');
const hostKeys = generateKeyPairSync('ed25519');
const authorization = {
  accountConfiguration: accountConfigurationWire,
  reviewers: [{keyId: 'fixture-reviewer-key', reviewerId: 'fixture-reviewer',
    principalId: 'fixture-reviewer-principal',
    publicKey: reviewerKeys.publicKey.export({type: 'spki', format: 'pem'})}],
  reviewReaders: ['fixture-reviewer-principal'],
  hostKey: {keyId: 'fixture-host-key',
    privateKey: hostKeys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  leaseMs: 10000, resumeAfterAnswer: false,
};
for (const kind of ['source', 'effect']) {
  const host = await openInstalledRemoteHttpHost({
    directory: join(directory, kind), authenticate: () => userInfo().username,
    ...(kind === 'source' ? {sourceProfilePath: sourcePath, resolveSourceSecret: resolveSecret}
      : {effectProfilePath: effectPath, resolveEffectSecret: resolveSecret, authorization}),
  });
  assert.equal(typeof host.handler, 'function');
  await host.close();
}
assert.equal(networkCalls, 0);
assert.equal(secretCalls, 0);
const require = createRequire(import.meta.url);
assert.throws(() => require.resolve('@duckdb/node-api'), {code: 'MODULE_NOT_FOUND'});
console.log('PACKED_INSTALLED_CONNECTORS', JSON.stringify({
  providers, githubSourceOpened: true, githubEffectOpened: true,
  networkCalls, secretCalls, optionalDuckDBAbsent: true,
}));
