// Actual Common, pinned SDK, original Undici HTTP, encrypted Store and SQLite.
// All policy/layout amounts remain explicit synthetic fixture declarations.
// No normal profile, public Client/Named Result or external Provider is tested.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHook} from 'node:async_hooks';
import {createServer} from 'node:http';
import {createServer as createTlsServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {createHash} from 'node:crypto';
import {setImmediate as turn} from 'node:timers/promises';
import {pathToFileURL} from 'node:url';
import {createOriginalUndiciFetch, prepareOriginalUndiciFetch} from '@actql/local-node/_internal/model-http-transport';
import {directLoopbackHttpFetch, originalHttpCommonFixture, originalSdkCommonFixture} from './infer-original-sdk-common.fixture.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {loadCheckpointRuntime} from './checkpoint-runtime.mjs';

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
    directChat:true, status:503, contentType:'text/plain', wire:'Controlled provider unavailable',
    outcome:'provider_error', usage:[null,null],
  }));

test('direct Chat HTTP retains an incomplete non-JSON refusal as the original unknown attempt',
  {timeout:15000}, t => originalHttpSettlement(t, false, {
    directChat:true, status:503, contentType:'text/plain', wire:'Controlled provider unavailable', loseResponse:true,
  }));

test('registered Chat SDK retains an incomplete non-JSON refusal as the original unknown attempt',
  {timeout:15000}, t => originalHttpSettlement(t, true, {
    status:503, contentType:'text/plain', wire:'Controlled provider unavailable', loseResponse:true,
  }));

test('direct Chat HTTPS saves the typed answer and Raw after one original credential read and OS lookup',
  {timeout:15000}, t => originalHttpSettlement(t, false, {directChat:true, tlsCredential:'exact'}));

test('direct Chat HTTPS keeps incomplete Raw on the original Unknown attempt',
  {timeout:15000}, t => originalHttpSettlement(t, false, {
    directChat:true, tlsCredential:'exact', status:503, contentType:'text/plain',
    wire:'Controlled provider unavailable', loseResponse:true,
  }));

test('direct Chat HTTPS refuses a missing credential before the original Entry or any connection',
  {timeout:15000}, t => originalHttpSettlement(t, false, {directChat:true, tlsCredential:'absent'}));

async function prepareTlsFixture(t, credential) {
  if (credential === undefined) return undefined;
  const fixture = await mkdtemp(join(tmpdir(), 'actql-direct-chat-tls-'));
  const key = join(fixture, 'key.pem'), cert = join(fixture, 'cert.pem');
  t.after(() => rm(fixture, {recursive:true, force:true}));
  execFileSync('openssl', ['req','-x509','-newkey','rsa:2048','-nodes','-days','1',
    '-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost','-keyout',key,'-out',cert],
    {stdio:'ignore',timeout:10000});
  const certificate = await readFile(cert, 'utf8');
  const trusted = getCACertificates('default');
  const environment = process.env;
  const reference = 'ACTQL_TEST_DIRECT_CHAT_COMMON_KEY';
  const secret = 'actql-controlled-direct-chat-key';
  assert.equal(environment[reference], undefined);
  let lookupOriginal, lookupStarted = 0, lookupCompleted = 0;
  const lookup = createHook({
    init(id, type) {
      if (type !== 'GETADDRINFOREQWRAP') return;
      lookupStarted++;
      if (lookupStarted === 1) lookupOriginal = id;
    },
    after(id) {
      if (id === lookupOriginal) lookupCompleted++;
    },
  }).enable();
  t.after(() => {
    lookup.disable();
    process.env = environment;
    delete environment[reference];
    setDefaultCACertificates(trusted);
  });
  setDefaultCACertificates([...trusted, certificate]);
  if (credential === 'exact') environment[reference] = secret;
  let reads = 0;
  process.env = new Proxy(environment, {get(target, name, receiver) {
    if (name === reference) reads++;
    return Reflect.get(target, name, receiver);
  }});
  return {server: {key: await readFile(key), cert: certificate}, reference, secret,
    placeholder:'actql-unbound-proof', reads:() => reads, lookup:() => [lookupStarted, lookupCompleted]};
}

test('selected structured SDK settles the original verified Raw through Common and the journal',
  {timeout:15000}, t => originalHttpSettlement(t, true));

test('registered SDK omits reported metadata excluded by its original Response Profile',
  {timeout:15000}, t => originalHttpSettlement(t,true,{excludeReportedMetadata:true}));

test('registered SDK rejects a separate equal profile before Entry and transport',
  {timeout:15000}, t => originalHttpSettlement(t, true, {foreignRegisteredProfile:true}));

for (const [name,flag] of [['false',false],['missing',undefined]]) {
  test('Common refuses a saved callback answer with '+name+' completion',
    {timeout:15000}, t => originalHttpSettlement(t,true,{overrideCompletion:()=>flag}));
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
  ['content_filter','safety_rejected',{prompt_tokens:5,completion_tokens:7}],
]) {
  test('registered SDK settles saved '+finish+' and retains actual failure usage',
    {timeout:15000}, t => {
      const reply=JSON.parse(responseWire);
      reply.usage=usage;
      if (finish==='refusal' || finish==='content_filter') {
        delete reply.system_fingerprint;
        reply.choices[0].message.content=null;
        reply.choices[0].message.refusal=finish==='refusal'?'controlled refusal':null;
      }
      if (finish!=='refusal') reply.choices[0].finish_reason=finish;
      return originalHttpSettlement(t,true,{outcome,wire:JSON.stringify(reply),
        usage:[usage.prompt_tokens??null,usage.completion_tokens??null], report:{
          provider_reported_model_id:'reported-model',provider_request_id:'original-http-response',
          finish_reason:finish==='refusal'?'stop':finish,
          ...(finish==='length'?{provider_metadata:{system_fingerprint:'fp_observed'}}:{}),
        }});
    });
}

for (const [reason,response,usage] of [
  ['RECITATION',{candidates:[{index:0,finishReason:'RECITATION'}],
    usageMetadata:{promptTokenCount:0,candidatesTokenCount:0,totalTokenCount:0}},[0,0]],
  ['BLOCKLIST',{promptFeedback:{blockReason:'BLOCKLIST'}},[null,null]],
]) {
  test('registered Google SDK saves '+reason+' as safety rejection',
    {timeout:15000}, t => originalHttpSettlement(t,true,{
      google:true,outcome:'safety_rejected',usage,
      wire:JSON.stringify({modelVersion:'reported-google',responseId:'original-google-response',...response}),
      report:{provider_reported_model_id:'reported-google',provider_request_id:'original-google-response',
        finish_reason:reason},
    }));
}

test('selected structured SDK keeps a truncated provider response unknown',
  {timeout:15000}, t => originalHttpSettlement(t, true, {loseResponse:true}));

async function originalHttpSettlement(t, structuredSdk, {refuseRaw=false, loseResponse=false, directChat=false,
  status=200, contentType='application/json', outcome, wire=responseWire, usage=[3,2], google=false, report,
  foreignRegisteredProfile=false, excludeReportedMetadata=false, overrideCompletion, tlsCredential} = {}) {
    assert(!directChat || !google);
    const tls = await prepareTlsFixture(t, tlsCredential);
    const calls=[],sockets=new Set(),clientSockets=new Set();
    let tcpConnections = 0, tlsConnections = 0, peerServerName = null;
    const partial = directChat && loseResponse ? Buffer.from('Controll') : undefined;
    let observedPrefix;
    const prefixReceived = partial === undefined ? undefined : new Promise(resolve => { observedPrefix = resolve; });
    const reply = async (request, response) => {
      if (tls !== undefined) {
        assert.equal(request.headers.authorization, 'Bearer ' + tls.secret);
        assert.equal(request.headers.host, 'localhost:' + server.address().port);
      }
      let body='';
      for await(const chunk of request)body+=chunk.toString('utf8');
      calls.push({method:request.method,path:request.url,body});
      response.sendDate=false;
      response.setHeader('content-type',contentType);
      response.setHeader('connection','close');
      response.statusCode=status;
      if (loseResponse) {
        response.setHeader('content-length',Buffer.byteLength(wire));
        if (partial === undefined) {
          response.write(wire.slice(0, 8), () => response.destroy());
        } else {
          response.write(partial);
          // Close only after the same physical reader receives these bytes.
          await prefixReceived;
          response.destroy();
        }
      } else {
        response.end(wire);
      }
    };
    const server = tls === undefined ? createServer(reply) : createTlsServer(tls.server, reply);
    if (tls !== undefined) server.on('secureConnection', socket => {
      tlsConnections++;
      peerServerName = socket.servername || null;
    });
    server.on('connection',socket=>{
      tcpConnections++;
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
    const modelId=google?'gemini-2.5-flash':'gpt-4.1-nano';
    const path=google?'/v1beta/models/'+modelId+':generateContent':'/v1/chat/completions';
    const endpoint=`${tls === undefined ? 'http://127.0.0.1' : 'https://localhost'}:${server.address().port}${path}`;
    const fetch=structuredSdk || directChat ? createOriginalUndiciFetch({endpoint,
      requestLimits:{maxBytes:1000,maxHeaderBytes:4096,maxHeaders:16},
      responseLimits:{maxBytes:2048,maxChunkBytes:512,maxChunks:16,
        maxHeaderBytes:128,observedHeaders:['content-type']},
      physicalAcquisitionLimits:{maxPlaintextBytes:65536,
        maxBorrowedBackingBytes:131072,maxReads:64},
      ...(tls === undefined ? {} : {registeredCredential:{endpoint, reference:tls.reference,
        header:'authorization',prefix:'Bearer ',placeholder:tls.placeholder,maxBytes:128}})}) : directLoopbackHttpFetch(endpoint,clientSockets);
    const refusal = new Error('FixtureRawConfirmationUnavailable');
    const reportedFailure=report!==undefined;
    let observedSettlement;
    const originalFixture = structuredSdk ? originalSdkCommonFixture : originalHttpCommonFixture;
    const physical = directChat ? {endpoint, credentialHeader: tls === undefined ? undefined : 'Bearer ' + tls.placeholder,
      prepareTransport(url, init, limits, controller) {
      const original = prepareOriginalUndiciFetch(fetch, url, init, limits, controller);
      if (partial === undefined) return original;
      return Object.freeze({...original, async invoke() {
        const response = await original.invoke();
        return Object.freeze({...response, body: Object.freeze({...response.body, getReader() {
          const reader = response.body.getReader();
          return Object.freeze({...reader, async read() {
            const next = await reader.read();
            if (!next.done) observedPrefix();
            return next;
          }});
        }})});
      }});
    }} : {endpoint, fetch};
    const f=await originalFixture(t,moon,{physical,foreignRegisteredProfile,
      google,modelId,excludeReportedMetadata, overrideCompletion,
      observeSettlement:reportedFailure ? value=>{observedSettlement=value;} : undefined,
      beforeOriginalRead({read}) {
        if (refuseRaw && read === 2) throw refusal;
      }});
    if (!structuredSdk) assert.equal(JSON.parse(f.profileWire).adapter.sdk,null);
    if (foreignRegisteredProfile) {
      assert.equal(calls.length,0);
      assert.equal(sockets.size,0);
      return;
    }
    assert.equal(f.sends,undefined,'Do not reuse the uninstrumented fixture counter');
    assert.equal(calls.length,0);
    if (tls !== undefined) {
      assert.deepEqual([tls.reads(), tcpConnections, tlsConnections], [0, 0, 0]);
      assert.deepEqual(tls.lookup(), [0, 0]);
      if (tlsCredential === 'absent') {
        await assert.rejects(f.opened.authorize(), {code:'ModelProjectCredentialUnavailable'});
        await assert.rejects(f.opened.authorize(), {code:'ModelProjectCredentialUnavailable'});
        assert.deepEqual([tls.reads(), tcpConnections, tlsConnections, calls.length], [1, 0, 0, 0]);
        assert.deepEqual(tls.lookup(), [0, 0]);
        assert.equal(f.opened.entry(0), undefined);
        assert.equal(f.cp.journal.getRunState('original-sdk-common'), undefined);
        assert.equal(f.originalReads(), 1);
        await f.operation.stop();
        await until(()=>f.operation.cleanup(), value=>value===true);
        assert.equal(await f.opened.cleanup(), true);
        finishRead(f);
        t.diagnostic('Missing direct credential: one read, Entry/TCP/TLS/POST0, original cleanup returned');
        return;
      }
    }
    assert.deepEqual(await f.opened.authorize(),{status:'dispatch'});
    assert.equal(calls.length,0,'Authorization is not transport start');
    if (tls !== undefined) {
      assert.deepEqual([tls.reads(), tcpConnections, tlsConnections], [1, 0, 0]);
      assert.equal(f.opened.entry(0), undefined);
    }
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
      if (partial !== undefined) {
        const entry = f.opened.entry(0);
        assert(entry);
        const raw = await assertOriginalChatRaw(f, entry, partial, status, false);
        t.diagnostic('Selected original incomplete Raw ' + JSON.stringify(raw));
      }
      // The installed driver observes the same failed flight without starting
      // another invocation or acknowledging the uncertain remote outcome.
      await assert.rejects(f.operation.run(), {code:'MoonBitHostFailure'});
    } else {
      await assertOriginalSettlement(f,capture,calls,{structuredSdk,outcome,usage,path,modelId,google,
        report,wire,directChat,status,readSettlement:()=>observedSettlement,excludeReportedMetadata});
    }
    assert.equal(calls.length,1,'Settlement must not repeat the original physical request');
    const firstCaptureCleanup=await capture.custody.cleanup();
    assert.equal(calls.length,1);
    if (firstCaptureCleanup !== true) {
      assert.equal(firstCaptureCleanup,false);
      await until(()=>capture.custody.cleanup(),value=>value===true);
    }
    const firstContinuationCleanup=await f.opened.cleanup();
    if (reportedFailure || directChat) {
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
    finishRead(f);
    await until(()=>sockets.size+clientSockets.size,value=>value===0);
    assert.equal(calls.length,1);
    if (tls !== undefined) {
      assert.deepEqual([tls.reads(), tcpConnections, tlsConnections], [1, 1, 1]);
      assert.deepEqual(tls.lookup(), [1, 1]);
      assert.equal(peerServerName, 'localhost');
      t.diagnostic('Exact direct credential: one read, one TCP/TLS/POST and original peer retired');
    }
    t.diagnostic('Actual loopback/' + (directChat ? 'direct HTTP' : 'SDK') +
      '/Common/raw Store/SQLite; synthetic funding and private Host fixture');
}

function finishRead(f) {
  const original = f.originalPreparation;
  f.control.stopCheckedClientInferOriginalReadPreparation(f.plan.compiled,
    f.plan.runDefinition,f.plan.inferGraph,original.scope,original.read);
  f.control.settleCheckedClientInferOriginalReadPreparation(f.plan.compiled,
    f.plan.runDefinition,f.plan.inferGraph,original.read,true);
  assert.equal(f.control.finishCheckedClientInferOriginalReadScope(f.plan.compiled,
    f.plan.runDefinition,f.plan.inferGraph,original.scope,true),true);
}

async function assertOriginalChatRaw(f, entry, expectedBytes, status, eof) {
  const holdingCid = f.control.modelScopedPrivateHoldingCid(f.plan.runDefinition,
    f.storeAuthorityCid, entry, 'model_raw_response', 'entered');
  const holding = await f.store.inspectPhysicalHolding(holdingCid);
  assert(holding);
  const semanticCid = holding.manifest_cid;
  const wire = await f.store.readModelRawResponseDescriptor(semanticCid, holdingCid, async (_bytes, owned) => {
    const original = owned.releaseBytes();
    await owned.confirm({name: 'model_raw_descriptor', semanticCid, holdingCid, wire: original});
    return original;
  });
  const original = JSON.parse(wire);
  assert.equal(original.self_cid, semanticCid);
  assert.equal(original.attempt_cid, entry.attemptCid);
  assert.equal(original.slot_cid, entry.slotCid);
  assert.equal(original.scope_cid, entry.scopeCid);
  assert.equal(original.run_definition_cid, entry.runDefinitionCid);
  assert.equal(original.response_profile_cid, JSON.parse(f.profileWire).self_cid);
  assert.equal(original.store_authority_cid, f.storeAuthorityCid);
  assert.equal(original.http_status, status);
  assert.equal(original.transport_eof, eof);
  const contentCid = 'sha256:' + createHash('sha256').update(expectedBytes).digest('hex');
  assert.equal(original.content_cid, contentCid);
  assert.equal(original.byte_count, expectedBytes.byteLength);
  const confirmed = await f.store.confirmModelRawEvidence({semanticCid, holdingCid, wire, contentCid, byteCount: expectedBytes.byteLength});
  assert.deepEqual(confirmed.bytes, expectedBytes);
  return {attempt: entry.attemptCid, slot: entry.slotCid, definition: entry.runDefinitionCid,
    scope: entry.scopeCid, profile: original.response_profile_cid, holding: holdingCid,
    descriptor: semanticCid, content: contentCid, bytes: expectedBytes.byteLength, httpStatus: status,
    transportEof: original.transport_eof};
}

async function assertOriginalSettlement(f,capture,calls,{structuredSdk,outcome,usage,path,modelId,google,
  report,wire,directChat,status,readSettlement,excludeReportedMetadata}) {
    const boundary=await f.operation.run();
    assert.equal(boundary.status,'settling');
    assert.equal(calls.length,1);
    assert.deepEqual({method:calls[0].method,path:calls[0].path},
      {method:'POST',path});
    if (!google) assert.equal(JSON.parse(calls[0].body).model,modelId);
    assert.equal(f.originalReads(),2,'Actual Store rechecks originals after transport');
    const entry=f.opened.entry(0);
    assert.ok(entry);
    assert.equal(f.cp.journal.readModelCalls(f.opened.inventory).slots[0].state,'EnteredUnknown',
      'A saved raw response alone is not the settled slot');
    const directRaw = directChat
      ? await assertOriginalChatRaw(f, entry, Buffer.from(wire), status, true)
      : undefined;
    const captureWire=moon.strategyRunEvidenceJson(f.operation.issuedSlotCapture(0));
    const record=JSON.parse(captureWire);
    assert.equal(record.outcome,outcome===undefined?'ok':'failed:'+outcome);
    let accountingWire;
    if (structuredSdk || directChat) {
      accountingWire=moon.strategyRunEvidenceJson(
        moon.clientProgramInferAttemptLeaf(f.operation.attemptEvidence(0),'accounting'));
      const accounting=JSON.parse(accountingWire);
      assert.deepEqual([accounting.input_tokens,accounting.output_tokens],usage);
    }
    if ((structuredSdk || directChat) && outcome===undefined) {
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
        assert.deepEqual(evidence.provider_metadata,excludeReportedMetadata || directChat ? null :
          {system_fingerprint:'fp_observed'});
        if (directChat) assert.equal(evidence.raw_response_artifact_cid, directRaw.descriptor);
      } finally {
        assert.equal(checked(moon.clientProgramCleanupInferCaptureExport(exporter)),true);
      }
    }
    const saved=await capture.persistSettlement(boundary.settlement,entry);
    const expected=outcome===undefined?'SavedSuccess':'SavedFailure';
    assert.equal(saved.state,expected);
    if (report!==undefined) {
      const proofCid=f.control.modelScopedPrivateHoldingCid(f.plan.runDefinition,
        f.storeAuthorityCid,entry,'model_attempt_outcome','settled');
      const proof=await f.store.inspectPhysicalHolding(proofCid);
      assert.equal(proof.manifest_cid,record.outcome_evidence_cid);
      const savedWire=Buffer.from(await f.store.readPrivateEvidence('model_attempt_outcome',proof.manifest_cid,proofCid));
      const body=JSON.parse(savedWire.toString('utf8'));
      assert.equal(body.version,'actql-model-attempt-outcome/0.1');
      assert.equal(body.failure,outcome);
      const rawHoldingCid=f.control.modelScopedPrivateHoldingCid(f.plan.runDefinition,
        f.storeAuthorityCid,entry,'model_raw_response','entered');
      const raw=await f.store.inspectPhysicalHolding(rawHoldingCid);
      assert.deepEqual(body.reported_response,{
        raw_response_artifact_cid:raw.manifest_cid,
        response_profile_cid:JSON.parse(f.profileWire).self_cid,
        observed_at:'2026-10-12T00:00:00.000Z',
        response_complete:false,
        ...report,
      });
      const rawWire=await f.store.readModelRawResponseDescriptor(raw.manifest_cid,rawHoldingCid,
        (_bytes,owned)=>owned.releaseBytes());
      const descriptor=JSON.parse(rawWire);
      assert.equal(descriptor.self_cid,raw.manifest_cid);
      assert.equal(descriptor.http_status,200);
      assert.equal(descriptor.transport_eof,true);
      assert.equal(descriptor.byte_count,Buffer.byteLength(wire));
      assert.equal(descriptor.content_cid,'sha256:'+createHash('sha256').update(wire).digest('hex'));
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
