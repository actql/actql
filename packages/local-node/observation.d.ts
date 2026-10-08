export interface HostObservationConnection {
  readonly __hostObservation: unique symbol;
  configuration(): Readonly<{scope: string; revision: string;
    limits: Readonly<ObservationLimits>; operations: readonly ObservationOperation[];
    correlation: boolean; correlations: readonly ObservationCorrelation[];
    measurements: Readonly<{selected: readonly ObservationMeasurement[];
      available: readonly ObservationMeasurement[]}>;
    attributes: Readonly<{exclude: readonly string[]}>;
    events: Readonly<{level: 'lifecycle' | 'diagnostic'}>}>;
  status(): Readonly<{dropped: number; budgetUnavailable: number;
    queueOverflow: number; deliveryFailed: number; limited: number;
    queued: number; queuedBytes: number; active: number; activeSegments: number; closed: boolean;
    loss: Readonly<Record<string, number>>}> | undefined;
}
export interface ObservationContext {
  readonly traceId: string;
  readonly spanId: string;
  readonly traceFlags: number;
}
export interface ObservationLimits {
  recordBytes: number; queueRecords: number; queueBytes: number;
  requestRecords: number; runRecords: number; runBytes: number;
  segmentRecords: number; activeSegments: number; shutdownMs: number;
  journalRuns: number;
}
export type ObservationOperation = 'run' | 'check' | 'planning' | 'source' |
  'compute' | 'infer' | 'effect' | 'approval' | 'checkpoint' | 'recovery' |
  'publication' | 'cleanup';
export type ObservationMeasurement = 'duration' | 'rows' | 'bytes' | 'requests' |
  'tokens' | 'resources' | 'cost';
export type ObservationCorrelation = 'run' | 'task' | 'attempt' | 'external_trace';
export interface ObservationSelection<T extends string> {
  readonly include?: readonly T[];
  readonly exclude?: readonly T[];
}
export interface ObservationRecord {
  readonly version: 'actql-observation/0.1';
  readonly operation: ObservationOperation;
  readonly event: string;
  readonly sequence: number;
  readonly observedAt: number;
  readonly monotonicAt: number;
  readonly attributes: Readonly<Record<string, string | number | boolean>>;
  readonly segment?: string;
  readonly durationMs?: number;
  readonly parent?: ObservationContext;
  readonly link?: ObservationContext;
}
/** Delivery runs outside Owner commits. Application callback time is not bounded. */
export declare function createHostObservationConnection(options: Readonly<{
  deliver(record: ObservationRecord): void | Promise<void>;
  currentContext?(): ObservationContext | undefined;
  scope?: string; revision?: string;
  limits?: Partial<ObservationLimits>;
  include?: readonly ObservationOperation[];
  exclude?: readonly ObservationOperation[];
  correlation?: boolean | ObservationSelection<ObservationCorrelation>;
  measurements?: ObservationSelection<ObservationMeasurement>;
  attributes?: Readonly<{exclude?: readonly string[]}>;
  events?: Readonly<{level?: 'lifecycle' | 'diagnostic'}>;
}>): HostObservationConnection;
export declare const observationLimits: Readonly<ObservationLimits>;
