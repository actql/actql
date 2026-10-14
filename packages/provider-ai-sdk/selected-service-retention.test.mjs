import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareAdmittedOpenAIChatRequest} from './_internal/original-openai-chat.mjs';
import {pollSdkPreparation, sdkPreparedRequest, prepareSdkTransport,
  startSdkTransport, pollSdkTransport, sdkTransportRawObservation,
  pollSdkDecode, takeSdkDecodedResult, cleanupSdkPreparation}
  from './_internal/intercepted-request.mjs';

// First-M1 independent schema. Common projection/generation are explicit
// doubles; SDK normalization, intercepted verification and raw reader are real.
// Instrumentation retains trees deliberately: no bytes/GC/grant/Store proof.
const schema={type:'object',properties:{
  reason:{anyOf:[{type:'string'},{type:'null'}]},risk:{type:'string'},
},required:['reason','risk'],additionalProperties:false};
const schemaWire=JSON.stringify(schema);
const instructions='Original e\u0301\r\n',inputWire='{"text":"hello"}';
const modelId='gpt-4.1-mini-2025-04-14';
const expected={model:modelId,temperature:0,top_p:1,max_tokens:32,seed:-7,
  messages:[{role:'system',content:instructions},{role:'user',content:inputWire}],
  response_format:{type:'json_schema',json_schema:{schema,strict:true,name:'actql_output'}}};
const rawWire='{"id":null,"model":null,"object":"chat.completion",'+
  '"choices":[{"index":0,"message":{"role":"assistant",'+
  '"content":"{\\"reason\\":null,\\"risk\\":\\"low\\"}"},"finish_reason":"stop"}],'+
  '"usage":{"prompt_tokens":null,"completion_tokens":1},"unknown":{"original":"é"}}';
const rawBytes=new TextEncoder().encode(rawWire);

async function until(read,accept) {
  for(let index=0;index<100;index++) {
    const value=read();if(accept(value))return value;await turn();
  }
  assert.fail('Finite selected SDK observation did not settle');
}
function census(root) {
  const result={objects:0,arrays:0,scalars:0,fields:0,maxDepth:0};
  const visit=(value,depth)=>{
    assert.ok(depth<=8,'Independent schema depth guard');
    result.maxDepth=Math.max(result.maxDepth,depth);
    if(value===null || typeof value!=='object'){result.scalars++;return;}
    if(Array.isArray(value)){result.arrays++;for(const child of value)visit(child,depth+1);}
    else {result.objects++;for(const child of Object.values(value)){
      result.fields++;visit(child,depth+1);
    }}
  };
  visit(root,1);return result;
}
function containers(root,objects=new Set(),arrays=new Set()) {
  if(root===null || typeof root!=='object')return {objects,arrays};
  const selected=Array.isArray(root)?arrays:objects;
  if(selected.has(root))return {objects,arrays};
  selected.add(root);
  assert.ok(objects.size+arrays.size<=40,'Independent container inventory guard');
  for(const child of Object.values(root))containers(child,objects,arrays);
  return {objects,arrays};
}

test('first selected M1 schema retains four distinct constructions and retires only the raw-only SDK consumer',
  {timeout:5000},async t=>{
    const parse=JSON.parse,stringify=JSON.stringify;
    const parsedSchemas=[],parsedRequests=[],sdkRequests=[];
    const request={},provider={};let generationReads=0,handle;
    t.after(async()=>{
      JSON.parse=parse;JSON.stringify=stringify;
      if(handle!==undefined)await until(()=>cleanupSdkPreparation(handle),Boolean);
    });
    try {
      JSON.parse=function(text,...rest){
        const value=parse(text,...rest);
        if(text===schemaWire)parsedSchemas.push(value);
        if(value?.model===modelId && value.response_format)parsedRequests.push(value);
        return value;
      };
      JSON.stringify=function(value,...rest){
        if(value?.model===modelId && value.response_format)sdkRequests.push(value);
        return stringify(value,...rest);
      };
      handle=prepareAdmittedOpenAIChatRequest({moon:{
        clientProgramProjectOpenAIChatRequest(p,r){
          assert.strictEqual(p,provider);assert.strictEqual(r,request);
          return {$tag:1,_0:{_0:instructions,_1:inputWire,_2:schemaWire,
            _3:'task',_4:'prompt',_5:'schema',_6:'selected-chat'}};
        },
        clientProgramModelRequestGeneration(r){
          assert.strictEqual(r,request);generationReads++;
          return {_0:'selected-chat',_1:0,_2:1,_3:32n,_4:-7n};
        },
      },admittedProvider:provider,request,taskCid:'task',promptCid:'prompt',
      outputSchemaCid:'schema',modelSelector:'selected-chat',modelId,
      projectionLimits:{maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000},
      baseURL:'https://api.openai.com/v1',apiKey:'fixture-only-never-sent',
      maxRequestBytes:4096,maxHeaderBytes:4096,maxHeaders:16,notify(){}});
      await until(()=>pollSdkPreparation(handle),value=>value.kind!=='pending');
      assert.deepEqual(pollSdkPreparation(handle),{kind:'ready'});
    } finally {JSON.parse=parse;JSON.stringify=stringify;}
    assert.equal(generationReads,1);
    assert.equal(parsedSchemas.length,2);assert.equal(parsedRequests.length,1);
    assert.equal(sdkRequests.length,1);
    const input=parsedSchemas[0],comparison=parsedSchemas[1];
    const checked=parsedRequests[0].response_format.json_schema.schema;
    const normalized=sdkRequests[0].response_format.json_schema.schema;
    const trees=[input,normalized,checked,comparison];
    assert.equal(new Set(trees).size,4);
    for(const tree of trees){
      assert.deepEqual(tree,schema);
      // Independent counts of the closed reason/risk schema, not SDK output.
      assert.deepEqual(census(tree),{objects:6,arrays:2,scalars:7,fields:10,maxDepth:6});
    }
    assert.notStrictEqual(normalized.properties,input.properties);
    assert.notStrictEqual(normalized.properties.reason,input.properties.reason);
    assert.notStrictEqual(normalized.properties.reason.anyOf,input.properties.reason.anyOf);
    assert.strictEqual(normalized.required,input.required);
    const union={objects:new Set(),arrays:new Set()};
    for(const tree of trees)containers(tree,union.objects,union.arrays);
    assert.equal(union.objects.size,24);assert.equal(union.arrays.size,7);
    const escaped=sdkPreparedRequest(handle);
    assert.deepEqual(parse(escaped.body),expected);
    assert.ok(escaped.requestBytes<=4096);assert.ok(escaped.headerBytes<=4096);

    let sends=0,rawParses=0;
    try {
      JSON.parse=function(text,...rest){if(text===rawWire)rawParses++;return parse(text,...rest);};
      prepareSdkTransport(handle,{responseMode:'raw-only',
        responseLimits:{maxBytes:8192,maxChunkBytes:8192,maxChunks:32,
          maxHeaderBytes:16384,observedHeaders:['content-type']},
        observeAt:()=> '2026-10-15T00:00:00.000Z',fetch(){
          sends++;return new Response(rawBytes,{headers:{'content-type':'application/json'}});
        }});
      assert.equal(sends,0);startSdkTransport(handle);
      await until(()=>pollSdkTransport(handle),value=>value.kind==='response');
      assert.deepEqual(await until(()=>pollSdkDecode(handle),value=>value.kind!=='pending'),
        {kind:'retired'});
    } finally {JSON.parse=parse;}
    const raw=sdkTransportRawObservation(handle);
    assert.deepEqual(raw.body,rawBytes);assert.equal(raw.body.buffer.byteLength,8192);
    assert.equal(raw.transportComplete,true);assert.equal(raw.status,200);
    assert.equal(rawParses,0);assert.equal(sends,1);
    assert.throws(()=>takeSdkDecodedResult(handle),{code:'SdkDecodedResultUnavailable'});
    assert.throws(()=>startSdkTransport(handle),{code:'SdkTransportStartRefused'});
    await until(()=>cleanupSdkPreparation(handle),Boolean);
    // Escaped raw/request objects are not mutated by handle retirement. They
    // retain independent backing/lifetime duties, not a Store receipt or loan.
    assert.deepEqual(raw.body,rawBytes);assert.deepEqual(parse(escaped.body),expected);
    assert.throws(()=>startSdkTransport(handle),{code:'ForeignSdkPreparation'});
    t.diagnostic('Pinned SDK identity/constructor observations only; Common double, network0, Store0, bytes/grant/GC/public0');
  });
