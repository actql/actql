import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {readSourceProfileJson} from './source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {sourceReadAccountConfiguration} from './local-account-config.mjs';
import {installedSourceIdentity} from './installed-source.mjs';
import {installedEffectIdentity} from './installed-effect.mjs';
import {readGitHubSite, readGitHubPublication,
  installedGitHubSourceIdentityParts} from '../connectors/github/host/installed-github-source.mjs';
import {installedGitHubEffectIdentityParts} from '../connectors/github/host/installed-github-effect.mjs';
import {installSalesforceAuthorization, loadInstalledSalesforceSite} from
  '../connectors/salesforce/host/installed-salesforce-site.mjs';
import {readPublicationFile} from '../connectors/salesforce/host/salesforce-publication.mjs';
import {installedSalesforceSourceIdentityParts} from
  '../connectors/salesforce/host/installed-salesforce-source.mjs';
import {installedSalesforceEffectIdentityParts} from
  '../connectors/salesforce/host/installed-salesforce-effect-installation.mjs';

const siteLimit = 1024 * 1024;
const publicationLimit = 16_000_000;
const salesforceSiteLimit = 8 * 1024 * 1024;
const cid = body => `sha256:${createHash('sha256').update(body, 'utf8').digest('hex')}`;

async function fixture(t) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'connector-profile-bounds-', label: 'Original connector configuration read boundary'});
  const path = join(scratch.path, 'selected.json');
  const open = fs.open;
  const state = {opens: 0, bytes: 0, reads: 0, closes: 0, allowClose: true};
  let assertionsPassed = false;
  fs.open = async (name, ...args) => {
    const original = await open(name, ...args);
    if (name !== path) return original;
    state.opens++;
    state.original = original;
    return {
      async read(...parameters) {
        state.reads++;
        const result = await original.read(...parameters);
        state.bytes += result.bytesRead;
        return result;
      },
      async close() {
        state.closes++;
        if (!state.allowClose) return false;
        await original.close();
      },
    };
  };
  syncBuiltinESMExports();
  t.after(async () => {
    fs.open = open;
    syncBuiltinESMExports();
    await state.original?.close();
    if (assertionsPassed) scratch.passed();
    t.diagnostic(`Retained owned connector configuration fixture: ${scratch.path}`);
  });
  return {root: scratch.path, path, state, passed() { assertionsPassed = true; }};
}

const githubSite = root => ({version: 'actql-installed-github-site/0.1',
  apiOrigin: 'https://github.example.test', owner: 'owner', repo: 'repo',
  credentialAuthorityId: 'fixture', credentialKeyId: 'fixture',
  credentialPrivateKeyPath: join(root, 'never-opened.key'), environment: 'fixture',
  journalRoot: join(root, 'never-opened-journal'), namespaceId: 'fixture',
  siteGeneration: 1, siteKey: 'fixture', tokenEnvironment: 'FIXTURE_TOKEN'});

test('GitHub Site and publication reads stop at the same original 1 MiB boundary', async t => {
  const f = await fixture(t), site = githubSite(f.root);
  const body = JSON.stringify(site);
  await fs.writeFile(f.path, body + ' '.repeat(siteLimit - Buffer.byteLength(body)));
  assert.equal((await readGitHubSite(f.path)).owner, site.owner);
  assert.equal(f.state.bytes, siteLimit);
  await fs.appendFile(f.path, ' ');
  f.state.bytes = 0;
  await assert.rejects(readGitHubSite(f.path), {code: 'InvalidInstalledGitHubSite'});
  assert.equal(f.state.bytes, siteLimit + 1);
  const publication = {version: 'actql-github-publication/0.1', connectorId: 'github',
    apiOrigin: site.apiOrigin, owner: site.owner, repo: site.repo};
  const wire = JSON.stringify(publication);
  await fs.writeFile(f.path, wire + ' '.repeat(siteLimit - Buffer.byteLength(wire)));
  assert.deepEqual(await readGitHubPublication({connectorId: 'github', publicationPath: f.path}, site), publication);
  await fs.appendFile(f.path, ' ');
  f.state.bytes = 0;
  await assert.rejects(readGitHubPublication({connectorId: 'github', publicationPath: f.path}, site),
    {code: 'GitHubPublicationMissing'});
  assert.equal(f.state.bytes, siteLimit + 1);
  f.passed();
});

test('GitHub Source and Effect identity reads keep the same bounded original parts', async t => {
  const f = await fixture(t), site = githubSite(f.root);
  await fs.writeFile(f.path, JSON.stringify(site));
  const profile = {version: 'actql-installed-github-source/0.1', connectorId: 'github',
    siteProfilePath: f.path, publicationPath: f.path, accountConfigurationWire: '{"account_id":"fixture"}'};
  const parts = await installedGitHubSourceIdentityParts(profile, profile, readSourceProfileJson);
  assert.deepEqual(parts.slice(1), [site, site]);
  const effect = {...profile, version: 'actql-installed-github-effect/0.1',
    writes: [{resource: 'issues', sources: [{target: 'title', field: 'title', null_behavior: 'reject'}]}]};
  assert.deepEqual((await installedGitHubEffectIdentityParts(effect, readSourceProfileJson)).slice(1), [site, site]);
  await fs.appendFile(f.path, ' '.repeat(siteLimit));
  for (const read of [() => installedGitHubSourceIdentityParts(profile, profile, readSourceProfileJson),
    () => installedGitHubEffectIdentityParts(effect, readSourceProfileJson)]) {
    await assert.rejects(read(), {message: 'InvalidInstalledSourceProfile'});
  }
  f.passed();
});

test('normal GitHub Source and Effect identity callers forward the explicit original Site ceiling', async t => {
  const f = await fixture(t), site = githubSite(f.root);
  const sourcePath = join(f.root, 'source.json'), effectPath = join(f.root, 'effect.json');
  const publicationPath = join(f.root, 'publication.json');
  const profile = {version: 'actql-installed-github-source/0.1', connectorId: 'github',
    siteProfilePath: f.path, publicationPath, accountConfigurationWire: '{"account_id":"fixture"}'};
  const effect = {...profile, version: 'actql-installed-github-effect/0.1',
    writes: [{resource: 'issues', sources: [{target: 'title', field: 'title', null_behavior: 'reject'}]}]};
  await fs.writeFile(sourcePath, JSON.stringify(profile));
  await fs.writeFile(effectPath, JSON.stringify(effect));
  await fs.writeFile(publicationPath, '{"original":"publication"}');
  const body = JSON.stringify(site);
  await fs.writeFile(f.path, body);
  const sourceIdentity = await installedSourceIdentity(sourcePath);
  const effectIdentity = await installedEffectIdentity(effectPath);
  await fs.writeFile(f.path, body + ' '.repeat(siteLimit - Buffer.byteLength(body)));
  assert.equal(await installedSourceIdentity(sourcePath), sourceIdentity);
  assert.equal(await installedEffectIdentity(effectPath), effectIdentity);
  await fs.appendFile(f.path, ' ');
  await assert.rejects(installedSourceIdentity(sourcePath), {message: 'InvalidInstalledSourceProfile'});
  await assert.rejects(installedEffectIdentity(effectPath), {code: 'InvalidInstalledEffectProfile'});
  f.passed();
});

test('GitHub read failure retains the same FD through outer initialization cleanup without rereading', async t => {
  const f = await fixture(t);
  await fs.writeFile(f.path, JSON.stringify(githubSite(f.root)));
  f.state.allowClose = false;
  let failure;
  await assert.rejects(readGitHubSite(f.path), error => {
    failure = error;
    return error.code === 'InvalidInstalledGitHubSite' && error.cleanupHandle.status().pending;
  });
  const outer = await retainInstalledHostInitializationFailure(failure, {});
  assert.equal(outer.cleanupPending, true);
  const reads = f.state.reads;
  await f.state.original.stat();
  f.state.allowClose = true;
  await outer.cleanupHandle.retry();
  assert.equal(outer.cleanupPending, false);
  await assert.rejects(f.state.original.stat(), {code: 'EBADF'});
  assert.equal(f.state.opens, 1);
  assert.equal(f.state.reads, reads);
  f.passed();
});

test('Salesforce publication keeps exact UTF8 text and the original 16000000 byte ceiling', async t => {
  const f = await fixture(t);
  const prefix = '{ "unicode": "e\u0301😀", "n": 1.00 }\n';
  const body = prefix + ' '.repeat(publicationLimit - Buffer.byteLength(prefix));
  await fs.writeFile(f.path, body);
  const read = await readPublicationFile(f.path);
  assert.equal(read.body === body, true);
  assert.equal(read.generationCid, cid(body));
  assert.equal(f.state.bytes, publicationLimit);
  await fs.appendFile(f.path, ' ');
  f.state.bytes = 0;
  await assert.rejects(readPublicationFile(f.path), {code: 'InvalidSalesforcePublication'});
  assert.equal(f.state.bytes, publicationLimit + 1);
  f.passed();
});

test('Salesforce publication preserves replacement decoding and the exact decoded UTF8 ceiling', async t => {
  const f = await fixture(t);
  // This remains valid JSON after the original replacement decoding. Its raw
  // bytes fit the physical bound even when the decoded identity text does not.
  const raw = Buffer.concat([Buffer.from('{"original":"'),
    Buffer.alloc(5_333_328, 0xff), Buffer.from('"} ')]);
  const body = raw.toString('utf8');
  assert.equal(Buffer.byteLength(body, 'utf8'), publicationLimit);
  assert.equal(JSON.parse(body).original.length, 5_333_328);
  assert.ok(raw.length < publicationLimit);
  await fs.writeFile(f.path, raw);
  const read = await readPublicationFile(f.path);
  assert.equal(read.body, body);
  assert.equal(read.generationCid, cid(body));
  assert.equal(f.state.bytes, raw.length);
  await fs.appendFile(f.path, ' ');
  f.state.bytes = 0;
  assert.equal(Buffer.byteLength(body + ' ', 'utf8'), publicationLimit + 1);
  await assert.rejects(readPublicationFile(f.path), {code: 'InvalidSalesforcePublication'});
  assert.equal(f.state.bytes, raw.length + 1);
  const originalCounter = Buffer.concat([Buffer.from('{"original":"'),
    Buffer.alloc(5_333_334, 0xff), Buffer.from('"}')]);
  assert.equal(originalCounter.length, 5_333_349);
  assert.equal(Buffer.byteLength(originalCounter.toString('utf8'), 'utf8'), 16_000_017);
  assert.equal(createHash('sha256').update(originalCounter).digest('hex'),
    'd9b709929e8b0251f620bc715ba351f81fa9699a256b91904be46c27ec008cdd');
  await fs.writeFile(f.path, originalCounter);
  await assert.rejects(readPublicationFile(f.path), {code: 'InvalidSalesforcePublication'});
  f.passed();
});

test('Salesforce publication close failure preserves exact original cleanup and missing-file classification', async t => {
  const f = await fixture(t);
  await assert.rejects(readPublicationFile(f.path), {code: 'SalesforcePublicationMissing'});
  await fs.writeFile(f.path, '{ "original": true }\n');
  f.state.allowClose = false;
  let failure;
  await assert.rejects(readPublicationFile(f.path), error => {
    failure = error;
    return error.cleanupHandle.status().pending;
  });
  const outer = await retainInstalledHostInitializationFailure(failure, {});
  assert.equal(outer.cleanupPending, true);
  const reads = f.state.reads;
  f.state.allowClose = true;
  await outer.cleanupHandle.retry();
  assert.equal(outer.cleanupPending, false);
  assert.equal(f.state.opens, 1);
  assert.equal(f.state.reads, reads);
  await assert.rejects(f.state.original.stat(), {code: 'EBADF'});
  f.passed();
});

test('Salesforce Source and Effect identity preserve publication text projection above the JSON configuration ceiling', async t => {
  const f = await fixture(t), sitePath = join(f.root, 'site.json');
  const site = {original: 'Site'};
  await fs.writeFile(sitePath, JSON.stringify(site));
  const publication = {original: 'é'};
  const body = JSON.stringify(publication) + ' '.repeat(9 * 1024 * 1024);
  await fs.writeFile(f.path, body);
  const profile = {version: 'actql-installed-salesforce-source/0.1', connectorId: 'salesforce',
    siteProfilePath: sitePath, publicationPath: f.path, resources: ['Contact'],
    accountConfigurationWire: '{"account_id":"fixture"}'};
  assert.deepEqual((await installedSalesforceSourceIdentityParts(profile, profile, readSourceProfileJson)).slice(1),
    [site, publication]);
  const effect = {...profile, version: 'actql-installed-salesforce-effect/0.1',
    writes: [{resource: 'Contact', kind: 'update', fields: ['Name']}]};
  delete effect.resources;
  assert.deepEqual((await installedSalesforceEffectIdentityParts(effect, readSourceProfileJson)).slice(1),
    [site, publication]);
  assert.equal((await readPublicationFile(f.path)).generationCid, cid(body));
  f.passed();
});

async function salesforceFixture(t) {
  // GitHub's file-only boundary cases do not need an unrelated Common import.
  const common = await import('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
  const f = await fixture(t);
  const keyPath = join(f.root, 'credential.key');
  await fs.writeFile(keyPath, generateKeyPairSync('ed25519').privateKey.export({type: 'pkcs8', format: 'pem'}));
  const site = {version: 'actql-installed-salesforce-site/0.1', apiVersion: 'v62.0',
    cliAlias: 'fixture', cliUsername: 'fixture@example.test', connectionRevision: 'original',
    credentialAuthorityId: 'fixture', credentialKeyId: 'fixture', credentialPrivateKeyPath: keyPath,
    environment: 'fixture', instanceOrigin: 'https://salesforce.example.test',
    journalRoot: join(f.root, 'never-opened-journal'), orgId: '00D000000000001',
    siteGeneration: 1, siteKey: 'fixture', namespaceId: 'fixture'};
  const authorization = await installSalesforceAuthorization({root: f.root, principalId: 'fixture',
    accountConfiguration: sourceReadAccountConfiguration({connection: `salesforce:${site.orgId}`, resource: 'Contact'})});
  const reachedJournal = new Error('ReachedOriginalJournalConstructor');
  let journalCalls = 0, secretCalls = 0;
  const options = {commonMoon: common, salesforceMoon: {}, authorization, runtimeBundleCid: cid('runtime'),
    resolveSecret() { secretCalls++; assert.fail('UnexpectedSecretResolution'); },
    openCredentialJournal() { journalCalls++; throw reachedJournal; }};
  return {...f, site, options, reachedJournal, journalCalls: () => journalCalls, secretCalls: () => secretCalls};
}

test('Salesforce Site read accepts its existing identity 8 MiB ceiling and refuses one extra byte before credential journal construction', async t => {
  const f = await salesforceFixture(t), body = JSON.stringify(f.site);
  await fs.writeFile(f.path, body + ' '.repeat(salesforceSiteLimit - Buffer.byteLength(body)));
  await assert.rejects(loadInstalledSalesforceSite(f.path, f.options), error => error === f.reachedJournal);
  assert.equal(f.journalCalls(), 1);
  const exactBytes = f.state.bytes;
  await fs.appendFile(f.path, ' ');
  f.state.bytes = 0;
  await assert.rejects(loadInstalledSalesforceSite(f.path, f.options), {code: 'InvalidInstalledSalesforceSiteProfile'});
  assert.equal(exactBytes, salesforceSiteLimit);
  assert.equal(f.state.bytes, salesforceSiteLimit + 1);
  assert.equal(f.journalCalls(), 1);
  assert.equal(f.secretCalls(), 0);
  f.passed();
});

test('Salesforce Site close failure returns the same original FD and never constructs a credential journal', async t => {
  const f = await salesforceFixture(t);
  await fs.writeFile(f.path, JSON.stringify(f.site));
  f.state.allowClose = false;
  let failure;
  await assert.rejects(loadInstalledSalesforceSite(f.path, f.options), error => {
    failure = error;
    return error.code === 'InvalidInstalledSalesforceSiteProfile' && error.cleanupHandle.status().pending;
  });
  const outer = await retainInstalledHostInitializationFailure(failure, {});
  assert.equal(outer.cleanupPending, true);
  const reads = f.state.reads;
  f.state.allowClose = true;
  await outer.cleanupHandle.retry();
  assert.equal(outer.cleanupPending, false);
  assert.equal(f.state.opens, 1);
  assert.equal(f.state.reads, reads);
  assert.equal(f.journalCalls(), 0);
  assert.equal(f.secretCalls(), 0);
  f.passed();
});
