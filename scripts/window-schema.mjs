import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {groupSchema,orderKeys,positive,fieldPattern,parameter} from './aggregate-schema.mjs';

export function watermarkRowsSchema() {
  return {type:'object',additionalProperties:false,required:['time','late_policy'],
    oneOf:[{required:['watermark_ms'],not:{required:['max_skew']}},
      {required:['max_skew'],not:{required:['watermark_ms']}}],
    properties:{time:{type:'string',minLength:1},late_policy:{enum:['drop','mark']},
      watermark_ms:{oneOf:[{type:'number'},parameter]},max_skew:millisecondsSchema()},
  };
}

export function lagSchema() {
  return {type:'object',additionalProperties:false,
    required:['partition_by','order_by','field','output'],properties:{
      partition_by:{type:'array',items:{type:'string',minLength:1}},
      order_by:orderKeys,field:{type:'string',minLength:1},
      output:{type:'string',pattern:fieldPattern},offset:positive,
    }};
}

export function millisecondsSchema(signed=false) {
  return {oneOf:[
    {type:'integer',minimum:signed?-9007199254740991:1,maximum:9007199254740991},
    {type:'string',pattern:'^0*[1-9][0-9]*([mM][sS]|[sSmMhHdD])$(?![\\s\\S])'},
    {type:'object',additionalProperties:false,required:['$param'],properties:{
      $param:{type:'string',pattern:'^[A-Za-z_][A-Za-z0-9_]*$(?![\\s\\S])'},
    }},
  ]};
}

export function windowSchema(relation) {
  return {type:'object',additionalProperties:false,
    required:relation?['kind','time','size']:['kind','size'],
    properties:{kind:{enum:['fixed','sliding']},
      ...(relation?{time:{type:'string',minLength:1}}:{}),
      size:millisecondsSchema(),step:millisecondsSchema(),offset:millisecondsSchema(true)},
    allOf:[{if:{properties:{kind:{const:'sliding'}},required:['kind']},then:{required:['step']}}],
  };
}

export function checkWindowSchemas(registry) {
  for(const p of parameterPrograms(registry)) {
    assert.deepEqual(p.properties.steps.items.properties.row_window,windowSchema(true));
    assert.deepEqual(p.properties.steps.items.properties.window_events,windowSchema(false));
    assert.deepEqual(p.properties.steps.items.properties.window_group,groupSchema());
    assert.deepEqual(p.properties.steps.items.properties.lag,lagSchema());
    assert.deepEqual(p.properties.steps.items.properties.watermark_rows,watermarkRowsSchema());
  }
  for(const [name,body] of Object.entries(registry.artifact_schemas)) assert.equal(registry.artifact_schema_cids[name],machineCid(body));
  assert.equal(registry.artifact_registry_cid,machineCid(registry.artifact_schemas));
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const path='spec/contracts/actql-protocol-schemas.json';
  const registry=JSON.parse(readFileSync(path,'utf8'));
  if(process.argv.includes('--write')) {
    for(const p of parameterPrograms(registry)) {
      p.properties.steps.items.properties.row_window=windowSchema(true);
      p.properties.steps.items.properties.window_events=windowSchema(false);
      p.properties.steps.items.properties.window_group=groupSchema();
      p.properties.steps.items.properties.lag=lagSchema();
      p.properties.steps.items.properties.watermark_rows=watermarkRowsSchema();
    }
    for(const [name,body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name]=machineCid(body);
    registry.artifact_registry_cid=machineCid(registry.artifact_schemas);
    writeFileSync(path,JSON.stringify(registry,null,2)+'\n');
  }
  checkWindowSchemas(registry);
  console.log('Window schemas and artifact pins verified.');
}
