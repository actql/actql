import assert from 'node:assert/strict';
import test from 'node:test';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';

// These are installation components, not public Run/Result/Saved acceptance.
// Every initialization, Resource, shared constructor and cleanup boundary is
// production code. BigQuery network work is deliberately never dispatched.
test('generated BigQuery entry reaches its real bound constructor and exact registration', async t => {
  const f = await boundConstructionActualFixture(t);
  const source = await f.load(await f.profile());
  assert.equal(source.connectorBindings[0].connectorId, 'bigquery1');
  assert.equal(typeof source.prepare, 'function');
  assert.equal(typeof source.close, 'function');
  assert.equal(f.secretReads(), 0);
  assert.equal(f.retire(), false, 'live adapter prevents parent retirement');
  await f.close();
  assert.equal(f.pending(), false);
  assert.equal(f.retire(), true, 'same actual parent remains retired');
  await f.close();
});

test('BigQuery missing-key rejection cleans its authorization child before any Site is returned', async t => {
  const f = await boundConstructionActualFixture(t);
  const sibling = await f.load(await f.profile());
  const failed = await f.profile({missingKey: true});
  let primary;
  await assert.rejects(f.load(failed), failure => {
    primary = failure;
    const pending = [failure], seen = new Set();
    while (pending.length) {
      const item = pending.shift();
      if (!item || typeof item !== 'object' || seen.has(item)) continue;
      seen.add(item);
      if (item.code === 'ENOENT') return true;
      pending.push(item.cause, item.primaryFailure);
    }
    return false;
  });
  assert.ok(primary);
  assert.equal(f.sources[0], sibling);
  assert.equal(f.sources.length, 1, 'failed construction never publishes another adapter');
  assert.equal(f.retire(), false, 'failed sibling cannot acknowledge the live sibling');
  assert.equal(f.secretReads(), 0);
  await f.close();
  assert.equal(f.pending(), false);
});


test('post-Site current failure closes its real journal without closing a sibling', async t => {
  const f = await boundConstructionActualFixture(t);
  const first = await f.profile();
  const sibling = await f.load(first);
  const failed = await f.profile();
  const fault = f.failCurrentAfterJournal(failed);
  await assert.rejects(f.load(failed), failure => {
    const pending = [failure], seen = new Set();
    while (pending.length) {
      const item = pending.shift();
      if (item === fault.failure) return true;
      if (!item || typeof item !== 'object' || seen.has(item)) continue;
      seen.add(item); pending.push(item.cause, item.primaryFailure);
    }
    return false;
  });
  assert.equal(fault.calls, 1, 'one original post-acquisition currentness failure');
  assert.equal(f.sources.length, 1);
  assert.equal(f.sources[0], sibling);
  if (process.platform === 'linux') {
    assert.ok(fault.descriptors.length > 0, 'failed Site really acquired a physical journal');
    assert.deepEqual(f.openJournalDescriptors(failed.journalPath), [], 'its original journal was closed');
    assert.ok(f.openJournalDescriptors(first.journalPath).length > 0, 'sibling stays physically live');
  }
  assert.equal(f.retire(), false, 'live sibling is not a parent cleanup ACK');
  assert.equal(f.secretReads(), 0);
  await f.close();
  if (process.platform === 'linux') assert.deepEqual(f.openJournalDescriptors(first.journalPath), []);
  assert.equal(f.retire(), true);
});

function failureMatches(failure, matches) {
  const pending = [failure], seen = new Set();
  while (pending.length) {
    const item = pending.shift();
    if (matches(item)) return true;
    if (!item || typeof item !== 'object' || seen.has(item)) continue;
    seen.add(item); pending.push(item.cause, item.primaryFailure);
  }
  return false;
}

test('generated Local table Effect retains its published Environment and actual authorization parent', async t => {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.tableEffectProfile();
  const effect = await f.load(selected);
  assert.equal(effect.connectorBindings[0].connectorId, 'table');
  assert.equal(effect.environmentWire, selected.value.environmentWire);
  assert.equal(typeof effect.prepareCaptured, 'function');
  assert.equal(typeof effect.prepareRecovered, 'function');
  assert.equal(effect.effectSelectors.length, 1);
  const {capabilityCid, ...selector} = effect.effectSelectors[0];
  assert.match(capabilityCid, /^sha256:[0-9a-f]{64}$/u);
  assert.deepEqual([selector], [{kind: 'store', target: 'connector://table/catalog',
    mappingRef: 'mapping:table.catalog.v1', mappingCid: selected.value.targets[0].mappingCid, effectId: 'save'}]);
  assert.equal(f.retire(), false);
  assert.equal(f.secretReads(), 0);
  await f.close();
  assert.equal(f.retire(), true);
});

test('Local table Effect post-construction current failure retains primary and leaves sibling alive', async t => {
  const f = await boundConstructionActualFixture(t);
  const first = await f.profile();
  const sibling = await f.load(first);
  const selected = await f.tableEffectProfile();
  // The real Table constructor creates this ledger directory after bridge and
  // authorization acquisition. The existing current callback runs on return.
  // No physical DB descriptor is claimed for this inert installation bridge.
  const fault = f.failCurrentAfterTableConstruction();
  await assert.rejects(f.load(selected), error => failureMatches(error, item => item === fault.failure));
  assert.equal(fault.calls, 1);
  assert.equal(f.sources.length, 1);
  assert.equal(f.sources[0], sibling);
  if (process.platform === 'linux') assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
  assert.equal(f.retire(), false);
  await f.close();
  assert.equal(f.retire(), true);
});

for (const invalid of ['invalidCatalog', 'invalidTarget']) {
  test(`Local table Effect rejects ${invalid} before authorization or Catalog I/O`, async t => {
    const {existsSync} = await import('node:fs');
    const {join} = await import('node:path');
    const f = await boundConstructionActualFixture(t);
    const selected = await f.tableEffectProfile({[invalid]: true});
    await assert.rejects(f.load(selected), {code: invalid === 'invalidCatalog'
      ? 'InvalidTablePhysicalConfiguration' : 'InvalidInstalledTableTarget'});
    assert.equal(f.sources.length, 0);
    assert.equal(f.secretReads(), 0);
    assert.equal(existsSync(join(f.root, 'state')), false, 'no Effect ledger store (pre-authorization order is checked in the real loader)');
    assert.equal(existsSync(selected.value.catalog.database), false);
    assert.equal(existsSync(selected.value.catalog.warehouse), false);
    await f.close();
  });
}

test('generated Local table Source registers one actual adapter without starting Python', async t => {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.tableSourceProfile();
  const source = await f.load(selected);
  assert.equal(source.connectorBindings[0].connectorId, 'table');
  assert.equal(source.connectorRegistration, 'local');
  assert.equal(source.tableReadTargets[0].selector.table_name, 'rows');
  assert.equal(typeof source.prepare, 'function');
  assert.equal(f.retire(), false);
  assert.equal(f.secretReads(), 0);
  await f.close();
  assert.equal(f.retire(), true);
});

test('Local table Source authorization rejection after bridge preparation preserves its sibling', async t => {
  const f = await boundConstructionActualFixture(t);
  const first = await f.profile();
  const sibling = await f.load(first);
  const selected = await f.tableSourceProfile({invalidAccount: true});
  await assert.rejects(f.load(selected), error => failureMatches(error,
    item => item?.code === 'ACTQL_E_ACCOUNT_CONFIG_INVALID'));
  assert.equal(f.sources.length, 1);
  assert.equal(f.sources[0], sibling);
  if (process.platform === 'linux') assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
  assert.equal(f.retire(), false);
  await f.close();
  assert.equal(f.retire(), true);
});

test('generated GitHub Source restores a real loopback-published generation without another request', async t => {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.githubProfile();
  const requests = selected.exchanges();
  assert.ok(requests > 0);
  const source = await f.load(selected);
  assert.equal(source.connectorRegistration, 'github');
  assert.equal(source.connectorBindings[0].connectorId, selected.value.connectorId);
  assert.equal(selected.exchanges(), requests, 'installation restores publication, not remote discovery');
  assert.equal(f.secretReads(), 0);
  assert.equal(f.retire(), false);
  await f.close();
  assert.equal(f.retire(), true);
});

test('GitHub post-Site current failure releases its real journal and leaves sibling live', async t => {
  const f = await boundConstructionActualFixture(t);
  const first = await f.profile();
  const sibling = await f.load(first);
  const selected = await f.githubProfile();
  const requests = selected.exchanges();
  const fault = f.failCurrentAfterJournal(selected);
  await assert.rejects(f.load(selected), error => failureMatches(error, item => item === fault.failure));
  assert.equal(fault.calls, 1);
  assert.equal(f.sources.length, 1);
  assert.equal(f.sources[0], sibling);
  assert.equal(selected.exchanges(), requests);
  if (process.platform === 'linux') {
    assert.ok(fault.descriptors.length > 0);
    assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
    assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
  }
  assert.equal(f.retire(), false);
  await f.close();
});

for (const provider of ['gcs', 'hubspot', 'kintone', 'snowflake']) {
  const profile = f => provider === 'gcs' ? f.gcsProfile() : f.metadataSourceProfile(provider);
  test(`generated ${provider} Source reaches its actual constructor and registration`, async t => {
    const f = await boundConstructionActualFixture(t);
    const selected = await profile(f);
    const source = await f.load(selected);
    assert.equal(source.connectorRegistration, provider);
    assert.equal(source.connectorBindings[0].connectorId, selected.value.connectorId);
    assert.equal(typeof source.prepare, 'function');
    assert.equal(f.secretReads(), 0);
    assert.equal(f.retire(), false);
    await f.close();
    assert.equal(f.retire(), true);
  });

  test(`${provider} post-Site current failure cleans its actual child but not the sibling`, async t => {
    const f = await boundConstructionActualFixture(t);
    const first = await f.profile();
    const sibling = await f.load(first);
    const selected = await profile(f);
    const fault = f.failCurrentAfterJournal(selected);
    await assert.rejects(f.load(selected), error => failureMatches(error, item => item === fault.failure));
    assert.equal(fault.calls, 1);
    assert.equal(f.sources.length, 1);
    assert.equal(f.sources[0], sibling);
    if (process.platform === 'linux') {
      assert.ok(fault.descriptors.length > 0);
      assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
      assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
    }
    assert.equal(f.secretReads(), 0);
    assert.equal(f.retire(), false);
    await f.close();
  });
}

for (const role of ['source', 'effect']) {
  test(`generated Salesforce ${role} restores its real publication and preserves the public surface`, async t => {
    const f = await boundConstructionActualFixture(t);
    const selected = await f.salesforceProfile(role);
    const requests = selected.exchanges();
    assert.ok(requests > 0);
    const adapter = await f.load(selected);
    assert.equal(adapter.connectorBindings[0].connectorId, selected.value.connectorId);
    if (role === 'source') {
      assert.deepEqual(Object.keys(adapter).sort(), ['realizationKey',
        'supportsRetainedRelationOutput', 'connectorRegistration', 'connectorRevision',
        'environmentWire', 'generationCid', 'connectorBindings', 'readAuthorization',
        'sourceAccess', 'sourceReadAccesses', 'admitsSource', 'ledgerCapacity',
        'managedCaptureCapacity', 'managedWholeSourceCapacity', 'managedEffectPlanSelection', 'prepare',
        'open', 'close', 'discovery', 'queryAliases'].sort());
      assert.equal(adapter.realizationKey, 'salesforce-acquired');
      assert.equal(adapter.supportsRetainedRelationOutput, true);
    } else {
      assert.equal(typeof adapter.prepareCaptured, 'function');
      assert.equal(typeof adapter.prepareRecovered, 'function');
      assert.ok(adapter.effectSelectors.length > 0);
    }
    assert.equal(selected.exchanges(), requests, 'installation must not repeat remote discovery');
    assert.equal(f.secretReads(), 0);
    assert.equal(f.retire(), false);
    await f.close();
    if (process.platform === 'linux') assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
    assert.equal(f.retire(), true);
  });

  test(`Salesforce ${role} post-Site failure closes its actual journal without closing a sibling`, async t => {
    const f = await boundConstructionActualFixture(t);
    const first = await f.profile();
    const sibling = await f.load(first);
    const selected = await f.salesforceProfile(role);
    const requests = selected.exchanges();
    const fault = f.failCurrentAfterJournal(selected);
    await assert.rejects(f.load(selected), error => failureMatches(error, item => item === fault.failure));
    assert.equal(fault.calls, 1);
    assert.equal(f.sources.length, 1);
    assert.equal(f.sources[0], sibling);
    assert.equal(selected.exchanges(), requests);
    if (process.platform === 'linux') {
      assert.ok(fault.descriptors.length > 0);
      assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
      assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
    }
    assert.equal(f.secretReads(), 0);
    assert.equal(f.retire(), false);
    await f.close();
    assert.equal(f.retire(), true);
  });
}

test('Salesforce Source identityParts uses the real funded reader without resolving credentials', async t => {
  const {installedSourceConfigurationReader} = await import('./installed-host-services.mjs');
  const {captureConfigurationReaders} = await import('./source-profile-json.mjs');
  const {installedConnectors} = await import('../connectors-builtin/installations.generated.mjs');
  const f = await boundConstructionActualFixture(t);
  const selected = await f.salesforceProfile('source');
  const requests = selected.exchanges();
  const entry = installedConnectors.find(value => value.registration === 'salesforce');
  const module = await entry.source.load();
  const configurationReader = installedSourceConfigurationReader(f.services);
  const readers = captureConfigurationReaders(configurationReader, undefined,
    () => assert.fail('The actual initial parent must provide its reader'));
  const parts = await module.identityParts(selected.value, selected.value, readers.readJson,
    entry, {configurationReader});
  assert.equal(parts.length, 3);
  assert.equal(parts[0].connectorId, selected.value.connectorId);
  assert.equal(parts[1].siteKey, selected.value.connectorId);
  assert.equal(typeof parts[2], 'object');
  assert.equal(selected.exchanges(), requests);
  assert.equal(f.secretReads(), 0);
  // An identity read alone does not manufacture or register an adapter.
  assert.equal(f.sources.length, 0);
  await f.close();
  assert.equal(f.retire(), true);
});
