import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {eventSchemas,checkEventSchemas} from './event-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

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
    for (const name of ['watermark_events','to_events']) {
      const copy=structuredClone(registry);
      parameterPrograms(copy)[index].properties.steps.items.properties[name]={};
      assert.throws(()=>checkEventSchemas(copy));
    }
  }
});
