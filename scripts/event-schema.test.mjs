import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {eventSchemas,checkEventSchemas} from './event-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('event dedupe preserves empty and repeated partition keys but requires order',()=>{
  const s=eventSchemas().dedupe_events;
  assert.equal(s.additionalProperties,false);
  assert.deepEqual(s.required,['by','order_by']);
  assert.equal(s.properties.by.minItems,undefined);
  assert.equal(s.properties.by.uniqueItems,undefined);
  assert.equal(s.properties.order_by.minItems,1);
});

test('session schema pairs relation roles and shares positive millisecond syntax',()=>{
  const s=eventSchemas().session;
  assert.deepEqual(s.required,['by','gap']);
  assert.deepEqual(s.dependentRequired,{id:['time'],time:['id']});
  assert.equal(s.additionalProperties,false);
  assert.equal(s.properties.gap.oneOf[0].minimum,1);
  assert.equal(s.properties.by.minItems,undefined);
});

test('watermark event options require literal threshold and explicit policy',()=>{
  assert.deepEqual(eventSchemas().watermark_events, {
    type:'object',additionalProperties:false,required:['watermark_ms','policy'],
    properties:{watermark_ms:{type:'number'},policy:{enum:['drop','mark']}},
  });
});
test('embedded event schemas and identity pins reject drift',()=>{
  const registry=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkEventSchemas(registry);
  for (const index of [0,1]) {
    for (const name of Object.keys(eventSchemas())) {
      const copy=structuredClone(registry);
      parameterPrograms(copy)[index].properties.steps.items.properties[name]={};
      assert.throws(()=>checkEventSchemas(copy));
    }
  }
});

test('interval joins require closed temporal operands and preserve repeated equality conditions',()=>{
  const s=eventSchemas().interval_join;
  assert.deepEqual(s.required,['with','kind','mode','on','left','right']);
  assert.deepEqual(s.properties.kind.enum,['inner','left','semi','anti']);
  assert.equal(s.additionalProperties,false);
  assert.equal(s.properties.on.minItems,undefined);
  assert.equal(s.properties.on.uniqueItems,undefined);
  assert.deepEqual(s.properties.on.items.required,['left','right']);
  assert.equal(s.properties.on.items.additionalProperties,false);
  assert.deepEqual(s.allOf[0].then.properties.left.required,['time']);
  assert.deepEqual(s.allOf[0].else.properties.left.required,['start','end']);
  assert.equal(s.allOf[0].then.properties.left.additionalProperties,false);
  assert.equal(s.allOf[0].else.properties.left.additionalProperties,false);
  assert.deepEqual(s.properties.right.required,['start','end']);
  assert.equal(s.properties.select.minProperties,1);
});
