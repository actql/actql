// Actual Common, pinned SDK, original Undici HTTP, encrypted Store and SQLite.
// All policy/layout amounts remain explicit synthetic fixture declarations.
// No normal profile, public Client/Named Result or external Provider is tested.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {setImmediate as turn} from 'node:timers/promises';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOriginalUndiciFetch} from '../../packages/provider-ai-sdk/_internal/original-undici-transport.mjs';
import {originalSdkCommonFixture} from './infer-original-sdk-common.fixture.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';

const responseWire='{"id":"original-http-response","model":"reported-model",'+
  '"choices":[{"index":0,"message":{"role":"assistant",'+
  '"content":"{\\"risk\\":\\"low\\",\\"reason\\":null}"},"finish_reason":"stop"}],'+
  '"usage":{"prompt_tokens":3,"completion_tokens":2}}';

async function until(read,accept) {
  for(let index=0;index<500;index++) {
    const value=await read();
    if(accept(value))return value;
    await turn();
  }
  assert.fail('Original joined physical duty did not finish');
}

test('original HTTP Common caller saves and settles one real loopback response before same-owner cleanup',
  {timeout:15000},async t=>{
    const calls=[],sockets=new Set();
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
      sockets.add(socket);
      socket.once('close',()=>sockets.delete(socket));
    });
    server.listen(0,'127.0.0.1');
    await once(server,'listening');
    t.after(async()=>{
      // Test-environment shutdown is not a product ACK. Success below first
      // requires original Common/SDK/Store cleanup with the server still live.
      server.closeAllConnections();
      await new Promise(resolve=>server.close(resolve));
    });
    const endpoint=`http://127.0.0.1:${server.address().port}/v1/chat/completions`;
    const fetch=createOriginalUndiciFetch({endpoint,
      requestLimits:{maxBytes:1000,maxHeaderBytes:4096,maxHeaders:16},
      responseLimits:{maxBytes:2048,maxChunkBytes:512,maxChunks:16,
        maxHeaderBytes:128,observedHeaders:['content-type']},
      physicalAcquisitionLimits:{maxPlaintextBytes:65536,
        maxBorrowedBackingBytes:131072,maxReads:64}});
    const f=await originalSdkCommonFixture(t,moon,{physical:{endpoint,fetch}});
    assert.equal(f.sends,undefined,'Do not reuse the uninstrumented fixture counter');
    assert.equal(calls.length,0);
    assert.deepEqual(await f.opened.authorize(),{status:'dispatch'});
    assert.equal(calls.length,0,'Authorization is not transport start');
    await f.opened.prepareOriginalResourcesForDispatch();
    assert.equal(calls.length,0,'Store ACK/COMMIT/fence removal is not a send grant');

    const capture=openNodeInferCaptureCustody({moon,control:f.control,
      operation:f.operation,plan:f.plan,store:f.store,storeAuthorityCid:f.storeAuthorityCid,
      durableCalls:true,captureOnly:true});
    capture.configureModelJournal({observe:f.opened.observe,entry:f.opened.entry});
    const boundary=await f.operation.run();
    assert.equal(boundary.status,'settling');
    assert.equal(calls.length,1);
    assert.deepEqual({method:calls[0].method,path:calls[0].path},
      {method:'POST',path:'/v1/chat/completions'});
    assert.equal(JSON.parse(calls[0].body).model,'gpt-4.1-nano');
    assert.equal(f.originalReads(),2,'Actual Store rechecks originals after transport');
    const entry=f.opened.entry(0);
    assert.ok(entry);
    assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,'EnteredUnknown',
      'A saved raw response alone is not the settled slot');
    const saved=await capture.persistSettlement(boundary.settlement,entry);
    assert.equal(saved.state,'SavedSuccess');
    assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,'SavedSuccess');
    await f.operation.run();
    assert.equal(calls.length,1,'Settlement must not repeat the original physical request');
    await until(()=>capture.custody.cleanup(),value=>value===true);
    await until(()=>f.opened.cleanup(),value=>value===true);
    assert.equal(f.operation.cleanupPending(),false);
    assert.equal(f.opened.cleanupPending(),false);
    const original=f.originalPreparation;
    f.control.stopCheckedClientInferOriginalReadPreparation(f.plan.compiled,
      f.plan.runDefinition,f.plan.inferGraph,original.scope,original.read);
    f.control.settleCheckedClientInferOriginalReadPreparation(f.plan.compiled,
      f.plan.runDefinition,f.plan.inferGraph,original.read,true);
    assert.equal(f.control.finishCheckedClientInferOriginalReadScope(f.plan.compiled,
      f.plan.runDefinition,f.plan.inferGraph,original.scope,true),true);
    await until(()=>sockets.size,value=>value===0);
    assert.equal(calls.length,1);
    t.diagnostic('Actual loopback/SDK/Common/raw Store/SQLite settlement; synthetic funding, public Model E2E0');
  });
