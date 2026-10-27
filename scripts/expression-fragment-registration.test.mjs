import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {gunzipSync} from 'node:zlib';
import {checkRegistration, registerExpressionFragment} from './expression-fragment-registration.mjs';
const read = p => JSON.parse(readFileSync(p, 'utf8'));
const aoa = read('spec/contracts/actql-aoa.json');
const expressions = read('spec/contracts/actql-expressions.json');
const registry = read(aoa.pipeline_registry_file);
const historical = read('portability/fixtures/pipeline-registry-values.json');
const op = 'ACTQL.expression_fragment/0.1';
// Independent canonical hashing for these already-normalized machine bodies.
const canonical = v => Array.isArray(v) ? `[${v.map(canonical)}]`
  : v !== null && typeof v === 'object'
    ? `{${Object.keys(v).sort().map(k => `${JSON.stringify(k)}:${canonical(v[k])}`)}}`
    : JSON.stringify(v);
const cid = v => 'sha256:' + createHash('sha256').update(canonical(v)).digest('hex');
const currentCid =
  'sha256:09353058f3feff94698f4707cc17c0eb6e142198d058c09b278b92b3f942271e';
const contractCid = 'sha256:ced7ee00f232f8d5bcfde44dfc769d9d6ae02c8386e54db7d844d43f922bac90';

function resolve(body, selected, owner = aoa, expr = expressions) {
  assert.equal(cid(body), selected, 'RegistryCidMismatch');
  assert.ok(body[op], 'MissingRegistration');
  const entry = body[op];
  assert.deepEqual(entry.inputs, ['relation']); assert.equal(entry.output, 'relation');
  assert.equal(entry.execution_contract.file, 'spec/contracts/actql-aoa.json');
  assert.equal(entry.execution_contract.pointer, '/execution_contracts/ACTQL.expression_fragment~10.1');
  const contract = entry.execution_contract.pointer.split('/').slice(1).reduce(
    (v, k) => v?.[k.replaceAll('~1', '/').replaceAll('~0', '~')], owner);
  assert.ok(contract); assert.equal(cid(contract), entry.execution_contract.cid);
  assert.equal(contract.dependencies.expression_contract.cid, cid(expr));
  assert.equal(contract.dependencies.fragment_schema.cid, cid(expr.schemas.fragment));
  assert.equal(owner.expression_contract_cid, cid(expr));
  checkRegistration(owner, expr, body);
  return contract;
}

test('extensions preserve historical primitives except explicitly revised values resources', () => {
  assert.equal(cid(historical), 'sha256:b97a22de3664c1dafe3bc1e6791f1f8bcfb70324a1fcc1087450fe057e0f2311');
  assert.equal(cid(registry), currentCid);
  const addedOperations = [
    'ACTQL.expression_fragment/0.1',
    'REL.analytic', 'REL.cross_join', 'REL.except_rows', 'REL.intersect_rows',
    'SGA.equal', 'SGA.mean_structural', 'SGA.subgraph',
    'TEA.join.interval', 'TEA.time_series', 'TEA.calendar.bucket', 'TEA.calendar.series',
  ];
  assert.deepEqual(Object.keys(registry).sort(),
    [...Object.keys(historical), ...addedOperations].sort());
  const {[op]: added, ...rest} = registry;
  const retained=structuredClone(rest);
  delete retained['REL.derive'].execution_extensions;
  delete retained['REL.except_rows'];
  delete retained['REL.intersect_rows'];
  delete retained['REL.cross_join'];
  delete retained['REL.analytic'];
  delete retained['TEA.calendar.bucket'];
  delete retained['TEA.calendar.series'];
  for (const operation of [
    'SGA.subgraph',
    'SGA.equal',
    'SGA.mean_structural',
    'TEA.time_series',
    'TEA.join.interval',
  ]) delete retained[operation];
  for (const operation of [
    'BRIDGE.rows.to_graph',
    'SGA.apply_delta',
    'SGA.union_structural',
    'SGA.traverse',
    'SGA.shortest_path',
    'SGA.reachable',
    'VEC.merge_rankings',
  ]) retained[operation] = historical[operation];
  assert.deepEqual(registry['SGA.reachable'], {
    input_alternatives: [['graph'], ['graph', 'relation']],
    output: 'relation',
  });
  assert.equal(retained['REL.values'].execution_contract.cid,
    cid(aoa.execution_contracts['REL.values']));
  assert.notEqual(retained['REL.values'].execution_contract.cid,
    historical['REL.values'].execution_contract.cid);
  retained['REL.values'].execution_contract.cid = historical['REL.values'].execution_contract.cid;
  assert.deepEqual(retained, historical); assert.ok(added);
  assert.equal(cid(resolve(registry, currentCid)), contractCid);
});

test('registration binds the existing schema without copying or weakening it', () => {
  const contract = resolve(registry, currentCid);
  assert.deepEqual(contract.params_schema.required, ['fragment']);
  assert.equal(contract.params_schema.additionalProperties, false);
  assert.deepEqual(contract.params_schema.properties, {fragment: {$ref: expressions.schemas.fragment.$id}});
  assert.equal(contract.dependencies.fragment_schema.pointer, '/schemas/fragment');
  assert.equal(contract.dependencies.expression_contract.pointer, '');
});

test('missing registration and mismatched selected registry are rejected', () => {
  assert.throws(() => resolve(historical, cid(historical)), /MissingRegistration/);
  assert.throws(() => resolve(historical, currentCid), /RegistryCidMismatch/);
  assert.throws(() => resolve(registry, cid(historical)), /RegistryCidMismatch/);
});

test('rehashed signature and reference mutations cannot satisfy registration', () => {
  for (const mutate of [
    e => {e.inputs = [];}, e => {e.output = 'events';},
    e => {e.execution_contract.file = 'elsewhere.json';},
    e => {e.execution_contract.pointer = '/execution_contracts/ACTQL.expression_fragment/0.1';},
    e => {e.execution_contract.cid = cid(historical);},
  ]) {
    const body = structuredClone(registry); mutate(body[op]);
    assert.throws(() => resolve(body, cid(body)));
  }
});

test('contract, expression body and stale expression pin are independently checked', () => {
  const changed = structuredClone(aoa);
  changed.execution_contracts[op].semantics.admission = 'skip';
  assert.throws(() => resolve(registry, currentCid, changed));
  const expr = structuredClone(expressions); expr.schemas.fragment.additionalProperties = true;
  assert.throws(() => resolve(registry, currentCid, aoa, expr));
  const stale = structuredClone(aoa); stale.expression_contract_cid = cid(historical);
  assert.throws(() => resolve(registry, currentCid, stale));
});

// Complete accepted predecessor bodies are retained independently of the
// writer. Only registered references change; the expression/schema law does not.
const predecessorBytes = gunzipSync(readFileSync(
  'scripts/fixtures/expression-fragment-registration/predecessor.json.gz'));
const predecessor = JSON.parse(predecessorBytes);

test('registered closure changes only the stale expression dependency and containing identities', () => {
  assert.equal(predecessor.source, '6f6ebe8a6e4fc4d642614c4753ccf6e8587f3ebf');
  const adopted = read('scripts/fixtures/signed-source-zero-grammar/identity-transition.json').retained_registration_after;
  assert.equal(adopted.source_commit, '3e0f3400f913bd20f386c0866c45617a8a702486');
  const {expression: expressions, aoa, pipelineRegistry: registry, checkEnvironment, grammarManifest} = adopted.records;
  const before = predecessor.bodies;
  assert.equal(cid(before.aoa), 'sha256:aace4d39f4f3f214158027007d7bfd27ded49f29f0aac55ca022b48bb0ddc5f0');
  assert.equal(cid(before.pipelineRegistry), 'sha256:26915f8a20a27b9e37c1e9760fe2526c460b63bf2f1957fa1af858b18051271c');
  assert.equal(before.aoa.expression_contract_cid, cid(expressions));
  assert.equal(before.aoa.execution_contracts[op].dependencies.expression_contract.cid,
    'sha256:6ccd3d3e87cf65610f96b81ce3a11844f1d12a6bee3166df66726a3c11e571f8');
  assert.throws(() => checkRegistration(before.aoa, expressions, before.pipelineRegistry));
  const expected = structuredClone(before);
  expected.aoa.execution_contracts[op].dependencies.expression_contract.cid = cid(expressions);
  const selected = cid(expected.aoa.execution_contracts[op]);
  expected.aoa.target_registry_requirements[op].execution_contract.cid = selected;
  expected.pipelineRegistry[op].execution_contract.cid = selected;
  expected.aoa.pipeline_registry_cid = cid(expected.pipelineRegistry);
  assert.deepEqual(aoa, expected.aoa);
  assert.deepEqual(registry, expected.pipelineRegistry);
  assert.deepEqual(checkEnvironment, before.checkEnvironment);
  assert.deepEqual(grammarManifest, before.grammarManifest);
});

test('containing expression writer uses the same closed registration updater', () => {
  const changed = structuredClone(expressions);
  changed.laws.try_number.number += ' Independent changed-law witness.';
  const owner = structuredClone(aoa), selected = structuredClone(registry);
  owner.expression_contract_cid = cid(changed);
  assert.throws(() => checkRegistration(owner, changed, selected));
  registerExpressionFragment(owner, changed, selected);
  assert.equal(owner.execution_contracts[op].dependencies.expression_contract.cid, cid(changed));
  assert.equal(selected[op].execution_contract.cid, cid(owner.execution_contracts[op]));
  assert.equal(owner.pipeline_registry_cid, cid(selected));
  const unchanged = structuredClone(owner);
  registerExpressionFragment(owner, changed, selected);
  assert.deepEqual(owner, unchanged);
});
