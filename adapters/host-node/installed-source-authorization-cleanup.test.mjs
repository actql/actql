import assert from 'node:assert/strict';
import test from 'node:test';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
// Actual shared cleanup function with one explicit Account close DATA port.
// No Account, SQLite, private key, FD, runtime, network or physical ACK exists.
test('failed original Site initialization retains original authorization until its true close ACK',async()=>{
  const primary=new Error('same original Site constructor failure');
  let attempts=0,allowClose=false;
  const authorization=Object.freeze({close(){assert.equal(this,authorization);attempts++;return allowClose;}});
  const failure=await retainInstalledHostInitializationFailure(primary,{authorization});
  assert.equal(attempts,1,'same constructed authorization must be offered close during initializer cleanup');
  assert.equal(failure.cleanupPending,true,'false close must retain the original authorization');
  assert.equal(failure.cleanupHandle.status().pending,true);
  allowClose=true;
  assert.equal((await failure.cleanupHandle.retry()).pending,false);
  assert.equal(attempts,2);assert.equal(failure.cleanupPending,false);
  assert.equal((await failure.cleanupHandle.retry()).pending,false);assert.equal(attempts,2);
});

test('same factory then Site then Account and initial parent retain original methods across initialization await', async () => {
  let finishInitialization, initialized = false, readerReady = false, accountReady = false;
  let readerCloses = 0, accountCloses = 0, siteCloses = 0, initialCloses = 0;
  const initialization = new Promise(resolve => {finishInitialization = resolve;});
  const primary = Object.assign(new Error('original constructor child'), {cleanupHandle: {
    retry: () => initialization, status: () => ({pending: !initialized, errors: []}),
  }});
  const sourceReader = {retire() {assert.equal(this, sourceReader);readerCloses++;return readerReady;}};
  const authorization = {close() {assert.equal(this, authorization);accountCloses++;return accountReady;}};
  const sourceProfile = Object.freeze({close() {siteCloses++;}});
  const initialControl = Object.freeze({close() {initialCloses++;return {pending: false};}});
  const closing = retainInstalledHostInitializationFailure(primary,
    {sourceReader, sourceProfile, authorization, initialControl});
  sourceReader.retire = () => assert.fail('No replaced factory method');
  authorization.close = () => assert.fail('No replaced Account method');
  initialized = true;finishInitialization();
  const failure = await closing;
  assert.equal(failure.primaryFailure, primary);
  assert.equal(readerCloses, 1);assert.equal(siteCloses, 0);assert.equal(accountCloses, 0);assert.equal(initialCloses, 0);
  assert(failure.cleanupHandle.status().owners.includes('source-reader'));
  readerReady = true;
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(readerCloses, 2);assert.equal(siteCloses, 1);assert.equal(accountCloses, 1);assert.equal(initialCloses, 0);
  accountReady = true;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(readerCloses, 2);assert.equal(siteCloses, 1);assert.equal(accountCloses, 2);assert.equal(initialCloses, 1);
  await failure.cleanupHandle.retry();
  assert.equal(readerCloses, 2);assert.equal(accountCloses, 2);assert.equal(initialCloses, 1);
});

test('non-Unit Promise retirement is joined without acknowledging factory or Account cleanup', async () => {
  for (const kind of ['reader', 'account']) {
    let valid = false, calls = 0, siteCloses = 0;
    const method = () => {calls++;return valid ? true : Promise.resolve(true);};
    const fields = kind === 'reader'
      ? {sourceReader: Object.freeze({retire: method}), sourceProfile: {close() {siteCloses++;}}}
      : {authorization: Object.freeze({close: method})};
    const primary = new Error('same original initialization');
    const failure = await retainInstalledHostInitializationFailure(primary, fields);
    assert.equal(failure.primaryFailure, primary);assert.equal(failure.cleanupPending, true);
    assert.equal(calls, 1);assert.equal(siteCloses, 0);
    valid = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(calls, 2);assert.equal(siteCloses, kind === 'reader' ? 1 : 0);
  }
});

test('pending original Site blocks Account close and missing Account method remains retryable on that original', async () => {
  let siteReady = false, siteCloses = 0, accountCloses = 0;
  const authorization = {}, primary = new Error('original Site setup');
  const failure = await retainInstalledHostInitializationFailure(primary, {
    sourceProfile: {close() {siteCloses++;if (!siteReady) throw new Error('same Site close pending');}},
    authorization,
  });
  assert.equal(failure.primaryFailure, primary);assert.equal(failure.cleanupPending, true);
  assert.equal(siteCloses, 1);assert.equal(accountCloses, 0);
  siteReady = true;
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(siteCloses, 2);assert.equal(accountCloses, 0);
  authorization.close = function () {assert.equal(this, authorization);accountCloses++;return true;};
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(siteCloses, 2);assert.equal(accountCloses, 1);
});
