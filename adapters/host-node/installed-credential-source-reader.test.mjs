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
