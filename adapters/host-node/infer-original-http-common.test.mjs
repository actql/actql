// Actual Common, pinned SDK, original Undici HTTP, encrypted Store and SQLite.
// All policy/layout amounts remain explicit synthetic fixture declarations.
// No normal profile, public Client/Named Result or external Provider is tested.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {setImmediate as turn} from 'node:timers/promises';
import {pathToFileURL} from 'node:url';
import {createOriginalUndiciFetch} from '../../packages/provider-ai-sdk/_internal/original-undici-transport.mjs';
import {originalSdkCommonFixture} from './infer-original-sdk-common.fixture.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {loadCheckpointRuntime} from './sqlite-checkpoint-journal.mjs';

const moon=await import(process.env.ACTQL_INFER_ORIGINAL_RUNTIME===undefined
  ? new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',import.meta.url).href
  : pathToFileURL(process.env.ACTQL_INFER_ORIGINAL_RUNTIME).href);

const responseWire='{"id":"original-http-response","model":"reported-model","system_fingerprint":"fp_observed",'+
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
  {timeout:15000}, t => originalHttpSettlement(t, false));

test('direct Chat HTTP saves a complete non-JSON refusal on the original attempt',
  {timeout:15000}, t => originalHttpSettlement(t, false, {
    status:503, contentType:'text/plain', wire:'Controlled provider unavailable', outcome:'provider_error',
  }));

test('direct Chat HTTP retains an incomplete non-JSON refusal as the original unknown attempt',
  {timeout:15000}, t => originalHttpSettlement(t, false, {
    status:503, contentType:'text/plain', wire:'Controlled provider unavailable', loseResponse:true,
  }));

test('selected structured SDK settles the original verified Raw through Common and the journal',
  {timeout:15000}, t => originalHttpSettlement(t, 'registered'));

test('registered SDK omits reported metadata excluded by its original Response Profile',
  {timeout:15000}, t => originalHttpSettlement(t,'registered',{excludeReportedMetadata:true}));

test('registered SDK rejects a separate equal profile before Entry and transport',
  {timeout:15000}, t => originalHttpSettlement(t, 'registered', {foreignRegisteredProfile:true}));

for (const [name,flag] of [['false',false],['missing',undefined]]) {
  test('Common refuses a saved callback answer with '+name+' completion',
    {timeout:15000}, t => originalHttpSettlement(t,'registered',{overrideCompletion:()=>flag}));
}

test('selected structured SDK retains the original unknown when Raw cannot be confirmed',
  {timeout:15000}, t => originalHttpSettlement(t, true, {refuseRaw: true}));

for (const [status, outcome] of [[401,'provider_error'],[429,'rate_limit'],[503,'provider_error']]) {
  test('selected structured SDK saves complete HTTP '+status+' as '+outcome,
    {timeout:15000}, t => originalHttpSettlement(t, true, {
      status, outcome, wire:'{"error":{"message":"controlled provider failure"}}', usage:[null,null],
    }));
}

test('selected structured SDK classifies a malformed complete 2xx from its decoder',
  {timeout:15000}, t => originalHttpSettlement(t, true, {
    outcome:'schema_invalid',wire:'{"not-a-provider-envelope":true}',usage:[null,null],
  }));

test('selected structured SDK rejects a type-invalid complete 2xx through Common',
  {timeout:15000}, t => originalHttpSettlement(t, true, {
    outcome:'schema_invalid',wire:responseWire.replace('\\"low\\"','123'),
  }));

test('selected structured SDK records provider-reported zero usage',
  {timeout:15000}, t => originalHttpSettlement(t, true, {
    wire:responseWire.replace('"prompt_tokens":3,"completion_tokens":2',
      '"prompt_tokens":0,"completion_tokens":0'), usage:[0,0],
  }));

test('selected structured SDK preserves absent usage separately from reported zero',
  {timeout:15000}, t => originalHttpSettlement(t, true, {
    wire:responseWire.replace(',"usage":{"prompt_tokens":3,"completion_tokens":2}',''),
    usage:[null,null],
  }));

for (const [finish,outcome,usage] of [
  ['length','truncated',{prompt_tokens:5,completion_tokens:7}],
  ['refusal','refusal',{prompt_tokens:0}],
]) {
  test('registered SDK settles saved '+finish+' and retains actual failure usage',
    {timeout:15000}, t => {
      const reply=JSON.parse(responseWire);
      reply.usage=usage;
      if(finish==='refusal') {
        delete reply.system_fingerprint;
        reply.choices[0].message.content=null;
        reply.choices[0].message.refusal='controlled refusal';
      } else {
        reply.choices[0].finish_reason=finish;
      }
      return originalHttpSettlement(t,'registered',{outcome,wire:JSON.stringify(reply),
        usage:[usage.prompt_tokens??null,usage.completion_tokens??null]});
    });
}

test('selected structured SDK keeps a truncated provider response unknown',
  {timeout:15000}, t => originalHttpSettlement(t, true, {loseResponse:true}));

async function originalHttpSettlement(t, structuredSdk, {refuseRaw=false, loseResponse=false,
  status=200, contentType='application/json', outcome, wire=responseWire, usage=[3,2],
  foreignRegisteredProfile=false, excludeReportedMetadata=false, overrideCompletion} = {}) {
    const calls=[],sockets=new Set();
    const server=createServer(async(request,response)=>{
      let body='';
      for await(const chunk of request)body+=chunk.toString('utf8');
      calls.push({method:request.method,path:request.url,body});
      response.sendDate=false;
      response.setHeader('content-type',contentType);
      response.setHeader('connection','close');
      response.statusCode=status;
      if (loseResponse) {
        response.setHeader('content-length',Buffer.byteLength(wire));
        response.write(wire.slice(0, 8), () => response.destroy());
      } else {
        response.end(wire);
      }
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
    const refusal = new Error('FixtureRawConfirmationUnavailable');
    const reportedFailure=structuredSdk==='registered' && ['truncated','refusal'].includes(outcome);
    let observedSettlement;
    const f=await originalSdkCommonFixture(t,moon,{physical:{endpoint,fetch},structuredSdk,foreignRegisteredProfile,
      excludeReportedMetadata, overrideCompletion,
      observeSettlement:reportedFailure ? value=>{observedSettlement=value;} : undefined,
      beforeOriginalRead({read}) {
        if (refuseRaw && read === 2) throw refusal;
      }});
    if (foreignRegisteredProfile) {
      assert.equal(calls.length,0);
      assert.equal(sockets.size,0);
      return;
    }
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
    if (refuseRaw || loseResponse || overrideCompletion!==undefined) {
      await assert.rejects(f.operation.run(), {code:'MoonBitHostFailure'});
      if (refuseRaw) assert.equal(f.ports[0].rawFailure(),refusal);
      if (overrideCompletion!==undefined) assert.equal(f.ports[0].rawFailure()?.code,'MoonBitHostFailure');
      assert.equal(f.originalReads(),2);
      assert.equal(calls.length,1);
      assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,'EnteredUnknown');
      assert.equal(f.operation.acquireOutput(),undefined);
      // The installed driver observes the same failed flight without starting
      // another invocation or acknowledging the uncertain remote outcome.
      await assert.rejects(f.operation.run(), {code:'MoonBitHostFailure'});
    } else {
      await assertOriginalSettlement(f,capture,calls,structuredSdk,outcome,usage,
        reportedFailure ? ()=>observedSettlement : undefined, excludeReportedMetadata);
    }
    assert.equal(calls.length,1,'Settlement must not repeat the original physical request');
    const firstCaptureCleanup=await capture.custody.cleanup();
    assert.equal(calls.length,1);
    if (firstCaptureCleanup !== true) {
      assert.equal(firstCaptureCleanup,false);
      await until(()=>capture.custody.cleanup(),value=>value===true);
    }
    const firstContinuationCleanup=await f.opened.cleanup();
    if (reportedFailure) {
      assert.equal(firstCaptureCleanup,true);
      assert.equal(firstContinuationCleanup,true);
    }
    assert.equal(calls.length,1);
    if (firstContinuationCleanup !== true) {
      assert.equal(firstContinuationCleanup,false);
      await until(()=>f.opened.cleanup(),value=>value===true);
    }
    t.diagnostic('First cleanup capture='+firstCaptureCleanup+
      ', continuation='+firstContinuationCleanup);
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
    t.diagnostic('Actual loopback/SDK/Common/raw Store/SQLite; synthetic funding and private Host fixture');
}

async function assertOriginalSettlement(f,capture,calls,structuredSdk,outcome,usage,readSettlement,excludeReportedMetadata) {
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
    const captureWire=moon.strategyRunEvidenceJson(f.operation.issuedSlotCapture(0));
    const record=JSON.parse(captureWire);
    assert.equal(record.outcome,outcome===undefined?'ok':'failed:'+outcome);
    let accountingWire;
    if (structuredSdk) {
      accountingWire=moon.strategyRunEvidenceJson(
        moon.clientProgramInferAttemptLeaf(f.operation.attemptEvidence(0),'accounting'));
      const accounting=JSON.parse(accountingWire);
      assert.deepEqual([accounting.input_tokens,accounting.output_tokens],usage);
    }
    if (structuredSdk && outcome===undefined) {
      const exporter=checked(moon.clientProgramStartInferCallSettlementExport(
        boundary.settlement,65536,100000));
      try {
        let wire='';
        await until(()=> {
          const progress=checked(moon.clientProgramAdvanceInferCaptureExport(exporter,256));
          wire+=runtimeField(progress,1);
          return runtimeField(progress,0);
        },Boolean);
        const bundle=JSON.parse(wire);
        assert.equal(bundle.captures.length,1);
        assert.deepEqual(bundle.captures[0].structured_response,{reason:null,risk:'low'});
        const evidence=bundle.captures[0].evidence;
        assert.match(evidence.raw_response_artifact_cid,/^sha256:[a-f0-9]{64}$/u);
        assert.deepEqual([evidence.input_tokens,evidence.output_tokens],usage);
        assert.equal(evidence.provider_reported_model_id,'reported-model');
        assert.equal(evidence.provider_request_id,'original-http-response');
        assert.equal(evidence.finish_reason,'stop');
        assert.deepEqual(evidence.provider_metadata,excludeReportedMetadata ? null :
          {system_fingerprint:'fp_observed'});
      } finally {
        assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(exporter)),true);
      }
    }
    const saved=await capture.persistSettlement(boundary.settlement,entry);
    const expected=outcome===undefined?'SavedSuccess':'SavedFailure';
    assert.equal(saved.state,expected);
    if (readSettlement!==undefined) {
      const proofCid=f.control.modelScopedPrivateHoldingCid(f.plan.runDefinition,
        f.storeAuthorityCid,entry,'model_attempt_outcome','settled');
      const proof=await f.store.inspectPhysicalHolding(proofCid);
      assert.equal(proof.manifest_cid,record.outcome_evidence_cid);
      const wire=Buffer.from(await f.store.readPrivateEvidence('model_attempt_outcome',proof.manifest_cid,proofCid));
      const body=JSON.parse(wire.toString('utf8'));
      assert.equal(body.version,'actql-model-attempt-outcome/0.1');
      const report=body.reported_response;
      const rawHoldingCid=f.control.modelScopedPrivateHoldingCid(f.plan.runDefinition,
        f.storeAuthorityCid,entry,'model_raw_response','entered');
      const raw=await f.store.inspectPhysicalHolding(rawHoldingCid);
      assert.deepEqual(report,{
        raw_response_artifact_cid:raw.manifest_cid,
        response_profile_cid:JSON.parse(f.profileWire).self_cid,
        observed_at:'2026-10-12T00:00:00.000Z',
        provider_reported_model_id:'reported-model',
        provider_request_id:'original-http-response',
        finish_reason:outcome==='truncated'?'length':'stop',
        response_complete:false,
        ...(outcome==='truncated' ? {provider_metadata:{system_fingerprint:'fp_observed'}} : {}),
      });
      const rawWire=await f.store.readModelRawResponseDescriptor(raw.manifest_cid,rawHoldingCid,
        (_bytes,owned)=>owned.releaseBytes());
      await assertSavedReportBinding(readSettlement(),body,record,accountingWire,rawWire);
    }
    assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,expected);
    assert.ok(await f.operation.run());
}

async function assertSavedReportBinding(original, outcome, capture, accounting, rawWire) {
  const runtime=await loadCheckpointRuntime();
  const seal=(name, {self_cid: _self, ...body}) =>
    moon.strategyRunEvidenceJson(checked(moon.strategyRunEvidenceSeal(name,
      JSON.stringify(body),16384,256,8)));
  const admit=(savedOutcome, savedCapture, raw)=>JSON.parse(runtime.modelSavedCallAdmit(
    JSON.stringify(original.originals),original.entry.ordinal,original.attemptWire,
    original.authorityWire,accounting,savedOutcome,savedCapture,undefined,raw));
  const outcomeWire=seal('model_attempt_outcome',outcome);
  const captureWire=seal('model_slot_capture',capture);
  assert.equal(admit(outcomeWire,captureWire,rawWire).state,'SavedFailure');
  assert.equal(admit(outcomeWire,captureWire,undefined).detail,'InvalidModelSavedRawObservation');
  for (const change of [
    {response_profile_cid:'sha256:'+'f'.repeat(64)},
    {raw_response_artifact_cid:'sha256:'+'f'.repeat(64)},
    {observed_at:'2026-10-12T00:00:01.000Z'},
  ]) {
    const otherOutcome=seal('model_attempt_outcome',
      {...outcome,reported_response:{...outcome.reported_response,...change}});
    const otherCapture=seal('model_slot_capture',
      {...capture,outcome_evidence_cid:JSON.parse(otherOutcome).self_cid});
    assert.equal(admit(otherOutcome,otherCapture,rawWire).detail,'InvalidModelSavedRawObservation');
  }
}
