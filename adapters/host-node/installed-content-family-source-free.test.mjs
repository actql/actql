// Actual family adapter with explicit Common/Store ports. This verifies caller
// selection only, not generation, physical byte custody or a funded execution.
import assert from 'node:assert/strict';
import test from 'node:test';
import {installEffectContentFamily} from './installed-content-family.mjs';

function fixture(sourceCount){
  let appends=0,binds=0,cancelled=0;
  const active=Object.freeze({}),proof=Object.freeze({});
  const owner=installEffectContentFamily({
    moon:{clientProgramEffectAcquisitionCount:()=>sourceCount},
    control:{effectFamily(_prepared,_graph,_bodies,_limits,_port,retain){retain(active);return {};},
      familyPendingPiece(value){assert.strictEqual(value,active);return{revision:1,piece:Buffer.from('exact')};},
      familyAcknowledgePiece(value,revision){assert.strictEqual(value,active);assert.equal(revision,1);return true;}},
    publications:{bindCheckedClientEffectSerializationCapture(){binds++;return proof;}},
    bodies:{},prepared:{},plan:{serializationGraph:{},compiled:{},
      runDefinition:{wire:'{"valid_until":"2099-01-01T00:00:00.000Z"}'}},
    store:{storeAuthorityCid:'same Store',status:()=>({closed:false}),
      createPreparedObjectWriter(){return{append(bytes){assert.deepEqual(bytes,Buffer.from('exact'));appends++;},
        cancel(){cancelled++;},status:()=>({reservationHeld:false,custodyPending:false,cleanupPending:false})};}},
    principalId:'same principal',ownerPrincipal:'same principal',now:()=> '2026-10-21T00:00:00.000Z',
    authorize:()=>true,storeAuthorityCid:'same Store',outputLimits:{}});
  return{owner,counts:()=>({appends,binds,cancelled})};
}

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
