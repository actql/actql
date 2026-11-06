import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {temporalJoinSourceSuccesses as normal,temporalJoinSourceRefusals as refused} from './fixtures/temporal-join-source-input.mjs';
import {temporalJoinSourceSuccesses as originalNormal,temporalJoinSourceRefusals as originalRefused}
  from '../reviews/2026-10-14-temporal-join-release-matrix/preimages/original-temporal-source-input.mjs';
test('temporal current text quotes reserved aliases and selects main while keeping original independent controls',()=>{
  assert.equal(normal.length,originalNormal.length); assert.equal(refused.length,originalRefused.length);
  const quote = text=>text.replace('10 AS at UNION','10 AS `at` UNION')
    .replace('FROM l AS current |>','FROM l AS `current` |>');
  for(const [index,item] of normal.entries()) {
    const original=originalNormal[index];
    const results=item.format==='json'?original.results:{main:original.results.answer};
    assert.deepEqual({...item,text:original.text},{...original,results});
    assert.equal(item.text,item.format==='json'?original.text:quote(original.text));
  }
  for(const [index,item] of refused.entries()) {
    const original=originalRefused[index];
    assert.deepEqual({...item,text:original.text},original);
    assert.equal(item.text,quote(original.text));
  }
});
test('temporal controls retain independent left/inner values, full schema, limits and zero acquisition',()=>{
  assert.equal(normal.length,12); assert.equal(refused.length,9);
  for(const suffix of ['asof-left','asof-inner','interval-left','interval-inner']) {
    const triple=normal.filter(c=>c.name.endsWith(suffix)); assert.equal(triple.length,3);
    for(const c of triple) {
      const resultName=c.format==='json'?'answer':'main';
      assert.equal(c.sourceReadCount,0);
      assert.deepEqual(c.results,{[resultName]:triple[0].results.answer});
      assert.deepEqual(c.results[resultName].columns.map(column=>column.name),['id','value']);
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
test('actual copied import closure reaches temporal fixtures and detects their removal',()=>{
  const copies=new Map([...readFileSync('scripts/test-packed-public-query.mjs','utf8')
    .matchAll(/\['([^']+)', '([^']+\.mjs)'\]/gu)].map(match=>[match[2],match[1]]));
  function missing(map) {
    const pending=['acceptance.mjs'],seen=new Set(),absent=[];
    while(pending.length) {
      const name=pending.pop(); if(seen.has(name)) continue; seen.add(name);
      const source=map.get(name); if(!source) {absent.push(name);continue;}
      for(const match of readFileSync(source,'utf8').matchAll(/(?:from\s*|import\s*\()(['"])(\.[^'"\n]+\.mjs)\1/gu)) {
        // Current copied fixture modules are flat. A new subdirectory requires
        // an explicit delivery change rather than silently guessing a path.
        assert.match(match[2],/^\.\/[^/]+\.mjs$/u);
        pending.push(match[2].slice(2));
      }
    }
    return {absent,seen};
  }
  const actual=missing(copies);
  assert.deepEqual(actual.absent,[]);
  assert.ok(actual.seen.has('temporal-join-source-input.mjs'));
  const omitted=new Map(copies); omitted.delete('temporal-join-source-input.mjs');
  assert.deepEqual(missing(omitted).absent,['temporal-join-source-input.mjs']);
});
