import type {WireClientProfile, WireDeliveryAttemptLookup, WireCancellation,
  WireRequestLookup, WireRunRef, WireRunState} from '@actql/client-wire';

export type Durability = 'volatile' | 'durable';
export type RunReference = WireRunRef;

type ConnectedEndpoint = Readonly<{
  endpoint: string;
  token: string | (() => string | Promise<string>);
  durability?: Durability;
  consentRefs?: readonly string[];
}>;

export type ConnectionOptions =
  | (ConnectedEndpoint & Readonly<{mode: 'remote'; owner?: never;
      runners?: never; movementPolicyRef?: never;
      cloudConnectionRef?: never}>)
  | (ConnectedEndpoint & Readonly<{mode: 'local'; owner: 'local';
      runners?: never; movementPolicyRef?: never;
      cloudConnectionRef?: never}>)
  | (ConnectedEndpoint & Readonly<{mode: 'hybrid'; owner: 'cloud';
      runners: readonly string[]; movementPolicyRef: string;
      cloudConnectionRef?: never}>)
  | (ConnectedEndpoint & Readonly<{mode: 'hybrid'; owner: 'local';
      runners?: readonly string[]; movementPolicyRef: string;
      cloudConnectionRef: string}>);

export type ConfirmedProfile = WireClientProfile;

export type RequestLookup = WireRequestLookup;

export type RunState = WireRunState;

export type DeliveryAttemptLookup = WireDeliveryAttemptLookup;

export declare class ClientError extends Error {
  readonly code: string;
  readonly hint?: string;
  readonly requestId?: string;
  readonly attemptId?: string;
  readonly cleanupError?: unknown;
  readonly lookupContext?: Readonly<{endpoint: string; scopeRef: string}>;
}

export type ReadOptions = {
  signal?: AbortSignal;
  maxWireBytes?: number;
  maxRowWireBytes?: number;
  maxRowRetainedValueBytes?: number;
  maxRows?: number;
  maxRetainedValueBytes?: number;
  maxBatchRows?: number;
  maxBatchRetainedValueBytes?: number;
};

export interface Reader<T> extends AsyncIterable<T> {
  readonly attemptId: string;
  state(): 'not_started' | 'prefix' | 'complete';
}

export interface Result {
  rows(options?: ReadOptions): Reader<unknown>;
  batches(options?: ReadOptions): Reader<unknown[]>;
  all(options?: ReadOptions): Promise<unknown[]>;
  one(options?: ReadOptions): Promise<unknown>;
  scalar(options?: ReadOptions): Promise<unknown>;
  deliveryAttempt(attemptId: string,
    options?: {signal?: AbortSignal}): Promise<DeliveryAttemptLookup>;
}

export interface Execution {
  readonly ref: RunReference;
  readonly profile: ConfirmedProfile;
  status(options?: {signal?: AbortSignal}): Promise<RunState>;
  wait(options?: {until?: string; signal?: AbortSignal}): Promise<RunState>;
  cancel(options?: {signal?: AbortSignal}): Promise<WireCancellation>;
  reconcile(options?: {signal?: AbortSignal}): Promise<unknown>;
  result(name: string): Result;
}

export interface Client {
  readonly profile: ConfirmedProfile;
  readonly requestedDurability: Durability | null;
  aql(text: string, options: {
    format: 'json' | 'yaml';
    parameters?: unknown;
    requestId?: string;
    signal?: AbortSignal;
  }): Promise<Execution>;
  start(program: Record<string, unknown>, options?: {
    parameters?: unknown;
    requestId?: string;
    signal?: AbortSignal;
  }): Promise<Execution>;
  attach(ref: RunReference, options?: {signal?: AbortSignal}): Promise<Execution>;
  lookupRequest(requestId: string,
    options?: {signal?: AbortSignal}): Promise<RequestLookup>;
  close(): void;
}

export declare function connect(options: ConnectionOptions): Promise<Client>;
