import assert from 'node:assert/strict';
import test from 'node:test';
import {validWireRunViewShape, validOwnerObservations} from '@actql/client-wire';
import {createReadEpoch} from './read-model.mjs';
import {runObservationLimits, runObservationModel, readRunObservation} from './run-observation.mjs';
import {observationCid as cid, observationRef as ref,
  runObservationFixture as view, ownerObservationFixture as owners} from './run-observation.fixture.mjs';

test('independent fixtures pass the existing closed Owner contracts', () => {
  assert(validWireRunViewShape(view()));assert(validOwnerObservations(owners(),ref(),runObservationLimits));
});
test('Run-level state never fills missing Plan bindings, usage or Result availability', () => {
  const wire=view();wire.run_state.status='succeeded';
  const model=runObservationModel(wire,null,ref());
  assert.equal(model.run.terminal,true);assert.equal(model.planBinding.compiledPlanCid,null);
  assert.equal(model.run.cleanupPending,undefined);
  for(const key of ['logicalProgress','elapsed','tokens','cost','preview','resultAvailability'])assert.equal(model[key].state,'unavailable');
  assert.deepEqual(model.quantities,[]);assert.equal(model.run.cancellation.state,'unavailable');
  assert(Object.isFrozen(model.runRef));assert(Object.isFrozen(model.run));
  wire.run_state.status='failed';assert.equal(model.run.status,'succeeded');
});
test('exact, bound, estimate and unknown quantities retain original text, units, scopes and bases', () => {
  const wire=view();wire.quantities=[
    {kind:'exact',value:'9007199254740993',unit:'rows',scope_cid:cid('1'),basis_cid:cid('2')},
    {kind:'bound',value:'17',unit:'calls',scope_cid:cid('3'),basis_cid:cid('4')},
    {kind:'estimate',value:'125',unit:'micro_USD',scope_cid:cid('5'),basis_cid:cid('6')},
    {kind:'unknown',unit:'tokens',reason:'not_observed'},
  ];
  const model=runObservationModel(wire,null,ref());
  assert.deepEqual(model.quantities.map(v=>v.kind),['exact','bound','estimate','unknown']);
  assert.equal(model.quantities[0].value,'9007199254740993');
  assert.deepEqual(model.quantities[3],{kind:'unknown',unit:'tokens',reason:'not_observed'});
  assert.equal(model.quantities[2].scopeCid,cid('5'));assert.equal(model.cost.state,'unavailable');
});
test('cancellation acceptance is separate from physical stop and per-Result Unknown', () => {
  const wire=view();wire.run_state.status='cancelled';wire.run_state.cleanup_pending=true;
  wire.run_state.legacy_state={...owners().owners[0].snapshot.value,status:'cancelled',
    result_availability:{answer:{state:'unknown',reason:'verification_pending',observed_at:'2026-10-15T00:00:00.000Z'}},
    control:{revision:8,cancellation_requested:true,physical_stop:'unknown'}};
  const model=runObservationModel(wire,null,ref());
  assert.equal(model.run.controlRevision,7);assert.equal(model.run.cleanupPending,true);
  assert.equal(model.run.cancellation.requested,true);assert.equal(model.run.cancellation.physicalStop,'unknown');
  assert.equal(model.resultAvailability.entries[0].state,'unknown');
});
test('history stays bounded, Owner-local and independent of current control revision', () => {
  const model=runObservationModel(view(),owners(),ref()),run=model.histories.owners[0];
  assert.equal(model.run.controlRevision,7);assert.equal(run.snapshot.revision,3);
  assert.deepEqual(run.history.entries.map(v=>v.revision),[2,3]);
  assert.equal(run.history.entries[1].state,'unknown');assert.equal(run.history.cursorAvailable,true);
  assert.equal(model.histories.owners[1].reason,'acquisition_failed');
  assert(!JSON.stringify(model).includes('original-opaque-cursor'));
});
test('foreign Run, malformed wire, original vector mismatch and nonconsecutive history refuse', () => {
  const invalid=view();invalid.run_ref.namespaceId='foreign';
  assert.throws(()=>runObservationModel(invalid,null,ref()),{code:'ExplorerInvalidRunObservation'});
  const malformed=view();malformed.run_state.status='complete';
  assert.throws(()=>runObservationModel(malformed,null,ref()),{code:'ExplorerInvalidRunObservation'});
  for(const change of [o=>o.ref.namespaceId='foreign',o=>o.revisionVector=[],
    o=>o.owners[0].history.entries[1].revision=4,
    o=>o.owners[0].history.entries[1].entryCid=cid('f')]){
    const o=owners();change(o);assert.throws(()=>runObservationModel(view(),o,ref()),{code:'ExplorerInvalidRunObservation'});
  }
});
test('existing metadata byte and one-page entry limits refuse instead of truncating', () => {
  const wire=view();wire.run_state.run_id='x'.repeat(65536);
  assert.throws(()=>runObservationModel(wire,null,ref()),{code:'ExplorerInvalidRunObservation'});
  const o=owners();o.owners[0].history.entries=Array.from({length:33},(_,i)=>({revision:i+2,entryCid:cid('2'),state:'unknown'}));
  assert.throws(()=>runObservationModel(view(),o,ref()),{code:'ExplorerInvalidRunObservation'});
});
test('actual SDK method selection is attach/inspect/Owner-read only, preserving original ref and bounds', async () => {
  const calls=[],epoch=createReadEpoch();
  const client={async attach(original){calls.push(['attach',original]);return {
    inspect(limits){calls.push(['inspect',limits]);return view();},
    observeOwners(limits){calls.push(['owners',limits]);return owners();},
    wait(){assert.fail('no wait');},cancel(){assert.fail('no cancel');},start(){assert.fail('no start');},
  };}};
  const model=await readRunObservation(client,ref(),epoch.capture());
  assert.equal(model.run.id,'original-run');
  assert.deepEqual(calls,[['attach',ref()],['inspect',{maxWireBytes:65536,maxNodes:10000,maxDepth:64}],['owners',{maxEntries:32,maxWireBytes:65536}]]);
});
test('missing Owner API is unavailable; stale success and stale denial cannot escape the old scope', async () => {
  const epoch=createReadEpoch();
  const old={attach:async()=>({inspect:async()=>view()})};
  assert.equal((await readRunObservation(old,ref(),epoch.capture())).histories.reason,'capability_unavailable');
  for(const fail of [false,true]){
    const client={attach:async()=>({inspect:async()=>view(),observeOwners:async()=>{
      epoch.invalidate();if(fail)throw Error('old private denial');return owners();
    }})};
    await assert.rejects(readRunObservation(client,ref(),epoch.capture()),{code:'ExplorerStaleScope'});
  }
});

test('decimal quantities retain the existing Owner refusal instead of rounding', () => {
  const wire=view();wire.quantities=[{kind:'estimate',value:'0.125',unit:'USD',scope_cid:cid('1'),basis_cid:cid('2')}];
  assert.throws(()=>runObservationModel(wire,null,ref()),{code:'ExplorerInvalidRunObservation'});
});
test('later Owner callbacks cannot mutate the earlier admitted Run snapshot', async () => {
  const wire=view(),epoch=createReadEpoch();
  const client={attach:async()=>({inspect:async()=>wire,observeOwners:async()=>{
    wire.run_state.status='failed';wire.run_ref.namespaceId='changed';return owners();
  }})};
  const model=await readRunObservation(client,ref(),epoch.capture());
  assert.equal(model.run.status,'running');assert.deepEqual(model.runRef,ref());
});
