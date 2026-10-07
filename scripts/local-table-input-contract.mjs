import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
export const definitionSchema = {
  type: 'object', properties: {
    version: {const: 'actql-local-table-input-definition/0.1'},
    unit_definition_cid: cid,
    table_input_name: {type: 'string', minLength: 1},
    self_cid: cid,
  },
  required: ['version', 'unit_definition_cid', 'table_input_name', 'self_cid'],
  additionalProperties: false,
};

// Only the new roles and the Manifest's private map are owned here. Preserve
// existing Result schemas, their producers and unrelated dependency edges.
export function withLocalTableInputContract(registry) {
  const next = structuredClone(registry);
  const map = {type: 'object', minProperties: 1,
    additionalProperties: structuredClone(cid)};
  next.schemas.local_manifest.properties.table_inputs = map;
  next.schemas.local_table_input_definition = structuredClone(definitionSchema);
  next.schemas.local_table_input_artifact =
    structuredClone(next.schemas.local_result_artifact);
  for (const name of ['local_manifest', 'local_table_input_definition',
    'local_table_input_artifact']) {
    next.schema_cids[name] = machineCid(next.schemas[name]);
  }
  next.reference_roles.local_manifest['table_inputs/*'] =
    'local_table_input_artifact';
  next.reference_roles.local_table_input_definition =
    {unit_definition_cid: 'local_dependencies'};
  next.reference_roles.local_table_input_artifact = {
    ...next.reference_roles.local_result_artifact,
    result_definition_cid: 'local_table_input_definition',
  };
  const sources = ['local_table_input_definition', 'local_table_input_artifact'];
  next.reference_graph = next.reference_graph.filter(edge =>
    !sources.includes(edge.source) && !(edge.source === 'local_manifest' &&
      edge.slot === 'table_inputs/*'));
  for (const source of [...sources, 'local_manifest']) {
    for (const [slot, target] of Object.entries(next.reference_roles[source])) {
      if (source === 'local_manifest' && slot !== 'table_inputs/*') continue;
      next.reference_graph.push({source, slot, target, role: 'semantic'});
    }
  }
  return next;
}

export function checkLocalTableInputContract(registry) {
  assert.deepEqual(registry, withLocalTableInputContract(registry),
    'Local private Table input contracts are stale');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-stage-contracts.json';
  let registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    registry = withLocalTableInputContract(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkLocalTableInputContract(registry);
  console.log('Local Table input producer and separate Manifest roles verified.');
}
