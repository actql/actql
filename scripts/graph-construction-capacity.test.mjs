import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';

const corpus=JSON.parse(readFileSync('portability/corpus/graph-construction-capacity.json','utf8'));
const fields=['max_graph_construction_input_rows','max_graph_construction_nodes','max_graph_construction_edges'];
test('subgraph induction preserves selected records before optional edge filtering',()=>{
  const {cases}=JSON.parse(readFileSync('portability/corpus/graph-subgraph-selection.json','utf8'));
  for(const c of cases) {
    const ids=new Set(c.mode==='predicate' ? c.nodes.filter(n=>n.active===true).map(n=>n.id) : c.selected);
    if([...ids].some(id=>!c.nodes.some(n=>n.id===id))) {
      assert.equal(c.error,'MissingIdentity',c.name);
      continue;
    }
    assert.equal(c.error,undefined,c.name);
    const nodes=c.nodes.filter(n=>ids.has(n.id));
    const edges=c.edges.filter(e=>ids.has(e.source)&&ids.has(e.target))
      .filter(e=>!c.edge_filter||e.active===true);
    assert.deepEqual(nodes,c.expected_nodes,c.name);
    assert.deepEqual(edges,c.expected_edges,c.name);
    assert(nodes.length<=c.nodes.length && edges.length<=c.edges.length,c.name);
    assert(nodes.every(n=>c.nodes.includes(n)) && edges.every(e=>c.edges.includes(e)),c.name);
  }
});
test('match selectors preserve multiplicity, absence, and inclusive output capacity',()=>{
  const {cases}=JSON.parse(readFileSync('portability/corpus/graph-match-resources.json','utf8'));
  for(const c of cases) {
    if(c.kind==='nodes' && c.ids?.some(id=>!c.rows.some(row=>row[0]===id))) {
      assert.equal(c.error,'MissingIdentity');
      continue;
    }
    assert.equal(c.error,undefined);
    const selected=c.kind==='nodes'
      ? c.rows.filter(([id,active])=>c.ids ? c.ids.includes(id) : active===true).map(([id])=>id).sort((a,b)=>a-b)
      : c.rows.filter(([, ,type])=>c.types===null || c.types.includes(type))
        .toSorted((a,b)=>a[0]-b[0] || a[1]-b[1] || (a[2]<b[2]?-1:a[2]>b[2]?1:0));
    assert.deepEqual(selected,c.selected);
    assert.equal(selected.length<=c.cap,c.accepted);
  }
});
test('structural Graph output ceilings remain separate from diagnostic thresholds',()=>{
  const vectors=JSON.parse(readFileSync('portability/corpus/graph-structural-resources.json','utf8'));
  for(const v of vectors.cases) {
    const {nodes,edges,bounds}=v;
    const degrees=nodes.map(id=>edges.reduce((n,[s,t])=>n+Number(s===id)+Number(t===id),0));
    const reports=Number(bounds.max_nodes!==undefined && nodes.length>bounds.max_nodes)
      +Number(bounds.max_edges!==undefined && edges.length>bounds.max_edges)
      +degrees.filter(n=>bounds.max_degree!==undefined && n>bounds.max_degree).length;
    assert.equal(nodes.length,v.degree_rows,v.name);
    assert.equal(reports,v.report_rows,v.name);
    for(const [cap,degreeAccepted,reportAccepted] of v.guards) {
      // External preflight and component/traversal ceilings are not this scope.
      for(const unrelated of [1,1000]) {
        const policy={max_relation_output_rows:cap,max_graph_input_nodes:unrelated,max_graph_output_rows:unrelated};
        assert.equal(nodes.length<=policy.max_relation_output_rows,degreeAccepted,v.name);
        assert.equal(reports<=policy.max_relation_output_rows,reportAccepted,v.name);
      }
    }
  }
});
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
