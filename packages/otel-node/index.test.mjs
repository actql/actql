import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {createNodeHostObservability} from './index.mjs';
import {installHostObservation} from '../local-node/adapters/host-common/observation.mjs';
import {field, assertNoMetricExemplars} from './test/otlp-fixture.mjs';

const parent = {traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1};
async function collector(t, failure = false) {
  const packets = [];
  const server = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    packets.push({path: request.url, type: request.headers['content-type'],
      body: Buffer.concat(chunks)});
    if (failure && request.url === '/v1/traces') response.statusCode = 503;
    response.end();
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  return {packets, endpoint: `http://127.0.0.1:${server.address().port}`};
}

test('managed SDK exports real protobuf with caller correlation and no content in any signal', async t => {
  const sink = await collector(t);
  const adapter = createNodeHostObservability({endpoint: sink.endpoint,
    metrics: {endpoint: `${sink.endpoint}/v1/metrics`},
    logs: {endpoint: `${sink.endpoint}/v1/logs`}});
  const observer = installHostObservation(adapter.connection);
  t.after(async () => { await observer.close(); await adapter.close(); });
  let contentReads = 0;
  const facts = {outcome: 'failed', task: 0};
  Object.defineProperty(facts, 'query', {get() { contentReads++; return 'SECRET_SENTINEL'; }});
  await observer.run('check', {...parent, baggage: {secret: 'SECRET_SENTINEL'}}, async () => {
    observer.emit('check', 'check_completed', facts);
  });
  await observer.close();
  assert.equal(contentReads, 0);
  assert.deepEqual([...new Set(sink.packets.map(packet => packet.path))].sort(),
    ['/v1/logs', '/v1/metrics', '/v1/traces']);
  for (const packet of sink.packets) {
    assert.equal(packet.type, 'application/x-protobuf');
    assert.equal(packet.body.includes(Buffer.from('SECRET_SENTINEL')), false);
    assert.ok(packet.body.length > 0 && packet.body.length <= 65536);
  }
  const packet = sink.packets.find(item => item.path === '/v1/traces');
  const span = field(field(field(packet.body, 1), 2), 2);
  assert.equal(field(span, 1).toString('hex'), parent.traceId);
  assert.equal(field(span, 4).toString('hex'), parent.spanId);
  assert.equal(field(span, 5).toString(), 'actql.check');
  for (const metric of sink.packets.filter(item => item.path === '/v1/metrics')) {
    assert.equal(metric.body.includes(Buffer.from(parent.traceId, 'hex')), false);
    assert.equal(metric.body.includes(Buffer.from('actql.run.id')), false);
    assert.equal(metric.body.includes(Buffer.from('actql.run.definition_cid')), false);
  }
  assert.equal(adapter.status().projection.deliveryFailed, 0);
  assertNoMetricExemplars(sink.packets);
});

for (const [traceFlags, sampleRate, sampled] of [[0, 0, false], [0, 1, false],
  [1, 0, true], [1, 1, true]]) {
  test(`parent sampled=${traceFlags} overrides root ratio=${sampleRate}`, async t => {
    const sink = await collector(t);
    const adapter = createNodeHostObservability({
      traces: {endpoint: `${sink.endpoint}/v1/traces`, sampleRate},
      metrics: {endpoint: `${sink.endpoint}/v1/metrics`},
      logs: {endpoint: `${sink.endpoint}/v1/logs`},
    });
    const observer = installHostObservation(adapter.connection);
    t.after(async () => { await observer.close(); await adapter.close(); });
    await observer.run('check', {...parent, traceFlags}, () => 42);
    await observer.close();
    assert.equal(sink.packets.some(item => item.path === '/v1/traces'), sampled);
    assert.ok(sink.packets.some(item => item.path === '/v1/logs'));
    assertNoMetricExemplars(sink.packets);
    assert.equal(adapter.configuration().signals.traces.sampler, 'parentbased_traceidratio');
  });
}

test('HTTP server spans use fixed route names and status-specific standard errors', async t => {
  const sink = await collector(t);
  const adapter = createNodeHostObservability({endpoint: sink.endpoint});
  const observer = installHostObservation(adapter.connection);
  t.after(async () => { await observer.close(); await adapter.close(); });
  for (const statusCode of [422, 503]) {
    await observer.run('http', parent, () => 42,
      {http: {method: 'POST', response: {statusCode}}});
  }
  await observer.close();
  const spans = sink.packets.filter(item => item.path === '/v1/traces')
    .map(packet => field(field(field(packet.body, 1), 2), 2));
  assert.equal(spans.length, 2);
  for (const span of spans) {
    assert.equal(field(span, 5).toString(), 'POST /actql/client/0.1/{operation}');
    assert.equal(field(span, 6), 2n);
  }
  const clientErrorStatus = field(spans[0], 15);
  assert.equal(clientErrorStatus === undefined ? 0n : field(clientErrorStatus, 3) ?? 0n, 0n);
  assert.equal(field(field(spans[1], 15), 3), 2n);
});

test('trace export failure does not disable logs or metrics or change execution', async t => {
  const sink = await collector(t, true);
  const adapter = createNodeHostObservability({endpoint: sink.endpoint,
    metrics: {endpoint: `${sink.endpoint}/v1/metrics`},
    logs: {endpoint: `${sink.endpoint}/v1/logs`}});
  const observer = installHostObservation(adapter.connection);
  t.after(async () => { await observer.close(); await adapter.close(); });
  observer.emit('compute', 'task_completed', {task: 0});
  await observer.close();
  assert.equal(adapter.status().signals.traces.failed, 1);
  assert.equal(adapter.status().signals.metrics.sent, 1);
  assert.equal(adapter.status().signals.logs.sent, 1);
  assert.equal(adapter.status().projection.deliveryFailed, 1);
});

test('sampling off still exports independently enabled metrics and logs', async t => {
  const sink = await collector(t);
  const adapter = createNodeHostObservability({traces: {endpoint: `${sink.endpoint}/v1/traces`, sampleRate: 0},
    metrics: {endpoint: `${sink.endpoint}/v1/metrics`}, logs: {endpoint: `${sink.endpoint}/v1/logs`}});
  const observer = installHostObservation(adapter.connection);
  t.after(async () => { await observer.close(); await adapter.close(); });
  observer.emit('compute', 'task_completed', {task: 0});
  await observer.close();
  assert.deepEqual(sink.packets.map(item => item.path).sort(), ['/v1/logs', '/v1/metrics']);
});

test('application provider callback is deferred and its shutdown is never called', async () => {
  let atomic = true, calls = 0, shutdown = 0;
  const adapter = createNodeHostObservability({tracerProvider: {
    shutdown() { shutdown++; },
    getTracer: () => ({startSpan() {
      assert.equal(atomic, false); calls++;
      return {addEvent() {}, setStatus() {}, end() {}};
    }}),
  }});
  const observer = installHostObservation(adapter.connection);
  observer.emit('compute', 'task_completed', {task: 0});
  assert.equal(calls, 0);
  atomic = false;
  await observer.close(); await adapter.close();
  assert.equal(calls, 1);
  assert.equal(shutdown, 0);
  assert.equal(adapter.status().profile, 'application-owned');
});

test('disabled adapter neither exports nor creates a localhost fallback', async () => {
  const adapter = createNodeHostObservability();
  const observer = installHostObservation(adapter.connection);
  observer.emit('compute', 'task_completed', {task: 0});
  await observer.close(); await adapter.close();
  assert.deepEqual(adapter.status().signals, {});
  assert.equal(adapter.status().projection.deliveryFailed, 0);
});

test('effective inspection is finite and does not disclose destination credentials or probe', async () => {
  const adapter = createNodeHostObservability({endpoint: 'https://collector.invalid',
    include: ['run', 'compute'], exclude: ['compute'], projectionLimits: {queueRecords: 1}});
  const effective = adapter.configuration();
  assert.equal(effective.signals.traces.enabled, true);
  assert.equal(effective.signals.logs.enabled, false);
  assert.equal(effective.limits.queueRecords, 1);
  assert.deepEqual(effective.operations, ['run']);
  assert.equal(JSON.stringify(effective).includes('collector.invalid'), false);
  assert.equal(adapter.status().signals.traces.sent, 0);
  await adapter.close();
});
