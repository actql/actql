// Actual TLS/Undici witness for the original preallocated native input. It is
// not a Model/Resource admission test, live Provider or complete numeric profile.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createServer} from 'node:https';
import {syncBuiltinESMExports} from 'node:module';
import tls from 'node:tls';
import {createOriginalUndiciFetch, prepareOriginalUndiciFetch} from
  './_internal/original-undici-transport.mjs';

const execute = promisify(execFile);

async function witness() {
  assert.equal(process.versions.node, '22.22.0');
  const expected = Buffer.alloc(8192);
  for (let index = 0; index < expected.length; index++) expected[index] = index % 251;
  const key = await readFile(process.env.ACTQL_TEST_ORIGINAL_TLS_KEY);
  const cert = await readFile(process.env.ACTQL_TEST_ORIGINAL_TLS_CERT);
  let requests = 0, secureConnections = 0, requestBytes = 0;
  let resolveWritten;
  const written = new Promise(resolve => { resolveWritten = resolve; });
  const serverSockets = new Set();
  const server = createServer({key, cert}, async (request, response) => {
    requests++;
    assert.equal(request.method, 'POST');
    assert.equal(request.url, '/chat/completions');
    for await (const bytes of request) requestBytes += bytes.length;
    response.writeHead(200, {'content-type': 'application/octet-stream',
      'content-length': expected.length, connection: 'close'});
    response.flushHeaders();
    // Separate peer writes ensure the same native input is refilled, not a
    // one-record test that could hide aliases to its reusable backing.
    for (let offset = 0; offset < expected.length; offset += 1024) {
      await new Promise(resolve => setTimeout(resolve, 2));
      response.write(expected.subarray(offset, offset + 1024));
    }
    response.end();
    resolveWritten();
  });
  server.on('secureConnection', socket => {
    secureConnections++;
    serverSockets.add(socket);
    socket.once('close', () => serverSockets.delete(socket));
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
  });
  const endpoint = `https://127.0.0.1:${server.address().port}/chat/completions`;
  const limits = {maxBytes: 8192, maxChunkBytes: 8192, maxChunks: 32,
    maxHeaderBytes: 16384, observedHeaders: ['content-type']};
  const slow = Buffer.allocUnsafeSlow, connect = tls.connect;
  const allocations = [];
  let clientSocket, closes = 0, preparing = false, call;
  Buffer.allocUnsafeSlow = function(length) {
    const bytes = Reflect.apply(slow, Buffer, [length]);
    if (new Error().stack.includes('/_internal/original-undici-transport.mjs:')) {
      allocations.push({bytes, preparation: preparing});
    }
    return bytes;
  };
  tls.connect = function(...args) {
    assert.equal(clientSocket, undefined, 'the same Call must not reconnect');
    clientSocket = Reflect.apply(connect, tls, args);
    clientSocket.once('close', () => { closes++; });
    return clientSocket;
  };
  syncBuiltinESMExports();
  try {
    const fetch = createOriginalUndiciFetch({endpoint,
      requestLimits: {maxBytes: 4096, maxHeaderBytes: 4096, maxHeaders: 16},
      responseLimits: limits,
      physicalAcquisitionLimits: {maxPlaintextBytes: 65536,
        maxBorrowedBackingBytes: 131072, maxReads: 64}});
    preparing = true;
    call = prepareOriginalUndiciFetch(fetch, endpoint, {method: 'POST', body: '{}',
      redirect: 'error', headers: [], signal: new AbortController().signal}, limits);
    preparing = false;
    assert.equal(requests, 0);
    assert.equal(clientSocket, undefined);
    const prepared = allocations.filter(value => value.preparation);
    assert.equal(prepared.length, 1);
    const input = prepared[0].bytes;
    assert.equal(input.byteOffset, 0);
    assert.equal(input.buffer.byteLength, 8192);
    const response = await call.invoke();
    assert.equal(response.status, 200);
    // Let TLS refill the input repeatedly before exposing any body borrower.
    await written;
    const reader = response.body.getReader();
    const received = [];
    for (;;) {
      const next = await reader.read();
      if (next.done) break;
      assert.notEqual(next.value.buffer, input.buffer);
      received.push(next.value);
    }
    reader.releaseLock();
    assert.deepEqual(Buffer.concat(received), expected);
    const copies = allocations.filter(value => !value.preparation);
    assert.ok(copies.length >= 2, 'observe multiple copies from the same TLS input');
    for (const {bytes} of copies) {
      assert.equal(bytes.byteOffset, 0);
      assert.equal(bytes.buffer.byteLength, bytes.byteLength);
      assert.notEqual(bytes.buffer, input.buffer);
    }
    assert.equal(await call.cleanup(), true);
    assert.equal(closes, 1);
    assert.equal(requests, 1);
    assert.equal(secureConnections, 1);
    assert.equal(requestBytes, 2);
    // This diagnostic alone retains the native input beyond the real ACK.
    // Mutating it cannot alter any escaped body bytes or imply physical GC.
    input.fill(90);
    assert.deepEqual(Buffer.concat(received), expected);
    return {scenario: 'original-native-input-real-tls', passed: 1,
      requests, secureConnections, closes, requestBytes,
      inputBackingBytes: input.buffer.byteLength, acceptedBodyBytes: expected.length,
      observedCopies: copies.length, normalNumericProfile: null, publicE2E: 0};
  } finally {
    preparing = false;
    try {
      if (call !== undefined) assert.equal(await call.cleanup(), true);
    } finally {
      Buffer.allocUnsafeSlow = slow; tls.connect = connect; syncBuiltinESMExports();
      for (const socket of serverSockets) socket.destroy();
      await new Promise(resolve => server.close(resolve));
    }
  }
}

if (process.env.ACTQL_TEST_ORIGINAL_TLS_CHILD === '1') {
  console.log(JSON.stringify(await witness()));
} else {
  test('original native input survives actual TLS reuse and same connection cleanup', async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-c-native-input-tls-'));
    const key = join(directory, 'key.pem'), cert = join(directory, 'cert.pem');
    let passed = false;
    t.after(async () => {
      if (passed) await rm(directory, {recursive: true, force: true});
      else t.diagnostic(`Preserved original TLS witness failure: ${directory}`);
    });
    // Ephemeral loopback-only credentials. No disabling peer verification,
    // live credentials, Provider request, system trust-store change or retry.
    await execute('/usr/bin/openssl', ['req', '-x509', '-newkey', 'rsa:2048',
      '-nodes', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=IP:127.0.0.1', '-keyout', key, '-out', cert],
    {timeout: 10000, maxBuffer: 1048576});
    const result = await execute(process.execPath, [fileURLToPath(import.meta.url)],
      {timeout: 15000, maxBuffer: 1048576, env: {...process.env,
        NODE_EXTRA_CA_CERTS: cert, ACTQL_TEST_ORIGINAL_TLS_CHILD: '1',
        ACTQL_TEST_ORIGINAL_TLS_KEY: key, ACTQL_TEST_ORIGINAL_TLS_CERT: cert}});
    const report = JSON.parse(result.stdout.trim());
    assert.equal(report.scenario, 'original-native-input-real-tls');
    assert.equal(report.passed, 1);
    assert.equal(report.requests, 1);
    assert.equal(report.secureConnections, 1);
    assert.equal(report.closes, 1);
    assert.equal(report.publicE2E, 0);
    t.diagnostic(JSON.stringify(report));
    passed = true;
  });
}
