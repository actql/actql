// Explicit Store/read ports isolate same-original partial cleanup. Actual
// Store/native byte delivery is covered by root-filesystem-native.test.mjs.
import assert from 'node:assert/strict';
import test from 'node:test';
import {consumeStoredContentOriginal,closeStoredContentReaders} from './generated-content-holding.mjs';
import {installEffectContentFamily} from './installed-content-family.mjs';

const original=Object.freeze({storeAuthorityCid:'same Store',holding:{namespace:'content',
  holding_cid:'same holding',objects:[{cid:'same bytes'}]}});

test('stored Content reader retains the same failed close and never reports a pending FD retired',async()=>{
  const readers=new Set();let pending=true,reads=0,closes=0;
  const primary=new Error('original read and close failed');
  const cleanup=Object.freeze({status:()=>({pending}),async retry(){closes++;return {pending};}});
  primary.cleanupHandle=cleanup;
  const store={storeAuthorityCid:original.storeAuthorityCid,
    async consumePhysicalHolding(holding,index,accept){
      reads++;assert.equal(holding,original.holding.holding_cid);assert.equal(index,0);
      await accept(Buffer.from('original'));throw primary;
    }};
  const observed=[];
  await assert.rejects(consumeStoredContentOriginal({store,original,readers,
    assertCurrent(){},accept:bytes=>observed.push(bytes)}),error=>error===primary);
  assert.equal(observed.length,1);assert.equal(readers.size,1);
  assert.equal(await closeStoredContentReaders(readers),false);
  assert.equal(closes,1);assert.equal(reads,1);
  pending=false;
  assert.equal(await closeStoredContentReaders(readers),true);
  assert.equal(readers.size,0);assert.equal(closes,1);assert.equal(reads,1);
});

test('stored Content checks the same current selection after a receiving callback',async()=>{
  const readers=new Set();let live=true,checks=0;
  const retired=new Error('same selection retired');
  const store={storeAuthorityCid:original.storeAuthorityCid,
    async consumePhysicalHolding(_holding,_index,accept){await accept(Buffer.from('original'));}};
  await assert.rejects(consumeStoredContentOriginal({store,original,readers,
    assertCurrent(){checks++;if(!live)throw retired;},accept(){live=false;}}),error=>error===retired);
  assert.equal(checks,3);assert.equal(readers.size,0);
});

function familyFixture(consumePhysicalHolding) {
  const binding={},issued={};
  const stored=Object.freeze({...original,issued});
  const owner=installEffectContentFamily({
    moon:{clientProgramEffectCommandContentMatchesIssued:(value,ref)=>value===binding&&ref===issued},
    control:{effectFamily:()=>({})},publications:{},bodies:{},prepared:{},
    plan:{serializationGraph:{},runDefinition:{wire:'{"valid_until":"2099-01-01T00:00:00.000Z"}'}},
    store:{storeAuthorityCid:stored.storeAuthorityCid,status:()=>({closed:false}),consumePhysicalHolding},
    principalId:'same principal',ownerPrincipal:'same principal',now:()=>'2026-10-21T00:00:00.000Z',
    authorize:()=>true,storeAuthorityCid:stored.storeAuthorityCid,outputLimits:{},
    restored:{generation:{},completion:{},recovery:{},storedOriginal:stored}});
  return {owner,binding,stored};
}

test('stored Content family refuses copied input before consuming its captured Store original',async()=>{
  let reads=0;
  const f=familyFixture(async(_holding,_index,accept)=>{reads++;await accept(Buffer.from('original'));});
  assert.throws(()=>f.owner.consumeContent({...f.binding},()=>{}),/OriginalEffectContentUnavailable/);
  assert.equal(reads,0);
  let bytes;
  await f.owner.consumeContent(f.binding,value=>{bytes=value;});
  assert.deepEqual(bytes,Buffer.from('original'));assert.equal(reads,1);
  assert.equal(await f.owner.cleanup(),true);
  assert.equal(f.owner.storageForContent(f.binding),undefined);
  assert.throws(()=>f.owner.consumeContent(f.binding,()=>{}),/OriginalEffectContentUnavailable/);
});

test('stored Content family keeps the original read pending when cleanup retires its selection',async()=>{
  let enter,release;
  const entered=new Promise(resolve=>{enter=resolve;}),barrier=new Promise(resolve=>{release=resolve;});
  const f=familyFixture(async(_holding,_index,accept)=>{await accept(Buffer.from('original'));});
  const flight=f.owner.consumeContent(f.binding,async()=>{enter();await barrier;});
  const outcome=flight.then(()=>({ok:true}),error=>({error}));
  await entered;
  assert.equal(await f.owner.cleanup(),false);
  assert.equal(f.owner.cleanupPending(),true);
  release();
  assert.match((await outcome).error?.message,/OriginalEffectContentUnavailable/);
  assert.equal(await f.owner.cleanup(),true);
  assert.equal(f.owner.cleanupPending(),false);
});
