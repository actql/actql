import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {crossJoinSchema,checkCrossJoinSchemas} from './cross-join-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';
test('cross join has no equality keys and requires explicit singleton spelling',()=>{
  const s=crossJoinSchema();
  assert.equal(s.additionalProperties,false);
  assert.deepEqual(s.required,['with']);
  assert.deepEqual(s.properties.right_rows,{const:'one'});
  assert.equal(s.properties.on,undefined);
  assert.equal(s.properties.select.minProperties,1);
  const ref=new RegExp(s.properties.select.additionalProperties.pattern);
  assert.ok(ref.test('left.id'));assert.ok(ref.test('right.line\nname'));assert.ok(!ref.test('id'));
});
test('embedded cross join contracts and pins reject stale constraints',()=>{
  const r=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkCrossJoinSchemas(r);
  for(const index of [0,1]) {
    const changed=structuredClone(r);
    parameterPrograms(changed)[index].properties.steps.items.properties.cross_join.properties.right_rows={type:'string'};
    assert.throws(()=>checkCrossJoinSchemas(changed));
  }
});
