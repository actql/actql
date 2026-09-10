import assert from 'node:assert/strict';
import {orderKeys,parameter,positive,fieldPattern} from './aggregate-schema.mjs';
import {crossJoinSchema} from './cross-join-schema.mjs';
import {millisecondsSchema} from './window-schema.mjs';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function eventSchemas() {
  const field = {type:'string',pattern:fieldPattern};
  const interval = {type:'object',additionalProperties:false,required:['start','end'],properties:{start:field,end:field}};
  const point = {type:'object',additionalProperties:false,required:['time'],properties:{time:field}};
  const timestamp = {oneOf:[{type:'string',pattern:'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$(?![\\s\\S])'},parameter]};
  return {
    sequence: {type:'object',additionalProperties:false,
      required:['by','id','time','pattern','within','overlap','contiguity'],properties:{
        by:{type:'array',items:field},id:field,time:field,
        pattern:{type:'array',minItems:2,items:{type:'object',additionalProperties:false,
          required:['as','where'],properties:{as:{type:'string',minLength:1},where:{$ref:'#/$defs/predicate'}}}},
        within:millisecondsSchema(),overlap:{enum:['allow','disallow']},
        contiguity:{enum:['adjacent','subsequence']},
        max_matches_per_key:positive,max_output_rows:positive,
      }},
    asof_join: {type:'object',additionalProperties:false,
      required:['with','kind','by','left_time','right_time','direction','tolerance','select'],
      properties:{
        with:{type:'string',minLength:1},kind:{enum:['left','inner']},
        by:{type:'array',items:{type:'object',additionalProperties:false,
          required:['left','right'],properties:{left:field,right:field}}},
        left_id:field,left_time:field,right_time:field,
        direction:{enum:['backward','forward','nearest']},tolerance:millisecondsSchema(),
        right_tie_break:{type:'array',items:field},select:crossJoinSchema().properties.select,
      }},
    interval_join: {type:'object',additionalProperties:false,
      required:['with','kind','mode','on','left','right'],properties:{
        with:{type:'string',minLength:1},kind:{enum:['inner','left','semi','anti']},
        mode:{enum:['point_in_interval','overlap']},
        on:{type:'array',items:{type:'object',additionalProperties:false,
          required:['left','right'],properties:{left:field,right:field}}},
        left:{oneOf:[point,interval]},right:interval,
        select:crossJoinSchema().properties.select,max_output_rows:positive,
      },allOf:[{if:{properties:{mode:{const:'point_in_interval'}},required:['mode']},
        then:{properties:{left:point}},else:{properties:{left:interval}}}]},
    time_series: {type:'object',additionalProperties:false,required:['start','end','step'],properties:{
      start:timestamp,end:timestamp,step:millisecondsSchema(),
    }},
    session: {type:'object',additionalProperties:false,required:['by','gap'],
      dependentRequired:{id:['time'],time:['id']},properties:{
        id:{type:'string',minLength:1},time:{type:'string',minLength:1},
        by:{type:'array',items:{type:'string',minLength:1}},gap:millisecondsSchema(),
      }},
    dedupe_events: {type:'object',additionalProperties:false,required:['by','order_by'],properties:{
      by:{type:'array',items:{type:'string',minLength:1}},order_by:orderKeys,
    }},
    to_events: {type:'object',additionalProperties:false,required:['id','time'],properties:{
      id:{type:'string',minLength:1},time:{type:'string',minLength:1},
    }},
    watermark_events: {type:'object',additionalProperties:false,required:['watermark_ms','policy'],properties:{
      watermark_ms:{type:'number'},policy:{enum:['drop','mark']},
    }},
  };
}

export function checkEventSchemas(registry) {
  for (const program of parameterPrograms(registry)) {
    const properties = program.properties.steps.items.properties;
    for (const operation of Object.keys(eventSchemas())) {
      assert.deepEqual(properties[operation], eventSchemas()[operation]);
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
      for (const operation of Object.keys(eventSchemas())) {
        program.properties.steps.items.properties[operation] = eventSchemas()[operation];
      }
    }
    for (const [name, body] of Object.entries(registry.artifact_schemas)) {
      registry.artifact_schema_cids[name] = machineCid(body);
    }
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkEventSchemas(registry);
  console.log('Event operation schemas and artifact pins verified.');
}
