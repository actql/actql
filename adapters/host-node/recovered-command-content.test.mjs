// Actual recovery child with explicit nominal Common and Store ports. These
// cases establish ordering/custody, not a real Reference, FD or public STORE.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareRecoveredCommandContent} from './recovered-command-content.mjs';

function fixture() {
  const candidate={},issued={},compiled={},prepared={},captured={},preview={},invocation={},source={};
  const definition={wire:'{"valid_until":"2099-01-01T00:00:00.000Z"}'};
  const events=[],proofs=['input','derivation','generation'].map(name=>({name}));
  const holding={holding_cid:'holding',namespace:'content',manifest_cid:'reference',
    objects:[{cid:'bytes',byte_count:3}]};
  let live=true,released=false,confirm,consume;
  const nominal=Object.freeze({binding:{},current:()=>!released&&live,
    matchesIssued:value=>value===issued&&!released&&live,wire:()=> 'original wire',
    release(){events.push('release binding');released=true;}});
  const description={storeCid:'Store',identity:'reference',workspaceScopeCid:'scope',
    effectiveDataPolicyCid:'policy',contentCid:'bytes',sizeBytes:3,wire:'original wire'};
  const store={storeAuthorityCid:'Store',status:()=>({closed:false}),
    async confirmPrivateEvidence(proof){events.push(proof.name);await confirm?.();return proof;},
    async inspectPhysicalHolding(value){assert.equal(value,'holding');events.push('holding');return holding;},
    async commitPhysicalHolding(value,objects){assert.strictEqual(value,holding);assert.deepEqual(objects,[]);
      events.push('commit');},
    async consumePhysicalHolding(value,index,accept){assert.equal(value,'holding');assert.equal(index,0);
      events.push('consume');await accept(Buffer.from('abc'));if(consume)await consume();}};
  const publications={capturedContentGenerationCount(value){assert.strictEqual(value,captured);return 1;},
    capturedContentGenerationStorage(value,run,authority,index){
      assert.strictEqual(value,captured);assert.strictEqual(run,definition);
      assert.equal(authority,'Store');assert.equal(index,0);
      return{holdingCid:'holding',manifestCid:'reference',contentCid:'bytes',byteCount:3n,bindings:proofs};},
    recoverEffectCommandContent(value){
      for(const [key,expected] of Object.entries({candidate,issued,compiled,prepared,captured,
        preview,invocation,source,definition}))assert.strictEqual(value[key],expected);
      assert.equal(value.memberIndex,0);assert.equal(value.row,0);assert.equal(value.inputName,'content');
      events.push('bind original Command');return nominal;}};
  const control={recoveryCandidate(wire,binding){assert.equal(wire,'original wire');assert.equal(binding.original,true);
    return candidate;},inspect:value=>{assert.strictEqual(value,candidate);return description;},
    issuer(available,authorize){return{available,authorize};},
    issue(value,issuer){assert.strictEqual(value,candidate);
      assert.equal(issuer.available(undefined,'original wire'),true);
      assert.equal(issuer.authorize('original wire'),true);events.push('issue');return issued;}};
  const child=prepareRecoveredCommandContent({publications,control,prepared,compiled,definition,
    captured,preview,invocation,source,store,principalId:'actor',ownerPrincipal:'actor',
    storeAuthorityCid:'Store',authorityScopeCid:'scope',now:()=>'2026-10-21T00:00:00.000Z',
    authorize:()=>live,installedBinding:()=>({graphPolicy:{cid:'policy'},binding:{original:true}}),
    referenceLimits:{},memberIndex:0,row:0,inputName:'content',referenceWire:'original wire',
    assertCurrent(){if(!live)throw new Error('OriginalRunRetired');},limits:{}});
  return{child,events,nominal,retire(){live=false;},
    confirm(value){confirm=value;},consume(value){consume=value;}};
}

test('recovered Command retains the same Store original and typed input before byte consumption',async()=>{
  const f=fixture();assert.deepEqual(f.events,[]);
  const restored=await f.child.prepare();
  assert.strictEqual(restored.borrow,f.nominal);
  assert.deepEqual(f.events,['input','derivation','generation','holding','commit','issue','bind original Command']);
  assert.throws(()=>restored.contentOwner.storageForContent({...f.nominal.binding}),/OriginalEffectContentUnavailable/);
  let bytes;
  await restored.contentOwner.consumeContent(f.nominal.binding,value=>{bytes=value;});
  assert.deepEqual(bytes,Buffer.from('abc'));
  assert.equal(await f.child.release(),true);assert.equal(f.child.status().pending,false);
  assert.throws(()=>f.child.prepare(),/RecoveredContentAlreadyAttempted/);
  assert.equal(f.events.filter(value=>value==='issue').length,1);
  assert.equal(f.events.filter(value=>value==='consume').length,1);
});

test('recovered Command close during the original evidence await retains the same child until terminal',async()=>{
  const f=fixture();let enter,release;
  const entered=new Promise(resolve=>{enter=resolve;}),barrier=new Promise(resolve=>{release=resolve;});
  f.confirm(()=>{enter();return barrier;});
  const outcome=f.child.prepare().then(()=>({ok:true}),error=>({error}));
  await entered;
  assert.equal(await f.child.release(),false);assert.equal(f.child.status().pending,true);
  release();assert.match((await outcome).error.message,/RecoveredContentUnavailable/);
  assert.equal(await f.child.release(),true);assert.equal(f.child.status().pending,false);
  assert.equal(f.events.includes('issue'),false);assert.equal(f.events.includes('bind original Command'),false);
});

test('recovered Command keeps the original failed FD close and never reissues on cleanup',async()=>{
  const f=fixture(),restored=await f.child.prepare();let pending=true,retries=0;
  const failure=Object.assign(new Error('original reader close failed'),{cleanupHandle:{
    status:()=>({pending}),async retry(){retries++;return{pending};}}});
  f.consume(()=>{throw failure;});
  await assert.rejects(restored.contentOwner.consumeContent(f.nominal.binding,()=>{}),error=>error===failure);
  assert.equal(await f.child.release(),false);assert.equal(f.child.status().pending,true);
  assert.equal(f.events.includes('release binding'),false);
  pending=false;
  assert.equal(await f.child.release(),true);assert.equal(f.child.status().pending,false);
  assert.equal(retries,1);assert.equal(f.events.filter(value=>value==='issue').length,1);
});
