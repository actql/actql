import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {createBoundedOtlpSender} from './transport.mjs';
import {managedLimits} from './configuration.mjs';

test('managed transport caps bytes and records and retains slot until close', async t => {
  const bodies = [];
  const server = createServer(async (request, response) => {
    assert.equal(request.headers['content-type'], 'application/x-protobuf');
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    bodies.push(Buffer.concat(chunks));
    response.end();
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const sender = createBoundedOtlpSender(`http://127.0.0.1:${server.address().port}/v1/traces`,
    {...managedLimits, payloadBytes: 3, windowRecords: 1});
  await assert.rejects(sender.send(new Uint8Array(4)), {message: 'ObservationSenderLimited'});
  await sender.send(new Uint8Array([1, 2, 3]));
  await assert.rejects(sender.send(new Uint8Array(1)), {message: 'ObservationSenderLimited'});
  assert.deepEqual(bodies, [Buffer.from([1, 2, 3])]);
  assert.equal(sender.status().active, 0);
  assert.equal(sender.status().windowBytes, 3);
  await sender.close();
});

test('hung response times out physically without retry and shutdown releases sender', async t => {
  let calls = 0;
  const server = createServer(() => { calls++; }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  const sender = createBoundedOtlpSender(`http://127.0.0.1:${server.address().port}/v1/logs`,
    {...managedLimits, exportTimeoutMs: 30});
  await assert.rejects(sender.send(new Uint8Array([1])), {message: 'ObservationExportFailed'});
  assert.equal(calls, 1);
  assert.equal(sender.status().active, 0);
  assert.equal(sender.status().failed, 1);
  await sender.close();
});

test('oversized acknowledgement and HTTP errors cannot be reported as exported', async t => {
  const server = createServer((request, response) => {
    request.resume();
    response.end(Buffer.alloc(5));
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  const sender = createBoundedOtlpSender(`http://127.0.0.1:${server.address().port}/v1/metrics`,
    {...managedLimits, responseBytes: 4});
  await assert.rejects(sender.send(new Uint8Array([1])), {message: 'ObservationExportFailed'});
  assert.equal(sender.status().sent, 0);
  await sender.close();
});
