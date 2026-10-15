import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {channel} from 'node:diagnostics_channel';
import {setImmediate as turn} from 'node:timers/promises';

// Delay each SAME original _destroy, not a synthetic close callback/event.
// Entry, saved receipt and Common projection below are explicit doubles.
// This verifies physical ordering, not numerical capacity or public adoption.
const require = createRequire(new URL('./package.json', import.meta.url));
const undici = require('undici');
const OriginalClient = undici.Client;
const bodies = [];
const sockets = [];
function delayOriginalClose(owner) {
  const destroy = owner._destroy;
  const record = {owner, finish: undefined, closes: 0};
  owner.once('close', () => { record.closes++; });
  owner._destroy = function(error, callback) {
    assert.strictEqual(this, owner);
    assert.equal(record.finish, undefined, 'one original destruction');
    record.finish = () => {
      record.finish = undefined;
      Reflect.apply(destroy, owner, [error, callback]);
    };
  };
  return record;
}
const connected = channel('undici:client:connected');
const onConnected = ({socket}) => { sockets.push(delayOriginalClose(socket)); };
connected.subscribe(onConnected);
undici.Client = new Proxy(OriginalClient, {construct(target, args) {
  const client = Reflect.construct(target, args, target);
  const request = client.request;
  client.request = function(options) {
    return Reflect.apply(request, this, [options]).then(response => {
      bodies.push(delayOriginalClose(response.body));
      return response;
    });
  };
  return client;
}});
let physical, sdk, port;
try {
  physical = await import('./_internal/original-undici-transport.mjs');
  sdk = await import('./_internal/intercepted-request.mjs');
  port = await import('./_internal/model-port.mjs');
} finally { undici.Client = OriginalClient; }

async function until(read, accepted) {
  for (let index = 0; index < 1000; index++) {
    const value = read();
    if (accepted(value)) return value;
    await turn();
  }
  assert.fail('Original finite body/Socket boundary did not settle');
}

test('normal saved Chat projection follows same body close but not delayed Socket close',
  {timeout: 10000}, async t => {
    const firstBody = bodies.length, firstSocket = sockets.length;
    const wire = '{"choices":[{"index":0,"message":{"content":"{}"},"finish_reason":"stop"}],"usage":null}';
    const limits = {maxBytes: 512, maxChunkBytes: 512, maxChunks: 8,
      maxHeaderBytes: 1024, observedHeaders: ['content-type']};
    let sends = 0, saves = 0, projections = 0, raw, holdingReleased = false;
    let handle, call;
    const server = createServer((request, response) => {
      request.resume(); sends++;
      response.setHeader('content-type', 'application/json');
      response.setHeader('x-unselected', 'original-header');
      response.end(wire);
    });
    t.after(async () => {
      for (const item of bodies.slice(firstBody)) item.finish?.();
      for (const item of sockets.slice(firstSocket)) item.finish?.();
      holdingReleased = true;
      try {
        if (call !== undefined) await until(() => call.cleanup(), value => value === true);
        else if (handle !== undefined) await until(() => sdk.cleanupSdkPreparation(handle), value => value === true);
      } finally {
        connected.unsubscribe(onConnected);
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      }
    });
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    const endpoint = `http://127.0.0.1:${server.address().port}/chat/completions`;
    const fetch = physical.createOriginalUndiciFetch({endpoint,
      requestLimits: {maxBytes: 256, maxHeaderBytes: 1024, maxHeaders: 8},
      responseLimits: limits, physicalAcquisitionLimits: {
        maxPlaintextBytes: 65536, maxBorrowedBackingBytes: 131072, maxReads: 64}});
    handle = sdk.interceptSdkRequest({endpoint, maxRequestBytes: 256,
      maxHeaderBytes: 1024, maxHeaders: 8, notify() {},
      async runSdk(intercepted, signal) {
        await intercepted(endpoint, {method: 'POST', body: '{}', signal});
        assert.fail('raw-only mode must not deliver an SDK response copy');
      }});
    const request = Object.freeze({original: Symbol('request double')});
    const entry = Object.freeze({original: Symbol('Entry double')});
    const moon = {
      clientProgramModelRequestPreflight: (advance, cleanup) => ({advance, cleanup}),
      clientProgramModelAsyncPhysicalRequestPlan: (...args) => ({start: args.at(-1)}),
      clientProgramModelPhysicalCallForRequest(actual, original, poll, cancel, cleanup) {
        assert.strictEqual(actual, entry); assert.strictEqual(original, request);
        return {poll, cancel, cleanup};
      },
      clientProgramModelPhysicalPending: () => ({kind: 'pending'}),
      clientProgramModelPhysicalUnknown: () => ({kind: 'unknown'}),
      clientProgramModelPhysicalSavedChat(response) {
        projections++;
        assert.equal(bodies[firstBody].closes, 1, 'actual same body must have closed');
        assert.equal(sockets[firstSocket].closes, 0, 'Socket ACK is still separate');
        return {kind: 'saved', response};
      },
      clientProgramModelPhysicalIoObservation: (original, quiescent, inner) =>
        ({original, quiescent, inner}),
    };
    const owner = port.createSdkModelPreflight({moon, request, preparation: handle,
      profile: {}, installation: {}, quantities: {tokens: 1n, costUnits: 0n, durationMs: 1n},
      fetch, responseLimits: limits, checked: value => value, notify() {},
      observeAt: () => '2026-10-16T00:00:00.000Z',
      persistRaw(original, observed) {
        assert.strictEqual(original, call); saves++; raw = observed;
        return {response: {raw, original: Symbol('saved receipt double')}};
      }, cleanupRaw: () => holdingReleased});
    const {_1: plan} = await until(() => owner.preflight.advance(), value => value._0);
    assert.ok(plan);
    call = plan.start(entry);
    assert.ok(call);
    const body = await until(() => bodies[firstBody], value => value?.finish !== undefined);
    assert.equal(body.owner.readableEnded, true, 'HTTP EOF alone is not the close event');
    assert.equal(body.closes, 0);
    for (let index = 0; index < 4; index++) {
      assert.equal(call.poll().inner.kind, 'pending');
      assert.equal(sdk.pollSdkTransport(handle).kind, 'pending');
      assert.equal(saves, 0); assert.equal(projections, 0);
      await turn();
    }
    body.finish();
    const observed = await until(() => call.poll(), value => value.inner?.kind === 'saved');
    assert.equal(await raw.readerRetirement, true);
    assert.equal(raw.transportComplete, true);
    assert.equal(raw.issue, undefined);
    assert.equal(Buffer.from(raw.body).toString('utf8'), wire);
    assert.deepEqual(raw.headers, [['content-type', 'application/json']]);
    assert.equal(observed.quiescent, false);
    const originalView = observed.inner;
    assert.equal(call.cleanup(), false, 'Store/raw holding is still pending');
    const socket = await until(() => sockets[firstSocket], value => value?.finish !== undefined);
    assert.equal(socket.closes, 0);
    socket.finish();
    const closed = await until(() => call.poll(), value => value.quiescent === true);
    assert.strictEqual(closed.inner, originalView);
    assert.equal(body.closes, 1); assert.equal(socket.closes, 1);
    assert.equal(call.cleanup(), false);
    holdingReleased = true;
    await until(() => call.cleanup(), value => value === true);
    assert.equal(plan.start(entry), undefined);
    assert.equal(sends, 1); assert.equal(saves, 1); assert.equal(projections, 1);
    assert.equal(Buffer.from(raw.body).toString('utf8'), wire, 'escaped raw stays unchanged');
  });
