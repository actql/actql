import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {positive, parameter} from './aggregate-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function legacyGraphSchemas() {
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
    mean_graphs:{type:'object',additionalProperties:false,required:['with','weights','support','properties'],properties:{
      with:{type:'array',minItems:1,items:field},
      weights:{type:'array',minItems:1,items:{type:'number',minimum:0},contains:{type:'number',exclusiveMinimum:0}},
      support:{type:'object',additionalProperties:false,required:['nodes','edges'],properties:Object.fromEntries(['nodes','edges'].map(k => [k,{type:'number',exclusiveMinimum:0,maximum:1}]))},
      properties:{type:'object',additionalProperties:false,required:['nodes','edges'],properties:Object.fromEntries(['nodes','edges'].map(k => [k,{type:'object',additionalProperties:{oneOf:[
        {const:'exact_equal'},
        {type:'object',additionalProperties:false,required:['mean'],properties:{mean:{type:'object',additionalProperties:false,required:['missing','nulls'],properties:{missing:{enum:['exclude','zero']},nulls:{enum:['exclude','zero','fail']}}}}},
      ]}}]))},
    }},
    shortest_path:{type:'object',additionalProperties:false,required:['source','target','direction','max_hops'],properties:{
      source:{oneOf:[selector,{type:['string','number','boolean']}]},
      target:{oneOf:[selector,{type:['string','number','boolean']}]},
      selection:{enum:['each_pair','nearest_per_source','nearest_pair']},
      direction:{enum:['in','out','both']},max_hops:{type:'integer',minimum:1},
      weight:field,edge_types:{type:'array',items:field},max_output_rows:positive,
    },if:{anyOf:['source','target'].map(name => ({properties:{[name]:{type:'object'}},required:[name]}))},
    then:{required:['selection']},else:{not:{required:['selection']}}},
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
    union_graphs: {...structural,properties:{...structural.properties,
      with:{oneOf:[field,{type:'array',minItems:1,items:field}]},
    }},
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

// Separate closed alternatives, not a permissive union of legacy and keyed
// members. Semantic key/domain admission remains with the common typed owner.
export function graphSchemas() {
  const legacy = legacyGraphSchemas();
  const field = {type:'string',minLength:1};
  const keys = {type:'array',minItems:1,uniqueItems:true,items:field};
  const properties = {oneOf:[
    {type:'object',additionalProperties:false,required:['mode'],properties:{mode:{const:'all_columns'}}},
    {type:'object',additionalProperties:false,required:['mode'],properties:{mode:{const:'no_properties'}}},
    {type:'object',additionalProperties:false,required:['mode','except'],properties:{mode:{const:'all_columns_except'},except:{type:'array',uniqueItems:true,items:field}}},
    {type:'object',additionalProperties:false,required:['mode','columns'],properties:{mode:{const:'columns'},columns:{type:'array',items:{type:'object',additionalProperties:false,required:['from','to'],properties:{from:field,to:field}}}}},
  ]};
  const element = {type:'object',additionalProperties:false,required:['name','from','key'],properties:{
    name:field,from:field,key:keys,
    labels:{type:'array',items:{type:'object',additionalProperties:false,required:['name'],properties:{name:field,properties}}},
  }};
  const endpoint = {type:'object',additionalProperties:false,required:['definition','key'],properties:{definition:field,key:keys,references_key:keys}};
  const result = {...legacy,
    node_rows:{oneOf:[{const:true},{type:'object',additionalProperties:false,
      required:['definition'],properties:{definition:field}}]},
    edge_rows:{oneOf:[{const:true},{type:'object',additionalProperties:false,
      required:['definition'],properties:{definition:field}}]},
    property_graph:{type:'object',additionalProperties:false,required:['version','nodes','edges'],properties:{
      version:{const:'actql-property-graph-constructor/0.1'},
      nodes:{type:'array',items:element},
      edges:{type:'array',items:{...element,required:[...element.required,'source','target'],properties:{...element.properties,source:endpoint,target:endpoint}}},
    }},
  };
  for (const name of ['match_nodes','match_edges']) {
    const keyed = structuredClone(legacy[name]);
    keyed.required.push('definition');
    Object.assign(keyed.properties, {
      definition:field,label:field,
      bindings:{type:'object',additionalProperties:false,properties:Object.fromEntries(
        (name === 'match_nodes' ? ['identity'] : ['identity','source','target']).map(role => [role,field]))},
    });
    result[name] = {oneOf:[legacy[name],keyed]};
  }
  const traversal = structuredClone(legacy.traverse);
  traversal.required.push('path_mode');
  traversal.properties.path_mode = {enum:['walk','trail','acyclic']};
  traversal.properties.emit = {enum:['nodes','paths']};
  // Both emissions apply the same existing homogeneous and patterned filters.
  const predicate = traversal.properties.hops.items.properties.edge_where;
  traversal.properties.edge_where = structuredClone(predicate);
  traversal.properties.node_where = structuredClone(predicate);
  traversal.oneOf[0].not.anyOf.push({required:['edge_where']},{required:['node_where']});
  result.traverse = {oneOf:[legacy.traverse,traversal]};
  return result;
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
