import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {verifyIdentity} from './check-canonical-json.mjs';

const fields=['max_input_codepoints','max_input_utf8_bytes','max_output_bytes','max_pattern_bytes','max_replacements'];
const contracts=JSON.parse(readFileSync('spec/contracts/actql-expressions.json','utf8'));
const expected={type:'object',additionalProperties:false,
  required:['version','max_input_codepoints','max_input_utf8_bytes','max_pattern_bytes','max_output_bytes','max_replacements'],
  properties:{version:{const:'actql-text-time-host-policy/0.1'},
    ...Object.fromEntries(fields.map(k=>[k,{type:'integer',minimum:1,maximum:9007199254740991}]))}};

test('text-time policy reader domain matches every existing embedded machine schema',()=>{
  assert.deepEqual(contracts.schemas.fragment.properties.request.properties.text_time_policy,expected);
  assert.deepEqual(contracts.schemas.predicate_consumer.properties.request.properties.text_time_policy,expected);
  assert.deepEqual(contracts.schemas.predicate_consumer.$defs.fragment.properties.request.properties.text_time_policy,expected);
});

test('text-time policy fixture identity is independently fixed',()=>{
  const body={...Object.fromEntries(fields.map(k=>[k,1])),version:'actql-text-time-host-policy/0.1'};
  verifyIdentity(body,'sha256:5fac567c3a4cc4da2a9494a9fc7b0d2304157c3641100f73e752426e62c8d8c1');
});
