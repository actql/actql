import type {TracerProvider, MeterProvider} from '@opentelemetry/api';
import type {LoggerProvider} from '@opentelemetry/api-logs';
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
  readonly tracerProvider?: TracerProvider;
  readonly meterProvider?: MeterProvider;
  readonly loggerProvider?: LoggerProvider;
}
export declare function createNodeHostObservability(options?: NodeHostObservationOptions): Readonly<{
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
}>;
