import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {checkLocalTableInputContract, definitionSchema,
  withLocalTableInputContract} from './local-table-input-contract.mjs';

const read = file => JSON.parse(readFileSync(file, 'utf8'));
const registry = read('spec/contracts/actql-stage-contracts.json');

test('private input schema has a distinct producer and typed reference roles', () => {
  checkLocalTableInputContract(registry);
  assert.deepEqual(registry.schemas.local_table_input_definition,
    definitionSchema);
  assert.equal(registry.schema_cids.local_table_input_definition,
    machineCid(definitionSchema));
  assert.equal(definitionSchema.additionalProperties, false);
  assert.deepEqual(definitionSchema.required,
    ['version', 'unit_definition_cid', 'table_input_name', 'self_cid']);
  assert.deepEqual(registry.schemas.local_table_input_artifact,
    registry.schemas.local_result_artifact);
  assert.equal(registry.reference_roles.local_result_artifact
    .result_definition_cid, 'local_result_definition');
  assert.equal(registry.reference_roles.local_table_input_artifact
    .result_definition_cid, 'local_table_input_definition');
  assert.equal(registry.reference_roles.local_manifest['results/*'],
    'local_result_artifact');
  assert.equal(registry.reference_roles.local_manifest['table_inputs/*'],
    'local_table_input_artifact');
});

test('private Manifest map is optional, nonempty and independent of Result names', () => {
  const manifest = registry.schemas.local_manifest;
  assert.equal(manifest.required.includes('table_inputs'), false);
  assert.equal(manifest.properties.table_inputs.minProperties, 1);
  assert.deepEqual(manifest.properties.table_inputs.additionalProperties,
    manifest.properties.results.additionalProperties);
  assert.equal(manifest.additionalProperties, false);
  const changed = structuredClone(registry);
  changed.reference_roles.local_result_artifact.extra = 'external:fixture';
  changed.reference_graph.push({source: 'local_result_artifact', slot: 'extra',
    target: 'external:fixture', role: 'semantic'});
  const next = withLocalTableInputContract(changed);
  assert.deepEqual(next.schemas.local_result_definition,
    changed.schemas.local_result_definition);
  assert.deepEqual(next.reference_graph.filter(e =>
    e.source === 'local_result_artifact'), changed.reference_graph.filter(e =>
    e.source === 'local_result_artifact'));
  assert.deepEqual(withLocalTableInputContract(next), next);
});

test('independent same-name producer and Manifest canonical preimages', () => {
  const cid = digit => `sha256:${digit.repeat(64)}`;
  const hash = value => `sha256:${createHash('sha256')
    .update(canonicalText(value)).digest('hex')}`;
  const table = {table_input_name: 'out', unit_definition_cid: cid('1'),
    version: 'actql-local-table-input-definition/0.1'};
  const result = {result_name: 'out', unit_definition_cid: cid('1'),
    version: 'actql-local-result-definition/0.1'};
  assert.notEqual(hash(table), hash(result));
  const ordinary = {local_invocation_cid: cid('2'),
    results: {out: cid('3')}, unit_definition_cid: cid('1'),
    version: 'actql-local-result-manifest/0.1'};
  const privateInventory = {...ordinary, table_inputs: {out: cid('4')}};
  assert.equal(canonicalText(privateInventory),
    `{"local_invocation_cid":"${cid('2')}","results":{"out":"${cid('3')}"},` +
    `"table_inputs":{"out":"${cid('4')}"},"unit_definition_cid":"${cid('1')}",` +
    '"version":"actql-local-result-manifest/0.1"}');
  assert.notEqual(hash(privateInventory), hash(ordinary));
  assert.notEqual(hash({...ordinary, table_inputs: {out: cid('3')}}),
    hash(privateInventory));
  assert.notEqual(hash({...ordinary, results: {out: cid('4')},
    table_inputs: {out: cid('3')}}), hash(privateInventory));
});
