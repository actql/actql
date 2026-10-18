import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const fixture=JSON.parse(read('scripts/fixtures/public-model-task-signed64.json'));
const canonical=value=>value===null||typeof value!=='object'?JSON.stringify(value):
  Array.isArray(value)?'['+value.map(canonical).join(',')+']':
    '{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}';
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const without=(value,key)=>{const result={...value};delete result[key];return result;};

test('Signed64 caller fixture retains the exact public model Task document and its Moon literal',()=>{
  const guide=read('docs/guides/models.md').match(/```yaml\n([\s\S]*?)\n```/u)[1];
  assert.equal(fixture.document,guide);
  const source=read('src/query_program/public_model_task_signed64_test.mbt');
  const original=source.slice(source.indexOf('fn public_signed64_task_document()'),source.indexOf('fn public_signed64_task_limits()'));
  assert.equal([...original.matchAll(/^\s*#\|(.*)$/gmu)].map(value=>value[1]).join('\n'),guide);
  assert.equal(fixture.input_schema.fields.active_users.type,'int64');
  assert.deepEqual(fixture.output_schema.fields.level.enum,['low','medium','high']);
});

test('public Signed64 canonical materials retain every independent schema policy prompt and Task preimage',()=>{
  const profile=fixture.profile.model_defaults.models[0],task=fixture.task;
  assert.equal(cid(fixture.input_schema),fixture.input_schema_cid);
  assert.equal(cid(fixture.output_schema),fixture.output_schema_cid);
  assert.equal(cid(without(profile.data_handling,'cid')),profile.data_handling.cid);
  assert.equal(cid(without(fixture.prompt,'self_cid')),fixture.prompt.self_cid);
  assert.equal(cid(without(task,'contract_cid')),task.contract_cid);
  assert.equal(task.prompt_template_cid,fixture.prompt.self_cid);
  assert.equal(task.input_schema_cid,fixture.input_schema_cid);
  assert.equal(task.output_schema_cid,fixture.output_schema_cid);
  assert.deepEqual(task.input_contract,fixture.input_schema);
  assert.deepEqual(task.output_contract,fixture.output_schema);
  assert.equal(task.generation_config.max_output_tokens,200);
  assert.equal(profile.generation_config.max_output_tokens,100);
  const source=read('src/query_program/public_model_task_signed64_test.mbt');
  for(const original of [profile.data_handling.cid,fixture.input_schema_cid,fixture.output_schema_cid,
    fixture.prompt.self_cid,task.contract_cid,canonical(task),canonical(fixture.prompt)])assert(source.includes(original));
});

test('public Signed64 base Environment preserves the complete original README mapping and catalog inputs',()=>{
  const source=read('src/query_program/readme_hero_test.mbt');
  const original=JSON.parse(source.match(/#\|(\{"command_contracts"[^\n]*)/u)[1]);
  const expected=without(original,'evidence_bundle_cid');expected.model_task_contracts=[];
  assert.deepEqual(without(fixture.base_environment,'evidence_bundle_cid'),expected);
  assert.equal(cid(expected),fixture.base_environment_cid);
  assert.equal(fixture.base_environment.evidence_bundle_cid,fixture.base_environment_cid);
});
