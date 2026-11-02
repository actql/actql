import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, writeFile} from 'node:fs/promises';
import {openHttpsExchangeFixture} from '../site-node/https-exchange-fixture.mjs';
import {observeOwnScopedStateFds} from '../../scripts/fixtures/external-rest/conformance.mjs';
import {boundConstructionActualFixture} from './fixtures/bound-construction-actual.fixture.mjs';
import {installedConnectors} from '../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';

function causedBy(error, code) {
  const pending = [error], seen = new Set();
  while (pending.length) {
    const value = pending.shift();
    if (value?.code === code) return true;
    if (!value || typeof value !== 'object' || seen.has(value)) continue;
    seen.add(value); pending.push(value.cause, value.primaryFailure);
  }
  return false;
}

// A trusted erroneous installer is the fault supplier. Its checker/identity
// and the generic loader, original parent, constructor, finish and cleanup
// remain real; no runtime value or original adapter is fabricated.
function faultyBigQuery(load) {
  const original = installedConnectors.find(entry => entry.registration === 'bigquery');
  return createInstalledConnectorTable([{...original, source: {...original.source,
    async load() {return {...await original.source.load(), load};}}}]);
}

test('another scope cannot publish a live sibling adapter or close its physical Site', async t => {
  const f = await boundConstructionActualFixture(t);
  const first = await f.profile();
  const sibling = await f.load(first);
  const second = await f.profile();
  let calls = 0;
  const connectorTable = faultyBigQuery(async () => {calls++; return sibling;});
  await assert.rejects(f.load(second, {connectorTable}), error =>
    causedBy(error, 'InstalledSourceConstructorUnavailable'));
  assert.equal(calls, 1);
  assert.equal(f.sources.length, 1);
  assert.equal(f.sources[0], sibling);
  if (process.platform === 'linux') {
    assert.ok(f.openJournalDescriptors(first.journalPath).length > 0,
      'rejecting a foreign adapter must not dispose the unrelated original owner');
  }
  assert.equal(f.retire(), false, 'live original sibling still prevents parent retirement');
  await f.close();
});

test('real initial Resource refuses oversized native demand before the domain projection', async t => {
  const {checked} = await import('../host-common/runtime-result.mjs');
  const f = await boundConstructionActualFixture(t);
  const selected = await f.profile();
  let quotes = 0, projections = 0;
  const connectorTable = faultyBigQuery(async (_profile, {construction, moon}) => {
    construction.prepareNativeDeclaration(Object.freeze({
      capacity() {
        quotes++;
        // A real native quote for a trusted hypothetical large producer.
        // No huge allocation, fake opaque value or parent quota override.
        return checked(moon.clientProgramInstalledSourceConstructionCapacity(
          0n, 0n, 1024n * 1024n * 1024n, 0n, 0n, 0n));
      },
      project() {projections++; assert.fail('An unfunded projection must not execute');},
    }));
  });
  await assert.rejects(f.load(selected, {connectorTable}), error => causedBy(error, 'MoonBitHostFailure'));
  assert.equal(quotes, 1);
  assert.equal(projections, 0);
  assert.equal(f.sources.length, 0);
  assert.equal(f.secretReads(), 0);
  if (process.platform === 'linux') assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
  await f.close();
});

test('an accidentally asynchronous native producer keeps the real parent pending until its original settles', async t => {
  const {checked} = await import('../host-common/runtime-result.mjs');
  const f = await boundConstructionActualFixture(t);
  const selected = await f.profile();
  let settle, calls = 0;
  const pending = new Promise(resolve => {settle = resolve;});
  // This is the erroneous provider callback, not a replacement cleanup ACK.
  const connectorTable = faultyBigQuery(async (_profile, {construction, moon}) => {
    construction.prepareNativeDeclaration(Object.freeze({
      capacity() {return checked(moon.clientProgramInstalledSourceConstructionCapacity(1n, 1n, 1n, 1n, 1n, 1n));},
      project() {calls++; return pending;},
    }));
  });
  try {
    await assert.rejects(f.load(selected, {connectorTable}), error =>
      causedBy(error, 'InstalledSourceConstructorNotSynchronous'));
    assert.equal(calls, 1);
    assert.equal(f.retire(), false, 'returned error is not a completed original producer');
    assert.equal(f.retire(), false, 'repeat observation does not replace producer settlement');
  } finally {
    settle(undefined);
    await pending;
    await Promise.resolve();
  }
  assert.equal(f.sources.length, 0);
  assert.equal(calls, 1, 'retirement never repeats domain construction');
  assert.equal(f.retire(), true);
  await f.close();
});

test('a faulty installer returning a sibling still cleans its own registered adapter only', async t => {
  const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
  const f = await boundConstructionActualFixture(t);
  const first = await f.profile();
  const sibling = await f.load(first);
  const second = await f.profile();
  let constructed;
  const connectorTable = faultyBigQuery(async (profile, options) => {
    constructed = await loadInstalledBigQuerySource(profile, options);
    assert.notEqual(constructed, sibling);
    if (process.platform === 'linux') {
      assert.ok(f.openJournalDescriptors(second.journalPath).length > 0,
        'the failing installer really acquired its own physical Site');
    }
    return sibling;
  });
  await assert.rejects(f.load(second, {connectorTable}), error =>
    causedBy(error, 'InstalledSourceConstructorUnavailable'));
  assert.ok(constructed);
  assert.equal(f.sources.length, 1);
  if (process.platform === 'linux') {
    assert.deepEqual(f.openJournalDescriptors(second.journalPath), [],
      'the registered original, not the foreign return value, must be cleaned');
    assert.ok(f.openJournalDescriptors(first.journalPath).length > 0,
      'the unrelated sibling remains physically live');
  }
  assert.equal(f.retire(), false);
  await f.close();
});

test('real journal cleanup refusal keeps its original carrier and parent pending until the allowed retry', async t => {
  const {join} = await import('node:path');
  const {generateKeyPairSync} = await import('node:crypto');
  const {openSqliteCredentialJournal} = await import('../site-node/sqlite-credential-journal.mjs');
  const {retainInstalledHostInitializationFailure} = await import('./installed-host-cleanup.mjs');
  const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
  const f = await boundConstructionActualFixture(t);
  const selected = await f.profile();
  const directory = join(f.root, 'partially-acquired-journal');
  const path = join(directory, 'credential-journal.sqlite3');
  const authority = generateKeyPairSync('ed25519');
  const primary = new Error('OriginalDomainFailureAfterJournalAcquisition');
  const closeFault = new Error('ExplicitExternalJournalCloseUnavailable');
  let available = false, closeAttempts = 0, physicalCloses = 0, constructions = 0;
  let originalFailure, observedFailure;
  const connectorTable = faultyBigQuery(async (profile, options) => {
    constructions++;
    await loadInstalledBigQuerySource(profile, options);
    const journal = openSqliteCredentialJournal(directory, {
      credentialAuthorities: new Map([['authority', new Map([['key', authority.publicKey]])]]),
    });
    // Only this external-IO supplier fails. The real cleanup owner captures
    // the actual journal and retries its same unfinished stage. No status,
    // retirement, Resource or primary-error projection is replaced.
    originalFailure = await retainInstalledHostInitializationFailure(primary, {journal,
      closeJournal() {
        closeAttempts++;
        if (!available) throw closeFault;
        assert.equal(journal.close(), true);
        physicalCloses++;
      }});
    throw originalFailure;
  });
  try {
    await assert.rejects(f.load(selected, {connectorTable}), error => {
      observedFailure = error;
      return error.primaryFailure === primary;
    });
    assert.equal(constructions, 1);
    assert.equal(originalFailure.cleanupHandle.status().pending, true);
    assert.equal(observedFailure.cleanupHandle.status().pending, true);
    assert.equal(physicalCloses, 0);
    assert.ok(closeAttempts > 0);
    assert.equal(f.retire(), false);
    if (process.platform === 'linux') {
      assert.ok(f.openJournalDescriptors(path).length > 0);
      assert.ok(f.openJournalDescriptors(selected.journalPath).length > 0,
        'registered adapter waits behind its own unfinished child cleanup');
    }
  } finally {
    available = true;
    if (observedFailure) assert.equal((await observedFailure.cleanupHandle.retry()).pending, false);
    else if (originalFailure) await originalFailure.cleanupHandle.retry();
  }
  assert.equal(originalFailure.cleanupHandle.status().pending, false);
  assert.equal(physicalCloses, 1);
  const attemptsAfterCompletion = closeAttempts;
  assert.equal((await observedFailure.cleanupHandle.retry()).pending, false);
  assert.equal(closeAttempts, attemptsAfterCompletion, 'completed physical stage is not reissued');
  assert.equal(constructions, 1);
  assert.equal(observedFailure.primaryFailure, primary);
  if (process.platform === 'linux') {
    assert.deepEqual(f.openJournalDescriptors(path), []);
    assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
  }
  assert.equal(f.retire(), true);
  await f.close();
});

for (const variant of ['close-collision', 'accessor', 'then', 'symbol']) {
  test(`actual RowSource rejects ${variant} publication before registration and cleans its own Site`, async t => {
    const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
    const f = await boundConstructionActualFixture(t);
    const first = await f.profile();
    const sibling = await f.load(first);
    const selected = await f.profile();
    let accessorCalls = 0, constructors = 0;
    const publication = variant === 'close-collision' ? {close() {assert.fail('Foreign close must never replace the owner');}}
      : variant === 'accessor' ? Object.defineProperty({}, 'providerValue', {enumerable: true,
        get() {accessorCalls++; assert.fail('Publication accessors must not be invoked');}})
      : variant === 'then' ? {then: undefined} : {[Symbol('provider')]: 'value'};
    Object.freeze(publication);
    const connectorTable = faultyBigQuery(async (profile, options) => {
      const original = options.construction;
      // The fault is one domain publication argument. Every invocation still
      // enters the exact bound constructor and original cleanup/registration.
      const construction = Object.freeze({...original, createRowSource(input) {
        constructors++;
        if (process.platform === 'linux') assert.ok(f.openJournalDescriptors(selected.journalPath).length > 0);
        return original.createRowSource({...input, publication});
      }});
      return loadInstalledBigQuerySource(profile, {...options, construction});
    });
    const expected = variant === 'close-collision' ? 'InstalledSourcePublicationCollision' : 'InvalidInstalledSourcePublication';
    await assert.rejects(f.load(selected, {connectorTable}), error => causedBy(error, expected));
    assert.equal(constructors, 1);
    assert.equal(accessorCalls, 0);
    assert.equal(f.sources.length, 1);
    assert.equal(f.sources[0], sibling);
    if (process.platform === 'linux') {
      assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
      assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
    }
    assert.equal(f.retire(), false);
    await f.close();
  });
}

test('an unregistered projection cannot replace the actual registered adapter', async t => {
  const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
  const f = await boundConstructionActualFixture(t);
  const selected = await f.profile();
  let original, projection;
  const connectorTable = faultyBigQuery(async (profile, options) => {
    original = await loadInstalledBigQuerySource(profile, options);
    // Intentional author mistake: project the adapter into another object.
    // Its functions remain real, but copying shape must not copy registration.
    projection = Object.freeze({...original});
    return projection;
  });
  await assert.rejects(f.load(selected, {connectorTable}), error =>
    causedBy(error, 'InstalledSourceConstructorUnavailable'));
  assert.notEqual(original, projection);
  assert.equal(f.sources.length, 0);
  if (process.platform === 'linux') assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
  assert.equal(f.retire(), true);
  await f.close();
});

async function keyPairMaterialFaultInstaller({openCredentialJournal} = {}) {
  const {openSnowflakeKeyPairMaterial} = await import('../connectors/snowflake/site/snowflake-key-pair.mjs');
  const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
  let original, created = 0, probes = 0;
  const probeFailure = new Error('NoSecretMaterialProvidedByFixture');
  const connectorTable = faultyBigQuery(async (profile, options) => {
    const real = options.construction;
    const construction = Object.freeze({...real, openRowSite(input) {
      return real.openRowSite({...input, ...(openCredentialJournal ? {openCredentialJournal} : {}),
        prepareSecretMaterial() {
          created++;
          original = openSnowflakeKeyPairMaterial({accountIdentifier: 'fixture-account', user: 'operator',
            privateKeyEnvironment: 'UNUSED_BOUNDARY_PRIVATE_KEY'}, {maxSecretBytes: 4096,
            resolveMaterial() {probes++; throw probeFailure;}});
          return original;
        }});
    }});
    return loadInstalledBigQuerySource(profile, {...options, construction});
  });
  return {connectorTable, original: () => original, created: () => created,
    probes: () => probes, probeFailure};
}

test('pre-Site credential-key rejection closes the exact real lazy key-pair material', async t => {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.profile({missingKey: true});
  const material = await keyPairMaterialFaultInstaller();
  await assert.rejects(f.load(selected, material), error => causedBy(error, 'ENOENT'));
  assert.equal(material.created(), 1);
  assert.equal(material.probes(), 0);
  await assert.rejects(material.original().resolveSecret({}), {code: 'SnowflakeKeyPairMaterialClosed'});
  assert.equal(material.probes(), 0, 'closed observation never resolves a secret');
  assert.equal(f.retire(), true);
  await f.close();
});

test('real Site journal close refusal retains lazy key material until its own physical cleanup completes', async t => {
  const {openSqliteCredentialJournal} = await import('../site-node/sqlite-credential-journal.mjs');
  const f = await boundConstructionActualFixture(t);
  const selected = await f.profile();
  let available = false, attempts = 0, physicalCloses = 0, failure;
  const material = await keyPairMaterialFaultInstaller({openCredentialJournal(root, options) {
    const journal = openSqliteCredentialJournal(root, options);
    // Only the physical IO supplier is faulted; actual Site and material
    // ownership, cleanup status and retry are untouched.
    return Object.freeze({...journal, close() {
      attempts++;
      if (!available) throw new Error('ExplicitJournalCloseUnavailable');
      const result = journal.close();
      if (result === true) physicalCloses++;
      return result;
    }});
  }});
  const fault = f.failCurrentAfterJournal(selected);
  try {
    await assert.rejects(f.load(selected, material), error => {
      failure = error;
      return error.primaryFailure === fault.failure;
    });
    assert.equal(fault.calls, 1);
    assert.equal(material.created(), 1);
    assert.equal(material.probes(), 0);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(f.retire(), false);
    assert.equal(physicalCloses, 0);
    if (process.platform === 'linux') assert.ok(f.openJournalDescriptors(selected.journalPath).length > 0);
    // A live probe reaches only an explicitly refusing local supplier. No
    // secret bytes/token are fetched or generated. After close it cannot.
    await assert.rejects(material.original().resolveSecret({}), error => error === material.probeFailure);
    assert.equal(material.probes(), 1);
  } finally {
    available = true;
    if (failure) assert.equal((await failure.cleanupHandle.retry()).pending, false);
  }
  assert.equal(physicalCloses, 1);
  const completedAttempts = attempts;
  await assert.rejects(material.original().resolveSecret({}), {code: 'SnowflakeKeyPairMaterialClosed'});
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(attempts, completedAttempts);
  await assert.rejects(material.original().resolveSecret({}), {code: 'SnowflakeKeyPairMaterialClosed'});
  assert.equal(material.probes(), 1);
  if (process.platform === 'linux') assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
  assert.equal(f.retire(), true);
  await f.close();
});

function faultySalesforceEffect(load) {
  const original = installedConnectors.find(entry => entry.registration === 'salesforce');
  return createInstalledConnectorTable([{...original, effect: {...original.effect,
    async load() {return {...await original.effect.load(), load};}}}]);
}

for (const fault of ['copied', 'foreign', 'substituted-close']) {
  test(`Salesforce Effect refuses a ${fault} alias and cleans only its own actual Site`, async t => {
    const {retainInstalledRowEffectAdapter} = await import('./installed-row-effect.mjs');
    const original = installedConnectors.find(entry => entry.registration === 'salesforce');
    const module = await original.effect.load();
    const f = await boundConstructionActualFixture(t);
    const first = await f.salesforceProfile('effect');
    let siblingOriginal;
    const capture = faultySalesforceEffect(async (...args) => {
      siblingOriginal = await module.load(...args);
      return siblingOriginal;
    });
    const sibling = await f.load(first, {connectorTable: capture});
    const selected = await f.salesforceProfile('effect');
    let ownDescriptors, calls = 0, substitutedCloses = 0;
    const connectorTable = faultySalesforceEffect(async (...args) => {
      calls++;
      const actual = await module.load(...args);
      ownDescriptors = f.openJournalDescriptors(selected.journalPath);
      if (fault === 'foreign') return siblingOriginal;
      if (fault === 'copied') return Object.freeze({...actual});
      return retainInstalledRowEffectAdapter(actual, Object.freeze({...actual,
        close() {substitutedCloses++; throw new Error('SubstitutedCloseMustNotOwnCleanup');}}));
    });
    await assert.rejects(f.load(selected, {connectorTable}), error =>
      causedBy(error, 'InstalledSourceConstructorUnavailable'));
    assert.equal(calls, 1);
    assert.equal(substitutedCloses, 0, 'cleanup must use the retained raw owner, not the rejected alias');
    assert.equal(f.sources.length, 1);
    assert.equal(f.sources[0], sibling);
    if (process.platform === 'linux') {
      assert.ok(ownDescriptors.length > 0, 'fault occurs after actual acquisition');
      assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
      assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
    }
    assert.equal(f.secretReads(), 0);
    assert.equal(f.retire(), false);
    await f.close();
    assert.equal(f.retire(), true);
  });
}

test('specialized Salesforce Site physical cleanup refusal keeps its real parent pending until retry', async t => {
  const {openSqliteCredentialJournal} = await import('../site-node/sqlite-credential-journal.mjs');
  const original = installedConnectors.find(entry => entry.registration === 'salesforce');
  const module = await original.effect.load();
  const f = await boundConstructionActualFixture(t);
  const first = await f.profile();
  const sibling = await f.load(first);
  const selected = await f.salesforceProfile('effect');
  let available = false, attempts = 0, physicalCloses = 0, failure, originalAuthorization;
  const connectorTable = faultySalesforceEffect(async (profile, options) => {
    const real = options.construction;
    const construction = Object.freeze({...real, openSpecializedSite(input) {
      return real.openSpecializedSite({...input,
        async authorizationConstructor(...args) {
          originalAuthorization = await input.authorizationConstructor(...args);
          return originalAuthorization;
        }, siteOptions: {...input.siteOptions,
        openCredentialJournal(root, options) {
          const journal = openSqliteCredentialJournal(root, options);
          return Object.freeze({...journal, close() {
            attempts++;
            if (!available) throw new Error('ExplicitSpecializedJournalCloseUnavailable');
            const result = journal.close();
            if (result === true) physicalCloses++;
            return result;
          }});
        }}});
    }});
    return module.load(profile, {...options, construction});
  });
  // This is after the real specialized Site returns, not a fabricated
  // exception inside its otherwise synchronous constructor tail.
  const fault = f.failCurrentAfterJournal(selected);
  let cleanupHandle;
  try {
    await assert.rejects(f.load(selected, {connectorTable}), error => {
      failure = error;
      return error.primaryFailure === fault.failure;
    });
    assert.equal(fault.calls, 1);
    assert.equal(failure.cleanupHandle.status().pending, true);
    cleanupHandle = failure.cleanupHandle;
    assert.equal(f.retire(), false);
    assert.equal(physicalCloses, 0);
    assert.doesNotThrow(() => originalAuthorization.assertConfigurationCurrent(),
      'real authorization stays live while original physical custody is pending');
    assert.equal(f.sources[0], sibling);
    if (process.platform === 'linux') {
      assert.ok(f.openJournalDescriptors(selected.journalPath).length > 0);
      assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
    }
  } finally {
    available = true;
    if (cleanupHandle !== undefined) assert.equal((await cleanupHandle.retry()).pending, false);
  }
  assert.equal(physicalCloses, 1);
  assert.throws(() => originalAuthorization.assertConfigurationCurrent(),
    {code: 'AuthorizationDecisionScopeClosed'});
  const completedAttempts = attempts;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(attempts, completedAttempts);
  if (process.platform === 'linux') {
    assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
    assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
  }
  assert.equal(f.retire(), false, 'live sibling still owns the parent');
  await f.close();
  assert.equal(f.retire(), true);
});

test('bound Site construction captures mutable provider data before its first asynchronous boundary', async t => {
  const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
  const f = await boundConstructionActualFixture(t);
  const selected = await f.profile();
  let supplied, calls = 0;
  const connectorTable = faultyBigQuery(async (profile, options) => {
    const real = options.construction;
    const construction = Object.freeze({...real, openRowSite(input) {
      calls++;
      supplied = {...input.profile};
      const pending = real.openRowSite({...input, profile: supplied});
      assert.equal(Object.isFrozen(supplied), false, 'common capture must not freeze caller data');
      supplied.credentialPrivateKeyPath = `${f.root}/must-not-read-this-key`;
      supplied.journalRoot = `${f.root}/must-not-open-this-journal`;
      return pending;
    }});
    return loadInstalledBigQuerySource(profile, {...options, construction});
  });
  const source = await f.load(selected, {connectorTable});
  assert.equal(calls, 1);
  assert.equal(source.connectorRegistration, 'bigquery');
  if (process.platform === 'linux') {
    assert.ok(f.openJournalDescriptors(selected.journalPath).length > 0,
      'the actual Site used its captured original journal target');
    assert.deepEqual(f.openJournalDescriptors(`${supplied.journalRoot}/credential-journal.sqlite3`), []);
  }
  assert.equal(f.secretReads(), 0);
  await f.close();
  assert.equal(f.retire(), true);
});

for (const variant of ['accessor', 'proxy']) {
  test(`bound Site profile rejects ${variant} without invoking provider code or opening a journal`, async t => {
    const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
    const f = await boundConstructionActualFixture(t);
    const selected = await f.profile();
    let calls = 0;
    const connectorTable = faultyBigQuery(async (profile, options) => {
      const real = options.construction;
      const construction = Object.freeze({...real, openRowSite(input) {
        const supplied = {...input.profile};
        const invalid = variant === 'proxy' ? new Proxy(supplied, {
          ownKeys() {calls++; throw new Error('ProxyMustNotBeObserved');},
          getOwnPropertyDescriptor() {calls++; throw new Error('ProxyMustNotBeObserved');},
          get() {calls++; throw new Error('ProxyMustNotBeObserved');},
        }) : Object.defineProperty(supplied, 'credentialPrivateKeyPath', {enumerable: true,
          get() {calls++; throw new Error('AccessorMustNotBeObserved');}});
        return real.openRowSite({...input, profile: invalid});
      }});
      return loadInstalledBigQuerySource(profile, {...options, construction});
    });
    await assert.rejects(f.load(selected, {connectorTable}), error => causedBy(error, 'InvalidInstalledSourceConstruction'));
    assert.equal(calls, 0);
    assert.equal(f.sources.length, 0);
    if (process.platform === 'linux') assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
    assert.equal(f.secretReads(), 0);
    await f.close();
    assert.equal(f.retire(), true);
  });
}

test('an admitted pure Environment throw retains its failure through sibling reconciliation without a fake pending child', async t => {
  const {checked} = await import('../host-common/runtime-result.mjs');
  const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
  const f = await boundConstructionActualFixture(t);
  const first = await f.profile();
  const sibling = await f.load(first);
  const selected = await f.profile();
  let projects = 0, error;
  const connectorTable = faultyBigQuery(async (profile, options) => {
    const real = options.construction;
    const construction = Object.freeze({...real, createRowSource(input) {
      real.prepareReadTargetWithMappings(Object.freeze({
        capacity() {return checked(options.moon.clientProgramInstalledSourceConstructionCapacity(
          64n, 64n, 4096n, 64n, 64n, 64n));},
        project() {
          projects++;
          // Malformed provider DATA reaches the actual Environment parser;
          // no runtime value, constructor or cleanup method is substituted.
          return Object.freeze({mappingWires: Object.freeze(['{'])});
        },
      }));
      return real.createRowSource(input);
    }});
    return loadInstalledBigQuerySource(profile, {...options, construction});
  });
  await assert.rejects(f.load(selected, {connectorTable}), failure => {
    error = failure;
    const pending = [failure], seen = new Set();
    while (pending.length) {
      const value = pending.shift();
      if (!value || typeof value !== 'object' || seen.has(value)) continue;
      seen.add(value);
      if (value instanceof SyntaxError && /rowSourceCheckEnvironment|byCid/.test(value.stack)) return true;
      pending.push(value.cause, value.primaryFailure);
    }
    return false;
  });
  assert.equal(projects, 1, 'the actual provider reserve admitted before its pure projection');
  assert.equal(f.sources[0], sibling);
  if (process.platform === 'linux') {
    assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
    assert.ok(f.openJournalDescriptors(first.journalPath).length > 0);
  }
  assert.notEqual(error.cleanupHandle?.status().pending, true,
    'a completed pure failure is retained debt, not an invented physical child');
  // A new real sibling forces the same material to reconcile again.
  const later = await f.load(await f.profile());
  assert.notEqual(later, sibling);
  assert.equal(f.retire(), false);
  await f.close();
  assert.equal(f.retire(), true);
});

test('pure Environment failure debt survives sibling reconciliation and changes actual admission', async t => {
  const {readFile} = await import('node:fs/promises');
  const {checked} = await import('../host-common/runtime-result.mjs');
  const {runtimeField} = await import('../host-common/compiler-binding.generated.mjs');
  const {sourceEnvironmentConstructionGeometry, sourceEnvironmentRetainedGeometry} =
    await import('./installed-source-construction-geometry.mjs');
  const {rowSourceCheckEnvironment} = await import('./installed-row-source.mjs');
  const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
  const base = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
  let derivedDelta, probeQuantity, probeBytes;
  const contains = (error, expected) => {
    const pending = [error], seen = new Set();
    while (pending.length) {
      const value = pending.shift();
      if (value === expected) return true;
      if (!value || typeof value !== 'object' || seen.has(value)) continue;
      seen.add(value); pending.push(value.cause, value.primaryFailure);
    }
    return false;
  };
  async function probe(failed) {
    const f = await boundConstructionActualFixture(t);
    const nativeQuote = (n, text, wire) => checked(f.moon.clientProgramInstalledSourceConstructionCapacity(n, text, wire, 0n, 0n, 0n));
    const bytes = value => runtimeField(f.moon.clientProgramSerializationCapacityBytes(
      checked(f.moon.clientProgramComposeInstalledSourceConstructionCapacity(nativeQuote(0n, 0n, 0n), [value]))), 1);
    const phaseDone = new Error('PurePhaseSucceededBeforeDeliberateInstallerFailure');
    let declared, projects = 0;
    const selected = await f.profile();
    const connectorTable = faultyBigQuery(async (profile, options) => {
      const real = options.construction;
      const construction = Object.freeze({...real,
        prepareNativeDeclaration(input) {
          const result = real.prepareNativeDeclaration(input);
          declared = result.declared;
          return result;
        },
        createRowSource() {
          real.prepareReadTargetWithMappings(Object.freeze({
            capacity() {return nativeQuote(64n, 64n, 4096n);},
            project() {projects++; return Object.freeze({mappingWires: Object.freeze([failed ? '{ ' : '{}'])});},
          }));
          throw phaseDone;
        },
      });
      return loadInstalledBigQuerySource(profile, {...options, construction});
    });
    let phaseFailure;
    await assert.rejects(f.load(selected, {connectorTable}), error => {
      phaseFailure = error;
      return failed ? !contains(error, phaseDone) : contains(error, phaseDone);
    });
    assert.equal(projects, 1);
    if (failed) {
      const chain = [phaseFailure]; let parsed = false;
      while (chain.length) {const e = chain.shift(); if (!e) continue;
        if (e instanceof SyntaxError) parsed = true; chain.push(e.cause, e.primaryFailure);}
      assert.equal(parsed, true);
    }
    const full = sourceEnvironmentConstructionGeometry(base, declared, ['{ ']);
    const retained = sourceEnvironmentRetainedGeometry(rowSourceCheckEnvironment(base, declared, ['{}']));
    const delta = bytes(nativeQuote(full.workspace.nodes + full.retained.nodes,
      full.workspace.text + full.retained.text, full.workspace.wire + full.retained.wire)) -
      bytes(nativeQuote(retained.nodes, retained.text, retained.wire));
    if (derivedDelta === undefined) derivedDelta = delta;
    else assert.equal(delta, derivedDelta, 'matched actual declaration recipes');
    assert.ok(delta > 0n);
    // Reconcile after failure on the same original parent with a real sibling.
    await f.load(await f.profile());
    // A bounded diagnostic established a success threshold of
    // [408 MiB, 410 MiB] for this matched fixture under the unchanged normal
    // parent. Choose half the derived debt below its admitted lower bound,
    // not a new runtime limit or a permanent capacity-search loop.
    probeBytes ??= 408n * 1024n * 1024n - derivedDelta / 2n;
    assert.ok(probeBytes > 0n);
    probeQuantity ??= nativeQuote(0n, 0n, probeBytes);
    const probeDone = new Error('ActualProbeAdmitted');
    let entered = 0;
    const probeTable = faultyBigQuery(async (_profile, {construction}) => {
      construction.prepareNativeDeclaration(Object.freeze({
        capacity() {return probeQuantity;},
        project() {entered++; throw probeDone;},
      }));
    });
    let observed;
    await assert.rejects(f.load(await f.profile(), {connectorTable: probeTable}), error => {
      observed = error; return contains(error, probeDone) || causedBy(error, 'MoonBitHostFailure');
    });
    assert.equal(entered, contains(observed, probeDone) ? 1 : 0);
    await f.close();
    assert.equal(f.retire(), true, 'pure failures do not fabricate pending physical work');
    return entered === 1;
  }
  assert.equal(await probe(false), true);
  assert.equal(await probe(true), false);
  t.diagnostic(JSON.stringify({pureEnvironmentDebtBytes: String(derivedDelta),
    sameNativeProbeBytes: String(probeBytes)}));
});

test('refused pure Environment workspace does not become ungranted debt on sibling reconciliation', async t => {
  const {checked} = await import('../host-common/runtime-result.mjs');
  const {loadInstalledBigQuerySource} = await import('../connectors/bigquery/host/installed-bigquery-source.mjs');
  const f = await boundConstructionActualFixture(t);
  const selected = await f.profile();
  // Explicit bounded external fixture DATA, not an allocation performed by
  // an unfunded product callback. Its native backing is acquired below.
  const wire = '{' + ' '.repeat(4 * 1024 * 1024 - 1);
  let projects = 0, failure;
  const connectorTable = faultyBigQuery(async (profile, options) => {
    const real = options.construction;
    const construction = Object.freeze({...real, createRowSource(input) {
      real.prepareReadTargetWithMappings(Object.freeze({
        capacity() {return checked(options.moon.clientProgramInstalledSourceConstructionCapacity(
          64n, 2n * BigInt(wire.length), BigInt(wire.length), 64n, 64n, 64n));},
        project() {projects++; return Object.freeze({mappingWires: Object.freeze([wire])});},
      }));
      return real.createRowSource(input);
    }});
    return loadInstalledBigQuerySource(profile, {...options, construction});
  });
  await assert.rejects(f.load(selected, {connectorTable}), error => {
    failure = error;
    return causedBy(error, 'MoonBitHostFailure');
  });
  assert.equal(projects, 1, 'provider input backing admitted; Environment reserve is the refused phase');
  let reserve = false, syntax = false;
  const pending = [failure], seen = new Set();
  while (pending.length) {
    const value = pending.shift();
    if (!value || typeof value !== 'object' || seen.has(value)) continue;
    seen.add(value);
    if (value.code === 'MoonBitHostFailure' && /prepareSourceEnvironment/.test(value.stack)) reserve = true;
    if (value instanceof SyntaxError) syntax = true;
    pending.push(value.cause, value.primaryFailure);
  }
  assert.equal(reserve, true);
  assert.equal(syntax, false, 'the actual Environment parser did not run on malformed DATA');
  if (process.platform === 'linux') assert.deepEqual(f.openJournalDescriptors(selected.journalPath), []);
  // The refused Environment demand exceeds the normal parent. Incorrectly
  // adding it as debt would make this genuine later reconciliation fail too.
  const sibling = await f.load(await f.profile());
  assert.equal(sibling.connectorRegistration, 'bigquery');
  await f.close();
  assert.equal(f.retire(), true);
});

// Same real Host constructor/parent as the existing bound-owner cases. Only
// provider metadata and loopback Site DATA are authored here; no new owner.
async function registeredBigQueryRefusalFixture(t) {
  const f = await boundConstructionActualFixture(t);
  const selected = await f.profile();
  const api = await openHttpsExchangeFixture(t);
  const site = JSON.parse(await readFile(selected.value.siteProfilePath, 'utf8'));
  const metadata = JSON.parse(await readFile(selected.value.metadataPath, 'utf8'));
  site.apiOrigin = api.origin;
  site.caPath = api.caPath;
  metadata.apiOrigin = api.origin;
  await writeFile(selected.value.siteProfilePath, JSON.stringify(site));
  await writeFile(selected.value.metadataPath, JSON.stringify(metadata));
  return {f, selected, api, metadata};
}

test('registered BigQuery malformed binary input keeps original refusal and initial cleanup', async t => {
  const {f, selected, api, metadata} = await registeredBigQueryRefusalFixture(t);
  await writeFile(selected.value.metadataPath, JSON.stringify({...metadata, body: metadata.body + '\n'}));
  await assert.rejects(f.load(selected), cause => {
    assert.equal(cause.primaryFailure?.code, 'InvalidInstalledBigQueryMetadata');
    assert.equal(cause.cleanupPending, false);
    assert.deepEqual(cause.cleanupErrors, []);
    return true;
  });
  assert.equal(f.secretReads(), 0);
  assert.deepEqual(api.seen(), []);
  assert.equal(f.sources.length, 0);
  await f.close();
  assert.equal(f.retire(), true);
  assert.equal(observeOwnScopedStateFds([f.root]).scopedStateFd0, true);
});

test('registered BigQuery native schema refusal retires the same initial material before Site', async t => {
  const {f, selected, api, metadata} = await registeredBigQueryRefusalFixture(t);
  await writeFile(selected.value.metadataPath, JSON.stringify({...metadata,
    body: Buffer.from('{}').toString('base64')}));
  const {moon} = f, {limits} = selected.value;
  const nativeLimits = moon.clientProgramBigQueryDescriptionLimits(limits.maxBytes,
    limits.maxNodes, limits.maxDepth, limits.maxFields, limits.maxNameBytes, limits.maxSchemaBytes);
  const expected = moon.clientProgramBigQueryDescribeTable(selected.value.project,
    selected.value.dataset, selected.value.table, Buffer.from('{}'), nativeLimits);
  assert.equal(expected.$tag, 0);
  // Same original typed refusal, without replacing the Core constructor.
  await assert.rejects(f.load(selected), cause => {
    assert.deepEqual(cause.primaryFailure?.cause, expected._0);
    assert.equal(cause.cleanupPending, false);
    assert.deepEqual(cause.cleanupErrors, []);
    return true;
  });
  assert.equal(f.secretReads(), 0);
  assert.deepEqual(api.seen(), []);
  assert.equal(f.sources.length, 0);
  await f.close();
  assert.equal(f.retire(), true);
  assert.equal(observeOwnScopedStateFds([f.root]).scopedStateFd0, true);
});
