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
type CheckReportScope = Extract<CheckOutcome, {outcome: 'completed'}>['report']['scope'];
type CheckReportExplanation<C extends 'complete' | 'partial'> = Readonly<{
  completeness: C;
  verdict: C extends 'partial' ? 'invalid' | 'undetermined' : 'invalid' | 'undetermined' | 'verified';
  scope: CheckReportScope;
  contextRef: string;
}>;
export type CheckOutcomeExplanation = Readonly<{summary: string; hint: string}> & (
  Readonly<{outcome: 'completed'; report: CheckReportExplanation<'complete'>}> |
  Readonly<{outcome: 'failed'; correlationRef: string; report?: CheckReportExplanation<'partial'>;
    problem: Readonly<{kind: 'known' | 'unknown'; code: string}>}> |
  Readonly<{outcome: 'unavailable'; correlationRef: string;
    problem: Readonly<{kind: 'known' | 'unknown'; code: string}>}>);
/** Safe presentation of a schema-admitted outcome; no input association or execution authority. */
export type CheckExplanationOptions = Readonly<{locale?: string}>;
/** Operation display wording only; never changes an Owner observation or next operation. */
export type OperationExplanationOptions = Readonly<{locale?: string}>;
/** Operation translation revision, separate from check translation and wire schemas. */
export declare function getOperationPresentationInfo(options?: OperationExplanationOptions):
  Readonly<{locale: 'en' | 'ja'; translationRevision: string}>;
/** The selected translation revision, separate from reason/outcome schema identity. */
export declare function getCheckPresentationInfo(options?: CheckExplanationOptions):
  Readonly<{locale: 'en' | 'ja'; translationRevision: string}>;
/** Display formats for an admitted public observation; no execution or edit authority. */
export type CheckFormatOptions = CheckExplanationOptions & Readonly<{
  format?: 'text' | 'html' | 'json';
  maxBytes?: number;
  currentInputs?: readonly CheckInput[];
  /** The negotiated encoding for text coordinates; UTF-16 is the default. */
  positionEncoding?: CheckPositionEncoding;
}>;
/** Undefined for malformed protocol data/options or a budget too small for the observation. */
export declare function formatCheckOutcome(outcome: unknown, options?: CheckFormatOptions): string | undefined;
export declare function explainCheckOutcome(outcome: unknown,
  options?: CheckExplanationOptions): CheckOutcomeExplanation | undefined;
export type CheckInput = Readonly<{documentId: string; revision: string}> & (
  Readonly<{kind: 'text'; text: string}> | Readonly<{kind: 'structured'; value: unknown}>);
/** Available only for the exact response of this SDK check call. */
export declare function getCheckInput(outcome: CheckOutcome, documentId: string,
  revision?: string): CheckInput | undefined;
type CompletedCheckReport = Extract<CheckOutcome, {outcome: 'completed'}>['report'];
type ParameterRequirementFacts = Readonly<Pick<Extract<
  CompletedCheckReport['requirements'][number]['facts'], {parameter: string; expected_type: string}>,
  'parameter' | 'expected_type'>>;
/** The known public parameter Requirements, not a complete future obligation list. */
export type CheckRequirementFrontier = Readonly<{
  contextRef: string;
  reasonSchemaCid: string;
  scope: CompletedCheckReport['scope'];
  requirements: readonly Readonly<{
    code: CompletedCheckReport['requirements'][number]['code'];
    facts: ParameterRequirementFacts;
  }>[];
  coverage: CompletedCheckReport['coverage'];
}>;
/** Copied, partial and uninterpretable reports have no comparable frontier. */
export declare function getCheckRequirementFrontier(outcome: CheckOutcome): CheckRequirementFrontier | undefined;
/** Structural set equality within the same bound scope/context; never verification. */
export declare function equalCheckRequirementFrontiers(first: CheckOutcome, second: CheckOutcome): boolean | undefined;
export type CheckSupplementationDecision = Readonly<{kind: 'more_checks'}> |
  Readonly<{kind: 'stop'; reason: 'frontier_unavailable' | 'no_known_supplement' |
    'unchanged_frontier' | 'attempt_budget'}>;
export interface CheckSupplementationSession {
  /** Explicit read-only check; no automatic I/O, supplement write or execution. */
  check(text: string, options: Parameters<Client['check']>[1]): Promise<Readonly<{
    outcome: CheckOutcome;
    attempts: number;
    decision: CheckSupplementationDecision;
  }>>;
}
/** A total attempt cap also applies when the bound context keeps changing. */
export declare function createCheckSupplementationSession(client: Pick<Client, 'check'>,
  options: Readonly<{maxAttempts: number}>): CheckSupplementationSession;
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
export declare function explainSubmission(result: unknown, options?: OperationExplanationOptions): SubmissionExplanation | undefined;
export type ReadFailureExplanation = Readonly<{
  observation: 'read_incomplete' | 'cleanup_unknown';
  cleanup?: 'unknown';
  attemptId: string;
  rowsYielded: number;
  summary: string;
  hint: string;
  next: Readonly<{
    operation: 'deliveryAttempt';
    ref: Readonly<RunReference>;
    resultName: string;
    attemptId: string;
    lookupContext: Readonly<{endpoint: string; scopeRef: string}>;
  }>;
}>;
/** SDK-observed progress for this exact read error; no opening, Run or release proof. */
export declare function explainReadFailure(result: unknown, options?: OperationExplanationOptions): ReadFailureExplanation | undefined;

export type CancellationExplanation = Readonly<{
  summary: string;
  next: Readonly<{operation: 'status'; ref: Readonly<RunReference>}>;
}> & (Readonly<{
  observation: 'accepted' | 'already_requested' | 'already_terminal'; revision: number;
}> | Readonly<{observation: 'outcome_unknown'}>);
/** Read-only advice for this exact Execution.cancel result; no cancellation-operation identity or stop/release proof. */
export declare function explainCancellation(result: unknown, options?: OperationExplanationOptions): CancellationExplanation | undefined;
/** Omitted for unavailable/stale input or a pointer without a submitted JSON node. No edits are applied. */
export declare function resolveCheckLocation(outcome: CheckOutcome,
  location: WireCheckLocation, currentInput?: CheckInput):
  (WireCheckLocation & Readonly<{input: CheckInput; text?: string}>) | undefined;
export type CheckPositionEncoding = 'utf-8' | 'utf-16' | 'utf-32';
export type CheckTextRange<E extends CheckPositionEncoding = CheckPositionEncoding> =
  Extract<WireCheckLocation, {kind: 'text'}> & Readonly<{
    input: CheckInput & Readonly<{kind: 'text'; text: string}>;
    text: string;
    positionEncoding: E;
    range: Readonly<{
      start: Readonly<{line: number; character: number}>;
      end: Readonly<{line: number; character: number}>;
    }>;
  }>;
/** Zero-based UTF-16 coordinates for the original revision; no CRLF-interior position or edits. */
export declare function resolveCheckTextRange(outcome: CheckOutcome,
  location: WireCheckLocation, currentInput?: CheckInput): CheckTextRange<'utf-16'> | undefined;
/** Use the already negotiated encoding; undefined for unsupported encodings or inexact boundaries. */
export declare function resolveCheckTextRangeEncoding<E extends CheckPositionEncoding>(outcome: CheckOutcome,
  location: WireCheckLocation, encoding: E, currentInput?: CheckInput): CheckTextRange<E> | undefined;
export type CheckDocumentObservation = Readonly<{
  outcome: CheckOutcome;
  version: number;
  positionEncoding: CheckPositionEncoding;
}>;
export interface CheckDocumentSession {
  /** Full replacement with a strictly increasing signed 32-bit version, including undo/redo. */
  update(text: string, version: number): void;
  /** Explicit check of the buffer captured at invocation; no execution or automatic retries. */
  check(options: Parameters<Client['check']>[1]): Promise<CheckDocumentObservation>;
  /** Only the newest issued check of this still-open current version may supply editor coordinates. */
  resolveTextRange(observation: CheckDocumentObservation, location: WireCheckLocation): CheckTextRange | undefined;
  /** Safe display in the negotiated encoding; omit positions for stale, foreign or copied observations. */
  format(observation: CheckDocumentObservation, options?: Omit<CheckFormatOptions, 'positionEncoding'>): string | undefined;
  /** Invalidate editor coordinates and release the current buffer; does not close the shared Client. */
  close(): void;
}
/** One open-buffer scope. Reopening requires a new session; UTF-16 is the default encoding. */
export declare function createCheckDocumentSession(client: Pick<Client, 'check'>,
  options: Readonly<{text: string; version: number; positionEncoding?: CheckPositionEncoding}>): CheckDocumentSession;
export declare function explainCheckReason(reason: Readonly<{code: string; facts?: unknown}>,
  options?: CheckExplanationOptions):
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
export declare function explainEffectUncertainty(state: unknown, options?: OperationExplanationOptions):
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
