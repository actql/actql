import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {selectReleaseNearestShorthandCases,selectReleaseNearestShorthandMatrix} from './release-nearest-shorthand-query-cases.mjs';
import {nearestCarrierFixtureDirectory} from './fixtures/nearest-carrier-source-data.mjs';
import {releaseNearestCarrierFixturePaths} from './release-nearest-carrier-fixtures.mjs';
import {auditNearestCarrierTransport} from '../reviews/2026-10-14-nearest-carrier-release-matrix/public-audit.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
const hash = bytes=>createHash('sha256').update(bytes).digest('hex');
const read = path=>JSON.parse(readFileSync(path));
const canonical = value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}':JSON.stringify(value);

test('new grammar identity is independently bound to both authored surface inputs',()=>{
  const old=read('reviews/2026-10-15-nearest-shorthand/preimages/grammar-manifest.json');
  const {grammar_manifest_cid:oldCid,...before}=old;
  assert.equal('sha256:'+hash(canonical(before)),oldCid);
  // Inherited main767's structural doc is byte-identical; its old manifest
  // pin was stale. Ordinary generation rebinds those existing normative bytes.
  const structural='5d2f2432181664678b364fc97c3545d1740b004cd7b073c4bf0d8181c30dcaae';
  assert.equal(hash(readFileSync('docs/spec/structural-text.md')),structural);
  const body={...before,structural_text_rules_sha256:structural,query_text_grammar_sha256:hash(readFileSync('spec/grammar/actql-query-0.1.ebnf')),query_text_rules_sha256:hash(readFileSync('docs/spec/query-text.md'))};
  const next=read('spec/manifests/actql-grammar-0.1.json');
  assert.deepEqual(next,{...body,grammar_manifest_cid:'sha256:'+hash(canonical(body))});
  assert.notEqual(next.grammar_manifest_cid,oldCid);
});
test('L3 inventory fixes exact cosine, original payload, field order and declarations',()=>{
  const {successes,refusals}=selectReleaseNearestShorthandCases();
  assert.equal(successes.length,7);assert.equal(refusals.length,4);
  assert.deepEqual(successes[0].results,successes[1].results);
  // The public SQL selector requires SELECT or WITH; bare FROM belongs to text.
  assert.match(successes[1].text,/^SELECT \* FROM queries \|> NEAREST candidates AS c /u);
  assert.equal(successes[1].format,'sql');
  assert.deepEqual(successes[0].results.answer.rows.map(row=>row.hit.score),[1,0]);
  assert.match(successes[3].text,/FROM questions \|> NEAREST corpus USING \(query_vec\) K 3 AS hit/u);
  assert.deepEqual(successes[3].results.answer.rows.map(row=>row.hit.body),['first','second']);
  assert.deepEqual(successes[4].results.answer.rows,[{note:null,context:'first'}]);
  assert.deepEqual(successes[0].results.answer.columns.map(column=>column.name),['embedding','note','request_id','hit']);
  const control=JSON.parse(successes[6].text);
  for(const step of control.stages[0].steps.filter(step=>step.values)) {
    assert.deepEqual(step.values.schema.embedding,{type:'vector',nullable:false,dimensions:2});
  }
  assert.equal(successes[6].results.answer.columns[1].contract.element_type,'f32');
  assert.match(refusals[0].text,/KEEP \(\*\)/u);
  assert.match(refusals[2].text,/embedding AS alternate/u);
  assert.equal(new Set([...successes,...refusals].map(item=>item.name)).size,11);
});
test('release selector retains original ten Carrier cases and five refusals',async()=>{
  const matrix=await selectReleaseNearestShorthandMatrix(nearestCarrierFixtureDirectory);
  assert.equal(matrix.successes.length,17);assert.equal(matrix.refusals.length,9);
  assert.equal(matrix.successes.reduce((n,item)=>n+item.sourceReadCount,0),32);
  assert(releaseNearestCarrierFixturePaths.includes('scripts/release-nearest-shorthand-query-cases.mjs'));
});
test('independent L3 audit rejects wrong values, schema, source count and partial inventory',()=>{
  const fixtures=selectReleaseNearestShorthandCases();
  const inventory=['successes','refusals'].flatMap(kind=>fixtures[kind].map((item,index)=>JSON.stringify(['nearest-carrier',kind,index,item.name,hash(encodeRetainedFixture(item))])));
  const count=i=>{const reads=fixtures.successes.slice(0,i).reduce((n,item)=>n+item.sourceReadCount,0);return {acceptedRuns:i,sourceIo:reads,sourceReads:reads,sourceReadSessions:reads};};
  const make=()=>({report:{mode:'local',complete:true,expectedInventory:inventory,completedInventory:[...inventory],actualNormal:7,actualRefusal:4,observations:{sourceIo:12,sourceReads:12,sourceReadSessions:12,acceptedPages:12,issuedGrants:12,closedSites:1}},receipt:{version:'actql-nearest-carrier-acceptance/0.1',mode:'local',complete:true,cases:fixtures.successes.map((item,i)=>({name:item.name,mode:'local',ref:{synthetic:i},results:{answer:{rows:structuredClone(item.results.answer.rows),columns:structuredClone(item.results.answer.columns)}},beforeSubmit:count(i),beforeRead:count(i+1),afterReplay:count(i+1)})),refusals:fixtures.refusals.map((item,i)=>({name:item.name,mode:'local',submissionRef:{synthetic:i},outcome:{kind:'not_accepted',problem:{code:item.expectedCode},submissionRef:{synthetic:i}},beforeSubmit:count(7),afterRefusal:count(7)}))}});
  const original=make();assert.equal(auditNearestCarrierTransport('local',original.report,original.receipt,fixtures).actualRows,13);
  for(const change of [r=>{r.receipt.cases[0].results.answer.rows.reverse();},r=>{r.receipt.cases[3].results.answer.rows[0].hit.body='query';},r=>{r.receipt.cases[0].results.answer.columns.reverse();},r=>{r.receipt.cases[0].afterReplay.sourceIo++;},r=>{r.report.completedInventory.pop();}]){
    const wrong=make();change(wrong);assert.throws(()=>auditNearestCarrierTransport('local',wrong.report,wrong.receipt,fixtures));
  }
});
