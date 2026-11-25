import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {analyticSchema,checkAnalyticSchemas} from './analytic-schema.mjs';
import {aggregateSchema} from './aggregate-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('analytic calls reuse the frame aggregate matrix without local ordering',()=>{
  assert.equal((analyticSchema.properties.partition_by as Record<string, unknown>).minItems,undefined);
  assert.equal((analyticSchema.properties.partition_by as Record<string, unknown>).uniqueItems,undefined);
  assert.equal(analyticSchema.properties.order_by.minItems,0);
  const calls=analyticSchema.properties.functions.additionalProperties.oneOf;
  assert.deepEqual(calls.slice(4),aggregateSchema(true).oneOf);
  for(const c of calls) assert.equal((c.properties as Record<string, unknown>).order_by,undefined);
  for(const c of calls.slice(0,4)) {
    assert.equal((c.properties as Record<string, unknown>).filter,undefined);
    assert.equal((c.properties as Record<string, unknown>).distinct,undefined);
  }
  assert.deepEqual(calls[2].properties.default, {$ref:'#/$defs/value_expression'});
  assert.equal(calls[0].properties.default, undefined);
  assert.equal(calls[3].properties.default, undefined);
  assert.deepEqual(calls[1].required, ['fn','buckets']);
  assert.deepEqual(calls[1].properties.buckets!.oneOf[0],
    {type:'integer', minimum:1, maximum:9007199254740991});
  assert.ok(analyticSchema.allOf[0].if.properties.functions.additionalProperties.oneOf.includes(calls[1]));
  assert.deepEqual(analyticSchema.allOf[0].then,{not:{required:['frame']}});
  assert.equal((analyticSchema.allOf[0] as Record<string, unknown>).else, undefined);
  const emptyOrder = analyticSchema.allOf[1];
  assert.deepEqual(emptyOrder.if,{properties:{order_by:{maxItems:0}}});
  assert.deepEqual(emptyOrder.then.not,{required:['frame']});
  const unordered = emptyOrder.then.properties.functions.additionalProperties.oneOf;
  assert.deepEqual(unordered, calls.slice(4).filter(call =>
    !['array_agg','string_agg','first','last'].includes((call as ReturnType<typeof aggregateSchema>['oneOf'][number]).properties.fn.const)));
});

test('analytic schema drift is rejected in both Program copies',()=>{
  const registry: Parameters<typeof checkAnalyticSchemas>[0]=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  checkAnalyticSchemas(registry);
  for(const index of [0,1]) {
    const r=structuredClone(registry);
    parameterPrograms(r)[index].properties.steps.items.properties.analytic.properties.frame.additionalProperties=true;
    assert.throws(()=>checkAnalyticSchemas(r));
  }
});
