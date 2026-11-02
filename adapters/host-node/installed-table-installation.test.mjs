// Installation acceptance, not public submit/approval acceptance. The real
// generic loaders and checker are used; loading must perform no Catalog I/O.
import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {inspect} from 'node:util';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {recordCheckpointApproval} from '../host-common/checkpoint-approval.mjs';
import {canonicalJson, contentCid, sourceReadAccountConfiguration} from './local-account-config.mjs';
import {installRowSourceAuthorization} from './installed-row-source.mjs';
import {installedSourceIdentity, loadInstalledSource} from './installed-source.mjs';
import {installedEffectIdentity, loadInstalledEffect} from './installed-effect.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {installedConnectors} from '../connectors-builtin/installations.generated.mjs';
import {checkInstalledTableSourceProfile, checkInstalledTableEffectProfile,
  installedTableReadSite, loadInstalledTableSource, loadInstalledTableEffect}
  from '../connectors/local/host/installed-local-table.mjs';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {tablePhysicalFixture} from './fixtures/table-physical-fixture.mjs';
import {createInstalledLoaderParent, installedFailureCode} from './fixtures/installed-loader-parent.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtimeUrl = new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const baseEnvironmentWire = (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const schemaWire = (await readFile(new URL('../connectors/local/iceberg/fixtures/presence-schema.json', import.meta.url), 'utf8')).trimEnd();
const schemaCid = 'sha256:8f5aaf81ac549e3e1b2724b949725bffe152abbae67451b31276b17f11c74e9a';
const connection = 'table-local', principalId = 'table-reader';
async function directory(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-table-installation-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
}
const common = root => ({connectorId: 'table', connection,
  // Deliberately nonexistent: installation cannot invoke Python or open files.
  python: join(root, 'uninstalled-python'),
  catalog: {database: join(root, 'catalog.db'), warehouse: join(root, 'warehouse'),
    catalogCid: cid('3'), limits: {bytes: 16777216, files: 256, operations: 32}},
  accountConfigurationWire: sourceReadAccountConfiguration({connection, resource: 'rows'})});
const sourceProfile = root => ({...common(root), version: 'actql-installed-local-table-source/0.1',
  targets: [{resource: 'rows', schemaWire, selector: {catalog_identity_cid: cid('3'),
    namespace: ['test'], table_name: 'rows',
    table_uuid: '00000000-0000-0000-0000-000000000001', schema_cid: schemaCid}}],
  limits: {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16}});

function effectProfile(root, approval = 'required') {
  const body = JSON.parse(baseEnvironmentWire);
  const targetRef = 'connector://table/catalog', mappingRef = 'mapping:table.catalog.v1';
  const manifestCid = withFixtureConnector(body, targetRef);
  const schema = {additional_properties: false, fields: {
    Id: {nullable: false, type: 'number'}, Name: {nullable: true, type: 'number'}},
    nullable: false, type: 'object'};
  const mapping = {connector_manifest_cid: manifestCid, conversions: [], mapping_ref: mappingRef,
    minimum_approval: approval, permission_rules: [{effect_kind: 'store', permissions: ['scope:store'],
      selector_class: 'none', write_fields: ['Name']}], primary_identity: 'Id',
    required_fields: [], required_permissions: [], resource_identity_cid: cid('b'),
    row_mapping: {Name: {field: 'id', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1', target_ref: targetRef, target_schema: schema,
    target_schema_identity: contentCid(schema), version: 'reference-v1', writable_fields: ['Name']};
  mapping.mapping_contract_cid = contentCid(mapping);
  body.mapping_contracts = [mapping];
  delete body.evidence_bundle_cid;
  const environmentWire = canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
  return {...common(root), version: 'actql-installed-local-table-effect/0.1', environmentWire,
    targets: [{effectId: 'save', resource: 'rows', targetRef, mappingRef,
      mappingCid: mapping.mapping_contract_cid, action: 'create', catalogCid: cid('3'),
      namespace: ['test'], tableName: 'rows', expectedTable: null,
      permissions: ['scope:store'], footprint: {version: 'fixture-only'}}], limits: {}};
}
async function installedProfile(t, value) {
  const root = await mkdtemp(join(tmpdir(), 'actql-table-installation-'));
  const path = join(root, 'profile.json');
  const parent = createInstalledLoaderParent({root, principalId, moon});
  t.after(async () => {await parent.close(); await rm(root, {recursive: true, force: true});});
  parent.open();
  const profile = value(root);
  await writeFile(path, JSON.stringify(profile));
  return {root, path, profile, parent, options: {root, principalId, moon, runtimeUrl, baseEnvironmentWire,
    installationServices: parent.services,
    resolveSecret() { assert.fail('Local Table installation needs no external credential'); }}};
}

test('explicit tables preserve real Local Table identity and generic loading', async t => {
  const connectorTable = createInstalledConnectorTable(installedConnectors);
  for (const [make, identity, load] of [
    [sourceProfile, installedSourceIdentity, loadInstalledSource],
    [effectProfile, installedEffectIdentity, loadInstalledEffect],
  ]) {
    const f = await installedProfile(t, make);
    assert.equal(await identity(f.path, {connectorTable}), await identity(f.path));
    const adapter = await f.parent.load(load, f.path, {...f.options, connectorTable});
    try {
      assert.equal(adapter.connectorBindings[0].connectorId, 'table');
      assert.match(adapter.connectorBindings[0].bindingCid, /^sha256:[0-9a-f]{64}$/u);
      if (load === loadInstalledSource) {
        assert.equal(adapter.connectorRegistration, 'local');
        assert.equal(adapter.connectorRevision, 'local/0.1');
      } else {
        const [{capabilityCid, ...selector}] = adapter.effectSelectors;
        assert.match(capabilityCid, /^sha256:[0-9a-f]{64}$/u);
        assert.deepEqual([selector], [{kind: 'store',
          target: 'connector://table/catalog', mappingRef: 'mapping:table.catalog.v1',
          mappingCid: f.profile.targets[0].mappingCid, effectId: 'save'}]);
      }
    } finally {
      await adapter.close();
      await adapter.close();
    }
  }
});

test('Table Source loads through the generic Host without physical I/O', async t => {
  const f = await installedProfile(t, sourceProfile);
  const identity = await installedSourceIdentity(f.path);
  assert.match(identity, /^sha256:[0-9a-f]{64}$/u);
  const adapter = await f.parent.load(loadInstalledSource, f.path, f.options);
  try {
    assert.equal(adapter.connectorRegistration, 'local');
    assert.equal(adapter.connectorRevision, 'local/0.1');
    assert.equal(adapter.sourceAccess.connection, connection);
    assert.equal(adapter.tableReadTargets[0].selector.table_name, 'rows');
    assert.equal(typeof adapter.open, 'function');
    assert.equal(typeof adapter.prepare, 'function');
    const document = JSON.parse(adapter.environmentWire);
    assert.ok(moon.clientProgramCheckEnvironment(adapter.environmentWire,
      document.evidence_bundle_cid, false, false, true, false, false, false, false));
    assert.deepEqual((await readdir(f.root)).sort(), ['profile.json']);
    assert.equal(await installedSourceIdentity(f.path), identity);
  } finally { await adapter.close(); }
});

test('Local Table cannot bypass the common bound construction even with claimed implementation DATA', async t => {
  const f = await installedProfile(t, sourceProfile);
  await assert.rejects(loadInstalledTableSource(f.profile, f.options),
    {code: 'InstalledTableSourceConstructionUnavailable'});
  const effect = effectProfile(f.root);
  await assert.rejects(loadInstalledTableEffect(effect, {...f.options, ledgerRoot: join(f.root, 'ledger')}),
    {code: 'InstalledTableEffectConstructionUnavailable'});
  // Domain-only refusal test: this facade is never invoked and establishes
  // no lifecycle success. Actual construction is covered by the tests above.
  const construction = Object.freeze({createTableSource() {assert.fail('invalid inventory reached construction');}});
  for (const installation of [{registration: 'local', revision: 'local/0.1'},
    {registration: 'local', revision: 'local/0.1', implementationFiles: []}]) {
    await assert.rejects(loadInstalledTableSource(f.profile, {...f.options, installation, construction}),
      {code: 'InvalidConnectorImplementationInventory'});
  }
  assert.deepEqual((await readdir(f.root)).sort(), ['profile.json'],
    'Missing implementation binding cannot create a Catalog, Ledger or authorization store');
});

test('Table Effect loads its admitted Mapping and existing runtime hooks without publication', async t => {
  const f = await installedProfile(t, effectProfile);
  assert.match(await installedEffectIdentity(f.path), /^sha256:[0-9a-f]{64}$/u);
  const adapter = await f.parent.load(loadInstalledEffect, f.path, f.options);
  try {
    assert.equal(typeof adapter.prepareCaptured, 'function');
    assert.equal(typeof adapter.prepareRecovered, 'function');
    assert.equal(adapter.connectorBindings[0].connectorId, 'table');
    assert.equal(JSON.parse(adapter.environmentWire).mapping_contracts[0].minimum_approval, 'required');
    // Only the existing Effect Ledger directory may be installed. A missing
    // Python executable cannot be masked by an accidental physical invocation.
    assert.deepEqual((await readdir(f.root)).sort(), ['profile.json', 'state']);
    assert.deepEqual(await readdir(join(f.root, 'state', 'effects', 'ledger')), []);
  } finally { await adapter.close(); }
});

test('Table installation refuses invalid closed profiles and budgets before I/O', async t => {
  const root = await directory(t);
  for (const profile of [sourceProfile(root), effectProfile(root)]) {
    const check = profile.version.includes('-source/')
      ? checkInstalledTableSourceProfile : checkInstalledTableEffectProfile;
    assert.throws(() => check({...profile, unknown: true}), {code: 'InvalidInstalledTableProfile'});
    for (const limits of [null, [], '1']) {
      assert.throws(() => check({...profile, limits}), {code: 'InvalidInstalledTableProfile'});
    }
    assert.throws(() => check({...profile, limits: {...profile.limits, typo: 1}}));
  }
  const profile = effectProfile(root);
  for (const limits of [{maxWork: 0}, {material: null}, {reservation: {byte: 1}},
    JSON.parse('{"__proto__":1}'), {material: {maxDepth: 0}},
    {material: {maxWireBytes: 65537}}, {material: {maxNodes: 4097}},
    {material: {maxDepth: 17}}, {material: {maxWork: 2147483648}}]) {
    assert.throws(() => checkInstalledTableEffectProfile({...profile, limits}),
      {code: 'InvalidInstalledTableEffectLimits'});
  }
  assert.deepEqual(await readdir(root), []);
});

test('Table Effect refuses absent or non-required approval Mappings before installing a Ledger', async t => {
  for (const variation of ['none', 'mapping', 'target']) {
    await t.test(variation, async t => {
      const f = await installedProfile(t, root => effectProfile(root, variation === 'none' ? 'none' : 'required'));
      if (variation === 'mapping') f.profile.targets[0].mappingCid = cid('f');
      if (variation === 'target') f.profile.targets[0].targetRef = 'connector://foreign/catalog';
      await writeFile(f.path, JSON.stringify(f.profile));
      await assert.rejects(f.parent.load(loadInstalledEffect, f.path, f.options), installedFailureCode('InstalledTableMappingNotInstalled'));
      assert.deepEqual(await readdir(f.root), ['profile.json']);
    });
  }
});

test('Table exact physical names do not alias through configuration NFC identities', async t => {
  for (const [make, identity] of [[sourceProfile, installedSourceIdentity], [effectProfile, installedEffectIdentity]]) {
    const f = await installedProfile(t, make), target = f.profile.targets[0];
    if (target.selector) target.selector.table_name = 'cafe\u0301';
    else target.tableName = 'cafe\u0301';
    await writeFile(f.path, JSON.stringify(f.profile));
    const decomposed = await identity(f.path);
    if (target.selector) target.selector.table_name = 'caf\u00e9';
    else target.tableName = 'caf\u00e9';
    await writeFile(f.path, JSON.stringify(f.profile));
    assert.notEqual(await identity(f.path), decomposed);
  }
});

test('Table profile validation freezes an independent copy without rewriting data', async t => {
  const root = await directory(t), profile = sourceProfile(root);
  profile.targets[0].selector.table_name = 'cafe\u0301';
  const checked = checkInstalledTableSourceProfile(profile);
  profile.targets[0].selector.table_name = 'changed';
  assert.equal(checked.targets[0].selector.table_name, 'cafe\u0301');
  assert.ok(Object.isFrozen(checked.targets[0].selector));
});

test('Table local Site accepts opaque installed read authority and refuses a copied decision', async t => {
  const root = await directory(t);
  const authorization = await installRowSourceAuthorization({root, principalId,
    connectorRegistration: 'table', accountConfiguration:
      sourceReadAccountConfiguration({connection, resource: 'rows'})});
  const site = installedTableReadSite({connection, authorization, principalId,
    targets: () => [{resource: 'rows'}]});
  const decision = await authorization.authorize('acquisition',
    {operation: 'read', connection, resource: 'rows'}, {subjectCid: cid('a')});
  const grant = {operation: 'table.read', decision, resource: 'rows', runInvocationCid: cid('1'),
    dispatchRequestCid: cid('2'), maxUses: 1};
  assert.deepEqual(site.issueReadGrant(grant), {runInvocationCid: cid('1'), dispatchRequestCid: cid('2')});
  assert.throws(() => site.issueReadGrant({...grant, decision: {...decision}}),
    {code: 'TableSourceReadGrantNotAuthorized'});
  site.close();
  assert.throws(() => site.issueReadGrant(grant), {code: 'InstalledTableSiteClosed'});
});

test('Table local Site checks exact opaque Checkpoint binding, principal and field subset', () => {
  const target = {version: 'actql-installed-table-read-target/0.1', catalog_cid: cid('a'),
    selector: {table_name: 'cafe\u0301'}, selector_cid: cid('b'), resource: 'rows', fields: ['id', 'p']};
  const site = installedTableReadSite({connection, principalId,
    authorization: {issued: () => false, context: {contextCid: cid('c')}}, targets: () => [target]});
  const tuple = {connection, resource: 'rows', operation: 'read'};
  const issue = facts => recordCheckpointApproval(Object.freeze({action: 'dispatch',
    boundary: 'acquisition', basis: 'resumed_approval', tuple}), facts);
  const facts = {principalId, readTuple: tuple, physicalBinding: {...target, fields: ['id']}};
  const decision = issue(facts);
  site.admitCheckpointReadApproval(decision);
  assert.ok(site.issueReadGrant({operation: 'table.read', decision, resource: 'rows',
    runInvocationCid: cid('1'), dispatchRequestCid: cid('2'), maxUses: 1}));
  for (const changed of [{...facts, principalId: 'other'},
    {...facts, physicalBinding: {...target, selector: {table_name: 'caf\u00e9'}}},
    {...facts, physicalBinding: {...target, fields: []}},
    {...facts, physicalBinding: {...target, fields: ['unknown']}}]) {
    assert.throws(() => site.admitCheckpointReadApproval(issue(changed)),
      {code: 'TableSourceReadApprovalNotAdmitted'});
  }
  assert.throws(() => site.admitCheckpointReadApproval(Object.freeze({...decision})),
    {code: 'TableSourceReadApprovalNotAdmitted'});
  site.close();
});

test('Table public Local reader acquires a real generation and leaves it after Run completion', async t => {
  const f = await tablePhysicalFixture(t);
  const expected = [{id: 1, p: 'e\u0301\r\n'}, {id: 2, p: null}, {id: 3}, {id: 3}];
  const committed = await f.bridge.execute(f.prepare(f.operation(), expected), {useCid: cid('7')});
  const receipt = JSON.parse(committed.observation.body).result;
  const profile = sourceProfile(f.root);
  profile.python = process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../.venv-table/bin/python', import.meta.url));
  profile.catalog = f.catalog;
  profile.targets[0].selector.table_uuid = receipt.table_uuid;
  const sourceProfilePath = join(f.root, 'source-profile.json');
  await writeFile(sourceProfilePath, JSON.stringify(profile));
  const accountConfiguration = canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'table-public-reader', entries: [{entry_id: 'run', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}]});
  const keys = generateKeyPairSync('ed25519');
  const observations = [];
  const options = {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: join(f.root, 'host'), sourceProfilePath,
      authorization: {accountConfiguration, observe: (name, detail) => observations.push({name, detail}),
        reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
        hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}}}};
  const program = {version: 'actql/0.1', id: 'public-table-reader', stages: [{id: 'read',
    inputs: {input: {connector: 'table', resource: 'rows'}},
    steps: [{filter: 'id >= 0', as: 'kept'}, {select: ['id'], as: 'output'}],
    results: {rows: {from: 'output', fields: ['id']}}},
    {id: 'compute', inputs: {rows: {result: {stage: 'read', result: 'rows'}}},
      steps: [{derive: {doubled: 'id * 2'}, as: 'derived'},
        {select: ['id', 'doubled'], as: 'output'}],
      results: {rows: {from: 'output', fields: ['id', 'doubled']}}}],
    results: {answer: {from: {stage: 'compute', result: 'rows'}}}};
  const expectedResult = expected.map(({id}) => ({id, doubled: id * 2}));
  // Iceberg file order is not a query-order contract. Compare the complete
  // multiset (including duplicates), not a promise about physical row order.
  const rows = async result => (await result.all()).sort((left, right) => left.id - right.id);
  const client = await connectEmbeddedLocal(options).catch(error => {
    assert.fail(error.primaryFailure?.stack ?? error.cause?.stack ?? error.stack);
  });
  let firstRunRef;
  try {
    const run = await client.startSource(JSON.stringify(program),
      {format: 'json', submissionRef: client.newSubmission()});
    firstRunRef = run.ref;
    const state = await run.wait({signal: AbortSignal.timeout(30000)});
    if (state.status !== 'succeeded') t.diagnostic(inspect(observations, {depth: 8}));
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(await rows(run.result('answer')), expectedResult);
    assert.equal((await run.status()).status, 'succeeded');
    assert.deepEqual(await rows((await client.attach(run.ref)).result('answer')), expectedResult);
  } finally { await client.close(); }
  assert.deepEqual(JSON.parse(JSON.stringify((await f.bridge.read(receipt, f.mapping)).result)), expected);
  const later = await connectEmbeddedLocal(options);
  try {
    const run = await later.startSource(JSON.stringify(program),
      {format: 'json', submissionRef: later.newSubmission()});
    assert.notDeepEqual(run.ref, firstRunRef,
      'A fresh submission reads the durable Table through a different Run');
    const state = await run.wait({signal: AbortSignal.timeout(30000)});
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(await rows(run.result('answer')), expectedResult);
  } finally { await later.close(); }
});
