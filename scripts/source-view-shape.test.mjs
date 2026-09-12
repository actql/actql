import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileSourceView} from './source-view-shape.mjs';
const schema=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json','utf8')).schemas.source_view;
test('read-mode semantic dispatch covers exactly the declared schema alternatives',()=>{
  const p=schema.properties.acquisition.properties;
  assert.deepEqual(p.default_mode.enum,['snapshot','changes','watch']);
  assert.deepEqual(p.modes.items.properties.mode.enum,['snapshot','changes','watch']);
  assert.deepEqual(p.modes.items.required,['mode','bounded']);
});
test('complete SourceView schema compiles without dropping fields or constraints',()=>{
  const text=compileSourceView(schema);
  assert.match(text,/SVPositiveInteger/);
  assert.match(text,/"max_keys_per_request", true/);
  assert.match(text,/"preserves_per_key_semantics", true, SVBoolean\(Some\(true\)\)/);
  assert.match(text,/"request_fields", true, SVArray\(1, true/);
  assert.match(text,/"resource_identity", false/);
});
test('new keywords and unsupported constraint changes require compiler support',()=>{
  for(const changed of [
    {...schema,unevaluatedProperties:false},
    {...schema,additionalProperties:true},
    {type:'string',minLength:2},
    {type:'string',pattern:'.*'},
    {type:'array',items:{type:'boolean'},uniqueItems:true},
    {type:'integer',minimum:0},
    {type:'boolean',enum:[true]},
  ])assert.throws(()=>compileSourceView(changed));
});
