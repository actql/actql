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

import type {LogRecordProcessor} from '@opentelemetry/sdk-logs';
import type {ReadableSpan, SpanProcessor} from '@opentelemetry/sdk-trace';
import type {Signal} from './configuration.mjs';
import type {TracerProvider as ApplicationTracerProvider,
  MeterProvider as ApplicationMeterProvider} from '@opentelemetry/api';
import type {LoggerProvider as ApplicationLoggerProvider} from '@opentelemetry/api-logs';
import type {HostObservationConnection, ObservationContext,
  ObservationOperation, ObservationLimits, ObservationSelection,
  ObservationMeasurement, ObservationCorrelation} from '@actql/local-node/observation';

export interface OtlpSignal {
  readonly endpoint: string;
  readonly headers?: Readonly<Record<string, string>>;
}
export interface NodeHostObservationOptions {
  readonly host?: 'node';
  readonly transport?: 'http/protobuf';
  /** Generic base destination enables traces only. No environment defaults. */
  readonly endpoint?: string;
  /** Explicit standalone environment mechanism; never overlays application providers. */
  readonly environment?: boolean;
  /** Only these standard, explicitly disclosed Resource attributes are supported. */
  readonly resource?: Readonly<Partial<Record<'service.name' | 'service.version' |
    'deployment.environment.name', string>>>;
  readonly traces?: false | (OtlpSignal & {readonly sampleRate?: number});
  readonly metrics?: false | OtlpSignal;
  readonly logs?: false | OtlpSignal;
  readonly scope?: string;
  readonly revision?: string;
  readonly include?: readonly ObservationOperation[];
  readonly exclude?: readonly ObservationOperation[];
  readonly operations?: ObservationSelection<ObservationOperation>;
  readonly measurements?: ObservationSelection<ObservationMeasurement>;
  readonly attributes?: Readonly<{exclude?: readonly string[]}>;
  readonly events?: Readonly<{level?: 'lifecycle' | 'diagnostic'}>;
  readonly correlation?: boolean | ObservationSelection<ObservationCorrelation>;
  readonly projectionLimits?: Partial<ObservationLimits>;
  readonly limits?: Partial<Readonly<{payloadBytes: number; windowBytes: number;
    windowRecords: number; windowMs: 60000; exportTimeoutMs: number;
    shutdownMs: number; responseBytes: number}>>;
  /** Alternative to managed destinations; providers remain application-owned. */
  readonly tracerProvider?: ApplicationTracerProvider;
  readonly meterProvider?: ApplicationMeterProvider;
  readonly loggerProvider?: ApplicationLoggerProvider;
}

type Sender = ReturnType<typeof createBoundedOtlpSender>;

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
export function createNodeHostObservability(options: NodeHostObservationOptions = {}): Readonly<{
  connection: HostObservationConnection;
  /** Supply to the SDK remote connection's traceContext option. */
  currentContext(): ObservationContext | undefined;
  /** Read-only metadata; no destination URLs, credentials or connectivity probe. */
  configuration(): Readonly<{host: 'node'; transport: 'http/protobuf';
    disclosure: 'metadata-only'; scope: string; revision: string;
    schemaUrl: string; sdk: string; signals: Readonly<Record<string,
      Readonly<{enabled: boolean; destination?: 'explicit';
        sampler?: 'parentbased_traceidratio'; sampleRate?: number;
        credentialsPresent: boolean}>>>;
    source: 'explicit' | 'environment+explicit'; diagnostics: readonly string[];
    resourceAttributes: readonly string[]; unsupported: readonly string[];
    correlations: readonly ObservationCorrelation[];
    measurements: Readonly<{selected: readonly ObservationMeasurement[];
      available: readonly ObservationMeasurement[]}>;
    attributes: Readonly<{exclude: readonly string[]}>;
    events: Readonly<{level: 'lifecycle' | 'diagnostic'}>;
    operations: readonly ObservationOperation[]; correlation: boolean;
    limits: Readonly<ObservationLimits>; transportLimits: Readonly<Record<string, number>>}>;
  status(): Readonly<{profile: 'managed' | 'application-owned';
    closed: boolean; deliveryConflicts: number;
    projection: ReturnType<HostObservationConnection['status']>;
    signals: Readonly<Record<string, Readonly<{sent: number; failed: number;
      limited: number; active: number; windowRecords: number; windowBytes: number;
      closed: boolean}>>>}>;
  /** Call after Host/Client close; never shuts down application providers. */
  close(): Promise<void>;
}> {
  const initialized = environmentOptions(options);
  options = initialized.options;
  const config = observationConfiguration(options);
  const resource = resourceFromAttributes(config.resource);
  const senders = Object.fromEntries(Object.entries(config.signals)
    .map(([signal, setting]) => [signal, createBoundedOtlpSender(setting.endpoint, config.limits, setting.headers)])) as Partial<Record<Signal, Sender>>;
  let endedSpan: ReadableSpan | undefined, emittedLog: Parameters<LogRecordProcessor['onEmit']>[0] | undefined, closed = false, busy = false;
  let deliveryConflicts = 0;
  const empty = async () => {};
  const traceProcessor: SpanProcessor = {onStart() {}, onEnd: span => { endedSpan = span; },
    forceFlush: empty, shutdown: empty};
  const logProcessor: LogRecordProcessor = {onEmit: log => { emittedLog = log; }, forceFlush: empty, shutdown: empty};
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
    disabled: (['traces', 'metrics', 'logs'] as const).filter(key => options[key] === false)})).digest('hex');
  const connection = createHostObservationConnection({
    ...config.projection,
    scope: options.scope ?? 'node', revision,
    include: tracer === undefined && meter === undefined && logger === undefined
      ? [] : config.projection.include,
    currentContext,
    async deliver(record) {
      if (closed) throw new Error('ObservationPipelineDisabled');
      if (busy) { deliveryConflicts++; throw new Error('ObservationDeliveryBusy'); }
      busy = true;
      const failures: unknown[] = [];
      // Each signal remains independent when a different destination fails.
      const attempt = async (work: () => Promise<void>) => {
        if (closed) return;
        try { await work(); } catch (cause) { failures.push(cause); }
      };
      try {
        const parent = record.parent === undefined ? ROOT_CONTEXT :
          trace.setSpanContext(ROOT_CONTEXT, {...record.parent, isRemote: true});
        // Export measured finite work as spans. Discrete Owner facts use the
        // correlated Logs API, without duplicate instant spans or Span Events.
        if (tracer !== undefined && record.durationMs !== undefined) {
          await attempt(async () => {
            endedSpan = undefined;
            const method = record.attributes['http.request.method'] as string | undefined;
            const route = record.attributes['http.route'];
            const clientAttempt = ['source', 'infer'].includes(record.operation) &&
              ['attempt_started', 'attempt_completed', 'attempt_observed',
                'transport_completed', 'acquisition_interval'].includes(record.event);
            const span = tracer.startSpan(method === undefined ? `actql.${record.operation}` :
              route === undefined ? method : `${method} ${route}`, {
              kind: method !== undefined ? SpanKind.SERVER :
                clientAttempt ? SpanKind.CLIENT : SpanKind.INTERNAL,
              attributes: record.attributes,
              startTime: record.observedAt - (record.durationMs ?? 0),
              links: record.link === undefined ? [] : [{context: {...record.link, isRemote: true}}],
            }, parent);
            if (method === undefined ? record.attributes['actql.outcome'] === 'failed' :
                (record.attributes['http.response.status_code'] as number) >= 500) {
              span.setStatus({code: SpanStatusCode.ERROR});
            }
            span.end(record.observedAt);
            if (endedSpan !== undefined) {
              await senders.traces!.send(ProtobufTraceSerializer.serializeRequest([endedSpan]),
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
            await senders.metrics!.send(ProtobufMetricsSerializer.serializeRequest(metrics.resourceMetrics),
              ProtobufMetricsSerializer);
          });
        }
        // Finite interval boundaries belong to spans, not discrete lifecycle
        // logs. Polling cannot consume the log allowance for an Owner outcome.
        if (logger !== undefined && record.segment === undefined) {
          await attempt(async () => {
            emittedLog = undefined;
            logger.emit({body: record.event, attributes: record.attributes,
              timestamp: record.observedAt, context: parent, severityNumber: SeverityNumber.INFO});
            if (emittedLog !== undefined) {
              await senders.logs!.send(ProtobufLogsSerializer.serializeRequest([emittedLog]),
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
      signals: Object.freeze(Object.fromEntries((['traces', 'metrics', 'logs'] as const).map(signal =>
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
