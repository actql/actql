import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
// This independent oracle hashes fixed authored JSON, never product output.
const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}':JSON.stringify(value);
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const history=read('portability/corpus/historical/pre-finite-math-contract-identities.json');
const earlier=Object.fromEntries(history.contracts.map(v=>[v.id,v.body]));

test('finite math preserves complete recovered ROUND predecessor identities',()=>{
  assert.equal(history.source_revision,'db4f717a5f3a9aea094a027e51e308463c84d597');
  assert.equal(history.source_revision_kind,'published-parent-with-exact-recovery-tree-match');
  assert.equal(history.recovery_revision, 'd01a44c24d14f176ecc9fbceae3163f6efbeddfe');
  assert.equal(history.source_tree, 'bbe0535b0abb8f348af436651cc4fb214307a2cd');
  assert.equal(cid(history),'sha256:c8909a0bcfe12a9c36a98143620c4c9e260d3ef2a40b0300298ef695584adf9c');
  assert.equal(history.contracts.length,12);
  for(const item of history.contracts)assert.equal(cid(item.body),item.cid,item.id);
  for(const item of history.expression_fragments.cases){assert.equal(canonical(item.body),item.canonical);assert.equal(cid(item.body),item.cid);assert.equal(Buffer.byteLength(item.canonical),item.bytes);}
  for(const item of history.ordered_fragment.preimages){assert.equal(canonical(history.ordered_fragment[item.id]),item.canonical);assert.equal(cid(history.ordered_fragment[item.id]),item.cid);}
  assert.equal(cid(history.policy_candidates.body),history.policy_candidates.expected_cid);
  const preimages=read('portability/corpus/historical/pre-finite-math-preimages.json');
  assert.equal(cid(preimages),'sha256:6e493bab7d787593c1c1c4a43814c28afabd375e4d0aca7296fc93f4a294080d');
  assert.equal(preimages.source_revision,history.source_revision);
  assert.equal(preimages.expression_contract_cid,cid(earlier.expression_contract));
  assert.equal(preimages.sources.length,17);assert.equal(new Set(preimages.sources.map(v=>v.source)).size,17);
  for(const item of preimages.sources)assert.equal(cid(item.body),item.cid,item.source);
  assert.equal(preimages.identity_envelopes.length,21);
  for(const item of preimages.identity_envelopes){assert.equal(canonical(item.envelope),item.canonical);assert.equal(cid(item.envelope),item.expected_cid);}
});

test('finite math extends only five closed source and machine alternatives and their laws',()=>{
  const expression=read('spec/contracts/actql-expressions.json');
  const program=read('spec/contracts/actql-protocol-schemas.json').artifact_schemas.executable_plan.properties.execution_material.properties.program;
  const names=new Set(['pow','exp','ln','log','log10']);const counts={};
  function withoutMath(value){
    if(Array.isArray(value))return value.map(withoutMath);
    if(value===null||typeof value!=='object')return value;
    const result=Object.fromEntries(Object.entries(value).map(([k,v])=>[k,withoutMath(v)]));
    if(result.oneOf)result.oneOf=result.oneOf.filter(shape=>{
      const name=shape.properties?.op?.const??(shape.required?.length===1?shape.required[0]:null);
      if(!names.has(name))return true;
      const node=Boolean(shape.properties?.op);const body=shape.properties[node?'body':name];
      assert.equal(shape.additionalProperties,false);assert.deepEqual(shape.required,node?['op','body']:[name]);
      if(name==='pow'||name==='log'){assert.equal(body.type,'array');assert.equal(body.minItems,2);assert.equal(body.maxItems,2);assert.deepEqual(Object.keys(body.items),['$ref']);}
      else assert.deepEqual(Object.keys(body),['$ref']);
      counts[name]=(counts[name]??0)+1;return false;
    });return result;
  }
  const before=withoutMath(expression);
  for(const name of names){assert.ok(expression.laws[name]);delete before.laws[name];}
  before.grammar_sha256=earlier.expression_contract.grammar_sha256;
  assert.deepEqual(before,earlier.expression_contract);
  assert.deepEqual(withoutMath(program),earlier.program_schema);
  assert.deepEqual(Object.keys(counts).sort(),[...names].sort());
  for(const count of Object.values(counts))assert.equal(count,8);
  assert.notEqual(cid(expression),cid(earlier.expression_contract));assert.notEqual(cid(program),cid(earlier.program_schema));
  for(const [id,path] of [['scalar_law_manifest','spec/dependencies/aoa-rela-scalar-laws.json'],['production_profile_registry','spec/contracts/actql-production-profile-schemas.json'],['barrier_manifest','spec/manifests/actql-barrier-contracts-0.1.json']])assert.deepEqual(read(path),earlier[id]);
});
