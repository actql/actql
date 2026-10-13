import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {sequenceSourceSuccesses as normal,sequenceSourceRefusals as refused} from './fixtures/sequence-source-input.mjs';
test('independent sequence values, empty/fullschema, clock, pattern and symbolic guards are preserved',()=>{
 assert.equal(normal.length,18);assert.equal(refused.length,9);
 const fields=['first_id','first_time_ms','match_end_ms','match_start_ms','second_id','second_time_ms'];
 for(const c of normal) {assert.equal(c.sourceReadCount,0);assert.deepEqual(c.results.answer.columns,fields.map(name=>({name,contract:{type:'number',nullable:false}})));}
 assert.deepEqual(normal.find(c=>c.name==='sequence-json-gap-adjacent').results.answer.rows,[]);
 assert.deepEqual(normal.find(c=>c.name==='sequence-json-gap-subsequence').results.answer.rows,[{first_id:1,first_time_ms:0,match_end_ms:10,match_start_ms:0,second_id:3,second_time_ms:10}]);
 const parameter=JSON.parse(normal.find(c=>c.name==='sequence-json-parameters').text);
 const op=parameter.stages[0].steps.find(s=>s.sequence).sequence;
 assert.deepEqual(op.within,{$param:'span'});assert.deepEqual(op.max_output_rows,{$param:'cap'});
 assert.equal(op.max_matches_per_key,2);assert.equal(op.overlap,'disallow');
 const event=JSON.parse(normal.find(c=>c.name==='sequence-json-events').text);
 assert.equal(event.stages[0].steps.find(s=>s.sequence).sequence.time,'occurred_ms');
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
