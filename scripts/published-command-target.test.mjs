import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {parameterPrograms} from './parameter-schema.mjs';
import {publishedCommandTargetSchema,publishedCommandTargetSchemas} from './published-command-target.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const protocol=read('spec/contracts/actql-protocol-schemas.json');
const vectors=read('portability/corpus/published-command-selectors.json');
const command=p=>p.properties.effects.additionalProperties.oneOf.find(m=>m.properties?.command).properties.command;

test('canonical Command selector changes only the declared target alternative in both actual Program schemas',()=>{
  publishedCommandTargetSchemas(protocol);
  const prior=read(vectors.previous_program_file);
  assert.equal(machineCid(prior),vectors.previous_program_cid);
  assert.deepEqual(prior,JSON.parse(execFileSync('git',['show',vectors.previous_source+':spec/contracts/actql-protocol-schemas.json'],{encoding:'utf8',maxBuffer:16*1024*1024})).artifact_schemas.executable_plan.properties.execution_material.properties.program);
  for(const program of parameterPrograms(protocol)) {
    assert.equal(machineCid(program),vectors.program_cid);
    const restored=structuredClone(program);
    assert.deepEqual(command(restored).properties.target.oneOf[2],publishedCommandTargetSchema());
    command(restored).properties.target.oneOf.pop();
    assert.deepEqual(restored,prior,'No unrelated Program fields or old targets changed');
  }
});

test('real schema gate rejects missing and mutated Command alternatives without replacing old forms',()=>{
  for(const mutate of [
    p=>command(p).properties.target.oneOf.pop(),
    p=>{command(p).properties.target.oneOf[2].properties.published_command.additionalProperties=true;},
    p=>{command(p).properties.target.oneOf[2].properties.published_command.required.push('identifier_field');},
    p=>{command(p).properties.target.oneOf[0].additionalProperties=true;},
    p=>{command(p).properties.target.oneOf[1].required=[];},
  ]) {
    const changed=structuredClone(protocol);mutate(parameterPrograms(changed)[0]);
    assert.throws(()=>publishedCommandTargetSchemas(changed));
  }
});

test('independent complete selector Programs retain authored ID-free input and source identities',()=>{
  assert.equal(vectors.qualification,'Independent Python canonical JSON SHA-256; not compiler output or execution evidence');
  for(const c of vectors.programs) {
    assert.equal(machineCid(c.program),c.cid);
    const member=c.program.effects.send.command;
    assert.equal(member.contract,'command:mail.send.v1');
    assert.deepEqual(Object.keys(member.target),['published_command']);
    assert.equal(Object.hasOwn(member,'input_key'),false,'Identifier selection does not invent ID correspondence');
  }
  assert.notEqual(vectors.programs[0].cid,vectors.programs[1].cid);
});
