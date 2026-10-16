import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { canonicalText, verifyIdentity } from './check-canonical-json.mjs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const fixture = JSON.parse(read('scripts/fixtures/readme-hero/compiler-inputs.json'));
const moon = read('src/query_program/readme_hero_test.mbt');
const hash = value => `sha256:${createHash('sha256').update(canonicalText(value)).digest('hex')}`;
const without = (value, field) => Object.fromEntries(Object.entries(value).filter(([key]) => key !== field));
const literals = moon.split('\n').filter(line => /^\s*#\|\{/.test(line)).map(line => JSON.parse(line.split('#|')[1]));

test('the compiled hero is the exact first README SQL, including its defaults', () => {
  const authored = read('README.md').split('```sql\n')[1].split('\n```')[0];
  const body = moon.split('fn readme_hero_text() -> String {')[1].split('\n}\n')[0];
  const compiled = body.split('\n').filter(line => /^\s*#\|/.test(line)).map(line => line.split('#|')[1]).join('\n');
  assert.equal(compiled, authored);
});

test('independent complete environment and member preimages match the compiler literals', () => {
  const environment = fixture.environment;
  assert.deepEqual(literals[0], environment);
  verifyIdentity(without(environment, 'evidence_bundle_cid'), fixture.expected_environment_cid);
  assert.equal(environment.evidence_bundle_cid, fixture.expected_environment_cid);
  const entries = environment.connector_manifest.connectors;
  assert.deepEqual(entries.map(hash), entries.map(hash).toSorted());
  for (const entry of entries) {
    assert.equal(environment.connector_catalogs.filter(catalog => catalog.connector_id === entry.connector_id && catalog.connector_version === entry.connector_version).length, 1);
  }
  const catalogs = environment.connector_catalogs;
  assert.deepEqual(catalogs.map(hash), catalogs.map(hash).toSorted());
  for (const catalog of catalogs) verifyIdentity(without(catalog, 'catalog_cid'), catalog.catalog_cid);
  for (const mapping of environment.mapping_contracts) {
    verifyIdentity(without(mapping, 'mapping_contract_cid'), mapping.mapping_contract_cid);
    verifyIdentity(mapping.target_schema, mapping.target_schema_identity);
    assert.equal(mapping.connector_manifest_cid, hash(entries.find(entry => entry.connector === 'salesforce')));
    assert.notEqual(mapping.connector_manifest_cid, hash(environment.connector_manifest));
  }
  for (const task of environment.model_task_contracts) {
    verifyIdentity(without(task, 'contract_cid'), task.contract_cid);
    verifyIdentity(task.input_contract, task.input_schema_cid);
    verifyIdentity(task.output_contract, task.output_schema_cid);
  }
});

test('captured-input declarations retain independent schemas and original key evidence', () => {
  assert.deepEqual(literals.slice(1), Object.values(fixture.declarations));
  assert.deepEqual(fixture.expected_input_fields, ['notes', 'active_users', 'trend']);
  assert.deepEqual(fixture.expected_visible_keep, ['id', 'notes', 'active_users', 'trend']);
  assert.deepEqual(fixture.expected_input_key, ['id']);
  assert.deepEqual(fixture.expected_public_results, ['updates']);
  for (const declaration of literals.slice(1)) {
    assert.equal(declaration.carrier, 'relation');
    assert.equal(Object.hasOwn(declaration, 'rows'), false);
    assert.equal(declaration.primary_key.length, 1);
    assert.equal(declaration.schema[declaration.primary_key[0]].nullable, false);
  }
});
