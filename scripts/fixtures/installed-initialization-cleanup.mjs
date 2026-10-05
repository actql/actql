import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {mock} from 'node:test';

const scenario = JSON.parse(process.argv[2]);
const root = await mkdtemp(join(tmpdir(), 'actql-initialization-custody-'));
const sourceVersion = 'actql-installed-cleanup-source/0.1';
const effectVersion = 'actql-installed-cleanup-effect/0.1';
const registration = 'cleanup';
const revision = 'cleanup/0.1';
const closeFailure = Object.assign(new Error('InjectedInstalledCloseFailure'),
  {code: 'InjectedInstalledCloseFailure'});
const factoryFailure = Object.assign(new Error('InjectedAsyncRowFactoryFailure'),
  {code: 'InjectedAsyncRowFactoryFailure'});

function owner(blocked = false) {
  return {blocked, attempts: 0, completed: 0,
    close() {
      this.attempts++;
      if (this.blocked) throw closeFailure;
      this.completed++;
    }};
}

async function writeJson(name, value) {
  const path = join(root, name);
  await writeFile(path, JSON.stringify(value));
  return path;
}

async function rejected(action) {
  let failure;
  await assert.rejects(action, error => { failure = error; return true; });
  return failure;
}

function initializationFailure(failure, primaryCode, primary) {
  assert.equal(failure.code, 'InstalledHostInitializationFailed');
  assert.equal(failure.primaryFailure?.code, primaryCode);
  if (primary !== undefined) assert.equal(failure.primaryFailure, primary);
  assert.equal(typeof failure.cleanupHandle?.status, 'function');
  assert.equal(typeof failure.cleanupHandle?.retry, 'function');
  assert.equal(failure.cleanupPending, failure.cleanupHandle.status().pending);
}

async function finishCleanup(failure, held, assertNoReopen) {
  const handle = failure.cleanupHandle;
  const initial = handle.status();
  assert.equal(initial.pending, held.blocked);
  assert.equal(held.attempts, 1, 'initialization must attempt owned cleanup');
  assert.equal(held.completed, held.blocked ? 0 : 1);
  if (held.blocked) {
    assert.equal(initial.owners.length, 1);
    assert.ok(initial.errors.some(item => item.error === closeFailure),
      'the original close error remains inspectable');
    // Concurrent retries must share one drain of the exact acquired owner.
    await Promise.all([handle.retry(), handle.retry()]);
    assert.equal(handle.status().pending, true);
    assert.equal(held.attempts, 2);
    assert.equal(held.completed, 0);
    assertNoReopen();
    held.blocked = false;
    await Promise.all([handle.retry(), handle.retry()]);
    assert.equal(held.attempts, 3);
    assert.equal(held.completed, 1);
  }
  assert.equal(handle.status().pending, false);
  assert.deepEqual(handle.status().owners, []);
  assert.equal(failure.cleanupPending, false);
  const attempts = held.attempts;
  await handle.retry();
  await handle.retry();
  assert.equal(held.attempts, attempts, 'completed cleanup must not close twice');
  assert.equal(held.completed, 1);
  assertNoReopen();
}

function adapter(held, index = 0) {
  const sourceRef = `connector://cleanup/resource-${index}#view`;
  const authorization = {authorize: async () => ({action: 'dispatch'})};
  return {connectorRegistration: registration, connectorRevision: revision,
    environmentWire: '{}', connectorBindings: [],
    prepareCaptured() {}, prepareRecovered() {},
    sourceAccess: {sourceRef, connection: `cleanup:${index}`,
      resource: `resource-${index}`, authorization},
    admitsSource: ref => ref === sourceRef, ledgerCapacity() {},
    close: () => held.close()};
}

function installConnector(load) {
  let sourceSelections = 0;
  let effectSelections = 0;
  const installation = {check: profile => profile,
    identityParts: profile => [profile], load};
  mock.module(new URL('../../adapters/connectors-builtin/installations.generated.mjs',
    import.meta.url).href, {namedExports: {installedConnectors: [{
    name: registration, registration, revision,
    source: {profileVersion: sourceVersion, load: async () => {
      sourceSelections++; return installation;
    }},
    effect: {profileVersion: effectVersion, load: async () => {
      effectSelections++; return installation;
    }},
  }]}});
  return {sourceSelections: () => sourceSelections,
    effectSelections: () => effectSelections};
}

async function adapterFailure() {
  const held = owner(scenario.failClose);
  const installed = adapter(held);
  if (scenario.defect === 'registration') {
    installed.connectorRegistration = 'different';
  } else if (scenario.defect === 'revision') {
    installed.connectorRevision = 'cleanup/wrong';
  } else if (scenario.defect === 'environmentWire') {
    installed.environmentWire = null;
  } else {
    delete installed[scenario.defect];
  }
  let loads = 0;
  const selections = installConnector(async () => { loads++; return installed; });
  const path = await writeJson('profile.json', {version: scenario.kind === 'source'
    ? sourceVersion : effectVersion});
  const options = {root, principalId: 'fixture', moon: {},
    runtimeUrl: new URL(import.meta.url), baseEnvironmentWire: '{}'};
  const load = scenario.kind === 'source'
    ? (await import('../../adapters/host-node/installed-source.mjs')).loadInstalledSource
    : (await import('../../adapters/host-node/installed-effect.mjs')).loadInstalledEffect;
  const failure = await rejected(() => load(path, options));
  initializationFailure(failure,
    ['registration', 'revision'].includes(scenario.defect)
      ? 'InstalledConnectorRegistrationMismatch'
      : 'InvalidInstalledEffectInstallation');
  const primary = failure.primaryFailure;
  const assertNoReopen = () => {
    assert.equal(loads, 1, 'cleanup may not reload the adapter');
    assert.equal(selections.sourceSelections(), scenario.kind === 'source' ? 1 : 0);
    assert.equal(selections.effectSelections(), scenario.kind === 'effect' ? 1 : 0);
    assert.equal(failure.primaryFailure, primary);
  };
  await finishCleanup(failure, held, assertNoReopen);
}

async function githubFailure() {
  const held = owner(scenario.failClose);
  const site = {close: () => held.close()};
  let opens = 0;
  let authorizations = 0;
  let factories = 0;
  let restores = 0;
  const authorization = {context: {contextCid: `sha256:${'a'.repeat(64)}`}};
  const create = async options => {
    factories++;
    assert.equal(options.site, site);
    assert.equal(opens, 1, 'factory failure happens after Site acquisition');
    await Promise.resolve();
    throw factoryFailure;
  };
  // Only the physical dependency boundary is replaced. GitHub's actual
  // profile, publication, open-Site and post-open initialization code runs.
  mock.module(new URL('../../adapters/host-node/installed-row-source.mjs', import.meta.url).href,
    {namedExports: {
      createInstalledRowSource: create,
      installRowSourceAuthorization: async () => {
        authorizations++; return authorization;
      },
      openRowSourceCredentialSite: async () => { opens++; return site; },
      rowSourceCheckEnvironment: () => ({wire: '{}'}),
      rowSourceMapping: () => ({target: 'connector://fixture/issue_comments',
        mappingRef: 'fixture-mapping', mappingCid: `sha256:${'b'.repeat(64)}`,
        body: '{}'}),
    }});
  mock.module(new URL('../../adapters/host-node/installed-row-effect.mjs', import.meta.url).href,
    {namedExports: {createInstalledRowEffect: create}});
  const siteProfilePath = await writeJson('site.json', {
    version: 'actql-installed-github-site/0.1',
    apiOrigin: 'https://api.github.test', owner: 'fixture', repo: 'repository',
    credentialAuthorityId: 'fixture-authority', credentialKeyId: 'fixture-key',
    credentialPrivateKeyPath: join(root, 'unused.key'),
    journalRoot: join(root, 'unused-journal'), namespaceId: 'fixture-namespace',
    environment: 'test', siteKey: 'fixture-site', siteGeneration: 1,
    tokenEnvironment: 'ACTQL_UNUSED_GITHUB_TOKEN',
  });
  const publicationPath = await writeJson('publication.json', {
    version: 'actql-github-publication/0.1', connectorId: 'fixture',
    apiOrigin: 'https://api.github.test', owner: 'fixture', repo: 'repository',
    repository: {id: '42', node_id: 'repository-node'},
    catalogCid: `sha256:${'c'.repeat(64)}`,
  });
  const profile = {version: `actql-installed-github-${scenario.kind}/0.1`,
    connectorId: 'fixture', accountConfigurationWire: '{}',
    siteProfilePath, publicationPath,
    ...(scenario.kind === 'effect' ? {writes: [{resource: 'issue_comments',
      sources: [{field: 'body', target: 'body', null_behavior: 'reject'}]}]} : {})};
  const moon = {
    clientProgramRowSourceRestoreDeclaration() {
      restores++; return {$tag: 1, _0: {}};
    },
    clientProgramRowSourceDeclarationJson: () => '{}',
  };
  const options = {root, principalId: 'fixture', moon, providerMoon: {},
    baseEnvironmentWire: '{}', runtimeBundleCid: `sha256:${'d'.repeat(64)}`,
    ledgerRoot: join(root, 'ledger')};
  const load = scenario.kind === 'source'
    ? (await import('../../adapters/connectors/github/host/installed-github-source.mjs'))
      .loadInstalledGitHubSource
    : (await import('../../adapters/connectors/github/host/installed-github-effect.mjs'))
      .loadInstalledGitHubEffect;
  const failure = await rejected(() => load(profile, options));
  initializationFailure(failure, factoryFailure.code, factoryFailure);
  await finishCleanup(failure, held, () => {
    assert.equal(opens, 1, 'cleanup may not reopen the credential Site');
    assert.equal(authorizations, 1);
    assert.equal(factories, 1, 'cleanup may not rerun the failed row factory');
    assert.equal(restores, 1);
    assert.equal(failure.primaryFailure, factoryFailure);
  });
}

async function multiSourceFailure() {
  const first = owner();
  const second = owner(true);
  const loaded = [adapter(first, 0), adapter(second, 1)];
  loaded[1].connectorRevision = 'cleanup/wrong';
  const loads = [0, 0];
  const selections = installConnector(async profile => {
    loads[profile.index]++; return loaded[profile.index];
  });
  const paths = await Promise.all([0, 1].map(index =>
    writeJson(`source-${index}.json`, {version: sourceVersion, index})));
  const {loadInstalledSources} = await import('../../adapters/host-node/installed-source.mjs');
  const failure = await rejected(() => loadInstalledSources(paths,
    {root, principalId: 'fixture', moon: {}, baseEnvironmentWire: '{}'}));
  initializationFailure(failure, 'InstalledConnectorRegistrationMismatch');
  const handle = failure.cleanupHandle;
  assert.equal(handle.status().pending, true);
  assert.equal(second.completed, 0);
  assert.ok(second.attempts > 0, 'the failing second source must remain owned');
  assert.deepEqual(loads, [1, 1]);
  const primary = failure.primaryFailure;
  second.blocked = false;
  await Promise.all([handle.retry(), handle.retry()]);
  assert.equal(handle.status().pending, false);
  assert.equal(failure.cleanupPending, false);
  assert.equal(first.completed, 1, 'the already-held first source must close');
  assert.equal(second.completed, 1, 'the failed second source must close');
  const attempts = [first.attempts, second.attempts];
  await handle.retry();
  assert.deepEqual([first.attempts, second.attempts], attempts);
  assert.deepEqual(loads, [1, 1], 'neither source may reload on cleanup retry');
  assert.equal(selections.sourceSelections(), 2);
  assert.equal(selections.effectSelections(), 0);
  assert.equal(failure.primaryFailure, primary);
}

try {
  if (scenario.mode === 'adapter') await adapterFailure();
  else if (scenario.mode === 'github') await githubFailure();
  else if (scenario.mode === 'multi-source') await multiSourceFailure();
  else throw new TypeError('UnknownInitializationCustodyScenario');
  console.log('initialization custody checked');
} finally {
  mock.restoreAll();
  await rm(root, {recursive: true, force: true});
}
