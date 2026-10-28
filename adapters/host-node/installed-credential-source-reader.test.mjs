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
  charge, decode, current, authorize, call, resolveSecret} = {}) {
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
      prepared++;assert.deepEqual(input, {resource: 'records', columns: ['id'], requestWire: 'original-request'});
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
