import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {setImmediate as turn} from 'node:timers/promises';
import {createInstalledOpenAIChatRegistration} from './_internal/installed-openai-chat.mjs';
import {installModelProviders} from '../../adapters/host-node/installed-model.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';
import {createInferIoNotification} from '../../adapters/host-node/infer-io-notification.mjs';
import {createInstalledUndiciOpenAIChatRegistration} from './index.mjs';
import {createServer} from 'node:http';
import {once} from 'node:events';

const corpus=JSON.parse(readFileSync(new URL('../../portability/corpus/openai-chat.json',import.meta.url)));
const cid=c=>`sha256:${c.repeat(64)}`;
const physicalAcquisitionLimits={maxPlaintextBytes:65536,maxBorrowedBackingBytes:131072,maxReads:64};
function configuration() {
  // Trusted-selection/profile/Core ports are explicit doubles. Their values
  // are not a normal numerical profile, installation grant or public Run.
  const profile={};
  const sdk=Object.freeze({package_name:'@ai-sdk/openai',version:'4.0.91',interface:'v4',lock_artifact_cid:cid('a')});
  const installation=Object.freeze({sdk,endpoint:'https://fixture.invalid/v1/chat/completions',
    http_method:'POST',streaming:false,completion_basis:'generation_finish'});
  const rawCaptureSelection=Object.freeze({profile,installation,probability:undefined,
    retention:{},metadata:{},clock:{},data:{},selectedAt:'selection',availableUntil:'availability',
    deleteBy:'delete',extensionCeilingAt:'ceiling',metadataDeleteBy:'metadata',selectionAvailable:()=>true});
  const nodeInstallation=Object.freeze({installation,probability:undefined,runtimeArtifactCid:cid('b'),
    layoutArtifactCid:cid('c'),layout:Object.freeze({response_profile:profile,
      runtime_artifact_cid:cid('b'),layout_artifact_cid:cid('c'),program_definition_cid:cid('d'),
      parameter_values_cid:cid('e'),barrier_cid:cid('f'),prepared_rows:1n,
      retained_bytes:7000n,execution_bytes:3000n})});
  const originalReadInstallation=Object.freeze({nodeInstallation,
    bootstrap:Object.freeze({bootstrapRetainedBytes:20n,bootstrapExecutionBytes:10n,
      maxReservations:8,maxHoldings:8,maxDelegations:8}),
    modelRetainedBytes:100n,modelExecutionBytes:10n});
  const bindingOriginals=Object.freeze(Object.fromEntries(Object.entries(providerBindingOriginals('models/fixture'))
    .map(([name,value])=>[name,Object.freeze(value)])));
  return {providerId:'models/fixture',modelSelector:'fixture-chat',modelId:'gpt-4.1-nano',
    baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',taskCid:corpus.task.contract_cid,
    promptCid:corpus.prompt.self_cid,outputSchemaCid:corpus.task.output_schema_cid,
    promptPayloadWire:JSON.stringify(corpus.prompt.payload),originalReadInstallation,rawCaptureSelection,bindingOriginals,
    quantityCapacity:Object.freeze({limits:Object.freeze({tokens:16n,costUnits:0n,durationMs:500n}),
      perAttempt:Object.freeze({tokens:16n,costUnits:0n,durationMs:500n})}),
    projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000},
    requestLimits:{maxBytes:4096,maxHeaderBytes:4096,maxHeaders:16},
    responseLimits:{maxBytes:1024,maxChunkBytes:1024,maxChunks:4,maxHeaderBytes:128,observedHeaders:['content-type']},
    fetch:()=>assert.fail('No ambient dispatch'),observeAt:()=> '2026-10-13T00:00:00.000Z',observeEgress:()=>({})};
}

function runtime(config) {
  const request={},provider={},entry={},cursor={};
  const counts={installs:0,starts:0,steps:0,retired:0,generation:0,fetch:0,saves:0};
  const wire='{"decimal":"9007199254740993.00","text":"é\\r\\n"}';
  const moon={
    clientProgramInstallAsyncModelProvider(id){assert.equal(id,config.providerId);counts.installs++;return {};},
    clientProgramStartOpenAIChatProjection(p,r,...limits){assert.equal(p,provider);assert.equal(r,request);
      assert.deepEqual(limits,[10000,1000,40,100,10000]);counts.starts++;return {$tag:1,_0:cursor};},
    clientProgramAdvanceOpenAIChatProjection(c){assert.equal(c,cursor);counts.steps++;
      return {$tag:1,_0:counts.steps<2?undefined:{_0:corpus.prompt.payload.instructions,_1:wire,
        _2:JSON.stringify(corpus.schema),_3:corpus.task.contract_cid,_4:corpus.prompt.self_cid,
        _5:corpus.task.output_schema_cid,_6:'fixture-chat'}};},
    clientProgramRetireOpenAIChatProjection(c){assert.equal(c,cursor);counts.retired++;},
    clientProgramModelRequestGeneration(r){assert.equal(r,request);counts.generation++;
      return {_0:'fixture-chat',_1:0.25,_2:0.875,_3:16n,_4:undefined};},
    clientProgramModelRequestPreflight:(advance,cleanup)=>({advance,cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan(r,bytes,tokens,cost,duration,profile,installation,start){
      assert.equal(r,request);assert.equal(profile,config.rawCaptureSelection.profile);
      assert.equal(installation,config.rawCaptureSelection.installation);assert.ok(bytes>0n&&bytes<=4096n);
      assert.deepEqual([tokens,cost,duration],[16n,0n,500n]);return {$tag:1,_0:{start}};},
    clientProgramModelPhysicalCallForRequest(e,r,poll,cancel,cleanup){assert.equal(e,entry);assert.equal(r,request);return {poll,cancel,cleanup};},
    clientProgramModelPhysicalPending:()=>({kind:'pending'}),
    clientProgramModelPhysicalUnknown:()=>({kind:'unknown'}),
    clientProgramModelPhysicalSavedChat:response=>({kind:'saved',response}),
  };
  config.fetch=(url,init)=>{counts.fetch++;assert.equal(url,'https://fixture.invalid/v1/chat/completions');
    assert.equal(JSON.parse(init.body).messages[1].content,wire);
    assert.equal(init.headers.find(([name])=>name==='authorization')[1],'Bearer fixture-only');
    return Promise.resolve(new Response('{}',{headers:{'content-type':'application/json'}}));};
  return {moon,request,provider,entry,counts};
}
async function until(read,predicate){for(let i=0;i<50;i++){const v=read();if(predicate(v))return v;await turn();}assert.fail('Finite private consumer did not settle');}

test('explicit Undici facade reaches the existing SDK/async port and real loopback only after start',
  {timeout:5000},async t=>{
    const calls=[];
    const server=createServer(async(request,response)=>{
      const chunks=[];for await(const chunk of request)chunks.push(chunk);
      calls.push({path:request.url,body:Buffer.concat(chunks).toString('utf8')});
      response.setHeader('content-type','application/json');response.end('{}');
    });
    server.listen(0,'127.0.0.1');await once(server,'listening');
    let preflight;
    t.after(async()=>{
      try{if(preflight!==undefined)await until(()=>preflight.cleanup(),Boolean);}
      finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
    });
    const config=configuration();
    config.baseURL=`http://127.0.0.1:${server.address().port}/v1`;
    config.responseLimits={...config.responseLimits,maxHeaderBytes:1024};
    config.rawCaptureSelection=Object.freeze({...config.rawCaptureSelection,
      installation:Object.freeze({...config.rawCaptureSelection.installation,
        endpoint:config.baseURL+'/chat/completions'})});
    config.originalReadInstallation=Object.freeze({...config.originalReadInstallation,
      nodeInstallation:Object.freeze({...config.originalReadInstallation.nodeInstallation,
        installation:config.rawCaptureSelection.installation})});
    const f=runtime(config); // Core/installation/nominal raw binding are doubles.
    const {fetch:unused,...selected}=config;void unused;
    const register=createInstalledUndiciOpenAIChatRegistration({...selected,physicalAcquisitionLimits});
    const installed=installModelProviders(f.moon,register).get(config.providerId);
    let bind;
    preflight=installed.physicalPreflight(f.request,createInferIoNotification(),
      callback=>{bind=callback;},f.provider);
    const {_1:plan}=await until(()=>preflight.advance(),value=>value._0);
    assert.ok(plan);assert.equal(calls.length,0);assert.equal(f.counts.fetch,0);
    let savedRaw;
    const persistence=async(call,raw)=>{savedRaw=raw;f.counts.saves++;return {response:{call,raw}};};
    persistence.cleanup=()=>true;
    bind({},persistence);
    const call=plan.start(f.entry);
    await until(()=>call.poll(),value=>value.kind==='saved');
    await until(()=>preflight.cleanup(),Boolean);
    assert.equal(calls.length,1);assert.equal(calls[0].path,'/v1/chat/completions');
    const sent=JSON.parse(calls[0].body);
    assert.equal(sent.model,'gpt-4.1-nano');
    assert.equal(sent.messages[1].content,'{"decimal":"9007199254740993.00","text":"é\\r\\n"}');
    assert.equal(savedRaw.transportComplete,true);
    assert.equal(Buffer.from(savedRaw.body).toString(),'{}');
    assert.equal(f.counts.fetch,0,'The separately supplied generic primitive was not used');
    assert.equal(f.counts.saves,1);assert.equal(f.counts.generation,1);
    assert.equal(plan.start(f.entry),undefined);
    t.diagnostic('Actual public package entry/pinned SDK/loopback; Core/Store/funding doubles, public Run0');
  });

test('explicit selected route refuses an extra fetch rather than accepting fallback or override',()=>{
  const config=configuration();
  assert.throws(()=>createInstalledUndiciOpenAIChatRegistration(config),
    {code:'InvalidInstalledOpenAIChatConfiguration'});
  const {fetch:unused,...selected}=config;void unused;
  assert.throws(()=>createInstalledOpenAIChatRegistration(selected),
    {code:'InvalidInstalledOpenAIChatConfiguration'});
});

test('explicit physical route cannot replace a missing original installation or mismatched profile',()=>{
  const {fetch:unused,...selected}=configuration();void unused;
  assert.throws(()=>createInstalledUndiciOpenAIChatRegistration({...selected,physicalAcquisitionLimits,
    originalReadInstallation:undefined}),{code:'OpenAIOriginalInstallationUnavailable'});
  assert.throws(()=>createInstalledUndiciOpenAIChatRegistration({...selected,physicalAcquisitionLimits,
    rawCaptureSelection:Object.freeze({...selected.rawCaptureSelection,profile:{}})}),
    {code:'OpenAIOriginalInstallationMismatch'});
});

test('explicit route retains inspected original DATA without invoking Proxy get or secret accessors',()=>{
  const config=configuration(),f=runtime(config);
  const {fetch:unused,...selected}=config;void unused;
  let gets=0;
  const supplied=new Proxy({...selected,physicalAcquisitionLimits},{get(){gets++;throw Error('LateReadForbidden');}});
  const entry=createInstalledUndiciOpenAIChatRegistration(supplied)(f.moon)[0];
  assert.equal(entry.providerId,selected.providerId);assert.equal(gets,0);
  const secret={...selected};Object.defineProperty(secret,'apiKey',{
    enumerable:true,get(){gets++;return 'not-read';}});
  assert.throws(()=>createInstalledUndiciOpenAIChatRegistration(secret),
    {code:'InvalidInstalledOpenAIChatConfiguration'});
  assert.equal(gets,0);assert.equal(f.counts.starts,0);assert.equal(f.counts.fetch,0);
});

test('private facade returns the existing exclusive async registration with zero construction I/O',()=>{
  const config=configuration(),f=runtime(config);
  const register=createInstalledOpenAIChatRegistration(config);
  const raw=register(f.moon)[0];
  assert.equal(Object.hasOwn(raw,'invoke'),false);
  assert.equal(raw.entryPersistence,'async');
  assert.equal(raw.rawCaptureSelection,config.rawCaptureSelection);
  const installed=installModelProviders(f.moon,register).get(config.providerId);
  assert.equal(installed.provider!==undefined,true);
  assert.equal(installed.originalReadInstallation.nodeInstallation.layout.response_profile,
    config.rawCaptureSelection.profile);
  assert.equal(installed.validatePrompt(config.taskCid,config.modelSelector,config.promptPayloadWire),true);
  for(const args of [[cid('a'),config.modelSelector,config.promptPayloadWire],
    [config.taskCid,'foreign',config.promptPayloadWire],
    [config.taskCid,config.modelSelector,config.promptPayloadWire+' ']]) {
    assert.equal(installed.validatePrompt(...args),false);
  }
  assert.deepEqual(f.counts,{installs:1,starts:0,steps:0,retired:0,generation:0,fetch:0,saves:0});
});

test('facade preserves original selectors bounds and fixed SDK transport across caller mutation',async()=>{
  const config=configuration(),f=runtime(config),register=createInstalledOpenAIChatRegistration(config);
  config.modelId='replacement';config.apiKey='replacement';config.baseURL='https://other.invalid';
  config.projectionLimits.maxWork=0;config.requestLimits.maxBytes=1;
  config.responseLimits.observedHeaders.push('replacement');
  const installed=installModelProviders(f.moon,register).get('models/fixture');
  let bind;
  const preflight=installed.physicalPreflight(f.request,createInferIoNotification(),
    callback=>{assert.equal(bind,undefined);bind=callback;},f.provider);
  const {_1:plan}=await until(()=>preflight.advance(),v=>v._0);
  assert.equal(f.counts.fetch,0);
  const persistence=async(call,raw)=>{f.counts.saves++;return {response:{call,raw}};};
  persistence.cleanup=()=>true;
  // Binding/Entry are doubles here; actual Host nominal port matching belongs
  // to the original-operation raw Store fixture, not this installation test.
  bind({},persistence);
  const call=plan.start(f.entry);
  await until(()=>call.poll(),v=>v.kind==='saved');
  await until(()=>preflight.cleanup(),Boolean);
  assert.equal(f.counts.starts,1);assert.equal(f.counts.generation,1);
  assert.equal(f.counts.fetch,1);assert.equal(f.counts.saves,1);assert.equal(f.counts.retired,1);
});

test('missing original supplier refuses before installing an async Provider',()=>{
  for(const originalReadInstallation of [undefined,null,{},Object.freeze({})]) {
    const config={...configuration(),originalReadInstallation};
    assert.throws(()=>createInstalledOpenAIChatRegistration(config),{code:'OpenAIOriginalInstallationUnavailable'});
  }
});

test('wrong physical SDK endpoint profile or copied opaque profile cannot select this builder',()=>{
  const base=configuration();
  for(const replacement of [{probability:{}},
    {profile:{...base.rawCaptureSelection.profile}},
    {installation:Object.freeze({...base.rawCaptureSelection.installation,endpoint:'https://foreign.invalid'})},
    {installation:Object.freeze({...base.rawCaptureSelection.installation,sdk:Object.freeze({
      ...base.rawCaptureSelection.installation.sdk,version:'unsupported'})})}]) {
    const config={...base,rawCaptureSelection:Object.freeze({...base.rawCaptureSelection,...replacement})};
    assert.throws(()=>createInstalledOpenAIChatRegistration(config),{code:'OpenAIOriginalInstallationMismatch'});
  }
});

test('missing original notifier binder or admitted Provider refuses before child or SDK construction',()=>{
  const config=configuration(),f=runtime(config),entry=createInstalledOpenAIChatRegistration(config)(f.moon)[0];
  for(const args of [[f.request,undefined,()=>{},f.provider],
    [f.request,createInferIoNotification(),undefined,f.provider],
    [f.request,createInferIoNotification(),()=>{},undefined]]) {
    assert.throws(()=>entry.physicalPreflight(...args),{code:'OpenAIOriginalPhysicalContextUnavailable'});
  }
  assert.equal(f.counts.starts,0);assert.equal(f.counts.generation,0);assert.equal(f.counts.fetch,0);
});

test('installation getter extra input and unavailable runtime do not install or dispatch',()=>{
  let getters=0;
  const config=configuration();Object.defineProperty(config,'apiKey',{enumerable:true,get(){getters++;return 'secret';}});
  assert.throws(()=>createInstalledOpenAIChatRegistration(config),{code:'InvalidInstalledOpenAIChatConfiguration'});
  assert.equal(getters,0);
  assert.throws(()=>createInstalledOpenAIChatRegistration({...configuration(),endpoint:'https://packet.invalid'}),
    {code:'InvalidInstalledOpenAIChatConfiguration'});
  const register=createInstalledOpenAIChatRegistration(configuration());
  assert.throws(()=>register({}),{code:'OpenAIOriginalRuntimeUnavailable'});
});

test('each missing consuming runtime hook rejects registration rather than failing after preparation',()=>{
  for(const hook of ['clientProgramStartOpenAIChatProjection','clientProgramAdvanceOpenAIChatProjection',
    'clientProgramRetireOpenAIChatProjection','clientProgramInstallAsyncModelProvider',
    'clientProgramModelRequestGeneration','clientProgramModelRequestPreflight',
    'clientProgramModelAsyncPhysicalRequestPlan','clientProgramModelPhysicalCallForRequest',
    'clientProgramModelPhysicalPending','clientProgramModelPhysicalUnknown','clientProgramModelPhysicalSavedChat']) {
    const config=configuration(),f=runtime(config),register=createInstalledOpenAIChatRegistration(config);
    delete f.moon[hook];
    assert.throws(()=>installModelProviders(f.moon,register),{code:'OpenAIOriginalRuntimeUnavailable'},hook);
    assert.equal(f.counts.installs,0);assert.equal(f.counts.starts,0);assert.equal(f.counts.fetch,0);
  }
});

test('facade retains inspected top-level DATA without Proxy property reads',()=>{
  const config=configuration(),f=runtime(config);let reads=0;
  const supplied=new Proxy(config,{get(target,name){reads++;return Reflect.get(target,name);}});
  const entry=createInstalledOpenAIChatRegistration(supplied)(f.moon)[0];
  assert.equal(reads,0,'validated descriptor DATA must not invoke later property callbacks');
  assert.equal(entry.providerId,config.providerId);
  assert.equal(entry.rawCaptureSelection,config.rawCaptureSelection);
  assert.equal(f.counts.fetch,0);assert.equal(f.counts.starts,0);
});

test('facade snapshots original projection and request DATA before Proxy substitution',()=>{
  const config=configuration(),f=runtime(config);let reads=0;
  config.projectionLimits=new Proxy(config.projectionLimits,{get(){reads++;return -1;}});
  config.requestLimits=new Proxy(config.requestLimits,{get(){reads++;return -1;}});
  const entry=createInstalledOpenAIChatRegistration(config)(f.moon)[0];
  const preflight=entry.physicalPreflight(f.request,createInferIoNotification(),()=>{},f.provider);
  assert.deepEqual(preflight.advance(),{_0:false,_1:undefined});
  assert.equal(reads,0,'the exact inspected values, not later get results, reach Common');
  assert.equal(f.counts.starts,1);assert.equal(f.counts.fetch,0);
  assert.equal(preflight.cleanup(),true);
});

test('facade refuses symbol and nonenumerable extra DATA before registration',()=>{
  for(const add of [value=>{value[Symbol('extra')]='not-admitted';},
    value=>{Object.defineProperty(value,'extra',{value:'not-admitted'});}]) {
    const config=configuration(),f=runtime(config);add(config);
    assert.throws(()=>createInstalledOpenAIChatRegistration(config),
      {code:'InvalidInstalledOpenAIChatConfiguration'});
    assert.equal(f.counts.installs,0);assert.equal(f.counts.fetch,0);
  }
});


test('facade refuses a combined projection key before registration',()=>{
  const config=configuration(),f=runtime(config);
  config.projectionLimits={'maxBytes,maxDepth':10000,maxFrames:100,maxNodes:1000,maxWork:10000};
  assert.throws(()=>createInstalledOpenAIChatRegistration(config),
    {code:'InvalidInstalledOpenAIChatProjection'});
  assert.equal(f.counts.installs,0);assert.equal(f.counts.starts,0);assert.equal(f.counts.fetch,0);
});

test('facade refuses a combined request key before registration',()=>{
  const config=configuration(),f=runtime(config);
  config.requestLimits={'maxBytes,maxHeaderBytes':4096,maxHeaders:16};
  assert.throws(()=>createInstalledOpenAIChatRegistration(config),
    {code:'InvalidInstalledOpenAIChatRequestLimits'});
  assert.equal(f.counts.installs,0);assert.equal(f.counts.starts,0);assert.equal(f.counts.fetch,0);
});
