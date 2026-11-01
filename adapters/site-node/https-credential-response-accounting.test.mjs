import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {EventEmitter} from 'node:events';
import {Readable} from 'node:stream';
import {types} from 'node:util';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:https';
import {maxHeaderSize} from 'node:http';
import test from 'node:test';
import {fixtureCertificates} from './https-exchange-fixture.mjs';
import * as resource from './https-credential-resource.mjs';

// Real original HTTPS binding/request/socket and explicit authority/Journal
// ports. This does not issue a Common grant or prove a normal funded Effect.
async function fixture(t, handle, {unjoinedOriginal = false, fenced = true} = {}) {
  const root = await mkdtemp(join(process.env.ACTQL_TEST_SCRATCH_PARENT ?? tmpdir(), 'actql-response-accounting-'));
  const {ca, cert, key} = await fixtureCertificates(root);
  const server = createServer({cert, key}, handle);
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
  const origin = `https://127.0.0.1:${server.address().port}`;
  const scope = Object.freeze({issuerAuthority:'authority',principal:'principal',namespaceId:'namespace',environment:'fixture',
    siteKey:'site',siteGeneration:1,runtimeBundleCid:'runtime',connectorRegistration:'fixture',connectorRevision:'fixture/1',
    resourceOrigin:origin,runInvocationCid:'run',taskAttempt:1,dispatchRequestCid:'dispatch',operation:'create'});
  const grant = {}, use = {}, outcomes = [];
  let claims = 0;
  const control = {identity: () => 'original-grant'};
  const journal = {claim(){claims++;return {replayed:false,grant,use,record:{useCid:'original-use',grantCid:'original-grant'}};},
    authorize(){},finish(id, outcome){assert.equal(id,'original-use');outcomes.push(outcome);}};
  const resolveSecret = async () => 'fixture-secret';
  const binding = resource.openHttpsCredentialBinding({scope,control,journal,resolveSecret,maxSecretBytes:64,
    ...(fenced ? {assertCurrent(){}} : {})});
  t.after(async()=>{
    assert.equal(resource.closeHttpsCredentialBinding(binding),unjoinedOriginal?'pending':'closed');
    await new Promise(resolve=>server.close(resolve));
    if(process.env.ACTQL_TEST_PRESERVE_SCRATCH==='1')t.diagnostic(`Retained owned TLS fixture: ${root}`);
    else await rm(root,{recursive:true,force:true});
  });
  const call = options => resource.callHttpsCredentialResource({grant,useId:'use',scope,control,journal,resolveSecret,binding,ca,
    currentBeforeSend:async()=>{},maxRequestBytes:1024,maxResponseBytes:64,
    operations:new Map([['create',{method:'POST',path:'/create',body:'{}'}]]),...options});
  return {call,outcomes,claims:()=>claims,binding,
    original:(response, consume)=>resource.withHttpsCredentialRunResponseOriginal(response,control,journal,consume)};
}

test('bounded original response reader charges the actual refusal byte before discarding its oversized body',async t=>{
  let requests=0;
  const f=await fixture(t,(request,response)=>{requests++;response.writeHead(200);response.end('x'.repeat(8192));});
  const lengths=[];
  await assert.rejects(f.call({observeResponseBytes:n=>{lengths.push(n);}}),{code:'RemoteCredentialResponseLimitExceeded'});
  assert.deepEqual(lengths,[65]);
  assert.equal(requests,1);assert.equal(f.claims(),1);assert.deepEqual(f.outcomes,['unknown']);
  assert.equal(resource.closeHttpsCredentialBinding(f.binding),'closed');
});

test('original binary response lengths and body remain exact through successful completion',async t=>{
  const body=Buffer.from('{"text":"東京"}');
  const f=await fixture(t,(request,response)=>{response.writeHead(200);response.end(body);});
  const lengths=[];
  const result=await f.call({observeResponseBytes:n=>{assert.equal(f.outcomes.length,0);lengths.push(n);}});
  assert.equal(lengths.reduce((a,b)=>a+b,0),body.byteLength);
  assert.deepEqual(result.body,body);assert.deepEqual(f.outcomes,['succeeded']);
  assert.equal(resource.httpsCredentialResponseWindowBytes(64),65n);
  for(const invalid of [0,-1,NaN,1.5])assert.throws(()=>resource.httpsCredentialResponseWindowBytes(invalid),{code:'InvalidRemoteCredentialResponseWindow'});
});

test('a lost reply preserves its actual consumed prefix without a quota substitution or another request',async t=>{
  let consumed;
  const originalRead=new Promise(resolve=>{consumed=resolve;});
  let requests=0;
  const f=await fixture(t,(request,response)=>{
    requests++;response.writeHead(200);response.write(Buffer.alloc(16384,120));
    originalRead.then(()=>request.socket.destroy());
  });
  const lengths=[];
  await assert.rejects(f.call({maxResponseBytes:32768,observeResponseBytes:n=>{lengths.push(n);consumed();}}));
  assert.deepEqual(lengths,[16384]);assert.equal(requests,1);assert.deepEqual(f.outcomes,['unknown']);
  assert.equal(resource.closeHttpsCredentialBinding(f.binding),'closed');
});

test('an invalid asynchronous byte observer stays joined after socket close until its original settlement',async t=>{
  for(const rejected of [false,true]){
    let ready,resolve,reject;
    const entered=new Promise(yes=>{ready=yes;});
    const original=new Promise((yes,no)=>{resolve=yes;reject=no;});
    const f=await fixture(t,(request,response)=>{response.writeHead(200);response.end('{}');});
    let completed=false;
    const pending=f.call({observeResponseBytes(){ready();return original;}});
    const refused=assert.rejects(pending,{code:'InvalidRemoteCredentialResponseByteObserver'}).then(()=>{completed=true;});
    await entered;
    assert.equal(resource.closeHttpsCredentialBinding(f.binding),'pending');
    await new Promise(setImmediate);assert.equal(completed,false);assert.deepEqual(f.outcomes,[]);
    if(rejected)reject(new Error('original invalid observer failure'));else resolve();
    await refused;
    assert.deepEqual(f.outcomes,['unknown']);
    assert.equal(resource.closeHttpsCredentialBinding(f.binding),'closed');
  }
});

for (const publicThen of ['throwing getter', 'throwing method']) {
  test(`native byte observer keeps its original pending task despite a ${publicThen}`, async t => {
    let entered, settle, socketClosed;
    const original = new Promise(resolve => {settle = resolve;});
    const observed = new Promise(resolve => {entered = resolve;});
    const closed = new Promise(resolve => {socketClosed = resolve;});
    const primary = new Error('original public then observation failed');
    if (publicThen === 'throwing getter') {
      Object.defineProperty(original, 'then', {get() {throw primary;}});
    } else Object.defineProperty(original, 'then', {value() {throw primary;}});
    let requests = 0;
    const f = await fixture(t, (request, response) => {
      requests++; request.socket.once('close', socketClosed);
      response.writeHead(200); response.end('{}');
    });
    let completed = false;
    const pending = f.call({observeResponseBytes() {entered(); return original;}});
    const refused = assert.rejects(pending, error => publicThen === 'throwing getter'
      ? error === primary : error.code === 'InvalidRemoteCredentialResponseByteObserver')
      .then(() => {completed = true;});
    try {
      await observed;
      await closed;
      // A deliberately pending child has no timeout-based ACK. Give the old
      // socket-close continuation a bounded opportunity to expose early release;
      // this is a lifetime assertion, not a latency/performance measurement.
      await new Promise(resolve => setTimeout(resolve, 25));
      assert.equal(completed, false, 'Socket close cannot settle a different native task');
      assert.deepEqual(f.outcomes, []);
      assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'pending');
    } finally {
      settle(); await refused;
    }
    assert.equal(requests, 1); assert.equal(f.claims(), 1);
    assert.deepEqual(f.outcomes, ['unknown']);
    assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'closed');
  });
}

test('native byte observer join failure retains the original under existing binding custody', async t => {
  let settle;
  const original = new Promise(resolve => {settle = resolve;});
  const primary = new Error('original native species lookup failed');
  Object.defineProperty(original, 'constructor', {get() {throw primary;}});
  let requests = 0;
  const f = await fixture(t, (request, response) => {
    requests++; response.writeHead(200); response.end('{}');
  }, {unjoinedOriginal: true});
  await assert.rejects(f.call({observeResponseBytes() {return original;}}), error => error === primary);
  assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'pending');
  settle(); await new Promise(setImmediate);
  // Failed native registration supplied no observable settlement witness to
  // this binding. A test-owned resolver cannot acknowledge its original duty.
  assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'pending');
  assert.equal(requests, 1); assert.equal(f.claims(), 1); assert.deepEqual(f.outcomes, ['unknown']);
});

for (const port of ['byte observer', 'response custody']) {
  test(`unfenced binding refuses another claim while its original ${port} cannot be joined`, async t => {
    let settle;
    const original = new Promise(resolve => {settle = resolve;});
    const primary = new Error('original native species lookup failed');
    Object.defineProperty(original, 'constructor', {get() {throw primary;}});
    let requests = 0;
    const f = await fixture(t, (request, response) => {
      requests++; response.writeHead(200); response.end('{}');
    }, {unjoinedOriginal: true, fenced: false});
    const options = port === 'byte observer'
      ? {observeResponseBytes() {return original;}}
      : {responseCustody: Object.freeze({retain() {return original;}})};
    try {
      await assert.rejects(f.call(options), error => error === primary);
      // No close first: active=false and a completed socket do not retire the
      // original callback task. Refuse BEFORE a second Journal claim or send.
      await assert.rejects(f.call({}), {code: 'RemoteCredentialBindingBusy'});
      assert.equal(requests, 1); assert.equal(f.claims(), 1);
      assert.deepEqual(f.outcomes, ['unknown']);
    } finally {
      settle(); await new Promise(setImmediate);
      // A test-owned resolver supplies no missing native settlement witness.
      assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'pending');
    }
  });
}

test('unfenced binding remains reusable after its original successful response retires', async t => {
  let requests = 0;
  const f = await fixture(t, (request, response) => {
    requests++; response.writeHead(200); response.end('{}');
  }, {fenced: false});
  for (let index = 0; index < 2; index++) {
    const response = await f.call({});
    assert.equal(response.body.toString(), '{}');
  }
  assert.equal(requests, 2); assert.equal(f.claims(), 2);
  assert.deepEqual(f.outcomes, ['succeeded', 'succeeded']);
  assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'closed');
});

test('a failed byte charge preserves its original error while the same request and binding stop',async t=>{
  const primary=new Error('original Ledger charge refusal');
  const f=await fixture(t,(request,response)=>{response.writeHead(200);response.end('body');});
  let charges=0;
  await assert.rejects(f.call({observeResponseBytes(){charges++;throw primary;}}),error=>error===primary);
  assert.equal(charges,1);assert.equal(f.claims(),1);assert.deepEqual(f.outcomes,['unknown']);
  assert.equal(resource.closeHttpsCredentialBinding(f.binding),'closed');
});

test('absent byte observation keeps the legacy body and a malformed observer refuses before claim',async t=>{
  let requests=0;
  const f=await fixture(t,(request,response)=>{requests++;response.writeHead(200);response.end('{}');});
  await assert.rejects(f.call({observeResponseBytes:true}),{code:'InvalidRemoteCredentialResponseByteObserver'});
  assert.equal(f.claims(),0);assert.equal(requests,0);
  const result=await f.call({});assert.equal(result.body.toString(),'{}');
  assert.equal(f.claims(),1);assert.equal(requests,1);assert.deepEqual(f.outcomes,['succeeded']);
});

test('an empty original response closes without fabricating a zero-byte observation',async t=>{
  const f=await fixture(t,(request,response)=>{response.writeHead(204);response.end();});
  const lengths=[];
  const result=await f.call({observeResponseBytes:n=>{lengths.push(n);}});
  assert.equal(result.statusCode,204);assert.equal(result.body.byteLength,0);assert.deepEqual(lengths,[]);
  assert.equal(f.claims(),1);assert.equal(resource.closeHttpsCredentialBinding(f.binding),'closed');
});

test('original HTTP header and trailer bounds retain exact body observations and original cleanup', async t => {
  assert.equal(resource.httpsCredentialResponseHeaderByteLimit, maxHeaderSize);
  const f = await fixture(t, (request, response) => {
    response.writeHead(200, {'x-initial': 'a'.repeat(256), trailer: 'x-final'});
    response.write('{}'); response.addTrailers({'x-final': 'b'.repeat(256)}); response.end();
  });
  const charges = [];
  const result = await f.call({observeResponseBytes: n => {charges.push(n);}});
  assert.equal(result.body.toString(), '{}');
  assert.equal(charges.reduce((a, b) => a + b, 0), 2);
  assert.deepEqual(f.outcomes, ['succeeded']); assert.equal(f.claims(), 1);
  assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'closed');
});

test('original HTTP overflow in either header block stays Unknown without another claim', async t => {
  for (const trailers of [false, true]) {
    let requests = 0;
    const f = await fixture(t, (request, response) => {
      requests++;
      if (trailers) {
        response.writeHead(200, {trailer: 'x-overflow'}); response.write('{}');
        response.addTrailers({'x-overflow': 'x'.repeat(maxHeaderSize)}); response.end();
      } else {
        response.writeHead(200, {'x-overflow': 'x'.repeat(maxHeaderSize)}); response.end('{}');
      }
    });
    const charges = [];
    await assert.rejects(f.call({observeResponseBytes: n => {charges.push(n);}}),
      {code: 'HPE_HEADER_OVERFLOW'});
    assert(charges.reduce((a, b) => a + b, 0) <= 2);
    assert.equal(requests, 1); assert.equal(f.claims(), 1);
    assert.deepEqual(f.outcomes, ['unknown']);
    assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'closed');
  }
});

test('original repeated headers preserve the selected normalized value without another response copy', async t => {
  const f = await fixture(t, (request, response) => {
    response.writeHead(200, {'x-repeated': ['one', 'two', 'three']}); response.end('{}');
  });
  const result = await f.call({operations: new Map([['create', {method: 'POST', path: '/create',
    body: '{}', responseHeaders: ['x-repeated']}]])});
  assert.deepEqual(result.headers, [['x-repeated', 'one, two, three']]);
  assert.equal(result.body.toString(), '{}'); assert.equal(f.claims(), 1);
  assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'closed');
});

// Execute the exact private receiver body with explicit original HTTP ports.
// No provider, Common grant, installed Run or physical cleanup is inferred.
function originalReceiveComponent({observed = true, concatFailure, readFailure} = {}) {
  const source = readFileSync(new URL('./https-credential-resource.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('function receive({');
  const end = source.indexOf('\n/// Execute one pre-registered HTTPS operation.', start);
  assert(start >= 0 && end > start);
  const response = new EventEmitter();
  response.statusCode = 200; response.headers = {}; response.rawHeaders = [];
  response.destroyed = false;
  response.destroy = error => {response.destroyed = true; response.emit('error', error);};
  const request = new EventEmitter(); request.end = () => {};
  let callback, copied, copiedAtConcat;
  const originalBytes = [Buffer.from('one'), Buffer.from('two')];
  const buffer = {from: Buffer.from.bind(Buffer), concat(chunks, received) {
    copied = chunks; copiedAtConcat = chunks.map(chunk => Buffer.from(chunk));
    if (concatFailure !== undefined) throw concatFailure.original;
    return Buffer.concat(chunks, received);
  }};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const receive = new Function('httpsRequest', 'httpsCredentialResponseHeaderByteLimit',
    'httpsCredentialAuthorizationPrefix', 'Buffer', 'types', 'nativePromiseThen',
    'httpsCredentialResponseReadQuantum', 'fail', `${source.slice(start, end)};return receive;`)(
    (_options, originalCallback) => {callback = originalCallback; return request;},
    maxHeaderSize, 'Bearer ', buffer, types, Promise.prototype.then, 16384, fail);
  const charges = [];
  const pending = receive({hostname: 'fixture.invalid', path: '/read', method: 'GET',
    requestBytes: 0, secret: 'fixture', headers: [], maxResponseBytes: 64,
    ...(observed ? {observeResponseBytes: count => {charges.push(count);}} : {})});
  if (observed) {
    const reads = [...originalBytes, null];
    response.read = () => reads.shift() ?? null;
    if (readFailure !== undefined) Object.defineProperty(response,'read',{get(){throw readFailure.original;}});
  }
  callback(response);
  if (observed) response.emit('readable');
  else for (const chunk of originalBytes) response.emit('data', chunk);
  return {response, pending, charges, originalBytes,
    copied: () => copied, copiedAtConcat: () => copiedAtConcat};
}

for (const observed of [false, true]) {
  test(`successful original ${observed ? 'observed' : 'legacy'} receiver severs copied chunks before returning its exact body`, async () => {
    const f = originalReceiveComponent({observed});
    assert.equal(f.response.listenerCount(observed ? 'readable' : 'data'), 1);
    f.response.emit('end');
    const result = await f.pending;
    assert.equal(result.body.toString(), 'onetwo');
    assert.deepEqual(f.copiedAtConcat(), f.originalBytes);
    assert.equal(f.copied().length, 0, 'No copied chunk remains in the original listener closure');
    assert.equal(f.response.listenerCount('readable'), 0);
    assert.equal(f.response.listenerCount('data'), 0);
    assert.deepEqual(f.charges, observed ? [3, 3] : []);
  });
}

test('failed original response concatenation retains its prefix and rejects with the same primary', async () => {
  const primary = {original: undefined};
  const f = originalReceiveComponent({concatFailure: primary});
  const rejected = assert.rejects(f.pending, error => error === primary.original);
  assert.doesNotThrow(() => f.response.emit('end'));
  await rejected;
  assert.deepEqual(f.copied(), f.originalBytes);
  assert.equal(f.response.listenerCount('readable'), 1);
});

test('successful original response retains its independent historical byte snapshot after copied chunks retire', async t => {
  const f = await fixture(t, (_request, response) => {response.writeHead(200); response.end('original');});
  const response = await f.call({retainRunResponseOriginal: true, observeResponseBytes() {}});
  assert.equal(response.body.toString(), 'original');
  f.original(response, facts => {assert.equal(facts.response, response);});
  response.body[0] = 0;
  assert.throws(() => f.original(response, () => assert.fail('changed original')),
    {code: 'RemoteCredentialRunResponseChanged'});
  assert.deepEqual(f.outcomes, ['succeeded']); assert.equal(f.claims(), 1);
  assert.equal(resource.closeHttpsCredentialBinding(f.binding), 'closed');
});


// Actual original receiver body with the pinned Node binary Readable.read(size)
// implementation. The request/socket/authority are explicit component ports;
// this proves copied-buffer geometry, not physical or normal Run admission.
test('observed original binary reader coalesces tiny ingress chunks with one EOF partial and retains its read method', async () => {
  assert.equal(resource.httpsCredentialResponseReadQuantum, 16384);
  const source = readFileSync(new URL('./https-credential-resource.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('function receive({');
  const end = source.indexOf('\n/// Execute one pre-registered HTTPS operation.', start);
  assert(start >= 0 && end > start);
  for (const bytes of [1,16383,16384,16385,32768,32769]) {
    const response = new Readable({read() {}});
    response.statusCode=200;response.headers={};response.rawHeaders=[];
    const request = new EventEmitter();request.end=()=>{};
    const nativeRead = response.read;
    let callback;
    const copied=[];const charges=[];
    const buffer={from(chunk){copied.push(chunk.byteLength);return Buffer.from(chunk);},concat:Buffer.concat.bind(Buffer)};
    const receive=new Function('httpsRequest','httpsCredentialResponseHeaderByteLimit',
      'httpsCredentialAuthorizationPrefix','Buffer','types','nativePromiseThen',
      'httpsCredentialResponseReadQuantum','fail',`${source.slice(start,end)};return receive;`)(
      (_options,original)=>{callback=original;return request;}, maxHeaderSize,'Bearer ',buffer,types,
      Promise.prototype.then,resource.httpsCredentialResponseReadQuantum,
      code=>{throw Object.assign(new Error(code),{code});});
    const pending=receive({hostname:'fixture.invalid',path:'/read',method:'GET',requestBytes:0,
      secret:'fixture',headers:[],maxResponseBytes:bytes,observeResponseBytes(count){
        charges.push(count);
        response.read=size=>{
          // Node's own deferred read(0) housekeeping remains outside this
          // receiver; all positive reads must use its captured original.
          assert.equal(size,0);
          return Reflect.apply(nativeRead,response,[size]);
        };
      }});
    callback(response);
    for(let i=0;i<bytes;i++) {
      response.push(Buffer.from([i%251]));
      response.emit('readable');
    }
    response.push(null);response.emit('readable');
    const result=await pending;
    assert.equal(copied.length,Math.ceil(bytes/16384));
    assert.deepEqual(copied,charges);
    assert.deepEqual(copied,[...Array(Math.floor(bytes/16384)).fill(16384),...(bytes%16384?[bytes%16384]:[])]);
    assert.equal(result.body.length,bytes);
    for(let i=0;i<bytes;i++)assert.equal(result.body[i],i%251);
    assert.equal(response.listenerCount('readable'),0);
  }
});


for (const original of [undefined, new Error('original read accessor refused')]) {
  test(`observed reader captures its method inside the existing error fence (${original === undefined ? 'undefined' : 'Error'})`, async () => {
    let component;
    assert.doesNotThrow(() => {component=originalReceiveComponent({readFailure:{original}});});
    await assert.rejects(component.pending, cause => cause === original);
    assert.equal(component.response.destroyed,true);
    assert.deepEqual(component.charges,[]);
  });
}
