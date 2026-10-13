import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {interceptSdkRequest,pollSdkPreparation,deliverSdkResponse,pollSdkDecode,
  takeSdkDecodedResult,retireSdkDecodedResult,cleanupSdkPreparation,
  sdkTransportRawObservation} from './_internal/intercepted-request.mjs';
import {prepareOpenAIChatRequest} from './_internal/openai-chat.mjs';
import {createSdkModelPreflight} from './_internal/model-port.mjs';

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
test('unused decoded alias retires only after the same SDK settles, without full cleanup',async t=>{
  const handle=preparation();t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),v=>v.kind==='ready');
  assert.equal(retireSdkDecodedResult(handle),false);
  deliverSdkResponse(handle,new Response('{"value":"é\\r\\n","unknown":17}'));
  await until(()=>pollSdkDecode(handle),v=>v.kind==='ready');
  assert.equal(retireSdkDecodedResult(handle),true);
  assert.equal(retireSdkDecodedResult(handle),true);
  assert.throws(()=>takeSdkDecodedResult(handle),{code:'SdkDecodedResultUnavailable'});
  assert.deepEqual(pollSdkDecode(handle),{kind:'ready'},'retirement is not a new SDK outcome');
  assert.throws(()=>retireSdkDecodedResult({...handle}),{code:'ForeignSdkPreparation'});
});
test('retiring the owner alias never mutates an already transferred original SDK view',async t=>{
  const handle=preparation();t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),v=>v.kind==='ready');
  deliverSdkResponse(handle,new Response('{"value":"é\\r\\n","unknown":17}'));
  await until(()=>pollSdkDecode(handle),v=>v.kind==='ready');
  const escaped=takeSdkDecodedResult(handle);
  assert.equal(retireSdkDecodedResult(handle),true);
  assert.deepEqual(escaped,{value:'é\r\n',unknown:17});
  assert.throws(()=>takeSdkDecodedResult(handle),{code:'SdkDecodedResultUnavailable'});
});
test('SDK decode failure observation stays rejected after unused alias retirement',async t=>{
  const handle=preparation();t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),v=>v.kind==='ready');
  deliverSdkResponse(handle,new Response('not JSON'));
  const before=await until(()=>pollSdkDecode(handle),v=>v.kind==='rejected');
  assert.equal(retireSdkDecodedResult(handle),true);
  assert.deepEqual(pollSdkDecode(handle),before);
});

const wire='{"id":"observed-id","object":"chat.completion","model":"observed-model","choices":[{"index":0,"message":{"role":"assistant","content":"{\\"ok\\":true}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2},"unknown":{"original":"é\\r\\n"}}';
const bytes=new TextEncoder().encode(wire);
function actualChatFixture({failSave=false}={}) {
  const request={},entry={},saved={marker:'Original saved raw'},failure=Error('FixtureStorePending');
  let sends=0,saves=0,completeSave,cleanupAllowed=false;
  const waiting=new Promise(resolve=>{completeSave=resolve;});
  const handle=prepareOpenAIChatRequest({modelId:'gpt-4.1-nano',
    baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',
    options:{prompt:[{role:'user',content:[{type:'text',text:'fixture'}]}],
      responseFormat:{type:'json',name:'answer',schema:{type:'object',properties:{ok:{type:'boolean'}},
        required:['ok'],additionalProperties:false}},temperature:0,topP:1,maxOutputTokens:16},
    maxRequestBytes:4096,maxHeaderBytes:4096,maxHeaders:16,notify(){}});
  const moon={clientProgramModelRequestPreflight:(advance,cleanup)=>({advance,cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan:(...args)=>({start:args.at(-1)}),
    clientProgramModelPhysicalCallForRequest(e,r,poll,cancel,cleanup){
      assert.equal(e,entry);assert.equal(r,request);return {poll,cancel,cleanup};},
    clientProgramModelPhysicalPending:()=>({kind:'pending'}),
    clientProgramModelPhysicalUnknown:()=>({kind:'unknown'}),
    clientProgramModelPhysicalSavedChat:response=>({kind:'chat',response})};
  const port=createSdkModelPreflight({moon,request,preparation:handle,profile:{},installation:{},
    quantities:{tokens:16n,costUnits:0n,durationMs:1n},
    fetch(){sends++;return new Response(bytes,{headers:{'content-type':'application/json'}});},
    responseLimits:{maxBytes:bytes.length,maxChunkBytes:bytes.length,maxChunks:2,
      maxHeaderBytes:64,observedHeaders:['content-type']},
    persistRaw(call,raw){saves++;assert.deepEqual(raw.body,bytes);
      if(failSave)throw failure;return waiting.then(()=>({response:saved}));},
    cleanupRaw:()=>cleanupAllowed,notify(){},checked:value=>value,observeAt:()=> '2026-10-13T00:00:00Z'});
  return {handle,port,entry,saved,failure,completeSave,
    allowCleanup(){cleanupAllowed=true;},sends:()=>sends,saves:()=>saves};
}

// Actual pinned SDK + physical port; Common and saved Store receipt are explicit
// boundary doubles. This proves alias/lifetime behavior, not ACK/grant/heap size.
test('Chat poll drops unused SDK projection while the same raw save remains pending',async t=>{
  const f=actualChatFixture();
  t.after(async()=>{f.completeSave();f.allowCleanup();await until(()=>f.port.preflight.cleanup(),v=>v===true);});
  const plan=(await until(()=>f.port.preflight.advance(),v=>v._0))._1;
  const call=plan.start(f.entry);
  await until(()=>pollSdkDecode(f.handle),v=>v.kind==='ready');
  const original=sdkTransportRawObservation(f.handle);
  assert.equal(call.poll().kind,'pending');
  await until(()=>f.saves(),v=>v===1);
  assert.throws(()=>takeSdkDecodedResult(f.handle),{code:'SdkDecodedResultUnavailable'});
  assert.equal(sdkTransportRawObservation(f.handle),original);
  assert.deepEqual(original.body,bytes);assert.equal(call.cleanup(),false);
  call.cancel();assert.equal(call.cleanup(),false,'abort is not raw cleanup ACK');
  f.completeSave();const observed=await until(()=>call.poll(),v=>v.kind==='chat');
  assert.equal(observed.response,f.saved);assert.equal(f.sends(),1);assert.equal(f.saves(),1);
  assert.equal(call.cleanup(),false);
});
test('Chat cleanup drops unused projection but keeps Store failure Unknown and raw reconciliation',async t=>{
  const f=actualChatFixture({failSave:true});
  t.after(async()=>{f.allowCleanup();await until(()=>f.port.preflight.cleanup(),v=>v===true);});
  const plan=(await until(()=>f.port.preflight.advance(),v=>v._0))._1;
  const call=plan.start(f.entry);
  await until(()=>pollSdkDecode(f.handle),v=>v.kind==='ready');
  call.poll();await until(()=>call.poll(),v=>v.kind==='unknown');
  const original=sdkTransportRawObservation(f.handle);
  assert.equal(call.cleanup(),false);
  assert.throws(()=>takeSdkDecodedResult(f.handle),{code:'SdkDecodedResultUnavailable'});
  assert.equal(f.port.rawFailure(),f.failure);assert.equal(call.poll().kind,'unknown');
  const retry=f.port.reconcileRaw(call);const same=f.port.reconcileRaw(call);
  assert.equal(retry,same);await assert.rejects(retry,error=>error===f.failure);
  assert.equal(sdkTransportRawObservation(f.handle),original);
  assert.deepEqual(original.body,bytes);assert.equal(f.sends(),1);assert.equal(f.saves(),2);
  assert.equal(call.cleanup(),false);
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
    clientProgramModelAsyncPhysicalRequestPlan:()=>({originalPlan:true})};
  const port=createSdkModelPreflight({moon,request:{},preparationProgress:originalProgress,
    profile:{},installation:{},quantities:{tokens:1n,costUnits:0n,durationMs:1n},
    fetch(){sends++;throw Error('Preflight cleanup must not send');},
    responseLimits:{maxBytes:128,maxChunkBytes:128,maxChunks:1,maxHeaderBytes:128},
    persistRaw(){throw Error('Unstarted cleanup must not save');},cleanupRaw:()=>true,
    notify(){},checked:v=>v,observeAt:()=> '2026-10-13T00:00:00Z'});
  assert.equal(port.preflight.advance()._0,false);
  assert.equal(port.preflight.advance()._0,true);
  await until(()=>port.preflight.cleanup(),()=>progressCleanups===1);
  assert.throws(()=>pollSdkDecode(handle),{code:'ForeignSdkPreparation'},
    'SDK cleanup is complete while the other owner remains pending');
  assert.equal(port.preflight.cleanup(),false);
  assert.equal(progressCleanups,2,'Same original preparation owner is retried');
  cleanupAllowed=true;
  assert.equal(port.preflight.cleanup(),true);
  assert.equal(progressCleanups,3);
  assert.equal(port.preflight.cleanup(),true);
  assert.equal(progressCleanups,3,'Completed cleanup remains idempotent');
  assert.equal(sends,0);
});
