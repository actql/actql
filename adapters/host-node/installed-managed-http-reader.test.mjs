import fs from 'node:fs';
import {types} from 'node:util';
import {parse} from 'acorn';
import {ownHttpRequest, ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {ownInvocationAuthorization, invocationBindingsMatch, invokeScopedCredentialOperation}
  from '../host-common/owned-invocation-context.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';
import {callHttpsCredentialResource} from '../site-node/https-credential-resource.mjs';
import {credentialInvocationBindingKeys} from '../host-common/credential-scope-fields.generated.mjs';

const deferred = () => {
  let resolve;
  const promise = new Promise(yes => {resolve = yes;});
  return {promise, resolve};
};

// Explicit grant/control and page ports isolate this Host lifecycle. They do
// not qualify a normal Account, compiled Common, provider or public Source.
function fixture({pages = [Buffer.from('one'), Buffer.from('two')],
  charge, decode, current, authorize, call, resolveSecret, prepareFailure} = {}) {
  const events = [], responses = [], delivered = [];
  const scope = Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name =>
    [name, name])), operation: 'example:records:list', resourceOrigin: 'https://example.invalid'});
  const grant = {}, control = {identity: () => 'original-grant'};
  const journal = {claim(_cid, useId) {
    events.push('claim');return {use: {}, record: {grantCid: 'original-grant', useId}, replayed: false};
  }, authorize() {}, finish() {events.push('finish');}};
  const credential = {control, journal, resolveSecret: resolveSecret ?? (() => 'secret')};
  let live = true, requestIndex = 0, decoded = 0, prepared = 0;
  const site = {credential, referenceCurrent() {assert.strictEqual(this, site);return live;},
    async callResource(options) {
      assert.strictEqual(this, site);events.push('send');
      if (call) return call(options);
      const response = {accepted: true, statusCode: 200, body: pages[requestIndex++]};
      responses.push(response);return response;
    }};
  const callbacks = {resource: 'records', columns: ['id'], requestWire: 'original-request',
    async verifyRead() {assert.strictEqual(this, callbacks);events.push('current');await current?.();},
    async authorizationFor(index) {
      assert.strictEqual(this, callbacks);events.push(`grant:${index}`);
      return authorize?.(index, scope) ?? {grant, scope, useId: `original-use-${index}`};
    },
    async chargePage(body) {
      assert.strictEqual(this, callbacks);assert.strictEqual(body, responses.at(-1)?.body ?? body);
      events.push('charge');await charge?.(body);return {body};
    },
    async consumePage(rows, ticket) {
      assert.strictEqual(this, callbacks);events.push('consume');
      assert.strictEqual(ticket.charge.body, responses.at(-1)?.body);
      delivered.push(rows);
    }};
  const capacity = {};
  const factory = createInstalledCredentialSourceReader({capacity, site,
    operation: scope.operation, maxResponses: pages.length, maxResponseBytes: 1024, maxSecretBytes: 64,
    preparePageReader(input) {
      prepared++;if (prepareFailure) throw prepareFailure;assert.deepEqual(input, {resource: 'records', columns: ['id'], requestWire: 'original-request'});
      const provider = {
        fetchPage(context) {
          assert.strictEqual(this, provider);assert.equal(context.pageIndex, decoded);
          assert.deepEqual(Object.keys(context).sort(), ['pageIndex','receivedBodyBytes','rowCount']);
          events.push('request');return {method: 'GET', path: '/records', query: [['cursor', String(decoded)]],
            headers: [['accept','application/json']]};
        },
        decodePage(response, context) {
          assert.strictEqual(this, provider);assert.strictEqual(response, responses.at(-1));
          assert.equal(events.at(-2), 'charge');assert.equal(events.at(-1), 'current');
          events.push('decode');decoded++;
          return decode?.(response, context) ?? {rows: [{id: response.body.toString()}], done: decoded === pages.length};
        },
      };return provider;
    }});
  const reader = factory.prepare(callbacks);
  return {factory, reader, capacity, responses, delivered, events, callbacks, site,
    notCurrent: () => {live = false;}, prepared: () => prepared};
}

test('managed reader owns two grants and charges exact responses before provider decode and same-ticket delivery', async () => {
  const f = fixture();
  assert.equal(f.prepared(), 1);assert.equal(f.events.length, 0);
  assert.strictEqual(f.factory.capacity, f.capacity);
  assert.deepEqual(await f.reader.read(), {pages: 2, rowCount: 2});
  assert.deepEqual(f.delivered, [[{id:'one'}],[{id:'two'}]]);
  assert.deepEqual(f.events.filter(x => x.startsWith('grant:')), ['grant:0','grant:1']);
  assert.equal(f.reader.observe().responseCount, 2);
  assert.equal(f.reader.observe().receivedBodyBytes, 6n);
  assert.equal(f.reader.observe().transportClosed, true);
  assert.equal(f.reader.observe().cleanupConfirmed, false);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
  f.reader.requestStop();f.reader.retry();
  await assert.rejects(f.reader.read(), {code:'InstalledSourceReaderAlreadyStarted'});
  assert.throws(() => f.reader.observe.call({}), {code:'ForeignInstalledCredentialSourceReader'});
});

test('managed reader retains and charges the failed response before refusal and never sends a second page', async () => {
  const cause = new Error('original charge failed');
  const f = fixture({charge() {throw cause;}});
  await assert.rejects(f.reader.read(), error => error === cause);
  assert.equal(f.events.filter(x => x === 'send').length, 1);
  assert.equal(f.events.includes('decode'), false);
  assert.equal(f.reader.observe().responseCount, 1);
  assert.equal(f.reader.observe().receivedBodyBytes, 3n);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
});

test('managed current loss after charging prevents provider decode and delivery', async () => {
  let f;
  f = fixture({charge() {f.notCurrent();}});
  await assert.rejects(f.reader.read(), {code:'InstalledSourceReaderNotCurrent'});
  assert.equal(f.events.filter(x => x === 'charge').length, 1);
  assert.equal(f.events.includes('decode'), false);assert.deepEqual(f.delivered, []);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
});

test('managed reader refuses a foreign later grant without another physical call', async () => {
  const f = fixture({authorize(index, scope) {
    return {grant:{}, useId:`use-${index}`, scope:index === 0 ? scope : {...scope, runInvocationCid:'foreign'}};
  }});
  await assert.rejects(f.reader.read(), {code:'ForeignInstalledSourceReaderAuthorization'});
  assert.equal(f.events.filter(x => x === 'send').length, 1);
  assert.equal(f.delivered.length, 1);
  f.reader.requestStop();assert.equal(f.reader.observe().cleanupConfirmed, true);
});

test('managed reader snapshots original Site and callback methods before the read await', async () => {
  const f = fixture();
  f.site.callResource = f.site.referenceCurrent = f.callbacks.chargePage = f.callbacks.consumePage = () => {
    assert.fail('replacement callback used');
  };
  await f.reader.read();f.reader.requestStop();
  assert.equal(f.reader.observe().cleanupConfirmed, true);
});

test('managed stop waits for the actual original Credential binding while secret resolution is pending', async () => {
  const entered = deferred(), secret = deferred();
  const f = fixture({call: callHttpsCredentialResource,
    resolveSecret() {entered.resolve();return secret.promise;}});
  const reading = f.reader.read();
  await entered.promise;
  f.reader.requestStop(new Error('same stop'));
  assert.equal(f.reader.observe().readPending, true);
  assert.equal(f.reader.observe().transportClosed, false);
  assert.equal(f.reader.observe().cleanupConfirmed, false);
  secret.resolve('secret');
  await assert.rejects(reading, {code:'RemoteCredentialBindingRetiring'});
  assert.equal(f.reader.observe().transportClosed, true);
  assert.equal(f.reader.observe().cleanupConfirmed, true);
  assert.equal(f.events.filter(x => x === 'claim').length, 1);
  assert.equal(f.events.filter(x => x === 'finish').length, 1);
  assert.equal(f.events.includes('charge'), false);
});

test('managed decoder forwards an original wide-number rows wire with the same charge and no JS row conversion', async () => {
  const wire = '[{"id":9007199254740993,"text":"é"}]';
  const f = fixture({pages:[Buffer.from('raw')], decode() {return {rowsWire:wire,rowCount:1,done:true};}});
  // A distinct preparation captures the existing Host wire consumer before
  // read; no provider receives a raw Core admission method.
  let actualWire, ticket;
  f.callbacks.consumePageWire = function(value, originalTicket) {
    assert.strictEqual(this, f.callbacks);actualWire=value;ticket=originalTicket;
  };
  const reader = f.factory.prepare(f.callbacks);
  assert.deepEqual(await reader.read(), {pages:1,rowCount:1});
  assert.strictEqual(actualWire, wire);assert.strictEqual(ticket.charge.body, f.responses[0].body);
  assert.deepEqual(f.delivered, []);
  reader.requestStop();f.reader.requestStop();
  assert.equal(reader.observe().cleanupConfirmed, true);
});


test('managed pure provider setup failure returns its original cleanup handle and sends nothing', async () => {
  const cause = new Error('original decoder unavailable');
  const f = fixture({prepareFailure:cause});
  await assert.rejects(f.reader.read(), error => error === cause);
  assert.equal(f.events.length, 0);
  assert.equal(f.reader.observe().phase, 'failed');
  f.reader.requestStop();
  assert.equal(f.reader.observe().cleanupConfirmed, true);
});

const source = fs.readFileSync(new URL('./installed-credential-source-reader.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const edits = [];
for (const node of tree.body) {
  if (node.type === 'ImportDeclaration') edits.push([node.start, node.end]);
  if (node.type === 'ExportNamedDeclaration') {
    assert(node.declaration); edits.push([node.start, node.declaration.start]);
  }
}
let executable = source;
for (const [start, end] of edits.sort((a, b) => b[0] - a[0])) {
  executable = executable.slice(0, start) + executable.slice(end);
}
const binding = Object.freeze({explicitFixtureBinding: true});
let closes = 0;
const createReader = Function('types', 'ownHttpRequest', 'ownResponseHeaderNames',
  'ownInvocationAuthorization', 'invocationBindingsMatch', 'invokeScopedCredentialOperation',
  'openHttpsCredentialBinding', 'closeHttpsCredentialBinding',
  executable + '\nreturn createInstalledCredentialSourceReader;')(types,
  ownHttpRequest, ownResponseHeaderNames, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation, () => binding, original => {
    assert.equal(original, binding); closes++; return 'closed';
  });


test('returned asynchronous decoder cannot retire its original response borrow before it settles', async () => {
  const entered = Promise.withResolvers(), release = Promise.withResolvers();
  const response = Object.freeze({accepted: true, statusCode: 200,
    useCid: 'sha256:' + 'a'.repeat(64), headers: [], body: new Uint8Array([91, 93])});
  let decoderReply, decoderFinished = false, charges = 0, sends = 0;
  const site = {credential: {}, referenceCurrent() {return true;}, callResource(input) {
    assert.equal(input.binding, binding); sends++; return response;
  }};
  const factory = createReader({capacity: Object.freeze({explicitFixtureDemand: true}), site,
    operation: 'fixture:read', maxResponses: 1, maxResponseBytes: 32, maxSecretBytes: 32,
    preparePageReader() {
      return {fetchPage() {return {method: 'GET', path: '/rows'};}, decodePage(original) {
        assert.equal(original, response);
        decoderReply = release.promise.then(() => {
          assert.equal(original.body, response.body); decoderFinished = true;
          return {rows: [], done: true};
        });
        entered.resolve(); return decoderReply;
      }};
    }});
  const reader = factory.prepare({columns: [], resource: 'records',
    verifyRead() {}, authorizationFor() {return {grant: {}, useId: 'fixture-use',
      scope: {operation: 'fixture:read', resourceOrigin: 'https://fixture.invalid'}};},
    chargePage(bytes) {assert.equal(bytes, response.body); charges++; return {};},
    consumePage() {assert.fail('an invalid asynchronous decoder must never admit rows');}});
  const outcome = reader.read().then(() => undefined, error => error);
  await entered.promise;
  reader.requestStop(new Error('stop while the returned decoder still borrows the response'));
  const retiredBeforeDecoder = reader.observe().cleanupConfirmed;
  // Always settle the exact original computation before any assertions, so
  // even this expected red leaves no background decoder or cleanup process.
  release.resolve(); await decoderReply;
  const error = await outcome;
  reader.retry();
  assert.equal(error?.code, 'InstalledSourcePageCallbackNotSynchronous');
  assert.equal(sends, 1); assert.equal(charges, 1); assert(decoderFinished); assert(closes > 0);
  assert.equal(retiredBeforeDecoder, false, 'the original response is still borrowed by the pending decoder');
  assert.equal(reader.observe().cleanupConfirmed, true);
});

for (const callback of ['prepare', 'fetch', 'error']) {
  test(`refused asynchronous ${callback} callback keeps its original borrow until settlement`, async () => {
    const entered = Promise.withResolvers(), release = Promise.withResolvers();
    const response = Object.freeze({accepted:true, statusCode:200, body:new Uint8Array([91,93])});
    const originalCause = new Error('original projection refusal');
    const lateCause = new Error('original asynchronous error mapper rejected');
    let reply, sends = 0, charges = 0, finished = false;
    const defer = finish => {
      reply = release.promise.then(() => {finished = true;return finish();});
      entered.resolve();return reply;
    };
    const site = {credential:{}, referenceCurrent() {return true;}, callResource() {sends++;return response;}};
    const provider = {
      fetchPage() {
        return callback === 'fetch' ? defer(() => ({method:'GET',path:'/rows'}))
          : {method:'GET',path:'/rows'};
      },
      decodePage(actual) {assert.strictEqual(actual,response);throw originalCause;},
      ...(callback === 'error' ? {onError(cause) {
        assert.strictEqual(cause,originalCause);
        return defer(() => {assert.strictEqual(cause,originalCause);throw lateCause;});
      }} : {}),
    };
    const factory = createReader({capacity:{}, site, operation:'fixture:read',
      maxResponses:1,maxResponseBytes:32,maxSecretBytes:32,
      preparePageReader(input) {
        return callback === 'prepare' ? defer(() => {
          assert.equal(input.requestWire,'same original request');return provider;
        }) : provider;
      }});
    const reader = factory.prepare({columns:[],resource:'records',requestWire:'same original request',
      verifyRead() {},authorizationFor() {return {grant:{},useId:'use',
        scope:{operation:'fixture:read',resourceOrigin:'https://fixture.invalid'}};},
      chargePage(body) {assert.strictEqual(body,response.body);charges++;return {};},
      consumePage() {assert.fail('invalid callbacks cannot admit rows');}});
    const outcome = reader.read().then(() => undefined,error => error);
    await entered.promise;
    reader.requestStop();
    const retiredBeforeSettlement = reader.observe().cleanupConfirmed;
    const pendingBeforeSettlement = reader.observe().pendingCallbacks;
    // Settle and join the exact original before any refusal assertion.
    release.resolve();
    if (callback === 'error') await assert.rejects(reply,error => error === lateCause);
    else await reply;
    const error = await outcome;
    reader.retry();
    assert.equal(error?.code,'InstalledSourcePageCallbackNotSynchronous');
    assert.equal(retiredBeforeSettlement,false);
    assert.equal(pendingBeforeSettlement,1);
    assert.equal(finished,true);
    assert.equal(sends,callback === 'error' ? 1 : 0);
    assert.equal(charges,sends);
    assert.equal(reader.observe().cleanupConfirmed,true);
    assert.equal(reader.observe().pendingCallbacks,0);
  });
}

test('private projection invoker uses the original receiver only within a Host callback frame', async () => {
  let invoke, projections = 0;
  const receiver = Object.freeze({original:'projection receiver'});
  const response = Object.freeze({accepted:true,statusCode:200,body:new Uint8Array([91,93])});
  const site = {credential:{},referenceCurrent() {return true;},callResource() {return response;}};
  const factory = createReader({capacity:{},site,operation:'fixture:read',
    maxResponses:1,maxResponseBytes:32,maxSecretBytes:32,
    preparePageReader(input, project) {
      assert.deepEqual(Object.keys(input).sort(),['columns','requestWire','resource']);
      invoke=project;
      return {fetchPage() {return project(function() {
        assert.strictEqual(this,receiver);projections++;return {method:'GET',path:'/rows'};
      },receiver,[]);},decodePage(original) {return project(function(actual) {
        assert.strictEqual(this,receiver);assert.strictEqual(actual,response);projections++;
        return {rows:[],done:true};
      },receiver,[original]);}};
    }});
  const reader=factory.prepare({columns:[],resource:'records',verifyRead() {},
    authorizationFor() {return {grant:{},useId:'use',
      scope:{operation:'fixture:read',resourceOrigin:'https://fixture.invalid'}};},
    chargePage() {return {};},consumePage() {}});
  const escaped=()=>invoke(()=>{assert.fail('escaped callback invoked');},receiver,[]);
  assert.throws(escaped,{code:'ForeignInstalledSourceProjection'});
  await assert.rejects(Promise.resolve().then(escaped),{code:'ForeignInstalledSourceProjection'});
  await reader.read();reader.requestStop();
  assert.equal(projections,2);assert.equal(reader.observe().cleanupConfirmed,true);
  assert.throws(escaped,{code:'ForeignInstalledSourceProjection'});
});

// Actual service + reader composition. Only installation/Site nominal issuance,
// Core quotes and the physical operation are explicit ports in this component.
const serviceSource = fs.readFileSync(new URL('./installed-host-services.mjs', import.meta.url), 'utf8');
const serviceTree = parse(serviceSource, {ecmaVersion:'latest',sourceType:'module'});
const serviceEdits = serviceTree.body.flatMap(node => node.type === 'ImportDeclaration'
  ? [[node.start,node.end]] : node.type === 'ExportNamedDeclaration'
    ? [[node.start,node.declaration.start]] : []);
let serviceExecutable = serviceSource;
for (const [start,end] of serviceEdits.sort((a,b) => b[0]-a[0])) {
  serviceExecutable = serviceExecutable.slice(0,start)+serviceExecutable.slice(end);
}
async function hostedStandardFixture() {
  const events=[], raw={}, grant={}, credential={}, control={identity:() => 'same-original-grant'};
  const scope=Object.freeze({...Object.fromEntries(credentialInvocationBindingKeys.map(name => [name,name])),
    operation:'fixture:standard',resourceOrigin:'https://example.invalid'});
  const journal={claim(_cid,useId) {return {use:{},record:{grantCid:'same-original-grant',useId},replayed:false};},
    authorize() {},finish() {}};
  const physicalCredential={...credential,control,journal,resolveSecret:() => 'secret'};
  let live=true,closed=false;
  const response=Object.freeze({accepted:true,statusCode:200,body:Buffer.from('same-response')});
  const site=Object.freeze({credential,
    callResource() {assert.equal(this,site);events.push('send');return response;}});
  const originalSite=Object.freeze({site,callResource:site.callResource,
    referenceCurrent() {assert.equal(this,originalSite);return live;},
    authorizationPurpose(value) {assert.equal(value,raw);events.push('purpose');return {kind:'read'};},
    bindRunAcquisition(value,current) {
      assert.equal(value,raw);current.assertCurrent();events.push('bind');
      const binding=Object.freeze({credential:physicalCredential,close() {
        assert.equal(this,binding);closed=true;events.push('close');return 'closed';}});
      return binding;
    }});
  const limits=Object.freeze({...Object.fromEntries([
    'maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth','maxRows','maxTotalRows','maxPages',
    'pageSize','maxCursorBytes','maxIdentityBytes','maxTargetBytes','maxValueNodes','maxValueTextBytes',
    'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth','maxSecretBytes'].map(name => [name,1])),maxResponseBytes:1024,maxSecretBytes:64});
  const capacity={},installation=Object.freeze({}),moon={
    clientProgramInstalledSourceReaderPolicy() {return [64,1,1];},
    clientProgramInstalledJsonSourceReaderCapacity() {return capacity;}};
  const api=Function('openInstalledRowSite','installedRowCredentialOperationSite','runtimeField',
    'runtimeIsBoxedSome','createInstalledCredentialSourceReader','installedJsonSourceReaderLimitNames',
    'installedJsonSourceReaderProfileLimitNames','nodeTypes',serviceExecutable+
    '\nreturn {createInstalledHostServices,retainInstalledHostServiceInstallation};')(
      async () => ({site}),value => {assert.equal(value,credential);return originalSite;},
      (value,index) => value[index],() => false,createInstalledCredentialSourceReader,
      Object.keys(limits).filter(name => name!=='maxSecretBytes'),[],types);
  const services=api.createInstalledHostServices({root:'/UNOPENED/component',principalId:'fixture',moon,
    assertCurrent() {if (!live) throw new Error('same Host current refused');}});
  api.retainInstalledHostServiceInstallation(services,installation,'sha256:'+'a'.repeat(64));
  const implementation=services.sourceReaderImplementation({installation,limits,columnCount:1});
  await services.openRowSite({installation});
  let decoded=0,consumed=0;
  const selection={installation,implementation,site,operation:scope.operation,preparePageReader() {
    return Object.freeze({fetchPage() {events.push('request');return {method:'GET',path:'/one'};},
      decodePage(observed) {assert.equal(observed,response);events.push('decode');decoded++;
        return {rows:[{id:'same'}],done:true};}});
  }};
  const factory=services.createSourceReader(selection);
  const options=Object.freeze({resource:'one',columns:['id'],originalAuthorization:raw,
    verifyRead() {events.push('current');},authorizationFor(index) {
      assert.equal(index,0);return {grant,scope,useId:'one'};},
    chargePage(body) {assert.equal(body,response.body);events.push('charge');return body;},
    consumePage(rows,ticket) {assert.equal(ticket.charge,response.body);assert.deepEqual(rows,[{id:'same'}]);
      events.push('consume');consumed++;}});
  return {events,services,selection,factory,options,capacity,
    inspect:() => ({decoded,consumed,closed}),retireHost:() => {live=false;}};
}

test('normal Source service retains the same nominal Site grant and standard reader through stop',async () => {
  const f=await hostedStandardFixture();
  assert.equal(f.factory.capacity,f.capacity);
  const reader=f.factory.prepare(f.options);
  assert.throws(() => ({...f.factory}).prepare(f.options),{code:'ForeignInstalledCredentialSourceReader'});
  await reader.read();
  assert.deepEqual(f.inspect(),{decoded:1,consumed:1,closed:false});
  for (const [before,after] of [['purpose','bind'],['bind','send'],['charge','decode'],['decode','consume']]) {
    assert(f.events.indexOf(before)<f.events.indexOf(after));
  }
  assert.equal(reader.observe().cleanupConfirmed,false);
  reader.requestStop();
  assert.equal(reader.observe().cleanupConfirmed,true);
  assert.equal(f.inspect().closed,true);
  assert.equal(f.factory.retire(),true);
  assert.throws(() => f.factory.prepare(f.options),{code:'InstalledSourceReaderFactoryClosed'});
});

test('normal standard service refuses copied selection mixed providers and current loss without transport',async () => {
  const f=await hostedStandardFixture();
  for (const selection of [{...f.selection,implementation:{...f.selection.implementation}},
    {...f.selection,site:{...f.selection.site}}]) {
    assert.throws(() => f.services.createSourceReader(selection),{code:'ForeignInstalledSourceReaderSelection'});
  }
  assert.throws(() => f.services.createSourceReader({...f.selection,readPages() {}}),
    {code:'InvalidInstalledSourceReaderSelection'});
  const reader=f.factory.prepare(f.options);f.retireHost();
  await assert.rejects(reader.read(),/same Host current refused/);
  assert.equal(f.events.includes('send'),false);
  reader.requestStop();assert.equal(reader.observe().cleanupConfirmed,true);
});

test('installed Source forwards its exact issued grant and retires the same reader before Site close',async () => {
  const source=fs.readFileSync(new URL('./installed-row-source.mjs',import.meta.url),'utf8');
  const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  let installed;
  for (const node of ast.body) if(node.type==='ExportNamedDeclaration'&&
      node.declaration?.id?.name==='createInstalledRowSource') installed=node.declaration;
  assert(installed);
  let optionsNode,closeNode;
  function visit(node) {
    if(!node||typeof node!=='object')return;
    if(node.type==='VariableDeclarator'&&node.id.name==='readerOptions')optionsNode=node.init;
    if(node.type==='ReturnStatement'&&node.argument?.callee?.object?.name==='Object'&&
        node.argument?.callee?.property?.name==='freeze') {
      const properties=node.argument.arguments[0]?.properties;
      if(properties?.some(property=>property.key?.name==='realizationKey')) {
        closeNode=properties.find(property=>property.key?.name==='close').value;
      }
    }
    for(const value of Object.values(node)) {
      if(Array.isArray(value))for(const child of value)visit(child);
      else if(value&&typeof value==='object')visit(value);
    }
  }
  visit(installed);assert(optionsNode&&closeNode);
  const raw={},grant=Object.freeze({grant:raw,scope:Object.freeze({operation:'same'})});
  const ports={owner:{resource:'same'},columns:['id'],requestWire:'original',preparedRead:{},operation:'same',signal:undefined,
    prepared:{},access:{},currentRead:async()=>{},rowRun:{},withOriginalJob:undefined,isListing:false,
    credentialRead:true,grant,directReadIdentity:undefined,nonce:'original-read',ledger:undefined,run:{},moon:{},
    checked:value=>value,fail:code=>{throw Object.assign(new Error(code),{code});},text:value=>typeof value==='string'};
  const options=Function(...Object.keys(ports),'return ('+source.slice(optionsNode.start,optionsNode.end)+');')(...Object.values(ports));
  assert.equal(options.originalAuthorization,grant);
  const use=await options.authorizationFor(0);
  assert.equal(use.grant,raw);assert.equal(use.scope,grant.scope);assert.equal(use.useId,'original-read-read-0');
  let ready=false;
  const events=[],reader={retire() {assert.equal(this,reader);events.push('retire');return ready;}};
  const site={close() {assert.equal(this,site);events.push('site-close');return 'original-close';}};
  const close=Function('originalReader','site','fail','return function'+source.slice(closeNode.start,closeNode.end))(
    {receiver:reader,retire:reader.retire},site,ports.fail);
  assert.throws(close,{code:'InstalledSourceReaderCleanupPending'});
  assert.deepEqual(events,['retire']);ready=true;
  assert.equal(close(),'original-close');assert.deepEqual(events,['retire','retire','site-close']);
});
