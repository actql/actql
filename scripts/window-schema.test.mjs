import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {millisecondsSchema,windowSchema,lagSchema,checkWindowSchemas} from './window-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('window options distinguish signed offsets and positive durations',()=>{
  assert.equal(millisecondsSchema().oneOf[0].minimum,1);
  assert.equal(millisecondsSchema(true).oneOf[0].minimum,-9007199254740991);
  const lexical=new RegExp(millisecondsSchema().oneOf[1].pattern);
  for(const s of ['1ms','01S','2m','3H','4d']) assert.ok(lexical.test(s));
  for(const s of ['0s','-1s','1.5s','1e3ms','１s','1 s','1s\n','1s\r\n']) assert.ok(!lexical.test(s));
  assert.deepEqual(windowSchema(false).allOf[0].then.required,['step']);
  assert.ok(!('time' in windowSchema(false).properties));
  assert.ok(windowSchema(true).required.includes('time'));
});

test('embedded window schema and pins reject drift',()=>{
  const r=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkWindowSchemas(r);
  for(const index of [0,1]) {
    const copy=structuredClone(r);
    parameterPrograms(copy)[index].properties.steps.items.properties.row_window.properties.offset=millisecondsSchema();
    assert.throws(()=>checkWindowSchemas(copy));
  }
});

test('lag requires explicit nonempty order and admits omitted or positive offset',()=>{
  const s=lagSchema();
  assert.deepEqual(s.required,['partition_by','order_by','field','output']);
  assert.equal(s.properties.order_by.minItems,1);
  assert.equal(s.properties.partition_by.minItems,undefined);
  assert.equal(s.properties.offset.oneOf[0].minimum,1);
  assert.equal(s.properties.offset.oneOf[0].maximum,9007199254740991);
  assert.equal(s.additionalProperties,false);
});
