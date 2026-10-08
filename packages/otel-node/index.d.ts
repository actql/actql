import type {TracerProvider, MeterProvider} from '@opentelemetry/api';
import type {LoggerProvider} from '@opentelemetry/api-logs';
import type {HostObservationConnection, ObservationContext,
  ObservationOperation, ObservationLimits} from '@actql/local-node/observation';

export interface OtlpSignal { readonly endpoint: string }
export interface NodeHostObservationOptions {
  readonly host?: 'node';
  readonly transport?: 'http/protobuf';
  /** Generic base destination enables traces only. No environment defaults. */
  readonly endpoint?: string;
  readonly traces?: false | (OtlpSignal & {readonly sampleRate?: number});
  readonly metrics?: false | OtlpSignal;
  readonly logs?: false | OtlpSignal;
  readonly scope?: string;
  readonly revision?: string;
  readonly include?: readonly ObservationOperation[];
  readonly exclude?: readonly ObservationOperation[];
  readonly correlation?: boolean;
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
        sampler?: 'traceidratio'; sampleRate?: number}>>>;
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
