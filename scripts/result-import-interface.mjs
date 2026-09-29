import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type:'string',pattern:'^sha256:[0-9a-f]{64}$'};
const name = {type:'string',minLength:1};
export const schema = {
  type:'object', properties:{
    version:{const:'actql-result-import-interface/0.1'},
    input_name:name,
    producer_namespace:{type:'object',properties:{program_id:name,node_id:name},
      required:['program_id','node_id'],additionalProperties:false},
    producer_unit_definition_cid:cid,
    producer_result:name,
    value_contract_cid:cid,
    availability:{const:'stage_success'},
    self_cid:cid,
  },
  required:['version','input_name','producer_namespace','producer_unit_definition_cid',
    'producer_result','value_contract_cid','availability','self_cid'],
  additionalProperties:false,
};
export const roles = {
  producer_unit_definition_cid:'local_dependencies',
  value_contract_cid:'external:value-contract',
};

// Dynamic observation is distinct from the static type/import interface.
// Its consumer position is semantic; Run membership is checked separately.
export const observationSchema = {
  type: 'object', properties: {
    version: {const: 'actql-result-import-observation/0.1'},
    consumer_unit_definition_cid: cid,
    input_name: name,
    import_interface_cid: cid,
    producer_local_manifest_cid: cid,
    result_artifact_cid: cid,
    self_cid: cid,
  },
  required: ['version', 'consumer_unit_definition_cid', 'input_name',
    'import_interface_cid', 'producer_local_manifest_cid',
    'result_artifact_cid', 'self_cid'],
  additionalProperties: false,
};
export const observationRoles = {
  consumer_unit_definition_cid: 'local_dependencies',
  import_interface_cid: 'result_import_interface',
  producer_local_manifest_cid: 'local_manifest',
  result_artifact_cid: 'local_result_artifact',
};

export function checkResultImportInterface(registry) {
  assert.deepEqual(registry.schemas.result_import_interface,schema);
  assert.equal(registry.schema_cids.result_import_interface,machineCid(schema));
  assert.deepEqual(registry.reference_roles.result_import_interface,roles);
  assert.deepEqual(registry.reference_graph.filter(e=>e.source==='result_import_interface'),
    Object.entries(roles).map(([slot,target])=>({source:'result_import_interface',slot,target,role:'semantic'})));
  // The general slot also admits receipt interfaces under their own contract;
  // registering the Result form must not reinterpret receipts as Result ports.
  assert.equal(registry.reference_roles.local_dependencies['import_interface_cids/*'],'external:import-interface');
  assert.deepEqual(registry.schemas.result_import_observation,
    observationSchema);
  assert.equal(registry.schema_cids.result_import_observation,
    machineCid(observationSchema));
  assert.deepEqual(registry.reference_roles.result_import_observation,
    observationRoles);
  assert.deepEqual(registry.reference_graph.filter(edge =>
    edge.source === 'result_import_observation'),
  Object.entries(observationRoles).map(([slot, target]) => ({
    source: 'result_import_observation', slot, target, role: 'semantic',
  })));
}

if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  const path='spec/contracts/actql-stage-contracts.json';
  const registry=JSON.parse(readFileSync(path,'utf8'));
  if(process.argv.includes('--write')) {
    registry.schemas.result_import_interface=schema;
    registry.schema_cids.result_import_interface=machineCid(schema);
    registry.reference_roles.result_import_interface=roles;
    registry.reference_graph=registry.reference_graph.filter(e=>e.source!=='result_import_interface');
    registry.reference_graph.push(...Object.entries(roles).map(([slot,target])=>({source:'result_import_interface',slot,target,role:'semantic'})));
    registry.schemas.result_import_observation = observationSchema;
    registry.schema_cids.result_import_observation = machineCid(observationSchema);
    registry.reference_roles.result_import_observation = observationRoles;
    registry.reference_graph = registry.reference_graph.filter(edge =>
      edge.source !== 'result_import_observation');
    registry.reference_graph.push(...Object.entries(observationRoles).map(
      ([slot, target]) => ({source: 'result_import_observation', slot,
        target, role: 'semantic'})));
    writeFileSync(path,JSON.stringify(registry,null,2)+'\n');
  }
  checkResultImportInterface(registry);
  console.log('Result import interface schema '+machineCid(schema));
}
