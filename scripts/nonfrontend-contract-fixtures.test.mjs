import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Hash normative JSON and independently authored preimages, not product output.
const read = path => readFileSync(path, 'utf8');
const json = path => JSON.parse(read(path));
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const hasPin = (path, expected) => assert.ok(read(path).includes('"' + expected + '"'), path);
const fixtureWire = (path, name) => {
  const match = read(path).match(new RegExp('let ' + name + ' : String =\\s*\\n\\s*#\\|([^\\n]+)'));
  assert.ok(match, name);
  return match[1];
};
const fixtureBody = (path, name) => JSON.parse(fixtureWire(path, name));

test('resident physical acquisition fixtures retain complete normative query dependencies', () => {
  const path = 'src/platform_native/remote_resident_source_compute_tests/source_compute_wbtest.mbt';
  for (const [name, contract] of [
    ['resident_compute_query_contract', 'actql-query-acquisition.json'],
    ['resident_compute_query_evidence_contract', 'actql-query-process-evidence.json'],
    ['resident_compute_query_two_receipt_contract', 'actql-query-two-receipt.json'],
  ]) assert.deepEqual(fixtureBody(path, name), json('spec/contracts/' + contract));
  const environment = fixtureBody(
    'src/platform_native/remote_resident_source_compute_tests/source_fixture_wbtest.mbt',
    'resident_effect_source_environment');
  assert.deepEqual(environment.connector_capabilities[0].capability_contract_cids,
    [cid(json('spec/contracts/actql-query-two-receipt.json'))]);
});

test('resident physical Source environments advertise their exact normative two-receipt capability', () => {
  const expected = cid(json('spec/contracts/actql-query-two-receipt.json'));
  for (const [file, name] of [
    ['source_fixture_wbtest.mbt', 'resident_effect_source_environment'],
    ['effect_completion_free_wbtest.mbt', 'native_completion_free_environment'],
  ]) {
    const wire = fixtureWire('src/platform_native/remote_resident_source_compute_tests/' + file, name);
    const body = JSON.parse(wire);
    assert.equal(wire, canonical(body));
    const memberCids = body.connector_capabilities.map(cid);
    assert.deepEqual(memberCids, [...memberCids].sort());
    const {evidence_bundle_cid: original, ...preimage} = body;
    assert.equal(original, cid(preimage));
    for (const capability of body.connector_capabilities) {
      assert.ok(capability.capability_contract_cids.includes(expected));
      assert.ok(!capability.capability_contract_cids.includes(
        'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8'));
    }
  }
});

test('current Catalog dependency fixtures pin the normative environment grammar', () => {
  const expected = cid(json('spec/contracts/actql-check-environment.json'));
  assert.equal(expected, 'sha256:971a37d4a819157f4016cfe804084ebe828dd07df287214e19cb8ed0483a13b9');
  for (const name of ['catalog_body_dependencies_test', 'lookup_body_dependencies_test']) {
    hasPin('src/check_environment/' + name + '.mbt', expected);
  }
  const valueSchema = json('spec/contracts/actql-protocol-schemas.json').schemas.canonical_value_contract;
  const valuePin = cid(valueSchema);
  assert.equal(valuePin, 'sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1');
  assert.equal(json('spec/contracts/actql-check-environment.json').value_contract_bodies.schema.cid, valuePin);
  hasPin('src/check_environment/catalog_body_dependencies_test.mbt', valuePin);
});

test('current expression fixture resolves only the normative root', () => {
  const expected = cid(json('spec/contracts/actql-expressions.json'));
  assert.equal(expected, 'sha256:2849a6667980fc51ed51a04879470a97068fd08e358d784262602a09b22dacda');
  hasPin('src/check_environment/expression_dependencies_test.mbt', expected);
  assert.notEqual(expected, 'sha256:e4b8431ae81884a1e198420dcbd08d6b12ef4dca4bd9b7b8ffa4cd45db887289');
});

test('current Program roots pin the normative closed source schema', () => {
  const body = json('spec/contracts/actql-protocol-schemas.json').artifact_schemas
    .executable_plan.properties.execution_material.properties.program;
  const expected = cid(body);
  assert.equal(expected, 'sha256:9308e067cc169370804ce2b9d53bd572f90c83d8f15a2b009db00f6e4c5c95a0');
  hasPin('src/pipeline_check_context/core_contracts_test.mbt', expected);
});

test('managed completion fixture pins the complete normative profile', () => {
  const expected = cid(json('spec/contracts/actql-managed-retained-execution.json'));
  assert.equal(expected, 'sha256:e9e0e4f42fd3d4b512385ae918096d00e766d343a98864cf1f959d01dbae8fb0');
  hasPin('src/execution_relation/managed_completion_wbtest.mbt', expected);
});

// Bind complete (authored source, CID, byte length) tuples, not textual CID
// membership: a pin belonging to another request must not satisfy this check.
const callerTuples = path => [...read(path).matchAll(
  /\(\s*("(?:\\.|[^"\\])*")\s*,\s*("(?:\\.|[^"\\])*")\s*,\s*(\d+),\s*\)/gu,
)].map(([, source, pin, bytes]) => [JSON.parse(JSON.parse(source)), JSON.parse(pin), Number(bytes)]);
const currentInstrTuples = fixture => fixture.cases.map(item => {
  // Preserve all historical request, graph, root and capacity witnesses. The
  // current caller intentionally uses the current normative expression body.
  const body = {...item.body, expression_contract_cid: cid(json('spec/contracts/actql-expressions.json'))};
  return [item.source, cid(body), Buffer.byteLength(canonical(body))];
});

test('INSTR and STRPOS fixtures retain the independent complete-fragment preimages', () => {
  const path = 'portability/corpus/translate-instr-identities.json';
  assert.equal(createHash('sha256').update(read(path)).digest('hex'),
    'f0d2dfe30ec14d858b22c321c141df68b8743bf01257282d7ae3bc075a149889');
  const fixture = json(path);
  assert.equal(fixture.cases.length, 4);
  for (const item of fixture.cases) {
    assert.equal(cid(item.body), item.cid);
    assert.equal(canonical(item.body), item.canonical);
    assert.equal(Buffer.byteLength(item.canonical), item.bytes);
    assert.equal(item.body.expression_contract_cid, fixture.expression_contract_cid);
  }
  // Exact caller bytes from c05f1f385d21e32865f542e63ddde21ba308157d:
  // this is historical source evidence, never a fallback for the current caller.
  const historical = 'portability/corpus/historical/translate-instr-identity-caller-c05f1f385.mbt';
  assert.equal(createHash('sha256').update(read(historical)).digest('hex'),
    '10ba0420baf40bd9fd6b228f8acbb3905e5c53a605359eed2b9a5243fa6fa5f1');
  assert.deepEqual(callerTuples(historical), fixture.cases.map(item => [item.source, item.cid, item.bytes]));
  const current = currentInstrTuples(fixture);
  assert.deepEqual(callerTuples('src/execution_relation/translate_instr_identity_wbtest.mbt'), current);
  assert.equal(new Set(current.map(([, pin]) => pin)).size, 4);
  for (const [index, [, pin]] of current.entries()) assert.notEqual(pin, fixture.cases[index].cid);
});

test('INSTR current caller binding refuses historical pins and cross-request substitution', () => {
  const fixture = json('portability/corpus/translate-instr-identities.json');
  const expected = currentInstrTuples(fixture);
  for (const mutate of [
    tuples => {tuples[0][1] = fixture.cases[0].cid;},
    tuples => {[tuples[0][1], tuples[1][1]] = [tuples[1][1], tuples[0][1]];},
    tuples => {tuples[0][0] = fixture.cases[1].source;},
    tuples => {tuples[0][2] += 1;},
  ]) {
    const candidate = structuredClone(expected);
    mutate(candidate);
    assert.throws(() => assert.deepEqual(candidate, expected), assert.AssertionError);
  }
});

for (const [path, prefix] of [
  ['src/platform_native/remote_resident_host/effect_source_fixture_wbtest.mbt', 'resident_effect_source'],
  ['src/platform_native/remote_resident_source_compute_tests/source_fixture_wbtest.mbt', 'resident_effect_source'],
  ['src/platform_native/remote_standard_host/retained_task_source_wbtest.mbt', 'retained_source'],
  ['src/client_local_host/resident_source_query_regression_wbtest.mbt', 'source_query_original'],
]) test(prefix + ' uses the complete normative fragment and matching registered CID', () => {
  const body = fixtureBody(path, prefix + '_fragment');
  const contract = json('spec/contracts/actql-aoa.json');
  const normative = contract.execution_contracts['ACTQL.expression_fragment/0.1'];
  const expressions = json('spec/contracts/actql-expressions.json');
  assert.deepEqual(body, normative);
  assert.equal(body.dependencies.expression_contract.cid, cid(expressions));
  assert.equal(body.dependencies.fragment_schema.cid, cid(expressions.schemas.fragment));
  const registry = fixtureBody(path, prefix + '_registry');
  assert.deepEqual(registry, json(contract.pipeline_registry_file));
  assert.equal(cid(registry), contract.pipeline_registry_cid);
  const values = fixtureBody(path, prefix + '_values');
  assert.deepEqual(values, contract.execution_contracts['REL.values']);
  assert.equal(cid(values), contract.target_registry_requirements['REL.values'].execution_contract.cid);
  assert.equal(registry['ACTQL.expression_fragment/0.1'].execution_contract.cid, cid(body));
});


test('current complete-fragment callers rebind only their declared normative dependencies', () => {
  const fixture = json('portability/corpus/expression-fragment-identities.json');
  const expression = cid(json('spec/contracts/actql-expressions.json'));
  const ordered = cid(json('spec/contracts/actql-aoa.json').execution_contracts['REL.derive.ordered']);
  for (const item of fixture.cases) {
    // Keep the complete independently authored historical preimage immutable.
    assert.equal(canonical(item.body), item.canonical);
    assert.equal(cid(item.body), item.cid);
    assert.equal(Buffer.byteLength(item.canonical), item.bytes);
    const current = structuredClone(item.body);
    let caller;
    if (item.id === 'ordered_node') {
      current.params.row_kernel_contract_cid = ordered;
      caller = 'src/execution_relation/fragment_ordered_wbtest.mbt';
    } else {
      assert.equal(item.id, 'complete_fragment');
      current.expression_contract_cid = expression;
      caller = 'src/execution_relation/fragment_candidate_wbtest.mbt';
    }
    assert.equal(Buffer.byteLength(canonical(current)), item.bytes);
    hasPin(caller, cid(current));
    assert.notEqual(cid(current), item.cid);
  }
});


test('current Registry, Values and graph caller literals bind complete normative bodies', () => {
  const owner = json('spec/contracts/actql-aoa.json');
  const registry = json(owner.pipeline_registry_file);
  const path = 'src/execution_relation/registry_wbtest.mbt';
  hasPin(path, cid(registry));
  hasPin(path, cid(owner.execution_contracts['REL.values']));
  hasPin(path, cid(owner.execution_contracts['BRIDGE.rows.to_graph']));
});
