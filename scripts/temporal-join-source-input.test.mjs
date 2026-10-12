import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {temporalJoinSourceSuccesses as normal,temporalJoinSourceRefusals as refused} from './fixtures/temporal-join-source-input.mjs';
test('temporal controls retain independent left/inner values, full schema, limits and zero acquisition',()=>{
  assert.equal(normal.length,12); assert.equal(refused.length,9);
  for(const suffix of ['asof-left','asof-inner','interval-left','interval-inner']) {
    const triple=normal.filter(c=>c.name.endsWith(suffix)); assert.equal(triple.length,3);
    for(const c of triple) {
      assert.equal(c.sourceReadCount,0);
      assert.deepEqual(c.results,triple[0].results);
      assert.deepEqual(c.results.answer.columns.map(column=>column.name),['id','value']);
    }
  }
  assert.deepEqual(normal[0].results.answer.rows,[{id:1,value:7},{id:2,value:8},{id:3,value:null}]);
  const interval=JSON.parse(normal.find(c=>c.name==='temporal-json-interval-left').text);
  assert.equal(interval.stages[0].steps[2].interval_join.max_output_rows,3);
  assert.equal(JSON.parse(normal[0].text).stages[0].steps[2].asof_join.tolerance,12);
});
test('temporal public selector preserves ordinary registration and actual receipts',()=>{
  const acceptance=readFileSync('scripts/fixtures/packed-public-query.mjs','utf8');
  const consumer=readFileSync('scripts/test-packed-public-query.mjs','utf8');
  for(const symbol of ['temporalJoinSourceSuccesses','temporalJoinSourceRefusals']) assert.ok(acceptance.includes('scopeInputs.'+(symbol.endsWith('Successes')?'successes':'refusals')+'.push(...'+symbol+')'));
  assert.ok(acceptance.includes('ACTQL_TEST_TEMPORAL_JOIN_ONLY')); assert.ok(consumer.includes('--temporal-join-only'));
  assert.ok(consumer.includes("['scripts/fixtures/temporal-join-source-input.mjs', 'temporal-join-source-input.mjs']"));
  assert.ok(consumer.includes('temporal-join-receipts.local.json'));
});
