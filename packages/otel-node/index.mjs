import {context, trace, ROOT_CONTEXT, SpanKind, SpanStatusCode} from '@opentelemetry/api';
import {SeverityNumber} from '@opentelemetry/api-logs';
import {TracerProvider, ParentBasedSampler, TraceIdRatioBasedSampler} from '@opentelemetry/sdk-trace';
import {LoggerProvider} from '@opentelemetry/sdk-logs';
import {MeterProvider, MetricReader, AggregationTemporality} from '@opentelemetry/sdk-metrics';
import {resourceFromAttributes} from '@opentelemetry/resources';
import {createHash} from 'node:crypto';
import {ProtobufTraceSerializer, ProtobufLogsSerializer,
  ProtobufMetricsSerializer} from '@opentelemetry/otlp-transformer';
import {createHostObservationConnection} from '@actql/local-node/observation';
import {observationConfiguration} from './configuration.mjs';
import {createBoundedOtlpSender} from './transport.mjs';
import {environmentOptions} from './environment.mjs';

const scope = 'actql.node-host', version = '0.0.0-development';
const schemaUrl = 'https://opentelemetry.io/schemas/1.43.0';
const metricKeys = ['actql.operation', 'actql.outcome'];
class OnDemandReader extends MetricReader {
  constructor() {
    super({aggregationTemporalitySelector: () => AggregationTemporality.DELTA,
      cardinalitySelector: () => 192});
  }
  async onShutdown() {}
  async onForceFlush() {}
}

/** Optional Node adapter. Never registers globals or detects a Resource. */
export function createNodeHostObservability(options = {}) {
  const initialized = environmentOptions(options);
  options = initialized.options;
  const config = observationConfiguration(options);
  const resource = resourceFromAttributes(config.resource);
  const senders = Object.fromEntries(Object.entries(config.signals)
    .map(([signal, setting]) => [signal, createBoundedOtlpSender(setting.endpoint, config.limits, setting.headers)]));
  let endedSpan, emittedLog, closed = false, busy = false;
  let deliveryConflicts = 0;
  const empty = async () => {};
  const traceProcessor = {onStart() {}, onEnd: span => { endedSpan = span; },
    forceFlush: empty, shutdown: empty};
  const logProcessor = {onEmit: log => { emittedLog = log; }, forceFlush: empty, shutdown: empty};
  const ownedTrace = config.signals.traces === undefined ? undefined : new TracerProvider({
    resource, spanProcessors: [traceProcessor],
    sampler: new ParentBasedSampler({
      root: new TraceIdRatioBasedSampler(config.signals.traces.sampleRate),
    }),
    spanLimits: {attributeCountLimit: 24, attributeValueLengthLimit: 128,
      eventCountLimit: 1, linkCountLimit: 1, attributePerLinkCountLimit: 0,
      attributePerEventCountLimit: 0},
  });
  const ownedLog = config.signals.logs === undefined ? undefined : new LoggerProvider({
    resource, processors: [logProcessor],
    logRecordLimits: {attributeCountLimit: 24, attributeValueLengthLimit: 128},
  });
  const reader = config.signals.metrics === undefined ? undefined : new OnDemandReader();
  const ownedMeter = reader === undefined ? undefined : new MeterProvider({resource,
    readers: [reader], sdkMetricsEnabled: false});
  const tracer = options.traces === false ? undefined :
    (options.tracerProvider ?? ownedTrace)?.getTracer(scope, version, {schemaUrl});
  const logger = options.logs === false ? undefined :
    (options.loggerProvider ?? ownedLog)?.getLogger(scope, version, {schemaUrl});
  const meter = options.metrics === false ? undefined :
    (options.meterProvider ?? ownedMeter)?.getMeter(scope, version, {schemaUrl});
  const counter = meter?.createCounter('actql.operation.observations', {unit: '{observation}'});
  const projectedConfiguration = createHostObservationConnection({deliver() {},
    ...config.projection}).configuration();
  const selectedMeasurements = projectedConfiguration.measurements;
  const durationEnabled = selectedMeasurements.selected.includes('duration');
  const duration = durationEnabled ? meter?.createHistogram('actql.operation.duration', {unit: 's'}) : undefined;
  const httpDuration = durationEnabled ? meter?.createHistogram('http.server.request.duration', {unit: 's'}) : undefined;
  const currentContext = () => projectedConfiguration.correlations.includes('external_trace')
    ? trace.getSpanContext(context.active()) : undefined;
  const revision = createHash('sha256').update(JSON.stringify({profile: config.applicationOwned,
    signals: config.signals, limits: config.limits, schemaUrl,
    sdk: '2.12.0/0.223.0', sampler: 'parentbased_traceidratio',
    resource: config.resource,
    revision: options.revision ?? 'otel-metadata/0.1',
    disabled: ['traces', 'metrics', 'logs'].filter(key => options[key] === false)})).digest('hex');
  const connection = createHostObservationConnection({
    ...config.projection,
    scope: options.scope ?? 'node', revision,
    include: tracer === undefined && meter === undefined && logger === undefined
      ? [] : config.projection.include,
    currentContext,
    async deliver(record) {
      if (closed) return;
      if (busy) { deliveryConflicts++; throw new Error('ObservationDeliveryBusy'); }
      busy = true;
      const failures = [];
      // Each signal remains independent when a different destination fails.
      const attempt = async work => {
        try { await work(); } catch (cause) { failures.push(cause); }
      };
      try {
        const parent = record.parent === undefined ? ROOT_CONTEXT :
          trace.setSpanContext(ROOT_CONTEXT, {...record.parent, isRemote: true});
        // A segment is exported only after it ends. Other confirmed facts are
        // instant spans; no span survives approval waits or process restart.
        if (tracer !== undefined && record.event !== 'segment_started') {
          await attempt(async () => {
            endedSpan = undefined;
            const method = record.attributes['http.request.method'];
            const route = record.attributes['http.route'];
            const span = tracer.startSpan(method === undefined ? `actql.${record.operation}` :
              route === undefined ? method : `${method} ${route}`, {
              kind: method === undefined ? SpanKind.INTERNAL : SpanKind.SERVER, attributes: record.attributes,
              startTime: record.observedAt - (record.durationMs ?? 0),
              links: record.link === undefined ? [] : [{context: {...record.link, isRemote: true}}],
            }, parent);
            span.addEvent(record.event, record.observedAt);
            if (method === undefined ? record.attributes['actql.outcome'] === 'failed' :
                record.attributes['http.response.status_code'] >= 500) {
              span.setStatus({code: SpanStatusCode.ERROR});
            }
            span.end(record.observedAt);
            if (endedSpan !== undefined) {
              await senders.traces.send(ProtobufTraceSerializer.serializeRequest([endedSpan]),
                ProtobufTraceSerializer);
              endedSpan = undefined;
            }
          });
        }
        const labels = Object.fromEntries(metricKeys.filter(key => record.attributes[key] !== undefined)
          .map(key => [key, record.attributes[key]]));
        // Never use active trace context for metrics: no exemplar correlation or
        // dynamic identity label crosses this metadata-only metric boundary.
        await attempt(async () => {
          counter?.add(1, labels, ROOT_CONTEXT);
          if (record.durationMs !== undefined) duration?.record(record.durationMs / 1000, labels, ROOT_CONTEXT);
          if (httpDuration !== undefined && record.durationMs !== undefined && record.attributes['http.request.method'] !== undefined) {
            const httpLabels = Object.fromEntries(['http.request.method', 'http.route',
              'http.response.status_code', 'error.type'].filter(key => record.attributes[key] !== undefined)
              .map(key => [key, record.attributes[key]]));
            httpDuration?.record(record.durationMs / 1000, httpLabels, ROOT_CONTEXT);
          }
        });
        if (reader !== undefined) {
          await attempt(async () => {
            const metrics = await reader.collect({timeoutMillis: config.limits.exportTimeoutMs});
            if (metrics.errors.length !== 0) throw new Error('ObservationMetricCollectionFailed');
            await senders.metrics.send(ProtobufMetricsSerializer.serializeRequest(metrics.resourceMetrics),
              ProtobufMetricsSerializer);
          });
        }
        if (logger !== undefined) {
          await attempt(async () => {
            emittedLog = undefined;
            logger.emit({body: record.event, attributes: record.attributes,
              timestamp: record.observedAt, context: parent, severityNumber: SeverityNumber.INFO});
            if (emittedLog !== undefined) {
              await senders.logs.send(ProtobufLogsSerializer.serializeRequest([emittedLog]),
                ProtobufLogsSerializer);
              emittedLog = undefined;
            }
          });
        }
        if (failures.length !== 0) throw new Error('ObservationDeliveryFailed');
      } finally { busy = false; endedSpan = undefined; emittedLog = undefined; }
    },
  });
  return Object.freeze({connection, currentContext,
    configuration: () => Object.freeze({host: 'node', transport: 'http/protobuf',
      disclosure: 'metadata-only', ...connection.configuration(),
      source: initialized.source, diagnostics: Object.freeze([...initialized.diagnostics]),
      resourceAttributes: Object.freeze(Object.keys(config.resource)),
      unsupported: Object.freeze(['native-host', 'worker-host', 'grpc', 'http/json',
        'declarative-file', 'baggage', 'content-capture', 'hosted-multi-tenant']),
      schemaUrl, sdk: '2.12.0/0.223.0',
      signals: Object.freeze(Object.fromEntries(['traces', 'metrics', 'logs'].map(signal =>
        [signal, Object.freeze({enabled: ({traces: tracer, metrics: meter, logs: logger})[signal] !== undefined,
          destination: senders[signal] === undefined ? undefined : 'explicit',
          credentialsPresent: config.signals[signal]?.headers !== undefined,
          sampler: signal === 'traces' && config.signals.traces !== undefined
            ? 'parentbased_traceidratio' : undefined,
          sampleRate: config.signals[signal]?.sampleRate})]))),
      transportLimits: config.limits}),
    status: () => Object.freeze({profile: config.applicationOwned ? 'application-owned' : 'managed',
      projection: connection.status(), deliveryConflicts,
      signals: Object.freeze(Object.fromEntries(Object.entries(senders)
        .map(([signal, sender]) => [signal, sender.status()]))), closed}),
    async close() {
      if (closed) return;
      closed = true;
      await Promise.allSettled(Object.values(senders).map(sender => sender.close()));
      // These providers are private to this adapter. Application providers
      // are neither registered/replaced globally nor flushed/shut down here.
      await Promise.allSettled([ownedTrace?.shutdown(), ownedLog?.shutdown(),
        ownedMeter?.shutdown({timeoutMillis: config.limits.shutdownMs})]);
    },
  });
}
