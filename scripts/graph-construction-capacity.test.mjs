import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';

const corpus=JSON.parse(readFileSync('portability/corpus/graph-construction-capacity.json','utf8'));
const fields=['max_graph_construction_input_rows','max_graph_construction_nodes','max_graph_construction_edges'];
test('construction scopes count input occurrences separately from completed entities',()=>{
  for(const c of corpus.cases) {
    // Independent finite numeric-ID model, not the product constructor/lowerer.
    const nodes=new Set(c.nodes??c.edges.flat());
    const edges=new Set(c.edges.filter(([s,t])=>nodes.has(s)&&nodes.has(t)).map(e=>JSON.stringify(e)));
    const counts=[(c.nodes?.length??0)+c.edges.length,nodes.size,edges.size];
    assert.deepEqual(counts,c.counts,c.name);
    for(let i=0;i<3;i++) {
      const cap=Math.max(1,counts[i]);
      assert(counts[i]<=cap);
      if(counts[i]>1) assert(!(counts[i]<=cap-1));
      assert(counts[i]<=cap+1);
    }
  }
});
test('construction ceilings are optional policy selections, not input Graph witness laws',()=>{
  const contract=JSON.parse(readFileSync('spec/contracts/actql-capacity-host-policy.json','utf8'));
  const base=Object.fromEntries(contract.schema.required.map(k=>[k,k==='version'?'actql-capacity-host-policy/0.1':1]));
  assert.equal(machineCid(base),'sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63');
  for(const name of fields) {
    assert.deepEqual(contract.schema.properties[name],{type:'integer',minimum:1,maximum:Number.MAX_SAFE_INTEGER});
    assert(!contract.schema.required.includes(name));
    assert(!Object.hasOwn(contract.host_witness_laws,name));
    assert.notEqual(machineCid({...base,[name]:7}),machineCid(base));
  }
  assert.equal(new Set(fields.map(name=>machineCid({...base,[name]:7}))).size,3);
});
