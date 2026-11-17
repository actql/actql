// Actual imported Host assembly with explicit construction ports. These
// component cases issue no Common parent, read grant or physical stop ACK.
import assert from 'node:assert/strict';
import test from 'node:test';
import {installFinitePageSource} from '../../../host-node/installed-finite-page-source.mjs';

function fixture({capacityFailure, publicationFailure, foreignCapacity, retire = () => true, openingFailure} = {}) {
  const events = [], capacity = {}, installation = {}, sourceInitialization = {};
  const implementation = {capacity, runAcquisitionLimits: {original: 'acquisition'}};
  const authorization = {}, source = {}, siteOptions = {profile: {}, resolveSecret() {
    assert.fail('No secret is resolved during constructor-only assembly');
  }};
  const site = {async close() {assert.equal(this, site);events.push('site.close');}};
  Object.assign(siteOptions, {installation, sourceInitialization,
    runAcquisitionLimits: implementation.runAcquisitionLimits});
  const reader = {get capacity() {
    events.push('reader.capacity');if (capacityFailure) throw capacityFailure;return foreignCapacity ?? capacity;
  }, retire() {assert.equal(this, reader);events.push('reader.retire');return retire();}};
  const preparePageReader = (...args) => {events.push('page');return args;};
  const input = {services(name, selected) {
    assert.equal(selected.installation, installation);
    assert.equal(selected.sourceInitialization, sourceInitialization);
    if (name === 'openRowSite') {
      events.push('site');assert.equal(selected.profile, siteOptions.profile);
      assert.equal(selected.runAcquisitionLimits, implementation.runAcquisitionLimits);
      if (openingFailure) throw openingFailure;
      return {site, authorization};
    }
    assert.equal(name, 'createSourceReader');events.push('reader');
    assert.equal(selected.implementation, implementation);assert.equal(selected.site, site);
    assert.equal(selected.preparePageReader, preparePageReader);
    assert.equal(selected.operation, 'notion:users:list');
    return reader;
  }, installation, sourceInitialization, implementation, siteOptions,
  operation: 'notion:users:list', preparePageReader,
  implementationMismatch: 'InstalledNotionReaderImplementationMismatch',
  publish(opened, originalReader) {
    events.push('publish');assert.equal(opened.site, site);assert.equal(opened.authorization, authorization);
    assert.equal(originalReader, reader);if (publicationFailure) throw publicationFailure;return source;
  }};
  const run = () => installFinitePageSource(input.services, siteOptions, implementation,
    input.operation, preparePageReader, input.implementationMismatch, input.publish);
  return {events, input, source, site, reader, preparePageReader, run};
}

test('finite provider-page assembly retains the same Host originals and pure page port', async () => {
  const f = fixture();
  assert.equal(await f.run(), f.source);
  assert.deepEqual(f.events, ['site', 'reader', 'reader.capacity', 'publish']);
  // The factory transfers this one reader; it does not retire a returned Source.
  const request = {resource: 'users', columns: ['id']}, projection = () => {};
  assert.deepEqual(f.preparePageReader(request, projection), [request, projection]);
});

test('finite provider-page capacity getter failure retains reader before Site cleanup', async () => {
  const original = new Error('original capacity getter');let ready = false, failure;
  const f = fixture({capacityFailure: original, retire: () => ready});
  await assert.rejects(f.run(), cause => {
    failure = cause;return cause.primaryFailure === original;
  });
  assert.deepEqual(f.events, ['site', 'reader', 'reader.capacity', 'reader.retire']);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert(failure.cleanupHandle.status().owners.includes('source-reader'));
  // An unfinished original retirement cannot close the dependent Site.
  ready = true;await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.deepEqual(f.events.slice(-2), ['reader.retire', 'site.close']);
});

test('finite provider-page publication refusal keeps its original cause and never republishes', async () => {
  const original = new Error('original declaration/current refusal');
  const f = fixture({publicationFailure: original});let failure;
  await assert.rejects(f.run(), cause => {
    failure = cause;return cause.primaryFailure === original;
  });
  assert.deepEqual(f.events, ['site', 'reader', 'reader.capacity', 'publish', 'reader.retire', 'site.close']);
  assert.equal(failure.cleanupHandle.status().pending, false);
  await failure.cleanupHandle.retry();assert.equal(f.events.filter(value => value === 'publish').length, 1);
});

test('finite provider-page opening failure retains its original partial child without creating a reader', async () => {
  let stopped = false, retries = 0;
  const original = Object.assign(new Error('original Site partial child'), {cleanupPending: true,
    cleanupHandle: {status: () => ({pending: !stopped}), async retry() {retries++;}}});
  const f = fixture({openingFailure: original});let failure;
  await assert.rejects(f.run(), cause => {
    failure = cause;return cause.primaryFailure === original;
  });
  assert.deepEqual(f.events, ['site']);assert.equal(failure.cleanupHandle.status().pending, true);
  stopped = true;await failure.cleanupHandle.retry();assert.equal(retries, 2);
  assert.equal(failure.cleanupHandle.status().pending, false);assert.deepEqual(f.events, ['site']);
});

// Direct loader selection controls stop at an explicit constructor refusal.
// They do not replace createInstalledRowSource or issue a nominal Core value.
async function loaderFixture({changeAfterRead = false, implementationFailure} = {}) {
  const {loadInstalledNotionSource} = await import('../host/installed-notion-source.mjs');
  const events = [], sentinel = new Error('original reader constructor refusal');
  const limits = {maxResponseBytes: 8192, maxTotalResponseBytes: 24576, maxNodes: 512,
    maxDepth: 16, maxRows: 2, maxTotalRows: 3, maxPages: 4, pageSize: 2, maxCursorBytes: 128,
    maxIdentityBytes: 128, maxTargetBytes: 1024, maxValueNodes: 100, maxValueTextBytes: 4096,
    maxRowsWireBytes: 8192, maxRowsWireNodes: 200, maxRowsWireDepth: 8,
    maxDeclarationBytes: 4096, maxDeclarationNodes: 1000, maxSecretBytes: 128, maxCaBytes: 16384};
  const profile = {version: 'actql-installed-notion-source/0.1', connectorId: 'workspace',
    siteProfilePath: '/UNOPENED/notion-site.json', accountConfigurationWire: '{}', limits};
  const siteProfile = {version: 'actql-installed-notion-site/0.1', apiOrigin: 'https://notion.invalid',
    credentialAuthorityId: 'authority', credentialKeyId: 'key', credentialPrivateKeyPath: '/UNOPENED/key',
    environment: 'test', journalRoot: '/UNOPENED/journal', namespaceId: 'original', siteGeneration: 1, siteKey: 'notion'};
  const sourceInitialization = {prepareDeclaration(views) {
    assert.equal(this, sourceInitialization);events.push('declaration');
    assert.equal(views[0].resource, 'users');assert.equal(views[0].resource_kind, 'notion_users');
    return {declaration: {}, declared: {views: [{fields: ['id', 'name']}]}, environment: {wire: 'original'}};
  }};
  const provider = {
    notionUserListSchemaWire() {assert.equal(this, provider);events.push('schema');return {$tag: 1, _0: 'schema'};},
    notionUserListRelationFactsWire() {assert.equal(this, provider);return 'facts';},
    notionUserListColumnNames() {assert.equal(this, provider);return ['id', 'name'];},
    notionUserListRowsWire() {assert.fail('No page in constructor scope');},
    notionUserListMetadataJson() {assert.fail('No page');}, notionUserListIds() {assert.fail('No page');},
    notionProjectUserList() {assert.fail('No page');},
  };
  const site = {async close() {assert.equal(this, site);events.push('site.close');}};
  let readerInput, implementationInput;
  const services = {
    sourceReaderImplementationProfile() {assert.equal(this, services);events.push('policy');return limits;},
    sourceReaderImplementation(input) {
      assert.equal(this, services);events.push('implementation');implementationInput = input;
      if (implementationFailure) throw implementationFailure;
      return {capacity: {}, runAcquisitionLimits: {original: 'limits'}};
    },
    async openRowSite(input) {
      assert.equal(this, services);events.push('site');assert.equal(input.connection, 'notion:workspace');
      assert.equal(input.profile.resourceOrigin, siteProfile.apiOrigin);return {site, authorization: {}};
    },
    createSourceReader(input) {assert.equal(this, services);readerInput = input;events.push('reader');throw sentinel;},
  };
  const configurationReader = {async readJson(path) {
    assert.equal(path, profile.siteProfilePath);events.push('configuration');
    if (changeAfterRead) {
      for (const key of Object.keys(services)) services[key] = () => assert.fail('Replaced service');
      for (const key of Object.keys(provider)) provider[key] = () => assert.fail('Replaced provider');
      sourceInitialization.prepareDeclaration = () => assert.fail('Replaced Source constructor');
    }
    return siteProfile;
  }, readText() {assert.fail('No CA selected');}};
  const options = {moon: {}, installation: {}, sourceInitialization, installationServices: services,
    providerMoon: provider, configurationReader, resolveSecret() {assert.fail('No credential resolution');}};
  return {events, options, sentinel, get readerInput() {return readerInput;},
    get implementationInput() {return implementationInput;}, load: overrides =>
      loadInstalledNotionSource(profile, {...options, ...overrides})};
}

test('Notion constructor captures original services and provider before configuration await', async () => {
  const f = await loaderFixture({changeAfterRead: true});
  await assert.rejects(f.load(), cause => cause.primaryFailure === f.sentinel);
  assert.deepEqual(f.events, ['configuration', 'policy', 'implementation', 'schema', 'declaration', 'site', 'reader', 'site.close']);
  assert.equal(f.readerInput.operation, 'notion:users:list');
  assert.throws(() => f.readerInput.preparePageReader({resource: 'foreign', columns: []}, () => {}),
    {code: 'UndeclaredNotionResource'});
  // This existing full-envelope plugin keeps the legacy JSON representation;
  // the row-only REST cursor mode is not selected by a Program or this adapter.
  assert.equal(f.implementationInput.cursorProgress, undefined);
});

test('Notion constructor refuses unavailable original methods before configuration', async () => {
  const f = await loaderFixture();
  await assert.rejects(f.load({sourceInitialization: undefined}), {code: 'NotionSourceInitializationUnavailable'});
  const services = {...f.options.installationServices};
  Object.defineProperty(services, 'openRowSite', {get() {assert.fail('No service accessor');}});
  await assert.rejects(f.load({installationServices: services}), {code: 'InstalledNotionSourceServicesUnavailable'});
  assert.deepEqual(f.events, []);
});

test('Notion constructor keeps the original implementation refusal before any Site or reader', async () => {
  const original = Object.assign(new Error('OriginalImplementationPending'), {cleanupPending: true});
  const f = await loaderFixture({implementationFailure: original});
  await assert.rejects(f.load(), cause => cause === original);
  assert.deepEqual(f.events, ['configuration', 'policy', 'implementation']);
});

test('finite provider-page foreign capacity refuses publication and retires only the returned reader', async () => {
  const f = fixture({foreignCapacity: {}});let failure;
  await assert.rejects(f.run(), cause => {
    failure = cause;return cause.primaryFailure?.code === 'InstalledNotionReaderImplementationMismatch';
  });
  assert.deepEqual(f.events, ['site', 'reader', 'reader.capacity', 'reader.retire', 'site.close']);
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(f.events.includes('publish'), false);
});
