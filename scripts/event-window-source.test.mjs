import assert from 'node:assert/strict';
import test from 'node:test';
import {eventWindowSourceSuccesses as successes,eventWindowSourceRefusals as refusals} from './fixtures/event-window-source-input.mjs';
test('prepared event windows distinguish offset, sliding multiplicity and equality watermark',()=>{
  assert.equal(successes.length,12);
  for(const name of ['relation-fixed','event-fixed','event-sliding','event-mark','event-drop','event-empty']){
    const json=successes.find(c=>c.name==='window-json-'+name);
    const text=successes.find(c=>c.name==='window-text-'+name);
    assert.deepEqual(text.results,json.results);
    const p=JSON.parse(json.text),steps=p.stages[0].steps;
    const window=steps.find(s=>s.row_window||s.window_events);
    const body=window.row_window||window.window_events;
    assert.deepEqual({size:body.size,step:body.step,offset:body.offset},{size:10,step:3,offset:-2});
    const answer=json.results.answer;
    assert.deepEqual(p.stages[0].results.rows.fields,answer.columns.map(c=>c.name));
    const start=window.row_window?'window_start':'window_start_ms',end=window.row_window?'window_end':'window_end_ms';
    const occurrences=name==='event-empty'?[]:[{event_id:1,occurred_ms:0},{event_id:2,occurred_ms:10}];
    // Independent grid enumeration, not an imported execution/typing helper.
    const boundaries=occurrences.flatMap(row=>Array.from({length:13},(_,n)=>-2+(n-4)*(body.kind==='fixed'?10:3))
      .filter(x=>x<=row.occurred_ms&&row.occurred_ms<x+10)
      .map(x=>({event_id:row.event_id,start:x,end:x+10})))
      .filter(row=>name!=='event-drop'||row.event_id===2);
    assert.deepEqual(answer.rows.map(r=>({event_id:r.event_id,start:r[start],end:r[end]})),boundaries);
    if(name==='event-mark')assert.deepEqual(answer.rows.map(r=>[r.late,r.watermark_decision]),[[true,'mark'],[false,'keep']]);
    if(name==='event-drop')assert.deepEqual(answer.rows.map(r=>[r.event_id,r.late]),[[2,false]]);
  }
});
test('prepared refused event cases keep an exact unique inventory',()=>{
  assert.equal(refusals.length,8);
  assert.equal(new Set([...successes,...refusals].map(c=>c.name)).size,20);
  assert.ok(refusals.every(c=>c.expectedCode==='ClientProgramInvalidInput'));
  assert.ok(successes.every(c=>c.sourceReadCount===0));
});
