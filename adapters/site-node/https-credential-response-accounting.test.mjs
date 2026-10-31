import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:https';
import test from 'node:test';
import {fixtureCertificates} from './https-exchange-fixture.mjs';
import * as resource from './https-credential-resource.mjs';

// Real original HTTPS binding/request/socket and explicit authority/Journal
// ports. This does not issue a Common grant or prove a normal funded Effect.
async function fixture(t, handle, {unjoinedOriginal = false} = {}) {
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
  const binding = resource.openHttpsCredentialBinding({scope,control,journal,resolveSecret,maxSecretBytes:64,assertCurrent(){}});
  t.after(async()=>{
    assert.equal(resource.closeHttpsCredentialBinding(binding),unjoinedOriginal?'pending':'closed');
    await new Promise(resolve=>server.close(resolve));
    if(process.env.ACTQL_TEST_PRESERVE_SCRATCH==='1')t.diagnostic(`Retained owned TLS fixture: ${root}`);
    else await rm(root,{recursive:true,force:true});
  });
  const call = options => resource.callHttpsCredentialResource({grant,useId:'use',scope,control,journal,resolveSecret,binding,ca,
    currentBeforeSend:async()=>{},maxRequestBytes:1024,maxResponseBytes:64,
    operations:new Map([['create',{method:'POST',path:'/create',body:'{}'}]]),...options});
  return {call,outcomes,claims:()=>claims,binding};
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
