import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {types} from 'node:util';
import {startInstalledRowRun} from './installed-row-run.mjs';
import {parse} from 'acorn';

const source=fs.readFileSync(new URL('./installed-credential-source-reader.mjs',import.meta.url),'utf8');
const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'});
const edits=[];
for(const node of tree.body){
  if(node.type==='ImportDeclaration')edits.push([node.start,node.end]);
  if(node.type==='ExportNamedDeclaration'){assert(node.declaration);edits.push([node.start,node.declaration.start]);}
}
let executable=source;
for(const [start,end]of edits.sort((a,b)=>b[0]-a[0]))executable=executable.slice(0,start)+executable.slice(end);
const unused=()=>assert.fail('preparation must not acquire, grant, send or close physical I/O');
const createReader=Function('types','ownHttpRequest','ownResponseHeaderNames',
  'ownInvocationAuthorization','invocationBindingsMatch','invokeScopedCredentialOperation',
  'openHttpsCredentialBinding','closeHttpsCredentialBinding',
  executable+'\nreturn createInstalledCredentialSourceReader;')(
  types,unused,unused,unused,unused,unused,unused,unused);

test('failed Source preparation retires only its original borrow and leaves a shared-factory peer unstopped',async()=>{
  const originalSite={bindRunAcquisition:unused,authorizationPurpose:unused,
    callResource:unused,referenceCurrent(){return true;}};
  const capacity={},factory=createReader({capacity,originalSite,assertCurrent(){},
    operation:'fixture:read',maxResponses:1,maxResponseBytes:32,maxSecretBytes:32,
    preparePageReader(){return {fetchPage:unused,decodePage:unused};}});
  const peer=factory.prepare({resource:'records',columns:[],verifyRead(){},
    authorizationFor:unused,chargePage:unused,consumePage:unused});
  let observed,closed=false;
  const ok=value=>({$tag:1,_0:value});
  const moon={clientProgramRowSourceStartProviderAccounted:()=>ok({}),
    clientProgramRowSourceBorrowResponses:()=>ok({}),
    clientProgramRowSourceBindResponseCleanup(_borrow,observer){observed=observer;return ok(undefined);},
    clientProgramRowSourceCloseAccounted(){if(!observed())return {$tag:0,_0:'pending'};closed=true;return ok(undefined);},
    clientProgramRowSourceCaptureCleanup:()=>ok(true),clientProgramRowSourceCaptureCleanupAdvance:()=>ok(true)};
  const session=startInstalledRowRun({moon,acquisition:{},nonce:'failed-only',ledger:{},
    capacity:{provider:capacity,transferBytes:0n,executionBytes:0n}});
  let peerStopped;
  try {
    // Missing authorizationFor is rejected by the original factory before
    // any request, without cancelling a different prepared acquisition.
    await assert.rejects(session.readProvider({prepare:factory.prepare,receiver:factory,retire:factory.retire,
      options:{resource:'records',columns:[],verifyRead(){},chargePage:unused,consumePage:unused}}),
    {code:'InstalledSourceReaderMethodUnavailable'});
    const state={};session.closeAfterFailure(state);
    peerStopped=peer.observe().stopRequested;
    assert.equal(closed,true,'this original unstarted borrow can retire');
  } finally {assert.equal(factory.retire(),true);}
  assert.equal(peerStopped,false,'failed preparation cannot retire another request on the same installation');
});

test('factory retirement cannot forget an unreturned asynchronous preparation after reentry',async()=>{
  const release=Promise.withResolvers();
  let factory,finished=false;
  const originalSite={bindRunAcquisition:unused,authorizationPurpose:unused,
    callResource:unused,referenceCurrent(){return true;}};
  factory=createReader({capacity:Object.freeze({explicitFixtureDemand:true}),originalSite,
    assertCurrent(){},operation:'fixture:read',maxResponses:1,maxResponseBytes:32,maxSecretBytes:32,
    preparePageReader(){
      assert.equal(factory.retire(),false,'the active preparer has not handed off its owner');
      return release.promise.then(()=>{finished=true;return {fetchPage:unused,decodePage:unused};});
    }});
  assert.throws(()=>factory.prepare({resource:'records',columns:[],
    verifyRead(){},authorizationFor:unused,chargePage:unused,consumePage:unused}),
  {code:'InstalledSourceReaderFactoryClosed'});
  const retiredWhilePending=factory.retire();
  // Settle the exact original Promise even on the expected red, leaving no
  // escaped callback or physical task behind the review counter.
  release.resolve();
  await release.promise;
  for(let index=0;index<4;index++)await Promise.resolve();
  assert.equal(finished,true);
  assert.equal(retiredWhilePending,false,'a pending callback survives the rejected prepare handoff');
  assert.equal(factory.retire(),true,'the same factory can retire after its original callback settles');
});


test('same RowRun retires a failed original factory borrow only after its callback settles',async()=>{
  const release=Promise.withResolvers();let factory,cleanup,retired=false;
  const originalSite={bindRunAcquisition:unused,authorizationPurpose:unused,
    callResource:unused,referenceCurrent(){return true;}};
  const capacity={},acquisition={},run={},ledger={};
  factory=createReader({capacity,originalSite,assertCurrent(){},operation:'fixture:read',
    maxResponses:1,maxResponseBytes:32,maxSecretBytes:32,preparePageReader(){
      assert.equal(factory.retire(),false);
      return release.promise.then(()=>({fetchPage:unused,decodePage:unused}));
    }});
  const ok=value=>({$tag:1,_0:value}),error=value=>({$tag:0,_0:value});
  const moon={clientProgramRowSourceStartProviderAccounted(){return ok(run);},
    clientProgramRowSourceBorrowResponses(){return ok({});},
    clientProgramRowSourceBindResponseCleanup(_borrow,observed){cleanup=observed;return ok(undefined);},
    clientProgramRowSourceCloseAccounted(){if(!cleanup())return error('same factory callback pending');retired=true;return ok(undefined);},
    clientProgramRowSourceCaptureCleanup(){return ok(true);},
    clientProgramRowSourceCaptureCleanupAdvance(){return ok(true);}};
  const session=startInstalledRowRun({moon,acquisition,nonce:'same',ledger,
    capacity:{provider:capacity,transferBytes:0n,executionBytes:0n}});
  await assert.rejects(session.readProvider({prepare:factory.prepare,receiver:factory,retire:factory.retire,
    options:{resource:'records',columns:[],verifyRead(){},authorizationFor:unused,
      chargePage:unused,consumePage:unused}}),{code:'InstalledSourceReaderFactoryClosed'});
  const state={};session.closeAfterFailure(state);
  assert.equal(state.closeFailed,true);assert.equal(retired,false);assert.equal(cleanup(),false);
  // Always join this exact original before any terminal assertion.
  release.resolve();await release.promise;
  for(let index=0;index<4;index++)await Promise.resolve();
  assert.equal(await state.recovery.cleanup(),true);
  assert.equal(retired,true);assert.equal(cleanup(),true);
});

test('failed factory retirement keeps exact then receiver and passive observation without settlement ACK',async()=>{
  const release=Promise.withResolvers();let reads=0,calls=0,cleanup,ready=false,thenReads=0;
  const original=new Error('original factory failure');
  const pending={get then(){thenReads++;return function(resolve,reject){
    assert.equal(this,pending);return release.promise.then(resolve,reject);
  };}};
  const factory={prepare(){reads++;throw original;},retire(){
    assert.equal(this,factory);calls++;return ready?true:pending;
  }};
  const ok=value=>({$tag:1,_0:value});
  const moon={clientProgramRowSourceStartProviderAccounted:()=>ok({}),
    clientProgramRowSourceBorrowResponses:()=>ok({}),
    clientProgramRowSourceBindResponseCleanup(_borrow,observed){cleanup=observed;return ok(undefined);},
    clientProgramRowSourceCloseAccounted(){return cleanup()?ok(undefined):{$tag:0,_0:'pending'};},
    clientProgramRowSourceCaptureCleanup:()=>ok(true),clientProgramRowSourceCaptureCleanupAdvance:()=>ok(true)};
  const session=startInstalledRowRun({moon,acquisition:{},nonce:'same',ledger:{},
    capacity:{provider:{},transferBytes:0n,executionBytes:0n}});
  await assert.rejects(session.readProvider({prepare:factory.prepare,receiver:factory,retire:factory.retire,
    options:{verifyRead(){}}}),error=>error===original);
  factory.retire=()=>assert.fail('replacement method');
  const state={};session.closeAfterFailure(state);
  assert.equal(calls,1);assert.equal(thenReads,1);
  assert.equal(cleanup(),false);assert.equal(cleanup(),false);assert.equal(calls,1);
  release.resolve(true);await release.promise;for(let index=0;index<4;index++)await Promise.resolve();
  assert.equal(cleanup(),false);assert.equal(calls,1);
  ready=true;assert.equal(await state.recovery.cleanup(),true);
  assert.equal(calls,2);assert.equal(reads,1);assert.equal(thenReads,1);
});

test('failed factory retirement never accepts a truthy non-Bool acknowledgement',async()=>{
  for(const declined of [1,'closed',Object.freeze({cleanupConfirmed:true})]){
    let cleanup,ready=false,calls=0;
    const original=new Error('same prepare failure'),factory={prepare(){throw original;},
      retire(){assert.equal(this,factory);calls++;return ready?true:declined;}};
    const ok=value=>({$tag:1,_0:value});
    const moon={clientProgramRowSourceStartProviderAccounted:()=>ok({}),
      clientProgramRowSourceBorrowResponses:()=>ok({}),
      clientProgramRowSourceBindResponseCleanup(_borrow,observed){cleanup=observed;return ok(undefined);},
      clientProgramRowSourceCloseAccounted:()=>cleanup()?ok(undefined):{$tag:0,_0:'pending'},
      clientProgramRowSourceCaptureCleanup:()=>ok(true),clientProgramRowSourceCaptureCleanupAdvance:()=>ok(true)};
    const session=startInstalledRowRun({moon,acquisition:{},nonce:'same',ledger:{},
      capacity:{provider:{},transferBytes:0n,executionBytes:0n}});
    await assert.rejects(session.readProvider({prepare:factory.prepare,receiver:factory,retire:factory.retire,
      options:{verifyRead(){}}}),error=>error===original);
    const state={};session.closeAfterFailure(state);assert.equal(cleanup(),false);
    assert.equal(calls,1);ready=true;assert.equal(await state.recovery.cleanup(),true);assert.equal(calls,2);
  }
});
