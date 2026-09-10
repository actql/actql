import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {cellValue,pivotSchema,checkPivotSchemas} from './pivot-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('pivot schema keeps empty axes and distinguishes repeated indexes from generated names',()=>{
  assert.equal(pivotSchema.properties.index.minItems,undefined);
  assert.equal(pivotSchema.properties.index.uniqueItems,undefined);
  assert.equal(pivotSchema.properties.values.minItems,undefined);
  assert.equal(pivotSchema.properties.values.uniqueItems,true);
  assert.deepEqual(pivotSchema.properties.aggregate.enum,['sum','avg','count','min','max','first']);
  assert.deepEqual(pivotSchema.properties.fill,cellValue);
  assert.deepEqual(cellValue.oneOf[0].required,['$param']);
  assert.equal(cellValue.oneOf[0].additionalProperties,false);
  assert.deepEqual(cellValue.oneOf[1].properties.literal,{});
  assert.deepEqual(cellValue.oneOf[2],{not:{type:'object',minProperties:1,maxProperties:1,anyOf:[{required:['$param']},{required:['literal']}]}});
});

test('both embedded pivot bodies and dependent pins are checked',()=>{
  const registry=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkPivotSchemas(registry);
  for(const index of [0,1]) {
    const r=structuredClone(registry);
    parameterPrograms(r)[index].properties.steps.items.properties.pivot.properties.values.minItems=1;
    assert.throws(()=>checkPivotSchemas(r));
  }
});
