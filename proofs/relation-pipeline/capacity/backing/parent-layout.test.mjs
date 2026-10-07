import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parentStartupLayout,inspectParentStartup} from './parent-layout.mjs';
const fixture=JSON.parse(readFileSync(new URL('../parent-control/chain-records.fixture.json',import.meta.url)));
const fact=()=>structuredClone(fixture.records.find(r=>r.kind==='startup'));
test('current source/ABI requests include aggregated state and padded captures',()=>{
  const model=parentStartupLayout();
  assert.equal(model.references,64);assert.equal(model.blocks.state,56);
  assert.equal(model.blocks.startEnvironment,80);assert.equal(model.blocks.advance,104);
  assert.equal(model.startupLower,600);
  const result=inspectParentStartup(fact(),'native');
  assert(result.componentBoundContradicted);assert.equal(result.totalReservationViolationProven,false);
});
test('the old ten-Ref layout and a portable target cannot enter current arithmetic',()=>{
  for(const mutate of [f=>f.count=3,f=>f.environments[0].requestedBytes=120,
    f=>f.state.requestedBytes=0,f=>f.callbacks[0].requestedBytes=96]) {
    const f=fact();mutate(f);assert.throws(()=>inspectParentStartup(f,'native'));
  }
  for(const target of ['js','wasm'])assert.throws(()=>inspectParentStartup(fact(),target));
});
