import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {setImmediate as turn} from 'node:timers/promises';
import {channel} from 'node:diagnostics_channel';

// Delegating observers only: the same pinned Client, BodyReadable and real
// original _destroy drive closure. No fixture callback manufactures an ACK.
const require = createRequire(new URL('./package.json', import.meta.url));
const undici = require('undici');
const OriginalClient = undici.Client;
const bodies = [];
const sockets = [];
const connected = channel('undici:client:connected');
const observeSocket = ({socket}) => {
  const record = {socket, closes: 0};
  socket.once('close', () => { record.closes++; });
  sockets.push(record);
};
connected.subscribe(observeSocket);
undici.Client = new Proxy(OriginalClient, {construct(target, args) {
  const client = Reflect.construct(target, args, target);
  const request = client.request;
  client.request = function(options) {
    return Reflect.apply(request, this, [options]).then(response => {
      const body = response.body;
      const record = {body, iterators: 0, closes: 0, finish: undefined};
      const iterator = body[Symbol.asyncIterator];
      body[Symbol.asyncIterator] = function(...args) {
        record.iterators++;
        return Reflect.apply(iterator, this, args);
      };
      body.once('close', () => { record.closes++; });
      if (response.headers['content-type'] === 'é'.repeat(700)) {
        const destroy = body._destroy;
        body._destroy = function(error, callback) {
          const owner = this;
          record.finish = () => {
            record.finish = undefined;
            Reflect.apply(destroy, owner, [error, callback]);
          };
        };
      }
      bodies.push(record);
      return response;
    });
  };
  return client;
}});
let physical, sdk, chat;
try {
  physical = await import('./_internal/original-undici-transport.mjs');
  sdk = await import('./_internal/intercepted-request.mjs');
  chat = await import('./_internal/openai-chat.mjs');
} finally { undici.Client = OriginalClient; }

const requestLimits = {maxBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16};
const responseLimits = {maxBytes: 4096, maxChunkBytes: 512, maxChunks: 16,
  maxHeaderBytes: 1024, observedHeaders: ['content-type']};
const physicalAcquisitionLimits = {maxPlaintextBytes: 65536,
  maxBorrowedBackingBytes: 131072, maxReads: 64};
async function until(read, accepted) {
  for (let index = 0; index < 1000; index++) {
    const value = read();
    if (accepted(value)) return value;
    await turn();
  }
  assert.fail('Finite original cleanup observation not reached');
}

test('actual SDK header refusal before getReader keeps unread body close pending and another Call alive',
  {timeout: 5000}, async t => {
    const handles = [];
    let requests = 0, secondResponse;
    const server = createServer((request, response) => {
      request.resume();
      requests++;
      // Latin-1 HTTP bytes fit the parser ceiling, but the observed UTF-8
      // header requires 1400 bytes: the bounded reader refuses before read.
      response.setHeader('content-type', requests === 1 ? 'é'.repeat(700) : 'application/json');
      response.write('{');
      if (requests === 2) secondResponse = response;
    });
    try {
      server.listen(0, '127.0.0.1');
      await once(server, 'listening');
      const endpoint = `http://127.0.0.1:${server.address().port}/chat/completions`;
      const fetch = physical.createOriginalUndiciFetch({endpoint,
        requestLimits, responseLimits, physicalAcquisitionLimits});
      async function start() {
        const handle = chat.prepareOpenAIChatRequest({modelId: 'synthetic-model',
          baseURL: endpoint.slice(0, -'/chat/completions'.length), apiKey: 'synthetic-only',
          maxRequestBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16,
          notify() {}, options: {prompt: [{role: 'user', content: [{type: 'text', text: 'original'}]}],
            maxOutputTokens: 16, responseFormat: {type: 'json'}}});
        handles.push(handle);
        await until(() => sdk.pollSdkPreparation(handle), value => value.kind === 'ready');
        sdk.prepareSdkTransport(handle, {fetch, responseLimits, responseMode: 'raw-only'});
        sdk.startSdkTransport(handle); // No Common Entry/authority admission.
        return handle;
      }
      const first = await start();
      await until(() => sdk.pollSdkTransport(first), value => value.kind === 'unknown');
      assert.equal(bodies.length, 1);
      assert.equal(bodies[0].iterators, 0, 'observed-header refusal precedes getReader');
      assert.equal(sdk.sdkTransportRawObservation(first), undefined, 'no invented empty raw body');
      const second = await start();
      await until(() => bodies.length, value => value === 2);
      assert.equal(sdk.cleanupSdkPreparation(first), false);
      await until(() => sockets[0].closes, value => value === 1);
      assert.equal(bodies[0].body.destroyed, true);
      assert.equal(bodies[0].closes, 0, 'socket close is not the unread body close');
      assert.equal(typeof bodies[0].finish, 'function');
      for (let index = 0; index < 4; index++) {
        assert.equal(sdk.cleanupSdkPreparation(first), false);
        assert.equal(sdk.pollSdkTransport(first).kind, 'unknown');
        assert.equal(sdk.pollSdkTransport(second).kind, 'pending');
        assert.equal(sockets[1].closes, 0, 'another Call is not cancelled');
        await turn();
      }
      assert.throws(() => sdk.startSdkTransport(first), {code: 'SdkTransportStartRefused'});
      bodies[0].finish();
      await until(() => sdk.cleanupSdkPreparation(first), value => value === true);
      assert.equal(bodies[0].closes, 1);
      assert.equal(sdk.cleanupSdkPreparation(first), true);
      assert.throws(() => sdk.startSdkTransport(first), {code: 'ForeignSdkPreparation'});
      secondResponse.end('}');
      await until(() => sdk.pollSdkTransport(second), value => value.kind === 'response');
      assert.equal(Buffer.from(sdk.sdkTransportRawObservation(second).body).toString(), '{}');
      await until(() => sdk.cleanupSdkPreparation(second), value => value === true);
      assert.equal(requests, 2, 'one send per original Call, no retry');
      assert.equal(bodies[1].closes, 1);
    } catch (error) {
      t.diagnostic(JSON.stringify({primary: error.message, stack: error.stack,
        requests, bodies: bodies.map(record => ({iterators: record.iterators,
          closes: record.closes, delayed: typeof record.finish === 'function'})),
        socketCloses: sockets.map(record => record.closes)}));
      throw error;
    } finally {
      for (const record of bodies) record.finish?.();
      try {
        for (const handle of handles) {
          await until(() => {
            for (const record of bodies) record.finish?.();
            return sdk.cleanupSdkPreparation(handle);
          }, value => value === true);
        }
      } finally {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
        connected.unsubscribe(observeSocket);
      }
    }
  });
