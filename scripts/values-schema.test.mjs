import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {cellSchema,checkValuesSchemas,valuesContract,generatorRule} from './values-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('cell grammar reserves exact singleton shapes without recursive substitution',()=>{
  const c=cellSchema();
  assert.deepEqual(c.oneOf[0].required,['$param']);
  assert.equal(c.oneOf[0].maxProperties,1);
  assert.deepEqual(c.oneOf[1].properties.literal,{});
  assert.deepEqual(c.oneOf[2].not.anyOf.map(s=>s.required[0]),['$param','literal']);
  const name=new RegExp(c.oneOf[0].properties.$param.pattern);
  for(const x of ['','a.b','1a']) assert.ok(!name.test(x));
  assert.ok(name.test('_a1'));
  assert.deepEqual(generatorRule.then.not,{required:['from']});
});
test('constructible contracts exclude opaque domains recursively and retain decimal guards',()=>{
  const r=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  const s=valuesContract(parameterPrograms(r)[0].$defs.value_contract);
  assert.equal(s.oneOf.find(s=>s.properties.type.const==='decimal').allOf.length,38);
  const serialized=JSON.stringify(s);
  assert.ok(!serialized.includes('"json"')); assert.ok(!serialized.includes('resource_ref'));assert.ok(!serialized.includes('artifact_ref'));
  assert.ok(!serialized.includes('"#/$defs/value_contract"'));assert.ok(serialized.includes('"#/$defs/values_contract"'));
});
test('embedded values contracts and generator rules detect drift',()=>{
  const r=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkValuesSchemas(r);
  for(const index of [0,1]) {
    const copy=structuredClone(r);
    parameterPrograms(copy)[index].properties.steps.items.properties.values.properties.schema.minProperties=0;
    assert.throws(()=>checkValuesSchemas(copy));
  }
});

test('finite and binary Relation operations require their normative registry signatures',()=>{
  const a=JSON.parse(readFileSync('spec/contracts/actql-aoa.json'));
  assert.deepEqual(a.target_registry_requirements['REL.values'],{inputs:[],output:'relation'});
  for(const op of ['REL.except_rows','REL.intersect_rows','REL.cross_join']) {
    assert.deepEqual(a.target_registry_requirements[op],{inputs:['relation','relation'],output:'relation'});
  }
});
