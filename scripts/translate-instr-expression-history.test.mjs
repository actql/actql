import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {gunzipSync} from 'node:zlib';
// Independently hash fixed authored JSON and retained envelopes, never runtime output.
const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}':JSON.stringify(value);
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const history=read('portability/corpus/historical/pre-translate-instr-contract-identities.json');
const earlier=Object.fromEntries(history.contracts.map(v=>[v.id,v.body]));

test('translate-instr retains complete predecessor bodies and identity preimages',()=>{
  assert.equal(history.source_revision,"21505177a8a7b54a2c273186b7d30456f757fcc4");
  assert.equal(history.source_revision_kind, 'published-parent-with-exact-recovery-tree-match');
  assert.equal(history.recovery_revision, '7ea785d48033a6b193ca1dc4d0eb951b689a1526');
  assert.equal(history.source_tree, '6180a210f8c80cd7d156f706bd2a230b485c1406');
  assert.equal(cid(history),"sha256:7d93e2fb1aae001453b36df5262992a7652740670cb6e52dac68dfb13f1f560c");
  assert.equal(history.contracts.length,12);
  for(const item of history.contracts)assert.equal(cid(item.body),item.cid,item.id);
  for(const item of history.expression_fragments.cases){assert.equal(canonical(item.body),item.canonical);assert.equal(cid(item.body),item.cid);assert.equal(Buffer.byteLength(item.canonical),item.bytes);}
  for(const item of history.ordered_fragment.preimages){assert.equal(canonical(history.ordered_fragment[item.id]),item.canonical);assert.equal(cid(history.ordered_fragment[item.id]),item.cid);}
  assert.equal(cid(history.policy_candidates.body),history.policy_candidates.expected_cid);
  const preimages=read('portability/corpus/historical/pre-translate-instr-preimages.json');
  assert.equal(cid(preimages),"sha256:4f4970b6064ab225c07744977b56d098cd8b31dc5986a8e7b7a1cf14a4a3b810");
  assert.equal(preimages.source_revision,history.source_revision);
  assert.equal(preimages.expression_contract_cid,cid(earlier.expression_contract));
  assert.equal(preimages.sources.length,17);assert.equal(new Set(preimages.sources.map(v=>v.source)).size,17);
  for(const item of preimages.sources)assert.equal(cid(item.body),item.cid,item.source);
  assert.equal(preimages.identity_envelopes.length,21);
  for(const item of preimages.identity_envelopes){assert.equal(canonical(item.envelope),item.canonical);assert.equal(cid(item.envelope),item.expected_cid);}
});

test('translate-instr adds only its exact closed source and machine alternatives and laws',()=>{
  // Bind the exact adopted successor, not later scalar/Content extensions.
  const successor=JSON.parse(gunzipSync(readFileSync('scripts/fixtures/translate-instr-successor/contracts.json.gz')));
  assert.equal(successor.source_commit,'109564ef9a4f8241096292843b875d4c81fbb6f3');
  assert.equal(cid(successor),'sha256:04faa5a190134d528c3a8368d491a394fcd26ed427031f93bb0dea7c1f4d31d2');
  const expression=JSON.parse(gunzipSync(readFileSync('scripts/fixtures/native-local-scalar-predecessor/expression.json.gz')));
  assert.equal(cid(expression),'sha256:a49aba23a30514b63c9f7bcd05663dcacf2e5646c56073e7d00a34d6abe402b7');
  const program=successor.bodies.program_schema;
  assert.equal(cid(program),'sha256:1e63d8fb2cdfb0a8b54811762a96091ce2b7bc107089fd1682a76b1dbd57919b');
  const shapes={"translate":{"min":3,"max":3},"instr":{"min":2,"max":4}},names=new Set(Object.keys(shapes)),counts={};
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
  // Retain the separate main adoption of the portable numeric Owner.
  const adopted=read('portability/corpus/historical/adopted-pre-translate-instr-numeric-laws.json');
  assert.equal(cid(adopted),'sha256:fdbe284a0274e4fc7d3359bd3b6e9dd1926b7c7e12cc331f79626aec5ca9b56f');
  assert.equal(adopted.source_revision,'d3555139c482d024d98ae9effd4bc5f3f73a8690');
  for(const [name,law] of Object.entries(adopted.laws)){
    assert.deepEqual(before.laws[name],law);
    before.laws[name]=structuredClone(earlier.expression_contract.laws[name]);
  }
  assert.deepEqual(before,earlier.expression_contract);
  assert.deepEqual(withoutIncrement(program),earlier.program_schema);
  assert.deepEqual(Object.keys(counts).sort(),[...names].sort());
  for(const count of Object.values(counts))assert.equal(count,8);
  assert.notEqual(cid(expression),cid(earlier.expression_contract));assert.notEqual(cid(program),cid(earlier.program_schema));
  for(const [id,path] of [['scalar_law_manifest','spec/dependencies/aoa-rela-scalar-laws.json'],['production_profile_registry','spec/contracts/actql-production-profile-schemas.json'],['barrier_manifest','spec/manifests/actql-barrier-contracts-0.1.json']])assert.deepEqual(id==='scalar_law_manifest'
    ? read('portability/corpus/historical/pre-exact-utc-timestamp.json').contracts.find(c=>c.id===id).body
    : successor.bodies[path],earlier[id]);
});
