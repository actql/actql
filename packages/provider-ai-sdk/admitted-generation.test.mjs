import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {readFileSync} from 'node:fs';
import {prepareAdmittedOpenAIChatRequest} from './_internal/original-openai-chat.mjs';
import {pollSdkPreparation,sdkPreparedRequest,cleanupSdkPreparation} from './_internal/intercepted-request.mjs';

// SDK construction tests use a Common boundary double. Actual Common reader
// and binding are exercised separately; this is not a funded public Run.
const corpus=JSON.parse(readFileSync(new URL('../../portability/corpus/openai-chat.json',import.meta.url)));
const original=Object.freeze({}),provider=Object.freeze({});
const projected=()=>({_0:corpus.prompt.payload.instructions,
  _1:'{"decimal":"9007199254740993.00","text":"é\\r\\n","null":null}',
  _2:JSON.stringify(corpus.schema),_3:corpus.task.contract_cid,
  _4:corpus.prompt.self_cid,_5:corpus.task.output_schema_cid,_6:'fixture-chat'});
const limits=Object.freeze({maxBytes:10000,maxNodes:1000,maxDepth:40,maxFrames:100,maxWork:10000});
const options={admittedProvider:provider,request:original,
  taskCid:corpus.task.contract_cid,promptCid:corpus.prompt.self_cid,
  outputSchemaCid:corpus.task.output_schema_cid,modelSelector:'fixture-chat',
  projectionLimits:limits,modelId:'gpt-4.1-nano',baseURL:'https://fixture.invalid/v1',
  apiKey:'fixture-only',maxRequestBytes:4000,maxHeaderBytes:4096,maxHeaders:16,notify(){}};
const moonFor=value=>({clientProgramProjectOpenAIChatRequest(p,r,...bounds){
  assert.equal(p,provider);assert.equal(r,original);
  assert.deepEqual(bounds,Object.values(limits));
  return {$tag:1,_0:value};
},clientProgramModelRequestGeneration(r){assert.equal(r,original);
  return {_0:'fixture-chat',_1:0.25,_2:0.875,_3:16n,_4:-7n};}});
async function poll(handle){for(let i=0;i<30;i++){const p=pollSdkPreparation(handle);if(p.kind!=='pending')return p;await turn();}assert.fail('SDK did not settle');}
async function retire(handle){for(let i=0;i<30;i++){if(cleanupSdkPreparation(handle))return;await turn();}assert.fail('SDK cleanup pending');}

test('admitted projection reaches actual SDK strict schema and two exact messages with zero network',async t=>{
  const ambient=globalThis.fetch;let calls=0;
  globalThis.fetch=()=>{calls++;assert.fail('Ambient network');};
  t.after(()=>{globalThis.fetch=ambient;});
  const value=projected(),handle=prepareAdmittedOpenAIChatRequest({...options,moon:moonFor(value)});
  t.after(()=>retire(handle));
  assert.equal((await poll(handle)).kind,'ready');
  assert.deepEqual(JSON.parse(sdkPreparedRequest(handle).body),{
    model:'gpt-4.1-nano',temperature:0.25,top_p:0.875,max_tokens:16,seed:-7,
    messages:[{role:'system',content:value._0},{role:'user',content:value._1}],
    response_format:{type:'json_schema',json_schema:{schema:corpus.schema,strict:true,name:'actql_output'}},
  });
  assert.equal(calls,0);
});

test('copied Task prompt output schema or selector mismatch refuses before SDK preparation',()=>{
  for(const field of ['taskCid','promptCid','outputSchemaCid','modelSelector']){
    let wakes=0;
    assert.throws(()=>prepareAdmittedOpenAIChatRequest({...options,[field]:'foreign',
      moon:moonFor(projected()),notify(){wakes++;}}),{message:'OpenAIOriginalSchemaBindingMismatch'});
    assert.equal(wakes,0);
  }
});

test('Common typed unsupported never builds SDK or sends a request',()=>{
  let generationReads=0;
  const moon={clientProgramProjectOpenAIChatRequest(){return {$tag:0,_0:'unsupported'};},
    clientProgramOpenAIChatProjectionIssueKind(x){return x;},
    clientProgramModelRequestGeneration(){generationReads++;assert.fail('Rejected projection read generation');}};
  assert.throws(()=>prepareAdmittedOpenAIChatRequest({...options,moon}),{message:'OpenAIProjection:unsupported'});
  assert.equal(generationReads,0);
});

test('original tuple mutation after preparation cannot replace instructions or schema expectations',async t=>{
  const value=projected(),generation={_0:'fixture-chat',_1:0.25,_2:0.875,_3:16n,_4:-7n};
  const moon={...moonFor(value),clientProgramModelRequestGeneration(){return generation;}};
  const handle=prepareAdmittedOpenAIChatRequest({...options,moon});
  t.after(()=>retire(handle));
  value._0='foreign';value._1='foreign';value._2='{}';generation._1=2;
  assert.equal((await poll(handle)).kind,'ready');
  const body=JSON.parse(sdkPreparedRequest(handle).body);
  assert.equal(body.temperature,0.25);
  assert.equal(body.messages[0].content,corpus.prompt.payload.instructions);
  assert.deepEqual(body.response_format.json_schema.schema,corpus.schema);
});

test('actual SDK keeps escaped and prototype-like properties required and closed',async t=>{
  const value=projected();
  const schema=JSON.parse('{"additionalProperties":false,"properties":{"__proto__":{"type":"boolean"},"quote\\\"":{"type":"string"},"é":{"items":{"anyOf":[{"type":"number"},{"type":"null"}]},"type":"array"}},"required":["__proto__","quote\\\"","é"],"type":"object"}');
  value._2=JSON.stringify(schema);
  const handle=prepareAdmittedOpenAIChatRequest({...options,moon:moonFor(value)});
  t.after(()=>retire(handle));
  assert.equal((await poll(handle)).kind,'ready');
  assert.deepEqual(JSON.parse(sdkPreparedRequest(handle).body).response_format.json_schema.schema,schema);
});

test('SDK model-dependent rewrite is refused instead of silently altering authored generation',async t=>{
  const handle=prepareAdmittedOpenAIChatRequest({...options,modelId:'o3-mini',moon:moonFor(projected())});
  t.after(()=>retire(handle));
  const status=await poll(handle);
  assert.equal(status.kind,'rejected');
  assert.equal(status.issue,'SdkOriginalRequestMismatch');
});
