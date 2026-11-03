import assert from 'node:assert/strict';
import {mkdtemp, mkdir, open, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {inspectDeclaredProjectCatalog} from './declared-project-catalog.mjs';

assert.ok(process.env.ACTQL_TEST_PROJECT_PROFILE_RUNTIME, 'Select the actual matching builtin Common runtime');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_PROFILE_RUNTIME));
const templates = ['churn-risk-mock', 'deal-review-mock'];
const invalid = {code: 'InvalidInstalledMockCatalog'};
const commonRefusal = {code: 'MoonBitHostFailure'};

// The exact generated declaration is the input. Only its catalog is written:
// the data, answers and model task files deliberately do not exist here.
// This boundary proves declaration admission, not a fixture read or execution.
async function fixture(t, template = templates[0]) {
  const files = projectTemplateFiles(template);
  const configuration = JSON.parse(files['actql.config.json']);
  const directory = await mkdtemp(join(tmpdir(), 'actql-declared-catalog-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const catalogFile = configuration.mock.catalog;
  const catalogPath = resolve(directory, catalogFile);
  await mkdir(dirname(catalogPath), {recursive: true});
  const connectionsWire = files['connectors.json'];
  const catalogWire = files['mock/catalog.json'];
  const state = {opens: [], currentChecks: 0};
  async function load({catalog = catalogWire, connections = connectionsWire} = {}) {
    const originalWire = typeof catalog === 'string' ? catalog : JSON.stringify(catalog);
    const originalConnections = checked(moon.clientProjectConnectionsAdmit(
      typeof connections === 'string' ? connections : JSON.stringify(connections)));
    await writeFile(catalogPath, originalWire);
    state.opens.length = 0;
    const result = await inspectDeclaredProjectCatalog(moon, {
      directory, catalogFile, dataFile: configuration.mock.data, connections: originalConnections,
      assertCurrent() {state.currentChecks++;},
      openFile(path, ...args) {
        state.opens.push(path);
        assert.equal(path, catalogPath, 'catalog admission must not open fixture data or any other file');
        return open(path, ...args);
      },
    });
    assert.equal(result.originalWire, originalWire);
    assert.equal(moon.clientProjectCatalogOriginalWire(result.original), originalWire);
    assert.deepEqual(state.opens, [catalogPath]);
    return result;
  }
  async function rejects(mutate, expected = invalid) {
    const catalog = JSON.parse(catalogWire);
    mutate(catalog);
    await assert.rejects(load({catalog}), expected);
    assert.deepEqual(state.opens, [catalogPath], 'rejection must precede every fixture read');
  }
  return {files, configuration, directory, catalogWire, connectionsWire, catalogPath, state, load, rejects};
}

function writableTarget(result) {
  const owners = result.sources.filter(source => source.writes.length !== 0);
  assert.equal(owners.length, 1);
  const source = owners[0];
  assert.equal(source.writes.length, 1);
  const spec = source.writes[0];
  return {connection: source.catalogue.connection, connector: source.catalogue.connectorId,
    aliases: source.catalogue.updateAliases, spec, mapping: JSON.parse(spec.mappingWire)};
}

for (const template of templates) {
  test(`actual catalog admits the exact ${template} declarations without fixture data`, async t => {
    const f = await fixture(t, template), result = await f.load();
    const declared = JSON.parse(f.catalogWire).connections;
    assert.equal(result.sources.length, Object.keys(declared).length);
    assert.ok(Object.isFrozen(result) && Object.isFrozen(result.sources));
    for (const source of result.sources) {
      const entry = declared[source.catalogue.connection];
      const restored = JSON.parse(moon.clientProgramRowSourceDeclarationJson(source.declaration));
      assert.equal(source.wire, moon.clientProgramRowSourceDeclarationJson(source.declaration));
      assert.equal(restored.connector_id, source.catalogue.connectorId);
      assert.match(restored.catalog_cid, /^sha256:[0-9a-f]{64}$/u);
      assert.deepEqual(restored.views.map(view => view.resource).sort(), entry.views.map(view => view.resource).sort());
      assert.deepEqual(source.catalogue.queryAliases, entry.query_aliases);
      assert.deepEqual(source.physical.map(binding => ({resource: binding.resource,
        items_path: binding.itemsPath, key_path: binding.keyPath, primary_identity: binding.primaryIdentity})),
      entry.data.map(({resource, items_path, key_path, primary_identity}) =>
        ({resource, items_path, key_path, primary_identity})));
      assert.ok(Object.isFrozen(source) && Object.isFrozen(source.physical) && Object.isFrozen(source.writes));
    }
    const target = writableTarget(result);
    const expected = declared.salesforce.writes[0];
    assert.equal(target.connection, 'salesforce');
    assert.equal(target.mapping.target_ref, 'connector://salesforce/' + expected.resource);
    assert.equal(target.mapping.primary_identity, expected.primary_identity);
    assert.deepEqual(target.mapping.writable_fields, [...expected.writable_fields].sort());
    assert.equal(target.mapping.minimum_approval, 'required');
    assert.deepEqual(target.mapping.permission_rules[0].permissions, [expected.permission]);
    assert.equal(target.spec.observe_permission, expected.observe_permission);
    assert.deepEqual(target.aliases, expected.aliases.map(name => ({name, resource: expected.resource})));
  });

  test(`actual ${template} writable target is independent of connection and catalog order`, async t => {
    const f = await fixture(t, template), original = writableTarget(await f.load());
    const catalog = JSON.parse(f.catalogWire), connections = JSON.parse(f.connectionsWire);
    const reverse = value => Object.fromEntries(Object.entries(value).reverse());
    catalog.connections = reverse(catalog.connections);
    assert.deepEqual(writableTarget(await f.load({catalog})), original);
    connections.connections = reverse(connections.connections);
    assert.deepEqual(writableTarget(await f.load({connections})), original);
    assert.deepEqual(writableTarget(await f.load({catalog, connections})), original);
  });
}

test('actual file declarations preserve separate physical strings and logical keyed Content views', async t => {
  const f = await fixture(t, 'deal-review-mock'), result = await f.load();
  const source = result.sources.find(value => value.catalogue.connection === 'drive');
  const entry = JSON.parse(f.catalogWire).connections.drive;
  assert.deepEqual(source.fileBindings, entry.file_bindings);
  assert.equal(source.physical.length, 1);
  assert.deepEqual(source.physical[0].schema, entry.data[0].schema);
  assert.notStrictEqual(source.physical[0].declaration, source.declaration);
  const physical = JSON.parse(moon.clientProgramRowSourceDeclarationJson(source.physical[0].declaration));
  assert.deepEqual(physical.views[0].fields.slice().sort(), Object.keys(entry.data[0].schema).sort());
  const listing = source.catalogue.views.find(view => view.resource === 'files');
  const content = source.catalogue.views.find(view => view.resource === 'contents');
  assert.deepEqual(JSON.parse(listing.schema_wire), entry.views[0].schema);
  assert.deepEqual(JSON.parse(content.schema_wire), entry.views[1].schema);
  assert.deepEqual(JSON.parse(content.request_schema_wire), entry.views[1].request_schema);
  assert.deepEqual(JSON.parse(content.acquisition_wire), entry.views[1].acquisition);
  const listingFacts = JSON.parse(listing.facts_wire), contentFacts = JSON.parse(content.facts_wire);
  assert.equal(listingFacts.file_listing.admitted_scope_contract_cid, source.scopeCid);
  assert.equal(contentFacts.file_content.admitted_scope_contract_cid, source.scopeCid);
  assert.equal(contentFacts.file_content.representation, 'exact_stored_bytes');
  assert.equal(contentFacts.lookup_capacity.max_rows_per_key, 1);
  assert.deepEqual(source.writes, []);
});

test('actual catalog refuses missing extra and foreign connections before fixture I/O', async t => {
  const f = await fixture(t);
  await f.rejects(catalog => {delete catalog.connections.salesforce;});
  await f.rejects(catalog => {catalog.connections.foreign = structuredClone(catalog.connections.salesforce);});
  await f.rejects(catalog => {
    catalog.connections.foreign = catalog.connections.salesforce;
    delete catalog.connections.salesforce;
  });
  await f.rejects(catalog => {catalog.connections = {};});
});

test('actual catalog refuses missing duplicate and foreign resource bindings before fixture I/O', async t => {
  const f = await fixture(t);
  for (const mutate of [
    catalog => {catalog.connections.salesforce.views = [];},
    catalog => {catalog.connections.salesforce.views.push(structuredClone(catalog.connections.salesforce.views[0]));},
    catalog => {catalog.connections.salesforce.data = [];},
    catalog => {catalog.connections.salesforce.data.push(structuredClone(catalog.connections.salesforce.data[0]));},
    catalog => {catalog.connections.salesforce.data[0].resource = 'usage_30d';},
    catalog => {catalog.connections.salesforce.query_aliases[0].resource = 'usage_30d';},
    catalog => {catalog.connections.salesforce.writes[0].resource = 'usage_30d';},
    catalog => {catalog.connections.snowflake.query_aliases[0].name = 'salesforce.accounts';},
    catalog => {catalog.connections.salesforce.writes.push({...catalog.connections.salesforce.writes[0], aliases: ['other.Account']});},
  ]) await f.rejects(mutate);
  const files = await fixture(t, 'deal-review-mock');
  for (const mutate of [
    catalog => {catalog.connections.drive.file_bindings[0].listing_resource = 'Opportunity';},
    catalog => {catalog.connections.drive.file_bindings[0].content_resource = 'missing';},
    catalog => {catalog.connections.drive.file_bindings[0].data_resource = 'contents';},
    catalog => {catalog.connections.drive.file_bindings.push(structuredClone(catalog.connections.drive.file_bindings[0]));},
  ]) await files.rejects(mutate);
});

test('actual catalog closes every declaration and binding object before fixture I/O', async t => {
  const f = await fixture(t, 'deal-review-mock');
  for (const select of [
    catalog => catalog.connections.salesforce,
    catalog => catalog.connections.salesforce.views[0],
    catalog => catalog.connections.salesforce.query_aliases[0],
    catalog => catalog.connections.salesforce.data[0],
    catalog => catalog.connections.salesforce.writes[0],
    catalog => catalog.connections.drive.file_bindings[0],
  ]) await f.rejects(catalog => {select(catalog).undeclared = true;});
  await f.rejects(catalog => {catalog.undeclared = true;}, commonRefusal);
});

test('actual catalog rejects invalid primary identities and malformed declared paths without reading their data', async t => {
  const f = await fixture(t);
  for (const identity of ['', 'missing', 'Risk_Reason__c']) {
    await f.rejects(catalog => {catalog.connections.salesforce.data[0].primary_identity = identity;});
  }
  await f.rejects(catalog => {catalog.connections.salesforce.writes[0].primary_identity = 'name';});
  for (const field of ['items_path', 'key_path']) for (const path of [null, 'rows', [], [''], [0], ['a\0b'], Array(17).fill('x')]) {
    await f.rejects(catalog => {catalog.connections.salesforce.data[0][field] = path;});
  }
  // Whether a well-formed path exists, and whether its key value matches, is
  // the later original-document Owner's job, not metadata schema inference.
  const declared = JSON.parse(f.catalogWire);
  declared.connections.salesforce.data[0].key_path = ['renamed', 'key'];
  const result = await f.load({catalog: declared});
  assert.deepEqual(result.sources.find(source => source.catalogue.connection === 'salesforce').physical[0].keyPath,
    ['renamed', 'key']);
});

test('actual Common rejects unknown writable columns and invalid declared schema types before fixture I/O', async t => {
  const f = await fixture(t);
  for (const fields of [['missing'], ['id'], ['Churn_Risk__c', 'missing']]) {
    await f.rejects(catalog => {catalog.connections.salesforce.writes[0].writable_fields = fields;}, commonRefusal);
  }
  await f.rejects(catalog => {catalog.connections.salesforce.views[0].schema.Churn_Risk__c.type = 'invented';}, commonRefusal);
  for (const fields of [null, 'Churn_Risk__c', [], [false], ['Churn_Risk__c', 'Churn_Risk__c']]) {
    await f.rejects(catalog => {catalog.connections.salesforce.writes[0].writable_fields = fields;});
  }
  for (const [field, value] of [['permission', false], ['observe_permission', ''], ['approval', 'none'], ['aliases', []]]) {
    await f.rejects(catalog => {catalog.connections.salesforce.writes[0][field] = value;});
  }
});

test('actual file bindings reject unknown physical columns types and overridden capability facts', async t => {
  const f = await fixture(t, 'deal-review-mock');
  for (const field of ['identity_field', 'name_field', 'version_field', 'media_type_field', 'content_utf8_field', 'path_field']) {
    await f.rejects(catalog => {catalog.connections.drive.file_bindings[0][field] = 'missing';});
  }
  for (const name of ['id', 'name', 'version', 'media_type', 'content_utf8']) {
    await f.rejects(catalog => {catalog.connections.drive.data[0].schema[name].type = 'int64';});
  }
  for (const index of [0, 1]) {
    await f.rejects(catalog => {catalog.connections.drive.views[index].facts = {};});
  }
});

test('actual Common rejects duplicate catalog keys including nested unused values', async t => {
  const f = await fixture(t);
  for (const catalog of [
    f.catalogWire.replace('"connections": {', '"connections": {}, "connections": {'),
    f.catalogWire.replace('"resource": "Account"', '"resource": "other", "resource": "Account"'),
    f.catalogWire.replace('"resource": "Account"', '"unused": {"same": 1, "same": 2}, "resource": "Account"'),
  ]) {
    assert.notEqual(catalog, f.catalogWire);
    await assert.rejects(f.load({catalog}), commonRefusal);
    assert.deepEqual(f.state.opens, [f.catalogPath]);
  }
});

// Actual Common DATA admission over replacement files, not a simulated query
// or installed Source/Run acceptance. The end-to-end reconnect test is separate.
for (const template of templates) test(`actual ${template} model admits replacement file data without changing declarations`, async t => {
  const f = await fixture(t, template), catalog = await f.load();
  const source = catalog.sources.find(value => value.writes.length === 1);
  const physical = source.physical.find(value => value.resource === source.writes[0].resource);
  const path = resolve(f.directory, f.configuration.mock.data);
  const initial = JSON.parse(f.files['mock/data.json']);
  const first = initial[source.catalogue.connection][physical.resource].rows[0];
  const identity = first[physical.primaryIdentity];
  const observeFile = async () => {
    const bytes = await readFile(path);
    const document = checked(moon.clientProgramRelationAdmitDocument(bytes, 1048576, 4096, 32, 100, 16777216));
    const rows = new Map();
    for (const owner of catalog.sources) for (const model of owner.physical) {
      rows.set(model, checked(moon.clientProgramRelationProjectTargetDocument(document,
        model.declaration, model.resource, model.itemsPath, model.keyPath,
        model.primaryIdentity, model.writableFields)));
    }
    const row = checked(moon.clientProgramRelationObserveTarget(rows.get(physical), physical.declaration, identity));
    return {row, before: moon.clientProgramRelationTargetBefore(row), version: moon.clientProgramRelationTargetVersion(row)};
  };
  await writeFile(path, JSON.stringify(initial));
  const original = await observeFile();
  first.name = 'Replacement customer, same declared model';
  await writeFile(path, JSON.stringify(initial));
  const replaced = await observeFile();
  assert.notEqual(replaced.before, original.before);
  assert.notEqual(replaced.version, original.version);
  assert.equal(JSON.parse(replaced.before).name, first.name);
  assert.equal(JSON.parse(original.before).name.includes('Replacement'), false, 'old original was not mutated or rebound');
  const fresh = await f.load();
  assert.deepEqual(fresh.sources.map(value => value.wire), catalog.sources.map(value => value.wire),
    'the same model declarations do not depend on sample rows');
  first.unexpected_column = 'reject before execution';
  await writeFile(path, JSON.stringify(initial));
  await assert.rejects(observeFile(), commonRefusal);
  delete first.unexpected_column;
  first.name = 123;
  await writeFile(path, JSON.stringify(initial));
  await assert.rejects(observeFile(), commonRefusal);
});
