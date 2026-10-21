// Explicit Store/read ports isolate same-original partial cleanup. Actual
// Store/native byte delivery is covered by root-filesystem-native.test.mjs.
import assert from 'node:assert/strict';
import test from 'node:test';
import {consumeStoredContentOriginal,closeStoredContentReaders,
  restoreStoredGeneratedContentOriginal} from './generated-content-holding.mjs';
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
    control:{effectFamily:()=>({})},publications:{
      checkedClientSerializationGenerationLimits:()=>({maxRows:100,maxBytes:10000})},bodies:{},prepared:{},
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

function recoveryFixture() {
  const candidate={},issued={},capturedRun={},runDefinition={},readers=new Set(),events=[];
  const proofs=['input','derivation','generation'].map(name=>Object.freeze({name}));
  const holding=Object.freeze({holding_cid:'same holding',namespace:'content',manifest_cid:'reference',
    objects:[{cid:'bytes',byte_count:3}]});
  const description={storeCid:'same Store',identity:'reference',workspaceScopeCid:'same workspace',
    effectiveDataPolicyCid:'same policy',contentCid:'bytes',sizeBytes:3,wire:'original wire'};
  let live=true,missing,failed,retained;
  const store={storeAuthorityCid:'same Store',status:()=>({closed:false}),
    async confirmPrivateEvidence(proof){events.push(proof.name);if(failed!==undefined)throw failed;
      return proof.name===missing?undefined:proof;},
    async inspectPhysicalHolding(cid){assert.equal(cid,holding.holding_cid);events.push('holding');return holding;},
    async commitPhysicalHolding(value,prepared){assert.strictEqual(value,holding);assert.deepEqual(prepared,[]);
      events.push('commit same holding');}};
  const publications={capturedContentGenerationCount(value){assert.strictEqual(value,capturedRun);return 1;},
    capturedContentGenerationStorage(value,definition,authority,index){
      assert.strictEqual(value,capturedRun);assert.strictEqual(definition,runDefinition);
      assert.equal(authority,store.storeAuthorityCid);assert.equal(index,0);
      return{holdingCid:holding.holding_cid,manifestCid:'reference',contentCid:'bytes',byteCount:3n,bindings:proofs};}};
  const control={inspect(value){assert.strictEqual(value,candidate);return description;},
    issuer(available,authorize){return{available,authorize};},
    issue(value,issuer){assert.strictEqual(value,candidate);
      assert.equal(issuer.available(undefined,'original wire'),true);
      assert.equal(issuer.authorize('original wire'),true);events.push('issue');return issued;}};
  const options={store,publications,control,capturedRun,runDefinition,index:0,candidate,
    workspaceScopeCid:description.workspaceScopeCid,effectiveDataPolicyCid:description.effectiveDataPolicyCid,
    available:()=>live,authorize:()=>live,assertCurrent(){if(!live)throw new Error('OriginalRunRetired');},
    readers,limits:{},retainOriginal(value){events.push('retain');retained=value;}};
  return{options,events,readers,issued,holding,description,retained:()=>retained,
    missing(name){missing=name;},fail(error){failed=error;},retire(){live=false;}};
}

test('stored Content restore confirms captured proof inventory and retains the same issued physical original',async()=>{
  const f=recoveryFixture();
  assert.strictEqual(await restoreStoredGeneratedContentOriginal(f.options),f.issued);
  assert.deepEqual(f.events,['input','derivation','generation','holding','commit same holding','issue','retain']);
  assert.strictEqual(f.retained().holding,f.holding);assert.strictEqual(f.retained().issued,f.issued);
  assert.equal(f.readers.size,0);
});

test('stored Content restore refuses wrong capture and missing proof without issuing another reference',async()=>{
  const wrong=recoveryFixture();wrong.description.contentCid='foreign bytes';
  await assert.rejects(restoreStoredGeneratedContentOriginal(wrong.options),{code:'StoredContentRecoveryBindingMismatch'});
  assert.deepEqual(wrong.events,[]);assert.equal(wrong.retained(),undefined);
  const missing=recoveryFixture();missing.missing('derivation');
  await assert.rejects(restoreStoredGeneratedContentOriginal(missing.options),{code:'StoredContentRecoveryEvidenceUnavailable'});
  assert.deepEqual(missing.events,['input','derivation']);assert.equal(missing.retained(),undefined);
});

test('stored Content restore keeps the same failed reader cleanup and post-issuance retirement',async()=>{
  const failed=recoveryFixture();let pending=true,retries=0;
  const cause=Object.assign(new Error('same evidence close failed'),{cleanupHandle:Object.freeze({
    status:()=>({pending}),async retry(){retries++;return{pending};}})});
  failed.fail(cause);
  await assert.rejects(restoreStoredGeneratedContentOriginal(failed.options),value=>value===cause);
  assert.equal(failed.readers.size,1);assert.equal(await closeStoredContentReaders(failed.readers),false);
  pending=false;assert.equal(await closeStoredContentReaders(failed.readers),true);assert.equal(retries,1);
  const retired=recoveryFixture(),retain=retired.options.retainOriginal;
  retired.options.retainOriginal=value=>{retain(value);retired.retire();};
  await assert.rejects(restoreStoredGeneratedContentOriginal(retired.options));
  assert.strictEqual(retired.retained().issued,retired.issued);
  assert.equal(retired.readers.size,0,'no physical FD is fabricated by reference retirement');
});
