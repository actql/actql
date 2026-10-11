import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
// Independently hash fixed authored JSON and retained envelopes, never runtime output.
const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}':JSON.stringify(value);
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const history=read('portability/corpus/historical/pre-number-extrema-contract-identities.json');
const earlier=Object.fromEntries(history.contracts.map(v=>[v.id,v.body]));

test('number-extrema retains complete predecessor bodies and identity preimages',()=>{
  assert.equal(history.source_revision,"5b78417131cb4d2d7be2b2a862e643587ab282eb");
  assert.equal(history.source_revision_kind, 'published-parent-with-exact-recovery-tree-match');
  assert.equal(history.recovery_revision, '4c59fe14d56a08ef3ada1352bee1de2bc3acbb49');
  assert.equal(history.source_tree, 'd18f5ad0eccc5b85806775dc85116ef10e2699bf');
  assert.equal(cid(history),"sha256:99353f2faf9e58e371012de8ec1fbf5df3fb198e99ce63d99127f368b28dd53e");
  assert.equal(history.contracts.length,12);
  for(const item of history.contracts)assert.equal(cid(item.body),item.cid,item.id);
  for(const item of history.expression_fragments.cases){assert.equal(canonical(item.body),item.canonical);assert.equal(cid(item.body),item.cid);assert.equal(Buffer.byteLength(item.canonical),item.bytes);}
  for(const item of history.ordered_fragment.preimages){assert.equal(canonical(history.ordered_fragment[item.id]),item.canonical);assert.equal(cid(history.ordered_fragment[item.id]),item.cid);}
  assert.equal(cid(history.policy_candidates.body),history.policy_candidates.expected_cid);
  const preimages=read('portability/corpus/historical/pre-number-extrema-preimages.json');
  assert.equal(cid(preimages),"sha256:24fd1a20cd85056c949e2ecb4b27183824e05c18443376f2ed0876706fcd288d");
  assert.equal(preimages.source_revision,history.source_revision);
  assert.equal(preimages.expression_contract_cid,cid(earlier.expression_contract));
  assert.equal(preimages.sources.length,17);assert.equal(new Set(preimages.sources.map(v=>v.source)).size,17);
  for(const item of preimages.sources)assert.equal(cid(item.body),item.cid,item.source);
  assert.equal(preimages.identity_envelopes.length,21);
  for(const item of preimages.identity_envelopes){assert.equal(canonical(item.envelope),item.canonical);assert.equal(cid(item.envelope),item.expected_cid);}
});

test('number-extrema adds only its exact closed source and machine alternatives and laws',()=>{
  const expression=read('spec/contracts/actql-expressions.json');
  const program=read('spec/contracts/actql-protocol-schemas.json').artifact_schemas.executable_plan.properties.execution_material.properties.program;
  const shapes={"greatest":{"min":1},"least":{"min":1}},names=new Set(Object.keys(shapes)),counts={};
  function withoutIncrement(value){
    if(Array.isArray(value))return value.map(withoutIncrement);
    if(value===null||typeof value!=='object')return value;
    const result=Object.fromEntries(Object.entries(value).map(([k,v])=>[k,withoutIncrement(v)]));
    if(result.oneOf)result.oneOf=result.oneOf.filter(shape=>{
      const name=shape.properties?.op?.const??(shape.required?.length===1?shape.required[0]:null);
      if(!names.has(name))return true;
      const node=Boolean(shape.properties?.op),body=shape.properties[node?'body':name];
      assert.equal(shape.additionalProperties,false);assert.deepEqual(shape.required,node?['op','body']:[name]);
      assert.equal(body.type,'array');assert.equal(body.minItems,shapes[name].min);
      assert.equal(body.maxItems,shapes[name].max??undefined);
      assert.deepEqual(Object.keys(body.items),['$ref']);
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
  for(const [id,path] of [['scalar_law_manifest','spec/dependencies/aoa-rela-scalar-laws.json'],['production_profile_registry','spec/contracts/actql-production-profile-schemas.json'],['barrier_manifest','spec/manifests/actql-barrier-contracts-0.1.json']])assert.deepEqual(read(path),earlier[id]);
});
