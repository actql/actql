import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {positive, parameter} from './aggregate-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function graphSchemas() {
  const nonnegative = {oneOf:[{type:'integer',minimum:0,maximum:9007199254740991},parameter]};
  return {
    graphs_equal: {type:'object', additionalProperties:false, required:['with'],
      properties:{with:{type:'string',minLength:1}}},
    graph_diff: {type:'object', additionalProperties:false, required:['with'],
      properties:{with:{type:'string',minLength:1}}},
    apply_graph_delta: {type:'object', additionalProperties:false, required:['with','field'],
      properties:{with:{type:'string',minLength:1},field:{type:'string',minLength:1}}},
    graph_bounds: {type:'object', additionalProperties:false, minProperties:1,
      properties:{max_nodes:nonnegative,max_edges:nonnegative,max_degree:nonnegative}},
    normalize_graph: {const: true},
    degree: {type:'object', additionalProperties:false, required:['direction'],
      properties:{direction:{enum:['in','out','both']}}},
    components: {type:'object', additionalProperties:false, required:['kind'],
      properties:{kind:{enum:['weak','strong']}, max_output_rows:positive}},
  };
}

export function checkGraphSchemas(registry) {
  for (const program of parameterPrograms(registry)) {
    for (const [name, schema] of Object.entries(graphSchemas())) {
      assert.deepEqual(program.properties.steps.items.properties[name], schema);
    }
  }
  for (const [name, body] of Object.entries(registry.artifact_schemas)) {
    assert.equal(registry.artifact_schema_cids[name], machineCid(body));
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    for (const program of parameterPrograms(registry)) {
      Object.assign(program.properties.steps.items.properties, graphSchemas());
    }
    for (const [name, body] of Object.entries(registry.artifact_schemas)) {
      registry.artifact_schema_cids[name] = machineCid(body);
    }
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkGraphSchemas(registry);
  console.log('Graph schemas and artifact pins verified.');
}
