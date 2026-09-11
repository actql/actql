import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const fixtures = JSON.parse(read('src/lowering_relation/registry-preimages.json'));
const contract = JSON.parse(read('spec/contracts/actql-aoa.json'));
// These pinned preimages contain only ASCII keys and finite ordinary JSON.
// Independent of the product encoder, with no reference package dependency.
const canonical = (v) => Array.isArray(v) ? `[${v.map(canonical).join(',')}]`
  : v !== null && typeof v === 'object'
    ? `{${Object.keys(v).sort().map(k => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`
    : JSON.stringify(v);
const cid = (v) => `sha256:${createHash('sha256').update(canonical(v)).digest('hex')}`;

test('recovered full registry and module bodies match current pins', () => {
  assert.equal(cid(fixtures.registry), contract.pipeline_registry_cid);
  assert.equal(cid(fixtures.target), contract.target_module_contract_cid);
});

test('four preparation handlers use pinned sort/arity including values extension', () => {
  const source = read('src/lowering_relation/prepare.mbt');
  for (const [variant, name, arity] of [
    ['Values', 'values', 0], ['Derive', 'derive', 1],
    ['Where', 'where', 1], ['Select', 'select', 1],
  ]) {
    const op = `REL.${name}`;
    const signature = contract.target_registry_requirements[op] ?? fixtures.registry[op];
    assert.deepEqual(signature, { inputs: Array(arity).fill('relation'), output: 'relation' });
    assert.ok(source.includes(`${variant}(_) => ("${name}", ${arity})`));
    assert.ok(source.includes(`${variant}(_) => "${op}"`));
  }
});
