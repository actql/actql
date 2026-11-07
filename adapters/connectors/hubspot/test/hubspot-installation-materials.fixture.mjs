// Actual provider decoders with explicit parent construction ports. These
// cases establish shared material/ordering, not whole-initialization funding.
import assert from 'node:assert/strict';
import test from 'node:test';
import {loadInstalledHubSpotSource, prepareInstalledHubSpotMaterials} from '../host/installed-hubspot-source.mjs';

function fixture(native) {
  const site = {version: 'actql-installed-hubspot-site/0.1', apiOrigin: 'https://api.hubapi.com',
    credentialAuthorityId: 'fixture', credentialKeyId: 'key', credentialPrivateKeyPath: '/unused/key',
    environment: 'fixture', journalRoot: '/unused/journal', namespaceId: 'fixture',
    siteGeneration: 1, siteKey: 'fixture', tokenEnvironment: 'ACTQL_HUBSPOT_FIXTURE'};
  const limits = {maxResponseBytes: 8192, maxNodes: 2000, maxDepth: 24, maxProperties: 20,
    maxNameUnits: 256, maxPages: 2, maxRows: 10, maxRequests: 8, perPage: 2, maxColumns: 10,
    maxCursorUnits: 256, maxValueNodes: 2000, maxValueTextBytes: 8192,
    maxRowsWireBytes: 8192, maxRowsWireNodes: 2000, maxRowsWireDepth: 24,
    maxObjects: 2, maxDeclarationBytes: 8192, maxDeclarationNodes: 2000, maxSecretBytes: 128};
  const profile = {version: 'actql-installed-hubspot-source/0.1', connectorId: 'fixture', portalId: '7',
    resources: [{resource: 'companies', objectType: 'companies'}, {resource: 'contacts', objectType: 'contacts'}],
    metadataPath: '/unused/metadata.json', siteProfilePath: '/unused/site.json',
    metadataResources: {account: 'account', properties: 'properties'}, accountConfigurationWire: '{}', limits};
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64');
  const properties = {results: [
    {name: 'amount', type: 'number', fieldType: 'number', calculated: false, modificationMetadata: {readOnlyValue: false}},
    {name: 'readonly_note', type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: true}},
  ]};
  const metadata = {version: 'actql-hubspot-read-metadata/0.1', connectorId: 'fixture', portalId: '7',
    apiOrigin: site.apiOrigin, accountBody: encode({portalId: 7}), objects: profile.resources.map(value =>
      ({...value, propertiesBody: encode(properties)}))};
  const state = {events: [], reads: [], quotes: [], retained: [], active: false, nativeCalls: [], declaration: undefined};
  const provider = Object.freeze(Object.fromEntries(Object.entries(native).map(([name, value]) =>
    [name, typeof value !== 'function' ? value : (...args) => {
      assert.equal(state.active, true, `provider ${name} outside original constructor`);
      state.nativeCalls.push(name); return Reflect.apply(value, native, args);
    }])));
  const quote = name => (...args) => {
    const capacity = Object.freeze({originalQuote: state.quotes.length + 1});
    state.quotes.push({name, args, capacity}); return capacity;
  };
  const moon = Object.freeze({clientProgramHubSpotAccountConstructionCapacity: quote('account'),
    clientProgramHubSpotObjectConstructionCapacity: quote('object'),
    clientProgramHubSpotSourceReaderCapacity: quote('source-reader')});
  const construction = {
    configurationReader: {async readJson(path) {
      state.reads.push(path);
      if (path === profile.siteProfilePath) return site;
      assert.equal(path, profile.metadataPath); return metadata;
    }},
    prepareNativeInput(original) {
      assert(Object.isFrozen(original)); const capacity = original.capacity();
      state.events.push(`reserve:${state.quotes.at(-1).name}`); state.active = true;
      let output;
      try {output = original.project();} finally {state.active = false;}
      assert(Object.isFrozen(output)); state.retained.push({capacity, output});
      state.events.push('retained'); return output;
    },
    prepareDeclaration(views) {
      state.events.push('declaration');
      state.declaration = Object.freeze({originalViews: views}); return {declared: state.declaration};
    },
    sourceReaderImplementation(options) {
      assert.equal(state.events.at(-1), 'declaration');
      const original = state.quotes.at(-1);
      assert.equal(original.name, 'source-reader');
      assert.strictEqual(options.readSequenceConstruction.capacity, original.capacity);
      assert.equal(options.columnCount, 3);
      assert.equal(options.limits.maxTotalResponseBytes, 65536);
      assert.equal(options.limits.maxRows, 2); assert.equal(options.limits.maxTotalRows, 10);
      assert.deepEqual(options.readSequenceConstruction.sequence, {
        operation: 'hubspot:objects:list', maxUses: 2, children: [
          {operation: 'hubspot:account:details', resource: 'account', maxUses: 8},
          {operation: 'hubspot:properties:read', resource: 'properties', maxUses: 8},
        ]});
      state.events.push('reader-implementation');
      state.implementation = Object.freeze({capacity: original.capacity,
        runAcquisitionLimits: Object.freeze({originalImplementation: true})});
      return state.implementation;
    },
    createSourceReader() {assert.fail('no Source reader after failed Site');},
  };
  return {profile, site, metadata, state, construction, moon, provider, encode,
    prepare: () => prepareInstalledHubSpotMaterials(profile, {moon, providerMoon: provider, construction})};
}

export function registerHubSpotInstallationMaterialTests(native) {
  test('HubSpot shared installation retains every original Catalog and complete read-only schema once', async () => {
    const f = fixture(native), original = await f.prepare();
    assert(Object.isFrozen(original)); assert.strictEqual(original.metadata, f.metadata);
    assert.strictEqual(original.declared, f.state.declaration);
    assert.deepEqual(f.state.reads, [f.profile.siteProfilePath, f.profile.metadataPath]);
    assert.deepEqual(f.state.quotes.map(value => value.name), ['account', 'object', 'object']);
    assert.deepEqual(f.state.events, ['reserve:account', 'retained', 'reserve:object', 'retained',
      'reserve:object', 'retained', 'declaration']);
    assert.deepEqual([...original.catalogs.keys()], ['companies', 'contacts']);
    for (const [index, view] of original.declared.originalViews.entries()) {
      assert.strictEqual(view, f.state.retained[index + 1].output.view);
      assert.strictEqual(original.catalogs.get(view.resource), f.state.retained[index + 1].output.catalog);
      const wire = JSON.parse(view.schema_wire);
      assert.deepEqual(wire, {id: {type: 'string', nullable: false},
        amount: {type: 'decimal', nullable: true, precision: 38, scale: 10},
        readonly_note: {type: 'string', nullable: true}});
    }
    assert.equal(f.state.nativeCalls.filter(name => name === 'hubspotProjectProperties').length, 2);
    assert.equal(f.state.nativeCalls.filter(name => name === 'hubspotRecheckAccountIdentityJson').length, 1);
  });

  test('HubSpot standard Source consumes the same shared materials before opening its original Site', async () => {
    const f = fixture(native), marker = new Error('original Site boundary');
    f.construction.openRowSite = async options => {
      assert.equal(options.connection, 'hubspot:fixture');
      assert.equal(f.state.retained.length, 3); assert.strictEqual(f.state.events.at(-1), 'reader-implementation');
      assert.strictEqual(options.runAcquisitionLimits, f.state.implementation.runAcquisitionLimits);
      assert.equal(options.admitsApprovalTarget({version: 'actql-installed-hubspot-target/0.1',
        apiOrigin: f.site.apiOrigin, portalId: '7', resource: 'companies', objectType: 'companies',
        metadataCid: 'foreign', fields: ['amount']}, 'companies'), false);
      throw marker;
    };
    // Supply the existing public shape without entering a physical Source.
    f.state.declaration = undefined;
    const prepare = f.construction.prepareDeclaration;
    f.construction.prepareDeclaration = views => {
      const {declared} = prepare(views);
      return {declared: {...declared, views: views.map(view => ({resource: view.resource, fields: ['id', 'amount', 'readonly_note']}))}};
    };
    f.construction.createRowSource = () => assert.fail('no Source after failed Site');
    await assert.rejects(loadInstalledHubSpotSource(f.profile, {moon: f.moon, providerMoon: f.provider,
      construction: f.construction, runtimeBundleCid: 'unused', resolveSecret: () => assert.fail('no secret')}),
    error => error === marker);
    assert.deepEqual(f.state.reads, [f.profile.siteProfilePath, f.profile.metadataPath]);
    assert.deepEqual(f.state.quotes.map(value => value.name), ['account', 'object', 'object', 'source-reader']);
    assert.deepEqual(f.state.events, ['reserve:account', 'retained', 'reserve:object', 'retained',
      'reserve:object', 'retained', 'declaration', 'reader-implementation']);
  });

  test('HubSpot shared installation preserves account and Catalog refusal order without Site or later constructor', async () => {
    for (const failure of ['account', 'properties']) {
      const f = fixture(native);
      if (failure === 'account') f.metadata.accountBody = f.encode({portalId: 8});
      else f.metadata.objects[0].propertiesBody = f.encode({results: [{name: 'bad', type: 'unsupported', fieldType: 'unknown'}]});
      await assert.rejects(f.prepare());
      assert.deepEqual(f.state.quotes.map(value => value.name), failure === 'account' ? ['account'] : ['account', 'object']);
      assert.equal(f.state.retained.length, failure === 'account' ? 0 : 1);
      assert.equal(f.state.events.includes('declaration'), false);
    }
    const f = fixture(native);
    await assert.rejects(prepareInstalledHubSpotMaterials(f.profile, {moon: f.moon, providerMoon: f.provider}),
      {code: 'HubSpotSourceConstructionUnavailable'});
    assert.equal(f.state.reads.length, 0); assert.equal(f.state.nativeCalls.length, 0);
  });
}
