import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parameterPrograms } from './parameter-schema.mjs';
import { machineCid } from './actql-spec-family.mjs';

export const functions = ['count', 'count_if', 'sum', 'avg', 'min', 'max', 'array_agg', 'string_agg', 'first', 'last', 'percentile_disc', 'percentile_cont', 'var_pop', 'var_samp', 'stddev_pop', 'stddev_samp'];
export const parameter = {type:'object', additionalProperties:false, required:['$param'], properties:{$param:{type:'string',pattern:'^[A-Za-z_][A-Za-z0-9_]*$'}}};
export const positive = {oneOf:[{type:'integer',minimum:1,maximum:9007199254740991},parameter]};
const field = {type:'string',minLength:1};
export const fieldPattern = '^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$';
export const orderKeys = {type:'array',minItems:1,items:{oneOf:[
  {type:'object',required:['field','dir','nulls'],additionalProperties:false,properties:{field,dir:{enum:['asc','desc']},nulls:{enum:['first','last']}}},
  {type:'object',minProperties:1,maxProperties:1,additionalProperties:{enum:['asc','desc']}},
]}};

export function aggregateSchema(analytic = false) {
  return {oneOf:functions.map(fn => {
    const properties = {fn:{const:fn},field,expr:{$ref:'#/$defs/value_expression'},filter:{$ref:'#/$defs/predicate'}};
    const required = ['fn'];
    const allOf = [{oneOf:fn === 'count' ? [{required:['field'],not:{required:['expr']}},{required:['expr'],not:{required:['field']}},{not:{anyOf:[{required:['field']},{required:['expr']}]}}] : [{required:['field'],not:{required:['expr']}},{required:['expr'],not:{required:['field']}}]}];
    if (['count','sum','avg','array_agg','string_agg'].includes(fn)) properties.distinct = {type:'boolean'};
    if (['min','max'].includes(fn)) properties.distinct = {const:false};
    if (fn === 'count') allOf.push({if:{required:['distinct'],properties:{distinct:{const:true}}},then:{anyOf:[{required:['field']},{required:['expr']}]}});
    if (['array_agg','string_agg','first','last'].includes(fn) && !analytic) {
      properties.order_by = orderKeys; required.push('order_by');
    }
    if (fn === 'array_agg') properties.max_items = positive;
    if (fn === 'string_agg') {
      properties.delimiter = {type:'string'}; properties.max_bytes = positive; required.push('delimiter');
    }
    if (fn.startsWith('percentile_')) {
      properties.fraction = {oneOf:[{type:'number',minimum:0,maximum:1},parameter]}; required.push('fraction');
    }
    return {type:'object',additionalProperties:false,required,properties,allOf};
  })};
}

export function groupSchema() {
  return {type:'object',additionalProperties:false,required:['by','aggregates'],properties:{
    by:{type:'array',items:field},
    aggregates:{type:'object',propertyNames:{pattern:fieldPattern},additionalProperties:aggregateSchema()},
  }};
}

export const aggregateBinding = 'REL.groupBy admits count, count_if, sum, avg, min, max, array_agg, string_agg, first, last, percentile_disc, percentile_cont, var_pop, var_samp, stddev_pop and stddev_samp. Authored calls have exactly one field or expr, except row-count count may omit both. Each filter is a separate root and gates demand for that call only. distinct true is admitted only for count with an argument, sum, avg, array_agg and string_agg; explicit false is additionally admitted for row-count count, min and max. Other functions reject the distinct member. Ordered functions use independent total orders, supplied by the analytic frame only in that context. avg requires number; decimal sum uses precision 38 and retains scale. array_agg excludes null and rejects recursively nonconstructible item contracts. Selected first/last values may retain reference and structured contracts. Percentile and statistical laws remain their own deterministic folds; binary64 sum/avg use numeric observation slots. Empty aggregate maps and repeated grouping references are retained; output keys occur once in first-occurrence order, and the empty global group emits one empty row even for empty input. Acceptance never authorizes operation deletion or preimage deduplication.';

export function checkAggregateSchemas(registry, expressions) {
  for (const p of parameterPrograms(registry)) assert.deepEqual(p.properties.steps.items.properties.group, groupSchema());
  assert.equal(expressions.laws.aggregate_binding, aggregateBinding);
  for (const [name, body] of Object.entries(registry.artifact_schemas)) assert.equal(registry.artifact_schema_cids[name], machineCid(body));
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const registryPath = 'spec/contracts/actql-protocol-schemas.json';
  const expressionsPath = 'spec/contracts/actql-expressions.json';
  const registry = JSON.parse(readFileSync(registryPath, 'utf8'));
  const expressions = JSON.parse(readFileSync(expressionsPath, 'utf8'));
  if (process.argv.includes('--write')) {
    for (const p of parameterPrograms(registry)) p.properties.steps.items.properties.group = groupSchema();
    expressions.laws.aggregate_binding = aggregateBinding;
    for (const [name, body] of Object.entries(registry.artifact_schemas)) registry.artifact_schema_cids[name] = machineCid(body);
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(registryPath, JSON.stringify(registry,null,2)+'\n');
    writeFileSync(expressionsPath, JSON.stringify(expressions,null,2)+'\n');
  }
  checkAggregateSchemas(registry, expressions);
  console.log('Aggregate grammar and pinned binding laws verified.');
}
