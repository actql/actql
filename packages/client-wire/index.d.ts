export * from './interactive-control.generated.js';
import type {ClientHostOperation, WireAdmissionShape, WireCancellationShape,
  WireOperationAttemptRefShape, WireCancellationAttemptShape,
  WireCancellationRefShape, WireCancellationLookupShape,
  WireSubmissionEpochShape, WireSubmissionRefShape, WireSubmissionOutcomeShape, WireSubmissionLookupShape, WireSubmissionRestartShape, WireSubmissionAttemptShape,
  WireSubmissionNameShape, WireNamedSubmissionAttemptShape,
  WireCheckpointReviewShape, WireCheckpointSummaryShape,
  WireConnectionShape, WireHeldShape, WireLookupFoundShape,
  WireLookupNotFoundShape, WireLookupUnknownShape, WireProfileShape,
  WireRequestCancellationShape, WireResourceInspectionShape,
  WireResourceListingShape, WireResourcePeekShape,
  WireResolveItemShape, WireResolveResultShape, WireRunRefShape,
  WireRunStateShape, WireSubmitPreparationErrorShape, WireCheckOutcomeShape,
  WireResultDescriptionShape, WireValueContractShape} from
  './client-host.generated.js';
import type {WireOwnerRefShape, WireOwnerCursorShape, WireOwnerObservationsShape} from './client-host.generated.js';
export type {ClientHostOperation} from './client-host.generated.js';
export {checkOutcomeProtocol, runStateProtocol} from './client-host.generated.js';

export declare const clientHostOperations: readonly ClientHostOperation[];
/** Explicit submit refusal contracts, not generic public error codes. */
export declare function isClientSubmitRejection(code: unknown): boolean;

type WireConnectionBase = Pick<WireConnectionShape,
  'durability' | 'consentRefs' | 'runners' | 'workspaceId'>;

export type WireConnection =
  | (WireConnectionBase & Readonly<{mode: 'local'; owner: 'local';
      movementPolicyRef?: never; cloudConnectionRef?: never}>)
  | (WireConnectionBase & Readonly<{mode: 'remote'; owner: 'remote';
      movementPolicyRef?: never; cloudConnectionRef?: never}>)
  | (WireConnectionBase & Readonly<{mode: 'hybrid'; owner: 'local';
      movementPolicyRef: string; cloudConnectionRef: string}>)
  | (WireConnectionBase & Readonly<{mode: 'hybrid'; owner: 'cloud';
      movementPolicyRef: string; cloudConnectionRef?: never}>);

export type WireSubmissionEpoch = WireSubmissionEpochShape;
export type WireSubmissionRef = WireSubmissionRefShape;
export type WireSubmissionOutcome = WireSubmissionOutcomeShape;
export type WireSubmissionAttempt = WireSubmissionAttemptShape;
export type WireSubmissionName = WireSubmissionNameShape;
export type WireNamedSubmissionAttempt = WireNamedSubmissionAttemptShape;
export declare function validSubmissionName(value: unknown): value is WireSubmissionName;
export declare function validNamedSubmissionAttempt(value: unknown, selected: WireConnection,
  name: WireSubmissionName, candidate: WireSubmissionRef, intentCid: string,
  attemptRef: WireOperationAttemptRef): value is WireNamedSubmissionAttempt;
export declare function validSubmissionAttempt(value: unknown, selected: WireConnection,
  expected: WireSubmissionRef, intentCid: string, attemptRef: WireOperationAttemptRef,
  unresolvedHistory?: WireSubmissionRestart): value is WireSubmissionAttempt;
export type WireSubmissionLookup = WireSubmissionLookupShape;
export type WireSubmissionRestart = WireSubmissionRestartShape;
export declare function validSubmissionRestart(value: unknown,
  fresh: WireSubmissionRef): value is WireSubmissionRestart;
export declare function validSubmissionEpoch(value: unknown): value is WireSubmissionEpoch;
export declare function validSubmissionRef(value: unknown): value is WireSubmissionRef;
export declare function sameSubmissionRef(left: unknown, right: unknown): boolean;
export declare function validStoredSubmissionOutcome(value: unknown,
  expected: WireSubmissionRef, intentCid: string): value is WireSubmissionOutcome;
export declare function validSubmissionOutcome(value: unknown, selected: WireConnection,
  expected: WireSubmissionRef, intentCid?: string,
  unresolvedHistory?: WireSubmissionRestart): value is WireSubmissionOutcome;
export declare function validSubmissionLookup(value: unknown, selected: WireConnection,
  expected: WireSubmissionRef): value is WireSubmissionLookup;
export type WireRunRef = WireRunRefShape;
export type WireOwnerRef = WireOwnerRefShape;
export type WireOwnerCursor = WireOwnerCursorShape;
export type WireOwnerObservations = WireOwnerObservationsShape;
export declare const ownerObservationLimits: Readonly<{maxEntries:number;maxWireBytes:number}>;
export declare function validOwnerRef(value:unknown): value is WireOwnerRef;
export declare function validOwnerCursor(value:unknown): value is WireOwnerCursor;
export declare function validOwnerObservations(value:unknown, ref:WireRunRef,
  limits?: typeof ownerObservationLimits & Readonly<{cursors?:readonly WireOwnerCursor[]}>): value is WireOwnerObservations;
export type WireResultDescription = WireResultDescriptionShape;
export type WireValueContract = WireValueContractShape;
export declare const resultDescriptionLimits: Readonly<{
  maxWireBytes: number; maxNodes: number; maxDepth: number}>;
export declare function withinResultDescriptionLimits(value: unknown,
  limits?: typeof resultDescriptionLimits): boolean;
export declare function validResultDescription(value: unknown,
  expected: Readonly<{ref: WireRunRef; resultName: string;
    format: 'json' | 'jsonl' | 'csv'}>,
  limits?: typeof resultDescriptionLimits): value is WireResultDescription;
export type WireRunState = WireRunStateShape;
export type WireSubmitPreparationError = WireSubmitPreparationErrorShape;
/** actql-check-outcome/0.1. */
export type WireCheckOutcome = WireCheckOutcomeShape;
export type {WireCheckLocationShape as WireCheckLocation} from './client-host.generated.js';
export type {WireCheckFixShape as WireCheckFix} from './client-host.generated.js';
export declare const checkReasonSchemaCid: string;
export declare const checkOutcomeSchemaCid: string;
export type ClientSourceFormat = 'json' | 'yaml' | 'aql-json' |
  'aql-yaml' | 'aql' | 'aql-text' | 'sql';
export const clientSourceFormats: readonly ClientSourceFormat[];

type WireBodyBase = Readonly<{connection: WireConnection}>;
type WireRefBody = WireBodyBase & Readonly<{ref: WireRunRef}>;

export type WireClientBodyByOperation = Readonly<{
  connect: WireBodyBase;
  submit: WireBodyBase & Readonly<{
    requestId: string;
    parameters: unknown;
  }> & (Readonly<{kind: 'aql'; input: Readonly<{
    text: string;
    format: ClientSourceFormat;
    parameterDeclarations?: Record<string, unknown>;
  }>}> | Readonly<{kind: 'program'; input: object}>);
  'submit-intent': Omit<WireClientBodyByOperation['submit'], 'requestId'> & Readonly<{
    submissionRef: WireSubmissionRef; intentCid: string}>;
  'submit-named-intent': WireClientBodyByOperation['submit-intent'] & Readonly<{
    requestName: WireSubmissionName; attemptRef: WireOperationAttemptRef;
    stopBefore?: 'commit'; readOnly?: true}>;
  'restart-intent': WireClientBodyByOperation['submit-intent'] & Readonly<{
    unresolvedHistory: WireSubmissionRestart}>;
  'lookup-submission': WireBodyBase & Readonly<{submissionRef: WireSubmissionRef}>;
  'run-plan': WireClientBodyByOperation['inspect-run'];
  'inspect-run': WireRefBody & Readonly<{
    maxWireBytes: number;
    maxNodes: number;
    maxDepth: number;
  }>;
  plan: Omit<WireClientBodyByOperation['submit'], 'requestId' | 'parameters'> & Readonly<{
    parameters: Record<string, unknown> | null;
    maxWireBytes: number; maxNodes: number; maxDepth: number}>;
  check: WireBodyBase & (Readonly<{
    kind: 'text'; input: Readonly<{
      text: string;
      format: 'aql' | 'aql-text' | 'sql';
      parameterDeclarations?: Record<string, unknown>;
    }>;
  }> | Readonly<{kind: 'program'; input: Record<string, unknown>}>) &
    (Readonly<{scope: 'template_only'; parameters?: never}> |
      Readonly<{scope: 'bound_input'; parameters: Record<string, unknown> | null}>);
  attach: WireRefBody;
  'lookup-request': WireBodyBase & Readonly<{requestId: string}>;
  status: WireRefBody;
  'owner-observations': WireRefBody & Readonly<{
    cursors:readonly WireOwnerCursor[];maxEntries:number;maxWireBytes:number}>;
  wait: WireRefBody & Readonly<{until: string | null; since: number | null}>;
  cancel: WireRefBody & Readonly<{cancelId: string; expectedRevision: number; attemptRef: WireOperationAttemptRef}>;
  'lookup-cancellation': WireRefBody & Readonly<{cancelId: string; expectedRevision: number}>;
  reconcile: WireRefBody;
  'result-describe': WireRefBody & Readonly<{
    resultName: string; format: 'json' | 'jsonl' | 'csv'; attemptId: string;
    maxWireBytes: number; maxNodes: number; maxDepth: number}>;
  read: WireRefBody & Readonly<{
    resultName: string;
    format: 'json' | 'jsonl' | 'csv';
    attemptId: string;
  }>;
  'delivery-attempt': WireRefBody & Readonly<{
    resultName: string;
    attemptId: string;
  }>;
  checkpoints: WireBodyBase & Readonly<{after: string; limit: number; checkpointId?: string}>;
  'checkpoint-review': WireBodyBase & Readonly<{
    checkpointCid: string;
    maxBytes: number;
  }>;
  resolve: WireBodyBase & Readonly<{items: readonly WireResolveItem[]}>;
  'cancel-request': WireBodyBase & Readonly<{requestId: string}>;
  resources: WireBodyBase & Readonly<{
    resourceConnection: string;
    query: string;
    limit: number;
  }>;
  'resource-inspect': WireBodyBase & Readonly<{
    resourceConnection: string;
    resource: string;
    maxBytes: number;
  }>;
  'resource-peek': WireBodyBase & Readonly<{
    resourceConnection: string;
    resource: string;
    fields: readonly string[];
    maxRows: number;
    maxBytes: number;
  }>;
}>;

export type WireClientBody =
  WireClientBodyByOperation[ClientHostOperation];

export declare function validRunRef(value: unknown): value is WireRunRef;
export declare function validRunState(value: unknown): value is WireRunState;
export declare function validRunWaitContract(value: unknown, since: number | null): value is WireRunState;
export declare function validCheckOutcome(value: unknown):
  value is WireCheckOutcome;
export declare function validSubmitPreparationError(value: unknown):
  value is WireSubmitPreparationError;
export declare function validClientConnection(value: unknown):
  value is WireConnection;
/** Equality with a trusted Host binding only; grants no operation permission. */
export declare function clientWorkspaceMatches(connection: WireConnection,
  authenticatedWorkspaceId: string | undefined): boolean;
export declare function validClientBody<O extends ClientHostOperation>(
  operation: O, body: unknown): body is WireClientBodyByOperation[O];

type WireProfileSelection =
  | Readonly<{mode: 'local'; owner: 'local'}>
  | Readonly<{mode: 'remote'; owner: 'remote'}>
  | Readonly<{mode: 'hybrid'; owner: 'local' | 'cloud'}>;

export type WireClientProfile = WireProfileShape & WireProfileSelection;

export type WireClientAdmission = WireAdmissionShape;

export type WireHeldRequest = WireHeldShape;
export type WireRequestLookup =
  | WireLookupFoundShape | WireLookupNotFoundShape | WireLookupUnknownShape
  | WireHeldRequest;
export type WireSubmitReply = WireClientAdmission | WireHeldRequest;
export type WireCheckpointSummary = WireCheckpointSummaryShape;
export type WireCheckpointPage = Readonly<{
  items: readonly WireCheckpointSummary[];
  next?: string;
}>;
export type WireCheckpointReview = WireCheckpointReviewShape;
export type WireResolveItem = WireResolveItemShape;
export type WireResolveResult = WireResolveResultShape;

export declare const checkpointLimits: Readonly<{
  maxPageItems: number;
  maxCursorLength: number;
  maxReviewBytes: number;
  maxResolveItems: number;
}>;

export declare function validClientProfile(value: unknown,
  selected: WireConnection): value is WireClientProfile;
export declare function validClientAdmission(value: unknown,
  selected: WireConnection): value is WireClientAdmission;
export declare function validRequestLookup(value: unknown,
  expectedRequestId: string):
  value is WireRequestLookup;
export declare function validHeldRequest(value: unknown,
  expectedRequestId: string): value is WireHeldRequest;
export declare function validSubmitReply(value: unknown,
  selected: WireConnection, expectedRequestId: string):
  value is WireSubmitReply;
export declare function validCheckpointPage(value: unknown, limit: number):
  value is WireCheckpointPage;
export declare function validCheckpointLookup(value: unknown, checkpointId: string):
  value is WireCheckpointPage;
export declare function validCheckpointReview(value: unknown,
  expected: Readonly<{checkpointCid: string; maxBytes: number}>):
  value is WireCheckpointReview;
export declare function validResolveItem(value: unknown):
  value is WireResolveItem;
export declare function validResolveResults(value: unknown,
  items: readonly Readonly<{checkpointCid: string}>[]):
  value is Readonly<{results: readonly WireResolveResult[]}>;

import type {WireDeliveryAttempt, WireDeliveryRecord,
  WireHostReleaseReceipt} from './publication.generated.js';
export type {WireDeliveryAttempt, WireDeliveryRecord,
  WireHostReleaseReceipt} from './publication.generated.js';

export type WireDeliveryAttemptLookup =
  | Readonly<{kind: 'not_found'}>
  | Readonly<{kind: 'found'; attempt: WireDeliveryAttempt;
      record: WireDeliveryRecord | null;
      hostReleaseReceipt: WireHostReleaseReceipt | null}>;

export declare function validDeliveryAttemptLookup(value: unknown,
  expected: Readonly<{attemptId: string; runDefinitionCid: string;
    resultName: string}>): value is WireDeliveryAttemptLookup;

export type WireCancellation = WireCancellationShape;
export type WireCancellationRef = WireCancellationRefShape;
export type WireCancellationLookup = WireCancellationLookupShape;
export type WireOperationAttemptRef = WireOperationAttemptRefShape;
export type WireCancellationAttempt = WireCancellationAttemptShape;
export declare function validOperationAttemptRef(value: unknown): value is WireOperationAttemptRef;
export declare function validCancellationAttempt(value: unknown, expected: WireCancellationRef,
  attemptRef: WireOperationAttemptRef): value is WireCancellationAttempt;
export declare function validCancellationRef(value: unknown): value is WireCancellationRef;
export declare function validCancellation(value: unknown,
  expected?: WireCancellationRef): value is WireCancellation;
export declare function validCancellationLookup(value: unknown,
  expected: WireCancellationRef): value is WireCancellationLookup;

export type WireRequestCancellation = WireRequestCancellationShape;
export declare function validRequestCancellation(value: unknown,
  expectedRequestId: string): value is WireRequestCancellation;

export declare const resourceLimits: Readonly<{
  maxQueryLength: number;
  maxListItems: number;
  maxInspectBytes: number;
  maxPeekFields: number;
  maxPeekRows: number;
  maxPeekBytes: number;
}>;

export type WireResourceListing = WireResourceListingShape;
export declare function validResourceListing(value: unknown,
  expected: Readonly<{resourceConnection: string; limit: number}>):
  value is WireResourceListing;

export type WireResourceInspection = WireResourceInspectionShape;
export declare function validResourceInspection(value: unknown,
  expected: Readonly<{resourceConnection: string; resource: string;
    maxBytes: number}>): value is WireResourceInspection;

export type WireResourcePeek = WireResourcePeekShape;
export declare function validResourcePeek(value: unknown,
  expected: Readonly<{resourceConnection: string; resource: string;
    fields: readonly string[]; maxRows: number; maxBytes: number}>):
  value is WireResourcePeek;

/** Detach a JSON Client request; throws before lossy source-number conversion. */
export declare function snapshotClientRequest(value: unknown): unknown;
/** Existing check entry point into the same request snapshot owner. */
export declare function snapshotCheckRequest(value: unknown): unknown;
/** Synchronous Host admission; optional immutable capture for deferred ingress.
 * The result contains shape facts, never authentication or authorization. */
export declare function prepareClientHostRequest(operation: ClientHostOperation,
  value: unknown, retainSnapshot?: boolean): Readonly<{body: unknown; connection: WireConnection}> | undefined;
