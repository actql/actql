import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkRegistration, operation, pointer} from './property-graph-registration.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const aoa = read('spec/contracts/actql-aoa.json');
const registry = read(aoa.pipeline_registry_file);
const law = read('spec/dependencies/actql-property-graph-laws.json');
const protocol = read('spec/contracts/actql-protocol-schemas.json');
// Independent hashing of normalized machine preimages; no product output.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const body = aoa.execution_contracts[operation];

test('current Property Graph law is owned locally, not by an external AoA checkout', () => {
  const law = read('spec/dependencies/actql-property-graph-laws.json');
  assert.equal(law.manifest_version, 'actql-property-graph-laws/0.1');
  assert.equal(law.identity_law_id, 'actql.property-graph.definition-key-identity.v0.1');
  assert.equal(law.value_law_id, 'actql.property-graph.typed-snapshot-value.v0.1');
  assert.equal(cid(law), 'sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc');
  const owner = read('spec/contracts/actql-aoa.json');
  assert.deepEqual(owner.execution_contracts['BRIDGE.rows.to_property_graph'].dependencies.property_graph_law,
    {file: 'spec/dependencies/actql-property-graph-laws.json', pointer: '', cid: cid(law)});
  for (const file of ['scripts/build-local-node-adapters.mjs', 'adapters/host-node/embedded-local.mjs']) {
    const source = readFileSync(file, 'utf8');
    assert.ok(source.includes('spec/dependencies/actql-property-graph-laws.json'));
    assert.ok(!source.includes('spec/dependencies/aoa-property-graph-laws.json'));
  }
});

test('independent complete snapshot preserves parallel edge keys, scoped identities and labels', () => {
  const fixture = read('portability/corpus/property-graph-owned-snapshot.json');
  assert.equal(cid(fixture.contract), fixture.expected_contract_cid);
  assert.equal(cid(fixture.snapshot), fixture.expected_snapshot_cid);
  const [version, contractCid, contract, nodes, edges] = fixture.snapshot;
  assert.equal(version, 'actql-property-graph-snapshot/0.1');
  assert.equal(contractCid, fixture.expected_contract_cid);
  assert.deepEqual(contract, fixture.contract);
  assert.deepEqual(edges.map(edge => edge.key), [[10], [11]]);
  assert.notDeepEqual(edges[0].id, edges[1].id);
  for (const edge of edges) {
    assert.deepEqual(edge.src, nodes[0].id);
    assert.deepEqual(edge.dst, nodes[0].id);
    assert.equal(edge.id.domain, contract.domain);
    assert.deepEqual(edge.id.key_types, [{kind: 'number'}]);
  }
  assert.deepEqual(contract.node_definitions[0].labels, {Node: ['name'], Person: []});
  assert.deepEqual(contract.edge_definitions[0].labels, {R: []});
  for (const file of ['src/bounded_graph_snapshot/property_snapshot_wbtest.mbt',
    'src/query_integration/property_graph_snapshot_wbtest.mbt']) {
    const source = readFileSync(file, 'utf8');
    assert.ok(source.includes(fixture.expected_contract_cid));
    assert.ok(source.includes(fixture.expected_snapshot_cid));
  }
});

test('SourceView Graph fixture owns independent schema and the complete CID chain', () => {
  const source = readFileSync('src/program_check/external_graph_capacity_fixture_wbtest.mbt', 'utf8');
  const line = source.split('\n').find(line => line.includes('"{\\"command_contracts\\":'));
  const environment = JSON.parse(JSON.parse(line.trim().slice(0, -1)));
  const catalog = environment.connector_catalogs[0];
  const envelope = catalog.contracts.find(entry => entry.kind === 'carrier_schema');
  const expected = {
    domain: 'sha256:' + '0'.repeat(64), edge_definitions: [],
    identity_law_cid: cid(read('spec/dependencies/actql-property-graph-laws.json')),
    node_definitions: [{key_columns: [null], key_contracts: [{nullable: false, type: 'number'}],
      labels: {Node: ['id']}, name: 'N', properties: {id: {nullable: false, type: 'number'}}}],
    value_law_cid: cid(read('spec/dependencies/actql-property-graph-laws.json')),
    version: 'actql-property-graph-contract/0.1',
  };
  assert.deepEqual(envelope.body, expected);
  const without = (value, self) => {
    const core = {...value}; delete core[self]; return cid(core);
  };
  for (const entry of catalog.contracts) assert.equal(entry.cid, without(entry, 'cid'));
  for (const view of catalog.source_views) {
    assert.equal(view.output.schema.cid, envelope.cid);
    assert.equal(view.contract_cid, without(view, 'contract_cid'));
  }
  assert.equal(catalog.catalog_cid, without(catalog, 'catalog_cid'));
  assert.equal(environment.evidence_bundle_cid, without(environment, 'evidence_bundle_cid'));
  assert.equal(environment.evidence_bundle_cid, 'sha256:600789313d7045af61cc8e70147cac3b86828abee26dd974f7d585a864812250');
  assert.ok(source.includes('"' + environment.evidence_bundle_cid + '"'));
  const sorted = entries => [...entries].sort((a, b) => a.id.localeCompare(b.id));
  assert.deepEqual(sorted(environment.contract_registry), sorted(catalog.contracts));
  assert.deepEqual(environment.source_views, catalog.source_views);
  // The wire sorts whole-member hashes; Catalog sorts self-CIDs. They are
  // distinct integrity rules, neither inferred from product Graph output.
  for (const name of ['contract_registry', 'source_views', 'connector_catalogs']) {
    const hashes = environment[name].map(cid);
    assert.deepEqual(hashes, [...hashes].sort());
  }
  for (const [name, self] of [['contracts', 'cid'], ['source_views', 'contract_cid']]) {
    const hashes = catalog[name].map(entry => entry[self]);
    assert.deepEqual(hashes, [...hashes].sort());
  }
});

test('constructor pins a distinct complete execution contract and exact shared dependencies', () => {
  checkRegistration(aoa, law, protocol, registry);
  assert.equal(cid(body), 'sha256:b00de8912497c6af1596debd1c59ee8d3477faf0391be40f64ac82ebc6d9ebb7');
  assert.equal(cid(registry), 'sha256:af8d2530f74cabec40daa30580dc0a036691a9d8875c0eb7a85ee40240768bcd');
  assert.equal(body.dependencies.property_graph_law.cid,
    'sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc');
  assert.equal(body.dependencies.canonical_value_contract.cid,
    'sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551');
  assert.equal(registry[operation].execution_contract.pointer, pointer);
  assert.equal(registry[operation].execution_contract.cid, cid(body));
});

test('adding keyed constructor preserves every prior registry entry and historical profile', () => {
  const {[operation]: added, ...previous} = registry;
  assert.ok(added);
  // Integrated String semantics change REL.values, not the Graph addition.
  assert.equal(cid(previous), 'sha256:579c3a62fc22e6fea165bdd5714e3ca26206f606e43098434e84c02c8c0651cc');
  assert.deepEqual(registry['BRIDGE.rows.to_graph'], {inputs: ['relation', 'relation'], output: 'graph'});
  assert.equal(aoa.local_family_execution_profile.registry_operations.includes(operation), false);
  assert.equal(aoa.local_family_execution_profile.registry_operations.length, 38);
  assert.deepEqual(body.finite_inputs, {repeated_input: 'relation', minimum_inputs: 0});
  // Variable occurrence count is deliberate; no invented pair of input edges.
  assert.equal(Object.hasOwn(body, 'inputs'), false);
});

test('params schema is closed and preserves complete definition types without a second value schema', () => {
  const schema = body.params_schema;
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required, ['contract', 'edges', 'nodes']);
  assert.deepEqual(schema.$defs, protocol.schemas.canonical_value_contract.$defs);
  const graph = schema.properties.contract;
  assert.equal(graph.additionalProperties, false);
  assert.equal(graph.properties.version.const, 'actql-property-graph-contract/0.1');
  for (const family of ['node_definitions', 'edge_definitions']) {
    const definition = graph.properties[family].items;
    assert.equal(definition.additionalProperties, false);
    assert.equal(definition.properties.key_contracts.minItems, 1);
    assert.equal(definition.properties.key_contracts.items.allOf[1].properties.nullable.const, false);
    assert.deepEqual(definition.properties.properties.additionalProperties, {$ref: '#/$defs/value_contract'});
    assert.equal(definition.properties.labels.type, 'object');
  }
  const node = schema.properties.nodes.items;
  assert.deepEqual(node.required, ['definition', 'input', 'keys', 'properties']);
  assert.equal(node.properties.keys.uniqueItems, true);
  const edge = schema.properties.edges.items;
  assert.deepEqual(edge.required, ['element', 'source', 'target']);
  assert.deepEqual(edge.properties.element, node);
  // Schema shape cannot certify typed coordinates/provenance by itself.
  assert.match(body.semantics.admission, /schema_validation_alone_is_not_admission/);
});

test('missing or forged registrations reject even if the containing registry is rehashed', () => {
  for (const mutate of [
    r => {delete r[operation];},
    r => {r[operation].finite_inputs.minimum_inputs = 2;},
    r => {r[operation].finite_inputs.repeated_input = 'graph';},
    r => {r[operation].execution_contract.file = 'other.json';},
    r => {r[operation].execution_contract.pointer = '/execution_contracts/BRIDGE.rows.to_graph';},
    r => {r[operation].execution_contract.cid = cid(law);},
  ]) {
    const changed = structuredClone(registry); mutate(changed);
    const owner = structuredClone(aoa); owner.pipeline_registry_cid = cid(changed);
    assert.throws(() => checkRegistration(owner, law, protocol, changed));
  }
});

test('rehashed weakening of admission uniqueness or shared type schemas cannot pass freshness', () => {
  for (const mutate of [
    b => {b.params_schema.additionalProperties = true;},
    b => {b.params_schema.properties.contract.properties.version.const = 'actql-graph-contract/0.1';},
    b => {b.semantics.duplicates = 'keep_first';},
    b => {b.semantics.domain = 'current_graph_content_CID';},
    b => {b.dependencies.property_graph_law.cid = cid(protocol);},
    b => {b.params_schema.$defs.value_contract = {};},
  ]) {
    const owner = structuredClone(aoa), changed = structuredClone(registry);
    mutate(owner.execution_contracts[operation]);
    const forged = cid(owner.execution_contracts[operation]);
    owner.target_registry_requirements[operation].execution_contract.cid = forged;
    changed[operation].execution_contract.cid = forged;
    owner.pipeline_registry_cid = cid(changed);
    assert.throws(() => checkRegistration(owner, law, protocol, changed));
  }
});
