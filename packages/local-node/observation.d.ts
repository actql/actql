export interface HostObservationConnection {
  readonly __hostObservation: unique symbol;
  configuration(): Readonly<{scope: string; revision: string;
    limits: Readonly<ObservationLimits>; operations: readonly ObservationOperation[];
    correlation: boolean}>;
  status(): Readonly<{dropped: number; budgetUnavailable: number;
    queueOverflow: number; deliveryFailed: number; limited: number;
    queued: number; queuedBytes: number; active: number; activeSegments: number; closed: boolean;
    cleanupPending: boolean;
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
  correlation?: boolean;
}>): HostObservationConnection;
export declare const observationLimits: Readonly<ObservationLimits>;
