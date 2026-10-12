import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {setImmediate as turn} from 'node:timers/promises';
import {createAdmittedOpenAIChatPreflight} from './_internal/original-openai-chat.mjs';
const corpus=JSON.parse(readFileSync(new URL('../../portability/corpus/openai-chat.json',import.meta.url)));

// Actual pinned SDK and fixed transport; Core/persistence ports are doubles.
// This exercises the consuming preparation shape, not public funding/admission.
function fixture({abort,issueAt,retireFailure=false,foreignBinding=false}={}) {
  const request={},provider={},cursor={},entry={};
  const counts={starts:0,advances:0,retire:0,fetch:0,plans:0,generation:0,saves:0};
  const projected={_0:corpus.prompt.payload.instructions,
    _1:'{"absent":null,"amount":"9007199254740993.00","text":"é\\r\\n"}',
    _2:JSON.stringify(corpus.schema),_3:corpus.task.contract_cid,
    _4:corpus.prompt.self_cid,_5:corpus.task.output_schema_cid,_6:'fixture-chat'};
  const checked=value=>{if(value.$tag===1)return value._0;throw Error('CoreRefused');};
  const moon={
    clientProgramStartOpenAIChatProjection(p,r){assert.equal(p,provider);assert.equal(r,request);counts.starts++;return {$tag:1,_0:cursor};},
    clientProgramAdvanceOpenAIChatProjection(c){assert.equal(c,cursor);counts.advances++;
      return counts.advances===issueAt?{$tag:0,_0:'limit'}:{$tag:1,_0:counts.advances<3?undefined:projected};},
    clientProgramRetireOpenAIChatProjection(c){assert.equal(c,cursor);counts.retire++;
      if(retireFailure&&counts.retire===1)throw Error('RetirementPending');},
    clientProgramModelRequestGeneration(r){assert.equal(r,request);counts.generation++;
      return {_0:'fixture-chat',_1:0.25,_2:0.875,_3:16n,_4:-7n};},
    clientProgramModelRequestPreflight:(advance,cleanup)=>({advance,cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan(r,bytes,tokens,cost,duration,p,i,start){
      assert.equal(r,request);assert.ok(bytes>0n);counts.plans++;return {$tag:1,_0:{start}};},
    clientProgramModelPhysicalCallForRequest(e,r,poll,cancel,cleanup){assert.equal(e,entry);assert.equal(r,request);return {poll,cancel,cleanup};},
    clientProgramModelPhysicalPending:()=>({kind:'pending'}),
    clientProgramModelPhysicalUnknown:()=>({kind:'unknown'}),
    clientProgramModelPhysicalSavedChat:view=>({kind:'saved',view}),
  };
  const port=createAdmittedOpenAIChatPreflight({moon,request,admittedProvider:provider,
    taskCid:foreignBinding?'foreign':corpus.task.contract_cid,
    promptCid:corpus.prompt.self_cid,outputSchemaCid:corpus.task.output_schema_cid,
    modelSelector:'fixture-chat',projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000},
    modelId:'gpt-4.1-nano',baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',
    maxRequestBytes:4096,maxHeaderBytes:4096,maxHeaders:16,signal:abort?.signal,
    notify(){},checked,profile:{},installation:{},quantities:{tokens:16n,costUnits:0n,durationMs:500n},
    responseLimits:{maxBytes:1000,maxChunkBytes:1000,maxChunks:2,maxHeaderBytes:100,observedHeaders:[]},
    observeAt:()=> '2026-10-13T00:00:00.000Z',cleanupRaw:()=>true,
    fetch(url,init){counts.fetch++;assert.equal(url,'https://fixture.invalid/v1/chat/completions');
      const body=JSON.parse(init.body);assert.equal(body.messages[1].content,projected._1);
      assert.deepEqual(body.response_format.json_schema.schema,corpus.schema);
      return Promise.resolve(new Response('{}',{headers:{'content-type':'application/json'}}));},
    async persistRaw(call,raw){counts.saves++;return {response:{call,raw}};},
  });
  return {port,counts,entry};
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
    assert.equal(f.counts.starts,1);assert.equal(f.counts.generation,0);
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
  const moon={clientProgramStartOpenAIChatProjection(){starts++;return {$tag:1,_0:{}};},
    clientProgramAdvanceOpenAIChatProjection(){assert.fail('Invalid installation advanced');},
    clientProgramRetireOpenAIChatProjection(){assert.fail('No child exists');}};
  assert.throws(()=>createAdmittedOpenAIChatPreflight({moon,admittedProvider:{},request:{},
    projectionLimits:{maxBytes:100,maxNodes:10,maxDepth:4,maxFrames:10,maxWork:100}}),
  {message:'InvalidSdkModelPort'});
  assert.equal(starts,0);
});
