// Installation DATA/callee correspondence only. Physical Site, original
// selection/approval owners and a matching normal cohort are separate checks.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {parse} from 'acorn';
import * as hubspotSource from '../host/installed-hubspot-source.mjs';
import {verifyInstalledConnectorBindings} from '../../../host-node/installed-check-environment.mjs';
import {checkInstalledHubSpotEffectProfile, installedHubSpotEffectIdentityParts,
  installedHubSpotTargetReadInventory, loadInstalledHubSpotEffect} from '../host/installed-hubspot-effect.mjs';
import {runtimeTupleFromFields} from '../../../host-common/compiler-binding.generated.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
const ok = value => ({$tag: 1, _0: value});

const cid = 'sha256:' + 'a'.repeat(64);
const profile = () => ({version: 'actql-installed-hubspot-effect/0.1', connectorId: 'fixture', sourceProfilePath: '/source.json',
  writes: [{resource: 'companies', fields: ['amount'], markerProperty: 'actql_request_id'}]});

test('HubSpot authored Source and Effect binding callers agree on the complete same Site and refuse changed originals', async () => {
  const canonical = value => value !== null && typeof value === 'object'
    ? Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
      : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
  const digest = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
  const sourceText = await readFile(new URL('../host/installed-hubspot-source.mjs', import.meta.url), 'utf8');
  const bindingNode = parse(sourceText, {ecmaVersion: 'latest', sourceType: 'module'}).body.find(node =>
    node.type === 'FunctionDeclaration' && node.id.name === 'siteBinding');
  const originalBinding = new Function('cid', sourceText.slice(bindingNode.start, bindingNode.end) + ';return siteBinding;')(digest);
  const original = {contextCid: 'sha256:' + 'b'.repeat(64), runtimeBundleCid: cid,
    metadata: {portalId: '7', objects: [{resource: 'companies', propertiesBody: 'e30='}]},
    site: {apiOrigin: 'https://hubspot.invalid', credentialAuthorityId: 'original', credentialKeyId: 'key',
      credentialPrivateKeyPath: '/unopened/key', namespaceId: 'original', siteGeneration: 1}};
  async function caller(path, select) {
    const text = await readFile(new URL(path, import.meta.url), 'utf8'), found = [];
    function visit(node) {
      if (!node || typeof node !== 'object') return;
      if (select(node)) found.push(node);
      for (const value of Object.values(node)) {
        if (Array.isArray(value)) value.forEach(visit); else if (value && typeof value === 'object') visit(value);
      }
    }
    visit(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}));
    assert.equal(found.length, 1, 'Exactly one actual binding caller');
    const expression = found[0].type === 'Property' ? found[0].value : found[0].right;
    const evaluate = new Function('cid', 'authorization', 'runtimeBundleCid', 'metadata', 'siteProfile',
      'installedHubSpotSiteBinding', 'siteBinding', 'metadataCid', 'return (' + text.slice(expression.start, expression.end) + ');');
    return input => evaluate(digest, {context: {contextCid: input.contextCid}}, input.runtimeBundleCid,
      input.metadata, input.site, hubspotSource.installedHubSpotSiteBinding, originalBinding,
      digest(input.metadata));
  }
  // Evaluate only the actual pure binding expressions with explicit immutable
  // DATA ports. No constructor, authorization, Site or physical I/O is run.
  const source = await caller('../host/installed-hubspot-source.mjs', node => node.type === 'Property' && node.key.name === 'bindingCid');
  const effect = await caller('../host/installed-hubspot-effect.mjs', node => node.type === 'AssignmentExpression' && node.left.name === 'siteBindingCid');
  const adapter = bindingCid => ({environmentWire: '{"connector_catalogs":[{"connector_id":"hubspot"}]}',
    connectorBindings: [{connectorId: 'hubspot', bindingCid}]});
  const expected = digest({version: 'actql-installed-hubspot-binding/0.1', contextCid: original.contextCid,
    runtimeBundleCid: original.runtimeBundleCid, metadataCid: digest(original.metadata), site: original.site});
  assert.equal(source(original), expected, 'Preserve the existing complete Source preimage');
  verifyInstalledConnectorBindings(adapter(source(original)), adapter(effect(original)));
  for (const changed of [{...original, contextCid: cid},
    {...original, runtimeBundleCid: original.contextCid},
    {...original, metadata: {...original.metadata, portalId: '8'}},
    {...original, site: {...original.site, apiOrigin: 'https://other.invalid'}},
    {...original, site: {...original.site, credentialKeyId: 'other'}},
    {...original, site: {...original.site, siteGeneration: 2}}]) {
    assert.throws(() => verifyInstalledConnectorBindings(adapter(source(original)), adapter(effect(changed))),
      {message: 'InstalledCheckEnvironmentConflict'});
  }
});

test('HubSpot standard table selects its own original Effect module without loading a provider or executing a case', async () => {
  const installed = installedConnectors.find(entry => entry.name === 'hubspot');
  assert.equal(installed.effect.profileVersion, 'actql-installed-hubspot-effect/0.1');
  const module = await installed.effect.load();
  assert.strictEqual(module.check, checkInstalledHubSpotEffectProfile);
  assert.strictEqual(module.identityParts, installedHubSpotEffectIdentityParts);
  assert.equal(typeof module.load, 'function');
});

test('HubSpot Effect profile captures original write and marker DATA without requesting authorization', () => {
  const input = profile(), checked = checkInstalledHubSpotEffectProfile(input);
  input.writes[0].fields[0] = 'other'; input.writes[0].markerProperty = 'foreign';
  assert.deepEqual(checked.writes[0], {resource: 'companies', fields: ['amount'], markerProperty: 'actql_request_id'});
  assert(Object.isFrozen(checked.writes[0].fields)); assert(Object.isFrozen(checked.writes));
  for (const change of [value => value.writes.push(value.writes[0]),
    value => value.writes[0].fields.push('amount'), value => value.writes[0].fields.push('actql_request_id'),
    value => value.writes[0].markerProperty = 'id', value => value.sourceProfilePath = 'relative',
    value => value.extra = true]) {
    const value = profile(); change(value);
    assert.throws(() => checkInstalledHubSpotEffectProfile(value), {code: 'InvalidInstalledHubSpotEffectProfile'});
  }
  const inputWithGetter = profile();
  Object.defineProperty(inputWithGetter.writes[0], 'fields', {enumerable: true, get() {assert.fail('no getter');}});
  assert.throws(() => checkInstalledHubSpotEffectProfile(inputWithGetter), {code: 'InvalidInstalledHubSpotEffectProfile'});
});

test('HubSpot Effect target inventory binds every installed member and rejects foreign descriptors or copied selections', () => {
  const mapping = Object.freeze({resource: 'companies', mappingRef: 'hubspot.amount', mappingCid: cid,
    fields: Object.freeze(['amount'])});
  const state = {kind: 'update', mapping: cid, calls: [], current: 0};
  const moon = {clientProgramEffectMemberDescriptor(prepared, stage, effect, work) {
    state.calls.push({prepared, stage, effect, work});
    return ok(runtimeTupleFromFields([effect === 'second' ? 1 : 0, effect, state.kind, 'target',
      mapping.mappingRef, state.mapping, 'result']));
  }};
  const prepared = Object.freeze({original: 'component'});
  const unit = Object.freeze({programId: 'program', stageId: 'commit', stageIndex: 2,
    effectIds: Object.freeze(['second', 'first'])});
  const inventory = installedHubSpotTargetReadInventory({moon, mappings: [mapping],
    connection: 'hubspot:fixture', siteBindingCid: cid, generationCid: cid, rowEffect: {}});
  const entries = inventory({moon, prepared, unit});
  assert.deepEqual(entries.map(entry => entry.physicalBinding.effect_id), ['first', 'second']);
  assert.notStrictEqual(entries[0].physicalBinding, entries[1].physicalBinding);
  assert.deepEqual(entries.map(entry => entry.readTuple), [0, 1].map(() =>
    ({connection: 'hubspot:fixture', resource: 'companies', operation: 'read'})));
  assert.deepEqual(entries[0].physicalBinding, {version: 'actql-installed-hubspot-effect-target-read/0.1',
    site_binding_cid: cid, generation_cid: cid, program_id: 'program', stage_id: 'commit', stage_index: 2,
    effect_id: 'first', member_index: 0, mapping_cid: cid, mapping_ref: mapping.mappingRef,
    resource: 'companies', effect_kind: 'update', key: 'id', fields: ['amount']});
  assert(state.calls.every(call => call.prepared === prepared && call.stage === 2 && call.work === 10000));
  assert.throws(() => inventory({moon: {}, prepared, unit}), {code: 'ForeignHubSpotEffectRuntime'});
  state.kind = 'create'; assert.throws(() => inventory({moon, prepared, unit}), {code: 'HubSpotEffectMappingNotInstalled'});
  state.kind = 'update'; state.mapping = 'sha256:' + 'b'.repeat(64);
  assert.throws(() => inventory({moon, prepared, unit}), {code: 'HubSpotEffectMappingNotInstalled'});
  state.mapping = cid;
  assert.throws(() => inventory({moon, prepared, unit, updateTargetSelections: [],
    assertUpdateSelectionCurrent() {state.current++;}}));
  assert.equal(state.current, 0);
});

test('HubSpot Effect identity reobserves the full declared Source through existing configuration readers', async () => {
  // Invalid Source refuses before identity construction or provider access.
  const calls = [];
  await assert.rejects(installedHubSpotEffectIdentityParts(profile(), undefined, undefined,
    {configurationReader: {async readJson(path) {calls.push(path); return {version: 'foreign', connectorId: 'fixture'};},
      readText() {assert.fail('no text read');}}}),
  {code: 'InvalidInstalledHubSpotSourceProfile'});
  assert.deepEqual(calls, ['/source.json']);
});

function aliasedSourceFixture() {
  const source = {version: 'actql-installed-hubspot-source/0.1', connectorId: 'fixture', portalId: '7',
    resources: [{resource: 'companies', objectType: 'companies'}], metadataPath: '/metadata.json',
    siteProfilePath: '/site.json', metadataResources: {account: 'account', properties: 'properties'},
    accountConfigurationWire: '{}', limits: {maxResponseBytes: 4096, maxNodes: 1000, maxDepth: 20,
      maxProperties: 10, maxNameUnits: 100, maxPages: 2, maxRows: 2, maxRequests: 5, perPage: 1,
      maxColumns: 3, maxCursorUnits: 64, maxValueNodes: 100, maxValueTextBytes: 4096,
      maxRowsWireBytes: 4096, maxRowsWireNodes: 100, maxRowsWireDepth: 10,
      maxObjects: 2, maxDeclarationBytes: 4096, maxDeclarationNodes: 1000, maxSecretBytes: 128},
    queryAliases: [{name: 'hubspot.companies', sourceRef: 'connector://fixture/companies',
      sourceViewContractCid: cid, schemaContractCid: cid}]};
  const site = {version: 'actql-installed-hubspot-site/0.1', apiOrigin: 'https://api.hubapi.com',
    credentialAuthorityId: 'fixture', credentialKeyId: 'key', credentialPrivateKeyPath: '/unused/key',
    environment: 'fixture', journalRoot: '/unused/journal', namespaceId: 'fixture',
    siteGeneration: 1, siteKey: 'fixture', tokenEnvironment: 'ACTQL_HUBSPOT_FIXTURE'};
  const metadata = {version: 'actql-hubspot-read-metadata/0.1', connectorId: 'fixture', portalId: '7',
    apiOrigin: site.apiOrigin, accountBody: Buffer.from('{"portalId":7}').toString('base64'),
    objects: [{resource: 'companies', objectType: 'companies', propertiesBody: Buffer.from('{"results":[]}').toString('base64')}]};
  const reads = [], reader = {async readJson(path) {
    reads.push(path);
    if (path === '/source.json') return source;
    if (path === '/site.json') return site;
    assert.equal(path, '/metadata.json'); return metadata;
  }, readText() {assert.fail('no replacement text read');}};
  return {source, reader, reads};
}

test('HubSpot Effect identity accepts existing Host aliases while preserving their exact immutable identity DATA', async () => {
  const f = aliasedSourceFixture();
  const original = await installedHubSpotEffectIdentityParts(profile(), undefined, undefined, {configurationReader: f.reader});
  assert.deepEqual(f.reads, ['/source.json', '/site.json', '/metadata.json']);
  assert.deepEqual(original[1].queryAliases, f.source.queryAliases);
  const aliases = original[1].queryAliases;
  assert(Object.isFrozen(aliases)); assert(Object.isFrozen(aliases[0]));
  f.source.queryAliases[0].name = 'changed';
  assert.equal(aliases[0].name, 'hubspot.companies');
  const changed = await installedHubSpotEffectIdentityParts(profile(), undefined, undefined, {configurationReader: f.reader});
  assert.notDeepEqual(changed, original);
  f.source.queryAliases[0].schemaContractCid = 'foreign';
  await assert.rejects(installedHubSpotEffectIdentityParts(profile(), undefined, undefined, {configurationReader: f.reader}),
    {message: 'InvalidPublicSourcePublication'});
});

test('HubSpot Effect load separates Host aliases before the same original provider constructor boundary', async () => {
  const f = aliasedSourceFixture(), marker = new Error('original Account constructor boundary');
  let constructors = 0;
  const construction = {configurationReader: f.reader,
    prepareEffectDriverConstruction() {assert.fail('no driver yet');},
    prepareDeclaration() {assert.fail('no declaration yet');},
    prepareNativeInput() {constructors++; throw marker;}};
  const moon = {clientProgramHubSpotEffectConstructorCapacity() {assert.fail('no driver quote yet');},
    clientProgramInstalledSourceReaderPolicy: () => [128, 4, 1],
    clientProgramHubSpotAccountConstructionCapacity() {assert.fail('no substituted constructor owner');},
    clientProgramHubSpotObjectConstructionCapacity() {assert.fail('no Catalog yet');}};
  await assert.rejects(loadInstalledHubSpotEffect(profile(), {moon, providerMoon: {}, construction,
    ledgerRoot: '/unused/ledger', runtimeBundleCid: cid}), error => error === marker);
  assert.equal(constructors, 1);
  assert.deepEqual(f.reads, ['/source.json', '/site.json', '/metadata.json']);
});
