import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkRegistration, operation, pointer} from './property-graph-registration.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const aoa = read('spec/contracts/actql-aoa.json');
const registry = read(aoa.pipeline_registry_file);
const law = read('spec/dependencies/aoa-property-graph-laws.json');
const protocol = read('spec/contracts/actql-protocol-schemas.json');
// Independent hashing of normalized machine preimages; no product output.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const body = aoa.execution_contracts[operation];

test('constructor pins a distinct complete execution contract and exact shared dependencies', () => {
  checkRegistration(aoa, law, protocol, registry);
  assert.equal(cid(body), 'sha256:6f84b787b55f3a84c6b420046e3f9346ac9019627bc852311fcf8d9f577dec03');
  assert.equal(cid(registry), 'sha256:7e6ae70262de7974f1145a440bd06c2dd1c9c2f56e373676c89d4da3f257f356');
  assert.equal(body.dependencies.property_graph_law.cid,
    'sha256:663bbb3096723cb38face189087f79ab37e9b7d34ec994937b3bff8334c405b1');
  assert.equal(body.dependencies.canonical_value_contract.cid,
    'sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551');
  assert.equal(registry[operation].execution_contract.pointer, pointer);
  assert.equal(registry[operation].execution_contract.cid, cid(body));
});

test('adding keyed constructor preserves every prior registry entry and historical profile', () => {
  const {[operation]: added, ...previous} = registry;
  assert.ok(added);
  assert.equal(cid(previous), 'sha256:fda8b3f12e5a42673160163c097f9626b09d999ee3f4889b96e549c6e5e24332');
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
