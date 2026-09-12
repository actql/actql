import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {machineCid} from './actql-spec-family.mjs';
const corpus=JSON.parse(readFileSync('portability/corpus/ordered-derive.json','utf8'));
assert.equal(corpus.version,'actql-ordered-derive-vectors/0.1');

test('row shape, prefix and resource preimages have independently fixed identities', () => {
  // Fixed ASCII preimages and digests were calculated with Python json/hashlib,
  // not with an expression compiler, lowerer or the contract generator.
  for (const c of corpus.preimages) {
    assert.deepEqual(JSON.parse(c.canonical), c.body, c.id);
    assert.equal('sha256:' + createHash('sha256').update(c.canonical).digest('hex'), c.cid, c.id);
    assert.equal(machineCid(c.body), c.cid, c.id);
    const artifact = {...c.body, self_cid:c.cid};
    const {self_cid, ...preimage} = artifact;
    assert.equal(machineCid(preimage), self_cid);
    assert.notEqual(machineCid(artifact), self_cid, 'self-CID is not hashed into itself');
  }
  const [shape, original, shadowed, limits] = corpus.preimages;
  assert.equal(original.body.input_contract_cid, shape.cid);
  assert.equal(shadowed.body.input_contract_cid, shape.cid);
  assert.notEqual(original.cid, shadowed.cid, 'a prior slot changes context ownership');
  for (const field of ['max_input_rows','max_value_bytes','max_live_value_bytes','max_work']) {
    assert.notEqual(machineCid({...limits.body, [field]:limits.body[field]+1}), limits.cid, field);
  }
});

// Independent reference oracle for the closed expression subset in these
// fixtures, not a production lowerer, evaluator or general expression validator.
function references(input, bindings) {
  assert.ok(bindings.length);
  const fields=new Set(input), prior=new Map(), out=[];
  for(const [i, binding] of bindings.entries()) {
    assert.ok(!prior.has(binding.name), 'duplicate binding');
    const work=[[binding.expr, `/bindings/${i}/expr`]];
    while(work.length) {
      const [expr,at]=work.pop();
      if(expr.op==='literal') continue;
      if(expr.op==='field') {
        assert.equal(typeof expr.body,'string');
        assert.ok(prior.has(expr.body)||fields.has(expr.body),'unresolved field');
        out.push({at,target:prior.has(expr.body)?{prior_slot:prior.get(expr.body)}:{input_field:expr.body}});
      } else {
        assert.equal(expr.op,'add','fixture oracle needs explicit new vocabulary');
        assert.equal(expr.body.length,2);
        for(let j=expr.body.length-1;j>=0;j--)work.push([expr.body[j],`${at}/body/${j}`]);
      }
    }
    prior.set(binding.name,i);
  }
  return out;
}

test('fixed reference tables retain every occurrence and resolve before shadowing', () => {
  for(const c of corpus.reference_cases)assert.deepEqual(references(c.input_fields,c.bindings),c.references,c.id);
  assert.throws(()=>references([],[]));
  assert.throws(()=>references([],[{name:'x',expr:{op:'field',body:'x'}}]));
  assert.throws(()=>references([],[{name:'x',expr:{op:'field',body:'y'}},{name:'y',expr:{op:'literal',body:1}}]));
});

test('missing, duplicate, reordered, forward and literal-interior references fail', () => {
  const mutations={
    remove_last:xs=>xs.pop(), repeat_first:xs=>xs.push(xs[0]), reverse:xs=>xs.reverse(),
    self_slot:xs=>{xs[0].target={prior_slot:0};},
    future_slot:xs=>{xs[0].target={prior_slot:1};},
    shadow_input:xs=>{xs.at(-1).target={input_field:'amount'};},
    literal_entry:xs=>xs.push({at:'/bindings/0/expr/body',target:{input_field:'missing'}}),
    double_target:xs=>{xs[0].target.prior_slot=0;},
    unknown_input:xs=>{xs[0].target.input_field='missing';},
  };
  for(const c of corpus.invalid_references){
    const base=corpus.reference_cases.find(x=>x.id===c.base); assert.ok(base);
    const changed=structuredClone(base.references); assert.ok(mutations[c.mutation]);
    mutations[c.mutation](changed);
    assert.throws(()=>assert.deepEqual(changed,references(base.input_fields,base.bindings)),c.id);
  }
});

// Every value occurrence contributes one node. String values and keys add raw
// UTF-8 octets; escaping belongs to wire bytes, not this logical work weight.
const utf8=s=>Buffer.byteLength(s,'utf8');
function weight(value){
  let total=0; const stack=[value];
  while(stack.length){
    const v=stack.pop(); total++;
    if(typeof v==='string')total+=utf8(v);
    else if(Array.isArray(v))stack.push(...v);
    else if(v!==null&&typeof v==='object')for(const [k,x]of Object.entries(v)){total+=utf8(k);stack.push(x);}
  }
  return total;
}
const wireBytes=v=>utf8(JSON.stringify(v)); // Fixtures are already canonical values.

test('work weight and escaped wire bytes are independently fixed measures', () => {
  for(const c of corpus.value_measures){
    assert.equal(weight(c.wire),c.weight,c.id); assert.equal(wireBytes(c.wire),c.bytes,c.id);
  }
});

test('logical live bytes count aliases and accumulate without reset', () => {
  for(const c of corpus.live_roots){
    const measured=c.roots.reduce((n,v)=>n+wireBytes(v),0);
    assert.equal(measured,c.bytes,c.id);
    const admit=cap=>{
      let remaining=cap;
      for(const root of c.roots){const n=wireBytes(root);if(n>remaining)return false;remaining-=n;}
      return true;
    };
    assert.equal(admit(c.bytes),true);assert.equal(admit(c.bytes-1),false);
  }
});
