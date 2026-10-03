import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {checkRegistration} from './expression-fragment-registration.mjs';
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
  'sha256:af8d2530f74cabec40daa30580dc0a036691a9d8875c0eb7a85ee40240768bcd';
const contractCid = 'sha256:1282c3d8af052606f64be809cead104630c67a8b676050bcdc7edd4a884b9b60';

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
  assert.equal(Object.keys(registry).length, 69);
  const {[op]: added, ...rest} = registry;
  const retained=structuredClone(rest);
  delete retained['BRIDGE.rows.to_property_graph'];
  delete retained['REL.derive'].execution_extensions;
  delete retained['REL.except_rows'];
  delete retained['REL.intersect_rows'];
  delete retained['REL.cross_join'];
  delete retained['REL.analytic'];
  for (const operation of [
    'SGA.subgraph',
    'SGA.equal',
    'SGA.mean_structural',
    'TEA.time_series',
    'TEA.join.interval',
  ]) delete retained[operation];
  for (const operation of [
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
