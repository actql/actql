import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {aggregateSchema, groupSchema, checkAggregateSchemas, functions} from './aggregate-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('aggregate schema has closed argument and modifier matrices for all functions', () => {
  for (const analytic of [false,true]) {
    const schema=aggregateSchema(analytic);
    assert.deepEqual(schema.oneOf.map(s=>s.properties.fn.const),functions);
    for(const call of schema.oneOf) {
      const fn=call.properties.fn.const;
      assert.equal(call.additionalProperties,false);
      assert.equal(call.allOf[0].oneOf.length,fn==='count'?3:2);
      assert.equal(Object.hasOwn(call.properties,'order_by'),!analytic&&['array_agg','string_agg','first','last'].includes(fn));
      assert.equal(Object.hasOwn(call.properties,'fraction'),fn.startsWith('percentile_'));
      if (['min','max'].includes(fn)) assert.deepEqual(call.properties.distinct,{const:false});
      if (['count_if','first','last','percentile_disc','percentile_cont','var_pop','var_samp','stddev_pop','stddev_samp'].includes(fn)) assert.equal(call.properties.distinct,undefined);
    }
  }
  const s=groupSchema();
  assert.equal(s.properties.by.minItems,undefined);
  assert.equal(s.properties.by.uniqueItems,undefined);
  assert.equal(s.properties.aggregates.minProperties,undefined);
});

test('embedded group schemas and aggregate binding law cannot drift', () => {
  const registry=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  const expressions=JSON.parse(readFileSync('spec/contracts/actql-expressions.json'));
  checkAggregateSchemas(registry,expressions);
  for(const p of [0,1]) {
    const mutated=structuredClone(registry);
    parameterPrograms(mutated)[p].properties.steps.items.properties.group.properties.aggregates.minProperties=1;
    assert.throws(()=>checkAggregateSchemas(mutated,expressions));
  }
  const mutated=structuredClone(expressions);
  mutated.laws.aggregate_binding='legacy seven functions';
  assert.throws(()=>checkAggregateSchemas(registry,mutated));
});
