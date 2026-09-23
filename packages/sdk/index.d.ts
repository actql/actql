export type Durability = 'volatile' | 'durable';
export type RunReference = Readonly<{
  tenantId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;

export type ConnectionOptions = Readonly<{
  mode: 'remote' | 'local' | 'hybrid';
  owner?: 'local' | 'cloud';
  endpoint: string;
  token: string | (() => string | Promise<string>);
  durability?: Durability;
  consentRefs?: readonly string[];
  runners?: readonly string[];
  movementPolicyRef?: string;
}>;

export type ConfirmedProfile = Readonly<{
  version: 'actql-client-host/0.1';
  mode: 'remote' | 'local' | 'hybrid';
  owner: 'remote' | 'local' | 'cloud';
  durability: Durability;
  scopeRef: string;
  capabilities: readonly string[];
  limits: Readonly<{
    maxReadWireBytes: number;
    maxRowBytes: number;
    maxRetainedValueBytes: number;
    maxRows: number;
    maxBatchRows: number;
    maxBatchRetainedValueBytes: number;
  }>;
}>;

export declare class ClientError extends Error {
  readonly code: string;
  readonly hint?: string;
  readonly requestId?: string;
  readonly attemptId?: string;
  readonly lookupContext?: Readonly<{endpoint: string; scopeRef: string}>;
}

export type ReadOptions = {
  signal?: AbortSignal;
  maxWireBytes?: number;
  maxRowBytes?: number;
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
    options?: {signal?: AbortSignal}): Promise<unknown>;
}

export interface Execution {
  readonly ref: RunReference;
  readonly profile: ConfirmedProfile;
  status(options?: {signal?: AbortSignal}): Promise<unknown>;
  wait(options?: {until?: string; signal?: AbortSignal}): Promise<unknown>;
  cancel(options?: {signal?: AbortSignal}): Promise<unknown>;
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
    options?: {signal?: AbortSignal}): Promise<unknown>;
  close(): void;
}

export declare function connect(options: ConnectionOptions): Promise<Client>;
