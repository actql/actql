import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {setSchema, checkSetSchemas} from './set-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('set bodies require explicit literal multiplicity and reject extra members',()=>{
  const s=setSchema();
  assert.deepEqual(s.required,['with','duplicates']);
  assert.equal(s.additionalProperties,false);
  assert.deepEqual(s.properties.duplicates,{enum:['distinct','all']});
  assert.deepEqual(s.properties.with,{type:'string',minLength:1});
});
test('embedded set schemas and pins reject drift',()=>{
  const r=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkSetSchemas(r);
  for (const index of [0,1]) for (const op of ['except','intersect']) {
    const changed=structuredClone(r);
    parameterPrograms(changed)[index].properties.steps.items.properties[op].properties.duplicates.enum.push('ALL');
    assert.throws(()=>checkSetSchemas(changed));
  }
});
