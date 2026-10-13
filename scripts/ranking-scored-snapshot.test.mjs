import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const base=new URL('../reviews/2026-10-13-ranked-snapshot-control/',import.meta.url);
const read=name=>JSON.parse(readFileSync(new URL(name,base),'utf8'));
const canonical=value=>JSON.stringify(Array.isArray(value)?value.map(canonicalValue):canonicalValue(value));
function canonicalValue(value) {
  if(Array.isArray(value))return value.map(canonicalValue);
  if(value && typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonicalValue(value[key])]));
  return value;
}
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const environment=read('environment.json');
const control=read('control-program.json');
const source=readFileSync(new URL('source.aql',base),'utf8').trim();
const moon=readFileSync(new URL('../src/query_program/ranking_scored_snapshot_test.mbt',import.meta.url),'utf8');
const literals=moon.split('\n').filter(line=>line.trim().startsWith('#|')).map(line=>JSON.parse(line.trim().slice(2)));

test('scored snapshot identities and environment membership use independent declared preimages',()=>{
  const {evidence_bundle_cid,...body}=environment;
  assert.equal(cid(body),evidence_bundle_cid);
  const identities=read('snapshot-identities.json');
  for(const snapshot of identities)assert.equal(cid(snapshot.body),snapshot.cid);
  const sorted=[...identities].sort((a,b)=>a.cid.localeCompare(b.cid));
  assert.deepEqual(environment.schema_snapshots,sorted.map(item=>item.body));
  assert.deepEqual(literals[0],environment);
  assert.match(moon,new RegExp(evidence_bundle_cid));
  for(const snapshot of identities) {
    assert.equal(snapshot.body.score_contracts.s.domain,'Relevance');
    assert.equal(snapshot.body.score_contracts.s.normalization,'Identity');
    assert.deepEqual(snapshot.body.score_contracts.s.range,[0,1]);
  }
});

test('ordinary Program and flat source retain the exact weighted policy and both named inputs',()=>{
  assert.deepEqual(literals[1],control);
  assert.equal(control.stages.length,1);
  assert.deepEqual(Object.keys(control.stages[0].inputs),['left','right']);
  const fusion=control.stages[0].steps[0];
  assert.equal(fusion.from,'left');
  assert.equal(fusion.merge_rankings.with,'right');
  assert.deepEqual(fusion.merge_rankings.score_policy,{weighted_sum:{left:0.5,right:0.5}});
  assert.equal(fusion.merge_rankings.k,3);
  assert.deepEqual(control.stages[0].results.rows.fields,['id','score','rank']);
  assert.equal(source,'FROM l |> merge_rankings(with: r, by: [], candidate: id, score: s, k: 3, score_policy: {weighted_sum: {left: 0.5, right: 0.5}}, score_contract: {domain: \'Relevance\', range: [0, 1], normalization: \'Identity\'}) |> SELECT id, score, rank |> ORDER BY rank');
  assert.ok(moon.includes(JSON.stringify(source)));
});

test('designed score rows are arithmetic expectations, not observed runtime output',()=>{
  const expected=read('expected.json');
  assert.deepEqual(expected.inputs,{left:[{id:1,s:0.5}],right:[{id:2,s:0.5}]});
  const weighted=Object.entries(expected.inputs).flatMap(([side,rows])=>rows.map(row=>({id:row.id,score:row.s*fusionWeight(side)})));
  const maximum=Object.values(expected.inputs).flatMap(rows=>rows.map(row=>({id:row.id,score:row.s})));
  const rank=rows=>rows.sort((a,b)=>b.score-a.score||a.id-b.id).map((row,index)=>({...row,rank:index+1}));
  assert.deepEqual(expected.weighted_sum,rank(weighted));
  assert.deepEqual(expected.max,rank(maximum));
  function fusionWeight(side){return control.stages[0].steps[0].merge_rankings.score_policy.weighted_sum[side];}
});
