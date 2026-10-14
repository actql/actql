import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {once} from 'node:events';

// Actual pinned Client/HTTP with a delegating response-access observer. This
// counts the original headers borrow, not heap bytes/GC, a Model ACK or grant.
const require = createRequire(new URL('./package.json', import.meta.url));
const undici = require('undici');
const OriginalClient = undici.Client;
let headersReads = 0;
let originalHeaders;
undici.Client = new Proxy(OriginalClient, {construct(target, args) {
  const client = Reflect.construct(target, args, target);
  const request = client.request;
  client.request = function(options) {
    return Reflect.apply(request, this, [options]).then(response => new Proxy(response, {
      get(original, name, receiver) {
        if (name === 'headers') {headersReads++; originalHeaders = original.headers;}
        return Reflect.get(original, name, receiver);
      },
    }));
  };
  return client;
}});
let physical;
try { physical = await import('./_internal/original-undici-transport.mjs'); }
finally { undici.Client = OriginalClient; }

test('original headers are borrowed once without retaining the full response through every getter', async () => {
  const server = createServer((request, response) => {
    request.resume();
    response.setHeader('content-type', 'application/json');
    response.setHeader('x-many', ['a', 'b']);
    response.end('{}');
  });
  let call;
  try {
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const endpoint = `http://127.0.0.1:${server.address().port}/chat/completions`;
    const limits = {maxBytes: 256, maxChunkBytes: 256, maxChunks: 8,
      maxHeaderBytes: 1024, observedHeaders: ['content-type']};
    const fetch = physical.createOriginalUndiciFetch({endpoint,
      requestLimits: {maxBytes: 256, maxHeaderBytes: 1024, maxHeaders: 8}, responseLimits: limits,
      physicalAcquisitionLimits: {maxPlaintextBytes: 65536, maxBorrowedBackingBytes: 131072, maxReads: 64}});
    call = physical.prepareOriginalUndiciFetch(fetch, endpoint, {method: 'POST', body: '{}', headers: [],
      redirect: 'error', signal: new AbortController().signal}, limits);
    const view = await call.invoke();
    assert.equal(view.headers.get('CONTENT-TYPE'), 'application/json');
    assert.equal(view.headers.get('x-many'), 'a, b');
    assert.equal(view.headers.get('x-absent'), null);
    assert.equal(headersReads, 1, 'the response box is inspected once, not captured by every query');
    // The SAME original header map/duplicate array remains borrowed. Do not
    // silently copy or freeze it, manufacture defaults, or retire its alias.
    originalHeaders['x-many'].push('c');
    assert.equal(view.headers.get('x-many'), 'a, b, c');
    assert.equal(headersReads, 1);
    await view.body.cancel();
    assert.equal(await call.cleanup(), true);
    assert.equal(await call.cleanup(), true);
    assert.equal(view.headers.get('x-many'), 'a, b, c', 'escaped original header view is unchanged');
  } finally {
    if (call !== undefined) await call.cleanup();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});
