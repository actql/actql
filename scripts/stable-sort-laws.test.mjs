import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';
import {checkDependencies,loadDependencies} from './check-aoa-versions.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const corpus=read('portability/corpus/stable-sort-laws.json');
// Independent numeric/null fixture oracle, not a product evaluator or backend
// conformance test. Explicit original occurrence indices avoid sort stability
// assumptions in the host implementation and retain duplicate row occurrences.
for(const f of corpus.cases)test(f.id,()=>{
  const indices=f.rows.map((_,i)=>i).sort((i,j)=>{
    for(const key of f.keys){
      const a=f.rows[i][key.field],b=f.rows[j][key.field];
      if(a===b)continue;
      if(a===null||b===null)return (a===null?-1:1)*((key.nulls??'last')==='first'?1:-1);
      assert.equal(typeof a,'number');assert.equal(typeof b,'number');
      return (a<b?-1:1)*(key.dir==='desc'?-1:1);
    }
    return i-j;
  });
  assert.deepEqual(indices,f.expected_indices);
  assert.equal(indices.length,f.rows.length);
  if(f.cid_order_must_differ){
    const cids=f.rows.map(row=>createHash('sha256').update(canonicalText(row)).digest('hex'));
    assert.deepEqual(cids,f.expected_value_cids);
    const byCid=f.rows.map((_,i)=>i).sort((i,j)=>cids[i]<cids[j]?-1:cids[i]>cids[j]?1:0);
    assert.deepEqual(byCid,f.expected_cid_indices);
    assert.notDeepEqual(byCid,f.expected_indices);
  }
});
for(const f of corpus.evidence_cases)test(f.id,()=>{
  const appended=f.authored_keys.length&&f.eligible_candidate?f.eligible_candidate.filter(k=>!f.authored_keys.includes(k)):[];
  const candidate=!!(f.authored_keys.length&&f.eligible_candidate);
  assert.deepEqual([...f.authored_keys,...appended],f.completed_keys);
  assert.deepEqual(appended,f.completion_record);
  assert.equal(candidate?'candidate_key':f.prior_total?'retained_total':'unresolved',f.tie_strategy);
  assert.equal(candidate,f.new_order_evidence);
});
test('shared law pin and limited proof claims match stable tie semantics',()=>{
  checkDependencies(loadDependencies());
  const stale=loadDependencies();
  stale.contract.rela_primitive_law_manifest_cid='sha256:a2a14eb0cca10f73ad577406a124f388cdde295cb6263e645675e967bcfa8b4d';
  assert.throws(()=>checkDependencies(stale),/primitive law body CID/);
  const law=read('spec/dependencies/aoa-rela-primitive-laws.json').operators['REL.orderByStable'];
  assert.match(law.ordering_law,/relative input order/);
  assert.match(law.ordering_law,/no implicit valueCID/);
  assert.equal(law.proof_status,'specification-only');
  assert.equal(law.theorem_root,undefined);
  assert.equal(law.conformance_cases,undefined);
  assert.match(law.reference_evidence.lean.scope,/no key-order or runtime stability proof/);
  assert.equal(law.fixed_vectors,'portability/corpus/stable-sort-laws.json');
});
