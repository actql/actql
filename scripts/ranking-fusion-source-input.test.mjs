import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {rankingFusionSourceSuccesses as normal,rankingFusionSourceRefusals as refused} from './fixtures/ranking-fusion-source-input.mjs';
test('independent RRF controls preserve input occurrences, exact weights, rank window and full schema',()=>{
 assert.equal(normal.length,12); assert.equal(refused.length,10);
 const repeat=normal.find(c=>c.name==='ranking-fusion-json-repeated-peers');
 const body=JSON.parse(repeat.text).stages[0].steps[2].merge_rankings;
 assert.deepEqual(body.with,['r','r']); assert.deepEqual(body.score_policy.rrf.weights,[1,2,3]);
 assert.equal(body.k,3); assert.equal(body.score_policy.rrf.rank_window,2);
 assert.deepEqual(repeat.results.answer.rows,[{id:2,score:2.833333333333333,rank:1},{id:3,score:1.6666666666666665,rank:2},{id:1,score:0.5,rank:3}]);
 for(const c of normal) {
  const resultName=c.format==='json'?'answer':'main';
  assert.deepEqual(Object.keys(c.results),[resultName]);
  assert.equal(c.sourceReadCount,0);
  assert.deepEqual(c.results[resultName].columns.map(x=>[x.name,x.contract]),['id','score','rank'].map(name=>[name,{type:'number',nullable:false}]));
 }
 const one=normal.find(c=>c.name==='ranking-fusion-json-single-peer');
 assert.notEqual(one.results.answer.rows[0].score,repeat.results.answer.rows[0].score);
 assert.deepEqual(normal.find(c=>c.name==='ranking-fusion-json-rank-window').results.answer.rows.map(r=>r.id),[2,1]);
});
test('ranking is registered in ordinary delivery, completed receipts and bounded narrow selection',()=>{
 const acceptance=readFileSync('scripts/fixtures/packed-public-query.mjs','utf8');
 const consumer=readFileSync('scripts/test-packed-public-query.mjs','utf8');
 assert.ok(acceptance.includes('scopeInputs.successes.push(...rankingFusionSourceSuccesses)'));
 assert.ok(acceptance.includes('scopeInputs.refusals.push(...rankingFusionSourceRefusals)'));
 assert.ok(acceptance.includes('ACTQL_TEST_RANKING_FUSION_ONLY'));
 assert.ok(consumer.includes('--ranking-fusion-only'));
 assert.ok(consumer.includes("['scripts/fixtures/ranking-fusion-source-input.mjs', 'ranking-fusion-source-input.mjs']"));
 assert.ok(consumer.includes('ranking-fusion-receipts.local.json'));
 assert.ok(acceptance.includes("if (item.name.startsWith('ranking-fusion-')) await rankingFusionReceipts.record(item, mode)"));
});
