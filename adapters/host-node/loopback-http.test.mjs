import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer, request} from 'node:http';
import {Server, Socket} from 'node:net';
import {isLoopbackSocketAddress, isLoopbackHttpRequest} from './loopback-http.mjs';
import {createClientHttpHandler} from './client-http.mjs';

test('loopback addresses exclude wildcard, mapped, named and malformed alternatives', () => {
  for (const value of ['127.0.0.1', '127.20.30.40', '127.255.255.255', '::1']) {
    assert.equal(isLoopbackSocketAddress(value), true);
  }
  for (const value of [undefined, null, {}, 'localhost', '127.1', '127.000.0.1',
    '0.0.0.0', '::', '::ffff:127.0.0.1', '192.168.1.1', '203.0.113.1']) {
    assert.equal(isLoopbackSocketAddress(value), false);
  }
  assert.equal(isLoopbackHttpRequest({socket: {localAddress: '127.0.0.1', remoteAddress: '127.0.0.1',
    server: {address: () => ({address: '127.0.0.1', port: 80})}}}), false);
  const socket = new Socket();
  socket.server = new Server();
  assert.equal(isLoopbackHttpRequest({socket}), false);
});

for (const host of ['127.0.0.1', '::1']) {
  test(`actual ${host} HTTP ingress uses the accepting listener rather than request headers`, async t => {
    const observations = [];
    const server = createServer((req, res) => {
      observations.push(isLoopbackHttpRequest(req)); res.end('ok');
    });
    await new Promise((resolve, reject) => {server.once('error', reject);
      server.listen({host, port: 0}, () => {server.off('error', reject); resolve();});});
    t.after(() => new Promise(resolve => {server.closeAllConnections(); server.close(resolve);}));
    await new Promise((resolve, reject) => {
      const req = request({hostname: host, port: server.address().port, path: '/', method: 'POST',
        agent: false, headers: {host: 'untrusted.example', forwarded: 'for=203.0.113.1;host=localhost',
          'x-forwarded-for': '203.0.113.1'}}, res => {res.resume(); res.on('end', resolve);});
      req.once('error', reject); req.end();
    });
    assert.deepEqual(observations, [true]);
  });
}

test('untrusted physical ingress is refused before auth despite spoofed local headers', async () => {
  const server = new Server();
  const address = Server.prototype.address;
  let observedBind;
  Server.prototype.address = function() {return this === server ? observedBind : address.call(this);};
  let authentication = 0, authorization = 0, workspace = 0, preparation = 0;
  const handler = createClientHttpHandler({loopbackHttp: true,
    authenticate() {authentication++; return 'owner';},
    authorizeConnection() {authorization++; return true;},
    workspaceForPrincipal() {workspace++; return 'workspace';},
    prepareRequest() {preparation++; assert.fail('No Request preparation before physical admission');},
  });
  try {
    // Synthetic facts only: this test never binds a public/wildcard listener.
    for (const [bound, local, remote, encrypted] of [
      [{address: '0.0.0.0', port: 1234}, '127.0.0.1', '127.0.0.1', false],
      [{address: '::', port: 1234}, '::1', '::1', false],
      [{address: '192.168.1.1', port: 1234}, '192.168.1.1', '127.0.0.1', false],
      [{address: '127.0.0.1', port: 1234}, '127.0.0.1', '203.0.113.1', false],
      [{address: '127.0.0.1', port: 1234}, '127.0.0.1', '::ffff:127.0.0.1', false],
      [{address: '127.0.0.1', port: 1234}, '127.0.0.1', '127.0.0.1', true],
      [null, '127.0.0.1', '127.0.0.1', false],
      ['/tmp/socket', '127.0.0.1', '127.0.0.1', false],
      [{address: '127.0.0.1', port: 9999}, '127.0.0.1', '127.0.0.1', false],
    ]) {
      observedBind = bound;
      const socket = new Socket(); socket.server = server;
      Object.defineProperties(socket, {localAddress: {value: local}, remoteAddress: {value: remote},
        localPort: {value: 1234}, encrypted: {value: encrypted}});
      let status, body;
      await handler({socket, headers: {host: 'localhost:1234', 'x-forwarded-for': '127.0.0.1',
        forwarded: 'for=127.0.0.1;host=localhost', authorization: 'Bearer fixture-only'},
      get method() {assert.fail('No request parsing before physical admission');}}, {
        writeHead(code) {status = code;}, end(value) {body = JSON.parse(value);},
      });
      assert.equal(status, 403);
      assert.deepEqual(body, {code: 'ClientConnectionDenied'});
    }
    assert.deepEqual({authentication, authorization, workspace, preparation},
      {authentication: 0, authorization: 0, workspace: 0, preparation: 0});
  } finally {Server.prototype.address = address;}
});
