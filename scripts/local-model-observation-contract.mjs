import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const references = {
  unit_definition_cid: 'local_dependencies',
  input_logical_relation_cid: 'external:relation-value',
  input_relation_schema_cid: 'external:value-contract',
  outcome_logical_relation_cid: 'external:relation-value',
  outcome_relation_schema_cid: 'external:value-contract',
};

// The checked Unit and step select the original INFER/task. Actual complete
// input/outcomes are semantic; Run/attempt/provider audit stays in its issuer.
export function withLocalModelObservationContract(registry) {
  const next = structuredClone(registry);
  const properties = {
    version: {const: 'actql-local-model-observation/0.1'},
    ...Object.fromEntries(Object.keys(references).map(key => [key, {...cid}])),
    source_ordinal: {type: 'integer', minimum: 0, maximum: 2147483646},
    self_cid: {...cid},
  };
  next.schemas.local_model_observation = {
    type: 'object', properties, required: Object.keys(properties),
    additionalProperties: false,
  };
  next.schema_cids.local_model_observation =
    machineCid(next.schemas.local_model_observation);
  next.reference_roles.local_model_observation = {...references};
  next.reference_graph = next.reference_graph.filter(edge =>
    edge.source !== 'local_model_observation');
  // The existing Table generator owns a trailing block. Keep that block in
  // its canonical position so the two additive generators commute.
  const table = next.reference_graph.findIndex(edge =>
    ['local_table_input_definition', 'local_table_input_artifact'].includes(edge.source) ||
    (edge.source === 'local_manifest' && edge.slot === 'table_inputs/*'));
  next.reference_graph.splice(table < 0 ? next.reference_graph.length : table, 0,
    ...Object.entries(references).map(([slot, target]) =>
      ({source: 'local_model_observation', slot, target, role: 'semantic'})));
  return next;
}

export function checkLocalModelObservationContract(registry) {
  assert.deepEqual(registry, withLocalModelObservationContract(registry),
    'Local Model observation contract is stale');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-stage-contracts.json';
  let registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    registry = withLocalModelObservationContract(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkLocalModelObservationContract(registry);
  console.log('Local Model observation schema and semantic references verified.');
}
