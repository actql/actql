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
    {traces: {endpoint: 'http://localhost', headers: {secret: 'value'}}},
    {limits: {windowMs: 1}}, {limits: {windowBytes: managedLimits.windowBytes + 1}},
    {traces: {endpoint: 'http://localhost', sampleRate: NaN}},
    {revision: 'SECRET '.repeat(1000)}, {scope: 'invalid space'},
    {include: ['run', 'run']}, {projectionLimits: {queueRecords: 99999}}]) {
    assert.throws(() => observationConfiguration(options), TypeError);
  }
});

test('application providers never implicitly select managed transport', () => {
  assert.equal(observationConfiguration({tracerProvider: {getTracer() {}}}).applicationOwned, true);
  assert.throws(() => observationConfiguration({tracerProvider: {getTracer() {}},
    endpoint: 'http://localhost'}), TypeError);
  assert.throws(() => observationConfiguration({meterProvider: {}}), TypeError);
});
