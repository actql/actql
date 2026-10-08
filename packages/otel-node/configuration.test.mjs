import test from 'node:test';
import assert from 'node:assert/strict';
import {observationConfiguration, managedLimits} from './configuration.mjs';

test('generic endpoint enables traces only and explicit false overrides it', () => {
  assert.deepEqual(observationConfiguration({endpoint: 'https://collector.invalid/otlp'}).signals,
    {traces: {endpoint: 'https://collector.invalid/otlp/v1/traces', sampleRate: 1}});
  assert.deepEqual(observationConfiguration({endpoint: 'https://collector.invalid',
    traces: false}).signals, {});
  assert.deepEqual(observationConfiguration().signals, {});
  assert.deepEqual(observationConfiguration({metrics: {endpoint: 'https://metrics.invalid/data'}})
    .signals, {metrics: {endpoint: 'https://metrics.invalid/data', sampleRate: 1}});
});

test('unsupported hosts, protocols and implicit destinations are explicit errors', () => {
  for (const options of [{host: 'worker'}, {transport: 'grpc'}, {traces: true},
    {logs: {}}, {metrics: {endpoint: 'http://localhost', sampleRate: 0.1}},
    {endpoint: 'http://name:password@localhost'}, {endpoint: 'http://localhost/?secret=1'},
    {traces: {endpoint: 'http://localhost', headers: {baggage: 'value'}}},
    {limits: {windowMs: 1}}, {limits: {windowBytes: managedLimits.windowBytes + 1}},
    {traces: {endpoint: 'http://localhost', sampleRate: NaN}},
    {revision: 'SECRET '.repeat(1000)}, {scope: 'invalid space'},
    {include: ['run', 'run']}, {projectionLimits: {queueRecords: 99999}}]) {
    assert.throws(() => observationConfiguration(options), TypeError);
  }
});

test('adopted selections validate before SDK construction and exclusions win', () => {
  const value = observationConfiguration({operations: {include: ['run', 'compute'], exclude: ['compute']},
    measurements: {include: ['duration'], exclude: ['duration']},
    correlation: {include: ['run']}, attributes: {exclude: ['actql.run.id']},
    events: {level: 'diagnostic'}});
  assert.deepEqual(value.projection.include, ['run', 'compute']);
  for (const options of [{operations: {include: ['invalid']}},
    {operations: {include: ['run']}, include: ['run']},
    {measurements: {include: ['cost']}}, {measurements: {include: ['duration', 'duration']}},
    {attributes: {exclude: ['unregistered']}}, {attributes: {include: []}},
    {correlation: {include: ['credentials']}}, {events: {level: 'raw'}}]) {
    assert.throws(() => observationConfiguration(options), TypeError);
  }
  assert.equal(observationConfiguration({endpoint: 'https://collector.invalid/v1/traces'})
    .signals.traces.endpoint, 'https://collector.invalid/v1/traces');
});

test('Resource filtering and authentication headers are bounded and never broaden propagation', () => {
  let reads = 0;
  const resource = {};
  Object.defineProperty(resource, 'private', {enumerable: true, get() { reads++; return 'SECRET'; }});
  assert.throws(() => observationConfiguration({resource}), TypeError);
  assert.equal(reads, 0);
  const excluded = {'service.name': 'public'};
  Object.defineProperty(excluded, 'service.version', {enumerable: true, get() { reads++; return 'SECRET'; }});
  assert.deepEqual(observationConfiguration({resource: excluded,
    attributes: {exclude: ['service.version']}}).resource, {'service.name': 'public'});
  assert.equal(reads, 0);
  assert.equal(observationConfiguration({traces: {endpoint: 'https://collector.invalid',
    headers: {Authorization: 'Bearer secret'}}}).signals.traces.headers.Authorization, 'Bearer secret');
  for (const headers of [{traceparent: 'secret'}, {'content-length': '99'},
    {authorization: 'line\r\nbreak'}, {authorization: 'x'.repeat(1025)}]) {
    assert.throws(() => observationConfiguration({traces: {endpoint: 'http://localhost', headers}}), TypeError);
  }
});

test('application providers never implicitly select managed transport', () => {
  assert.equal(observationConfiguration({tracerProvider: {getTracer() {}}}).applicationOwned, true);
  assert.throws(() => observationConfiguration({tracerProvider: {getTracer() {}},
    endpoint: 'http://localhost'}), TypeError);
  assert.throws(() => observationConfiguration({meterProvider: {}}), TypeError);
});
