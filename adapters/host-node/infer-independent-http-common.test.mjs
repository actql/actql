// Actual Common/independent B HTTP/encrypted Store/SQLite. Synthetic profile,
// byte declarations and authority remain fixture DATA, not normal funding.
// No AI SDK branch, live Provider, public Client or Named Result is used.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer,request as httpRequest} from 'node:http';
import {Readable} from 'node:stream';
import {once} from 'node:events';
import {setImmediate as turn} from 'node:timers/promises';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {originalHttpCommonFixture} from './infer-original-sdk-common.fixture.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {checked} from '../host-common/runtime-result.mjs';

const expectedRequest={model:'independent-fixture',n:1,stream:false,
  temperature:0,top_p:1,max_tokens:32,seed:-7,
  messages:[{role:'system',content:'Original é\r\n'},
    {role:'user',content:'{"text":"hello"}'}],
  response_format:{type:'json_schema',json_schema:{name:'actql_output',strict:true,
    schema:{type:'object',properties:{reason:{anyOf:[{type:'string'},{type:'null'}]},
      risk:{type:'string'}},required:['reason','risk'],additionalProperties:false}}}};

async function until(read,accept) {
  for(let index=0;index<500;index++){
    const value=await read();
    if(accept(value))return value;
    await turn();
  }
  assert.fail('Independent original HTTP responsibility did not retire');
}

function readOriginalAnswer(settlement) {
  // Existing bounded Common settlement serializer, not a JS answer decoder.
  // Release this same temporary output use before normal persistence/ACK.
  const exporter=checked(moon.clientProgramStartInferCallSettlementExport(settlement,4096,10000));
  let complete=false,wire='';
  try {
    for(let count=0;count<10000&&!complete;count++){
      const progress=checked(moon.clientProgramAdvanceInferCaptureExport(exporter,256));
      wire+=progress._1;complete=progress._0;
    }
    assert.equal(complete,true);
    const bundle=JSON.parse(wire);
    assert.equal(bundle.captures.length,1);
    return bundle.captures[0].structured_response;
  } finally {
    if(!complete&&moon.clientProgramCancelInferCaptureExport(exporter)) {
      assert.equal(moon.clientProgramAdvanceInferCaptureExport(exporter,1).$tag,0);
    }
    let retired=false;
    for(let count=0;count<10&&!retired;count++)retired=checked(moon.clientProgramCleanupInferCaptureExport(exporter));
    assert.equal(retired,true,'The original exporter must return its temporary output use');
  }
}

for(const variant of ['reported','unreported']) {
  test(`independent HTTP ${variant} joins actual Common raw custody and same journal settlement`,
    {timeout:15000},async t=>{
      const calls=[],sockets=new Set();
      const began=performance.now();
      let phase='prepare';
      const mark=next=>{
        phase=next;
        t.diagnostic(`Independent phase ${phase}; elapsed_ms=${Math.round(performance.now()-began)}; requests=${calls.length}`);
      };
      t.after(()=>mark(`final:${phase}`));
      // Independently authored response, not copied from the product decoder.
      const responseWire=JSON.stringify({
        ...(variant==='reported'?{id:'independent-response',model:'reported-model',
          usage:{prompt_tokens:3,completion_tokens:2}}:{}),
        choices:[{index:0,message:{role:'assistant',
          content:'{"risk":"low","reason":null}'},finish_reason:'stop'}],
        opaque:{unknown:'é\r\n'},
      });
      const server=createServer(async(request,response)=>{
        let body='';
        for await(const chunk of request)body+=chunk.toString('utf8');
        calls.push({method:request.method,path:request.url,body});
        response.sendDate=false;
        response.setHeader('content-type','application/json');
        response.setHeader('connection','close');
        response.end(responseWire);
      });
      server.on('connection',socket=>{
        sockets.add(socket);socket.once('close',()=>sockets.delete(socket));
      });
      server.listen(0,'127.0.0.1');await once(server,'listening');
      t.after(async()=>{
        // Environment teardown, never the Core's physical-close receipt.
        server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
      });
      const endpoint=`http://127.0.0.1:${server.address().port}/v1/chat/completions`;
      const clientSockets=new Set();
      // Explicit no-credential test transport using Node HTTP, not ambient
      // fetch, A's SDK/Undici, a retrying agent or another Model scheduler.
      // These test-only Node/Response holdings are NOT a normal layout proof.
      const physicalFetch=(url,init)=>new Promise((resolve,reject)=>{
        assert.equal(url,endpoint);assert.equal(init.redirect,'error');
        const request=httpRequest(url,{method:init.method,
          headers:Object.fromEntries(init.headers),signal:init.signal,agent:false},response=>{
          resolve(new Response(Readable.toWeb(response),{
            status:response.statusCode,headers:response.headers}));
        });
        request.on('socket',socket=>{
          clientSockets.add(socket);socket.once('close',()=>clientSockets.delete(socket));
        });
        request.once('error',reject);request.end(init.body);
      });
      const f=await originalHttpCommonFixture(t,moon,{modelId:'independent-fixture',
        physical:{endpoint,fetch:physicalFetch}});
      mark('prepared');
      assert.equal(JSON.parse(f.profileWire).adapter.sdk,null);
      assert.equal(f.registered.rawCaptureSelection.installation.sdk,undefined);
      assert.equal(f.sends,undefined,'Only the actual server witnesses dispatch');
      assert.equal(calls.length,0);
      assert.deepEqual(await f.opened.authorize(),{status:'dispatch'});
      mark('authorized');
      assert.equal(calls.length,0,'Authorization alone starts no physical request');
      await f.opened.prepareOriginalResourcesForDispatch();
      mark('original-cut-confirmed');
      assert.equal(calls.length,0,'Original Store/Journal resource handoff is not send');
      const capture=openNodeInferCaptureCustody({moon,control:f.control,
        operation:f.operation,plan:f.plan,store:f.store,storeAuthorityCid:f.storeAuthorityCid,
        durableCalls:true,captureOnly:true});
      capture.configureModelJournal({observe:f.opened.observe,entry:f.opened.entry});
      const boundary=await f.operation.run();
      mark('settling');
      assert.equal(boundary.status,'settling');
      assert.equal(calls.length,1);
      assert.equal(calls[0].method,'POST');
      assert.equal(calls[0].path,'/v1/chat/completions');
      assert.deepEqual(JSON.parse(calls[0].body),expectedRequest);
      assert.equal(f.originalReads(),2,'Same Store rechecks original policy after raw acquisition');
      const entry=f.opened.entry(0);assert.ok(entry);
      assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,'EnteredUnknown');
      assert.deepEqual(readOriginalAnswer(boundary.settlement),{reason:null,risk:'low'});
      const observation=JSON.parse(moon.strategyRunEvidenceJson(f.operation.invocationEvidence(0)));
      assert.equal(observation.provider_request_id,variant==='reported'?'independent-response':null);
      assert.equal(observation.provider_reported_model_id,variant==='reported'?'reported-model':null);
      assert.equal(observation.input_tokens,variant==='reported'?3:null);
      assert.equal(observation.output_tokens,variant==='reported'?2:null);
      assert.equal(observation.provider_metadata,null,'Unknown raw fields are not invented metadata');
      assert.equal(observation.response_complete,true);
      assert.match(observation.raw_response_artifact_cid,/^sha256:[a-f0-9]{64}$/u);
      const saved=await capture.persistSettlement(boundary.settlement,entry);
      mark('settlement-saved');
      assert.equal(saved.state,'SavedSuccess');
      await f.operation.run();
      mark('completed');
      assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,'SavedSuccess');
      assert.equal(f.operation.hasUnknownCalls(),false);
      await until(()=>capture.custody.cleanup(),value=>value===true);
      mark('capture-cleaned');
      await until(()=>f.opened.cleanup(),value=>value===true);
      mark('continuation-cleaned');
      const original=f.originalPreparation;
      f.control.stopCheckedClientInferOriginalReadPreparation(f.plan.compiled,
        f.plan.runDefinition,f.plan.inferGraph,original.scope,original.read);
      f.control.settleCheckedClientInferOriginalReadPreparation(f.plan.compiled,
        f.plan.runDefinition,f.plan.inferGraph,original.read,true);
      assert.equal(f.control.finishCheckedClientInferOriginalReadScope(f.plan.compiled,
        f.plan.runDefinition,f.plan.inferGraph,original.scope,true),true);
      mark('scope-finished');
      await until(()=>sockets.size+clientSockets.size,value=>value===0);
      mark('sockets-closed');
      assert.equal(calls.length,1,'Cleanup/settlement cannot send the original request again');
      t.diagnostic('Actual SDK-free HTTP/Common/Store/journal; explicit fixture transport/profile, public Model E2E0');
    });
}
