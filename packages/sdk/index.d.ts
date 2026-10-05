import type {ClientSourceFormat, WireCancellation, WireCheckpointSummary, WireClientProfile,
  WireConnection,
  WireRequestCancellation,
  WireDeliveryAttemptLookup, WireHeldRequest, WireRequestLookup,
  WireResolveItem, WireResolveResult, WireRunRef,
  WireRunState, WireResultDescription, WireCheckOutcome, WireCheckLocation} from
  '@actql/client-wire';

export type Durability = 'volatile' | 'durable';
export type RunReference = WireRunRef;
/** actql-check-outcome/0.1. */
export type CheckOutcome = WireCheckOutcome;
export type CheckInput = Readonly<{documentId: string; revision: string}> & (
  Readonly<{kind: 'text'; text: string}> | Readonly<{kind: 'structured'; value: unknown}>);
/** Available only for the exact response of this SDK check call. */
export declare function getCheckInput(outcome: CheckOutcome, documentId: string,
  revision?: string): CheckInput | undefined;
export type SubmissionInput = Readonly<{
  requestId: string;
  kind: 'program' | 'aql';
  input: unknown;
  parameters: unknown;
  connection: Readonly<WireConnection>;
  lookupContext: Readonly<{endpoint: string; scopeRef: string}>;
}>;
/** Original prepared JSON input, not evidence of sending, acceptance or permission to resend. */
export declare function getSubmissionInput(result: unknown): SubmissionInput | undefined;
export type SubmissionExplanation = Readonly<{summary: string}> & (
  Readonly<{
    observation: 'acceptance_unknown' | 'request_held';
    next: Readonly<{operation: 'lookupRequest'; requestId: string;
      lookupContext: Readonly<{endpoint: string; scopeRef: string}>}>;
  }> | Readonly<{
    observation: 'run_reference_received';
    next: Readonly<{operation: 'status'; ref: Readonly<RunReference>}>;
  }>);
/** Read-only advice for this exact SDK submit result; no retry or execution permission. */
export declare function explainSubmission(result: unknown): SubmissionExplanation | undefined;
/** Omitted for unavailable/stale input or a pointer without a submitted JSON node. No edits are applied. */
export declare function resolveCheckLocation(outcome: CheckOutcome,
  location: WireCheckLocation, currentInput?: CheckInput):
  (WireCheckLocation & Readonly<{input: CheckInput; text?: string}>) | undefined;
/** Zero-based UTF-16 coordinates for the original revision; no CRLF-interior position or edits. */
export declare function resolveCheckTextRange(outcome: CheckOutcome,
  location: WireCheckLocation, currentInput?: CheckInput):
  (Extract<WireCheckLocation, {kind: 'text'}> & Readonly<{
    input: CheckInput & Readonly<{kind: 'text'; text: string}>;
    text: string;
    positionEncoding: 'utf-16';
    range: Readonly<{
      start: Readonly<{line: number; character: number}>;
      end: Readonly<{line: number; character: number}>;
    }>;
  }>) | undefined;
export declare function explainCheckReason(reason: Readonly<{code: string; facts?: unknown}>):
  Readonly<{kind: 'known' | 'unknown'; summary: string; hint?: string}>;

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
export type RunNextAction = WireRunState['next_action'];

export type EffectUncertaintyExplanation = Readonly<{
  observation: 'effect_outcome_unknown';
  summary: string;
  /** Owner-issued Effect names, scoped by the original Run reference below. */
  effects: readonly string[];
  /** Only the received control observation can confirm physical stop. */
  physicalStop: 'confirmed' | 'unknown';
  /** Absent when this response has no control observation; not a composite revision. */
  controlRevision?: number;
  next: Readonly<{operation: 'status'; ref: Readonly<RunReference>}>;
}>;
/** Presentation for the exact validated SDK status/wait/reconcile response.
 * Does not authorize retry, rollback, release or any reconciliation operation.
 */
export declare function explainEffectUncertainty(state: unknown):
  EffectUncertaintyExplanation | undefined;

export type DeliveryAttemptLookup = WireDeliveryAttemptLookup;

export type HeldRequest = WireHeldRequest;
export type RequestCancellation = WireRequestCancellation;
export type CheckpointSummary = WireCheckpointSummary;
export type SignedCheckpointAnswer = WireResolveItem;
export type CheckpointAnswerResult = WireResolveResult;

// Supplied by the application; the SDK never holds the key. `sign` signs
// the UTF-8 text of an unsigned artifact CID (Ed25519, 64-byte signature
// or its base64 text).
export type CheckpointSigner = Readonly<{
  keyId: string;
  reviewerId: string;
  /** Exact authority scope for an Effect approval; verified by the Host. */
  authorityScopeCid?: string;
  sign(bytes: Uint8Array): Uint8Array | string | Promise<Uint8Array | string>;
}>;

export declare class ClientError extends Error {
  readonly code: string;
  readonly hint?: string;
  readonly requestId?: string;
  readonly attemptId?: string;
  /** Complete rows returned by the failed call; aggregate calls return none. */
  readonly rowsYielded?: number;
  readonly cleanupError?: unknown;
  readonly lookupContext?: Readonly<{endpoint: string; scopeRef: string}>;
  readonly status?: number;
  // ResolutionUnknown: the exact signed answers to resend unchanged.
  readonly signed?: readonly SignedCheckpointAnswer[];
}

// A durably held request with no Run yet (not a failure; never resubmit).
export declare class RequestHeld extends ClientError {
  readonly code: 'RequestHeld';
  readonly requestId: string;
  readonly held: HeldRequest;
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
  /** Complete rows yielded to this reader's caller, excluding buffered rows. */
  rowsYielded(): number;
}

export type ResultDescription = WireResultDescription;
export interface ResultDescriptionOptions {
  signal?: AbortSignal;
  format?: 'json' | 'jsonl' | 'csv';
  /** Whole UTF-8 JSON response bytes, including its envelope. */
  maxWireBytes?: number;
  maxNodes?: number;
  maxDepth?: number;
}
export interface Result {
  describe(options?: ResultDescriptionOptions): Promise<ResultDescription>;
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
  reconcile(options?: {signal?: AbortSignal}): Promise<RunState>;
  result(name: string): Result;
}

export interface Client {
  readonly profile: ConfirmedProfile;
  readonly requestedDurability: Durability | null;
  aql(text: string, options: {
    format: ClientSourceFormat;
    /** The existing Program params map, admitted by the Host checker. */
    parameterDeclarations?: Record<string, unknown>;
    parameters?: unknown;
    requestId?: string;
    signal?: AbortSignal;
  }): Promise<Execution>;
  /**
   * Check authored source without starting anything. Completed, failed and
   * unavailable are all returned outcomes; a verdict is always bound to its
   * scope and context reference.
   */
  check(text: string, options: {
    format: 'aql-text' | 'sql';
    parameterDeclarations?: Record<string, unknown>;
    parameters?: Record<string, unknown> | null;
    signal?: AbortSignal;
  }): Promise<CheckOutcome>;
  start(program: Record<string, unknown>, options?: {
    parameters?: unknown;
    requestId?: string;
    signal?: AbortSignal;
  }): Promise<Execution>;
  attach(ref: RunReference, options?: {signal?: AbortSignal}): Promise<Execution>;
  lookupRequest(requestId: string,
    options?: {signal?: AbortSignal}): Promise<RequestLookup>;
  cancelRequest(requestId: string, options?: {signal?: AbortSignal}):
    Promise<RequestCancellation>;
  resources(resourceConnection: string, options?: {query?: string;
    limit?: number; signal?: AbortSignal}): Promise<Readonly<{
      resourceConnection: string; observationCid: string;
      resources: readonly Readonly<{name: string; outcome: string}>[];
      snapshotComplete: boolean; snapshotTruncated: boolean;
      resultTruncated: boolean}>>;
  inspectResource(resourceConnection: string, resource: string, options?: {
    maxBytes?: number; signal?: AbortSignal}): Promise<Readonly<{
      resourceConnection: string; resource: string; observationCid: string;
      status: 'ready' | 'catalog_required';
      reason?: 'listing_truncated' | 'not_visible' | 'not_observed' |
        'not_found' | 'describe_unavailable';
      summary?: unknown}>>;
  peekResource(resourceConnection: string, resource: string, options: {
    fields: readonly string[]; maxRows?: number; maxBytes?: number;
    signal?: AbortSignal}): Promise<Readonly<{
      resourceConnection: string; resource: string; observationCid: string;
      fields: readonly string[];
      rows: readonly Readonly<Record<string,
        string | number | boolean | null>>[];
      limited: boolean}>>;
  checkpoints(options?: {after?: string; limit?: number;
    signal?: AbortSignal}): Promise<Readonly<{
      items: readonly CheckpointSummary[]; next?: string}>>;
  reviewCheckpoint(checkpoint: string | CheckpointSummary, options?: {
    maxBytes?: number; signal?: AbortSignal}): Promise<Readonly<{
      checkpointCid: string; artifactCid: string; bytes: Uint8Array}>>;
  resolveCheckpoints(items: readonly (
    | Readonly<{checkpoint: CheckpointSummary;
        decision: 'approved' | 'rejected'}>
    | SignedCheckpointAnswer)[], options?: {
      signer?: CheckpointSigner; signal?: AbortSignal}): Promise<Readonly<{
        results: readonly CheckpointAnswerResult[];
        signed: readonly SignedCheckpointAnswer[]}>>;
  close(): void;
}

export declare function connect(options: ConnectionOptions): Promise<Client>;
