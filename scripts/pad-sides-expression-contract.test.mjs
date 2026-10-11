import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {updatePadSidesContracts, padSidesLaws} from './pad-sides-expression-contract.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const bodies=()=>['actql-expressions','actql-protocol-schemas'].map(name=>read(`spec/contracts/${name}.json`));
// Independent grammar fixture for unit tests. The CLI checks the actual pinned
// EBNF; unit success does not establish generated artifact freshness.
const grammar='scalar-call = "replace" | "left" | "right" | "lpad" | "rpad" ;\n';
const shape=(e,name)=>e.schemas.expression.$defs.expression.oneOf.find(x=>x.required?.[0]===name);

test('padding and side contracts preserve ordered arity local refs and omission',()=>{
 const input=bodies();updatePadSidesContracts(...input,grammar,true);
 updatePadSidesContracts(...input,grammar);
 const frozen=structuredClone(input);updatePadSidesContracts(...input,grammar,true);
 assert.deepEqual(input,frozen);
 for(const name of ['left','right','lpad','rpad']) {
  assert.deepEqual(shape(input[0],name).properties[name],{type:'array',minItems:2,maxItems:name.endsWith('pad')?3:2,items:{$ref:'#/$defs/expression'}});
  assert.deepEqual(input[0].laws[name],padSidesLaws[name]);
 }
});

test('padding and side contracts reject changed ordering shape domain and budget laws',()=>{
 for(const mutate of [
  ([e])=>{shape(e,'left').properties.left.maxItems=3;},
  ([e])=>{shape(e,'right').additionalProperties=true;},
  ([e])=>{shape(e,'lpad').properties.lpad.minItems=3;},
  ([e])=>{shape(e,'rpad').properties.rpad.items.$ref='#/$defs/other';},
  ([e])=>{e.laws.left.value='count UTF-16 code units';},
  ([e])=>{e.laws.right.identity='duplicate length child';},
  ([e])=>{e.laws.lpad.value='empty pattern is a no-op';},
  ([e])=>{e.laws.rpad.evaluation='allocate then measure';},
  ([e])=>{e.grammar_sha256='0'.repeat(64);},
  ([,p])=>{p.artifact_registry_cid='sha256:'+'0'.repeat(64);},
 ]) {
  const input=bodies();updatePadSidesContracts(...input,grammar,true);mutate(input);
  assert.throws(()=>updatePadSidesContracts(...input,grammar));
 }
});


test('padding contract writer refuses an incomplete grammar before changing bodies',()=>{
 for (const name of ['left','right','lpad','rpad']) {
  const input=bodies();
  const before=structuredClone(input);
  assert.throws(()=>updatePadSidesContracts(...input,grammar.replace(`| "${name}"`,''),true));
  assert.deepEqual(input,before);
 }
});
