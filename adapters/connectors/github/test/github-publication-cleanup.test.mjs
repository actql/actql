import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as providerMoon from '../../../../_build/js/release/build/connectors/github/host_node/host_node.js';
import {openHttpsExchangeFixture} from '../../../site-node/https-exchange-fixture.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {publishInstalledGitHubSource, INSTALLED_GITHUB_SITE_VERSION,
  INSTALLED_GITHUB_SOURCE_VERSION} from '../host/installed-github-source.mjs';
import {graphqlRoute} from './github-graphql.fixture.mjs';

async function setup(t, outcome) {
  const world = {repositories: new Map([['R_original', {databaseId: 1296269,
    nameWithOwner: 'octocat/hello', issues: []}]]),
  names: new Map([['octocat/hello', 'R_original']])};
  const api = await openHttpsExchangeFixture(t, {routes: [graphqlRoute(() => world)]});
  const root = await mkdtemp(join(tmpdir(), 'actql-github-publication-cleanup-'));
  const {privateKey} = generateKeyPairSync('ed25519');
  const key = join(root, 'credential.key');
  await writeFile(key, privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const sitePath = join(root, 'site.json');
  await writeFile(sitePath, JSON.stringify({version: INSTALLED_GITHUB_SITE_VERSION,
    apiOrigin: api.origin, owner: 'octocat', repo: 'hello', namespaceId: 'namespace-a',
    environment: 'test', siteKey: 'github-site', siteGeneration: 1,
    credentialAuthorityId: 'host-credential-authority', credentialKeyId: 'host-credential-key',
    credentialPrivateKeyPath: key, journalRoot: join(root, 'credential-journal'),
    tokenEnvironment: 'ACTQL_TEST_GITHUB_TOKEN', caPath: api.caPath}));
  const profile = {version: INSTALLED_GITHUB_SOURCE_VERSION, siteProfilePath: sitePath,
    publicationPath: join(root, 'publication.json'), connectorId: 'github-original',
    accountConfigurationWire: canonicalJson({version: 'actql-execution-account-config/0.1',
      account_id: 'github-source-account', entries: [{entry_id: 'read-own-repository', outcome,
        exclusions: [], principal: {all: true},
        connection: {any_of: [`github:${new URL(api.origin).host}/octocat/hello`]},
        resource: {any_of: ['issues']}, operation: {any_of: ['read']}}]})};
  return {root, profile, api, publish: () => publishInstalledGitHubSource(profile,
    {root: join(root, 'state'), principalId: userInfo().username, moon, providerMoon,
      runtimeBundleCid: `sha256:${'a'.repeat(64)}`, resolveSecret: async () => 'test-only-token'})};
}

// Inject before the real close, preserving the exact original DatabaseSync
// object and every product journal operation. Retry must close that same DB.
function failOriginalClose(t, times) {
  const close = DatabaseSync.prototype.close;
  const cause = Object.assign(new Error('FixtureSqliteClosePending'), {code: 'FixtureSqliteClosePending'});
  let original, calls = 0, physicalClosed = false;
  DatabaseSync.prototype.close = function(...args) {
    original ??= this;
    assert.equal(this, original);
    calls++;
    if (calls <= times) throw cause;
    const result = Reflect.apply(close, this, args);
    physicalClosed = true;
    return result;
  };
  t.after(() => {
    DatabaseSync.prototype.close = close;
    // On the original regression's red path the public retry handle is lost.
    // The fixture still owns this exact injected physical DB for final close.
    // Keep all files, including failed metadata, rather than resetting a DB.
    if (original !== undefined && !physicalClosed) Reflect.apply(close, original, []);
  });
  return {cause, calls: () => calls, physicalClosed: () => physicalClosed};
}

test('GitHub publication retains its original journal after successful publication close fails', async t => {
  const fixture = await setup(t, 'allow');
  const close = failOriginalClose(t, 2);
  const failure = await fixture.publish().then(() => assert.fail('close must not be acknowledged'), error => error);
  assert.equal(failure.code, 'InstalledHostInitializationFailed');
  assert.equal(failure.primaryFailure, close.cause);
  assert.equal(failure.cleanupPending, true);
  assert.deepEqual(failure.cleanupHandle.status().owners, ['source-profile']);
  assert.equal(close.physicalClosed(), false);
  const saved = await readFile(fixture.profile.publicationPath);
  assert.equal(JSON.parse(saved).repository.node_id, 'R_original');
  assert.equal(fixture.api.seen().length, 1);
  await failure.cleanupHandle.retry();
  assert.equal(close.physicalClosed(), true);
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(fixture.api.seen().length, 1, 'cleanup never repeats repository discovery');
  assert.deepEqual(await readFile(fixture.profile.publicationPath), saved);
  const count = close.calls();
  await failure.cleanupHandle.retry();
  assert.equal(close.calls(), count, 'the confirmed physical close is not repeated');
});

test('GitHub publication keeps authorization refusal primary while original cleanup is pending', async t => {
  const fixture = await setup(t, 'deny');
  const close = failOriginalClose(t, 2);
  const failure = await fixture.publish().then(() => assert.fail('denied read must fail'), error => error);
  assert.equal(failure.code, 'InstalledHostInitializationFailed');
  assert.equal(failure.primaryFailure.code, 'ExecutionAuthorizationDenied');
  assert.equal(failure.cleanupPending, true);
  assert.equal(fixture.api.seen().length, 0);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(close.physicalClosed(), true);
  assert.equal(fixture.api.seen().length, 0, 'cleanup never retries the denied operation');
});

test('GitHub publication still returns its durable original after confirmed close', async t => {
  const fixture = await setup(t, 'allow');
  const close = failOriginalClose(t, 0);
  const publication = await fixture.publish();
  assert.equal(publication.repository.node_id, 'R_original');
  assert.deepEqual(JSON.parse(await readFile(fixture.profile.publicationPath)), publication);
  assert.equal(close.physicalClosed(), true);
  assert.equal(close.calls(), 1);
  assert.equal(fixture.api.seen().length, 1);
});

test('GitHub publication leaves an ordinary authorization refusal unchanged after confirmed close', async t => {
  const fixture = await setup(t, 'deny');
  const close = failOriginalClose(t, 0);
  const failure = await fixture.publish().then(() => assert.fail('denied read must fail'), error => error);
  assert.equal(failure.code, 'ExecutionAuthorizationDenied');
  assert.equal(failure.cleanupHandle, undefined);
  assert.equal(close.physicalClosed(), true);
  assert.equal(close.calls(), 1);
  assert.equal(fixture.api.seen().length, 0);
});
