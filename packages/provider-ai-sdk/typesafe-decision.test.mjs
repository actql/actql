import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareTypeSafeDecisionRequest} from './_internal/typesafe-decision.mjs';
import {pollSdkPreparation,sdkPreparedRequest,prepareSdkTransport,startSdkTransport,
  pollSdkTransport,sdkTransportRawObservation,pollSdkDecode,takeSdkDecodedResult,
  cancelSdkPreparation,cleanupSdkPreparation} from './_internal/intercepted-request.mjs';

const state=['é\r\né\n😀',0,false,null,{text:''}];
const choice=Object.fromEntries([['constructor',''],['toString','é\r\n'],['other','é']]);
const questions=Object.fromEntries([
  ['constructor',{type:'choice',instructions:'',criteria:choice}],
  ['score',{type:'score',instructions:'é\r\n',criteria:['','middle','high']}],
  ['boolean',{type:'boolean',instructions:''}],
]);
const expected={model:'jev-latest',state,questions:Object.fromEntries([
  ['constructor',{type:'choice',instructions:'',criteria:choice}],
  ['score',{type:'score',instructions:'é\r\n',criteria:['','middle','high']}],
  ['boolean',{type:'noul',instructions:''}],
])};
const responseWire='{"model":"reported-jev","answers":{"constructor":{"type":"choice","choice":"other","probabilities":{"constructor":0.33,"toString":0.33,"other":0.33}},"score":{"type":"score","score":1.5,"probabilities":{"0":0,"1":0.5,"2":0.5}},"boolean":{"type":"noul","noul":0.25}},"usage":{"input_tokens":0,"output_tokens":3}}';
const responseBytes=new TextEncoder().encode(responseWire);
const limits={maxBytes:responseBytes.length,maxChunkBytes:responseBytes.length,
  maxChunks:2,maxHeaderBytes:64,observedHeaders:['content-type']};
const prepare=(overrides={})=>prepareTypeSafeDecisionRequest({modelId:'jev-latest',
  baseURL:'https://fixture.invalid/v1',apiKey:'private-fixture-only',
  options:{state,questions},maxRequestBytes:4096,maxHeaderBytes:4096,maxHeaders:16,
  notify(){},...overrides});
async function until(read,kind){for(let i=0;i<40;i++){const value=read();
  if(value.kind===kind)return value;await turn();}assert.fail(`Finite native ${kind} unavailable`);}
async function release(handle){for(let i=0;i<40;i++){if(cleanupSdkPreparation(handle))return;
  await turn();}assert.fail('Original native SDK cleanup incomplete');}

test('actual native SDK captures all questions in one unchanged array-state request with zero network',async t=>{
  const ambient=globalThis.fetch;let calls=0;
  globalThis.fetch=()=>{calls++;throw Error('No ambient Provider');};
  t.after(()=>{globalThis.fetch=ambient;});
  const handle=prepare({verifyRequest:body=>{
    assert.deepEqual(JSON.parse(body),expected);return true;}});
  t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),'ready');
  const request=sdkPreparedRequest(handle);
  assert.equal(request.url,'https://fixture.invalid/v1/systemone');
  assert.equal(request.method,'POST');
  assert.deepEqual(JSON.parse(request.body),expected);
  assert.equal(Object.hasOwn(JSON.parse(request.body).questions,'constructor'),true);
  assert.equal(request.body.includes('private-fixture-only'),false);
  assert.equal(calls,0);
  assert.deepEqual(pollSdkDecode(handle),{kind:'pending'});
});

test('native fixed transport starts once and preserves actual raw answer values without generation settings',async t=>{
  let calls=0;const handle=prepare();t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),'ready');
  prepareSdkTransport(handle,{responseLimits:limits,fetch(url,init){calls++;
    assert.equal(url,'https://fixture.invalid/v1/systemone');
    assert.equal(init.redirect,'error');
    assert.equal(new Headers(init.headers).get('authorization'),'Bearer private-fixture-only');
    assert.deepEqual(JSON.parse(init.body),expected);
    return Promise.resolve(new Response(responseBytes,{headers:{'content-type':'application/json'}}));}});
  assert.equal(calls,0);startSdkTransport(handle);assert.equal(calls,1);
  assert.throws(()=>startSdkTransport(handle),{code:'SdkTransportStartRefused'});
  await until(()=>pollSdkTransport(handle),'response');
  await until(()=>pollSdkDecode(handle),'ready');
  const decoded=takeSdkDecodedResult(handle);
  assert.equal(Object.hasOwn(decoded.answers,'constructor'),true);
  assert.equal(decoded.answers.constructor.choice,'other');
  assert.deepEqual(decoded.answers.constructor.probabilities,
    Object.fromEntries([['constructor',0.33],['toString',0.33],['other',0.33]]));
  assert.equal(decoded.answers.score.score,1.5);
  assert.equal(decoded.answers.boolean.probability,0.25);
  assert.deepEqual(decoded.usage,{inputTokens:0,outputTokens:3});
  assert.deepEqual(decoded.rounding,{probabilityDecimals:2,scoreDecimals:2});
  assert.deepEqual(sdkTransportRawObservation(handle).body,responseBytes);
  assert.equal(calls,1);
  // SDK answers/rounding are observations only. Common must still validate
  // every original question/distribution/profile and native completeness.
});

test('configured native model fallback is not a provider-reported model or invented usage',async t=>{
  const wire='{"answers":{"boolean":{"type":"noul","noul":0}}}';
  const bytes=new TextEncoder().encode(wire),handle=prepare();t.after(()=>release(handle));
  await until(()=>pollSdkPreparation(handle),'ready');
  prepareSdkTransport(handle,{responseLimits:limits,
    fetch:()=>new Response(bytes,{headers:{'content-type':'application/json'}})});
  startSdkTransport(handle);await until(()=>pollSdkTransport(handle),'response');
  await until(()=>pollSdkDecode(handle),'ready');
  const decoded=takeSdkDecodedResult(handle);
  assert.equal(decoded.response.modelId,'jev-latest');
  assert.equal(Object.hasOwn(decoded.response.body,'model'),false);
  assert.deepEqual(decoded.usage,{inputTokens:undefined,outputTokens:undefined});
  assert.equal(Object.hasOwn(decoded.response.body,'usage'),false);
  assert.deepEqual(sdkTransportRawObservation(handle).body,bytes);
  // Missing other required answers does not become a Common successful call.
});

test('native SDK request byte exact fit and one short remain finite pre-send preparation',async()=>{
  const count=Buffer.byteLength(JSON.stringify(expected));
  const exact=prepare({maxRequestBytes:count});
  await until(()=>pollSdkPreparation(exact),'ready');
  assert.equal(sdkPreparedRequest(exact).requestBytes,count);await release(exact);
  const short=prepare({maxRequestBytes:count-1});
  assert.deepEqual(await until(()=>pollSdkPreparation(short),'rejected'),
    {kind:'rejected',issue:'SdkRequestBindingRefused'});await release(short);
});

test('unsupported native SDK options and question ceilings cannot create a sending plan',async()=>{
  for(const options of [{state,questions,providerOptions:{}},{state,questions,headers:{}},
    {state,questions,temperature:0.5}]){
    assert.throws(()=>prepare({options}),/InvalidTypeSafeSdkPreparation/u);
  }
  for(const question of [{type:'choice',instructions:'',criteria:Object.fromEntries(
    Array.from({length:256},(_,i)=>[`id${i}`,'']))},
    {type:'score',instructions:'',criteria:Array(11).fill('')}]){
    const handle=prepare({options:{state,questions:{question}}});
    assert.deepEqual(await until(()=>pollSdkPreparation(handle),'rejected'),
      {kind:'rejected',issue:'SdkPreparationRejected'});
    assert.equal(sdkPreparedRequest(handle),undefined);await release(handle);
  }
});

test('cancelled original native preparation cannot start and cleanup uses that same handle',async()=>{
  const handle=prepare();await until(()=>pollSdkPreparation(handle),'ready');
  let calls=0;
  prepareSdkTransport(handle,{responseLimits:limits,fetch(){calls++;assert.fail('No cancelled send');}});
  cancelSdkPreparation(handle);
  assert.throws(()=>startSdkTransport(handle),{code:'SdkTransportStartRefused'});
  await release(handle);assert.equal(calls,0);
});

test('SDK prototype-key response refusal retains exact raw without silently banning original common IDs',async t=>{
  const wire='{"answers":{"__proto__":{"type":"noul","noul":0}}}';
  const bytes=new TextEncoder().encode(wire);
  const handle=prepare({options:{state,questions:Object.fromEntries([
    ['__proto__',{type:'boolean',instructions:''}],
  ])}});t.after(()=>release(handle));let calls=0;
  await until(()=>pollSdkPreparation(handle),'ready');
  assert.equal(Object.hasOwn(JSON.parse(sdkPreparedRequest(handle).body).questions,'__proto__'),true);
  prepareSdkTransport(handle,{responseLimits:limits,fetch(){calls++;
    return new Response(bytes,{headers:{'content-type':'application/json'}});}});
  startSdkTransport(handle);await until(()=>pollSdkTransport(handle),'response');
  assert.deepEqual(await until(()=>pollSdkDecode(handle),'rejected'),
    {kind:'rejected',issue:'SdkPreparationRejected'});
  assert.deepEqual(sdkTransportRawObservation(handle).body,bytes);
  assert.equal(calls,1);
  assert.throws(()=>startSdkTransport(handle),{code:'SdkTransportStartRefused'});
  // A Common-issued exact question/option key mapping is still required in
  // the real native caller. SDK refusal must not become a language-wide ban,
  // successful answer, raw-byte loss or repair request.
});
