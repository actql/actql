// Actual recovery child with explicit nominal Common and Store ports. These
// cases establish ordering/custody, not a real Reference, FD or public STORE.
import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareRecoveredCommandContent} from './recovered-command-content.mjs';

type Options = Parameters<typeof prepareRecoveredCommandContent>[0];
type Confirm = ReturnType<Options['publications']['capturedContentGenerationStorage']>['bindings'][number];
type Construct = Parameters<NonNullable<Options['recoveryResources']>['constructCaptured']>;
type Callback = () => unknown;
type Consume = Parameters<Options['store']['consumePhysicalHolding']>;
type Commit = Parameters<Options['store']['commitPhysicalHolding']>;
type RecoveryInput = Parameters<Options['publications']['recoverEffectCommandContent']>[0];
type Issuer = Readonly<{
  available: Parameters<Options['control']['issuer']>[0];
  authorize: Parameters<Options['control']['issuer']>[1];
}>;

function fixture({funded = false, cutFailure}: {funded?: boolean; cutFailure?: unknown} = {}) {
  const candidate={},issued={},compiled={},prepared={},captured={},preview={},invocation={},source={};
  const definition={wire:'{"valid_until":"2099-01-01T00:00:00.000Z"}'};
  const events: string[] = [],proofs=['input','derivation','generation'].map(name=>({name}));
  const holding={holding_cid:'holding',namespace:'content',manifest_cid:'reference',
    objects:[{cid:'bytes',byte_count:3}]};
  let live=true,released=false,confirm: Callback | undefined,consume: Callback | undefined;
  const nominal=Object.freeze({binding:{},current:()=>!released&&live,
    matchesIssued:(value: unknown)=>value===issued&&!released&&live,wire:()=> 'original wire',
    release(){events.push('release binding');released=true;}});
  const description={storeCid:'Store',identity:'reference',workspaceScopeCid:'scope',
    effectiveDataPolicyCid:'policy',contentCid:'bytes',sizeBytes:3,wire:'original wire'};
  const store={storeAuthorityCid:'Store',status:()=>({closed:false}),
    async confirmPrivateEvidence(proof: Confirm){events.push(proof.name);await confirm?.();return proof;},
    async inspectPhysicalHolding(value: string){assert.equal(value,'holding');events.push('holding');return holding;},
    async commitPhysicalHolding(value: Commit[0],objects: Commit[1]){assert.strictEqual(value,holding);assert.deepEqual(objects,[]);
      events.push('commit');},
    async consumePhysicalHolding(value: Consume[0],index: Consume[1],accept: Consume[2]){assert.equal(value,'holding');assert.equal(index,0);
      events.push('consume');await accept(Buffer.from('abc'));if(consume)await consume();}};
  const publications={capturedContentGenerationCount(value: unknown){assert.strictEqual(value,captured);return 1;},
    capturedContentGenerationStorage(value: unknown,run: unknown,authority: string,index: number){
      assert.strictEqual(value,captured);assert.strictEqual(run,definition);
      assert.equal(authority,'Store');assert.equal(index,0);
      return{holdingCid:'holding',manifestCid:'reference',contentCid:'bytes',byteCount:3n,bindings:proofs};},
    recoverEffectCommandContent(value: RecoveryInput){
      for(const [key,expected] of Object.entries({candidate,issued,compiled,prepared,captured,
        preview,invocation,source,definition}))assert.strictEqual(value[key as keyof RecoveryInput],expected);
      assert.equal(value.memberIndex,0);assert.equal(value.row,0);assert.equal(value.inputName,'content');
      events.push('bind original Command');return nominal;}};
  const control={recoveryCandidate(wire: string,binding: {original?: unknown}){assert.equal(wire,'original wire');assert.equal(binding.original,true);
    return candidate;},inspect:(value: unknown)=>{assert.strictEqual(value,candidate);return description;},
    issuer(available: Issuer['available'],authorize: Issuer['authorize']){return{available,authorize};},
    issue(value: unknown,issuer: Issuer){assert.strictEqual(value,candidate);
      assert.equal(issuer.available(undefined,'original wire'),true);
      assert.equal(issuer.authorize('original wire'),true);events.push('issue');return issued;}};
  const recoveryResources = funded ? {constructCaptured(original: Construct[0], receiver: Construct[1], method: Construct[2], argument: Construct[3]) {
    assert.strictEqual(original,captured); assert.strictEqual(receiver,undefined);
    events.push('begin original Read inverse');
    const result=Reflect.apply(method,receiver,[argument]);
    events.push('complete original Read inverse');
    if(cutFailure!==undefined)throw cutFailure;
    return result;
  }} : undefined;
  // Only the custody ports exercised here are implemented by this fixture.
  const child=prepareRecoveredCommandContent({publications,control,prepared,compiled,definition,
    captured,preview,invocation,source,store,principalId:'actor',ownerPrincipal:'actor',
    storeAuthorityCid:'Store',authorityScopeCid:'scope',now:()=>'2026-10-21T00:00:00.000Z',
    authorize:()=>live,installedBinding:()=>({graphPolicy:{cid:'policy'},binding:{original:true}}),
    referenceLimits:{},memberIndex:0,row:0,inputName:'content',referenceWire:'original wire',
    assertCurrent(){if(!live)throw new Error('OriginalRunRetired');},limits:{},recoveryResources} as unknown as Options);
  return{child,events,nominal,retire(){live=false;},
    confirm(value: Callback){confirm=value;},consume(value: Callback){consume=value;}};
}

test('installed recovered Command validates its original only inside the retained Read constructor',async()=>{
  const f=fixture({funded:true}),restored=await f.child.prepare();
  assert.strictEqual(restored.borrow,f.nominal);
  const entered=f.events.indexOf('begin original Read inverse');
  assert(entered>f.events.indexOf('issue'));
  assert.deepEqual(f.events.slice(entered,entered+3),
    ['begin original Read inverse','bind original Command','complete original Read inverse']);
  assert.equal(await f.child.release(),true);
  assert.equal(f.events.filter(value=>value==='bind original Command').length,1);
});

test('recovered Command retains the returned view when the SAME Read success cut refuses',async()=>{
  const primary=new Error('original current cut refusal'),f=fixture({funded:true,cutFailure:primary});
  await assert.rejects(f.child.prepare(),error=>error===primary);
  assert.equal(f.events.filter(value=>value==='bind original Command').length,1);
  assert.equal(f.events.includes('release binding'),false);
  assert.equal(await f.child.release(),true);
  assert.equal(f.events.filter(value=>value==='release binding').length,1);
});

test('recovered Command retains the same Store original and typed input before byte consumption',async()=>{
  const f=fixture();assert.deepEqual(f.events,[]);
  const restored=await f.child.prepare();
  assert.strictEqual(restored.borrow,f.nominal);
  assert.deepEqual(f.events,['input','derivation','generation','holding','commit','issue','bind original Command']);
  assert.throws(()=>restored.contentOwner.storageForContent({...f.nominal.binding}),/OriginalEffectContentUnavailable/);
  let bytes: Uint8Array | undefined;
  await restored.contentOwner.consumeContent(f.nominal.binding,value=>{bytes=value;});
  assert.deepEqual(bytes,Buffer.from('abc'));
  assert.equal(await f.child.release(),true);assert.equal(f.child.status().pending,false);
  assert.throws(()=>f.child.prepare(),/RecoveredContentAlreadyAttempted/);
  assert.equal(f.events.filter(value=>value==='issue').length,1);
  assert.equal(f.events.filter(value=>value==='consume').length,1);
});

test('recovered Command close during the original evidence await retains the same child until terminal',async()=>{
  const f=fixture();let enter!: () => void,release!: () => void;
  const entered=new Promise<void>(resolve=>{enter=resolve;}),barrier=new Promise<void>(resolve=>{release=resolve;});
  f.confirm(()=>{enter();return barrier;});
  const outcome=f.child.prepare().then(()=>({ok:true}),error=>({error}));
  await entered;
  assert.equal(await f.child.release(),false);assert.equal(f.child.status().pending,true);
  release();assert.match((await outcome as {error: Error}).error.message,/RecoveredContentUnavailable/);
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
