import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as turn} from 'node:timers/promises';
import {createServer} from 'node:http';
import {createHttpChatPreflight} from './_internal/model-port.mjs';
import {createInferIoNotification, claimInferIoNotification} from '../../adapters/host-node/infer-io-notification.mjs';

async function until(read, accept) {
  for (let i=0;i<80;i++) { const value=read(); if(accept(value))return value; await turn(); }
  assert.fail('Finite original HTTP physical observation not reached');
}
const body='{"model":"fixture","n":1,"stream":false}';
const wire='{"id":"observed","choices":[{"index":0,"message":{"content":"{\\"ok\\":true}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":0}}';
const bytes=new TextEncoder().encode(wire);
function fixture(extra={}) {
  const request={},provider={},entry={},saved=Object.freeze({originalSaved: true});
  const responseProfile = {};
  let sends=0,saves=0,cleanupAllowed=false,lastRaw;
  const moon={
    clientProgramModelResponseProfileTransportMatches(profile, ...limits) {
      assert.strictEqual(profile, responseProfile);
      assert.deepEqual(limits, [4096, 512, 512, 2, 64]);
      return true;
    },
    clientProgramProjectHTTPChatRequest(p,r,model,...bounds){
      assert.equal(p,provider);assert.equal(r,request);assert.equal(model,'fixture');
      assert.deepEqual(bounds,[4096,256,16,32,4096]);
      return {$tag:1,_0:{_0:body,_1:'task',_2:'prompt',_3:'schema',_4:'selector'}};
    },
    clientProgramModelRequestPreflight:(advance,cleanup)=>({advance,cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan(r,wireBytes,tokens,cost,duration,profile,installation,start){
      assert.equal(r,request);assert.equal(wireBytes,BigInt(Buffer.byteLength(body)));
      assert.equal(tokens,16n);return {start};
    },
    clientProgramModelPhysicalCallForRequest(e,r,poll,cancel,cleanup){
      assert.equal(e,entry);assert.equal(r,request);return {poll,cancel,cleanup};
    },
    clientProgramModelPhysicalPending:()=>({kind:'pending'}),
    clientProgramModelPhysicalUnknown:()=>({kind:'unknown'}),
    clientProgramModelPhysicalSavedChat:response=>({kind:'chat',response}),
    clientProgramReadReconciledInferRawUsage:(call,view,quantum)=>({call,view,quantum}),
  };
  const args={moon,admittedProvider:provider,request,modelId:'fixture',
    taskCid:'task',promptCid:'prompt',outputSchemaCid:'schema',modelSelector:'selector',
    projectionLimits:{maxBytes:4096,maxNodes:256,maxDepth:16,maxFrames:32,maxWork:4096},
    endpoint:'https://fixture.invalid/chat',headers:[['content-type','application/json']],
    requestLimits:{maxBytes:4096,maxHeaderBytes:128,maxHeaders:4},
    responseLimits:{maxBytes:512,maxChunkBytes:512,maxChunks:2,maxHeaderBytes:64,
      observedHeaders:['content-type']},profile:responseProfile,installation:{sdk:undefined},
    quantities:{tokens:16n,costUnits:0n,durationMs:1n},
    fetch(endpoint,init){sends++;assert.equal(init.body,body);assert.equal(init.redirect,'error');
      return Promise.resolve(new Response(bytes,{headers:{'content-type':'application/json'}}));},
    persistRaw(call,raw){saves++;lastRaw=raw;return Promise.resolve({response:saved});},
    cleanupRaw:()=>cleanupAllowed,notify(){},observeAt:()=> '2026-10-13T00:00:00Z',checked:value=>value,
    ...extra,
  };
  const port=createHttpChatPreflight(args);
  return {args,port,entry,saved,sends:()=>sends,saves:()=>saves,raw:()=>lastRaw,
    allowCleanup(){cleanupAllowed=true;}};
}
async function finish(f){f.allowCleanup();await until(()=>f.port.preflight.cleanup(),v=>v===true);}

// Common/Entry/saved view are explicit boundary doubles. Node HTTP, bounded
// reader, original raw buffers and physical cleanup execute for real; no
// numerical grant, nominal Store receipt or public Named Result is established.
test('direct HTTP physical preflight refuses admitted bound mismatch before projection plan or raw binder', async t => {
  const f = fixture();
  t.after(() => finish(f));
  let matches = 0, projections = 0, bindings = 0;
  const moon = {...f.args.moon,
    clientProgramProjectHTTPChatRequest() { projections++; assert.fail('No projection before admission'); },
    clientProgramModelResponseProfileTransportMatches(profile, ...limits) {
      matches++;
      assert.strictEqual(profile, f.args.profile);
      assert.deepEqual(limits, [4096, 512, 512, 2, 64]);
      return false;
    },
  };
  assert.throws(() => createHttpChatPreflight({...f.args, moon,
    persistRaw: undefined, cleanupRaw: undefined, rawCaptureBinder() { bindings++; }}),
  {message: 'HTTPChatOriginalTransportLimitsMismatch'});
  assert.deepEqual({matches, projections, bindings, sends: f.sends()},
    {matches: 1, projections: 0, bindings: 0, sends: 0});
});

test('independent HTTP physical plan freezes request, starts once, saves same raw before release',async t=>{
  const f=fixture();t.after(()=>finish(f));
  const plan=f.port.preflight.advance()._1;
  assert.equal(f.sends(),0);const call=plan.start(f.entry);
  assert.equal(plan.start(f.entry),undefined);
  const result=await until(()=>call.poll(),v=>v.kind==='chat');
  assert.equal(result.response,f.saved);assert.equal(f.sends(),1);assert.equal(f.saves(),1);
  assert.deepEqual(f.raw().body,bytes);assert.equal(f.raw().body.buffer.byteLength,512);
  assert.equal(f.raw().transportComplete,true);
  assert.equal(call.cleanup(),false);call.cancel();assert.equal(call.cleanup(),false);
});
test('independent HTTP cancelled prefix remains incomplete while original read retains cleanup', async t => {
  let finishRead;
  let finishCancel;
  let reads = 0;
  let releases = 0;
  let sends = 0;
  let raw;
  const f = fixture({fetch() {
    sends++;
    return {status: 503, headers: new Headers(), body: {getReader() { return {
      read() {
        reads++;
        if (reads === 1) return Promise.resolve({done: false, value: new Uint8Array([65])});
        return new Promise(resolve => { finishRead = resolve; });
      },
      cancel() { return new Promise(resolve => { finishCancel = resolve; }); },
      releaseLock() { releases++; },
    }; }}};
  }, persistRaw(call, value) { raw = value; return Promise.resolve({response: f.saved}); }});
  t.after(async () => {
    finishRead?.({done: true}); finishCancel?.();
    await finish(f);
  });
  const plan = f.port.preflight.advance()._1;
  const call = plan.start(f.entry);
  await until(() => finishRead, value => typeof value === 'function');
  call.cancel();
  await until(() => { call.poll(); return raw; }, value => value !== undefined);
  assert.deepEqual(raw.body, new Uint8Array([65]));
  assert.equal(raw.observedBytes, 1);
  assert.equal(raw.transportComplete, false);
  assert.equal(raw.issue, 'InferResponseReadCancelled');
  assert.equal(raw.status, 503);
  assert.equal(call.cleanup(), false);
  finishCancel();
  for (let i = 0; i < 4; i++) await turn();
  assert.equal(call.cleanup(), false);
  assert.equal(releases, 0);
  finishRead({done: false, value: new Uint8Array([66])});
  await finish(f);
  assert.equal(releases, 1);
  assert.equal(reads, 2);
  assert.equal(sends, 1);
  assert.equal(plan.start(f.entry), undefined);
  assert.deepEqual(raw.body, new Uint8Array([65]));
  assert.equal(raw.transportComplete, false);
});
test('independent HTTP save backpressure retains raw and cancel is not cleanup ACK',async t=>{
  let completeSave,saves=0,raw;
  const waiting=new Promise(resolve=>{completeSave=resolve;});
  const f=fixture({persistRaw(call,value){saves++;raw=value;return waiting;}});
  t.after(async()=>{completeSave({response:f.saved});await finish(f);});
  const call=f.port.preflight.advance()._1.start(f.entry);
  await until(()=>{call.poll();return saves;},v=>v===1);
  assert.deepEqual(raw.body,bytes);assert.equal(call.cleanup(),false);
  call.cancel();assert.equal(call.poll().kind,'pending');assert.equal(call.cleanup(),false);
  completeSave({response:f.saved});
  await until(()=>call.poll(),v=>v.kind==='chat');assert.equal(f.sends(),1);
});
test('independent HTTP unknown save preserves one stable explicit reconciliation and never resends',async t=>{
  const failure=Error('OriginalStoreUnavailable');let saves=0,raw;
  const f=fixture({persistRaw(call,value){saves++;if(raw!==undefined)assert.equal(value,raw);
    raw=value;return saves===1?Promise.reject(failure):Promise.resolve({response:f.saved});}});
  t.after(()=>finish(f));
  const call=f.port.preflight.advance()._1.start(f.entry);
  await until(()=>call.poll(),v=>v.kind==='unknown');assert.equal(f.port.rawFailure(),failure);
  assert.equal(call.cleanup(),false);
  const first=f.port.reconcileRaw(call);const second=f.port.reconcileRaw(call);
  assert.equal(first,second);const saved=await first;assert.equal(saved.response,f.saved);
  assert.equal(call.poll().kind,'unknown','reconciliation is not a Host success rewrite');
  assert.equal(f.port.readReconciledUsage(call,1).view,f.saved);
  assert.equal(f.sends(),1);assert.equal(saves,2);
  await assert.rejects(f.port.reconcileRaw({...call}),/ReconciliationUnavailable/);
});
test('independent HTTP transport throw remains original unknown and one attempted start',async t=>{
  let attempts=0;
  const f=fixture({fetch(){attempts++;throw Error('UnconfirmedTransmission');}});
  t.after(()=>finish(f));const plan=f.port.preflight.advance()._1;const call=plan.start(f.entry);
  await until(()=>call.poll(),v=>v.kind==='unknown');
  assert.equal(plan.start(f.entry),undefined);assert.equal(attempts,1);assert.equal(f.saves(),0);
});
test('independent HTTP deferred raw binding cannot regain a consumed missing-binding attempt',async t=>{
  let bind;
  const f=fixture({persistRaw:undefined,cleanupRaw:undefined,
    rawCaptureBinder(callback){bind=callback;}});
  t.after(()=>finish(f));const plan=f.port.preflight.advance()._1;
  assert.equal(plan.start(f.entry),undefined);assert.equal(f.sends(),0);
  const persistence=()=>Promise.resolve({response:f.saved});persistence.cleanup=()=>true;
  bind({},persistence);assert.equal(plan.start(f.entry),undefined);assert.equal(f.sends(),0);
  assert.throws(()=>bind({},persistence),/RawBindingRefused/);
});
test('independent HTTP binder failure returns same rejected cleanup instead of losing a bound port',async t=>{
  let released=false,cleanups=0;
  const persistence=()=>{assert.fail('Rejected preparation cannot save');};
  persistence.cleanup=()=>{cleanups++;return released;};
  const f=fixture({persistRaw:undefined,cleanupRaw:undefined,
    rawCaptureBinder(bind){bind({},persistence);throw Error('BinderFailedAfterBinding');}});
  t.after(async()=>{released=true;await finish(f);});
  assert.deepEqual(f.port.preflight.advance(),{_0:true,_1:undefined});
  assert.equal(f.port.preflight.cleanup(),false);assert.equal(cleanups,1);assert.equal(f.sends(),0);
  released=true;assert.equal(f.port.preflight.cleanup(),true);
});
test('independent HTTP cancellation before preparation sends zero and keeps finite cleanup',async()=>{
  const controller=new AbortController();controller.abort();const f=fixture({signal:controller.signal});
  assert.deepEqual(f.port.preflight.advance(),{_0:true,_1:undefined});
  assert.equal(f.sends(),0);await finish(f);assert.equal(f.port.preflight.cleanup(),true);
});
test('independent HTTP cancellation after preparation before entered start sends zero',async t=>{
  const controller=new AbortController();const f=fixture({signal:controller.signal});
  t.after(()=>finish(f));const plan=f.port.preflight.advance()._1;
  controller.abort();const call=plan.start(f.entry);
  assert.equal(f.sends(),0);
  assert.equal(call.poll().kind,'unknown','local cancellation cannot reclassify an entered attempt');
  assert.equal(plan.start(f.entry),undefined);
});
test('independent HTTP uses two explicitly authorized loopback fixture endpoints without SDK',{timeout:5000},async t=>{
  const nativeFetch=globalThis.fetch;
  for(const tag of ['a','b']) {
    let requests=0;
    const server=createServer((req,res)=>{
      requests++;assert.equal(req.method,'POST');assert.equal(req.url,'/chat');
      let input='';req.setEncoding('utf8');req.on('data',chunk=>{input+=chunk;});
      req.on('end',()=>{assert.equal(input,body);res.writeHead(200,{'content-type':'application/json'});
        res.end(JSON.stringify({id:tag,choices:[{index:0,message:{content:'{"ok":true}'},finish_reason:'stop'}]}));});
    });
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
    t.after(()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();}));
    const endpoint=`http://127.0.0.1:${server.address().port}/chat`;
    const notification=createInferIoNotification();
    const wake=claimInferIoNotification(notification);t.after(()=>wake.close());
    let raw;
    const f=fixture({endpoint,fetch:(url,init)=>{assert.equal(url,endpoint);return nativeFetch(url,init);},
      notify:notification.notify,
      persistRaw(call,value){raw=value;return Promise.resolve({response:f.saved});}});
    t.after(()=>finish(f));const call=f.port.preflight.advance()._1.start(f.entry);
    let result;
    for(let i=0;i<8;i++) {
      const ticket=wake.arm();
      try {result=call.poll();if(result.kind==='chat')break;await ticket.promise;}
      finally {ticket.dispose();}
    }
    assert.equal(result.kind,'chat');
    assert.equal(requests,1);assert.equal(raw.status,200);assert.equal(raw.transportComplete,true);
    assert.equal(JSON.parse(new TextDecoder().decode(raw.body)).id,tag);
    await finish(f);
  }
});
