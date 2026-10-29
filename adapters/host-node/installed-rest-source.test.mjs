import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {createInstalledRestSource} from './installed-rest-source.mjs';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {REST_SOURCE_SITE_VERSION} from './rest-source-metadata.mjs';

// Compose the actual facade, service-method capture, ManagedReader factory
// and installed row adapter. Common declaration/policy and Site creation are
// explicit ports: this is not normal Account, capacity or SDK/Host evidence.
async function fixture() {
  const events = [], capacity = Object.freeze({}), installation = Object.freeze({});
  const sources = ['customers', 'events'].map(resource => ({resource, resource_kind: 'record',
    fields: [{name: 'id', type: 'string', nullable: false}], read: {method: 'GET', path: `/${resource}`},
    pagination: {kind: 'none', items: []}, limits: {maxPageRows: 2, maxPageBytes: 1024,
      maxPages: 2, maxRows: 4, maxNodes: 64, maxDepth: 8, maxCursorBytes: 32}}));
  const definition = {registration: 'acme', revision: 'acme/0.1',
    profileVersion: 'actql-installed-acme-rest-source/0.1', origin: 'https://api.acme.invalid',
    auth: {kind: 'bearer'}, sources};
  const declared = {catalog_cid: 'fixture-issued-catalog', catalog: '{"fixture":"catalog"}',
    manifest_entry: '{"fixture":"manifest"}', contracts: ['{"fixture":"contract"}'],
    evidence_schemas: ['{"fixture":"schema-one"}', '{"fixture":"schema-two"}'],
    evidence_capabilities: ['{"fixture":"capability-one"}', '{"fixture":"capability-two"}'],
    view_bodies: ['{"fixture":"view-one"}', '{"fixture":"view-two"}'],
    views: sources.map(source => ({resource: source.resource, fields: ['id'],
      source_ref: `fixture-issued-source:${source.resource}`}))};
  const declaration = Object.freeze({});
  const moon = {
    clientProgramRowSourceRestoreDeclaration(...args) {
      assert.strictEqual(this, moon);assert.equal(args[0], 'acme-one');
      assert.deepEqual(args.slice(1, 3), ['acme', 'acme/0.1']);
      assert.deepEqual(JSON.parse(args[3]), {views: sources.map(({resource, resource_kind, fields}) =>
        ({resource, resource_kind, fields}))});
      events.push('declaration');return {$tag: 1, _0: declaration};
    },
    clientProgramRowSourceDeclarationJson(value) {
      assert.strictEqual(this, moon);assert.strictEqual(value, declaration);return JSON.stringify(declared);
    },
  };
  for (const name of ['clientProgramRowSourceProjectJsonPage', 'clientProgramRowSourceJsonPageRowsWire',
    'clientProgramRowSourceJsonPageRowCount', 'clientProgramRowSourceJsonPageHasNextCursor',
    'clientProgramRowSourceJsonPageNextCursor', 'clientProgramInstalledProviderRowCaptureCapacity',
    'clientProgramInstalledProviderRowCaptureCapacityMatches', 'clientProgramRowSourceStartProviderAccounted',
    'clientProgramRowSourceBorrowResponses', 'clientProgramRowSourceBindResponseCleanup']) {
    moon[name] = () => assert.fail('No parse, Run, page or capacity operation in this component');
  }
  const policy = Object.freeze({maxRows: 2, maxResponseBytes: 1024, maxPages: 2, maxTotalRows: 4,
    maxNodes: 64, maxDepth: 8, maxCursorBytes: 32, maxSecretBytes: 64});
  const acquisitionLimits = Object.freeze({maxBindings: 2, maxSecretBytes: 64});
  const implementation = Object.freeze({capacity, limits: policy, runAcquisitionLimits: acquisitionLimits});
  const authorization = {accountConfiguration: '{}', context: {contextCid: 'fixture-context'}};
  const site = {connection: 'acme:acme-one', credential: {},
    callResource() {assert.fail('No provider send');}, referenceCurrent() {return true;},
    close() {assert.strictEqual(this, site);events.push('site-close');}};
  let selection, providerReader;
  const services = {
    sourceReaderImplementationProfile(options) {
      assert.strictEqual(this, services);assert.strictEqual(options.installation, installation);
      assert.deepEqual(Object.keys(options).sort(), ['installation', 'metadataResponses', 'originUnits']);
      assert.equal(options.metadataResponses, 0);assert.equal(options.originUnits, definition.origin.length);
      events.push('policy');return policy;
    },
    sourceReaderImplementation(options) {
      assert.strictEqual(this, services);assert.strictEqual(options.installation, installation);
      assert.strictEqual(options.limits, policy);assert.equal(options.columnCount, 1);
      events.push('implementation');return implementation;
    },
    openRowSite(options) {
      assert.strictEqual(this, services);assert.strictEqual(options.installation, installation);
      assert.strictEqual(options.runAcquisitionLimits, acquisitionLimits);
      assert.equal(options.profile.resourceOrigin, definition.origin);assert.equal(Object.isFrozen(options.profile), true);
      events.push('site-open');return {site, authorization};
    },
    createSourceReader(options) {
      assert.strictEqual(this, services);assert.strictEqual(options.installation, installation);
      assert.strictEqual(options.implementation, implementation);assert.strictEqual(options.site, site);
      assert.deepEqual(Object.keys(options).sort(), ['implementation', 'installation', 'operation', 'preparePageReader', 'site']);
      selection = options;events.push('reader');
      providerReader = createInstalledCredentialSourceReader({capacity, site,
        operation: options.operation, maxResponses: policy.maxPages, maxResponseBytes: policy.maxResponseBytes,
        maxSecretBytes: policy.maxSecretBytes, preparePageReader: options.preparePageReader});
      return providerReader;
    },
  };
  const profile = {version: definition.profileVersion, connectorId: 'acme-one',
    siteProfilePath: '/UNOPENED/rest-site.json', accountConfigurationWire: '{}'};
  const options = {moon, installation, installationServices: services,
    baseEnvironmentWire: await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'),
    runtimeBundleCid: 'sha256:' + 'a'.repeat(64), resolveSecret() {assert.fail('No credential resolution');},
    configurationReader: {readJson() {return {version: REST_SOURCE_SITE_VERSION,
      apiOrigin: definition.origin, credentialAuthorityId: 'authority', credentialKeyId: 'key',
      credentialPrivateKeyPath: '/UNOPENED/key.pem', journalRoot: '/UNOPENED/journal',
      namespaceId: 'namespace', environment: 'fixture', siteGeneration: 0, siteKey: 'site'};},
    readText() {assert.fail('No optional CA operation');}}};
  return {definition, profile, options, moon, services, events, site,
    selection: () => selection, reader: () => providerReader};
}

test('REST facade uses one original managed factory for multiple pure resource adapters', async () => {
  const f = await fixture(), facade = createInstalledRestSource(f.definition);
  const adapter = await facade.load(f.profile, f.options);
  assert.deepEqual(f.events, ['declaration', 'policy', 'implementation', 'site-open', 'reader']);
  assert.equal(adapter.connectorRegistration, 'acme');assert.equal(adapter.realizationKey, 'row-source-acquired');
  for (const resource of ['customers', 'events']) {
    const pages = f.selection().preparePageReader({resource, columns: ['id'], requestWire: 'fixture-original'},
      () => assert.fail('No optional author callback'));
    assert.deepEqual(pages.fetchPage({pageIndex: 0, rowCount: 0}), {method: 'GET', path: `/${resource}`,
      query: [], headers: [['accept', 'application/json']], responseHeaders: []});
  }
  assert.throws(() => f.selection().preparePageReader({resource: 'foreign'}), {code: 'RestSourceReadTargetMismatch'});
  adapter.close();
  assert.equal(f.events.filter(value => value === 'site-close').length, 1);
  assert.equal(f.reader().retire(), true);
  assert.throws(() => f.reader().prepare({}), {code: 'InstalledSourceReaderFactoryClosed'});
});

test('REST facade refuses uncovered author bounds and original Common failure before opening a Site', async () => {
  const f = await fixture(); f.definition.sources[0].limits.maxRows = 5;
  await assert.rejects(createInstalledRestSource(f.definition).load(f.profile, f.options),
    {code: 'RestSourceImplementationBoundsExceeded'});
  assert.deepEqual(f.events, ['declaration', 'policy']);
  const g = await fixture(), issue = Object.freeze({kind: 'UnsupportedType'});
  g.moon.clientProgramRowSourceRestoreDeclaration = () => ({$tag: 0, _0: issue});
  await assert.rejects(createInstalledRestSource(g.definition).load(g.profile, g.options), cause =>
    cause.code === 'MoonBitHostFailure' && cause.cause === issue);
  assert.deepEqual(g.events, []);
});

test('REST facade retains the original after-Site construction failure through shared cleanup', async () => {
  const f = await fixture();delete f.moon.clientProgramRowSourceProjectJsonPage;
  await assert.rejects(createInstalledRestSource(f.definition).load(f.profile, f.options), cause => {
    assert.equal(cause.code, 'InstalledHostInitializationFailed');
    assert.equal(cause.primaryFailure.code, 'RestSourcePageProjectionUnavailable');
    return true;
  });
  assert.deepEqual(f.events, ['declaration', 'policy', 'implementation', 'site-open', 'site-close']);
});

test('REST initialization failure must retire its original managed factory before releasing the Site', async t => {
  const f = await fixture();delete f.moon.clientProgramRowSourceStartProviderAccounted;
  t.after(() => f.reader()?.retire());
  let primary;
  try {await createInstalledRestSource(f.definition).load(f.profile, f.options);}
  catch (cause) {primary = cause;}
  assert.equal(primary?.primaryFailure?.code, 'InstalledProviderSourceUnavailable');
  assert.equal(f.events.includes('reader'), true);
  t.diagnostic(JSON.stringify({events: f.events, primary: primary.code,
    originalCause: primary.primaryFailure.code}));
  assert.throws(() => f.reader().prepare({}), {code: 'InstalledSourceReaderFactoryClosed'},
    'The failed initializer must not leave the same factory holding its already-released Site');
});
