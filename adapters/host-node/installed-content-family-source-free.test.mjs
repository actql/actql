// Actual family adapter with explicit Common/Store ports. This verifies caller
// selection only, not generation, physical byte custody or a funded execution.
import assert from 'node:assert/strict';
import test from 'node:test';
import {installEffectContentFamily} from './installed-content-family.mjs';

function fixture(sourceCount,{bounds={maxRows:1000,maxBytes:1000},boundFailure}={}){
  let appends=0,binds=0,cancelled=0;
  let selectedLimits;
  const active=Object.freeze({}),proof=Object.freeze({});
  const compiled=Object.freeze({}),graph=Object.freeze({});
  const owner=installEffectContentFamily({
    moon:{clientProgramEffectAcquisitionCount:()=>sourceCount},
    control:{effectFamily(_prepared,_graph,_bodies,limits,_port,retain){selectedLimits=limits;retain(active);return {};},
      familyPendingPiece(value){assert.strictEqual(value,active);return{revision:1,piece:Buffer.from('exact')};},
      familyAcknowledgePiece(value,revision){assert.strictEqual(value,active);assert.equal(revision,1);return true;}},
    publications:{bindCheckedClientEffectSerializationCapture(){binds++;return proof;},
      checkedClientSerializationGenerationLimits(value,selection){
        assert.strictEqual(value,compiled);assert.strictEqual(selection,graph);
        if(boundFailure!==undefined)throw boundFailure;
        return bounds;
      }},
    bodies:{},prepared:{},plan:{serializationGraph:graph,compiled,
      runDefinition:{wire:'{"valid_until":"2099-01-01T00:00:00.000Z"}'}},
    store:{storeAuthorityCid:'same Store',status:()=>({closed:false}),
      createPreparedObjectWriter(){return{append(bytes){assert.deepEqual(bytes,Buffer.from('exact'));appends++;},
        cancel(){cancelled++;},status:()=>({reservationHeld:false,custodyPending:false,cleanupPending:false})};}},
    principalId:'same principal',ownerPrincipal:'same principal',now:()=> '2026-10-21T00:00:00.000Z',
    authorize:()=>true,storeAuthorityCid:'same Store',outputLimits:{}});
  return{owner,counts:()=>({appends,binds,cancelled}),selectedLimits:()=>selectedLimits};
}

test('Content family forwards the same compiled row and byte ceilings before provider construction',async()=>{
  const f=fixture(0,{bounds:{maxRows:7,maxBytes:1000}});
  try{
    assert.equal(f.selectedLimits().generation.maxRows,7);
    assert.equal(f.selectedLimits().generation.maxBytes,1000);
    assert.equal(f.selectedLimits().output.maxRows,7);
  }finally{await f.owner.cleanup();}
});

test('Content family retains a compiled zero-row zero-byte ceiling without a fallback',async()=>{
  const f=fixture(0,{bounds:{maxRows:0,maxBytes:0}});
  try{
    assert.equal(f.selectedLimits().generation.maxRows,0);
    assert.equal(f.selectedLimits().generation.maxBytes,0);
    assert.equal(f.selectedLimits().output.maxRows,0);
  }finally{await f.owner.cleanup();}
});

test('Content family preserves original compiled-bound refusal before provider construction',async()=>{
  const original=new Error('OriginalCompiledBoundsRefused');let f;
  try{
    assert.throws(()=>{f=fixture(0,{boundFailure:original});},error=>error===original);
  }finally{await f?.owner.cleanup();}
});

test('source-free Content family uses its checked Values input without inventing Source proof',async()=>{
  const f=fixture(0);
  assert.throws(()=>f.owner.bindCapture({},{}),{message:'ForeignSourceFreeContentCapture'});
  assert.deepEqual(await f.owner.handlePause({status:'settling',slot:0}),{action:'resume'});
  assert.deepEqual(f.counts(),{appends:1,binds:0,cancelled:0});
  assert.equal(await f.owner.cleanup(),true);
  assert.deepEqual(f.counts(),{appends:1,binds:0,cancelled:1});
});

test('acquired Content family still requires its actual captured-input binding',async()=>{
  const f=fixture(1);
  await assert.rejects(f.owner.handlePause({status:'settling',slot:0}),{message:'InvalidContentPause'});
  assert.equal(f.counts().appends,0);
  f.owner.bindCapture({},{});
  assert.deepEqual(await f.owner.handlePause({status:'settling',slot:0}),{action:'resume'});
  assert.equal(f.counts().binds,1);
  assert.equal(await f.owner.cleanup(),true);
});

test('early managed Content keeps its same provider and binds physical execution only once', async () => {
  const prepared={},compiled={},graph={},selection={},provider={},store={storeAuthorityCid:'store',status:()=>({closed:false})};
  const plan={compiled,serializationGraph:graph,runDefinition:{wire:'{"valid_until":"2099-01-01T00:00:00Z"}'}};
  let retain,constructs=0,cleanup;
  const original={inputRows:0,prepare(){return selection;}};
  const family=installEffectContentFamily({moon:{clientProgramEffectAcquisitionCount:()=>0},
    control:{effectFamily(p,g,b,l,physical,keep,recovery,managed){
      assert.strictEqual(p,prepared);assert.strictEqual(g,graph);assert.strictEqual(managed,original);
      assert.equal(recovery,undefined);assert(cleanup,'parent owns cleanup before native constructor');
      assert.equal(l.output.maxRows,0);assert.equal(l.generation.maxRows,0);
      constructs++;retain=keep;return{provider,preparation:selection};}},
    publications:{checkedClientSerializationGenerationLimits:()=>({maxRows:1,maxBytes:100})},
    bodies:{},prepared,plan,store,principalId:'owner',ownerPrincipal:'owner',now:()=> '2026-11-03T00:00:00Z',
    authorize:()=>true,storeAuthorityCid:'store',outputLimits:{},managedOriginal:original,
    retainCleanup(value){cleanup=value;}});
  assert.strictEqual(family.provider,provider);assert.strictEqual(family.preparation,selection);
  assert.equal(retain({}),false,'unbound provider cannot start a physical generation');
  assert.throws(()=>family.bindExecution({prepared:{},plan,store,principalId:'owner'}),{message:'ForeignInstalledContentFamily'});
  family.bindExecution({prepared,plan,store,principalId:'owner'});
  assert.equal(retain({}),true);assert.equal(constructs,1);
  assert.throws(()=>family.bindExecution({prepared,plan,store,principalId:'owner'}),{message:'ForeignInstalledContentFamily'});
  assert.equal(await cleanup.close(),true);assert.equal(cleanup.cleanupPending(),false);
});
