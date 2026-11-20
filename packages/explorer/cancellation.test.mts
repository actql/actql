import test from 'node:test';
import assert from 'node:assert/strict';
import {captureCancellation,requestExistingCancellation,lookupExistingCancellation,
  validCancellationObservation} from './cancellation.mjs';
import {createReadEpoch} from '../explorer-ui/read-model.mjs';
const ref={namespaceId:'original',authorityScopeCid:'sha256:'+'a'.repeat(64),runDefinitionCid:'sha256:'+'b'.repeat(64)};
const original=()=>({cancelRef:{...ref,cancelId:'original-cancel',expectedRevision:7},
  attemptRef:{operation:'cancel',attemptId:'original-attempt'}});
const accepted=()=>({kind:'accepted',attemptRef:original().attemptRef,
  cancellation:{kind:'accepted',ref:{...ref},cancelRef:original().cancelRef,revision:8}});
const ticket=()=>createReadEpoch().capture();

test('cancellation captures exact identities and dispatches once without status or replacement revision',async()=>{
  const input=original(),calls=[];
  const client={async attach(r){calls.push(['attach',r]);input.cancelRef.expectedRevision=99;return{
    async cancel(options){calls.push(['cancel',options]);return accepted();},
    status(){assert.fail('no revision replacement');},reconcile(){assert.fail('no implicit reconcile');},
  };}};
  const answer=await requestExistingCancellation(client,input,ticket());
  assert.deepEqual(calls,[['attach',ref],['cancel',{cancelId:'original-cancel',expectedRevision:7,attemptId:'original-attempt'}]]);
  assert.equal(answer.state,'observed');assert.equal(answer.outcome.kind,'accepted');
  assert(validCancellationObservation(answer,original()));
  assert(!Object.hasOwn(answer,'physicalStop'));
});

test('lost or malformed cancellation replies stay presentation Unknown with original references and no retry',async()=>{
  for(const behavior of ['throw','foreign','malformed']){
    let requests=0;
    const client={async attach(){return{async cancel(){requests++;
      if(behavior==='throw')throw new Error('secret Host token and path');
      if(behavior==='malformed')return{kind:'stopped'};
      const value=accepted();value.cancellation.cancelRef.cancelId='foreign';return value;
    }}}};
    const answer=await requestExistingCancellation(client,original(),ticket());
    assert.equal(requests,1);assert.deepEqual(answer,{state:'unknown',original:original()});
    assert(validCancellationObservation(answer,original()));assert(!JSON.stringify(answer).includes('secret'));
    assert(!Object.hasOwn(answer,'kind'),'not a fabricated Owner attempt wire');
  }
});

test('known Owner refusal and conflict remain exact and never become no physical work guarantees',async()=>{
  for(const outcome of [
    {kind:'refused',attemptRef:original().attemptRef,cancelRef:original().cancelRef,
      guarantee:'attempt_uncommitted_unconsumed',reason:'authorization'},
    {kind:'conflict',attemptRef:original().attemptRef,cancelRef:original().cancelRef,reason:'control_revision'},
  ]){
    const answer=await requestExistingCancellation({attach:async()=>({cancel:async()=>outcome})},original(),ticket());
    assert.deepEqual(answer,{state:'observed',original:original(),outcome});
  }
});

test('original cancellation lookup never calls cancel, start, payload or accepts another Run',async()=>{
  const calls=[];
  const client={async attach(r){assert.deepEqual(r,ref);return{
    async lookupCancellation(r){calls.push(r);return{kind:'found',cancellation:accepted().cancellation};},
    cancel(){assert.fail('no resend');},result(){assert.fail('no payload');},
  };},start(){assert.fail('no new Run');}};
  const result=await lookupExistingCancellation(client,original().cancelRef,ticket());
  assert.equal(result.kind,'found');assert.deepEqual(calls,[original().cancelRef]);
  const foreign={kind:'found',cancellation:accepted().cancellation};foreign.cancellation.ref.namespaceId='foreign';
  await assert.rejects(lookupExistingCancellation({attach:async()=>({lookupCancellation:async()=>foreign})},original().cancelRef,ticket()),{code:'ExplorerInvalidCancellation'});
});

test('scope switch discards delayed control replies but never sends a compensating operation',async()=>{
  const epoch=createReadEpoch();let release,requests=0;
  const ready=new Promise(resolve=>release=resolve);
  const answer=requestExistingCancellation({attach:async()=>({async cancel(){requests++;return ready;}})},original(),epoch.capture());
  await new Promise(resolve=>setImmediate(resolve));epoch.invalidate();release(accepted());
  await assert.rejects(answer,{code:'ExplorerStaleScope'});assert.equal(requests,1);
});

test('invalid original fields fail before attach and unknown presentation cannot claim foreign identity',async()=>{
  for(const input of [undefined,{...original(),cancelRef:{...original().cancelRef,expectedRevision:'7'}},
    {...original(),attemptRef:{operation:'submit',attemptId:'wrong'}},
    {...original(),cancelRef:{...original().cancelRef,permission:true}}]){
    assert.throws(()=>captureCancellation(input?.cancelRef,input?.attemptRef),{code:'ExplorerInvalidCancellation'});
  }
  const forged={state:'unknown',original:{...original(),cancelRef:{...original().cancelRef,cancelId:'other'}}};
  assert(!validCancellationObservation(forged,original()));
  assert(!validCancellationObservation({...forged,allow:true},original()));
});
