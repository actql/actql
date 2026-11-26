/// <reference lib="esnext.disposable" preserve="true" />

import {connectSelected} from './internal/client.mjs';
import {connectionFailure, connectionObjectExample, connectionOptions, connectionStringExample,
  connectionStringOptions} from './internal/connection-options.mjs';
import {isOwnedClientFailure} from './internal/errors.mjs';
import {explainDeliveryAttempt, explainReadFailure} from './internal/result-read.mjs';
import {explainCancellation, explainEffectUncertainty, explainOwnerObservations,
  explainRunObservationFailure} from './internal/run-observation.mjs';
import {explainRequestCancellation, explainRequestLookup, explainSubmission} from './internal/submission-observation.mjs';
import {formatOperationExplanation} from './operation-formats.mjs';

export {getCheckReasonCatalogInfo, getCheckReasonCatalogEntry,
  type CheckReasonCatalogInfo, type CheckReasonCatalogEntry, type KnownCheckReasonCode} from './check-reason-catalog.generated.js';
export {getCheckPresentationInfo} from './check-presentation.mjs';
export {getOperationPresentationInfo} from './operation-presentation.mjs';
export {explainCheckOutcome, explainCheckReason} from './check-presentation.mjs';
export {ClientError} from './internal/errors.mjs';
export {getCheckFailureInput, explainCheckFailure, getCheckInput, getCheckFixes,
  getCheckParameterAdmission, getCheckContextRequirements, getCheckRequirementFrontier,
  equalCheckRequirementFrontiers, createCheckSupplementationSession, resolveCheckLocation,
  resolveCheckTextRange, resolveCheckTextRangeEncoding, createCheckDocumentSession,
  formatCheckOutcome} from './internal/check-observation.mjs';
export {getSubmissionCheckObservation, getSubmissionInput, getSubmissionOutcome,
  getSubmissionAttempt, explainSubmission, explainRequestLookup, explainRequestCancellation,
  RequestHeld} from './internal/submission-observation.mjs';
export {explainRunObservationFailure, explainOwnerObservations, explainEffectUncertainty,
  explainCancellation} from './internal/run-observation.mjs';
export {explainReadFailure, explainDeliveryAttempt} from './internal/result-read.mjs';
export function connect(options: ConnectionOptions): Promise<Client>;
export function connect(connectionString: string, options?: ConnectionStringOptions): Promise<Client>;
export async function connect(options: unknown, stringOptions?: unknown): Promise<Client> {
  const connectionString = typeof options === 'string';
  if (!connectionString && stringOptions !== undefined) {
    connectionFailure('InvalidConnectionOptions',
      'Object connections take one options argument. ' + connectionObjectExample);
  }
  let selected;
  try {
    selected = connectionOptions(connectionString
      ? connectionStringOptions(options, stringOptions) : options, connectionString);
  } catch (error) {
    if (!isOwnedClientFailure(error)) {
      connectionFailure('InvalidConnectionOptions',
        'Connection options could not be read safely. ' +
        (connectionString ? connectionStringExample : connectionObjectExample));
    }
    throw error;
  }
  return connectSelected(connectionString
    ? Object.freeze({...selected, redactCredentialErrors: true}) : selected);
}

export {connectInProcess} from './host-port.mjs';

/** Display retained operation facts without lookup, retry or execution authority. */
export function formatSubmission(result: unknown, options?: OperationFormatOptions) {
  return formatOperationExplanation(explainSubmission(result), 'submission', options);
}
export function formatRequestLookup(result: unknown, options?: OperationFormatOptions) {
  return formatOperationExplanation(explainRequestLookup(result), 'request', options);
}
export function formatRequestCancellation(result: unknown, options?: OperationFormatOptions) {
  return formatOperationExplanation(explainRequestCancellation(result), 'requestCancellation', options);
}
export function formatCancellation(result: unknown, options?: OperationFormatOptions) {
  return formatOperationExplanation(explainCancellation(result), 'cancellation', options);
}
export function formatReadFailure(result: unknown, options?: OperationFormatOptions) {
  return formatOperationExplanation(explainReadFailure(result), 'read', options);
}
export function formatDeliveryAttempt(result: unknown, options?: OperationFormatOptions) {
  return formatOperationExplanation(explainDeliveryAttempt(result), 'delivery', options);
}
export function formatEffectUncertainty(result: unknown, options?: OperationFormatOptions) {
  return formatOperationExplanation(explainEffectUncertainty(result), 'effect', options);
}

export function formatRunObservationFailure(error: unknown, options?: OperationFormatOptions) {
  return formatOperationExplanation(explainRunObservationFailure(error), 'observation', options);
}

export function formatOwnerObservations(result: unknown, options?: OperationFormatOptions) {
  return formatOperationExplanation(explainOwnerObservations(result), 'ownerObservations', options);
}

import type {StandardSchemaV1} from './standard-schema.js';
export type {StandardSchemaV1} from './standard-schema.js';
import type {ClientSourceFormat, WireCancellationAttempt, WireCancellationRef, WireOperationAttemptRef,
  WireCancellationLookup, WireCheckpointSummary, WireClientProfile,
  WireConnection, WireSubmissionRef, WireSubmissionOutcome, WireSubmissionLookup, WireSubmissionRestart, WireSubmissionAttempt,
  WireNamedSubmissionAttempt,
  WireRequestCancellation,
  WireDeliveryAttemptLookup, WireHeldRequest, WireRequestLookup,
  WireResolveItem, WireResolveResult, WireRunRef,
  WireRunState, WireResultDescription, WireCheckOutcome, WireCheckLocation, WireCheckFix,
  WireEffectfulStaticPlanView, WirePlanView, WireRunView, WireRunPlanView, WireRunExplanationView,
  WireRunExplanationContextView, WireStaticExplanationView, WireRunSample, WireSampleSelector,
  WireControlCommand, WireControlOperationRef, WireControlOperationLookup} from
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
/** Display formats for an admitted public observation; no execution or edit authority. */
export type CheckFormatOptions = CheckExplanationOptions & Readonly<{
  format?: 'text' | 'html' | 'json';
  maxBytes?: number;
  currentInputs?: readonly CheckInput[];
  /** The negotiated encoding for text coordinates; UTF-16 is the default. */
  positionEncoding?: CheckPositionEncoding;
}>;
/** A rejected check observation, never a verdict, accepted report or retry grant. */
export type CheckFailureExplanation = Readonly<{summary: string; hint: string}> & (
  Readonly<{kind: 'uninterpretable'; problem: 'unknown_outcome'}> |
  Readonly<{kind: 'protocol_failure'; problem: 'contract_mismatch' | 'malformed_response'}>);
/** Detached input actually submitted by this call; no Host document revision. */
export type CheckFailureInput = Readonly<{scope: 'template_only' | 'bound_input'; parameters?: unknown}> &
  (Readonly<{kind: 'text'; text: string; format: 'sql' | 'aql' | 'aql-text'; parameterDeclarations?: unknown}> |
    Readonly<{kind: 'program'; program: Readonly<Record<string, unknown>>}>);
export type CheckInput = Readonly<{documentId: string; revision: string}> & (
  Readonly<{kind: 'text'; text: string}> | Readonly<{kind: 'structured'; value: unknown}>);
export type CheckFix = WireCheckFix;
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
}> | Readonly<{
  code: 'calendar_profile_required';
  facts: Readonly<{
    issue: 'selection_missing' | 'artifact_missing';
    supplier: 'checking_context_owner';
    stage: 'checking';
  }>;
}>;
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
  /** Original first-Plan selection; absent on unchanged Normal input. */
  executionProfile?: 'debug';
  connection: Readonly<WireConnection>;
  lookupContext: Readonly<{endpoint: string; scopeRef: string}>;
}>;
/** Persistable lookup data, not an authenticated identity, acceptance or retry grant.
 * Restoring it requires the same endpoint and confirmed connection scope. */
export type RequestLookupTarget = RequestObservationTarget;
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
export type RequestLookupExplanation = Readonly<{summary: string; hint: string}> & (
  HeldRequestExplanation | Readonly<{
    observation: 'lookup_unresolved' | 'lookup_unavailable' | 'lookup_uninterpretable';
    next: RequestLookupTarget;
  }> | Readonly<{
    observation: 'run_reference_received';
    durability: 'durable' | 'volatile';
    next: Readonly<{operation: 'status'; ref: Readonly<RunReference>}>;
  }>);
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

export type DynamicRow = Record<string, unknown>;
/** Recovery locator using the existing Run and authored Result name. */
export type ResultReference = Readonly<{run: RunReference; resultName: string}>;
export type QueryParameters = Record<string, unknown> | null;
export type QueryOptions = SubmissionIdentityOptions & Readonly<{
  attemptId?: string;
  signal?: AbortSignal;
  result?: string;
  parameterDeclarations?: Record<string, unknown>;
  /** Select real operation boundaries before the original Plan; no Sample/control grant. */
  executionProfile?: 'debug';
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
  /** Retained compiler-original structural facts; absent evidence is never rebuilt.
   * The signal cancels this read only, not the execution. */
  explain(options?: {signal?: AbortSignal; maxWireBytes?: number;
    maxNodes?: number; maxDepth?: number}): Promise<WireRunExplanationView>;
  /** Read the original Saved Plan, Facts, and Context where it was retained. */
  explainContext(options?: {signal?: AbortSignal; maxWireBytes?: number;
    maxNodes?: number; maxDepth?: number}): Promise<WireRunExplanationContextView>;
  /** Read a retained Sample. With nextRevision, select an exact input port of the current Next Step. */
  sample(selector: WireSampleSelector, options?: Readonly<{signal?: AbortSignal; maxWireBytes?: number;
    maxNodes?: number; maxDepth?: number; nextRevision?: number}>): Promise<WireRunSample>;
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
  /** Prepare the exact command before sending it. Operation IDs are supplied by the caller. */
  prepareResume(options: Readonly<{operationId: string; expectedRevision: number;
    until: 'step' | 'terminal'}>): Promise<WireControlCommand>;
  /** Send one sealed Resume for the observed pause on this Run. The command
   * retains the exact reference for a later lookup if the response is lost. */
  resume(command: WireControlCommand, options?: Readonly<{signal?: AbortSignal;
    maxWireBytes?: number; maxNodes?: number; maxDepth?: number}>): Promise<WireControlOperationLookup>;
  /** Recover the original control receipt through the same attached Run. */
  lookupControlOperation(ref: WireControlOperationRef, options?: Readonly<{signal?: AbortSignal;
    maxWireBytes?: number; maxNodes?: number; maxDepth?: number}>): Promise<WireControlOperationLookup>;
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
  /** Explicit first-Plan physical strategy; omission preserves Normal. */
  executionProfile?: 'debug';
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
  /** Static structural Plan, Facts and Context through the current Host's read authority. */
  explain(input: string | Record<string, unknown>,
    options?: Parameters<Client['plan']>[1]): Promise<WireStaticExplanationView>;
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
/** A credential-bearing actql:// connection string, or one with a separate token provider. */
export type ConnectionStringOptions = Readonly<{
  token?: string | (() => string | Promise<string>);
  durability?: Durability;
  consentRefs?: readonly string[];
  traceContext?: ConnectedEndpoint['traceContext'];
}>;

/** The caller-owned declaration contract/rules, not complete Program verification. */
export type CheckParameterAdmission = NonNullable<Extract<NonNullable<
  Extract<CheckOutcome, {outcome: 'completed'}>['report']['requirements'][number]['facts']>,
  {admission?: unknown}>['admission']>;

/** Complete display of original SDK-owned operation facts; never performs I/O. */
export type OperationFormatOptions = OperationExplanationOptions & Readonly<{
  format?: 'text' | 'html' | 'json';
  /** UTF-8 output bytes, 1024..1048576. Undefined output if complete facts cannot fit. */
  maxBytes?: number;
}>;

/** Safe explanation of an original SDK-rejected Run observation; no write permission. */
export type RunObservationFailureExplanation = Readonly<{
  operation: 'status' | 'wait' | 'reconcile';
  summary: string;
  hint: string;
  next: Readonly<{operation: 'status'; ref: RunReference}>;
}> & (Readonly<{kind: 'uninterpretable'; problem: 'unknown_state'}> |
  Readonly<{kind: 'unavailable'; problem: 'observation_unavailable'}> |
  Readonly<{kind: 'protocol_failure'; problem: 'contract_mismatch' | 'malformed_response' | 'stale_observation'}>);

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
