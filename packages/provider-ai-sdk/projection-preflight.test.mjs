import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {setImmediate as turn} from 'node:timers/promises';
import {createOpenAI} from '@ai-sdk/openai';
import {sdkProvider, verifyRequest} from './_internal/openai-chat.mjs';
import {createAdmittedRegisteredSdkPreflight} from './_internal/model-port.mjs';
const corpus=JSON.parse(readFileSync(new URL('../../portability/corpus/openai-chat.json',import.meta.url)));

// Actual pinned SDK and fixed transport; Core/persistence ports are doubles.
// This exercises the consuming preparation shape, not public funding/admission.
function fixture({abort,issueAt,retireFailure=false,renderMismatch=false,foreignBinding=false,deferredRaw=false,
  rawCleanup=()=>true,saveRaw,projectionChange={},generationChange={},
  projectionLimits={maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000}}={}) {
  const request={},cursor={},entry={},admission={};
  const providerOptions=Object.freeze({openai:Object.freeze({})});
  const route={selector:'fixture-chat',modelId:'gpt-4.1-nano',apiMode:'chat_completions',
    endpoint:'https://fixture.invalid/v1/chat/completions'};
  const registeredSdk={route,sdkProvider,providerOptions,
    sdkPackage:'@ai-sdk/openai',sdkVersion:'4.0.91',lockArtifactCid:'lock',adapterArtifactCid:'adapter',
    createLanguageModel:fetch=>createOpenAI({baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',fetch}).chat(route.modelId),
    verifyRequest(body,options) {counts.verifications++;wire=body;return verifyRequest(body,options,
      renderMismatch ? {...route,modelId:'foreign-model'} : route,providerOptions);}};
  const installation={endpoint:route.endpoint,build_artifact_cid:'adapter',
    sdk:{package_name:registeredSdk.sdkPackage,version:registeredSdk.sdkVersion,interface:'v4',lock_artifact_cid:'lock'}};
  const profile={};

  let wire;
  const counts={starts:0,advances:0,retire:0,verifications:0,fetch:0,plans:0,generation:0,saves:0};
  let bindRaw;
  const persist=async(call,raw)=>{counts.saves++;return saveRaw===undefined?
    {receipt:{call,raw},bytes:raw.body}:saveRaw(call,raw);};
  persist.cleanup=rawCleanup;
  const projected={_0:corpus.prompt.payload.instructions,
    _1:'{"absent":null,"amount":"9007199254740993.00","text":"é\\r\\n"}',
    _2:JSON.stringify(corpus.schema),_3:corpus.task.contract_cid,
    _4:corpus.prompt.self_cid,_5:corpus.task.output_schema_cid,_6:'fixture-chat',...projectionChange};
  const generation={_0:'fixture-chat',_1:0.25,_2:0.875,_3:16n,_4:-7n,...generationChange};
  const checked=value=>{if(value.$tag===1)return value._0;throw Error('CoreRefused');};
  const moon={
    clientProgramAdmittedStructuredSdkRouteMatches(...args){
      assert.deepEqual(args,[admission,route.selector,route.modelId,route.apiMode,route.endpoint]);return true;},
    clientProgramStartAdmittedStructuredSdkProjection(a,r,p,i,...bounds){
      assert.strictEqual(a,admission);assert.strictEqual(r,request);
      assert.strictEqual(p,profile);assert.strictEqual(i,installation);
      assert.deepEqual(bounds,[10000,1000,40,100,10000]);counts.starts++;return {$tag:1,_0:cursor};},
    clientProgramAdvanceOpenAIChatProjection(c){assert.equal(c,cursor);counts.advances++;
      return counts.advances===issueAt?{$tag:0,_0:'limit'}:{$tag:1,_0:counts.advances<3?undefined:projected};},
    clientProgramRetireOpenAIChatProjection(c){assert.equal(c,cursor);counts.retire++;
      if(retireFailure&&counts.retire===1)throw Error('RetirementPending');},
    clientProgramModelRequestGeneration(r){assert.equal(r,request);counts.generation++;
      return generationChange===null?undefined:generation;},
    clientProgramModelRequestPreflight:(advance,cleanup)=>({advance,cleanup}),
    clientProgramModelStructuredRequestPlan(a,r,bytes,tokens,cost,duration,p,i,start){
      assert.strictEqual(a,admission);assert.equal(r,request);assert.ok(bytes>0n);counts.plans++;return {$tag:1,_0:{start}};},
    clientProgramModelPhysicalCallForRequest(e,r,poll,cancel,cleanup){assert.equal(e,entry);assert.equal(r,request);return {poll,cancel,cleanup};},
    clientProgramModelPhysicalPending:()=>({kind:'pending'}),
    clientProgramModelPhysicalUnknown:()=>({kind:'unknown'}),
    clientProgramModelPhysicalSavedStructured:(_call,receipt)=>({$tag:1,_0:{kind:'saved',view:receipt}}),
  };
  const port=createAdmittedRegisteredSdkPreflight({moon,request,admission,registeredSdk,
    taskCid:foreignBinding?'foreign':corpus.task.contract_cid,
    promptCid:corpus.prompt.self_cid,outputSchemaCid:corpus.task.output_schema_cid,
    modelSelector:'fixture-chat',projectionLimits,
    maxRequestBytes:4096,maxHeaderBytes:4096,maxHeaders:16,signal:abort?.signal,
    notify(){},checked,profile,installation,quantities:{tokens:16n,costUnits:0n,durationMs:500n},
    responseLimits:{maxBytes:1000,maxChunkBytes:1000,maxChunks:2,maxHeaderBytes:100,observedHeaders:[]},
    observeAt:()=> '2026-10-13T00:00:00.000Z',
    fetch(url,init){counts.fetch++;assert.equal(url,'https://fixture.invalid/v1/chat/completions');
      const body=JSON.parse(init.body);assert.equal(body.messages[1].content,projected._1);
      assert.deepEqual(body.response_format.json_schema.schema,JSON.parse(projected._2));
      return Promise.resolve(new Response('{}',{headers:{'content-type':'application/json'}}));},
    ...(deferredRaw?{rawCaptureBinder(callback){assert.equal(bindRaw,undefined);bindRaw=callback;}}
      :{persistRaw:persist,cleanupRaw:rawCleanup}),
  });
  return {port,counts,entry,persist,projected,generation,wire:()=>wire,bindRaw:(registration,persistence=persist)=>bindRaw(registration,persistence)};
}
async function eventually(read,predicate){for(let i=0;i<50;i++){const value=read();if(predicate(value))return value;await turn();}assert.fail('Finite preflight did not settle');}

test('preflight polls one Common child transition and starts one fixed SDK/request only after projection',async()=>{
  const f=fixture();
  assert.equal(f.counts.starts,0);
  assert.deepEqual(f.port.preflight.advance(),{_0:false,_1:undefined});
  assert.equal(f.counts.starts,1);assert.equal(f.counts.advances,0);
  for(let i=1;i<=2;i++){
    assert.deepEqual(f.port.preflight.advance(),{_0:false,_1:undefined});
    assert.equal(f.counts.advances,i);assert.equal(f.counts.generation,0);assert.equal(f.counts.fetch,0);
  }
  assert.deepEqual(f.port.preflight.advance(),{_0:false,_1:undefined});
  assert.equal(f.counts.advances,3);assert.equal(f.counts.generation,1);assert.equal(f.counts.retire,1);
  const {_1:plan}=await eventually(()=>f.port.preflight.advance(),v=>v._0);
  assert.ok(plan);assert.equal(f.counts.fetch,0);
  assert.deepEqual(JSON.parse(f.wire()),{
    model:'gpt-4.1-nano',temperature:0.25,top_p:0.875,max_tokens:16,seed:-7,
    messages:[{role:'system',content:f.projected._0},{role:'user',content:f.projected._1}],
    response_format:{type:'json_schema',json_schema:{schema:corpus.schema,strict:true,name:'actql_output'}},
  });
  assert.equal(f.port.preflight.advance()._1,plan);
  assert.equal(f.counts.advances,3);assert.equal(f.counts.generation,1);
  const call=plan.start(f.entry);assert.equal(f.counts.fetch,1);
  assert.equal(plan.start(f.entry),undefined);
  await eventually(()=>call.poll(),v=>v.kind==='saved');
  assert.equal(f.counts.saves,1);
  await eventually(()=>f.port.preflight.cleanup(),Boolean);
  assert.deepEqual(f.port.preflight.advance(),{_0:true,_1:undefined});
  assert.equal(f.counts.fetch,1);
});

test('cancelled original child creates no SDK request and cleanup retires the same child',()=>{
  const abort=new AbortController(),f=fixture({abort});
  f.port.preflight.advance();abort.abort();
  assert.deepEqual(f.port.preflight.advance(),{_0:true,_1:undefined});
  assert.equal(f.counts.advances,0);assert.equal(f.counts.generation,0);
  assert.equal(f.port.preflight.cleanup(),true);assert.equal(f.counts.retire,1);
  assert.equal(f.port.preflight.cleanup(),true);assert.equal(f.counts.retire,1);
  assert.equal(f.counts.fetch,0);
});

test('child failure and foreign binding cannot prepare SDK or silently restart projection',()=>{
  for(const options of [{issueAt:2},{foreignBinding:true}]){
    const f=fixture(options);
    for(let i=0;i<4;i++)f.port.preflight.advance();
    assert.deepEqual(f.port.preflight.advance(),{_0:true,_1:undefined});
    assert.equal(f.counts.starts,1);assert.equal(f.counts.verifications,0);
    assert.equal(f.counts.fetch,0);assert.equal(f.counts.plans,0);
    assert.equal(f.port.preflight.cleanup(),true);
  }
});

test('retirement failure before SDK allocation keeps the same retry child and no orphan Promise',()=>{
  const f=fixture({retireFailure:true});
  f.port.preflight.advance();f.port.preflight.advance();f.port.preflight.advance();
  assert.deepEqual(f.port.preflight.advance(),{_0:true,_1:undefined});
  assert.equal(f.counts.retire,1);assert.equal(f.counts.generation,0);assert.equal(f.counts.fetch,0);
  assert.equal(f.port.preflight.cleanup(),true);assert.equal(f.counts.retire,2);
  assert.equal(f.port.preflight.cleanup(),true);assert.equal(f.counts.retire,2);
});

test('invalid physical installation refuses before allocating a Common child',()=>{
  let starts=0;
  const moon={clientProgramStartAdmittedStructuredSdkProjection(){starts++;return {$tag:1,_0:{}};}};
  assert.throws(()=>createAdmittedRegisteredSdkPreflight({moon,request:{},
    projectionLimits:{maxBytes:100,maxNodes:10,maxDepth:4,maxFrames:10,maxWork:100}}),
  {message:'RegisteredSdkPhysicalInstallationUnavailable'});
  assert.equal(starts,0);
});

test('installation bounds are snapshotted before lazy child allocation',()=>{
  const projectionLimits={maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000};
  const f=fixture({projectionLimits});
  projectionLimits.maxBytes=2_147_483_647;projectionLimits.maxWork=0;
  assert.deepEqual(f.port.preflight.advance(),{_0:false,_1:undefined});
  assert.equal(f.counts.starts,1);assert.equal(f.counts.generation,0);
  assert.equal(f.port.preflight.cleanup(),true);
});

test('original deferred raw Store binds before Entry and cleanup retries the same responsibility',async()=>{
  let clean=false;
  const f=fixture({deferredRaw:true,rawCleanup:()=>clean});
  const {_1:plan}=await eventually(()=>f.port.preflight.advance(),v=>v._0);
  assert.equal(f.counts.fetch,0);
  const registration={};
  f.bindRaw(registration);
  assert.throws(()=>f.bindRaw(registration),{message:'OriginalSdkRawBindingUnavailable'});
  const call=plan.start(f.entry);
  assert.equal(f.counts.fetch,1);
  await eventually(()=>call.poll(),v=>v.kind==='saved');
  assert.equal(f.port.preflight.cleanup(),false);
  assert.equal(plan.start(f.entry),undefined);
  clean=true;
  await eventually(()=>f.port.preflight.cleanup(),Boolean);
  assert.equal(f.counts.saves,1);
  assert.equal(f.counts.fetch,1);
});

test('late missing raw binding at an entered attempt cannot start transport or recreate its plan',async()=>{
  const f=fixture({deferredRaw:true});
  const {_1:plan}=await eventually(()=>f.port.preflight.advance(),v=>v._0);
  assert.equal(plan.start(f.entry),undefined);
  assert.equal(f.counts.fetch,0);
  f.bindRaw({});
  assert.equal(plan.start(f.entry),undefined,'late custody is not a restored send gate');
  assert.equal(f.counts.fetch,0);
  // The actual Owner keeps this Entry Unknown. Cleanup, not re-entry, follows.
  await eventually(()=>f.port.preflight.cleanup(),Boolean);
  assert.throws(()=>f.bindRaw({}),{message:'OriginalSdkRawBindingUnavailable'});
  assert.equal(plan.start(f.entry),undefined);
  assert.equal(f.counts.plans,1);
});

test('unresolved raw save keeps the original SDK port pending through cancellation',async()=>{
  let resolve;
  const saving=new Promise(r=>{resolve=r;});
  const abort=new AbortController();
  const f=fixture({abort,deferredRaw:true,saveRaw:()=>saving});
  const {_1:plan}=await eventually(()=>f.port.preflight.advance(),v=>v._0);
  f.bindRaw({});
  const call=plan.start(f.entry);
  await eventually(()=>call.poll(),()=>f.counts.saves===1);
  abort.abort();
  assert.equal(f.port.preflight.cleanup(),false);
  assert.equal(plan.start(f.entry),undefined);
  resolve({receipt:{original:'saved raw double'},bytes:new TextEncoder().encode('{}')});
  await eventually(()=>call.poll(),v=>v.kind==='unknown');
  await eventually(()=>f.port.preflight.cleanup(),Boolean);
  assert.equal(f.counts.fetch,1);
});

test('registered request mismatch retires the child and refuses the Plan before Entry',async()=>{
  const f=fixture({renderMismatch:true});
  const {_1:plan}=await eventually(()=>f.port.preflight.advance(),v=>v._0);
  assert.equal(plan,undefined);
  assert.equal(f.counts.generation,1);assert.equal(f.counts.verifications,1);
  assert.equal(f.counts.fetch,0);assert.equal(f.counts.plans,0);
  assert.equal(f.counts.retire,1);
  await eventually(()=>f.port.preflight.cleanup(),Boolean);
  assert.equal(f.counts.retire,1);
});

test('foreign Task, prompt, schema or selector and missing generation refuse before the SDK',async()=>{
  const variants=['_3','_4','_5','_6'].map(field=>({projectionChange:{[field]:'foreign'}}));
  variants.push({generationChange:null},{generationChange:{_0:'foreign'}});
  for(const options of variants){
    const f=fixture(options);
    const {_1:plan}=await eventually(()=>f.port.preflight.advance(),value=>value._0);
    assert.equal(plan,undefined);
    assert.equal(f.counts.retire,1);
    assert.equal(f.counts.verifications,0);
    assert.equal(f.counts.fetch,0);
    assert.equal(f.counts.plans,0);
    await eventually(()=>f.port.preflight.cleanup(),Boolean);
  }
});

test('original tuple mutation cannot replace the selected SDK request or its escaped schema',async()=>{
  const schema=JSON.parse(String.raw`{"additionalProperties":false,"properties":{"__proto__":{"type":"boolean"},"quote\"":{"type":"string"},"é":{"items":{"anyOf":[{"type":"number"},{"type":"null"}]},"type":"array"}},"required":["__proto__","quote\"","é"],"type":"object"}`);
  const f=fixture({projectionChange:{_2:JSON.stringify(schema)}});
  const expected={system:f.projected._0,user:f.projected._1,temperature:f.generation._1};
  for(let n=0;n<4;n++)assert.equal(f.port.preflight.advance()._0,false);
  f.projected._0='foreign';f.projected._1='foreign';f.projected._2='{}';f.generation._1=1;
  const {_1:plan}=await eventually(()=>f.port.preflight.advance(),value=>value._0);
  assert.ok(plan);
  const body=JSON.parse(f.wire());
  assert.deepEqual(body.messages,[{role:'system',content:expected.system},{role:'user',content:expected.user}]);
  assert.equal(body.temperature,expected.temperature);
  assert.deepEqual(body.response_format.json_schema.schema,schema);
  assert.equal(f.counts.fetch,0);
  await eventually(()=>f.port.preflight.cleanup(),Boolean);
});
