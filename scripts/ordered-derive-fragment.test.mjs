import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {rowKernelSchemas} from './ordered-derive-contract.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const v=read('portability/corpus/ordered-derive-fragment.json');
const aoa=read('spec/contracts/actql-aoa.json');
const expressions=read('spec/contracts/actql-expressions.json');
const schemas=rowKernelSchemas(read('spec/contracts/actql-protocol-schemas.json'));

test('fixed source and graph preimages bind distinct exact step bodies',()=>{
  // ASCII canonical bytes and SHA-256 digests are fixed from Python json/hashlib,
  // independently of product compilers, lowerers and registration generators.
  assert.equal(v.extension_cid,machineCid(aoa.execution_contracts['REL.derive.ordered']));
  for(const p of v.preimages){
    assert.deepEqual(JSON.parse(p.canonical),v[p.id]);
    assert.equal('sha256:'+createHash('sha256').update(p.canonical).digest('hex'),p.cid);
    assert.equal(machineCid(v[p.id]),p.cid);
  }
  assert.notEqual(v.preimages[0].cid,v.preimages[1].cid);
  assert.equal(v.expected_aoa_node_cid,v.preimages.find(p=>p.id==='graph_step').cid);
  assert.deepEqual(v.source_step.params.bindings[0].expr.add[1],{$param:'delta'});
  assert.deepEqual(v.graph_step.params.bindings[0].expr.body[1],{op:'literal',body:v.parameters.delta.value});
  assert.deepEqual(v.graph_step.params.references,[
    {at:'/bindings/0/expr/body/0',target:{input_field:'amount'}},
    {at:'/bindings/1/expr',target:{prior_slot:0}},
  ]);
});

test('node identity includes names, edges and full params but not external evidence',()=>{
  const expected=v.preimages.find(p=>p.id==='graph_step').cid;
  for(const mutate of [
    s=>{s.id='other';},s=>{s.in=['previous'];},
    s=>{s.params.row_kernel_contract_cid='sha256:'+'0'.repeat(64);},
    s=>{s.params.bindings.reverse();},s=>{s.params.references.reverse();},
    s=>{s.params.bindings[0].expr.body[1].body=2;},
    s=>{delete s.params.references;},
  ]){const changed=structuredClone(v.graph_step);mutate(changed);assert.notEqual(machineCid(changed),expected);}
  for(const wrong of [v.source_step,v.graph_step.params,{node:v.graph_step},
    {version:'aoa-pipeline/0.1',sources:{input:{sort:'relation'}},steps:[v.graph_step],output:'derive'},
    {...v.graph_step,input_sorts:['relation'],output_sort:'relation'}])assert.notEqual(machineCid(wrong),expected);
  const reverseKeys=x=>Array.isArray(x)?x.map(reverseKeys):x&&typeof x==='object'?
    Object.fromEntries(Object.entries(x).reverse().map(([k,y])=>[k,reverseKeys(y)])):x;
  assert.equal(machineCid(reverseKeys(v.graph_step)),expected);
  const fragment={graph:{steps:[v.graph_step]},row_kernel_evidence:{bindings:[]}};
  const before=machineCid(fragment);
  fragment.row_kernel_evidence.bindings.push({aoa_node_cid:expected});
  assert.equal(machineCid(fragment.graph.steps[0]),expected);
  assert.notEqual(machineCid(fragment),before);
});

// Shape interpreter for these new schema surfaces only. External expressions
// use an explicit fixture subset; this is not a general expression checker.
function expression(x,machine){
  if(!x||typeof x!=='object'||Array.isArray(x))return false;
  const keys=Object.keys(x);
  if(machine&&!(keys.length===2&&keys.includes('op')&&keys.includes('body')))return false;
  if(!machine&&keys.length!==1)return false;
  const op=machine?x.op:keys[0],body=machine?x.body:x[op];
  if(op==='literal')return true; // opaque business data, never traversed
  if(op==='field'||(!machine&&op==='$param'))return typeof body==='string';
  if(op==='add')return Array.isArray(body)&&body.length===2&&body.every(e=>expression(e,machine));
  return false;
}
function valid(s,x){
  for(const k of Object.keys(s))assert.ok(['$id','$schema','$ref','type','const','properties','required','additionalProperties','items','minItems','maxItems','minLength','pattern','minimum','maximum','oneOf'].includes(k),k);
  if(s.$ref===expressions.schemas.expression.$id)return expression(x,false);
  if(s.$ref===expressions.schemas.expression_node.$id)return expression(x,true);
  if(s.$ref===schemas.params.$id)return valid(schemas.params,x);
  assert.equal(s.$ref,undefined,'unknown fixture schema reference');
  if(s.oneOf)return s.oneOf.filter(a=>valid(a,x)).length===1;
  if(Object.hasOwn(s,'const')&&s.const!==x)return false;
  if(s.type==='object'){
    if(x===null||typeof x!=='object'||Array.isArray(x))return false;
    if((s.required??[]).some(k=>!Object.hasOwn(x,k)))return false;
    return Object.entries(x).every(([k,y])=>Object.hasOwn(s.properties??{},k)?valid(s.properties[k],y):
      s.additionalProperties===false?false:typeof s.additionalProperties==='object'?valid(s.additionalProperties,y):true);
  }
  if(s.type==='array')return Array.isArray(x)&&x.length>=(s.minItems??0)&&x.length<=(s.maxItems??Infinity)&&x.every(y=>valid(s.items,y));
  if(s.type==='string')return typeof x==='string'&&x.length>=(s.minLength??0)&&(!s.pattern||new RegExp(s.pattern).test(x));
  if(s.type==='integer')return Number.isSafeInteger(x)&&x>=(s.minimum??-Infinity)&&x<=(s.maximum??Infinity);
  return true;
}

test('source and graph schemas distinguish closed params without changing legacy maps',()=>{
  const request=expressions.schemas.fragment.properties.request.properties.pipeline.properties.steps.items.allOf[0];
  const graph=expressions.schemas.fragment.properties.graph.properties.steps.items.allOf[0];
  assert.deepEqual(request.if,{properties:{op:{const:'REL.derive'}},required:['op']});
  assert.deepEqual(graph.if,request.if);
  assert.deepEqual(request.then.properties.params.oneOf[1],schemas.source_params);
  assert.deepEqual(graph.then.properties.params.oneOf[1],schemas.params);
  for(const params of [{exprs:{}},{exprs:{x:{literal:1}}},v.source_step.params])assert.equal(valid(request.then.properties.params,params),true);
  assert.equal(valid(graph.then.properties.params,v.graph_step.params),true);
  assert.equal(valid(schemas.node_preimage,v.graph_step),true);
  assert.equal(valid(schemas.node_preimage,v.source_step),false);
  for(const params of [{},{bindings:[]},v.graph_step.params,
    {...v.source_step.params,references:[]},
    {...v.source_step.params,row_kernel_contract_cid:v.extension_cid},
    {...v.source_step.params,row_kernel_evidence:{}},
    {bindings:[{name:'x',expr:{op:'literal',body:1}}]},
    {bindings:[{name:'x',expr:{literal:1},context_contract_cid:v.extension_cid}]},
  ])assert.equal(valid(request.then.properties.params,params),false);
  assert.equal(valid(graph.then.properties.params,v.source_step.params),false);
  assert.equal(valid(schemas.source_params,{bindings:[{name:'x',expr:{literal:{op:'field',body:'missing',$param:'data'}}}]}),true);
  for(const bad of [{...v.graph_step,extra:1},{...v.graph_step,in:[]},{...v.graph_step,in:['input','other']}])assert.equal(valid(schemas.node_preimage,bad),false);
});

// Fixed bodies are independently assembled from authored row operations and
// capacity forms, then hashed with Python json/hashlib. No runtime output is
// used to manufacture these expected identities.
const identities = read('portability/corpus/expression-fragment-identities.json');
for (const fixture of identities.cases) test(`independent ${fixture.id} retains its complete fixed identity`, () => {
  assert.deepEqual(JSON.parse(fixture.canonical), fixture.body);
  assert.equal(Buffer.byteLength(fixture.canonical), fixture.bytes);
  assert.equal('sha256:' + createHash('sha256').update(fixture.canonical).digest('hex'), fixture.cid);
  assert.equal(machineCid(fixture.body), fixture.cid);
  if (fixture.id === 'ordered_node') {
    assert.equal(fixture.body.params.row_kernel_contract_cid,
      machineCid(aoa.execution_contracts['REL.derive.ordered']));
    for (const name of ['ordered_node', 'ordered_binding', 'fragment_ordered'])
      assert.ok(readFileSync(`src/execution_relation/${name}_wbtest.mbt`, 'utf8').includes(fixture.cid));
  } else {
    assert.equal(fixture.id, 'complete_fragment');
    assert.equal(fixture.body.expression_contract_cid, machineCid(expressions));
    assert.ok(readFileSync('src/execution_relation/fragment_candidate_wbtest.mbt', 'utf8').includes(fixture.cid));
    assert.equal(fixture.body.request.pipeline.steps[0].params.exprs.x.literal, 7);
    assert.deepEqual(fixture.body.roots[0].contract, {type: 'number', nullable: false});
  }
});
