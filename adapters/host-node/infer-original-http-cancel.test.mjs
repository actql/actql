// Same actual Common/SDK/Undici/Store/journal as the success join. The server
// deliberately never responds. Synthetic allowances remain fixture DATA;
// no live Provider, normal numerical profile or public Run is admitted here.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {setImmediate as turn} from 'node:timers/promises';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOriginalUndiciFetch} from '../../packages/provider-ai-sdk/_internal/original-undici-transport.mjs';
import {originalSdkCommonFixture} from './infer-original-sdk-common.fixture.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';

async function until(read,accept) {
  for(let index=0;index<500;index++){
    const value=await read();
    if(accept(value))return value;
    await turn();
  }
  assert.fail('Original cancellation duty did not finish');
}

test('original HTTP cancellation preserves the entered Unknown without a response or resend',
  {timeout:15000},async t=>{
    const calls=[],sockets=new Set();
    let receive;
    const received=new Promise(resolve=>{receive=resolve;});
    const server=createServer(async request=>{
      let bytes=0;
      for await(const chunk of request)bytes+=chunk.byteLength;
      calls.push({method:request.method,path:request.url,bytes});
      receive();
      // Deliberately no headers, response body or server-side forced close.
    });
    server.on('connection',socket=>{
      sockets.add(socket);socket.once('close',()=>sockets.delete(socket));
    });
    server.listen(0,'127.0.0.1');await once(server,'listening');
    t.after(async()=>{
      // Environment teardown after assertions, never a product close ACK.
      server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
    });
    const endpoint=`http://127.0.0.1:${server.address().port}/v1/chat/completions`;
    const fetch=createOriginalUndiciFetch({endpoint,
      requestLimits:{maxBytes:1000,maxHeaderBytes:4096,maxHeaders:16},
      responseLimits:{maxBytes:2048,maxChunkBytes:512,maxChunks:16,
        maxHeaderBytes:128,observedHeaders:['content-type']},
      physicalAcquisitionLimits:{maxPlaintextBytes:65536,
        maxBorrowedBackingBytes:131072,maxReads:64}});
    const abort=new AbortController();
    const f=await originalSdkCommonFixture(t,moon,{physical:{endpoint,fetch},signal:abort.signal});
    const capture=openNodeInferCaptureCustody({moon,control:f.control,
      operation:f.operation,plan:f.plan,store:f.store,storeAuthorityCid:f.storeAuthorityCid,
      durableCalls:true,captureOnly:true});
    capture.configureModelJournal({observe:f.opened.observe,entry:f.opened.entry});
    assert.deepEqual(await f.opened.authorize(),{status:'dispatch'});
    await f.opened.prepareOriginalResourcesForDispatch();
    assert.equal(calls.length,0);
    const running=f.operation.run();
    // Observe rejection before delivering cancellation, including a prompt
    // original response loss; do not detach a rejecting original flight.
    const stopped=running.then(value=>({value}),error=>({error}));
    await Promise.race([received,stopped.then(()=>{
      assert.fail('Original Model finished before the server received its request');
    })]);
    assert.equal(calls.length,1);assert.ok(calls[0].bytes>0);
    const entry=f.opened.entry(0);assert.ok(entry);
    const originalIdentity={...entry};
    assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,'EnteredUnknown');
    const reason=new Error('Selected fixture cancellation');
    abort.abort(reason);
    assert.equal(f.operation.cleanupPending(),true,'Cancel request alone cannot retire original custody');
    const stoppedError=(await stopped).error;
    // An entered request with no response is UnknownCalls, not proof that
    // remote work was cancelled. Assert semantic original evidence below,
    // rather than depending on private numeric enum tags or relabelling it
    // as the AbortSignal's local reason.
    assert.equal(stoppedError?.code,'MoonBitHostFailure');
    assert.equal(f.operation.hasUnknownCalls(),true,
      'Adopting result_unknown cannot make the live original observation false');
    await capture.persistStoppedAttempts();
    const proof=f.operation.attemptEvidence(0);
    const outcome=JSON.parse(moon.strategyRunEvidenceJson(moon.clientProgramInferAttemptLeaf(proof,'outcome')));
    const accountingWire=moon.strategyRunEvidenceJson(moon.clientProgramInferAttemptLeaf(proof,'accounting'));
    const accounting=JSON.parse(accountingWire);
    assert.equal(outcome.category,'result_unknown');
    assert.equal(accounting.input_tokens,null);assert.equal(accounting.output_tokens,null);
    assert.equal(accounting.cost_units,null);assert.equal(accounting.duration_ms,null);
    assert.equal(accounting.reservation.tokens,128,'Reservation is not observed usage');
    assert.ok(accounting.uncertain_wire_bytes>0);
    await until(()=>capture.custody.cleanup(),value=>value===true);
    await until(()=>f.opened.cleanup(),value=>value===true);
    await until(()=>sockets.size,value=>value===0);
    assert.deepEqual(entry,originalIdentity);
    assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,'EnteredUnknown');
    assert.equal(f.controller.unresolved('original-sdk-common'),true);
    assert.equal(moon.strategyRunEvidenceJson(moon.clientProgramInferAttemptLeaf(proof,'accounting')),accountingWire,
      'Physical cleanup must not replace the immutable Unknown accounting');
    assert.equal(f.originalReads(),1,'No absent response can supply a second raw-save recheck');
    assert.equal(calls.length,1,'Cancellation/cleanup cannot recreate Entry or send again');
    const original=f.originalPreparation;
    f.control.stopCheckedClientInferOriginalReadPreparation(f.plan.compiled,
      f.plan.runDefinition,f.plan.inferGraph,original.scope,original.read);
    f.control.settleCheckedClientInferOriginalReadPreparation(f.plan.compiled,
      f.plan.runDefinition,f.plan.inferGraph,original.read,true);
    assert.equal(f.control.finishCheckedClientInferOriginalReadScope(f.plan.compiled,
      f.plan.runDefinition,f.plan.inferGraph,original.scope,true),true);
    t.diagnostic('Original EnteredUnknown retained; actual local close is not remote cancellation or a resend grant');
  });
