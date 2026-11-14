import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createClientHttpHandler} from './client-http.mjs';

test('HTTP ingress requires Request preparation before installing a handler', () => {
  let calls = 0;
  const installation = {
    authenticate() {calls++; return 'principal';},
    authorizeConnection() {calls++; return true;},
  };
  // Missing preparation cannot select an unprepared dispatch route. The
  // rejection is installation failure, not a submitted operation outcome.
  assert.throws(() => createClientHttpHandler(installation),
    {name: 'TypeError', message: 'InvalidClientHostInstallation'});
  assert.equal(calls, 0);
});

// Actual Node HTTP input and wire validation; Resource/preflight are explicit
// ports here. The separate Core case owns measured geometry, not this fixture.
async function rawHttpFixture(run, {maxRequestBytes = 65536, denyAuth = false,
  denyConnection = false, failRead = false, failJson = false} = {}) {
  const events = [], current = {}, parent = {}, receivers = [];
  let ownReads = 0, opened = 0, prepared = 0;
  const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
    durability: 'volatile', scopeRef: 'raw-input', capabilities: ['aql-document'],
    limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
      maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};
  const prepare = () => assert.fail('Raw input must not open a second Request');
  Object.defineProperty(prepare, 'beforeBody', {value(operation, limit) {
    opened++; events.push('parent');
    assert.equal(operation, 'connect'); assert.equal(limit, maxRequestBytes);
    const receiver = {
      beforeRead(bytes, chunks, quantum) {
        assert.strictEqual(this, receiver); assert.strictEqual(current.parent, parent);
        assert(Number.isSafeInteger(bytes) && bytes <= limit + 1);
        assert(Number.isSafeInteger(chunks) && chunks > 0);
        assert(Number.isSafeInteger(quantum) && quantum > 0 && quantum <= limit + 1);
        events.push('reserve');
        if (failRead) throw Object.assign(new Error('same raw refusal'), {code: 'ClientRequestTooLarge'});
        current.reserved = true;
      },
      beforeJson(wire) {
        assert.strictEqual(this, receiver); assert.strictEqual(current.parent, parent);
        events.push('geometry'); assert.equal(typeof wire, 'string');
        if (failJson) throw Object.assign(new Error('same current refusal'), {code: 'ClientConnectionDenied'});
      },
      prepareRequest(request) {
        assert.strictEqual(this, receiver); assert.strictEqual(current.parent, parent);
        prepared++; events.push('snapshot');
        return {body: request, bindRequest() {}, beforeReply() {events.push('reply');},
          finish(terminal) {events.push(`finish:${terminal}`);}};
      },
      finish(terminal) {
        assert.strictEqual(this, receiver); events.push(`raw-finish:${terminal}`);
      },
    };
    current.parent = parent; receivers.push(receiver); return receiver;
  }});
  const handler = createClientHttpHandler({maxRequestBytes, prepareRequest: prepare,
    authenticate() {events.push('authenticate'); return denyAuth ? undefined : 'principal';},
    authorizeConnection() {events.push('authorize'); return !denyConnection;},
    negotiate() {events.push('dispatch'); return profile;}});
  const active = new Set();
  const server = createServer((request, response) => {
    const read = request.read;
    request.read = function(count) {
      if (Number.isInteger(count) && count > 0) {
        ownReads++;
        assert.strictEqual(current.parent, parent);
        assert.equal(current.reserved, true, 'Reserve before the consumer read(n)');
      }
      return Reflect.apply(read, this, [count]);
    };
    const handled = handler(request, response); active.add(handled);
    handled.finally(() => active.delete(handled)).catch(() => {});
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    await run({url: `http://127.0.0.1:${server.address().port}/actql/client/0.1/connect`,
      events, receivers, inspect: () => ({ownReads, opened, prepared})});
  } finally {
    server.closeAllConnections();
    await Promise.allSettled([...active]);
    await new Promise(resolve => server.close(resolve));
  }
}
const rawBody = JSON.stringify({connection: {mode: 'local', owner: 'local',
  consentRefs: [], runners: []}});
const postRaw = (url, body = rawBody) => fetch(url, {method: 'POST',
  headers: {'content-type': 'application/json'}, body, signal: AbortSignal.timeout(10000)});

test('HTTP raw input reserves one original before own read and decodes before authorization and snapshot', async () => {
  await rawHttpFixture(async ({url, events, inspect}) => {
    const response = await postRaw(url);
    assert.equal(response.status, 200); assert.equal((await response.json()).scopeRef, 'raw-input');
    assert.deepEqual(inspect().opened, 1); assert.equal(inspect().prepared, 1);
    assert(inspect().ownReads > 0);
    assert(events.indexOf('authenticate') < events.indexOf('parent'));
    assert(events.indexOf('parent') < events.indexOf('reserve'));
    assert(events.indexOf('reserve') < events.indexOf('geometry'));
    assert(events.indexOf('geometry') < events.indexOf('authorize'));
    assert(events.indexOf('authorize') < events.indexOf('snapshot'));
    assert(events.indexOf('snapshot') < events.indexOf('dispatch'));
    assert.equal(events.filter(value => value === 'finish:returned').length, 1);
    assert.equal(events.filter(value => value.startsWith('raw-finish')).length, 0);
  });
});

test('HTTP raw refusal preserves its primary before read and before JSON construction', async () => {
  for (const [options, status, code, beforeRead] of [
    [{failRead: true}, 413, 'ClientRequestTooLarge', true],
    [{failJson: true}, 403, 'ClientConnectionDenied', false],
  ]) await rawHttpFixture(async ({url, events, inspect}) => {
    const response = await postRaw(url);
    assert.equal(response.status, status); assert.deepEqual(await response.json(), {code});
    assert.equal(inspect().prepared, 0);
    if (beforeRead) assert.equal(inspect().ownReads, 0);
    assert.equal(events.includes('authorize'), false);
    assert.equal(events.includes('dispatch'), false);
    assert.equal(events.filter(value => value === 'raw-finish:failed').length, 1);
  }, options);
});

test('HTTP raw input keeps authentication wire UTF8 and connection refusal boundaries', async () => {
  for (const [options, body, status, code] of [
    [{denyAuth: true}, rawBody, 403, 'ClientAuthenticationDenied'],
    [{maxRequestBytes: 16}, rawBody, 413, 'ClientRequestTooLarge'],
    [{}, Buffer.from([0xff]), 400, 'InvalidClientRequest'],
    [{}, '{', 400, 'InvalidClientRequest'],
    [{denyConnection: true}, rawBody, 403, 'ClientConnectionDenied'],
  ]) await rawHttpFixture(async ({url, events, inspect}) => {
    const response = await postRaw(url, body);
    assert.equal(response.status, status); assert.deepEqual(await response.json(), {code});
    assert.equal(inspect().prepared, 0); assert.equal(events.includes('dispatch'), false);
    if (options.denyAuth) {assert.equal(inspect().opened, 0); assert.equal(inspect().ownReads, 0);}
    else assert.equal(events.filter(value => value === 'raw-finish:failed').length, 1);
  }, options);
});
