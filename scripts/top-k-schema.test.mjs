import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {topKSchema,checkTopKSchemas} from './top-k-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';
test('top-k grammar retains distinct operators and symbolic positive bounds',()=>{
  assert.equal(topKSchema().properties.partition_by,undefined);
  assert.equal(topKSchema(true).properties.partition_by.minItems,undefined);
  assert.equal(topKSchema(true).properties.partition_by.uniqueItems,undefined);
  for(const p of [false,true]) {
    const s=topKSchema(p);
    assert.equal(s.additionalProperties,false);
    assert.equal(s.properties.by.minItems,1);
    assert.deepEqual(s.properties.k.oneOf[0],{type:'integer',minimum:1,maximum:9007199254740991});
    assert.deepEqual(s.properties.k.oneOf[1].required,['$param']);
  }
});
test('both embedded top-k schemas and pins detect drift',()=>{
  const registry=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkTopKSchemas(registry);
  for(const index of [0,1]) {
    const r=structuredClone(registry);
    parameterPrograms(r)[index].properties.steps.items.properties.top_k_by.properties.partition_by.minItems=1;
    assert.throws(()=>checkTopKSchemas(r));
  }
});
