import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {gunzipSync} from 'node:zlib';
import {checkRegistration, operation, pointer} from './graph-registration.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const aoa = read('spec/contracts/actql-aoa.json');
const registry = read(aoa.pipeline_registry_file);
const law = read('spec/dependencies/actql-graph-laws.json');
const protocol = read('spec/contracts/actql-protocol-schemas.json');
// Independent hashing of normalized machine preimages; no product output.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const body = aoa.execution_contracts[operation];

test('current Graph law is owned locally, not by an external AoA checkout', () => {
  const law = read('spec/dependencies/actql-graph-laws.json');
  assert.equal(law.manifest_version, 'actql-graph-laws/0.1');
  assert.equal(law.identity_law_id, 'actql.graph.definition-key-identity.v0.1');
  assert.equal(law.value_law_id, 'actql.graph.typed-snapshot-value.v0.1');
  assert.equal(cid(law), 'sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34');
  const owner = read('spec/contracts/actql-aoa.json');
  assert.deepEqual(owner.execution_contracts['BRIDGE.rows.to_graph'].dependencies.graph_law,
    {file: 'spec/dependencies/actql-graph-laws.json', pointer: '', cid: cid(law)});
  const {dataFiles} = localNodePackageInputs(process.cwd());
  assert.equal(dataFiles.filter(path => path === 'spec/dependencies/actql-graph-laws.json').length, 1);
  assert.ok(!dataFiles.includes('spec/dependencies/aoa-graph-laws.json'));
  const source = readFileSync('adapters/host-node/embedded-local.mjs', 'utf8');
  assert.ok(source.includes('spec/dependencies/actql-graph-laws.json'));
  assert.ok(!source.includes('spec/dependencies/aoa-graph-laws.json'));
});

test('independent complete snapshot preserves parallel edge keys, scoped identities and labels', () => {
  const fixture = read('portability/corpus/graph-owned-snapshot.json');
  assert.equal(cid(fixture.contract), fixture.expected_contract_cid);
  assert.equal(cid(fixture.snapshot), fixture.expected_snapshot_cid);
  const [version, contractCid, contract, nodes, edges] = fixture.snapshot;
  assert.equal(version, 'actql-graph-snapshot/0.1');
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
  for (const file of ['src/bounded_graph_snapshot/representation_wbtest.mbt',
    'src/query_integration/graph_snapshot_wbtest.mbt']) {
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
    identity_law_cid: cid(read('spec/dependencies/actql-graph-laws.json')),
    node_definitions: [{key_columns: [null], key_contracts: [{nullable: false, type: 'number'}],
      labels: {Node: ['id']}, name: 'N', properties: {id: {nullable: false, type: 'number'}}}],
    value_law_cid: cid(read('spec/dependencies/actql-graph-laws.json')),
    version: 'actql-graph-contract/0.1',
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
  assert.equal(environment.evidence_bundle_cid, 'sha256:93c1f1364afc2743e898037d4d4ed91dc0b35c89bc7cba36a02bb98856c645a1');
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
  const historical = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/pre-signed64-type-closure.json.gz')));
  const prior = historical.records;
  assert.equal(cid(prior['spec/contracts/actql-aoa.json'].execution_contracts[operation]),
    'sha256:d567ede4e421b6aaa6df39bf9fe03dfaaff129fb85ab9489faa6ffb61a8fa282');
  assert.equal(cid(prior['spec/dependencies/aoa-pipeline-registry.json']),
    'sha256:e22e68346562f75943e37453469d40c378bfe6994b124977f73addc1c23e76b6');
  assert.equal(historical.constructor_registry.source_revision,
    'f9720668eaec295295935f1c3cdd075df7e58434');
  assert.equal(cid(historical.constructor_registry.body),
    'sha256:a39ed49bed5ddd2dd6442a1dd92493a89fd47d563d36d255023e80ac10270041');
  assert.equal(historical.constructor_registry.cid, cid(historical.constructor_registry.body));
  const current = read('portability/corpus/signed64-identities.json');
  assert.deepEqual(body, current.graphExecution.body);
  assert.equal(canonical(body), current.graphExecution.canonicalPreimage);
  assert.equal(cid(body), current.graphExecution.cid);
  // The signed64 registry is a retained transition, not the later live registry.
  assert.equal(canonical(current.selectedRegistry.body), current.selectedRegistry.canonicalPreimage);
  assert.equal(cid(current.selectedRegistry.body), current.selectedRegistry.cid);
  assert.deepEqual(registry[operation], current.selectedRegistry.body[operation]);
  assert.equal(body.dependencies.graph_law.cid,
    'sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34');
  assert.equal(cid(prior['spec/contracts/actql-protocol-schemas.json'].schemas.canonical_value_contract),
    'sha256:2eeca1588b33cf19cfdbd1891820a6657ccd5a80cade9c159784d2e744cbbe6c');
  assert.equal(historical.constructor_value_grammar.source_revision,
    historical.constructor_registry.source_revision);
  assert.equal(cid(historical.constructor_value_grammar.body),
    'sha256:08c311d9a05b323ea6fde184981a965773ee71059c61bf3a830ab0e295c21947');
  assert.equal(historical.constructor_value_grammar.cid, cid(historical.constructor_value_grammar.body));
  assert.equal(body.dependencies.canonical_value_contract.cid, current.canonicalGrammar.cid);
  assert.equal(registry[operation].execution_contract.pointer, pointer);
  assert.equal(registry[operation].execution_contract.cid, cid(body));
});

test('Graph migration preserves the frozen prior registry and replaces the constructor contract', () => {
  assert.ok(registry[operation]);
  // Later scalar and graph additions cannot recreate an earlier registry by
  // deleting one operation and substituting a few current dependency pins.
  // Retain the exact published pre-constructor body and its independent CID.
  const historical = read('portability/fixtures/pipeline-registry-exact-strings.json');
  assert.equal(Object.hasOwn(historical[operation], 'execution_contract'), false);
  assert.deepEqual(historical['BRIDGE.rows.to_graph'],
    {inputs: ['relation', 'relation'], output: 'graph'});
  assert.equal(cid(historical), 'sha256:579c3a62fc22e6fea165bdd5714e3ca26206f606e43098434e84c02c8c0651cc');
  assert.deepEqual(historical[operation], {inputs: ['relation', 'relation'], output: 'graph'});
  assert.deepEqual(registry[operation].finite_inputs, {repeated_input: 'relation', minimum_inputs: 0});
  assert.equal(aoa.local_family_execution_profile.registry_operations.includes(operation), true);
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
  assert.equal(graph.properties.version.const, 'actql-graph-contract/0.1');
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
    r => {r[operation].execution_contract.pointer = '/execution_contracts/REL.values';},
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
    b => {b.params_schema.properties.contract.properties.version.const = 'actql-property-graph-contract/0.1';},
    b => {b.semantics.duplicates = 'keep_first';},
    b => {b.semantics.domain = 'current_graph_content_CID';},
    b => {b.dependencies.graph_law.cid = cid(protocol);},
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
