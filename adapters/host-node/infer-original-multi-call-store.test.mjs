// Actual Common/SDK/Undici/Store/Journal, with synthetic physical declarations.
// The installed IO-access supplier is absent: this tests two serial original
// Calls, not the separate four-slot window, public startup or normal funding.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {setImmediate as turn} from 'node:timers/promises';
import {pathToFileURL} from 'node:url';
import {createOriginalUndiciFetch} from '../../packages/provider-ai-sdk/_internal/original-undici-transport.mjs';
import {originalSdkCommonFixture} from './infer-original-sdk-common.fixture.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';

const runtime=process.env.ACTQL_INFER_ORIGINAL_RUNTIME===undefined
  ? new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url)
  : pathToFileURL(process.env.ACTQL_INFER_ORIGINAL_RUNTIME);
const moon=await import(runtime.href);
const deferred=()=>{let resolve;const promise=new Promise(value=>{resolve=value;});return {promise,resolve};};
async function until(read,accept){
  for(let step=0;step<500;step++){const value=await read();if(accept(value))return value;await turn();}
  assert.fail('The same original cleanup duty did not finish');
}

test('two original Common Calls save distinct raw and typed captures through one installed Store',
  {timeout:15000},async t=>{
    const rowTexts=['first original row','second original row'];
    const received=rowTexts.map(deferred),requests=[],responses=[],sockets=new Set();
    const parked=deferred(),release=deferred();
    const server=createServer(async(request,response)=>{
      let body='';for await(const chunk of request)body+=chunk.toString('utf8');
      const text=JSON.parse(JSON.parse(body).messages.at(-1).content).text;
      const slot=rowTexts.indexOf(text);assert.ok(slot>=0);
      assert.equal(responses[slot],undefined,'The original Call cannot be resent');
      requests.push({slot,method:request.method,path:request.url,body,port:request.socket.remotePort});
      responses[slot]=response;received[slot].resolve();
    });
    server.on('connection',socket=>{sockets.add(socket);socket.once('close',()=>sockets.delete(socket));});
    server.listen(0,'127.0.0.1');await once(server,'listening');
    t.after(async()=>{
      release.resolve();
      server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
    });
    const reply=slot=>{
      const response=responses[slot];assert.ok(response);
      response.sendDate=false;response.setHeader('content-type','application/json');
      response.setHeader('connection','close');
      response.end(JSON.stringify({id:`original-${slot}`,model:'reported-model',choices:[{
        index:0,message:{role:'assistant',content:JSON.stringify({risk:rowTexts[slot],reason:null})},
        finish_reason:'stop'}],usage:{prompt_tokens:3,completion_tokens:2}}));
    };
    const endpoint=`http://127.0.0.1:${server.address().port}/v1/chat/completions`;
    const fetch=createOriginalUndiciFetch({endpoint,
      requestLimits:{maxBytes:1000,maxHeaderBytes:4096,maxHeaders:16},
      responseLimits:{maxBytes:2048,maxChunkBytes:512,maxChunks:16,
        maxHeaderBytes:128,observedHeaders:['content-type']},
      physicalAcquisitionLimits:{maxPlaintextBytes:65536,maxBorrowedBackingBytes:131072,maxReads:64}});
    const f=await originalSdkCommonFixture(t,moon,{physical:{endpoint,fetch},rowTexts,
      async beforeOriginalRead({read}){
        if(read===2){parked.resolve();await release.promise;}
      }});
    assert.equal(f.ports.length,2,'All original SDK cursors prepare before the CallSet');
    const capture=openNodeInferCaptureCustody({moon,control:f.control,
      operation:f.operation,plan:f.plan,store:f.store,storeAuthorityCid:f.storeAuthorityCid,
      durableCalls:true,captureOnly:true});
    capture.configureModelJournal({observe:f.opened.observe,entry:f.opened.entry});
    assert.deepEqual(await f.opened.authorize(),{status:'dispatch'});
    await f.opened.prepareOriginalResourcesForDispatch();
    assert.equal(requests.length,0);
    const first=f.operation.run();
    await Promise.race([received[0].promise,first.then(()=>assert.fail('No response is available yet'))]);
    assert.equal(requests.length,1);reply(0);
    await Promise.race([parked.promise,first.then(()=>assert.fail('Original raw Store read is still pending'))]);
    assert.equal(f.operation.run(),first,'Pending raw save keeps the same driver flight');
    assert.equal(f.operation.cleanupPending(),true);
    assert.equal(requests.length,1,'Raw EOF cannot admit a later Call while saving is pending');
    assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,'EnteredUnknown');
    release.resolve();
    const firstBoundary=await first;
    assert.equal(firstBoundary.status,'settling');
    assert.equal(f.operation.settlementSlot(firstBoundary.settlement),0);
    assert.equal(requests.length,1,'Raw Store confirmation is not the original settlement ACK');
    assert.equal((await capture.persistSettlement(firstBoundary.settlement,f.opened.entry(0))).state,'SavedSuccess');
    const second=f.operation.run();
    await Promise.race([received[1].promise,second.then(()=>assert.fail('Second original response is still absent'))]);
    assert.equal(requests.length,2);reply(1);
    const secondBoundary=await second;
    assert.equal(secondBoundary.status,'settling');
    assert.equal(f.operation.settlementSlot(secondBoundary.settlement),1);
    assert.equal((await capture.persistSettlement(secondBoundary.settlement,f.opened.entry(1))).state,'SavedSuccess');
    await f.operation.run();
    assert.equal(f.originalReads(),3,'Authorization and both original raw saves recheck the same policy originals');
    assert.deepEqual(f.cp.journal.readModelCalls(f.opened.inventory).slots.map(value=>value.state),
      ['SavedSuccess','SavedSuccess']);
    const inventory=f.opened.evaluationInventory(),slotCids=[],attemptCids=[];
    for(let slot=0;slot<2;slot++){
      const captureRecord=JSON.parse(moon.strategyRunEvidenceJson(f.operation.issuedSlotCapture(slot)));
      const saved=await inventory.readBundle(slot);
      assert.ok(saved);
      const bundle=JSON.parse(saved.wire);assert.equal(bundle.captures.length,1);
      assert.equal(bundle.captures[0].model_call_slot_cid,captureRecord.slot_cid);
      assert.deepEqual(bundle.captures[0].structured_response,{risk:rowTexts[slot],reason:null});
      assert.equal(captureRecord.outcome,'ok');
      assert.equal(captureRecord.adopted_attempt_cid,f.opened.entry(slot).attemptCid);
      slotCids.push(captureRecord.slot_cid);attemptCids.push(captureRecord.adopted_attempt_cid);
    }
    assert.equal(new Set(slotCids).size,2);assert.equal(new Set(attemptCids).size,2);
    assert.equal(new Set(requests.map(value=>value.port)).size,2,'Each original Call owns a separate Client/socket');
    assert.deepEqual(requests.map(value=>[value.slot,value.method,value.path]),
      [[0,'POST','/v1/chat/completions'],[1,'POST','/v1/chat/completions']]);
    await until(()=>capture.custody.cleanup(),value=>value===true);
    await until(()=>f.opened.cleanup(),value=>value===true);
    const original=f.originalPreparation;
    f.control.stopCheckedClientInferOriginalReadPreparation(f.plan.compiled,
      f.plan.runDefinition,f.plan.inferGraph,original.scope,original.read);
    f.control.settleCheckedClientInferOriginalReadPreparation(f.plan.compiled,
      f.plan.runDefinition,f.plan.inferGraph,original.read,true);
    assert.equal(f.control.finishCheckedClientInferOriginalReadScope(f.plan.compiled,
      f.plan.runDefinition,f.plan.inferGraph,original.scope,true),true);
    await until(()=>sockets.size,value=>value===0);
    assert.equal(f.operation.cleanupPending(),false);assert.equal(f.opened.cleanupPending(),false);
    assert.equal(requests.length,2,'Cleanup/settlement never sends another original request');
  });
