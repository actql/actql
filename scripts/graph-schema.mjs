import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {positive, parameter} from './aggregate-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function graphSchemas() {
  const nonnegative = {oneOf:[{type:'integer',minimum:0,maximum:9007199254740991},parameter]};
  const field = {type:'string',minLength:1};
  const fields = {type:'array',items:field,uniqueItems:true};
  const projectedFields = {...fields,minItems:1};
  const predicate = {oneOf:[{type:'string'},{type:'object',minProperties:1,maxProperties:1}]};
  const selector = {oneOf:[
    {type:'object',additionalProperties:false,required:['ids'],properties:{ids:{type:'array',minItems:1,items:{}}}},
    {type:'object',additionalProperties:false,required:['from','id'],properties:{from:field,id:field}},
    {type:'object',additionalProperties:false,required:['where'],properties:{where:predicate}},
  ]};
  const strategies = {type:'object',additionalProperties:{enum:[
    'exact_equal','set_union','set_difference','number_sum','number_mean','number_min','number_max',
  ]}};
  const structural = {type:'object',additionalProperties:false,required:['with'],properties:{
    with:field,
    merge:{type:'object',additionalProperties:false,properties:{node_properties:strategies,edge_properties:strategies}},
  }};
  return {
    traverse:{type:'object',additionalProperties:false,required:['start','emit'],properties:{
      start:selector,emit:{enum:['nodes','paths']},max_output_rows:positive,
      direction:{enum:['in','out','both']},edge_types:{type:'array',items:field},
      min_hops:{type:'integer',minimum:0},max_hops:{type:'integer',minimum:1},
      hops:{type:'array',minItems:1,items:{type:'object',additionalProperties:false,required:['direction'],properties:{direction:{enum:['in','out','both']},edge_types:{type:'array',items:field},edge_where:predicate,node_where:predicate}}},
    },oneOf:[
      {required:['hops'],not:{anyOf:['direction','edge_types','min_hops','max_hops'].map(name => ({required:[name]}))}},
      {required:['direction','min_hops','max_hops'],not:{required:['hops']}},
    ]},
    reach:{type:'object',additionalProperties:false,required:['start','direction','max_depth'],properties:{start:{},direction:{enum:['in','out','both']},max_depth:{type:'integer',minimum:1}}},
    subgraph:{type:'object',additionalProperties:false,required:['nodes'],properties:{nodes:selector,edges:predicate}},
    match_nodes: {type:'object',additionalProperties:false,required:['fields'],
      properties:{fields:projectedFields,ids:{type:'array',minItems:1,items:{}},where:predicate},
      oneOf:[{required:['ids'],not:{required:['where']}},{required:['where'],not:{required:['ids']}}]},
    match_edges: {type:'object',additionalProperties:false,required:['fields'],
      properties:{fields:projectedFields,types:{type:'array',items:field},where:predicate}},
    graft_graph: {type:'object',additionalProperties:false,required:['with'],properties:{with:field}},
    union_graphs: structural,
    subtract_graphs: structuredClone(structural),
    graph: {oneOf:[
      {type:'object',additionalProperties:false,required:['nodes','edges'],properties:{
        nodes:{type:'object',additionalProperties:false,required:['from','id'],properties:{from:field,id:field,fields}},
        edges:{type:'object',additionalProperties:false,required:['from','source','target'],properties:{from:field,source:field,target:field,label:field,fields}},
      }},
      {type:'object',additionalProperties:false,required:['source','target'],properties:{source:field,target:field,label:field}},
    ]},
    node_rows: {const:true},
    edge_rows: {const:true},
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
