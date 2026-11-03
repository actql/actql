import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';
import {observeSalesforceTargetSet} from '../site/salesforce-target-observation.mjs';
import {salesforceWriteDriver} from '../host/salesforce-write-driver.mjs';
import {captureSalesforceEffectPlanRecipeBuilder} from '../host/salesforce-effect-plan.mjs';
import {localOutputLimits} from '../../../host-node/local-values-plan.mjs';
import {salesforceEffectSiteHooks} from '../host/installed-salesforce-effect-hooks.mjs';
import {salesforceEffectTargetReadInventory, loadInstalledSalesforceEffect, INSTALLED_SALESFORCE_EFFECT_VERSION} from
  '../host/installed-salesforce-effect.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;

test('Salesforce Site hooks forward the same managed Effect owner through capture and recovery', () => {
  const managedEffect = Object.freeze({original: 'managed Effect'});
  const compilation = Object.freeze({original: 'compilation'});
  const updateTargetSelections = Object.freeze([Object.freeze({original: 'target selection'})]);
  const assertUpdateSelectionCurrent = () => {};
  const selected = [];
  const moon = {
    clientProgramEffectCompilationPlanWire(actual) {
      assert.strictEqual(actual, compilation);
      return JSON.stringify({execution_material: {program: {id: 'program',
        stages: [{id: 'stage', effects: {save: {}}}]}}});
    },
    clientProgramEffectCompilationCompiledPlanWire(actual) {
      assert.strictEqual(actual, compilation);return 'compiled Plan';
    },
    strategyPublicationAdmit() {return {$tag: 1, _0: {original: 'compiled Plan'}};},
  };
  const hooks = salesforceEffectSiteHooks({environmentWire: 'environment',
    prepareCaptured(facts) {selected.push(facts);return 'captured';},
    prepareRecovered(facts) {selected.push(facts);return 'recovered';}});
  const publicationPlan = {invocationOwner: {}, contractLimits: {
    maxWireBytes: 1024, maxNodes: 128, maxDepth: 16}};
  let observations = 0;
  const captureFacts = {moon, compilation, publicationPlan, managedEffect,
    updateTargetSelections, assertUpdateSelectionCurrent,
    assertContinuationCurrent() {assert.strictEqual(this, captureFacts);observations++;}};
  const recoveryFacts = {moon, managedEffect,
    recovered: {updateTargetSelections, assertUpdateSelectionCurrent},
    assertContinuationCurrent() {assert.strictEqual(this, recoveryFacts);observations++;}};
  assert.equal(hooks.prepareCaptured(captureFacts), 'captured');
  assert.equal(hooks.prepareRecovered(recoveryFacts), 'recovered');
  assert.equal(observations, 0, 'projection must not observe current early');
  captureFacts.assertContinuationCurrent = recoveryFacts.assertContinuationCurrent =
    () => assert.fail('The original method must already be retained');
  for (const facts of selected) {
    assert.strictEqual(facts.managedEffect, managedEffect);
    assert.strictEqual(facts.updateTargetSelections, updateTargetSelections);
    assert.strictEqual(facts.assertUpdateSelectionCurrent, assertUpdateSelectionCurrent);
    facts.assertContinuationCurrent();
  }
  assert.equal(observations, 2);
});

function actualDriverConstructor(createDriver, limits,
  captureRecipes = () => () => Object.freeze({})) {
  const source = readFileSync(new URL('../host/installed-salesforce-effect.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const selected = ast.body.filter(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'prepareInstalledSalesforceEffectDriver');
  assert.equal(selected.length, 1);
  const consumer = ast.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'installedSalesforceEffect');
  const variables = consumer.body.body.filter(node => node.type === 'VariableDeclaration')
    .flatMap(node => node.declarations);
  const bound = variables.find(node => node.init?.callee?.name === 'prepareInstalledSalesforceEffectDriver');
  assert.equal(bound.id.type, 'ObjectPattern');assert.equal(bound.id.properties[0].value.name, 'driver');
  const row = variables.find(node => node.id.name === 'rowEffect').init.argument;
  assert.equal(row.callee.object.name, 'construction');assert.equal(row.callee.property.name, 'createRowEffect');
  assert.equal(row.arguments[0].properties.find(node => node.key.name === 'driver').value.name, 'driver');
  assert.equal(row.arguments[0].properties.find(node => node.key.name === 'managedPlanRecipes').value.name, 'managedPlanRecipes');
  const fail = code => {throw Object.assign(new Error(code), {code});};
  return compileFunction(`${source.slice(selected[0].start, selected[0].end)}
    return prepareInstalledSalesforceEffectDriver;`,
  ['nodeTypes', 'fail', 'salesforceWriteDriver', 'limits', 'installedRowCredentialOperationSite',
    'captureSalesforceEffectPlanRecipeBuilder', 'DEFAULT_SALESFORCE_CATALOG_LIMITS'])(nodeTypes, fail,
    createDriver, limits, () => ({construction: {}}), captureRecipes, {});
}

function managedRecipeFixture() {
  const profile = Object.freeze({original: 'profile Option'}), capture = Object.freeze({original: 'capture Option'});
  const capacities = Array.from({length: 8}, (_, index) => Object.freeze({originalCapacity: index}));
  const calls = [], extents = [];
  const ok = value => ({$tag: 1, _0: value});
  const moon = {
    clientProgramInstalledEffectControlWireBound(outcome,maximum) {assert.equal(maximum,1000000);return ok(outcome+1510);},
    clientProgramInstalledDescribedEffectInputRecipeCapacities(...args) {
      assert.strictEqual(this, moon);assert.strictEqual(args[0], profile);assert.strictEqual(args[1], capture);
      assert.deepEqual(args.slice(5,8),[128,32,8],
        'same actual proposal body limit, not the whole Preview limit');
      calls.push(args);return ok(capacities);
    },
    clientProgramInstalledEffectOperationStagedExtentPrepare(initial,maximum) {return ok(Object.freeze({initial,maximum}));},
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation, capacity, transferBytes, physical) {
      assert.strictEqual(this, moon);
      const original = Object.freeze({operation, capacity, transferBytes, physical});
      extents.push(original);return ok(original);
    },
    clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare(operation, original, bytes, nodes, depth) {
      assert.strictEqual(this, moon);assert.deepEqual(original, capacities.slice(0, 6));
      assert.deepEqual([bytes, nodes, depth], [1024, 128, 16]);
      return ok(Object.freeze({operation, original}));
    },
  };
  const provider = {
    salesforceEffectConstructionProfile(...args) {
      assert.strictEqual(this, provider);assert.equal(args[20], 1);assert.equal(args[21], 4);
      // Both original methods were captured before the first callback.
      provider.salesforceEffectInputCaptureConstructionProfile = () => assert.fail('replacement');
      provider.salesforceEffectMetadataInputConstructionProfile = () => assert.fail('replacement');
      return profile;
    },
    salesforceEffectInputCaptureConstructionProfile(...args) {
      assert.strictEqual(this, provider);assert.strictEqual(args[0], profile);
      assert.equal(args[17], localOutputLimits.maxWireBytes);return capture;
    },
    salesforceEffectTargetInputConstructionProfile(original) {assert.equal(this,provider);assert.equal(original,profile);return profile;},
    salesforceEffectMetadataInputConstructionProfile(original) {assert.equal(this,provider);assert.equal(original,profile);return profile;},
  };
  const write = Object.freeze({resource: 'Account', fields: Object.freeze(['Name'])});
  const installed = Object.freeze({mappings: Object.freeze([Object.freeze({write})])});
  const limits = {preview: {maxWireBytes: 1024, maxNodes: 128, maxDepth: 16},
    body: {maxBytes: 128, maxNodes: 32, maxDepth: 8},
    request: {maxPathBytes: 256, maxTargetBytes: 64, maxBodyBytes: 128},
    target: {maxResponseBytes: 256, maxNodes: 64, maxDepth: 8}, maxIdentityBytes: 128,
    write: {maxRequestBytes: 128, maxResponseBytes: 256, maxNodes: 64, maxDepth: 8}, maxRetainedBytes: 1024};
  const catalogLimits = {list: {maxBytes: 256, maxNodes: 64, maxDepth: 8,
    maxResources: 4, maxSelected: 2, maxNameUnits: 64},
  describe: {maxBytes: 256, maxNodes: 64, maxDepth: 8, maxFields: 4, maxNameUnits: 64}, maxObservationBytes: 1024};
  const secret = Object.freeze({scope: Object.freeze({siteKey: 'same original site'}),
    issuer: Object.freeze({authority: 'authority', keyId: 'key'}), limits: Object.freeze({maxSecretBytes: 64})});
  return {options: {moon, salesforceMoon: provider, installed, limits, catalogLimits,
    site: {apiVersion: 'v61.0'}, credentialConstruction: secret}, calls, capacities, extents};
}

test('Salesforce managed recipes retain original native profiles and distinct member/row HTTP occurrences', () => {
  const {options, calls, capacities} = managedRecipeFixture();
  const build = captureSalesforceEffectPlanRecipeBuilder(options);
  options.salesforceMoon.salesforceEffectConstructionProfile = () => assert.fail('changed during Source reserve');
  options.moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare = () => assert.fail('changed during Source reserve');
  const recipes = build(options);
  assert(Object.isFrozen(recipes));assert.deepEqual(Object.keys(recipes), ['create', 'update', 'upsert']);
  assert.deepEqual(calls.map(args => args[10]), [false, false, false, true, true, true, true, true, true]);
  assert.deepEqual(calls.map(args => args.at(-1)), [0, -1, 0, 0, -1, 0, 0, -1, 0],
    'only the original maximum prequotes the full Host parser; warm input has not been built');
  for (const [kind, recipe] of Object.entries(recipes)) {
    assert.strictEqual(recipe.controlsPerRow, capacities[4]);
    assert.equal(recipe.memberOperations.length, 4);
    assert.equal(recipe.rowOperations.length, kind === 'create' ? 2 : 5);
    const descriptions = recipe.credentialOperations.filter(entry => entry.phase.endsWith('-describe'));
    assert.deepEqual(descriptions.map(entry => entry.operationIndex), [1, 2, 3]);
    for (const entry of descriptions) {
      assert.equal(entry.perRow, false);
      const staged = recipe.memberOperations[entry.operationIndex].extent;
      assert(Object.isFrozen(staged));assert.equal(typeof entry.responseExtent,'function');
      const extent = staged.initial;
      assert.strictEqual(extent.capacity, capacities[7]);assert.equal(extent.physical, true);
      assert.equal(extent.operation, 'salesforce:catalog:describe');
    }
    const targets = recipe.credentialOperations.filter(entry => entry.phase.endsWith('-target'));
    assert.equal(targets.length, kind === 'create' ? 0 : 3);
    for (const entry of targets) {
      assert.equal(entry.perRow, true);assert.strictEqual(recipe.rowOperations[entry.operationIndex].extent.initial.capacity, capacities[6]);
    }
    const write = recipe.credentialOperations.find(entry => entry.phase === 'write');
    assert.equal(write.perRow, true);assert.strictEqual(recipe.rowOperations[write.operationIndex].extent.capacity, capacities[3]);
  }
});

test('Salesforce managed recipe preserves original native refusal before any child constructor', () => {
  const {options, calls, extents} = managedRecipeFixture();
  const original = new Error('original native constructor refused');
  options.salesforceMoon.salesforceEffectConstructionProfile = () => {throw original;};
  const build = captureSalesforceEffectPlanRecipeBuilder(options);
  assert.throws(() => build(options), error => error === original);
  assert.equal(calls.length, 0);assert.equal(extents.length, 0);
});

test('Salesforce driver is constructed only inside its original funded initialization', () => {
  const quantity = {}, driver = {}, site = {}, limits = {}, mapping = {mappingCid: 'mapping'};
  const installed = {generationCid: 'generation', mappings: [mapping]};
  const nextOccurrence = () => assert.fail('No provider callback during installation');
  const events = [];
  let active = false;
  const provider = {salesforceEffectDriverConstructionCapacity() {
    assert.strictEqual(this, provider);events.push('capacity');return quantity;
  }};
  const construction = {prepareEffectDriverConstruction(projection) {
    assert.strictEqual(this, construction);assert(Object.isFrozen(projection));
    assert.strictEqual(projection.capacity(), quantity);
    // Capture precedes the existing reserve/current boundary. Replacing the
    // namespace entry here cannot replace the original quantity callback.
    provider.salesforceEffectDriverConstructionCapacity = () => assert.fail('replacement');
    assert.strictEqual(projection.capacity(), quantity);
    events.push('reserve');active = true;
    try {return projection.project();} finally {active = false;}
  }};
  const prepare = actualDriverConstructor(options => {
    assert(active);events.push('driver');assert.strictEqual(options.site, site);
    assert.strictEqual(options.salesforceMoon, provider);assert.strictEqual(options.limits, limits);
    assert.strictEqual(options.mappingOf('mapping'), mapping);
    assert.strictEqual(options.nextOccurrence, nextOccurrence);
    assert.equal(options.siteBindingCid, 'site');assert.equal(options.generationCid, 'generation');
    return driver;
  }, limits, options => {
    assert.equal(active, false);assert.strictEqual(options.salesforceMoon, provider);
    events.push('capture-methods');
    return () => {assert(active);events.push('recipes');return Object.freeze({});};
  });
  const result = prepare({construction, salesforceMoon: provider, site, installed, nextOccurrence, siteBindingCid: 'site'});
  assert(Object.isFrozen(result));assert.strictEqual(result.driver, driver);
  assert.deepEqual(events, ['capture-methods', 'capacity', 'capacity', 'reserve', 'recipes', 'driver']);
});

test('Salesforce driver retains an original initializer refusal without constructing provider callbacks', () => {
  const original = new Error('original reservation refused');
  let constructed = 0, capacityCalls = 0, accessors = 0;
  const prepare = actualDriverConstructor(() => {constructed++;return {};}, {});
  const provider = {salesforceEffectDriverConstructionCapacity() {capacityCalls++;return {};}};
  assert.throws(() => prepare({salesforceMoon: provider,
    construction: {prepareEffectDriverConstruction(projection) {
      projection.capacity();throw original;
    }}}), error => error === original);
  assert.equal(constructed, 0);assert.equal(capacityCalls, 1);
  assert.throws(() => prepare({salesforceMoon: provider, construction: {
    get prepareEffectDriverConstruction() {accessors++;return () => {};},
  }}), {code: 'InstalledSalesforceDriverConstructionUnavailable'});
  assert.equal(accessors, 0);assert.equal(constructed, 0);assert.equal(capacityCalls, 1);
});

test('Salesforce managed recheck uses the same original control frame before Native request checking', () => {
  const requests = [{}, {}], observation = {}, events = [];
  let active = false;
  const moon = {salesforceRecheckSingleWriteRequest(request, original) {
    assert(active);assert.strictEqual(original, observation);
    assert.strictEqual(request, requests[events.length]);events.push(request);
    return {$tag: 1, _0: undefined};
  }};
  const driver = salesforceWriteDriver({salesforceMoon: moon, site: {}, mappingOf() {}, nextOccurrence() {},
    siteBindingCid: 'original-site', generationCid: 'original-generation', limits: {}});
  let frames = 0;
  driver.recheckRequests({entries: requests.map(request => ({request})), current: {observation},
    controlConstruction(receiver, method, args) {
      frames++;active = true;
      try {return Reflect.apply(method, receiver, args);} finally {active = false;}
    }});
  assert.equal(frames, 1);assert.deepEqual(events, requests);assert.equal(active, false);
});

function fixture() {
  let calls = 0;
  const site = {connection: 'crm', context: {contextCid: cid('1')},
    namespaceId: 'namespace', principal: 'owner', environment: 'test',
    connectionRevision: 'revision-1', orgId: 'org-1',
    instanceOrigin: 'https://example.invalid', siteKey: 'site-1',
    siteGeneration: 'generation-1', apiVersion: 'v61.0',
    cliAlias: 'fixture', cliUsername: 'fixture@example.invalid',
    credentialAuthorityId: 'credential', credentialKeyId: 'key-1',
    credentialPrivateKeyPath: '/fixture/key.pem', caPath: '/fixture/ca.pem',
    issueGrant() { assert.fail('Inventory must not issue grants'); },
    describeEffectCatalog() { assert.fail('Inventory must not read the provider'); }};
  const installed = {generationCid: cid('2'), mappings: [
    {mappingCid: cid('3'), mappingRef: 'mapping:account',
      write: {resource: 'Account', kind: 'update', fields: ['Name']}},
    {mappingCid: cid('4'), mappingRef: 'mapping:contact',
      write: {resource: 'Contact', kind: 'update', fields: ['Name']}},
  ]};
  const ids = ['account', 'contact', 'account_again'];
  const prepared = {};
  const moon = {clientProgramEffectMemberDescriptor(actual, stage, id) {
    calls++;
    assert.equal(actual, prepared);
    assert.equal(stage, 1);
    const index = ids.indexOf(id);
    const mapping = installed.mappings[index === 1 ? 1 : 0];
    return {$tag: 1, _0: {_0: index, _1: id, _2: 'update',
      _4: mapping.mappingRef, _5: mapping.mappingCid, _6: {}}};
  }};
  return {options: {moon, prepared, installed, site, connectorId: 'crm',
    unit: {programId: 'program', stageId: 'write', stageIndex: 1,
      effectIds: ids}}, calls: () => calls};
}

test('target inventory preserves distinct tuples and same-tuple member bindings without I/O', () => {
  const {options, calls} = fixture();
  const inventory = salesforceEffectTargetReadInventory(options);
  assert.equal(calls(), 3);
  assert.deepEqual(inventory.map(item => item.readTuple), [
    {connection: 'crm', resource: 'Account', operation: 'read'},
    {connection: 'crm', resource: 'Contact', operation: 'read'},
    {connection: 'crm', resource: 'Account', operation: 'read'},
  ]);
  assert.deepEqual(inventory.map(item => [item.physicalBinding.effect_id,
    item.physicalBinding.member_index, item.physicalBinding.mapping_cid]), [
    ['account', 0, cid('3')], ['contact', 1, cid('4')],
    ['account_again', 2, cid('3')],
  ]);
  assert.ok(Object.isFrozen(inventory));
  assert.ok(inventory.every(item => Object.isFrozen(item) &&
    Object.isFrozen(item.readTuple) && Object.isFrozen(item.physicalBinding) &&
    Object.isFrozen(item.physicalBinding.fields)));
  options.installed.mappings[0].write.fields = ['Changed'];
  assert.deepEqual(inventory[0].physicalBinding.fields, ['Name']);
});

test('target inventory changes when the Site or installed generation changes', () => {
  const {options} = fixture();
  const original = salesforceEffectTargetReadInventory(options);
  options.site.orgId = 'another-org';
  const changed = salesforceEffectTargetReadInventory(options);
  assert.notEqual(changed[0].physicalBinding.site_binding_cid,
    original[0].physicalBinding.site_binding_cid);
  options.installed.generationCid = cid('5');
  assert.equal(salesforceEffectTargetReadInventory(options)[0]
    .physicalBinding.generation_cid, cid('5'));
});

test('target inventory rejects an unresolved Mapping before any I/O', () => {
  const {options} = fixture();
  options.moon.clientProgramEffectMemberDescriptor = () => ({$tag: 1,
    _0: {_0: 0, _1: 'account', _2: 'update', _4: 'mapping:other',
      _5: cid('f'), _6: {}}});
  assert.throws(() => salesforceEffectTargetReadInventory(options),
    {code: 'SalesforceEffectMappingNotInstalled'});
});

// These original protocol ports expose managed transport correspondence only;
// they issue no Site grant, native capacity, durable claim or provider outcome.
test('Salesforce driver forwards the same managed Describe and write transport callbacks', async () => {
  const request = {}, observation = {}, approval = {}, signal = new AbortController().signal;
  const readChild = () => assert.fail('Describe construction must not invoke its read child');
  let descriptions = 0, sends = 0;
  const site = {instanceOrigin: 'https://example.invalid', credential: {},
    describeEffectCatalog(options) {
      assert.equal(this, site);
      assert.strictEqual(options.readChild, readChild);
      assert.strictEqual(options.approval, approval);
      assert.strictEqual(options.signal, signal);
      descriptions++;
      return observation;
    }};
  const moon = {
    salesforceSingleWriteRequestOrgId: original => {assert.equal(original, request); return 'org';},
    salesforceSingleWriteRequestGrantOperation: () => 'salesforce:record:update',
    salesforceSingleWriteRequestScopeMatches: () => true,
    salesforceRecheckSingleWriteRequest(original, current) {
      assert.equal(original, request); assert.equal(current, observation);
      return {$tag: 1, _0: undefined};
    },
    salesforceSingleWriteRequestMethod: () => 'PATCH',
    salesforceSingleWriteRequestPath: () => '/record/original',
    salesforceSingleWriteRequestBody: () => '{"Name":"original"}',
  };
  const driver = salesforceWriteDriver({salesforceMoon: moon, site,
    mappingOf: () => assert.fail('transport must keep the already prepared request'),
    nextOccurrence: label => `original-${label}`, siteBindingCid: 'binding', generationCid: 'generation',
    limits: {write: {maxRequestBytes: 128, maxResponseBytes: 64, maxNodes: 16, maxDepth: 4}}});
  assert.strictEqual(await driver.describe({member: {resource: 'Account'}, runInvocationCid: cid('1'),
    dispatchRequestCid: cid('2'), label: 'capture', approval, signal, readChild}), observation);
  const grant = {}, control = {}, journal = {}, binding = {}, secret = () => assert.fail('no secret resolution');
  const authorization = {grant, useId: 'same-use', scope: {operation: 'salesforce:record:update'}};
  const credential = {orgId: 'org', control, journal, binding, resolveSecret: secret};
  const body = Buffer.from('{}');
  const result = await driver.send({request, current: {observation}, authorization, credential, signal,
    callResource(input) {
      sends++;
      assert.strictEqual(input.grant, grant);
      assert.strictEqual(input.control, control);
      assert.strictEqual(input.journal, journal);
      assert.strictEqual(input.binding, binding);
      assert.strictEqual(input.resolveSecret, secret);
      assert.strictEqual(input.signal, signal);
      assert.equal(input.useId, 'same-use');
      assert.deepEqual([...input.operations], [['salesforce:record:update',
        {method: 'PATCH', path: '/record/original', body: '{"Name":"original"}'}]]);
      assert.deepEqual([input.maxRequestBytes, input.maxResponseBytes], [128, 64]);
      return {useCid: 'original-use', statusCode: 204, body};
    }});
  assert.equal(descriptions, 1);
  assert.equal(sends, 1);
  assert.strictEqual(result.observation.body, body);
});

test('Salesforce target inventory preserves each original authorization and row through its managed read child', async () => {
  const requests = [{path: '/record/first'}, {path: '/record/second'}], current = {};
  const grants = [{}, {}], authorizations = grants.map((grant, index) => Object.freeze({grant,
    useId: `original-use-${index}`, scope: Object.freeze({operation: 'salesforce:record:observe'})}));
  const binding = {}, control = {}, journal = {}, secret = () => assert.fail('no secret resolution');
  const credential = {orgId: 'org', binding, control, journal, resolveSecret: secret};
  let calls = 0, authorizationsRead = 0;
  const moon = {
    salesforceSingleWriteRequestMethod: () => 'PATCH',
    salesforceSingleWriteRequestOrgId: () => 'org',
    salesforceSingleWriteRequestScopeMatches: () => true,
    salesforceRecheckSingleWriteRequest(request, original) {
      assert(requests.includes(request)); assert.strictEqual(original, current);
      return {$tag: 1, _0: undefined};
    },
    salesforceSingleWriteRequestPath: request => request.path,
    salesforcePrepareTargetObservation(request, status, body) {
      assert.equal(status, 200); assert.equal(body.toString(), '{}');
      return {$tag: 1, _0: {request}};
    },
    salesforceTargetObservationVersionCid: record => cid(record.request === requests[0] ? '1' : '2'),
    salesforceTargetObservationBeforeValueWire: () => '{}',
    salesforcePrepareObservedPreviewRow: (request, record) => {
      assert.strictEqual(record.request, request);
      return {$tag: 1, _0: {request}};
    },
    salesforceObservedPreviewRowFields: row => [JSON.stringify(row.request.path),
      cid(row.request === requests[0] ? '1' : '2'), '{}', undefined, undefined],
  };
  const targetLimits = {maxResponseBytes: 64, maxNodes: 16, maxDepth: 4, maxIdentityBytes: 128};
  const site = {credential};
  const driver = salesforceWriteDriver({salesforceMoon: moon, site, mappingOf() {}, nextOccurrence() {},
    siteBindingCid: 'binding', generationCid: 'generation',
    limits: {target: targetLimits, maxMembers: 1, maxRows: 2, maxTotalResponseBytes: 128, maxIdentityBytes: 128}});
  const seen = await driver.observeTargets({entries: requests.map(request => ({request})),
    current: {observation: current},
    authorizationForRow: index => {authorizationsRead++; return authorizations[index];},
    readChild(authorization, input, rowIndex) {
      assert.strictEqual(authorization, authorizations[rowIndex]);
      assert.strictEqual(input.grant, grants[rowIndex]);
      assert.strictEqual(input.binding, binding);
      assert.strictEqual(input.control, control);
      assert.strictEqual(input.journal, journal);
      assert.strictEqual(input.resolveSecret, secret);
      assert.equal(input.useId, `original-use-${rowIndex}`);
      assert.equal(input.operations.get('salesforce:record:observe').path, requests[rowIndex].path);
      assert.equal(input.maxResponseBytes, 64);
      calls++;
      return {useCid: `read-${rowIndex}`, statusCode: 200, body: Buffer.from('{}')};
    }});
  assert.deepEqual(seen, requests.map((request, index) => ({identity: request.path,
    versionCid: cid(index === 0 ? '1' : '2'), before: {}})));
  assert.equal(calls, 2);
  assert.equal(authorizationsRead, 2);
});

test('invalid Salesforce managed target child refuses before an authorization or provider call', async () => {
  let authorizations = 0;
  for (const readChild of [null, {}, 0, 'callback']) {
    await assert.rejects(observeSalesforceTargetSet({moon: {},
      members: [{requests: [{}], currentCatalog: {}, credential: {},
        authorizationForRow() {authorizations++; throw new Error('must not issue');}, readChild,
        limits: {maxResponseBytes: 64, maxNodes: 16, maxDepth: 4, maxIdentityBytes: 128}}],
      maxMembers: 1, maxRows: 1, maxTotalResponseBytes: 128}), {code: 'InvalidSalesforceTargetSet'});
  }
  assert.equal(authorizations, 0);
});

const effectPolicyFixture = () => ({version: INSTALLED_SALESFORCE_EFFECT_VERSION,
  siteProfilePath: '/authored-site.json', publicationPath: '/authored-publication.json', connectorId: 'crm',
  accountConfigurationWire: '{}', writes: [{resource: 'Account', kind: 'update', fields: ['Name']}]});
const effectPolicyRuntime = () => Object.fromEntries(['salesforcePrepareExecutionWriteBody',
  'salesforceWriteValueRefusal', 'salesforceSingleWriteRequestValue'].map(name =>
  [name, () => assert.fail('preparation must not invoke a provider codec')]));

test('Salesforce Effect initialization forwards the one original Core Credential policy before opening its actual Site', async () => {
  const policy = [64, 2, 100], original = {}, failure = new Error('stop before actual Site IO');
  let selections = 0, sites = 0;
  const moon = {clientProgramInstalledSourceReaderPolicy() {
    assert.strictEqual(this, moon);selections++;return policy;
  }};
  const provider = effectPolicyRuntime();
  await assert.rejects(loadInstalledSalesforceEffect(effectPolicyFixture(), {moon,
    salesforceMoon: provider, runtimeBundleCid: cid('1'), ledgerRoot: '/authored-ledger',
    resolveSecret: original, construction: {openSpecializedSite(options) {
      sites++;
      assert.strictEqual(options.siteOptions.salesforceMoon, provider);
      assert.strictEqual(options.siteOptions.resolveSecret, original);
      assert.deepEqual(options.siteOptions.runAcquisitionLimits, {maxBindings: 2, maxSecretBytes: 64});
      assert(Object.isFrozen(options.siteOptions.runAcquisitionLimits));
      policy[0] = 1;
      assert.equal(options.siteOptions.runAcquisitionLimits.maxSecretBytes, 64);
      throw failure;
    }}}), error => error === failure);
  assert.equal(selections, 1);assert.equal(sites, 1);
});

test('Salesforce Effect refuses an absent or malformed original Credential policy before Site or provider preparation', async () => {
  let sites = 0, accessors = 0;
  const accessor = {get clientProgramInstalledSourceReaderPolicy() {accessors++; return () => [64, 2, 100];}};
  for (const moon of [{}, accessor, ...[undefined, [64, 2], [0, 2, 100], [64, 2147483648, 100], [64, 2, 100, 1]]
    .map(policy => ({clientProgramInstalledSourceReaderPolicy: () => policy}))]) {
    await assert.rejects(loadInstalledSalesforceEffect(effectPolicyFixture(), {moon,
      salesforceMoon: effectPolicyRuntime(), runtimeBundleCid: cid('1'), ledgerRoot: '/authored-ledger',
      construction: {openSpecializedSite() {sites++;assert.fail('must not open');}}}),
    {code: 'InstalledEffectCredentialPolicyUnavailable'});
  }
  assert.equal(sites, 0);assert.equal(accessors, 0);
});
