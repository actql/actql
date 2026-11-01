/// <reference lib="esnext.disposable" />
import type {StandardSchemaV1} from './standard-schema.js';
export type {StandardSchemaV1} from './standard-schema.js';
export {connectInProcess} from './host-port.js';
export {getCheckReasonCatalogInfo, getCheckReasonCatalogEntry,
  type CheckReasonCatalogInfo, type CheckReasonCatalogEntry, type KnownCheckReasonCode} from './check-reason-catalog.generated.js';
import type {ClientSourceFormat, WireCancellationAttempt, WireCancellationRef, WireOperationAttemptRef,
  WireCancellationLookup, WireCheckpointSummary, WireClientProfile,
  WireConnection, WireSubmissionRef, WireSubmissionOutcome, WireSubmissionLookup, WireSubmissionRestart, WireSubmissionAttempt,
  WireNamedSubmissionAttempt,
  WireRequestCancellation,
  WireDeliveryAttemptLookup, WireHeldRequest, WireRequestLookup,
  WireResolveItem, WireResolveResult, WireRunRef,
  WireRunState, WireResultDescription, WireCheckOutcome, WireCheckLocation, WireCheckFix,
  WireEffectfulStaticPlanView, WirePlanView, WireRunView, WireRunPlanView} from
  '@actql/client-wire';

export type Durability = 'volatile' | 'durable';
export type RunReference = WireRunRef;
export type CancellationReference = WireCancellationRef;
export type CancellationLookup = WireCancellationLookup;
export type SubmissionReference = WireSubmissionRef;
export type SubmissionOutcome = WireSubmissionOutcome | Extract<WireSubmissionLookup, {kind: 'unresolvable'}>;
export type SubmissionAttempt = WireSubmissionAttempt | WireNamedSubmissionAttempt;
export type SubmissionLookup = WireSubmissionLookup;
/** actql-check-outcome/0.1. */
export type CheckOutcome = WireCheckOutcome;
type CheckReportScope = Extract<CheckOutcome, {outcome: 'completed'}>['report']['scope'];
type CheckReportExplanation<C extends 'complete' | 'partial'> = Readonly<{
  completeness: C;
  verdict: C extends 'partial' ? 'invalid' | 'undetermined' : 'invalid' | 'undetermined' | 'verified';
  scope: CheckReportScope;
  contextRef: string;
  omissions?: Readonly<{requirements: true}>;
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
/** A rejected check observation, never a verdict, accepted report or retry grant. */
export type CheckFailureExplanation = Readonly<{summary: string; hint: string}> & (
  Readonly<{kind: 'uninterpretable'; problem: 'unknown_outcome'}> |
  Readonly<{kind: 'protocol_failure'; problem: 'contract_mismatch' | 'malformed_response'}>);
/** Available only for the original SDK error from response decoding/admission. */
export declare function explainCheckFailure(error: unknown,
  options?: CheckExplanationOptions): CheckFailureExplanation | undefined;
/** Detached input actually submitted by this call; no Host document revision. */
export type CheckFailureInput = Readonly<{scope: 'template_only' | 'bound_input'; parameters?: unknown}> &
  (Readonly<{kind: 'text'; text: string; format: 'sql' | 'aql' | 'aql-text'; parameterDeclarations?: unknown}> |
    Readonly<{kind: 'program'; program: Readonly<Record<string, unknown>>}>);
/** Explicit access only; copied/foreign errors cannot recover the original input. */
export declare function getCheckFailureInput(error: unknown): CheckFailureInput | undefined;
export type CheckInput = Readonly<{documentId: string; revision: string}> & (
  Readonly<{kind: 'text'; text: string}> | Readonly<{kind: 'structured'; value: unknown}>);
/** Available only for the exact check or rejection observation of this SDK call. */
export declare function getCheckInput(outcome: CheckOutcome, documentId: string,
  revision?: string): CheckInput | undefined;
export type CheckFix = WireCheckFix;
/** Only this SDK response offers revision-bound proposals; copied data has no input custody. */
export declare function getCheckFixes(outcome: CheckOutcome): readonly CheckFix[] | undefined;
type CompletedCheckReport = Extract<CheckOutcome, {outcome: 'completed'}>['report'];
type ParameterRequirementFacts = Readonly<Pick<Extract<
  CompletedCheckReport['requirements'][number]['facts'], {parameter: string; expected_type: string}>,
  'parameter' | 'expected_type'> & {admission?: CheckParameterAdmission}>;
/** The known public parameter Requirements, not a complete future obligation list. */
export type CheckRequirementFrontier = Readonly<{
  contextRef: string;
  reasonSchemaCid: string;
  scope: CompletedCheckReport['scope'];
  requirements: readonly Readonly<{
    code: 'parameter_value_required';
    facts: ParameterRequirementFacts;
  }>[];
  coverage: CompletedCheckReport['coverage'];
}>;
/** Known public context selections from the original completed check; no write permission. */
export type CheckContextRequirement = Readonly<{
  code: 'host_capacity_policy_required';
  facts: Extract<NonNullable<CompletedCheckReport['requirements'][number]['facts']>, {schema_pointer: '/schema'}>;
}> | Readonly<{
  code: 'numeric_reduction_profile_required';
  facts: Extract<NonNullable<CompletedCheckReport['requirements'][number]['facts']>, {profile_cid: string}>;
}>;
export declare function getCheckContextRequirements(outcome: unknown): readonly CheckContextRequirement[] | undefined;
/** Copied, partial and uninterpretable reports have no comparable frontier. */
export declare function getCheckRequirementFrontier(outcome: CheckOutcome): CheckRequirementFrontier | undefined;
/** Structural set equality within the same bound scope/context; never verification. */
export declare function equalCheckRequirementFrontiers(first: CheckOutcome, second: CheckOutcome): boolean | undefined;
export type CheckSupplementationDecision = Readonly<{kind: 'more_checks'}> |
  Readonly<{kind: 'stop'; reason: 'frontier_unavailable' | 'no_known_supplement' |
    'unchanged_frontier' | 'attempt_budget'}>;
export type CheckScopeOptions = Readonly<{scope: 'template_only'; parameters?: never}> |
  Readonly<{scope: 'bound_input'; parameters?: Record<string, unknown> | null}>;
export type CheckTextOptions = CheckScopeOptions & Readonly<{
  format: 'aql' | 'aql-text' | 'sql'; parameterDeclarations?: Record<string, unknown>; signal?: AbortSignal;
}>;
export type TextCheckOptions = CheckTextOptions & Readonly<{kind: 'text'}>;
export type ProgramCheckOptions = CheckScopeOptions & Readonly<{
  kind: 'program'; format?: never; parameterDeclarations?: never; signal?: AbortSignal;
}>;
export type CheckSupplementationObservation = Readonly<{
  outcome: CheckOutcome; attempts: number; decision: CheckSupplementationDecision;
}>;
export interface CheckSupplementationSession {
  /** Explicit read-only check; no automatic I/O, supplement write or execution. */
  check(text: string, options: TextCheckOptions): Promise<CheckSupplementationObservation>;
  check(program: Record<string, unknown>, options: ProgramCheckOptions): Promise<CheckSupplementationObservation>;
}
/** A total attempt cap also applies when the bound context keeps changing. */
export declare function createCheckSupplementationSession(client: Pick<Client, 'check'>,
  options: Readonly<{maxAttempts: number}>): CheckSupplementationSession;
export type SubmissionInput = Readonly<{
  requestId: string;
  /** A public scoped name; the retained submissionRef is its sent first-binding
   * candidate, not evidence that this candidate became the durable original. */
  requestName?: string;
  submissionRef?: WireSubmissionRef;
  attemptRef?: WireOperationAttemptRef;
  unresolvedHistory?: WireSubmissionRestart;
  kind: 'program' | 'aql';
  input: unknown;
  parameters: unknown;
  connection: Readonly<WireConnection>;
  lookupContext: Readonly<{endpoint: string; scopeRef: string}>;
}>;
/** Detached original of the pending Promise, execution or exact SDK error.
 * Available before first send; not Host persistence, acceptance or resend authority. */
export declare function getSubmissionInput(result: unknown): SubmissionInput | undefined;
/** Persistable lookup data, not an authenticated identity, acceptance or retry grant.
 * Restoring it requires the same endpoint and confirmed connection scope. */
export type RequestLookupTarget = RequestObservationTarget;
/** Exact, schema-admitted Owner response only; error codes alone provide no facts. */
export declare function getSubmissionOutcome(result: unknown): SubmissionOutcome | undefined;
/** Invocation-bound admission fact; distinct from the durable original receipt. */
export declare function getSubmissionAttempt(result: unknown): SubmissionAttempt | undefined;
/** Newly bound checking of this original source submission; never changes acceptance or grants execution. */
export declare function getSubmissionCheckObservation(result: unknown): CheckOutcome | undefined;
type RequestObservationTarget = Readonly<{lookupContext: Readonly<{endpoint: string; scopeRef: string}>}> & (
  Readonly<{operation: 'lookupRequest'; requestId: string}> |
  Readonly<{operation: 'lookupSubmission'; submissionRef: SubmissionReference}>);
export type HeldRequestExplanation = Readonly<{
  observation: 'request_held';
  preparationState: 'waiting_checkpoint' | 'resuming' | 'ended';
  prepareAttemptId: string;
  durability: 'durable';
  summary: string;
  hint: string;
  next: RequestObservationTarget;
}>;
export type SubmissionExplanation = Readonly<{summary: string}> & (
  Readonly<{
    observation: 'acceptance_unknown';
    next: RequestObservationTarget;
  }> | HeldRequestExplanation | Readonly<{
    observation: 'run_reference_received';
    next: Readonly<{operation: 'status'; ref: Readonly<RunReference>}>;
  }> | Readonly<{
    observation: 'refused'; reason: Extract<SubmissionAttempt, {kind: 'refused'}>['reason'];
    guarantee: 'attempt_uncommitted_unconsumed';
    attemptRef: Readonly<WireOperationAttemptRef & {operation: 'submit'}>;
    submissionRef: Readonly<SubmissionReference>; hint: string;
    next: RequestObservationTarget & Readonly<{operation: 'lookupSubmission'}>;
  }> | Readonly<{
    observation: 'conflict'; reason: Extract<SubmissionAttempt, {kind: 'conflict'}>['reason'];
    attemptRef: Readonly<WireOperationAttemptRef & {operation: 'submit'}>;
    submissionRef: Readonly<SubmissionReference>; hint: string;
    next: RequestObservationTarget & Readonly<{operation: 'lookupSubmission'}>;
  }> | Readonly<{
    observation: 'not_accepted' | 'preparation_failed';
    problem: Extract<SubmissionOutcome, {kind: 'not_accepted'}>['problem'];
    preparationIssue?: Readonly<{kind: 'analysis_budget_exhausted' | 'implementation_limit'; summary: string; hint: string}>;
    hint: string;
    next: RequestObservationTarget & Readonly<{operation: 'lookupSubmission'}>;
  }> | Readonly<{
    observation: 'preparing' | 'history_unresolvable' | 'lookup_unavailable' |
      'lookup_uninterpretable' | 'not_sent';
    hint: string;
    next: RequestObservationTarget & Readonly<{operation: 'lookupSubmission'}>;
  }>);
/** Read-only advice for this exact SDK submit or lookup result; no retry or execution permission.
 * Refused certifies only this invocation's uncommitted/unconsumed outcome. */
export declare function explainSubmission(result: unknown, options?: OperationExplanationOptions): SubmissionExplanation | undefined;
export type RequestLookupExplanation = Readonly<{summary: string; hint: string}> & (
  HeldRequestExplanation | Readonly<{
    observation: 'lookup_unresolved' | 'lookup_unavailable' | 'lookup_uninterpretable';
    next: RequestLookupTarget;
  }> | Readonly<{
    observation: 'run_reference_received';
    durability: 'durable' | 'volatile';
    next: Readonly<{operation: 'status'; ref: Readonly<RunReference>}>;
  }>);
/** Original admitted lookup or rejected observation; no unvalidated Owner facts or authority. */
export declare function explainRequestLookup(result: unknown, options?: OperationExplanationOptions): RequestLookupExplanation | undefined;
export type ReadFailureExplanation = Readonly<{
  observation: 'read_open_unknown' | 'read_incomplete' | 'cleanup_unknown';
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

export type DeliveryObservationExplanation = Readonly<{
  summary: string;
  hint: string;
  next: ReadFailureExplanation['next'];
}> & (Readonly<{observation: 'lookup_unresolved' | 'lookup_unavailable' | 'lookup_uninterpretable' | 'attempt_recorded'}> |
  (Readonly<{
    recordSequence: number;
    /** Sink-confirmed Host bytes, never the caller's yielded-row count. */
    hostConfirmedByteCount: number;
    exposure: 'exact' | 'unknown_additional';
    possibleUnconfirmedMaxBytes?: number;
    /** Omitted does not certify application cleanup or other Owner releases. */
    cleanup?: 'unresolved';
  }> & (Readonly<{
    observation: 'delivery_streaming' | 'delivery_failed' | 'delivery_cancelled';
  }> | Readonly<{
    observation: 'host_delivery_succeeded';
    hostReleaseReceiptCid: string;
    deliveredSha256: string;
  }>)));
/** Original admitted lookup or safe lookup error; no Run, received-row or application-persistence proof. */
export declare function explainDeliveryAttempt(result: unknown,
  options?: OperationExplanationOptions): DeliveryObservationExplanation | undefined;

export type RequestCancellationExplanation = Readonly<{
  requestId: string;
  summary: string;
  hint: string;
}> & (Readonly<{
  observation: 'accepted' | 'already_requested' | 'already_terminal';
}> & (Readonly<{
  revision: number;
  next: Readonly<{operation: 'status'; ref: Readonly<RunReference>}>;
}> | Readonly<{next: RequestLookupTarget}>) | Readonly<{
  observation: 'outcome_unknown';
  problem: 'exchange_failed' | 'response_uninterpretable';
  next: RequestLookupTarget;
}>);
/** Original request-cancellation observation; no cancel-operation identity or stop/release certificate. */
export declare function explainRequestCancellation(result: unknown, options?: OperationExplanationOptions): RequestCancellationExplanation | undefined;
export type CancellationExplanation = Readonly<{
  summary: string;
}> & (Readonly<{
  observation: 'accepted' | 'already_requested' | 'already_terminal'; revision: number;
  next: Readonly<{operation: 'status'; ref: Readonly<RunReference>}>;
}> | Readonly<{observation: 'outcome_unknown';
  next: Readonly<{operation: 'lookupCancellation'; cancelRef: Readonly<CancellationReference>}>;
}> | Readonly<{
  observation: 'refused'; reason: 'authorization' | 'admission_capacity';
  guarantee: 'attempt_uncommitted_unconsumed';
  attemptRef: Readonly<WireOperationAttemptRef & {operation: 'cancel'}>; cancelRef: Readonly<CancellationReference>;
  hint: string;
  next: Readonly<{operation: 'lookupCancellation'; cancelRef: Readonly<CancellationReference>}>;
}> | Readonly<{
  observation: 'conflict'; reason: 'intent' | 'control_revision';
  attemptRef: Readonly<WireOperationAttemptRef & {operation: 'cancel'}>; cancelRef: Readonly<CancellationReference>;
  hint: string;
  next: Readonly<{operation: 'lookupCancellation'; cancelRef: Readonly<CancellationReference>}>;
}>);
/** Read-only advice from cancel or an exact lookup; the original operation
 * reference and recorded outcome certify neither physical stop nor release.
 * Refused certifies only this invocation's uncommitted/unconsumed outcome. */
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
  check(options: CheckTextOptions): Promise<CheckDocumentObservation>;
  /** Explicitly reviewed one-document edits, committed atomically after rechecking.
   * Fresh original-request checks reject observed context changes on both sides
   * of the candidate check; they do not create an authorization lease.
   * Stale/copied proposals, conflicting edits or failed checks leave the buffer unchanged. */
  applyFixes(observation: CheckDocumentObservation, fixes: readonly CheckFix[],
    options: Readonly<{version: number; reviewed: true}>): Promise<CheckDocumentObservation>;
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
  /** An expected service Workspace, checked by the authenticated Host on every request. */
  workspaceId?: string;
  durability?: Durability;
  consentRefs?: readonly string[];
  /** Optional correlation only; never supplies authorization or baggage. */
  traceContext?: () => Readonly<{traceId: string; spanId: string; traceFlags: number}> | undefined;
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
/** Lookup-only recovery of an existing request; never submits or resumes work. */
export interface RequestRecovery {
  readonly target: RequestLookupTarget;
  lookup(options?: {signal?: AbortSignal}): Promise<RequestLookup | SubmissionLookup>;
  /** Only a found/ready observation from this handle's lookup is accepted.
   * The Host checks current authorization again when attaching. */
  attach(observation: Extract<RequestLookup, {kind: 'found'}> | Extract<SubmissionLookup, {kind: 'ready'}>,
    options?: {signal?: AbortSignal}): Promise<Execution>;
}

/** Validated wire facts with a non-wire convenience alias on an actual
 * Checkpoint reference. Other states do not fabricate a Checkpoint. */
export type RunState = Omit<WireRunState, 'checkpoint'> & Readonly<{
  checkpoint?: NonNullable<WireRunState['checkpoint']> & Readonly<{id: string}>;
}>;
export type OwnerObservations = import('@actql/client-wire').WireOwnerObservations;
export type OwnerCursor = import('@actql/client-wire').WireOwnerCursor;
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
  /** Candidate only: the existing Host rechecks current authority and original custody. */
  next: Readonly<{operation: 'reconcile'; ref: Readonly<RunReference>}>;
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
  /** Present only after a Run was admitted; never fabricated for RequestHeld. */
  readonly execution?: Execution;
  readonly executionRef?: RunReference;
  /** Exact owner observation on a short query failure; omitted from JSON. */
  readonly observation?: RunState;
  /** Original immutable cancellation target on uncertainty or refusal. */
  readonly cancelRef?: Readonly<CancellationReference>;
  readonly attemptRef?: Readonly<WireOperationAttemptRef>;
  /** Complete rows returned by the failed call; aggregate calls return none. */
  readonly rowsYielded?: number;
  /** Local schema validation failure; the Run itself is unchanged. */
  readonly validationKind?: 'issues' | 'exception' | 'invalid_result';
  /** Zero-based index of the raw row that failed validation. */
  readonly rowIndex?: number;
  readonly resultRef?: ResultReference;
  /** Explicit schema diagnostics, omitted from default JSON serialization. */
  readonly issues?: readonly StandardSchemaV1.Issue[];
  readonly cleanupError?: unknown;
  /** Client cleanup has not confirmed release; retry await client.close(). */
  readonly cleanupPending?: boolean;
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

export type DynamicRow = Record<string, unknown>;
/** Recovery locator using the existing Run and authored Result name. */
export type ResultReference = Readonly<{run: RunReference; resultName: string}>;
export type QueryParameters = Record<string, unknown> | null;
export type QueryOptions = SubmissionIdentityOptions & Readonly<{
  attemptId?: string;
  signal?: AbortSignal;
  result?: string;
  parameterDeclarations?: Record<string, unknown>;
}>;

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
  /** Opening failures retain their attempt; lookup absence is not no-send proof. */
  state(): 'not_started' | 'opening' | 'open_unknown' | 'prefix' | 'complete';
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
  readonly ref: ResultReference;
  readonly execution: Execution;
  describe(options?: ResultDescriptionOptions): Promise<ResultDescription>;
  /** Serial validation; output types come from the schema, not a cast. */
  rows<Schema extends StandardSchemaV1>(schema: Schema,
    options?: ReadOptions): Reader<StandardSchemaV1.InferOutput<Schema>>;
  rows(options?: ReadOptions): Reader<DynamicRow>;
  batches(options?: ReadOptions): Reader<DynamicRow[]>;
  /** Raw rows are charged before validation; transformed output size is not bounded. */
  all<Schema extends StandardSchemaV1>(schema: Schema,
    options?: ReadOptions): Promise<StandardSchemaV1.InferOutput<Schema>[]>;
  all(options?: ReadOptions): Promise<DynamicRow[]>;
  one(options?: ReadOptions): Promise<DynamicRow>;
  scalar(options?: ReadOptions): Promise<unknown>;
  /** Detached, recursively frozen snapshot of this lookup's admitted response. */
  deliveryAttempt(attemptId: string,
    options?: {signal?: AbortSignal}): Promise<DeliveryAttemptLookup>;
}

/** One eager submission. Re-awaiting shares its Result; collection opens a fresh read. */
export interface ResultPromise extends Promise<Result> {
  readonly requestId: string;
  /** Raw rows are charged before validation; transformed output size is not bounded. */
  all<Schema extends StandardSchemaV1>(schema: Schema,
    options?: ReadOptions): Promise<StandardSchemaV1.InferOutput<Schema>[]>;
  all(options?: ReadOptions): Promise<DynamicRow[]>;
  one(options?: ReadOptions): Promise<DynamicRow>;
  scalar(options?: ReadOptions): Promise<unknown>;
}

export interface Execution {
  readonly ref: RunReference;
  readonly profile: ConfirmedProfile;
  status(options?: {signal?: AbortSignal}): Promise<RunState>;
  /** Saved original compiler map; unavailable legacy evidence is not recompiled. */
  plan(options?: {signal?: AbortSignal; maxWireBytes?: number;
    maxNodes?: number; maxDepth?: number}): Promise<WireRunPlanView>;
  /** Read-only Owner-local projection; omitted pending facts remain unknown. */
  inspect(options?: {signal?: AbortSignal; maxWireBytes?: number;
    maxNodes?: number; maxDepth?: number}): Promise<WireRunView>;
  /** Independent Owner-local views; cursors are not authority or control revisions. */
  observeOwners(options?: {signal?:AbortSignal;cursors?:readonly OwnerCursor[];
    maxEntries?:number;maxWireBytes?:number}): Promise<OwnerObservations>;
  wait(options?: {until?: string; since?: number | null; signal?: AbortSignal}): Promise<RunState>;
  /** A new operation observes the current control revision when omitted.
   * A lost response retains cancelRef; lookup never resends the cancellation. */
  cancel(options?: {signal?: AbortSignal; cancelId?: string;
    expectedRevision?: number; attemptId?: string}): Promise<WireCancellationAttempt>;
  lookupCancellation(ref: CancellationReference,
    options?: {signal?: AbortSignal}): Promise<CancellationLookup>;
  reconcile(options?: {signal?: AbortSignal}): Promise<RunState>;
  result(name: string): Result;
}

type SubmissionIdentityOptions = (
  /** Omit for deliberate new work; retain getSubmissionInput(promise) before awaiting. */
  Readonly<{submissionRef?: undefined; requestId?: never; unresolvedHistory?: never}> |
  /** Scoped durable name, resolved by the Host's original named-submission
   * Owner. A new connection's candidate never replaces saved named custody. */
  Readonly<{submissionRef?: undefined; requestId: string; unresolvedHistory?: never}> |
  /** requestId only asserts this original nonce; it never allocates an identity. */
  Readonly<{submissionRef: WireSubmissionRef; requestId?: string;
    unresolvedHistory?: WireSubmissionRestart}>
);
export type SubmissionOptions = SubmissionIdentityOptions & Readonly<{
  attemptId?: string;
  parameters?: unknown;
  /** Persist an explicit review stop before the original Run's first Effect. */
  stopBefore?: 'commit';
  /** Retained read-only continuation choice; never an Account grant. */
  readOnly?: true;
  signal?: AbortSignal;
}>;

export interface Client {
  /** Allocate and retain before sending; reconnect never replaces an original ref. */
  newSubmission(options?: {nonce?: string}): WireSubmissionRef;
  lookupSubmission(ref: WireSubmissionRef, options?: {signal?: AbortSignal}): Promise<WireSubmissionLookup>;
  readonly profile: ConfirmedProfile;
  readonly requestedDurability: Durability | null;
  sql(text: string, parameters?: QueryParameters, options?: QueryOptions): ResultPromise;
  aql(text: string, parameters?: QueryParameters, options?: QueryOptions): ResultPromise;
  /**
   * Source admission without an automatic wait or Result read. Supports checked
   * Effect-only Programs; use the Execution and ordinary Checkpoint APIs, not
   * Result selection, when no public Results are declared.
   */
  startSource(text: string, options: SubmissionOptions & {
    format: ClientSourceFormat;
    /** The existing Program params map, admitted by the Host checker. */
    parameterDeclarations?: Record<string, unknown>;
  }): Promise<Execution>;
  /**
   * Check an authored text or Program snapshot without starting anything. Completed, failed and
   * unavailable are all returned outcomes; a verdict is always bound to its
   * scope and context reference.
   */
  check(text: string, options: TextCheckOptions): Promise<CheckOutcome>;
  check(program: Record<string, unknown>, options: ProgramCheckOptions): Promise<CheckOutcome>;
  /** Static checked Plan projection; creates no Run and performs no Provider I/O. */
  plan(input: string | Record<string, unknown>, options?: {
    kind?: 'aql' | 'program'; format?: ClientSourceFormat;
    parameterDeclarations?: Record<string, unknown>;
    parameters?: QueryParameters;
    maxWireBytes?: number; maxNodes?: number; maxDepth?: number;
    signal?: AbortSignal;
  }): Promise<WirePlanView | WireEffectfulStaticPlanView>;
  start(program: Record<string, unknown>, options?: SubmissionOptions): Promise<Execution>;
  attach(ref: RunReference, options?: {signal?: AbortSignal}): Promise<Execution>;
  lookupRequest(requestId: string,
    options?: {signal?: AbortSignal}): Promise<RequestLookup>;
  /** No I/O. Accepts this SDK's original submission/lookup observation, or a
   * saved RequestLookupTarget as untrusted data. Copies of errors are refused. */
  recoverRequest(observationOrTarget: unknown): RequestRecovery;
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
  checkpoints(options?: {after?: string; limit?: number; checkpointId?: string;
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
  /** Exact authorized pending-ID lookup, then the existing signed resolution.
   * Without an explicit application signer, requires the installed Local
   * provider's original signing custody; never discovers or creates a key.
   * On ResolutionUnknown, resend only its exact `signed` items through
   * resolveCheckpoints; do not call approve/reject again to re-sign. */
  approve(checkpointId: string, options?: {signer?: CheckpointSigner;
    signal?: AbortSignal}): ReturnType<Client['resolveCheckpoints']>;
  reject(checkpointId: string, options?: {signer?: CheckpointSigner;
    signal?: AbortSignal}): ReturnType<Client['resolveCheckpoints']>;
  /** Seal this Client immediately, release its readers and await its Local
   * lease. Does not cancel Runs. A failed close may be retried. */
  close(): Promise<void>;
  [Symbol.asyncDispose](): Promise<void>;
}

export declare function connect(options: ConnectionOptions): Promise<Client>;
/** A credential-bearing actql:// connection string, or one with a separate token provider. */
export type ConnectionStringOptions = Readonly<{
  token?: string | (() => string | Promise<string>);
  durability?: Durability;
  consentRefs?: readonly string[];
  traceContext?: ConnectedEndpoint['traceContext'];
}>;
export declare function connect(connectionString: string,
  options?: ConnectionStringOptions): Promise<Client>;

/** The caller-owned declaration contract/rules, not complete Program verification. */
export type CheckParameterAdmission = NonNullable<Extract<NonNullable<
  Extract<CheckOutcome, {outcome: 'completed'}>['report']['requirements'][number]['facts']>,
  {admission?: unknown}>['admission']>;
/** Undefined without original check custody, a disclosed Requirement or typed conditions. */
export declare function getCheckParameterAdmission(outcome: unknown,
  parameter: string): CheckParameterAdmission | undefined;

/** Complete display of original SDK-owned operation facts; never performs I/O. */
export type OperationFormatOptions = OperationExplanationOptions & Readonly<{
  format?: 'text' | 'html' | 'json';
  /** UTF-8 output bytes, 1024..1048576. Undefined output if complete facts cannot fit. */
  maxBytes?: number;
}>;
export declare function formatSubmission(result: unknown, options?: OperationFormatOptions): string | undefined;
export declare function formatRequestLookup(result: unknown, options?: OperationFormatOptions): string | undefined;
export declare function formatCancellation(result: unknown, options?: OperationFormatOptions): string | undefined;
export declare function formatRequestCancellation(result: unknown, options?: OperationFormatOptions): string | undefined;
export declare function formatReadFailure(result: unknown, options?: OperationFormatOptions): string | undefined;
export declare function formatDeliveryAttempt(result: unknown, options?: OperationFormatOptions): string | undefined;
export declare function formatEffectUncertainty(result: unknown, options?: OperationFormatOptions): string | undefined;
/** Passive text/HTML/agent JSON for an original SDK Run-observation error. */
export declare function formatRunObservationFailure(error: unknown, options?: OperationFormatOptions): string | undefined;

/** Safe explanation of an original SDK-rejected Run observation; no write permission. */
export type RunObservationFailureExplanation = Readonly<{
  operation: 'status' | 'wait' | 'reconcile';
  summary: string;
  hint: string;
  next: Readonly<{operation: 'status'; ref: RunReference}>;
}> & (Readonly<{kind: 'uninterpretable'; problem: 'unknown_state'}> |
  Readonly<{kind: 'unavailable'; problem: 'observation_unavailable'}> |
  Readonly<{kind: 'protocol_failure'; problem: 'contract_mismatch' | 'malformed_response' | 'stale_observation'}>);
export declare function explainRunObservationFailure(error: unknown,
  options?: OperationExplanationOptions): RunObservationFailureExplanation | undefined;

/** Passive explanation bound to an original SDK-admitted multi-Owner observation. */
export type OwnerObservationAdvice = Readonly<{summary: string; hint: string}>;
type ExplainedOwnerView<T> = T extends {history: infer H}
  ? Omit<T, 'history' | 'snapshotProblem'> & Readonly<{history: H & OwnerObservationAdvice}> &
    (T extends {snapshotProblem: infer P}
      ? Readonly<{snapshotProblem: P & OwnerObservationAdvice}> : {})
  : T & OwnerObservationAdvice;
export type OwnerObservationsExplanation = Omit<OwnerObservations, 'owners'> & OwnerObservationAdvice & Readonly<{
  observation: 'owner_views';
  owners: readonly ExplainedOwnerView<OwnerObservations['owners'][number]>[];
  requested: Readonly<{cursors: readonly OwnerCursor[]; maxEntries: number; maxWireBytes: number}>;
  lookupContext: Readonly<{endpoint: string; scopeRef: string}>;
}>;
/** Copies, foreign responses and rejected observations have no explanation custody. */
export declare function explainOwnerObservations(result: unknown,
  options?: OperationExplanationOptions): OwnerObservationsExplanation | undefined;
export declare function formatOwnerObservations(result: unknown,
  options?: OperationFormatOptions): string | undefined;
