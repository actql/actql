import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {eventDedupeSourceSuccesses as successes,eventDedupeSourceRefusals as refusals,
  eventDedupeSourceExecutionFailures as failures} from './fixtures/event-dedupe-source-input.mjs';
test('independent dedupe controls distinguish global NULL grouping order and empty schemas',()=>{
  assert.equal(successes.length,10);
  const expectedIds={'repeated-nullable-score':[2,3],'short-time':[2,4],global:[4],'nulls-first':[1,4],empty:[]};
  for(const [name,ids] of Object.entries(expectedIds)){
    const json=successes.find(c=>c.name==='event-dedupe-json-'+name);
    const text=successes.find(c=>c.name==='event-dedupe-text-'+name);
    assert.deepEqual(text.results,{main:json.results.answer});
    assert.deepEqual(json.results.answer.rows.map(row=>row.event_id),ids);
    assert.deepEqual(json.results.answer.columns,[
      {name:'event_id',contract:{type:'number',nullable:false}},
      {name:'occurred_ms',contract:{type:'number',nullable:false}},
      {name:'bucket',contract:{type:'number',nullable:true}},
      {name:'score',contract:{type:'number',nullable:true}},
    ]);
    const program=JSON.parse(json.text),body=program.stages[0].steps.find(step=>step.dedupe_events).dedupe_events;
    assert.deepEqual(body.by,name==='global'?[]:['bucket',...(name==='empty'||name==='repeated-nullable-score'?['bucket']:[])]);
    assert.equal(body.order_by.length,1);
    assert.deepEqual(program.stages[0].steps.at(-1).select,json.results.answer.columns.map(c=>c.name));
  }
});
test('top tie remains an execution failure rather than a hidden arrival-order choice',()=>{
  assert.equal(failures.length,2);
  const program=JSON.parse(failures[0].text),steps=program.stages[0].steps;
  const rows=steps[0].values.rows;
  assert.equal(rows[0].bucket,rows[1].bucket);
  assert.equal(rows[0].occurred_ms,rows[1].occurred_ms);
  assert.notEqual(rows[0].event_id,rows[1].event_id);
  assert.deepEqual(steps[2].dedupe_events,{by:['bucket'],order_by:[{occurred_ms:'asc'}]});
  assert.deepEqual(failures.map(c=>c.resultNames),[['answer'],['main']]);
  assert.equal(refusals.length,6);
  assert.ok(refusals.every(c=>c.expectedCode==='ClientProgramInvalidInput'));
  assert.equal(new Set([...successes,...refusals,...failures].map(c=>c.name)).size,18);
});
test('prepared dedupe cases use the ordinary packed registration and selector',()=>{
  const packed=readFileSync('scripts/fixtures/packed-public-query.mjs','utf8');
  const installer=readFileSync('scripts/test-packed-public-query.mjs','utf8');
  for(const symbol of ['eventDedupeSourceSuccesses','eventDedupeSourceRefusals','eventDedupeSourceExecutionFailures'])assert.ok(packed.includes('...'+symbol));
  assert.ok(installer.includes("['scripts/fixtures/event-dedupe-source-input.mjs', 'event-dedupe-source-input.mjs']"));
  assert.ok(packed.includes("process.env.ACTQL_TEST_EVENT_DEDUPE_ONLY"));
  assert.ok(packed.includes('eventDedupeOnly ||'));
  assert.match(installer, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--event-dedupe-only'[^\]]*\]\.includes\(flag\)\)/u);
  assert.ok(installer.includes("if (process.argv.includes('--event-dedupe-only')) return;"));
  assert.ok(installer.includes("runtimeEnvironment.ACTQL_TEST_EVENT_DEDUPE_ONLY = '1'"));
});
