import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {prepareOpenAIChatRequest} from './_internal/openai-chat.mjs';
import {pollSdkPreparation, prepareSdkTransport, startSdkTransport,
  pollSdkTransport, sdkTransportRawObservation, pollSdkDecode,
  takeSdkDecodedResult, cancelSdkPreparation, cleanupSdkPreparation,
  interceptSdkRequest} from './_internal/intercepted-request.mjs';
import {createSdkModelPreflight} from './_internal/model-port.mjs';

const limits = {maxBytes:2048,maxChunkBytes:512,maxChunks:16,
  maxHeaderBytes:128,observedHeaders:['content-type']};
const wire = '{"choices":[{"index":0,"message":{"role":"assistant",' +
  '"content":"{\\"answer\\":\\"é\\r\\n\\"}"},"finish_reason":"stop"}],' +
  '"usage":{"prompt_tokens":0,"completion_tokens":4}}';
const bytes = new TextEncoder().encode(wire);
const prepare = () => prepareOpenAIChatRequest({modelId:'gpt-4.1-nano',
  baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',
  maxRequestBytes:1000,maxHeaderBytes:4096,maxHeaders:16,notify(){},
  options:{prompt:[{role:'user',content:[{type:'text',text:'Original é\r\n'}]}],
    maxOutputTokens:16,responseFormat:{type:'json'}}});

async function until(read, accepts) {
  for (let i = 0; i < 50; i++) {
    const value = read();
    if (accepts(value)) return value;
    await turn();
  }
  assert.fail('Original private SDK observation did not finish');
}

test('Chat raw-only keeps original bytes without an unused SDK response copy or decoder', async t => {
  // Actual pinned SDK, synthetic fixed HTTP only. No original Common/Store
  // receipt, numerical profile, public Run or Provider execution is claimed.
  const wire = '{"choices":[{"index":0,"message":{"role":"assistant",' +
    '"content":"{\\"answer\\":\\"é\\r\\n\\"}"},"finish_reason":"stop"}],' +
    '"usage":{"prompt_tokens":0,"completion_tokens":4}}';
  const bytes = new TextEncoder().encode(wire);
  const response = new Response(bytes, {headers: {'content-type': 'application/json'}});
  const handle = prepareOpenAIChatRequest({modelId:'gpt-4.1-nano',
    baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',
    maxRequestBytes:1000,maxHeaderBytes:4096,maxHeaders:16,notify(){},
    options:{prompt:[{role:'user',content:[{type:'text',text:'Original é\r\n'}]}],
      maxOutputTokens:16,responseFormat:{type:'json'}}});
  await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
  const originalParse = JSON.parse;
  const OriginalResponse = globalThis.Response;
  let parses = 0, copies = 0, sends = 0;
  t.after(async () => {
    JSON.parse = originalParse;
    globalThis.Response = OriginalResponse;
    await until(() => cleanupSdkPreparation(handle), value => value === true);
  });
  // Preparation is already ready. These probes observe the unused physical
  // response work only, not the required SDK request normalization/schema work.
  JSON.parse = (...args) => { parses++; return originalParse(...args); };
  globalThis.Response = class extends OriginalResponse {
    constructor(...args) { copies++; super(...args); }
  };
  prepareSdkTransport(handle, {responseMode:'raw-only',
    responseLimits:{maxBytes:2048,maxChunkBytes:512,maxChunks:16,
      maxHeaderBytes:128,observedHeaders:['content-type']},
    observeAt:()=>'2026-10-14T00:00:00.000Z',fetch(){sends++;return response;}});
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  const raw = sdkTransportRawObservation(handle);
  assert.deepEqual(raw.body, bytes);
  assert.equal(raw.transportComplete, true);
  assert.equal(raw.status, 200);
  assert.equal(raw.observedAt, '2026-10-14T00:00:00.000Z');
  const consumer = await until(() => pollSdkDecode(handle), value => value.kind !== 'pending');
  assert.equal(copies, 0, 'Raw Chat must not allocate an unused SDK Response copy');
  assert.equal(parses, 0, 'Common owns Chat response decoding; SDK request normalization remains');
  assert.deepEqual(consumer, {kind:'retired'});
  assert.throws(() => takeSdkDecodedResult(handle), {code:'SdkDecodedResultUnavailable'});
  assert.equal(sends, 1);
  assert.throws(() => startSdkTransport(handle), {code:'SdkTransportStartRefused'});
});

test('raw-only retains malformed bytes and HTTP refusal without claiming answer validation', async t => {
  const originals = [new Uint8Array([255]), new TextEncoder().encode('{'),
    new TextEncoder().encode('{"error":"unavailable"}')];
  for (let i = 0; i < originals.length; i++) {
    const handle = prepare();
    t.after(() => until(() => cleanupSdkPreparation(handle), Boolean));
    await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
    let sends = 0;
    const status = i === 2 ? 503 : 200;
    prepareSdkTransport(handle, {responseMode:'raw-only',responseLimits:limits,
      fetch(){sends++;return new Response(originals[i], {status});}});
    startSdkTransport(handle);
    await until(() => pollSdkTransport(handle), value => value.kind === 'response');
    assert.deepEqual(await until(() => pollSdkDecode(handle), value => value.kind !== 'pending'),
      {kind:'retired'});
    const raw = sdkTransportRawObservation(handle);
    assert.deepEqual(raw.body, originals[i]);
    assert.equal(raw.status, status);
    assert.equal(raw.transportComplete, true);
    assert.equal(sends, 1);
    assert.throws(() => startSdkTransport(handle), {code:'SdkTransportStartRefused'});
    // Physical EOF and SDK retirement deliberately do not parse/admit this
    // response. Actual Common fatal-UTF8/JSON/status/typed checks still apply.
  }
});

test('raw-only invoke loss stays Unknown with no invented bytes or second request', async t => {
  const handle = prepare();
  t.after(() => until(() => cleanupSdkPreparation(handle), Boolean));
  await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
  let sends = 0;
  prepareSdkTransport(handle, {responseMode:'raw-only',responseLimits:limits,
    fetch(){sends++;throw Error('SyntheticResponseLost');}});
  startSdkTransport(handle);
  assert.equal((await until(() => pollSdkTransport(handle), value => value.kind === 'unknown')).kind, 'unknown');
  assert.equal(sdkTransportRawObservation(handle), undefined);
  assert.equal((await until(() => pollSdkDecode(handle), value => value.kind !== 'pending')).kind, 'rejected');
  assert.throws(() => startSdkTransport(handle), {code:'SdkTransportStartRefused'});
  assert.equal(sends, 1);
});

test('raw-only abort-ignoring transport remains held after local SDK cancellation', async () => {
  const handle = prepare();
  await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
  let sends = 0;
  prepareSdkTransport(handle, {responseMode:'raw-only',responseLimits:limits,
    fetch(){sends++;return new Promise(() => {});}});
  startSdkTransport(handle);
  cancelSdkPreparation(handle);
  await until(() => pollSdkDecode(handle), value => value.kind === 'rejected');
  for (let i = 0; i < 8; i++) {
    assert.deepEqual(pollSdkTransport(handle), {kind:'pending'});
    assert.equal(sdkTransportRawObservation(handle), undefined);
    assert.equal(cleanupSdkPreparation(handle), false);
    await turn();
  }
  assert.throws(() => startSdkTransport(handle), {code:'SdkTransportStartRefused'});
  assert.equal(sends, 1);
  // The synthetic transport never settles. Natural test-process exit does
  // not acknowledge its original physical holding or any public Run release.
});

test('raw-only read failure keeps its original partial bytes and cannot report SDK retirement', async t => {
  const handle = prepare();
  t.after(() => until(() => cleanupSdkPreparation(handle), Boolean));
  await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
  let reads = 0, releases = 0, sends = 0;
  prepareSdkTransport(handle, {responseMode:'raw-only',responseLimits:limits,fetch(){
    sends++;
    return {status:200,headers:new Headers(),body:{getReader:()=>({
      read(){return ++reads === 1 ? Promise.resolve({done:false,value:new Uint8Array([123])})
        : Promise.reject(Error('OriginalReadFailed'));},
      cancel(){},releaseLock(){releases++;},
    })}};
  }});
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  const raw = sdkTransportRawObservation(handle);
  assert.deepEqual(raw.body, new Uint8Array([123]));
  assert.equal(raw.issue, 'InferResponseReadFailed');
  assert.equal(raw.transportComplete, false);
  assert.equal((await until(() => pollSdkDecode(handle), value => value.kind !== 'pending')).kind, 'rejected');
  assert.equal(await raw.readerRetirement, true);
  assert.equal(releases, 1); assert.equal(reads, 2); assert.equal(sends, 1);
});

test('SDK consumer settlement alone cannot retire a raw reader whose lock release still fails', async t => {
  const handle = prepare();
  let lockAvailable = false, releases = 0;
  t.after(async () => {lockAvailable=true;await until(() => cleanupSdkPreparation(handle), Boolean);});
  await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
  let reads = 0;
  prepareSdkTransport(handle, {responseMode:'raw-only',responseLimits:limits,fetch(){
    return {status:200,headers:new Headers(),body:{getReader:()=>({
      read(){return Promise.resolve(++reads === 1 ? {done:false,value:bytes} : {done:true});},
      cancel(){},releaseLock(){releases++;if(!lockAvailable)throw Error('OriginalReaderStillHeld');},
    })}};
  }});
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  assert.deepEqual(await until(() => pollSdkDecode(handle), value => value.kind !== 'pending'), {kind:'retired'});
  const raw = sdkTransportRawObservation(handle);
  assert.equal(await raw.readerRetirement, false);
  assert.equal(cleanupSdkPreparation(handle), false);
  assert.deepEqual(raw.body, bytes);
  lockAvailable = true;
  await until(() => cleanupSdkPreparation(handle), Boolean);
  assert.ok(releases >= 2);
  assert.deepEqual(raw.body, bytes);
});

test('raw-only complete response does not retire an SDK operation which ignores its ended fetch wait', async () => {
  let handled = 0, sends = 0;
  const handle = interceptSdkRequest({endpoint:'https://fixture.invalid/v1/chat/completions',
    maxRequestBytes:1000,maxHeaderBytes:4096,maxHeaders:16,notify(){},
    runSdk(fetch){
      void fetch('https://fixture.invalid/v1/chat/completions', {method:'POST',body:'{}'})
        .catch(() => {handled++;});
      return new Promise(() => {});
    }});
  await until(() => pollSdkPreparation(handle), value => value.kind === 'ready');
  prepareSdkTransport(handle, {responseMode:'raw-only',responseLimits:limits,
    fetch(){sends++;return new Response(bytes);}});
  startSdkTransport(handle);
  await until(() => pollSdkTransport(handle), value => value.kind === 'response');
  await until(() => handled, value => value === 1);
  assert.deepEqual(sdkTransportRawObservation(handle).body, bytes);
  for (let i = 0; i < 8; i++) {
    assert.deepEqual(pollSdkDecode(handle), {kind:'pending'});
    assert.equal(cleanupSdkPreparation(handle), false);
    await turn();
  }
  assert.equal(sends, 1); assert.equal(handled, 1);
  // An intentionally nonconforming SDK double verifies early-free prevention,
  // not acceptance of this never-settling implementation as a physical profile.
});

test('Chat raw-only Store await remains pending after SDK retirement and retains the same raw backing', async t => {
  const handle = prepare();
  const request = {}, entry = {};
  let sends = 0, saves = 0, raw, finishSave, rawReleased = false;
  const saved = {};
  const moon = {
    clientProgramModelRequestPreflight:(advance,cleanup)=>({advance,cleanup}),
    clientProgramModelAsyncPhysicalRequestPlan:(...args)=>({start:args.at(-1)}),
    clientProgramModelPhysicalCallForRequest:(e,r,poll,cancel,cleanup)=>({poll,cancel,cleanup}),
    clientProgramModelPhysicalPending:()=>({kind:'pending'}),
    clientProgramModelPhysicalUnknown:()=>({kind:'unknown'}),
    clientProgramModelPhysicalSavedChat:value=>({kind:'chat',value}),
  };
  const port = createSdkModelPreflight({moon,request,preparation:handle,profile:{},installation:{},
    quantities:{tokens:16n,costUnits:0n,durationMs:500n},responseLimits:limits,
    notify(){},checked:value=>value,observeAt:()=>'2026-10-14T00:00:00.000Z',
    fetch(){sends++;return new Response(bytes);},
    persistRaw(call,value){saves++;raw=value;return new Promise(resolve=>{
      finishSave=()=>resolve({response:saved});
    });},cleanupRaw:()=>rawReleased,
  });
  t.after(async()=>{finishSave?.();rawReleased=true;await until(()=>port.preflight.cleanup(),Boolean);});
  const plan = (await until(()=>port.preflight.advance(),value=>value._0))._1;
  const call = plan.start(entry);
  await until(()=>{call.poll();return raw;},Boolean);
  assert.deepEqual(await until(()=>pollSdkDecode(handle),value=>value.kind!=='pending'), {kind:'retired'});
  const backing = raw.body.buffer;
  for (let i=0;i<4;i++) {
    assert.deepEqual(call.poll(), {kind:'pending'});
    assert.equal(port.preflight.cleanup(), false);
    assert.equal(raw.body.buffer, backing);
    assert.equal(plan.start(entry), undefined);
  }
  finishSave();
  assert.strictEqual((await until(()=>call.poll(),value=>value.kind==='chat')).value,saved);
  assert.equal(port.preflight.cleanup(),false);
  assert.equal(sends,1);assert.equal(saves,1);
  assert.deepEqual(raw.body,bytes);
  // Common/Entry/receipt are doubles. The actual Store, fatal UTF8 and answer
  // validator are not replaced or established by this local custody counter.
});

test('unknown raw-only mode is refused before installing or starting a transport', async t => {
  const handle = prepare();
  t.after(()=>until(()=>cleanupSdkPreparation(handle),Boolean));
  await until(()=>pollSdkPreparation(handle),value=>value.kind==='ready');
  let sends=0;
  for(const responseMode of ['raw-only-retiring','unknown',false,null]) {
    assert.throws(()=>prepareSdkTransport(handle,{responseMode,responseLimits:limits,
      fetch(){sends++;return new Response(bytes);}}), {code:'SdkTransportPreparationRefused'});
  }
  assert.equal(sends,0);
});
