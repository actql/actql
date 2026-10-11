import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
// Independently hash fixed authored JSON and retained envelopes, never runtime output.
const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}':JSON.stringify(value);
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const history=read('portability/corpus/historical/pre-direct-trig-contract-identities.json');
const earlier=Object.fromEntries(history.contracts.map(v=>[v.id,v.body]));

test('direct-trig retains complete predecessor bodies and identity preimages',()=>{
  assert.equal(history.source_revision,"745a2003524fc4000d978674e0a095ee46f038d1");
  assert.equal(history.source_revision_kind, 'published-parent-with-exact-recovery-tree-match');
  assert.equal(history.recovery_revision, '6502831d5b81de11b8486282cae39cb4faa01fd7');
  assert.equal(history.source_tree, 'c4d0ce434a62490bcef6b6287b58d4a120448dd7');
  assert.equal(cid(history),"sha256:4bd4518680f424877aafaefa8b25114a432d6bc38b41027ade89aca87d55ed07");
  assert.equal(history.contracts.length,12);
  for(const item of history.contracts)assert.equal(cid(item.body),item.cid,item.id);
  for(const item of history.expression_fragments.cases){assert.equal(canonical(item.body),item.canonical);assert.equal(cid(item.body),item.cid);assert.equal(Buffer.byteLength(item.canonical),item.bytes);}
  for(const item of history.ordered_fragment.preimages){assert.equal(canonical(history.ordered_fragment[item.id]),item.canonical);assert.equal(cid(history.ordered_fragment[item.id]),item.cid);}
  assert.equal(cid(history.policy_candidates.body),history.policy_candidates.expected_cid);
  const preimages=read('portability/corpus/historical/pre-direct-trig-preimages.json');
  assert.equal(cid(preimages),"sha256:87ae66ebf46d376f0ff61de57e30e61a83c9b9b7c8da7746db9c16921b81e822");
  assert.equal(preimages.source_revision,history.source_revision);
  assert.equal(preimages.expression_contract_cid,cid(earlier.expression_contract));
  assert.equal(preimages.sources.length,17);assert.equal(new Set(preimages.sources.map(v=>v.source)).size,17);
  for(const item of preimages.sources)assert.equal(cid(item.body),item.cid,item.source);
  assert.equal(preimages.identity_envelopes.length,21);
  for(const item of preimages.identity_envelopes){assert.equal(canonical(item.envelope),item.canonical);assert.equal(cid(item.envelope),item.expected_cid);}
});

test('direct-trig adds only its exact closed source and machine alternatives and laws',()=>{
  const successor=Object.fromEntries(read('portability/corpus/historical/pre-translate-instr-contract-identities.json').contracts.map(v=>[v.id,v.body]));
  const expression=successor.expression_contract;
  const program=successor.program_schema;
  const shapes={"sin":{},"cos":{},"tan":{},"asin":{},"acos":{},"atan":{},"atan2":{"min":2,"max":2},"sinh":{},"cosh":{},"tanh":{},"asinh":{},"acosh":{},"atanh":{}},names=new Set(Object.keys(shapes)),counts={};
  function withoutIncrement(value){
    if(Array.isArray(value))return value.map(withoutIncrement);
    if(value===null||typeof value!=='object')return value;
    const result=Object.fromEntries(Object.entries(value).map(([k,v])=>[k,withoutIncrement(v)]));
    if(result.oneOf)result.oneOf=result.oneOf.filter(shape=>{
      const name=shape.properties?.op?.const??(shape.required?.length===1?shape.required[0]:null);
      if(!names.has(name))return true;
      const node=Boolean(shape.properties?.op),body=shape.properties[node?'body':name];
      assert.equal(shape.additionalProperties,false);assert.deepEqual(shape.required,node?['op','body']:[name]);
      if(name==='atan2'){
        assert.equal(body.type,'array');assert.equal(body.minItems,2);assert.equal(body.maxItems,2);
        assert.deepEqual(Object.keys(body.items),['$ref']);
        assert.match(body.items.$ref,/^#\/\$defs\/(expression|source_expression|machine_expression|value_expression)$/u);
      }else{
        assert.deepEqual(Object.keys(body),['$ref']);
        assert.match(body.$ref,/^#\/\$defs\/(expression|source_expression|machine_expression|value_expression)$/u);
      }
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
