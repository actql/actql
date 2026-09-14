import {parameter, fieldPattern} from './aggregate-schema.mjs';
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parameterPrograms} from './parameter-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

export function scoreContractSchema() {
  const field = {type:'string',minLength:1};
  return {type:'object',additionalProperties:false,required:['domain','range','normalization'],properties:{
    domain:field,normalization:field,higher_is_better:{const:true},
    range:{type:'array',minItems:2,maxItems:2,items:{type:'number'}},
  }};
}

export function vectorSchemas() {
  const field = {type:'string',minLength:1};
  const positive = {type:'integer',minimum:1,maximum:9007199254740991};
  const common = {by:{type:'array',items:field},candidate:field,k:positive};
  const scoreContract = scoreContractSchema();
  const scored = policy => ({type:'object',additionalProperties:false,required:['with','by','candidate','score','score_policy','score_contract','k'],properties:{
    ...common,with:field,score:field,score_contract:scoreContract,score_policy:policy,tie_break:{type:'array',items:field},
  }});
  return {
    text_rank:{type:'object',additionalProperties:false,required:['queries','query_id','query_text','candidate_id','candidate_text','tokenizer','scoring','k'],properties:{
      queries:field,query_id:field,query_text:field,candidate_id:field,candidate_text:field,
      tokenizer:{enum:['unicode_words','char_bigram']},k:positive,
      scoring:{type:'object',additionalProperties:false,required:['bm25'],properties:{bm25:{type:'object',additionalProperties:false,required:['k1','b'],properties:{k1:{type:'number',exclusiveMinimum:0},b:{type:'number',minimum:0,maximum:1}}}}},
    }},
    merge_rankings:{oneOf:[
      scored({const:'max'}),
      scored({type:'object',additionalProperties:false,required:['weighted_sum'],properties:{weighted_sum:{
        type:'object',additionalProperties:false,required:['left','right'],properties:{left:{type:'number',minimum:0,maximum:1},right:{type:'number',minimum:0,maximum:1}},
      }}}),
      {type:'object',additionalProperties:false,required:['with','by','candidate','rank','score_policy','k'],properties:{
        ...common,with:{oneOf:[field,{type:'array',minItems:1,items:field}]},rank:field,
        score_policy:{type:'object',additionalProperties:false,required:['rrf'],properties:{rrf:{
          type:'object',additionalProperties:false,required:['rank_constant','weights','rank_window'],properties:{
            rank_constant:positive,rank_window:positive,weights:{type:'array',minItems:2,items:{type:'number',minimum:0},contains:{type:'number',exclusiveMinimum:0}},
          },
        }}},
      }},
    ]},
    pool_vectors:{type:'object',additionalProperties:false,required:['by','method'],properties:{
      vector:{type:'string',minLength:1},
      by:{type:'array',minItems:1,uniqueItems:true,items:{type:'string',minLength:1}},
      method:{enum:['mean','sum','max']},
      output_id:{type:'string',pattern:fieldPattern},
    },allOf:[{if:{required:['output_id']},then:{properties:{by:{maxItems:1}}}}]},
    nearest:{type:'object',additionalProperties:false,required:['queries','metric','k'],properties:{
      queries:{type:'string',minLength:1},metric:{enum:['cosine','dot','l2']},
      k:{type:'integer',minimum:1,maximum:9007199254740991},
      ...Object.fromEntries(['candidate_id','candidate_vector','query_id','query_vector'].map(k => [k,{type:'string',minLength:1}])),
    }},
    to_vectors: {type:'object',additionalProperties:false,required:['id','vector'],properties:{
      id:{type:'string',minLength:1},vector:{type:'string',minLength:1},
    }},
    normalize_vectors: {const:true},
    score_vectors: {type:'object',additionalProperties:false,required:['query','metric'],properties:{
      query:{oneOf:[{type:'array',minItems:1,items:{type:'number'}},parameter]},
      metric:{enum:['cosine','dot','l2']},
    }},
  };
}

export function checkVectorSchemas(registry) {
  for (const program of parameterPrograms(registry)) {
    const properties = program.properties.steps.items.properties;
    for (const operation of Object.keys(vectorSchemas())) {
      assert.deepEqual(properties[operation], vectorSchemas()[operation]);
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
      for (const operation of Object.keys(vectorSchemas())) {
        program.properties.steps.items.properties[operation] = vectorSchemas()[operation];
      }
    }
    for (const [name, body] of Object.entries(registry.artifact_schemas)) {
      registry.artifact_schema_cids[name] = machineCid(body);
    }
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkVectorSchemas(registry);
  console.log('Vector operation schemas and artifact pins verified.');
}
