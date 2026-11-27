import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as turn} from 'node:timers/promises';
import {createServer} from 'node:http';
import {createHttpChatPreflight} from './_internal/model-port.mjs';
import {createOriginalUndiciFetch, prepareOriginalUndiciFetch} from '@actql/local-node/_internal/model-http-transport';
import {createInferIoNotification, claimInferIoNotification} from '../../adapters/host-node/infer-io-notification.mjs';

import type {AddressInfo} from 'node:net';

type Input = Parameters<typeof createHttpChatPreflight>[0];
type Persist = NonNullable<Input['persistRaw']>;
type Raw = Parameters<Persist>[1];
type FixtureRead = {done: true} | {done: false; value: Uint8Array};
type Bind = Parameters<NonNullable<Input['rawCaptureBinder']>>[0];
type Poll = ({kind: 'pending' | 'unknown'} | {kind: 'chat'; response: unknown}) & {ioRetired?: boolean};
type Call = {poll(): Poll; cancel(): void; cleanup(): boolean};
type Plan = {start(entry: unknown): Call | undefined};
type Port = Omit<ReturnType<typeof createHttpChatPreflight>,'preflight' | 'readReconciledUsage'> & {
  preflight: {advance(): {_0: boolean; _1?: Plan}; cleanup(): boolean};
  readReconciledUsage(original: unknown, quantum: number): {view: unknown};
};

async function until<Value>(read: () => Value, accept: (value: Value) => unknown): Promise<Value> {
  for (let i=0;i<80;i++) { const value=read(); if(accept(value))return value; await turn(); }
  assert.fail('Finite original HTTP physical observation not reached');
}
const body='{"model":"fixture","n":1,"stream":false}';
const wire='{"id":"observed","choices":[{"index":0,"message":{"content":"{\\"ok\\":true}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":0}}';
const bytes=new TextEncoder().encode(wire);
function fixture(extra: Partial<Input>={}) {
  const request={},provider={},entry={},saved=Object.freeze({originalSaved: true});
  const responseProfile = {};
  let sends=0,saves=0,cleanupAllowed=false,lastRaw: Raw | undefined;
  let originalCall: unknown;
  const moon: Input['moon']={
    clientProgramModelResponseProfileTransportMatches(profile, ...limits) {
      assert.strictEqual(profile, responseProfile);
      assert.deepEqual(limits, [4096, 512, 512, 2, extra.responseLimits?.maxHeaderBytes ?? 64]);
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
      assert.equal(e,entry);assert.equal(r,request);
      originalCall={poll,cancel,cleanup}; return originalCall;
    },
    clientProgramModelPhysicalPending:()=>({kind:'pending'}),
    clientProgramModelPhysicalUnknown:()=>({kind:'unknown'}),
    clientProgramModelPhysicalSavedChat:response=>({kind:'chat',response}),
    clientProgramModelPhysicalIoObservation(original, ioRetired, observed) {
      assert.strictEqual(original, originalCall);
      return {...(observed as Poll), ioRetired};
    },
    clientProgramReadReconciledInferRawUsage:(call,view,quantum)=>({call,view,quantum}),
  };
  const args: Input={moon,admittedProvider:provider,request,modelId:'fixture',
    taskCid:'task',promptCid:'prompt',outputSchemaCid:'schema',modelSelector:'selector',
    projectionLimits:{maxBytes:4096,maxNodes:256,maxDepth:16,maxFrames:32,maxWork:4096},
    endpoint:'https://fixture.invalid/chat',headers:[['content-type','application/json']],
    requestLimits:{maxBytes:4096,maxHeaderBytes:128,maxHeaders:4},
    responseLimits:{maxBytes:512,maxChunkBytes:512,maxChunks:2,maxHeaderBytes:64,
      observedHeaders:['content-type']},profile:responseProfile,installation:{sdk:undefined},
    quantities:{tokens:16n,costUnits:0n,durationMs:1n},
    fetch(endpoint,init){sends++;assert.equal((init as RequestInit).body,body);assert.equal((init as RequestInit).redirect,'error');
      return Promise.resolve(new Response(bytes,{headers:{'content-type':'application/json'}}));},
    persistRaw(call,raw){saves++;lastRaw=raw;return Promise.resolve({response:saved});},
    cleanupRaw:()=>cleanupAllowed,notify(){},observeAt:()=> '2026-10-13T00:00:00Z',checked:value=>value,
    ...extra,
  };
  const port=createHttpChatPreflight(args) as Port;
  return {args,port,entry,saved,sends:()=>sends,saves:()=>saves,raw:()=>lastRaw,
    allowCleanup(){cleanupAllowed=true;}};
}
async function finish(f: ReturnType<typeof fixture>){f.allowCleanup();await until(()=>f.port.preflight.cleanup(),v=>v===true);}

// Common/Entry/saved view are explicit boundary doubles. Node HTTP, bounded
// reader, original raw buffers and physical cleanup execute for real; no
// numerical grant, nominal Store receipt or public Named Result is established.
test('direct HTTP physical preflight refuses admitted bound mismatch before projection plan or raw binder', async t => {
  const f = fixture();
  t.after(() => finish(f));
  let matches = 0, projections = 0, bindings = 0;
  let originalCall: unknown;
  const moon: Input['moon'] = {...f.args.moon,
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
  const plan=f.port.preflight.advance()._1!;
  assert.equal(f.sends(),0);const call=plan.start(f.entry)!;
  assert.equal(plan.start(f.entry),undefined);
  const result=await until(()=>call.poll(),v=>v.kind==='chat');
  assert.equal((result as Extract<Poll,{kind:'chat'}>).response,f.saved);assert.equal(f.sends(),1);assert.equal(f.saves(),1);
  assert.deepEqual(f.raw()!.body,bytes);assert.equal(f.raw()!.body.buffer.byteLength,512);
  assert.equal(f.raw()!.transportComplete,true);
  assert.equal(call.cleanup(),false);call.cancel();assert.equal(call.cleanup(),false);
});
test('independent HTTP cancelled prefix remains incomplete while original read retains cleanup', async t => {
  let finishRead!: (value: FixtureRead) => void;
  let finishCancel!: () => void;
  let reads = 0;
  let releases = 0;
  let sends = 0;
  let raw: Raw | undefined;
  const f = fixture({fetch() {
    sends++;
    return {status: 503, headers: new Headers(), body: {getReader() { return {
      read() {
        reads++;
        if (reads === 1) return Promise.resolve({done: false, value: new Uint8Array([65])});
        return new Promise<FixtureRead>(resolve => { finishRead = resolve; });
      },
      cancel() { return new Promise<void>(resolve => { finishCancel = resolve; }); },
      releaseLock() { releases++; },
    }; }}};
  }, persistRaw(call, value) { raw = value; return Promise.resolve({response: f.saved}); }});
  t.after(async () => {
    finishRead?.({done: true}); finishCancel?.();
    await finish(f);
  });
  const plan = f.port.preflight.advance()._1!;
  const call = plan.start(f.entry)!;
  await until(() => finishRead, value => typeof value === 'function');
  call.cancel();
  await until(() => { call.poll(); return raw; }, value => value !== undefined);
  assert.deepEqual(raw!.body, new Uint8Array([65]));
  assert.equal(raw!.observedBytes, 1);
  assert.equal(raw!.transportComplete, false);
  assert.equal(raw!.issue, 'InferResponseReadCancelled');
  assert.equal(raw!.status, 503);
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
  assert.deepEqual(raw!.body, new Uint8Array([65]));
  assert.equal(raw!.transportComplete, false);
});
test('independent HTTP save backpressure retains raw and cancel is not cleanup ACK',async t=>{
  let completeSave!: (value: {response: unknown}) => void,saves=0,raw: Raw | undefined;
  const waiting=new Promise<{response: unknown}>(resolve=>{completeSave=resolve;});
  const f=fixture({persistRaw(call,value){saves++;raw=value;return waiting;}});
  t.after(async()=>{completeSave({response:f.saved});await finish(f);});
  const call=f.port.preflight.advance()._1!.start(f.entry)!;
  await until(()=>{call.poll();return saves;},v=>v===1);
  assert.deepEqual(raw!.body,bytes);assert.equal(call.cleanup(),false);
  call.cancel();assert.equal(call.poll().kind,'pending');assert.equal(call.cleanup(),false);
  completeSave({response:f.saved});
  await until(()=>call.poll(),v=>v.kind==='chat');assert.equal(f.sends(),1);
});
test('independent HTTP unknown save preserves one stable explicit reconciliation and never resends',async t=>{
  const failure=Error('OriginalStoreUnavailable');let saves=0,raw: Raw | undefined;
  const f=fixture({persistRaw(call,value){saves++;if(raw!==undefined)assert.equal(value,raw);
    raw=value;return saves===1?Promise.reject(failure):Promise.resolve({response:f.saved});}});
  t.after(()=>finish(f));
  const call=f.port.preflight.advance()._1!.start(f.entry)!;
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
  t.after(()=>finish(f));const plan=f.port.preflight.advance()._1!;const call=plan.start(f.entry)!;
  await until(()=>call.poll(),v=>v.kind==='unknown');
  assert.equal(plan.start(f.entry),undefined);assert.equal(attempts,1);assert.equal(f.saves(),0);
});
test('independent HTTP deferred raw binding cannot regain a consumed missing-binding attempt',async t=>{
  let bind!: Bind;
  const f=fixture({persistRaw:undefined,cleanupRaw:undefined,
    rawCaptureBinder(callback){bind=callback;}});
  t.after(()=>finish(f));const plan=f.port.preflight.advance()._1!;
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
  t.after(()=>finish(f));const plan=f.port.preflight.advance()._1!;
  controller.abort();const call=plan.start(f.entry)!;
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
    await new Promise<void>((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
    t.after(()=>new Promise<Error | undefined>(resolve=>{server.close(resolve);server.closeAllConnections();}));
    const endpoint=`http://127.0.0.1:${(server.address() as AddressInfo).port}/chat`;
    const notification=createInferIoNotification();
    const wake=claimInferIoNotification(notification);t.after(()=>wake.close());
    let raw: Raw | undefined;
    const f=fixture({endpoint,fetch:(url,init)=>{assert.equal(url,endpoint);return nativeFetch(url,init as RequestInit);},
      notify:notification.notify,
      persistRaw(call,value){raw=value;return Promise.resolve({response:f.saved});}});
    t.after(()=>finish(f));const call=f.port.preflight.advance()._1!.start(f.entry)!;
    let result;
    for(let i=0;i<8;i++) {
      const ticket=wake.arm();
      try {result=call.poll();if(result.kind==='chat')break;await ticket.promise;}
      finally {ticket.dispose();}
    }
    assert.equal(result!.kind,'chat');
    assert.equal(requests,1);assert.equal(raw!.status,200);assert.equal(raw!.transportComplete,true);
    assert.equal(JSON.parse(new TextDecoder().decode(raw!.body)).id,tag);
    await finish(f);
  }
});


test('selected HTTP port keeps its same unstarted child until actual retirement', async () => {
  type Prepared = NonNullable<ReturnType<NonNullable<Input['prepareTransport']>>>;
  let close!: (done: boolean) => void;
  const acknowledgement = new Promise<boolean>(resolve=>{close=resolve;});
  let prepared=0,cleanupCalls=0,invocations=0,rawCleanup=0,notifications=0;
  const original: Prepared = {
    invoke() { invocations++; return Promise.reject(Error('unexpected send')); },
    cleanup() {
      cleanupCalls++;
      if (cleanupCalls === 1) return Promise.resolve(false);
      if (cleanupCalls === 2) return Promise.reject(Error('retirement not confirmed'));
      return acknowledgement;
    },
  };
  const f=fixture({fetch:undefined,prepareTransport(){prepared++;return original;},
    cleanupRaw(){rawCleanup++;return true;}, notify(){notifications++;}});
  assert.throws(()=>createHttpChatPreflight({...f.args,fetch:globalThis.fetch as Input['fetch']}),
    {message:'InvalidHTTPChatPhysicalPort'});
  const plan=f.port.preflight.advance()._1!;
  try {
    assert.equal(prepared,1);
    assert.equal(f.port.preflight.cleanup(),false);
    assert.equal(plan.start(f.entry),undefined);
    assert.equal(f.port.preflight.advance()._1,undefined);
    await turn();
    assert.deepEqual([cleanupCalls,notifications],[1,0]);
    assert.equal(f.port.preflight.cleanup(),false);
    await turn();
    assert.deepEqual([cleanupCalls,notifications],[2,0]);
    for(let i=0;i<3;i++){
      assert.equal(f.port.preflight.cleanup(),false);
      await turn();
    }
    assert.deepEqual([cleanupCalls,notifications,invocations,rawCleanup,f.saves()],[3,0,0,0,0]);
  } finally {
    close(true);
    await finish(f);
  }
  assert.equal(notifications, 1);
});

test('selected HTTP port refuses missing or credential-unbound prepared children without Fetch', async t => {
  const missing=fixture({fetch:undefined,prepareTransport:()=>undefined});
  const {clientProgramModelPhysicalIoObservation, ...withoutIoObservation} = missing.args.moon;
  assert.equal(typeof clientProgramModelPhysicalIoObservation, 'function');
  assert.throws(() => createHttpChatPreflight({...missing.args, moon: withoutIoObservation}),
    {message:'HTTPChatRuntimeUnavailable'});
  t.after(()=>finish(missing));
  assert.equal(missing.port.preflight.advance()._1,undefined);
  let closed=0;
  const credential=fixture({fetch:undefined,prepareTransport:()=>({
    invoke(){assert.fail('Unbound credential reached transport');},
    bindCredential(){assert.fail('Wrong credential owner');},
    async cleanup(){closed++;return true;},
  })});
  assert.equal(credential.port.preflight.advance()._1,undefined);
  await finish(credential);
  assert.equal(closed,1);
});

test('selected HTTP binds a protected credential once through the original Host continuation', async t => {
  const cases = ['success', 'missing', 'unprepared'] as const;
  for (const outcome of cases) await t.test(outcome, async () => {
    const credentialFailure = Object.assign(Error('fixture credential absent'), {code:'ModelProjectCredentialUnavailable'});
    let bindRaw!: Bind, prepareCredential!: () => void;
    let binds = 0, sends = 0, closes = 0;
    const selected = fixture({
      fetch: undefined, persistRaw: undefined, cleanupRaw: undefined, needsCredential: true,
      rawCaptureBinder(bind, prepare) { bindRaw = bind; assert(prepare); prepareCredential = prepare; },
      prepareTransport() {
        return {
          bindCredential() {
            binds++;
            if (outcome === 'missing') throw credentialFailure;
          },
          async invoke() {
            sends++;
            assert.equal(binds, 1);
            return new Response(bytes, {headers:{'content-type':'application/json'}});
          },
          async cleanup() { closes++; return true; },
        };
      },
    });
    const plan = selected.port.preflight.advance()._1!;
    assert(plan);
    assert.deepEqual([binds, sends], [0, 0]);
    const persist = Object.assign(() => ({response:selected.saved}), {cleanup: () => true});
    if (outcome === 'success') {
      prepareCredential();
      assert.throws(prepareCredential, {message:'HTTPChatCredentialPreparationUnavailable'});
    } else if (outcome === 'missing') {
      assert.throws(prepareCredential, cause => cause === credentialFailure);
      assert.throws(prepareCredential, {message:'HTTPChatCredentialPreparationUnavailable'});
    }
    assert.equal(sends, 0);
    bindRaw({}, persist);
    const call = plan.start(selected.entry)!;
    const final = await until(() => call.poll(), result => result.kind !== 'pending');
    assert.equal(final.kind, outcome === 'success' ? 'chat' : 'unknown');
    assert.deepEqual([binds, sends], [outcome === 'unprepared' ? 0 : 1, outcome === 'success' ? 1 : 0]);
    assert.throws(prepareCredential, {message:'HTTPChatCredentialPreparationUnavailable'});
    await until(() => call.cleanup(), value => value);
    assert.equal(closes, 1);
    assert.equal(plan.start(selected.entry), undefined);
  });
});

for (const mode of ['complete', 'response-loss']) {
  test(`direct HTTP keeps one original prepared Undici Call through ${mode}`, {timeout:5000}, async t => {
    let sends=0,connections=0,socketCloses=0;
    const peer=createServer((req,res)=>{
      sends++;assert.equal(req.method,'POST');assert.equal(req.url,'/chat');
      let input='';req.setEncoding('utf8');req.on('data',part=>{input+=part;});
      req.on('end',()=>{
        assert.equal(input,body);
        if(mode==='response-loss'){res.destroy();return;}
        res.writeHead(200,{'content-type':'application/json','content-length':bytes.byteLength});
        res.end(bytes);
      });
    });
    peer.on('connection',socket=>{connections++;socket.once('close',()=>{socketCloses++;});});
    await new Promise<void>((resolve,reject)=>{peer.once('error',reject);peer.listen(0,'127.0.0.1',resolve);});
    t.after(()=>new Promise<Error | undefined>(resolve=>{peer.close(resolve);peer.closeAllConnections();}));
    const endpoint=`http://127.0.0.1:${(peer.address() as AddressInfo).port}/chat`;
    const responseLimits={maxBytes:512,maxChunkBytes:512,maxChunks:2,maxHeaderBytes:512,
      observedHeaders:['content-type']};
    const selected=createOriginalUndiciFetch({endpoint,requestLimits:{maxBytes:4096,maxHeaderBytes:128,maxHeaders:4},
      responseLimits,physicalAcquisitionLimits:{maxPlaintextBytes:4096,maxBorrowedBackingBytes:16384,maxReads:32}});
    const notification=createInferIoNotification();
    const wake=claimInferIoNotification(notification);t.after(()=>wake.close());
    let prepared=0,physicalClosed=false,physicalCloseCalls=0,rawCloses=0;
    let release!: () => void;
    const deliveryGate=new Promise<void>(resolve=>{release=resolve;});
    const f=fixture({endpoint,responseLimits,fetch:undefined,notify:notification.notify,
      prepareTransport(url,init,limits,controller){
        prepared++;
        const owned=prepareOriginalUndiciFetch(selected,url,init,limits,controller)!;
        return {...owned,async cleanup(){
          physicalCloseCalls++;
          physicalClosed=await owned.cleanup();
          await deliveryGate;
          return physicalClosed;
        }};
      },
      cleanupRaw(){rawCloses++;return true;}
    });
    try {
      const plan=f.port.preflight.advance()._1!;
      assert.deepEqual([prepared,connections,sends],[1,0,0]);
      const call=plan.start(f.entry)!;
      assert.equal(plan.start(f.entry),undefined);
      let result: Poll | undefined;
      for (let i=0;i<8;i++) {
        const ticket=wake.arm();
        try { result=call.poll();if(result.kind!=='pending')break;await ticket.promise; }
        finally { ticket.dispose(); }
      }
      const complete=mode==='complete';
      assert.equal(result?.kind,complete?'chat':'unknown');
      if(complete){
        assert.deepEqual(f.raw()!.body,bytes);
        assert.equal(f.raw()!.status,200);
        assert.equal(f.raw()!.transportComplete,true);
      }else{
        assert.equal(f.raw(),undefined);
      }
      assert.deepEqual([connections,sends,f.saves()],[1,1,complete?1:0]);
      assert.equal(result?.ioRetired, false);
      await until(()=>physicalClosed,value=>value);
      assert.equal(call.poll().ioRetired, false);
      assert.deepEqual([physicalCloseCalls,rawCloses],[1,0]);
      release();
      const retired = await until(() => call.poll(), value => value.ioRetired === true);
      assert.equal(retired.kind, complete ? 'chat' : 'unknown');
      assert.deepEqual([physicalCloseCalls,rawCloses],[1,0]);
      await finish(f);
      await until(()=>socketCloses,n=>n===1);
      assert.deepEqual([sends,physicalCloseCalls,rawCloses],[1,1,complete?1:0]);
    } finally {
      release();
      await finish(f);
    }
  });
}
