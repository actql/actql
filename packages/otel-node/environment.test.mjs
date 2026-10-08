import test from 'node:test';
import assert from 'node:assert/strict';
import {environmentOptions} from './environment.mjs';
import {observationConfiguration} from './configuration.mjs';
const resolved = (environment, options = {}) => observationConfiguration(
  environmentOptions({environment: true, ...options}, environment).options);

test('explicit environment mechanism implements the independent signal matrix', () => {
  const generic = {OTEL_EXPORTER_OTLP_ENDPOINT: 'https://collector.invalid/base'};
  assert.deepEqual(Object.keys(resolved({}).signals), []);
  assert.deepEqual(Object.keys(resolved(generic).signals), ['traces']);
  assert.equal(resolved(generic).signals.traces.endpoint, 'https://collector.invalid/base/v1/traces');
  assert.deepEqual(Object.keys(resolved({OTEL_EXPORTER_OTLP_LOGS_ENDPOINT: 'https://logs.invalid'}).signals), ['logs']);
  assert.deepEqual(Object.keys(resolved({...generic, OTEL_METRICS_EXPORTER: 'OTLP',
    OTEL_LOGS_EXPORTER: 'none'}).signals), ['traces', 'metrics']);
  assert.equal(resolved({...generic, OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: 'https://specific.invalid/v1/traces'})
    .signals.traces.endpoint, 'https://specific.invalid/v1/traces');
  assert.deepEqual(Object.keys(resolved({...generic, OTEL_SDK_DISABLED: 'TrUe'}).signals), []);
  assert.deepEqual(Object.keys(resolved(generic, {traces: false}).signals), []);
  assert.equal(resolved(generic, {endpoint: 'https://explicit.invalid'}).signals.traces.endpoint,
    'https://explicit.invalid/v1/traces');
  assert.equal(resolved({...generic, OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: ''}).signals.traces.endpoint,
    'https://collector.invalid/base/v1/traces');
  assert.equal(environmentOptions({endpoint: 'https://explicit.invalid'},
    {get OTEL_EXPORTER_OTLP_ENDPOINT() { throw new Error('must not read'); }}).source, 'explicit');
});

test('standard sampling, timeout, Resource and headers preserve precedence without leaking diagnostics', () => {
  const environment = {OTEL_EXPORTER_OTLP_ENDPOINT: 'https://collector.invalid',
    OTEL_TRACES_SAMPLER: 'parentbased_traceidratio', OTEL_TRACES_SAMPLER_ARG: '0.1',
    OTEL_EXPORTER_OTLP_HEADERS: 'authorization=Bearer%20SECRET',
    OTEL_EXPORTER_OTLP_LOGS_ENDPOINT: 'https://logs.invalid',
    OTEL_EXPORTER_OTLP_LOGS_HEADERS: 'x-api-key=local',
    OTEL_EXPORTER_OTLP_TIMEOUT: '25', OTEL_SERVICE_NAME: 'chosen',
    OTEL_RESOURCE_ATTRIBUTES: 'service.name=ignored,service.version=one,secret=%INVALID'};
  const value = resolved(environment);
  assert.equal(value.signals.traces.sampleRate, 0.1);
  assert.equal(value.signals.traces.headers.authorization, 'Bearer SECRET');
  assert.deepEqual({...value.signals.logs.headers}, {'x-api-key': 'local'});
  assert.equal(value.limits.exportTimeoutMs, 25);
  assert.deepEqual(value.resource, {'service.name': 'chosen', 'service.version': 'one'});
  const warnings = environmentOptions({environment: true}, {...environment,
    OTEL_TRACES_SAMPLER_ARG: 'SECRET', OTEL_LOGS_EXPORTER: 'unknown'});
  assert.equal(JSON.stringify(warnings.diagnostics).includes('SECRET'), false);
  assert.equal(observationConfiguration(warnings.options).signals.traces.sampleRate, 1);
  assert.deepEqual(warnings.diagnostics,
    ['invalid_sampler_argument_ignored', 'unsupported_logs_exporter_ignored']);
  const noDestination = environmentOptions({environment: true}, {OTEL_METRICS_EXPORTER: 'otlp'});
  assert.deepEqual(noDestination.diagnostics, ['metrics_destination_missing']);
  assert.deepEqual(resolved({OTEL_METRICS_EXPORTER: 'otlp'}).signals, {});
});

test('unsupported configuration mechanisms are explicit and never overlay application providers', () => {
  for (const environment of [{OTEL_CONFIG_FILE: 'config.yaml'},
    {OTEL_EXPORTER_OTLP_ENDPOINT: 'https://collector.invalid', OTEL_EXPORTER_OTLP_PROTOCOL: 'grpc'},
    {OTEL_PROPAGATORS: 'baggage'}]) {
    assert.throws(() => resolved(environment), TypeError);
  }
  assert.throws(() => resolved({}, {tracerProvider: {getTracer() {}}}),
    /ApplicationProviderEnvironmentOverlayUnsupported/u);
  const value = environmentOptions({environment: true}, {OTEL_PROPAGATORS: 'none'}).options;
  assert.deepEqual(value.correlation.include, ['run', 'task', 'attempt']);
  const unsupported = environmentOptions({environment: true}, {OTEL_TRACES_SAMPLER: 'errors_only'});
  assert.deepEqual(unsupported.diagnostics, ['unsupported_sampler_ignored']);
});
