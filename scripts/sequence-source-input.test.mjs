import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {sequenceSourceSuccesses as normal,sequenceSourceRefusals as refused} from './fixtures/sequence-source-input.mjs';
test('independent sequence values, empty/fullschema, clock, pattern and symbolic guards are preserved',()=>{
 assert.equal(normal.length,22);assert.equal(refused.length,9);
 const fields=['first_id','first_time_ms','match_end_ms','match_start_ms','second_id','second_time_ms'];
 for(const c of normal) {
  const resultName=c.format==='json'?'answer':'main';
  assert.deepEqual(Object.keys(c.results),[resultName]);
  assert.equal(c.sourceReadCount,0);assert.deepEqual(c.results[resultName].columns,fields.map(name=>({name,contract:{type:'number',nullable:false}})));
 }
 assert.deepEqual(normal.find(c=>c.name==='sequence-json-gap-adjacent').results.answer.rows,[]);
 assert.deepEqual(normal.find(c=>c.name==='sequence-json-gap-subsequence').results.answer.rows,[{first_id:1,first_time_ms:0,match_end_ms:10,match_start_ms:0,second_id:3,second_time_ms:10}]);
 const parameter=JSON.parse(normal.find(c=>c.name==='sequence-json-parameters').text);
 const op=parameter.stages[0].steps.find(s=>s.sequence).sequence;
 assert.deepEqual(op.within,{$param:'span'});assert.deepEqual(op.max_output_rows,{$param:'cap'});
 assert.equal(op.max_matches_per_key,2);assert.equal(op.overlap,'disallow');
 const event=JSON.parse(normal.find(c=>c.name==='sequence-json-events').text);
 assert.equal(event.stages[0].steps.find(s=>s.sequence).sequence.time,'occurred_ms');
});
test('adopted Sequence omissions keep independent results and refuse explicit invalid modes',()=>{
 const expected={rows:[{first_id:1,first_time_ms:0,match_end_ms:10,
  match_start_ms:0,second_id:2,second_time_ms:10}],columns:[
  'first_id','first_time_ms','match_end_ms','match_start_ms','second_id','second_time_ms',
 ].map(name=>({name,contract:{type:'number',nullable:false}}))};
 for(const name of ['sequence-implicit-overlap','sequence-json-omitted-defaults',
  'sequence-sql-omitted-defaults','sequence-aql-text-omitted-defaults']) {
  const item=normal.find(value=>value.name===name);assert.ok(item,name);
  assert.deepEqual(item.results,{[item.format==='json'?'answer':'main']:expected});assert.equal(item.sourceReadSessionCount,0);
 }
 const body=JSON.parse(normal.find(value=>value.name==='sequence-json-omitted-defaults').text)
  .stages[0].steps.find(step=>step.sequence).sequence;
 assert.deepEqual(Object.keys(body).sort(),['id','max_matches_per_key','max_output_rows','pattern','time','within']);
 assert.equal(body.max_matches_per_key,2);assert.equal(body.max_output_rows,2);
 assert.ok(!refused.some(value=>value.name==='sequence-implicit-overlap'));
 assert.ok(refused.find(value=>value.name==='sequence-invalid-overlap').text.includes("overlap: 'invented'"));
});
test('sequence public matrix uses normal delivery, registered cohort and actual completed-case hook',()=>{
 const acceptance=readFileSync('scripts/fixtures/packed-public-query.mjs','utf8');
 const consumer=readFileSync('scripts/test-packed-public-query.mjs','utf8');
 assert.ok(acceptance.includes('scopeInputs.successes.push(...sequenceSourceSuccesses)'));
 assert.ok(acceptance.includes('scopeInputs.refusals.push(...sequenceSourceRefusals)'));
 assert.ok(acceptance.includes('ACTQL_TEST_SEQUENCE_SOURCE_ONLY'));
 assert.ok(consumer.includes('--sequence-source-only'));
 assert.ok(consumer.includes("['scripts/fixtures/sequence-source-input.mjs', 'sequence-source-input.mjs']"));
 assert.ok(consumer.includes('sequence-source-receipts.local.json'));
 assert.ok(acceptance.includes("if (item.name.startsWith('sequence-')) await sequenceReceipts.record(item, mode)"));
});
