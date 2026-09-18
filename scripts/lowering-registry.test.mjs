import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const fixtures = JSON.parse(read('src/lowering_relation/registry-preimages.json'));
const contract = JSON.parse(read('spec/contracts/actql-aoa.json'));
const registry = JSON.parse(read(contract.pipeline_registry_file));
// These pinned preimages contain only ASCII keys and finite ordinary JSON.
// Independent of the product encoder, with no reference package dependency.
const canonical = (v) => Array.isArray(v) ? `[${v.map(canonical).join(',')}]`
  : v !== null && typeof v === 'object'
    ? `{${Object.keys(v).sort().map(k => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`
    : JSON.stringify(v);
const cid = (v) => `sha256:${createHash('sha256').update(canonical(v)).digest('hex')}`;

test('current registry and historical preimages keep distinct identities', () => {
  assert.equal(cid(registry), contract.pipeline_registry_cid);
  assert.equal(cid(registry),
    'sha256:604f29b5b36a5b9e66fdd8b866978a65f529d56a41c9c571052a59364196943a');
  const fragmentRegistry = JSON.parse(read('portability/fixtures/pipeline-registry-fragment.json'));
  assert.equal(cid(fragmentRegistry), 'sha256:23a7f1081d1a2cdab7b20e425dddce846510355ba964058e0c809350fae33816');
  const valuesRegistry = JSON.parse(read('portability/fixtures/pipeline-registry-values.json'));
  assert.equal(cid(valuesRegistry), 'sha256:b97a22de3664c1dafe3bc1e6791f1f8bcfb70324a1fcc1087450fe057e0f2311');
  const {['ACTQL.expression_fragment/0.1']: fragment, ...previous} = registry;
  assert.ok(fragment);
  const primitive = structuredClone(previous);
  assert.equal(
    cid(contract.execution_contracts['REL.derive.ordered']),
    'sha256:5c42162fa5adc40007f7e4630fa30e835c0dce20f74785be074f4490aff522de',
  );
  delete primitive['REL.derive'].execution_extensions;
  delete primitive['REL.except_rows'];
  delete primitive['REL.intersect_rows'];
  delete primitive['REL.cross_join'];
  primitive['REL.values'] = valuesRegistry['REL.values'];
  assert.deepEqual(primitive, valuesRegistry);
  assert.equal(cid(fixtures.registry), 'sha256:00ac46baefe7fa34412ad83beb85cf1899b906e792d74fa89211a7c4972f0d5a');
  assert.equal(Object.hasOwn(fixtures.registry, 'REL.values'), false);
  const {['REL.values']: added, ...retained} = valuesRegistry;
  assert.ok(added);
  assert.deepEqual(retained, fixtures.registry);
  assert.equal(cid(fixtures.target), contract.target_module_contract_cid);
});

test('preparation handlers use pinned relation signatures', () => {
  const source = read('src/lowering_relation/prepare.mbt');
  for (const [variant, name, arity] of [
    ['Values', 'values', 0], ['Derive', 'derive', 1],
    ['Where', 'where', 1], ['Select', 'select', 1],
  ]) {
    const op = `REL.${name}`;
    // A target requirement is not a registration. Resolve the selected body.
    const signature = registry[op];
    assert.ok(signature, `missing selected registration: ${op}`);
    assert.deepEqual({inputs: signature.inputs, output: signature.output},
      { inputs: Array(arity).fill('relation'), output: 'relation' });
    if (op === 'REL.values') {
      assert.deepEqual(signature.execution_contract, {
        file: 'spec/contracts/actql-aoa.json',
        pointer: '/execution_contracts/REL.values',
        cid: 'sha256:9dec7cf1abedfb23b0af130ec5e25c7442d28c205a94cad0218b2f5982d44b44',
      });
      assert.equal(cid(contract.execution_contracts[op]), signature.execution_contract.cid);
    }
    assert.ok(source.includes(`${variant}(_) => ("${name}", ${arity})`));
    assert.ok(source.includes(`${variant}(_) => "${op}"`));
  }
  for (const op of [
    'REL.except_rows',
    'REL.intersect_rows',
    'REL.cross_join',
  ]) {
    const signature = registry[op];
    assert.deepEqual(
      {inputs: signature.inputs, output: signature.output},
      {inputs: ['relation', 'relation'], output: 'relation'},
    );
    assert.ok(source.includes(`=> "${op}"`));
  }
});
