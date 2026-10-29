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
