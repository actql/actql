import {readHistoricalJson} from './historical-json.mjs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
// Independently hash fixed authored JSON and retained envelopes, never runtime output.
const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}':JSON.stringify(value);
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const read = readHistoricalJson;
const history=read('portability/corpus/historical/pre-unicode-scalars-contract-identities.json');
const earlier=Object.fromEntries(history.contracts.map(v=>[v.id,v.body]));

test('unicode-scalars retains complete predecessor bodies and identity preimages',()=>{
  assert.equal(history.source_revision,"c7fe4309a9b9433fab1ed68b14b46a132256efb7");
  assert.equal(history.source_revision_kind,"published-parent-with-exact-recovery-tree-match");
  assert.equal(history.recovery_revision,'943ac358a07345c375b28eefd4d41670616ac1ea');
  assert.equal(history.source_tree,'a1ba5254cfd1ddfe3f889e4778f1157362e12b4b');
  assert.equal(cid(history),"sha256:6692b77da7953ebc3a9cc9133000317ffd825ec447161b2b3a6fd667d1f23211");
  assert.equal(history.contracts.length,12);
  for(const item of history.contracts)assert.equal(cid(item.body),item.cid,item.id);
  for(const item of history.expression_fragments.cases){assert.equal(canonical(item.body),item.canonical);assert.equal(cid(item.body),item.cid);assert.equal(Buffer.byteLength(item.canonical),item.bytes);}
  for(const item of history.ordered_fragment.preimages){assert.equal(canonical(history.ordered_fragment[item.id]),item.canonical);assert.equal(cid(history.ordered_fragment[item.id]),item.cid);}
  assert.equal(cid(history.policy_candidates.body),history.policy_candidates.expected_cid);
  const preimages=read('portability/corpus/historical/pre-unicode-scalars-preimages.json');
  assert.equal(cid(preimages),"sha256:714af6f712a7485a810bcef3fca556f222da8199ae799884b1f345a73d387d34");
  assert.equal(preimages.source_revision,history.source_revision);
  assert.equal(preimages.expression_contract_cid,cid(earlier.expression_contract));
  assert.equal(preimages.sources.length,17);assert.equal(new Set(preimages.sources.map(v=>v.source)).size,17);
  for(const item of preimages.sources)assert.equal(cid(item.body),item.cid,item.source);
  assert.equal(preimages.identity_envelopes.length,21);
  for(const item of preimages.identity_envelopes){assert.equal(canonical(item.envelope),item.canonical);assert.equal(cid(item.envelope),item.expected_cid);}
});

test('unicode-scalars adds only its exact closed source and machine alternatives and laws',()=>{
  const successor=Object.fromEntries(read('portability/corpus/historical/pre-repeat-reverse-contract-identities.json').contracts.map(v=>[v.id,v.body]));
  const expression=successor.expression_contract;
  const program=successor.program_schema;
  const shapes={"byte_length":{},"unicode":{},"chr":{}},names=new Set(Object.keys(shapes)),counts={};
  function withoutIncrement(value){
    if(Array.isArray(value))return value.map(withoutIncrement);
    if(value===null||typeof value!=='object')return value;
    const result=Object.fromEntries(Object.entries(value).map(([k,v])=>[k,withoutIncrement(v)]));
    if(result.oneOf)result.oneOf=result.oneOf.filter(shape=>{
      const name=shape.properties?.op?.const??(shape.required?.length===1?shape.required[0]:null);
      if(!names.has(name))return true;
      const node=Boolean(shape.properties?.op),body=shape.properties[node?'body':name];
      assert.equal(shape.additionalProperties,false);assert.deepEqual(shape.required,node?['op','body']:[name]);
      assert.deepEqual(Object.keys(body),['$ref']);
      assert.match(body.$ref,/^#\/\$defs\/(expression|source_expression|machine_expression|value_expression)$/u);
      counts[name]=(counts[name]??0)+1;return false;
    });return result;
  }
  const before=withoutIncrement(expression);
  for(const name of names){assert.ok(expression.laws[name]);delete before.laws[name];}
  before.grammar_sha256=earlier.expression_contract.grammar_sha256;
  assert.deepEqual(before,earlier.expression_contract);
  assert.deepEqual(withoutIncrement(program),earlier.program_schema);
  assert.deepEqual(Object.keys(counts).sort(),[...names].sort());
  for(const count of Object.values(counts))assert.equal(count,8);
  assert.notEqual(cid(expression),cid(earlier.expression_contract));assert.notEqual(cid(program),cid(earlier.program_schema));
  for(const [id,path] of [['scalar_law_manifest','spec/dependencies/aoa-rela-scalar-laws.json'],['production_profile_registry','spec/contracts/actql-production-profile-schemas.json'],['barrier_manifest','spec/manifests/actql-barrier-contracts-0.1.json']])assert.deepEqual(id==='scalar_law_manifest'
    ? read('portability/corpus/historical/pre-exact-utc-timestamp.json').contracts.find(c=>c.id===id).body
    : successor[id],earlier[id]);
});
