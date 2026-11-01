import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';

// Constructor/method-selection controls only. These ports issue no grant,
// physical read, Common capacity, business Run or cleanup acknowledgement.
function fixture() {
  const calls=[];
  const site=Object.freeze({credential:{},referenceCurrent(){return true;},
    callResource(){assert.fail('No physical call in a constructor control');}});
  const originalSite=Object.freeze({site,referenceCurrent(){return true;},
    authorizationPurpose(){assert.fail('No acquisition in a constructor control');},
    bindRunAcquisition(){assert.fail('No acquisition in a constructor control');},
    readChildCredential(){assert.fail('No read child in a constructor control');},
    callResource:site.callResource});
  return{site,originalSite,calls,options:{capacity:{},originalSite,assertCurrent(){calls.push('installation-current');},
    operation:'read',maxResponses:1,maxResponseBytes:128,maxSecretBytes:128}};
}

for(const method of ['createReader','readPages'])test(`obsolete ${method} mode is refused before invoking its constructor or transport`,()=>{
  const f=fixture();
  assert.throws(()=>createInstalledCredentialSourceReader({...f.options,
    [method](){assert.fail('Obsolete mode must not execute');}}),{code:'InvalidInstalledCredentialSourceReader'});
  assert.deepEqual(f.calls,[]);
});

test('obsolete unhosted raw-site page mode is refused rather than constructing another credential binding',()=>{
  const f=fixture();const {originalSite,...options}=f.options;
  assert.throws(()=>createInstalledCredentialSourceReader({...options,site:f.site,
    preparePageReader(){assert.fail('No unsupported page preparation');}}),{code:'InvalidInstalledCredentialSourceReader'});
  assert.deepEqual(f.calls,[]);
});

for(const method of ['preparePageReader','prepareReadSequence'])test(`normal ${method} selection captures the original method once`,()=>{
  const f=fixture();let prepared=0,retired=0;
  const options={...f.options,[method](){prepared++;
    return method==='preparePageReader'?{fetchPage(){},decodePage(){}}:{read(){},retire(){retired++;return true;}};}};
  const factory=createInstalledCredentialSourceReader(options);
  options[method]=()=>assert.fail('No replacement installation callback');
  const reader=factory.prepare({resource:'records',columns:['id'],verifyRead(){},authorizationFor(){},
    authorizeReadChild(){},chargePage(){},consumePage(){},consumeObservation(){}});
  assert.equal(prepared,1);reader.requestStop();
  assert.equal(reader.observe().cleanupConfirmed,true);assert.equal(factory.retire(),true);
  assert.equal(retired,method==='prepareReadSequence'?1:0);
});


test('installation refuses mixed missing accessor and proxy protocols without invoking a callback',()=>{
  const f=fixture();let observed=0;
  const page=()=>assert.fail('No unsupported callback');
  for(const input of [{...f.options},{...f.options,preparePageReader:page,prepareReadSequence:page},
    {...f.options,get preparePageReader(){observed++;return page;}},
    new Proxy({...f.options,preparePageReader:page},{get(){observed++;assert.fail('No Proxy observation');}})]) {
    assert.throws(()=>createInstalledCredentialSourceReader(input),error=>
      ['InvalidInstalledCredentialSourceReader','InstalledSourceReaderMethodUnavailable'].includes(error.code));
  }
  assert.equal(observed,0);assert.deepEqual(f.calls,[]);
});

test('invalid asynchronous page preparation remains owned until the same callback settles',async()=>{
  const f=fixture();let resolve;
  const pending=new Promise(done=>{resolve=done;});
  const factory=createInstalledCredentialSourceReader({...f.options,preparePageReader(){return pending;}});
  const reader=factory.prepare({columns:['id'],verifyRead(){},authorizationFor(){},chargePage(){},consumePage(){}});
  await assert.rejects(reader.read(),{code:'InstalledSourcePageCallbackNotSynchronous'});
  reader.requestStop();assert.equal(reader.observe().pendingCallbacks,1);
  assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(factory.retire(),false);
  resolve({fetchPage(){},decodePage(){}});await pending;await Promise.resolve();
  assert.equal(reader.observe().pendingCallbacks,0);assert.equal(reader.observe().cleanupConfirmed,true);
  assert.equal(factory.retire(),true);
});
