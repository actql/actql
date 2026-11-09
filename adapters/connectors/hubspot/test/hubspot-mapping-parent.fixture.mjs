// Real initialization parent, Ledger, Common declaration and Native Mapping.
// The fixture supplies immutable input metadata only. No Site, Client, Run,
// provider I/O, physical acknowledgement or complete installation is claimed.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm, access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {openHostInitializationPreparation, closeHostInitializationPreparation}
  from '../../../local-node/request-preparation-adapter.mjs';
import {createInstalledHostServices, retainInstalledHostServiceInstallation,
  beginInstalledSourceInitialization, finishInstalledSourceInitialization, retireInstalledSourceInitialization}
  from '../../../host-node/installed-host-services.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {prepareInstalledHubSpotUpdateMappings} from '../host/hubspot-effect-mappings.mjs';
import {captureHubSpotEffectPlanRecipeBuilder} from '../host/hubspot-effect-plan.mjs';
import {hubSpotEffectPlanFixture} from './hubspot-effect-plan.fixture.mjs';
import {loadInstalledHubSpotEffect} from '../host/installed-hubspot-effect.mjs';
import {createInstalledRowEffect} from '../../../host-node/installed-row-effect.mjs';

const mappingLimits = Object.freeze({maxProperties: 10, maxFields: 4, maxNameBytes: 100,
  maxBytes: 4096, maxNodes: 1000, maxDepth: 20});
const writes = Object.freeze([Object.freeze({resource: 'companies', fields: Object.freeze(['name'])})]);
const body = Buffer.from(JSON.stringify({results: [
  {name: 'name', type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}},
  {name: 'actql_request_id', type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}},
]}));
const runtimeCid = 'sha256:' + 'a'.repeat(64);

function fixture(common, native, baseEnvironmentWire, role = 'effect') {
  const state = {}, root = '/unopened-hubspot-mapping-parent-' + role;
  let pending = false, closed = false, finished = false;
  const current = () => assert.equal(closed, false);
  const parent = openHostInitializationPreparation(state, common,
    Object.freeze({root, purpose: 'actual original Mapping constructor controls'}), current, () => pending);
  const services = createInstalledHostServices({root, principalId: 'component', moon: common,
    initialPreparation: parent, assertCurrent: current});
  pending = true;
  const installation = installedConnectors.find(value => value.name === 'hubspot');
  retainInstalledHostServiceInstallation(services, installation, runtimeCid);
  const context = beginInstalledSourceInitialization(services, installation, 'hubspot', baseEnvironmentWire, role);
  const input = context.prepareNativeInput(Object.freeze({
    capacity: () => common.clientProgramHubSpotObjectConstructionCapacity(body.length,
      body.toString('base64').length, 'companies'.length, 4096, 1000, 20, 10, 100, 3, 100, 4096, 1000, 20),
    project() {
      const catalog = checked(native.hubspotProjectProperties(body, 'companies', 4096, 1000, 20, 10, 100));
      const names = native.hubspotPropertyCatalogNames(catalog);
      const schema = checked(native.hubspotObjectSchemaWire(catalog, names, 3, 100, 4096, 1000, 20));
      return Object.freeze({catalog, view: Object.freeze({resource: 'companies', resource_kind: 'object',
        schema_wire: schema, schema_cid: 'sha256:' + createHash('sha256').update(schema).digest('hex'),
        facts_wire: native.hubspotObjectRelationFactsWire()})});
    },
  }));
  const prepared = context.prepareDeclaration([input.view]);
  return {context, prepared, catalog: input.catalog,
    close() {
      if (closed) return;
      // A constructor-only component deliberately stops before any Site or
      // adapter. Retire this exact unfinished construction, not a fake adapter.
      if (!finished) {
        finishInstalledSourceInitialization(context, undefined, new Error('pure component terminal'), true);
        finished = true;
      }
      assert.equal(retireInstalledSourceInitialization(services), true);
      pending = false; closeHostInitializationPreparation(state); closed = true;
    }};
}

function prepare(f, common, native) {
  return prepareInstalledHubSpotUpdateMappings({construction: f.context, moon: common, providerMoon: native,
    connectorId: 'hubspot', declared: f.prepared.declared, catalogFor: () => f.catalog,
    writes, limits: mappingLimits});
}

async function rowConstructorFixture(common, t) {
  const {options} = hubSpotEffectPlanFixture();
  const recipe = captureHubSpotEffectPlanRecipeBuilder({moon: common})(options);
  const root = await mkdtemp(join(tmpdir(), 'actql-hubspot-kind-finalization-'));
  t.after(() => rm(root, {recursive: true}));
  let closed = 0;
  const unused = () => assert.fail('No request, provider, grant or authority in constructor-only component');
  const driver = Object.freeze({kinds: Object.freeze(['update']), targetRead: Object.freeze({operation: 'hubspot:read'}),
    prepareRequest: unused, requestFacts: unused, writeOperation: unused, send: unused, project: unused,
    footprint: unused, observeTargets: unused, recoverRequests: unused, recoveryEntry: unused, requestCid: unused,
    finalizeRequest: unused, capabilityRequestCid: unused, assertRequestFinalized: unused});
  const input = {moon: {strategyRemoteManagedOutputEvidenceKind: () => 'unused-kind'}, driver,
    mappings: [{resource: 'companies', mappingRef: 'mapping:component/update.v1', mappingCid: runtimeCid,
      body: JSON.stringify({mapping_contract_cid: runtimeCid, target_ref: 'connector://hubspot/companies',
        primary_identity: ['id'], minimum_approval: 'required',
        permission_rules: [{effect_kind: 'update', permissions: ['write']}]})}],
    environmentWire: '{}', connectorId: 'hubspot', connectorRegistration: 'hubspot', connectorRevision: 'hubspot/0.1',
    connection: 'hubspot:hubspot', site: {issueEffectGrant: unused, issueReadGrant: unused, close() {closed++;}},
    authorization: {authorize: unused}, runtimeBundleCid: runtimeCid, bindingCid: runtimeCid, ledgerRoot: root};
  return {input, recipe, closed: () => closed};
}

export function registerHubSpotMappingParentTests(common, native, baseEnvironmentWire) {
  test('HubSpot real initial parent funds Native Mapping after its same declaration and completes its original Environment', () => {
    const f = fixture(common, native, baseEnvironmentWire);
    let attempted = 0, completed = 0;
    const counted = {...native, hubspotPrepareExecutionMapping(...args) {
      attempted++; const result = native.hubspotPrepareExecutionMapping(...args); checked(result); completed++; return result;
    }};
    try {
      const result = prepare(f, common, counted);
      assert.equal(attempted, 1); assert.equal(completed, 1);
      assert.strictEqual(result.prepared.declaration, f.prepared.declaration);
      assert.strictEqual(result.prepared.declared, f.prepared.declared);
      assert.equal(result.prepared.mappings.length, 1);
      assert.equal(result.prepared.mappings[0].body, result.originals[0].body);
      const environment = JSON.parse(result.prepared.environment.wire);
      assert(environment.mapping_contracts.some(mapping => mapping.mapping_contract_cid === result.originals[0].mappingCid));
      const projection = Object.freeze({capacity() {assert.fail('no quote after mappings');}, project() {assert.fail('no native input after mappings');}});
      assert.throws(() => f.context.prepareNativeInput(projection), {code: 'ForeignInstalledSourceInitialization'});
      assert.throws(() => f.context.prepareNativeMappings(f.prepared.declared, result.originals),
        {code: 'ForeignInstalledSourceInitialization'});
    } finally {f.close();}
  });

  test('HubSpot real initial parent keeps Source post-declaration and retired native input paths closed', () => {
    const f = fixture(common, native, baseEnvironmentWire, 'source');
    const projection = Object.freeze({capacity() {assert.fail('no Source quote after declaration');}, project() {assert.fail('no Source native input after declaration');}});
    try {assert.throws(() => f.context.prepareNativeInput(projection), {code: 'ForeignInstalledSourceInitialization'});}
    finally {f.close();}
    assert.throws(() => f.context.prepareNativeInput(projection), {code: 'ForeignInstalledSourceInitialization'});
  });

  test('HubSpot real initial Ledger refuses excess post-declaration quantity before Native projection', () => {
    const f = fixture(common, native, baseEnvironmentWire);
    let quoted = 0, projected = 0;
    try {
      assert.throws(() => f.context.prepareNativeInput(Object.freeze({
        capacity() {quoted++; return checked(common.clientProgramInstalledSourceConstructionCapacity(
          100000000n, 0n, 0n, 0n, 0n, 0n));},
        project() {projected++; return Object.freeze({});},
      })));
      assert.equal(quoted, 1, 'Reach the real original Ledger, not the old phase refusal');
      assert.equal(projected, 0);
    } finally {f.close();}
  });

  test('HubSpot Mapping originals cannot move to another actual initialization parent or be copied', () => {
    const original = fixture(common, native, baseEnvironmentWire);
    const other = fixture(common, native, baseEnvironmentWire);
    try {
      const result = prepare(original, common, native);
      assert.throws(() => other.context.prepareNativeMappings(other.prepared.declared, result.originals),
        {code: 'ForeignInstalledSourceInitialization'});
      assert.throws(() => other.context.prepareNativeMappings(other.prepared.declared,
        Object.freeze(result.originals.map(value => Object.freeze({...value})))),
      {code: 'ForeignInstalledSourceInitialization'});
      assert.equal(prepare(other, common, native).prepared.mappings.length, 1);
    } finally {other.close(); original.close();}
  });

  test('HubSpot post-declaration Native projection cannot reenter or reuse its original attempt', () => {
    const f = fixture(common, native, baseEnvironmentWire);
    let projected = 0;
    const nested = Object.freeze({capacity() {assert.fail('no reentrant quote');},
      project() {assert.fail('no reentrant projection');}});
    const projection = Object.freeze({
      capacity() {return checked(common.clientProgramInstalledSourceConstructionCapacity(1n, 0n, 0n, 0n, 0n, 0n));},
      project() {
        projected++;
        assert.throws(() => f.context.prepareNativeInput(nested), {code: 'ForeignInstalledSourceInitialization'});
        assert.throws(() => f.context.prepareNativeMappings(f.prepared.declared, Object.freeze([])),
          {code: 'ForeignInstalledSourceInitialization'});
        return Object.freeze({});
      },
    });
    try {
      assert.deepEqual(f.context.prepareNativeInput(projection), {});
      assert.throws(() => f.context.prepareNativeInput(projection), {code: 'ForeignInstalledSourceInitialization'});
      assert.equal(projected, 1);
    } finally {f.close();}
  });

  test('HubSpot real material factory leaves credential policy selection to the original Host Site owner', async () => {
    const root = '/unopened-hubspot-credential-selection', state = {};
    let pending = false, retired = false, siteCalls = 0;
    const current = () => assert.equal(retired, false);
    const parent = openHostInitializationPreparation(state, common, Object.freeze({root}), current, () => pending);
    const services = createInstalledHostServices({root, principalId: 'component', moon: common,
      initialPreparation: parent, assertCurrent: current});
    pending = true;
    const installation = installedConnectors.find(value => value.name === 'hubspot');
    retainInstalledHostServiceInstallation(services, installation, runtimeCid);
    const context = beginInstalledSourceInitialization(services, installation, 'hubspot', baseEnvironmentWire, 'effect');
    const site = {version: 'actql-installed-hubspot-site/0.1', apiOrigin: 'https://api.hubapi.com',
      credentialAuthorityId: 'component', credentialKeyId: 'key', credentialPrivateKeyPath: '/unopened/key',
      environment: 'component', journalRoot: '/unopened/journal', namespaceId: 'component',
      siteGeneration: 1, siteKey: 'component', tokenEnvironment: 'ACTQL_HUBSPOT_COMPONENT'};
    const source = {version: 'actql-installed-hubspot-source/0.1', connectorId: 'hubspot', portalId: '7',
      resources: [{resource: 'companies', objectType: 'companies'}], metadataPath: '/metadata.json',
      siteProfilePath: '/site.json', metadataResources: {account: 'account', properties: 'properties'},
      accountConfigurationWire: '{}', limits: {maxResponseBytes: 4096, maxNodes: 1000, maxDepth: 20,
        maxProperties: 10, maxNameUnits: 100, maxPages: 2, maxRows: 2, maxRequests: 5, perPage: 1,
        maxColumns: 3, maxCursorUnits: 64, maxValueNodes: 100, maxValueTextBytes: 4096,
        maxRowsWireBytes: 4096, maxRowsWireNodes: 100, maxRowsWireDepth: 10,
        maxObjects: 2, maxDeclarationBytes: 4096, maxDeclarationNodes: 1000, maxSecretBytes: 128}};
    const metadata = {version: 'actql-hubspot-read-metadata/0.1', connectorId: 'hubspot', portalId: '7',
      apiOrigin: site.apiOrigin, accountBody: Buffer.from('{"portalId":7}').toString('base64'),
      objects: [{resource: 'companies', objectType: 'companies', propertiesBody: body.toString('base64')}]};
    const boundary = new Error('original Host Site credential selection boundary');
    const construction = Object.freeze({configurationReader: Object.freeze({async readJson(path) {
      return ({'/source.json': source, '/site.json': site, '/metadata.json': metadata})[path];
    }}), prepareNativeInput: projection => context.prepareNativeInput(projection),
    prepareDeclaration: views => context.prepareDeclaration(views),
    prepareNativeMappings: (declared, originals) => context.prepareNativeMappings(declared, originals),
    prepareEffectDriverConstruction() {assert.fail('no driver before Site');},
    openRowSite(options) {
      siteCalls++;
      assert.equal(Object.hasOwn(options, 'runAcquisitionLimits'), false);
      assert.equal(options.connection, 'hubspot:hubspot');
      assert.equal(options.profile.credentialAuthorityId, site.credentialAuthorityId);
      throw boundary;
    }});
    const callerMoon = {...common, clientProgramInstalledSourceReaderPolicy() {
      assert.fail('Only the original Host selects its credential policy');
    }};
    try {
      await assert.rejects(loadInstalledHubSpotEffect({version: 'actql-installed-hubspot-effect/0.1',
        connectorId: 'hubspot', sourceProfilePath: '/source.json',
        writes: [{resource: 'companies', fields: ['name'], markerProperty: 'actql_request_id'}]},
      {moon: callerMoon, providerMoon: native, construction, ledgerRoot: '/unopened/ledger', runtimeBundleCid: runtimeCid}),
      error => error === boundary);
      assert.equal(siteCalls, 1);
    } finally {
      finishInstalledSourceInitialization(context, undefined, boundary, true);
      assert.equal(retireInstalledSourceInitialization(services), true);
      pending = false; closeHostInitializationPreparation(state); retired = true;
    }
  });
  test('HubSpot Row constructor retains complete per-kind and legacy finalization refusals before ledger opening', async t => {
    const {input, recipe, closed} = await rowConstructorFixture(common, t);
    const ledgerRoot = join(input.ledgerRoot, 'must-not-open');
    const {requestFinalization, ...rest} = recipe;
    const incomplete = Object.freeze(rest);
    const byKind = recipes => Object.freeze(recipes);
    for (const selected of [
      {managedPlanRecipes: byKind({update: incomplete})},
      {driver: Object.freeze({...input.driver, kinds: Object.freeze(['create', 'update'])}),
        managedPlanRecipes: byKind({create: recipe, update: incomplete})},
      {managedPlanRecipe: incomplete},
    ]) {
      await assert.rejects(createInstalledRowEffect({...input, ledgerRoot, ...selected}),
        {code: 'InstalledEffectRequestFinalizationPlanUnavailable'});
      await assert.rejects(access(ledgerRoot), {code: 'ENOENT'});
      assert.equal(closed(), 0, 'A refused constructor does not fabricate Site close');
    }
    const aliased = Object.freeze({...recipe, requestFinalization: recipe.requestConstruction});
    await assert.rejects(createInstalledRowEffect({...input, ledgerRoot,
      managedPlanRecipes: byKind({update: aliased})}), {code: 'InvalidInstalledEffectPlanRecipe'});
    await assert.rejects(access(ledgerRoot), {code: 'ENOENT'});
    const legacy = await createInstalledRowEffect({...input, managedPlanRecipe: recipe});
    await legacy.close(); assert.equal(closed(), 1);
  });

  test('HubSpot actual Row constructor accepts distinct finalization in each selected kind recipe', async t => {
    const {input, recipe, closed} = await rowConstructorFixture(common, t);
    const effect = await createInstalledRowEffect({...input, managedPlanRecipes: Object.freeze({update: recipe})});
    assert(Object.isFrozen(effect)); await effect.close(); assert.equal(closed(), 1);
  });

  test('HubSpot actual Common builds the complete staged recipe through the JavaScript caller', () => {
    const {options} = hubSpotEffectPlanFixture();
    const recipe = captureHubSpotEffectPlanRecipeBuilder({moon: common})(options);
    assert.equal(recipe.memberOperations.length, 9);
    assert.equal(recipe.rowOperations.length, 15);
    assert.equal(recipe.credentialOperations.length, 19);
  });

  test('HubSpot actual Common response extents grow each original physical envelope within its declared maximum', () => {
    const {options} = hubSpotEffectPlanFixture(), stages = new Map();
    const moon = {...common, clientProgramInstalledEffectOperationStagedExtentPrepare(initial, maximum) {
      const result = common.clientProgramInstalledEffectOperationStagedExtentPrepare(initial, maximum);
      stages.set(checked(result), {initial, maximum});
      return result;
    }};
    const recipe = captureHubSpotEffectPlanRecipeBuilder({moon})(options);
    for (const operation of recipe.credentialOperations) {
      if (operation.responseExtent === undefined) continue;
      const entries = operation.perRow === false ? recipe.memberOperations : recipe.rowOperations;
      const original = stages.get(entries[operation.operationIndex].extent);
      assert(original, 'The exact physical occurrence retains its original staged envelope');
      for (const bytes of [0, 16, 128, operation.maxResponseBytes]) {
        const input = operation.responseExtent(bytes, new Uint8Array(bytes));
        // The same Core predicate used by InputBegin requires initial <= input
        // <= maximum. These real immutable constructors perform no Host I/O.
        assert.doesNotThrow(() => checked(common.clientProgramInstalledEffectOperationStagedExtentPrepare(
          original.initial, input)), `${operation.phase}/${operation.slot}: initial <= ${bytes}-byte input`);
        assert.doesNotThrow(() => checked(common.clientProgramInstalledEffectOperationStagedExtentPrepare(
          input, original.maximum)), `${operation.phase}/${operation.slot}: input <= maximum`);
      }
    }
  });

  test('HubSpot actual Common cold recovery input stays within its original capture maximum', () => {
    const {options} = hubSpotEffectPlanFixture(), stages = new Map();
    const moon = {...common, clientProgramInstalledEffectOperationStagedExtentPrepare(initial, maximum) {
      const result = common.clientProgramInstalledEffectOperationStagedExtentPrepare(initial, maximum);
      stages.set(checked(result), {initial, maximum});
      return result;
    }};
    const recipe = captureHubSpotEffectPlanRecipeBuilder({moon})(options);
    const original = stages.get(recipe.memberOperations[recipe.recoveryConstruction.operationIndex].extent);
    for (const size of [2, 1024, options.maxRecoveryBytes]) {
      const wire = size === 2 ? '{}' : JSON.stringify('x'.repeat(size - 2));
      const input = recipe.recoveryConstruction.inputExtent('{}', [{memberIndex: 0, wire}], 0);
      assert.doesNotThrow(() => checked(common.clientProgramInstalledEffectOperationStagedExtentPrepare(
        original.initial, input)), `${size}-byte cold constructor retains the original prepaid wire envelope`);
      assert.doesNotThrow(() => checked(common.clientProgramInstalledEffectOperationStagedExtentPrepare(
        input, original.maximum)), `${size}-byte cold constructor must fit the existing maximum`);
    }
  });

}
