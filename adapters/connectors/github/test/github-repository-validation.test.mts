import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {loadInstalledGitHubSource, publishInstalledGitHubSource, readGitHubSite}
  from '../host/installed-github-source.mjs';
import {loadInstalledGitHubEffect} from '../host/installed-github-effect.mjs';

test('GitHub actual scalar repository rule gates Source Effect and publication before credentials', async t => {
  // Only this provider package is compiled. No Common/Host, Site, Account,
  // credential, network, request issuer or installed-runtime substitute runs.
  const native = await import(new URL('../../../../_build/js/release/build/connectors/github/host_node/host_node.js', import.meta.url).href) as
    Parameters<typeof readGitHubSite>[2];
  const boundary = 'a'.repeat(100);
  for (const [owner, repo] of [['octo', 'hello.js'], ['A_0-', '...'], [boundary, boundary]]) {
    assert.equal(native.githubRepositoryAccessValid(owner, repo), true);
  }
  for (const invalid of ['', '.', '..', 'o/x', 'r?x', 'r%2F', '東京', 'repo\n', boundary + 'x']) {
    assert.equal(native.githubRepositoryAccessValid(invalid, 'repo'), false);
    assert.equal(native.githubRepositoryAccessValid('owner', invalid), false);
  }
  const root = await mkdtemp(join(tmpdir(), 'actql-github-name-rule-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'site.json');
  const site = {version: 'actql-installed-github-site/0.1', apiOrigin: 'https://github.invalid',
    credentialAuthorityId: 'unused-authority', credentialKeyId: 'unused-key',
    credentialPrivateKeyPath: join(root, 'MUST-NOT-READ.key'), environment: 'test',
    journalRoot: join(root, 'MUST-NOT-OPEN'), namespaceId: 'fixture', owner: 'octo', repo: 'hello.js',
    siteGeneration: 0, siteKey: 'fixture', tokenEnvironment: 'MUST_NOT_RESOLVE'};
  await writeFile(path, JSON.stringify(site));
  assert.deepEqual(await readGitHubSite(path, undefined, native), {...site, ca: undefined});
  const unreachable = () => assert.fail('Repository refusal must precede credentials/declaration/publication');
  const configurationReader = {readJson: async (selected: string) => {
    assert.equal(selected, path);return JSON.parse(await readFile(path, 'utf8'));
  }, readText: unreachable, readOriginalText: unreachable};
  const construction = {configurationReader, prepareDeclaration: unreachable,
    openRowSite: unreachable, createRowSource: unreachable,
    sourceReaderImplementation: unreachable, createSourceReader: unreachable};
  let nativeCalls = 0;
  const provider = Object.freeze({githubRepositoryAccessValid(owner: string, repo: string) {
    nativeCalls++;return native.githubRepositoryAccessValid(owner, repo);
  },
  // Explicit immutable fixture metadata for the unrelated CREATE preparer.
  // It issues no opaque value and must never open an actual Effect/Site here.
  installedStandardCreateHttpLimits: () => [1024, 1024, 64, 8]});
  const sourceProfile = {version: 'actql-installed-github-source/0.1', connectorId: 'github',
    siteProfilePath: path, publicationPath: join(root, 'MUST-NOT-READ-publication.json'),
    accountConfigurationWire: 'unused'};
  const effectProfile = {...sourceProfile, version: 'actql-installed-github-effect/0.1',
    writes: [{resource: 'issues', sources: [{field: 'body', target: 'body', null_behavior: 'refuse'}]}]};
  const options = {providerMoon: provider, configurationReader, construction,
    baseEnvironmentWire: 'unused', ledgerRoot: join(root, 'MUST-NOT-OPEN-ledger'), resolveSecret: unreachable};
  for (const caller of [
    () => loadInstalledGitHubSource(sourceProfile, options as unknown as Parameters<typeof loadInstalledGitHubSource>[1]),
    () => loadInstalledGitHubEffect(effectProfile, options as unknown as Parameters<typeof loadInstalledGitHubEffect>[1]),
    () => publishInstalledGitHubSource(sourceProfile, options as unknown as Parameters<typeof publishInstalledGitHubSource>[1]),
  ]) {
    await writeFile(path, JSON.stringify({...site, repo: '..', caPath: join(root, 'MUST-NOT-READ-ca')}));
    const before = nativeCalls;
    await assert.rejects(caller(), {code: 'InvalidGitHubRepository'});
    assert.equal(nativeCalls, before + 1);
    // The old JS regex coerced numeric/array inputs. Configuration names are
    // Text: reject them before entering the typed predicate, without coercion.
    for (const repo of [17, ['hello.js']]) {
      await writeFile(path, JSON.stringify({...site, repo}));
      await assert.rejects(caller(), {code: 'InvalidGitHubRepository'});
      assert.equal(nativeCalls, before + 1);
    }
  }
});
