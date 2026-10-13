import test from 'node:test';
import assert from 'node:assert/strict';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {originalSdkCommonFixture} from './infer-original-sdk-common.fixture.mjs';

const responseWire='{"id":"original-response","model":"reported-model","choices":[{"index":0,"message":{"role":"assistant","content":"{\\"risk\\":\\"low\\",\\"reason\\":null}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2}}';

test('original Common physical request joins pinned SDK and actual raw Store after journal authorization',async t=>{
  const f=await originalSdkCommonFixture(t,moon,{responseWire});
  assert.equal(f.sends(),0);
  assert.deepEqual(await f.opened.authorize(),{status:'dispatch'});
  assert.equal(f.originalReads(),1);
  assert.equal(f.sends(),0);
  await f.opened.prepareOriginalResourcesForDispatch();
  assert.equal(f.sends(),0);
  let result;
  try {result=await f.operation.run();}
  catch(error){
    const tag=value=>Number.isInteger(value?.$tag)?value.$tag:null;
    t.diagnostic(`Original post-cut tags ${JSON.stringify([tag(error.cause),tag(error.cause?._0),tag(error.cause?._0?._0)])}; sends=${f.sends()}; state=${f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state}`);
    const failure=f.ports[0]?.rawFailure();
    t.diagnostic(`Original raw persistence code=${typeof failure?.code==='string'?failure.code:'unavailable'}; retained=${failure?.rawCustodyRetained===true}`);
    throw error;
  }
  t.diagnostic(`Original execution boundary: ${result?.status??'complete'}`);
  assert.equal(f.sends(),1);
  assert.equal(f.originalReads(),2,'same actual Store rechecks after transport');
  assert.deepEqual(JSON.parse(f.requests[0].body),{
    model:'gpt-4.1-nano',temperature:0,top_p:1,max_tokens:32,seed:-7,
    messages:[{role:'system',content:'Original é\r\n'},{role:'user',content:'{"text":"hello"}'}],
    response_format:{type:'json_schema',json_schema:{name:'actql_output',strict:true,
      schema:{type:'object',properties:{reason:{anyOf:[{type:'string'},{type:'null'}]},risk:{type:'string'}},
        required:['reason','risk'],additionalProperties:false}}},
  });
});

test('actual original policy body absence refuses before Approval Entry or SDK fetch and never retries the check',async t=>{
  const f=await originalSdkCommonFixture(t,moon,{responseWire,storeOriginals:false});
  await assert.rejects(f.opened.authorize(),{code:'PublicationContractMissing'});
  await assert.rejects(f.opened.authorize(),{code:'PublicationContractMissing'});
  assert.equal(f.originalReads(),1);
  assert.equal(f.sends(),0);
  assert.equal(f.cp.journal.getRunState('original-sdk-common'),undefined);
  assert.equal(f.opened.entry(0),undefined);
});

test('cancellation while exact Store originals are checked cannot authorize an Entry or send',async t=>{
  const abort=new AbortController();
  const f=await originalSdkCommonFixture(t,moon,{responseWire,signal:abort.signal,
    beforeOriginalRead(){abort.abort();}});
  await assert.rejects(f.opened.authorize(),{name:'AbortError'});
  assert.equal(f.originalReads(),1);
  assert.equal(f.sends(),0);
  assert.equal(f.opened.entry(0),undefined);
});

test('failed original Store reader keeps same cleanup handle and input token until retry confirms closure',async t=>{
  let pending=true,retries=0;
  const issue=Object.assign(new Error('OriginalReadCloseFailed'),{
    code:'OriginalReadCloseFailed',cleanupHandle:{status:()=>({pending}),async retry(){retries++;pending=false;}}});
  const f=await originalSdkCommonFixture(t,moon,{responseWire,beforeOriginalRead(){throw issue;}});
  await assert.rejects(f.opened.authorize(),error=>error===issue);
  assert.equal(f.opened.close(),false);
  assert.equal(f.opened.token.available,true);
  assert.equal(f.sends(),0);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(retries,1);
  assert.equal(pending,false);
  // Core physical read/SDK retirement remains a separate original Owner fact.
  // A Store cleanup acknowledgement alone cannot refund or reopen that Scope.
  assert.equal(f.opened.entry(0),undefined);
});
