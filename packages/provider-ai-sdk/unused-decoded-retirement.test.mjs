import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {interceptSdkRequest,pollSdkPreparation,pollSdkDecode,
  takeSavedSdkDecodedResult,retireSdkDecodedResult,cleanupSdkPreparation,prepareSdkTransport,
  startSdkTransport,sdkTransportRawObservation,confirmSavedSdkTransportResponse} from './_internal/intercepted-request.mjs';
import {createSdkStructuredModelPreflight} from './_internal/model-port.mjs';

async function until(read,accept) {
  for(let i=0;i<60;i++){const value=read();if(accept(value))return value;await turn();}
  assert.fail('Finite original SDK observation was not reached');
}
async function release(handle){await until(()=>cleanupSdkPreparation(handle),v=>v===true);}
const endpoint='https://fixture.invalid/chat';
function preparation(){return interceptSdkRequest({endpoint,maxRequestBytes:128,
  maxHeaderBytes:128,maxHeaders:4,notify(){},
  async runSdk(fetch){const response=await fetch(endpoint,{method:'POST',body:'{}'});
    return response.json();}});}
async function confirmResponse(handle, wire) {
  const bytes = new TextEncoder().encode(wire);
  let sends = 0;
  prepareSdkTransport(handle, {responseMode: 'saved-sdk',
    responseLimits: {maxBytes: 128, maxChunkBytes: 128, maxChunks: 2, maxHeaderBytes: 128},
    fetch() {assert.equal(++sends, 1);return new Response(bytes);}});
  startSdkTransport(handle);
  const raw = await until(() => sdkTransportRawObservation(handle), Boolean);
  assert.equal(raw.transportComplete, true);
  assert.deepEqual(raw.body, bytes);
  assert.equal(pollSdkDecode(handle).kind, 'pending');
  const receipt = Object.freeze({});
  confirmSavedSdkTransportResponse(handle, raw, {receipt, bytes});
  assert.equal(sends, 1);
  return {receipt, bytes};
}
test('unused decoded alias retires only after the same SDK settles, without full cleanup',async t=>{
  const handle=preparation();t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),v=>v.kind==='ready');
  assert.equal(retireSdkDecodedResult(handle),false);
  const {receipt, bytes} = await confirmResponse(handle, '{"value":"é\\r\\n","unknown":17}');
  await until(()=>pollSdkDecode(handle),v=>v.kind==='ready');
  assert.equal(retireSdkDecodedResult(handle),true);
  assert.equal(retireSdkDecodedResult(handle),true);
  assert.throws(()=>takeSavedSdkDecodedResult(handle, receipt, bytes),{code:'SdkDecodedResultUnavailable'});
  assert.deepEqual(pollSdkDecode(handle),{kind:'ready'},'retirement is not a new SDK outcome');
  assert.throws(()=>retireSdkDecodedResult({...handle}),{code:'ForeignSdkPreparation'});
});
test('retiring the owner alias never mutates an already transferred original SDK view',async t=>{
  const handle=preparation();t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),v=>v.kind==='ready');
  const {receipt, bytes} = await confirmResponse(handle, '{"value":"é\\r\\n","unknown":17}');
  await until(()=>pollSdkDecode(handle),v=>v.kind==='ready');
  const escaped=takeSavedSdkDecodedResult(handle, receipt, bytes);
  assert.equal(retireSdkDecodedResult(handle),true);
  assert.deepEqual(escaped,{value:'é\r\n',unknown:17});
  assert.throws(()=>takeSavedSdkDecodedResult(handle, receipt, bytes),{code:'SdkDecodedResultUnavailable'});
});
test('SDK decode failure observation stays rejected after unused alias retirement',async t=>{
  const handle=preparation();t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),v=>v.kind==='ready');
  await confirmResponse(handle, 'not JSON');
  const before=await until(()=>pollSdkDecode(handle),v=>v.kind==='rejected');
  assert.equal(retireSdkDecodedResult(handle),true);
  assert.deepEqual(pollSdkDecode(handle),before);
});

test('Saved SDK cleanup waits for the same operation after confirmed Raw is delivered',async t=>{
  let finish, delivered=false, sends=0;
  const held=new Promise(resolve=>{finish=resolve;});
  const handle=interceptSdkRequest({endpoint,maxRequestBytes:128,maxHeaderBytes:128,maxHeaders:4,notify(){},
    async runSdk(fetch) {
      const response=await fetch(endpoint,{method:'POST',body:'{}'});
      delivered=true;
      await held;
      return response.text();
    }});
  t.after(async()=>{finish();await release(handle);});
  await until(()=>pollSdkPreparation(handle),value=>value.kind==='ready');
  prepareSdkTransport(handle,{responseMode:'saved-sdk',
    responseLimits:{maxBytes:128,maxChunkBytes:128,maxChunks:2,maxHeaderBytes:128},
    fetch(){sends++;return new Response('{"value":1}');}});
  startSdkTransport(handle);
  const raw=await until(()=>sdkTransportRawObservation(handle),Boolean);
  assert.equal(delivered,false);
  const receipt=Object.freeze({});
  confirmSavedSdkTransportResponse(handle,raw,{receipt,bytes:raw.body});
  await until(()=>delivered,Boolean);
  assert.equal(pollSdkDecode(handle).kind,'pending');
  assert.equal(cleanupSdkPreparation(handle),false);
  assert.strictEqual(sdkTransportRawObservation(handle),raw);
  assert.throws(()=>startSdkTransport(handle),{code:'SdkTransportStartRefused'});
  finish();
  await release(handle);
  assert.equal(sends,1);
  assert.equal(Buffer.from(raw.body).toString(),'{"value":1}');
});

// Original SDK and preparation-progress cleanup acknowledge independently.
// Retiring the SDK alias must retain the second owner's pending retry.
test('partial SDK owner cleanup retries while original preparation owner remains pending', async()=>{
  const handle=preparation();
  await until(()=>pollSdkPreparation(handle),v=>v.kind==='ready');
  let cleanupAllowed=false,progressCleanups=0,sends=0;
  const originalProgress={advance:()=>({kind:'ready',preparation:handle}),
    cleanup(){progressCleanups++;return cleanupAllowed;}};
  const moon={clientProgramModelRequestPreflight:(advance,cleanup)=>({advance,cleanup}),
    clientProgramModelStructuredRequestPlan:()=>({originalPlan:true}),
    clientProgramModelPhysicalSavedStructured(){assert.fail('No saved response');}};
  const port=createSdkStructuredModelPreflight({moon,request:{},preparationProgress:originalProgress,
    profile:{},installation:{},quantities:{tokens:1n,costUnits:0n,durationMs:1n},
    fetch(){sends++;throw Error('Preflight cleanup must not send');},
    responseLimits:{maxBytes:128,maxChunkBytes:128,maxChunks:1,maxHeaderBytes:128},
    persistRaw(){throw Error('Unstarted cleanup must not save');},cleanupRaw:()=>true,
    notify(){},checked:v=>v,observeAt:()=> '2026-10-13T00:00:00Z'}, Object.freeze({}));
  assert.equal(port.preflight.advance()._0,false);
  assert.deepEqual(port.preflight.advance(),{_0:true,_1:{originalPlan:true}});
  await until(()=>port.preflight.cleanup(),()=>progressCleanups===1);
  assert.throws(()=>pollSdkDecode(handle),{code:'ForeignSdkPreparation'},
    'SDK cleanup is complete while the other owner remains pending');
  assert.equal(retireSdkDecodedResult(handle),true);
  assert.throws(()=>retireSdkDecodedResult({...handle}),{code:'ForeignSdkPreparation'});
  assert.equal(port.preflight.cleanup(),false);
  assert.equal(progressCleanups,2,'Same original preparation owner is retried');
  cleanupAllowed=true;
  assert.equal(port.preflight.cleanup(),true);
  assert.equal(progressCleanups,3);
  assert.equal(port.preflight.cleanup(),true);
  assert.equal(progressCleanups,3,'Completed cleanup remains idempotent');
  assert.equal(sends,0);
});
