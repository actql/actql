import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {timeSeriesPrimarySuccesses as successes,timeSeriesPrimaryRefusals as refusals}
  from './fixtures/time-series-primary-source-input.mjs';
test('independent UTC grid retains half-open bounds, timestamp schema and whole Parameters',()=>{
  assert.equal(successes.length,9);assert.equal(refusals.length,7);
  assert.equal(new Set([...successes,...refusals].map(item=>item.name)).size,16);
  const expected=[{time:'2026-10-12T00:00:00.000Z'},{time:'2026-10-12T00:01:00.000Z'},{time:'2026-10-12T00:02:00.000Z'}];
  for(const item of successes) {
    const resultName=item.format==='json'?'answer':'main';
    assert.deepEqual(Object.keys(item.results),[resultName]);
    assert.deepEqual(item.results[resultName].columns,[{name:'time',contract:{type:'timestamp',nullable:false}}]);
    assert.deepEqual(item.results[resultName].rows,item.name.includes('empty')?[]:expected);
    assert.equal(item.sourceReadCount,0);assert.equal(item.sourceReadSessionCount,0);
    assert.ok(!item.results[resultName].rows.some(row=>row.time==='2026-10-12T00:03:00.000Z'));
  }
  const control=JSON.parse(successes[0].text);
  assert.deepEqual(control.stages[0].inputs,{});
  assert.deepEqual(control.stages[0].steps[0].time_series,{start:expected[0].time,end:'2026-10-12T00:03:00.000Z',step:'1m'});
  const parameter=JSON.parse(successes.find(item=>item.name==='time-series-primary-parameters-json').text);
  assert.deepEqual(parameter.stages[0].steps[0].time_series,{start:{$param:'begin'},end:{$param:'finish'},step:{$param:'tick'}});
  assert.ok(refusals.every(item=>item.expectedCode==='ClientProgramInvalidInput'));
});

test('time-series public selection preserves normal registration, receipt hook and isolated copy',()=>{
  const corpus=readFileSync('scripts/fixtures/packed-public-query.mjs','utf8');
  const driver=readFileSync('scripts/test-packed-public-query.mjs','utf8');
  assert.ok(corpus.includes('timeSeriesPrimaryOnly ? {successes: timeSeriesPrimarySuccesses, refusals: timeSeriesPrimaryRefusals}'));
  assert.ok(corpus.includes('scopeInputs.successes.push(...timeSeriesPrimarySuccesses)'));
  assert.ok(corpus.includes('scopeInputs.refusals.push(...timeSeriesPrimaryRefusals)'));
  assert.ok(corpus.includes('await timeSeriesPrimaryReceipts.record(item, mode)'));
  assert.ok(corpus.includes('await timeSeriesPrimaryReceipts.complete()'));
  assert.ok(driver.includes("['scripts/fixtures/time-series-primary-source-input.mjs', 'time-series-primary-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_TIME_SERIES_PRIMARY_ONLY = '1'"));
  assert.ok(driver.includes("? ['time-series-primary-receipts.local.json', 'time-series-primary-receipts.remote.json']"));
  const read=path=>JSON.parse(readFileSync(path,'utf8'));
  const before=read('scripts/fixtures/pre-time-series-primary-public-query-inventory.json');
  // The original cohort delta is frozen; the current union has a separate full-corpus check.
  const after=read('scripts/fixtures/submitted-time-series-primary-public-query-inventory.json');
  assert.deepEqual(after.counts,{successes:before.counts.successes+9,executionFailures:before.counts.executionFailures,refusals:before.counts.refusals+7});
  assert.equal(after.totalCases,before.totalCases+16);
  assert.deepEqual(after.repeatedFailures,before.repeatedFailures);
  assert.deepEqual(after.profiles.slice(1),before.profiles.slice(1));
});
