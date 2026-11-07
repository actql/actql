import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {readSourceProfileJson} from '../../../host-node/source-profile-json.mjs';
import {retainInstalledHostInitializationFailure} from '../../../host-node/installed-host-cleanup.mjs';
import {loadInstalledGcsSource, installedGcsSourceIdentityParts} from '../host/installed-gcs-source.mjs';

async function fixture(t) {
  const scratch = await createOwnedScratch({parent: new URL('../../../../_build/', import.meta.url).pathname,
    prefix: 'gcs-site-bounds-', label: 'GCS original Site configuration read'});
  const path = join(scratch.path, 'site.json');
  const site = {version: 'actql-installed-gcs-site/0.1', credentialAuthorityId: 'fixture',
    credentialKeyId: 'fixture', credentialPrivateKeyPath: join(scratch.path, 'never-opened.key'),
    environment: 'fixture', journalRoot: join(scratch.path, 'never-opened-journal'),
    namespaceId: 'fixture', siteGeneration: 1, siteKey: 'fixture', tokenEnvironment: 'FIXTURE_TOKEN'};
  const body = JSON.stringify(site);
  const profile = {version: 'actql-installed-gcs-source/0.1', connectorId: 'storage',
    project: 'fixture-project', bucket: 'actql-fixture', prefix: 'e\u0301/',
    mediaType: 'application/pdf', siteProfilePath: path,
    accountConfigurationWire: '{"account_id":"fixture"}',
    limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
      maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
      maxPageBytes: 8192, maxPageItems: 9, maxRequestBytes: 4096, maxContentBytes: 4096}};
  let coreCalls = 0, secretCalls = 0;
  const reachedCore = Object.freeze(new Error('ReachedBoundDeclarationBoundary'));
  // Reader/domain boundary only, not a Host construction or lifecycle proof.
  // Actual Common/Resource composition has separate installed-bound tests.
  const unavailable = () => assert.fail('Reader test must stop before Site construction');
  const construction = {configurationReader: {readJson: readSourceProfileJson},
    prepareDerivedDeclaredCommands() {coreCalls++; throw reachedCore;},
    prepareReadTargetWithMappings: unavailable, openRowSite: unavailable, createRowSource: unavailable};
  const options = {root: scratch.path, principalId: 'fixture', construction,
    resolveSecret() { secretCalls++; assert.fail('UnexpectedCredentialOperation'); }};
  const open = fs.open;
  const state = {bytes: 0, reads: 0, opens: 0, closes: 0, allowClose: true, handle: undefined};
  fs.open = async (name, ...args) => {
    const handle = await open(name, ...args);
    if (name !== path) return handle;
    state.handle = handle;
    state.opens++;
    return {
      async read(...parameters) {
        state.reads++;
        const result = await handle.read(...parameters);
        state.bytes += result.bytesRead;
        return result;
      },
      async close() {
        state.closes++;
        if (!state.allowClose) return false;
        await handle.close();
      },
    };
  };
  syncBuiltinESMExports();
  t.after(async () => {
    fs.open = open;
    syncBuiltinESMExports();
    await state.handle?.close();
    scratch.passed();
  });
  return {path, body, site, profile, options, state, reachedCore,
    coreCalls: () => coreCalls, secretCalls: () => secretCalls};
}

test('GCS Site load accepts exactly its original 1 MiB ceiling and stops at lookahead', async t => {
  const f = await fixture(t);
  await fs.writeFile(f.path, f.body + ' '.repeat(1048576 - Buffer.byteLength(f.body)));
  await assert.rejects(loadInstalledGcsSource(f.profile, f.options), error => error === f.reachedCore);
  assert.equal(f.coreCalls(), 1);
  assert.equal(f.state.bytes, 1048576);
  assert.equal(f.state.closes, 1);
  await fs.appendFile(f.path, ' ');
  f.state.bytes = 0;
  await assert.rejects(loadInstalledGcsSource(f.profile, f.options), {code: 'InvalidInstalledGcsSite'});
  assert.equal(f.state.bytes, 1048577);
  assert.equal(f.coreCalls(), 1);
  assert.equal(f.secretCalls(), 0);
});

test('GCS Site identity uses the same 1 MiB ceiling without changing its original parts', async t => {
  const f = await fixture(t);
  await fs.writeFile(f.path, f.body);
  const parts = await installedGcsSourceIdentityParts(f.profile, f.profile, readSourceProfileJson);
  assert.deepEqual(parts[2], f.site);
  assert.equal(parts[0].accountConfigurationWire.account_id, 'fixture');
  await fs.appendFile(f.path, ' '.repeat(1048577));
  f.state.bytes = 0;
  await assert.rejects(installedGcsSourceIdentityParts(f.profile, f.profile, readSourceProfileJson),
    {message: 'InvalidInstalledSourceProfile'});
  assert.equal(f.state.bytes, 1048577);
  assert.equal(f.coreCalls(), 0);
  assert.equal(f.secretCalls(), 0);
});

test('GCS Site error projection retains its original FD through initialization cleanup', async t => {
  const f = await fixture(t);
  await fs.writeFile(f.path, f.body);
  f.state.allowClose = false;
  let failure;
  await assert.rejects(loadInstalledGcsSource(f.profile, f.options), error => {
    failure = error;
    assert.equal(error.code, 'InvalidInstalledGcsSite');
    assert.equal(error.cleanupHandle.status().pending, true);
    return true;
  });
  const outer = await retainInstalledHostInitializationFailure(failure, {});
  assert.equal(outer.cleanupPending, true);
  await f.state.handle.stat();
  const reads = f.state.reads;
  f.state.allowClose = true;
  await outer.cleanupHandle.retry();
  assert.equal(outer.cleanupPending, false);
  await assert.rejects(f.state.handle.stat(), {code: 'EBADF'});
  assert.equal(f.state.opens, 1);
  assert.equal(f.state.reads, reads);
  assert.equal(f.coreCalls(), 0);
  assert.equal(f.secretCalls(), 0);
});
