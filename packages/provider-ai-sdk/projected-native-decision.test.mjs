import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareProjectedTypeSafeDecisionRequest} from './_internal/typesafe-decision.mjs';
import {pollSdkPreparation,sdkPreparedRequest,prepareSdkTransport,startSdkTransport,
  pollSdkTransport,sdkTransportRawObservation,pollSdkDecode,takeSdkDecodedResult,
  cleanupSdkPreparation,cancelSdkPreparation} from './_internal/intercepted-request.mjs';

// Actual pinned SDK, synthetic HTTP and explicit Common boundary doubles.
// The independent wires match Common's positional projection fixture; this
// does not establish actual Common admission, profile or installed Run support.
const stateWire='["é\\r\\né\\n😀",0,false,null,{"text":""}]';
const questionsWire='{"q0000000000":{"criteria":{"o0000000000":"toString","o0000000001":"__proto__","o0000000002":"constructor"},"instructions":"Choose a routing label.\\r\\né","type":"choice"},"q0000000001":{"criteria":["low","medium","high"],"instructions":"Score the state.","type":"score"},"q0000000002":{"instructions":"P(true) for eligibility.","type":"boolean"}}';
const expected={model:'jev-latest',state:['é\r\né\n😀',0,false,null,{text:''}],
  questions:{q0000000000:{criteria:{o0000000000:'toString',o0000000001:'__proto__',
    o0000000002:'constructor'},instructions:'Choose a routing label.\r\né',type:'choice'},
  q0000000001:{criteria:['low','medium','high'],instructions:'Score the state.',type:'score'},
  q0000000002:{instructions:'P(true) for eligibility.',type:'noul'}}};
const responseWire='{"answers":{"q0000000000":{"type":"choice","choice":"o0000000001","probabilities":{"o0000000000":0.33,"o0000000001":0.33,"o0000000002":0.33}},"q0000000001":{"type":"score","score":1.5,"probabilities":{"0":0,"1":0.5,"2":0.5}},"q0000000002":{"type":"noul","noul":0.25}},"unknown":{"text":"é\\r\\n"}}';
function fixture({current=true,retired=false}={}) {
  const projected={},provider={},request={};
  const binding={_0:'task',_1:'prompt',_2:'schema',_3:'native'};
  const wires={_0:stateWire,_1:questionsWire};
  let wakes=0;
  const moon={clientProgramNativeDecisionRequestMatches(value,p,r){
    return current&&!retired&&value===projected&&p===provider&&r===request;},
    clientProgramNativeDecisionRequestBinding(value){assert.equal(value,projected);return binding;},
    clientProgramNativeDecisionRequestWires(value){assert.equal(value,projected);return wires;}};
  const input={moon,projected,admittedProvider:provider,request,
    taskCid:'task',promptCid:'prompt',outputSchemaCid:'schema',modelSelector:'native',
    modelId:'jev-latest',baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',
    maxRequestBytes:4096,maxHeaderBytes:4096,maxHeaders:16,notify(){wakes++;}};
  return {input,binding,wires,wakes:()=>wakes};
}
async function until(read,kind){for(let i=0;i<50;i++){const value=read();
  if(value.kind===kind)return value;await turn();}assert.fail(`Finite projected native ${kind} unavailable`);}
async function release(handle){for(let i=0;i<50;i++){if(cleanupSdkPreparation(handle))return;
  await turn();}assert.fail('Original projected native SDK cleanup incomplete');}

test('original Common projection keys reach actual native SDK without prototype-key or generation rewriting',async t=>{
  const ambient=globalThis.fetch;let calls=0;
  globalThis.fetch=()=>{calls++;assert.fail('No ambient network');};
  t.after(()=>{globalThis.fetch=ambient;});
  const f=fixture(),handle=prepareProjectedTypeSafeDecisionRequest(f.input);
  t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),'ready');
  const body=JSON.parse(sdkPreparedRequest(handle).body);
  assert.deepEqual(body,expected);assert.equal(calls,0);
  for(const key of ['temperature','top_p','max_tokens','seed','tools'])assert.equal(Object.hasOwn(body,key),false);
  assert.deepEqual(Object.keys(body.questions),['q0000000000','q0000000001','q0000000002']);
});

test('foreign original request provider view and retired view refuse before allocating SDK',()=>{
  for(const change of [input=>{input.request={};},input=>{input.admittedProvider={};},
    input=>{input.projected={};},input=>{delete input.moon.clientProgramNativeDecisionRequestMatches;}]){
    const f=fixture();change(f.input);
    assert.throws(()=>prepareProjectedTypeSafeDecisionRequest(f.input),/TypeSafeOriginalProjectionUnavailable/u);
    assert.equal(f.wakes(),0);
  }
  for(const options of [{current:false},{retired:true}]){
    const f=fixture(options);
    assert.throws(()=>prepareProjectedTypeSafeDecisionRequest(f.input),/TypeSafeOriginalProjectionUnavailable/u);
    assert.equal(f.wakes(),0);
  }
});

test('each original binding mismatch refuses instead of inventing a native Task selection',()=>{
  for(const field of ['taskCid','promptCid','outputSchemaCid','modelSelector']){
    const f=fixture();f.input[field]='foreign';
    assert.throws(()=>prepareProjectedTypeSafeDecisionRequest(f.input),/TypeSafeOriginalProjectionBindingMismatch/u);
    assert.equal(f.wakes(),0);
  }
});

test('original projected wires and selector stay captured across external tuple mutation',async t=>{
  const f=fixture(),handle=prepareProjectedTypeSafeDecisionRequest(f.input);
  t.after(()=>release(handle));
  f.wires._0='["changed"]';f.wires._1='{}';f.binding._3='foreign';f.input.modelId='foreign';
  await until(()=>pollSdkPreparation(handle),'ready');
  assert.deepEqual(JSON.parse(sdkPreparedRequest(handle).body),expected);
});

test('native positional response remains raw and SDK observed, not Common answer completion',async t=>{
  const f=fixture(),handle=prepareProjectedTypeSafeDecisionRequest(f.input);
  t.after(()=>release(handle));await until(()=>pollSdkPreparation(handle),'ready');
  const bytes=new TextEncoder().encode(responseWire);let calls=0;
  prepareSdkTransport(handle,{responseLimits:{maxBytes:bytes.length,maxChunkBytes:bytes.length,
    maxChunks:2,maxHeaderBytes:64,observedHeaders:['content-type']},fetch(url,init){calls++;
    assert.equal(url,'https://fixture.invalid/v1/systemone');
    assert.deepEqual(JSON.parse(init.body),expected);
    return new Response(bytes,{headers:{'content-type':'application/json'}});}});
  assert.equal(calls,0);startSdkTransport(handle);
  await until(()=>pollSdkTransport(handle),'response');await until(()=>pollSdkDecode(handle),'ready');
  const observed=takeSdkDecodedResult(handle);
  assert.equal(observed.answers.q0000000000.choice,'o0000000001');
  assert.equal(observed.answers.q0000000001.score,1.5);
  assert.equal(observed.answers.q0000000002.probability,0.25);
  assert.deepEqual(observed.usage,{inputTokens:undefined,outputTokens:undefined});
  assert.equal(Object.hasOwn(observed.response.body,'model'),false);
  assert.deepEqual(sdkTransportRawObservation(handle).body,bytes);
  assert.throws(()=>startSdkTransport(handle),{code:'SdkTransportStartRefused'});
  assert.equal(calls,1);
  // Alias-to-original answer mapping, distributions/precision and endpoint
  // completeness remain with the existing Common response child, not JS.
});

test('projected native request exact physical byte bound and one short do not retry',async()=>{
  const length=Buffer.byteLength(JSON.stringify(expected));
  for(const maxRequestBytes of [length,length-1]){
    const f=fixture();f.input.maxRequestBytes=maxRequestBytes;
    const handle=prepareProjectedTypeSafeDecisionRequest(f.input);
    const result=await until(()=>pollSdkPreparation(handle),maxRequestBytes===length?'ready':'rejected');
    if(maxRequestBytes===length)assert.equal(sdkPreparedRequest(handle).requestBytes,length);
    else assert.equal(result.issue,'SdkRequestBindingRefused');
    await release(handle);
  }
});

test('cancelled projected native preparation keeps the same SDK handle and starts zero transport',async()=>{
  const f=fixture(),abort=new AbortController();f.input.signal=abort.signal;
  const handle=prepareProjectedTypeSafeDecisionRequest(f.input);
  await until(()=>pollSdkPreparation(handle),'ready');let calls=0;
  prepareSdkTransport(handle,{responseLimits:{maxBytes:512,maxChunkBytes:512,maxChunks:2,
    maxHeaderBytes:64,observedHeaders:[]},fetch(){calls++;assert.fail('No cancelled send');}});
  abort.abort();cancelSdkPreparation(handle);
  assert.throws(()=>startSdkTransport(handle),{code:'SdkTransportStartRefused'});
  await release(handle);assert.equal(calls,0);
});
