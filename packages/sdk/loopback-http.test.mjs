import assert from 'node:assert/strict';
import test from 'node:test';
import * as http from 'node:http';
import {requestLoopbackClient} from './loopback-http.mjs';

const listen = server => new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen({host: '127.0.0.1', port: 0}, () => {server.off('error', reject); resolve();});
});
const close = server => new Promise(resolve => {server.closeAllConnections(); server.close(resolve);});
const options = signal => ({method: 'POST', redirect: 'error', signal,
  headers: {'content-type': 'application/json', authorization: 'Bearer fixture-only-secret'}, body: '{"request":1}'});

test('direct loopback POST ignores global Fetch and proxy configuration', async t => {
  let proxyRequests = 0, requests = 0;
  const proxy = http.createServer((_request, response) => {proxyRequests++; response.end('unexpected proxy');});
  const server = http.createServer(async (request, response) => {
    requests++;
    assert.equal(request.method, 'POST');
    assert.equal(request.url, '/actql/client/0.1/connect');
    assert.equal(request.headers.authorization, 'Bearer fixture-only-secret');
    let body = ''; for await (const chunk of request) body += chunk;
    assert.equal(body, '{"request":1}');
    response.writeHead(200, {'content-type': 'application/json'}); response.end('{"ok":true}');
  });
  await listen(proxy); await listen(server);
  const oldFetch = globalThis.fetch;
  globalThis.fetch = () => assert.fail('Loopback HTTP must not use a global Fetch dispatcher');
  const restoreProxy = http.setGlobalProxyFromEnv?.({
    HTTP_PROXY: `http://127.0.0.1:${proxy.address().port}`, NO_PROXY: '',
  });
  t.after(async () => {globalThis.fetch = oldFetch; restoreProxy?.(); await close(server); await close(proxy);});
  const response = await requestLoopbackClient(new URL(
    `http://127.0.0.1:${server.address().port}/actql/client/0.1/connect`), options());
  assert.deepEqual(await response.json(), {ok: true});
  assert.equal(requests, 1);
  assert.equal(proxyRequests, 0);
});

test('loopback transport never follows a redirect or sends its bearer to the target', async t => {
  let targetRequests = 0;
  const target = http.createServer((_request, response) => {targetRequests++; response.end();});
  const origin = http.createServer((_request, response) => {
    response.writeHead(307, {location: `http://127.0.0.1:${target.address().port}/elsewhere`}); response.end();
  });
  await listen(target); await listen(origin);
  t.after(async () => {await close(origin); await close(target);});
  await assert.rejects(requestLoopbackClient(new URL(
    `http://127.0.0.1:${origin.address().port}/actql/client/0.1/connect`), options()),
  {message: 'LoopbackRedirectRefused'});
  assert.equal(targetRequests, 0);
});

test('loopback Response streams and cancellation closes the original response', async t => {
  let ended;
  const disconnected = new Promise(resolve => {ended = resolve;});
  const server = http.createServer((request, response) => {
    response.once('close', ended);
    response.writeHead(200, {'content-type': 'application/jsonl'});
    response.write('{"n":1}\n');
  });
  await listen(server); t.after(() => close(server));
  const response = await requestLoopbackClient(new URL(
    `http://127.0.0.1:${server.address().port}/actql/client/0.1/read`), options());
  const reader = response.body.getReader();
  assert.equal(new TextDecoder().decode((await reader.read()).value), '{"n":1}\n');
  await reader.cancel(); reader.releaseLock();
  await disconnected;
});

test('loopback transport refuses invalid targets, port zero and pre-aborted work before network I/O', async () => {
  for (const endpoint of ['http://example.test/actql/client/0.1/connect',
    'https://127.0.0.1/actql/client/0.1/connect', 'http://127.0.0.1:0/actql/client/0.1/connect',
    'http://127.0.0.1/other', 'http://127.0.0.1/actql/client/0.1/connect?other=1']) {
    await assert.rejects(requestLoopbackClient(new URL(endpoint), options()),
      {message: 'InvalidLoopbackClientRequest'});
  }
  const reason = new Error('before-send');
  await assert.rejects(requestLoopbackClient(new URL('http://127.0.0.1:1/actql/client/0.1/connect'),
    options(AbortSignal.abort(reason))), error => error === reason);
});

test('a null-body 205 cannot leave an unbounded response draining', {timeout: 5000}, async t => {
  let ended;
  const disconnected = new Promise(resolve => {ended = resolve;});
  const server = http.createServer((_request, response) => {
    response.once('close', ended);
    response.writeHead(205, {'content-type': 'application/json', 'transfer-encoding': 'chunked'});
    response.write('{"unfinished":');
  });
  await listen(server); t.after(() => close(server));
  const response = await requestLoopbackClient(new URL(
    `http://127.0.0.1:${server.address().port}/actql/client/0.1/connect`), options());
  assert.equal(response.body, null);
  await disconnected;
});
