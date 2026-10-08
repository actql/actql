import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {createNodeHostObservability} from './index.mjs';
import {installHostObservation} from '../local-node/adapters/host-common/observation.mjs';
import {field, records, attributes, assertNoMetricExemplars} from './test/otlp-fixture.mjs';

const parent = {traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1};
async function collector(t, failure = false) {
  const packets = [];
  const server = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    packets.push({path: request.url, type: request.headers['content-type'],
      authorization: request.headers.authorization,
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
  assert.equal(sink.packets.filter(item => item.path === '/v1/traces').length, 1,
    'only the measured segment is a span; the discrete check fact is a log');
  assert.ok(sink.packets.some(item => item.path === '/v1/logs' &&
    item.body.includes(Buffer.from('check_completed'))));
  const span = field(field(field(packet.body, 1), 2), 2);
  assert.equal(field(span, 11), undefined, 'new facts do not duplicate Span Events');
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
    await observer.run('check', {...parent, traceFlags}, () => {
      observer.emit('check', 'check_completed', {checkVerdict: 'verified'});
      return 42;
    });
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
  observer.emit('compute', 'task_completed', {task: 0}, {durationMs: 1});
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
  observer.emit('compute', 'task_completed', {task: 0}, {durationMs: 1});
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
  observer.emit('compute', 'task_completed', {task: 0}, {durationMs: 1});
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

test('closing a managed pipeline revokes queued and not-yet-sent signals', async t => {
  let entered;
  const sending = new Promise(resolve => { entered = resolve; });
  const paths = [];
  const server = createServer((request, response) => {
    paths.push(request.url);
    request.resume();
    entered();
    // Keep the already-entered trace outstanding until the adapter closes.
    response.on('error', () => {});
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const adapter = createNodeHostObservability({endpoint: base,
    logs: {endpoint: `${base}/v1/logs`}, metrics: {endpoint: `${base}/v1/metrics`}});
  const observer = installHostObservation(adapter.connection);
  t.after(async () => { await adapter.close(); await observer.close(); });
  observer.emit('compute', 'task_completed');
  await sending;
  observer.emit('cleanup', 'cleanup_completed');
  await adapter.close();
  await observer.close();
  assert.deepEqual(paths, ['/v1/traces'], 'no queued or later signal leaves after revocation');
  for (const sender of Object.values(adapter.status().signals)) assert.equal(sender.active, 0);
});

test('measured Source and Model attempts use standard CLIENT span kind', async t => {
  const sink = await collector(t);
  const adapter = createNodeHostObservability({endpoint: sink.endpoint});
  const observer = installHostObservation(adapter.connection);
  t.after(async () => { await observer.close(); await adapter.close(); });
  observer.emit('infer', 'attempt_observed', {outcome: 'unknown'}, {durationMs: 1});
  observer.emit('source', 'attempt_completed', {}, {durationMs: 1});
  await observer.close();
  const spans = records(sink.packets, 'traces');
  assert.equal(spans.length, 2);
  for (const span of spans) assert.equal(field(span, 6), 3n);
});

test('execution intervals do not duplicate discrete Owner logs', async t => {
  const sink = await collector(t);
  const adapter = createNodeHostObservability({endpoint: sink.endpoint,
    logs: {endpoint: `${sink.endpoint}/v1/logs`}});
  const observer = installHostObservation(adapter.connection);
  t.after(async () => { await observer.close(); await adapter.close(); });
  await observer.run('check', parent, () => {
    observer.emit('check', 'check_completed', {checkVerdict: 'verified'});
  });
  await observer.close();
  const logs = records(sink.packets, 'logs');
  assert.equal(logs.length, 1);
  assert.equal(attributes(logs[0], 6)['actql.event'], 'check_completed');
  assert.equal(records(sink.packets, 'traces').length, 2);
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

test('selected measurements and disclosed metadata reach every managed wire carrier', async t => {
  const sink = await collector(t);
  const adapter = createNodeHostObservability({traces: {endpoint: `${sink.endpoint}/v1/traces`,
    headers: {authorization: 'Bearer SECRET_SENTINEL'}},
    metrics: {endpoint: `${sink.endpoint}/v1/metrics`}, logs: {endpoint: `${sink.endpoint}/v1/logs`},
    operations: {include: ['check', 'compute'], exclude: ['compute']},
    measurements: {include: []}, correlation: {include: []},
    attributes: {exclude: ['actql.check.verdict']}, resource: {'service.name': 'user-service'}});
  const observer = installHostObservation(adapter.connection);
  t.after(async () => { await observer.close(); await adapter.close(); });
  await observer.run('check', parent, () => {
    observer.emit('compute', 'task_completed', {task: 0});
    observer.emit('check', 'check_completed', {checkVerdict: 'invalid'});
  });
  await observer.close();
  for (const packet of sink.packets) assert.equal(packet.body.includes(Buffer.from('SECRET_SENTINEL')), false);
  assert.ok(sink.packets.filter(packet => packet.path === '/v1/traces')
    .every(packet => packet.authorization === 'Bearer SECRET_SENTINEL'));
  for (const record of records(sink.packets, 'logs')) {
    assert.equal(attributes(record, 6)['actql.check.verdict'], undefined);
    assert.equal(field(field(record, 5), 1).toString().includes('task'), false);
  }
  for (const span of records(sink.packets, 'traces')) {
    assert.equal(field(span, 4), undefined);
    assert.equal(attributes(span, 9)['actql.check.verdict'], undefined);
  }
  const names = records(sink.packets, 'metrics').map(metric => field(metric, 1).toString());
  assert.ok(names.length > 0);
  assert.ok(names.every(name => name === 'actql.operation.observations'));
  assert.equal(adapter.configuration().signals.traces.credentialsPresent, true);
  assert.equal(JSON.stringify(adapter.configuration()).includes('SECRET_SENTINEL'), false);
  assertNoMetricExemplars(sink.packets);
});

test('explicit environment setup exports configured signals without a second global provider', async t => {
  const sink = await collector(t);
  const keys = ['OTEL_EXPORTER_OTLP_ENDPOINT', 'OTEL_LOGS_EXPORTER', 'OTEL_METRICS_EXPORTER',
    'OTEL_TRACES_EXPORTER', 'OTEL_TRACES_SAMPLER', 'OTEL_TRACES_SAMPLER_ARG',
    'OTEL_SDK_DISABLED', 'OTEL_EXPORTER_OTLP_PROTOCOL', 'OTEL_SERVICE_NAME'];
  const before = Object.fromEntries(keys.map(key => [key, process.env[key]]));
  for (const key of keys) delete process.env[key];
  t.after(() => {
    for (const key of keys) {
      if (before[key] === undefined) delete process.env[key];
      else process.env[key] = before[key];
    }
  });
  process.env.OTEL_EXPORTER_OTLP_ENDPOINT = sink.endpoint;
  process.env.OTEL_LOGS_EXPORTER = 'otlp';
  process.env.OTEL_TRACES_SAMPLER = 'parentbased_traceidratio';
  process.env.OTEL_TRACES_SAMPLER_ARG = '0';
  process.env.OTEL_SERVICE_NAME = 'environment-service';
  const adapter = createNodeHostObservability({environment: true});
  const observer = installHostObservation(adapter.connection);
  t.after(async () => { await observer.close(); await adapter.close(); });
  observer.emit('check', 'check_completed', {checkVerdict: 'verified'});
  await observer.close();
  assert.deepEqual([...new Set(sink.packets.map(packet => packet.path))], ['/v1/logs']);
  assert.equal(adapter.configuration().source, 'environment+explicit');
  assert.deepEqual(adapter.configuration().resourceAttributes, ['service.name']);
  assert.equal(sink.packets[0].body.includes(Buffer.from('environment-service')), true);
  await adapter.close();
  process.env.OTEL_SDK_DISABLED = 'true';
  const disabled = createNodeHostObservability({environment: true});
  const silent = installHostObservation(disabled.connection);
  silent.emit('check', 'check_completed');
  await silent.close(); await disabled.close();
  assert.deepEqual(disabled.status().signals, {});
  assert.equal(sink.packets.length, 1);
});
