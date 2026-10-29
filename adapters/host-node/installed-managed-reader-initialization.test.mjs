import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';

// Actual common factory and failed-initialization owner. Original Site/Core
// selection is an explicit port; this component performs no physical I/O.
test('failed Source construction retires the same original reader factory before its Site',async () => {
  const originalSite=Object.freeze({callResource() {assert.fail('no send');},referenceCurrent:()=>true,
    bindRunAcquisition() {assert.fail('no binding');},authorizationPurpose() {assert.fail('no authorization');}});
  const factory=createInstalledCredentialSourceReader({capacity:{},originalSite,assertCurrent() {},
    maxResponses:1,readPages() {assert.fail('no read');}});
  const cause=new Error('original Source constructor failed');let closed=0;
  const failure=await retainInstalledHostInitializationFailure(cause,{sourceReader:factory,
    sourceProfile:{close() {closed++;assert.throws(()=>factory.prepare({}),{code:'InstalledSourceReaderFactoryClosed'});}}});
  assert.equal(failure.primaryFailure,cause);assert.equal(failure.cleanupPending,false);
  assert.equal(closed,1);assert.throws(()=>factory.prepare({}),{code:'InstalledSourceReaderFactoryClosed'});
  await failure.cleanupHandle.retry();assert.equal(closed,1);
});

test('pending original factory retirement retains its Site and captures the method before cleanup awaits',async () => {
  let attempts=0,siteCloses=0,effectCloses=0,controlCloses=0,initialDone=false;
  const factory={retire() {assert.equal(this,factory);return ++attempts===2;}};
  const cause=Object.assign(new Error('same original primary'),{cleanupHandle:{
    async retry() {initialDone=true;},status:()=>({pending:!initialDone,errors:[]})}});
  const retaining=retainInstalledHostInitializationFailure(cause,{sourceReader:factory,
    sourceProfile:{close() {siteCloses++;}},installedEffect:{close() {effectCloses++;}},
    initialControl:{close() {controlCloses++;return {pending:false};}}});
  factory.retire=()=>assert.fail('replacement factory method');
  const failure=await retaining;
  assert.equal(failure.primaryFailure,cause);assert.equal(failure.cleanupPending,true);
  assert.equal(attempts,1);assert.equal(siteCloses,0);assert.equal(effectCloses,1);assert.equal(controlCloses,0);
  assert.deepEqual(failure.cleanupHandle.status().owners,['source-reader','source-profile','initial-control']);
  await failure.cleanupHandle.retry();
  assert.equal(attempts,2);assert.equal(siteCloses,1);assert.equal(effectCloses,1);assert.equal(controlCloses,1);
  assert.equal(failure.cleanupHandle.status().pending,false);
});

test('unexpected asynchronous factory retirement is joined and cannot acknowledge Site release',async () => {
  let resolve,siteCloses=0,attempts=0;
  const pending=new Promise(done=>{resolve=done;});
  const factory={retire() {assert.equal(this,factory);return ++attempts===1?pending:true;}};
  const cause=new Error('same initialization cause');
  const retaining=retainInstalledHostInitializationFailure(cause,{sourceReader:factory,
    sourceProfile:{close() {siteCloses++;}}});
  await Promise.resolve();await Promise.resolve();assert.equal(siteCloses,0);
  resolve(true);const failure=await retaining;
  assert.equal(failure.primaryFailure,cause);assert.equal(failure.cleanupPending,true);assert.equal(siteCloses,0);
  assert.equal(failure.cleanupErrors[0].error.message,'InstalledSourceReaderRetirementPending');
  await failure.cleanupHandle.retry();assert.equal(siteCloses,1);assert.equal(attempts,2);
  assert.equal(failure.cleanupHandle.status().pending,false);
});
