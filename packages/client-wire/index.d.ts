import type {ClientHostOperation, WireAdmissionShape, WireCancellationShape,
  WireCheckpointReviewShape, WireCheckpointSummaryShape,
  WireConnectionShape, WireHeldShape, WireLookupFoundShape,
  WireLookupNotFoundShape, WireLookupUnknownShape, WireProfileShape,
  WireRequestCancellationShape, WireResourceInspectionShape,
  WireResourceListingShape, WireResourcePeekShape,
  WireResolveItemShape, WireResolveResultShape, WireRunRefShape,
  WireRunStateShape, WireSubmitPreparationErrorShape} from
  './client-host.generated.js';
export type {ClientHostOperation} from './client-host.generated.js';

export declare const clientHostOperations: readonly ClientHostOperation[];

type WireConnectionBase = Pick<WireConnectionShape,
  'durability' | 'consentRefs' | 'runners'>;

export type WireConnection =
  | (WireConnectionBase & Readonly<{mode: 'local'; owner: 'local';
      movementPolicyRef?: never; cloudConnectionRef?: never}>)
  | (WireConnectionBase & Readonly<{mode: 'remote'; owner: 'remote';
      movementPolicyRef?: never; cloudConnectionRef?: never}>)
  | (WireConnectionBase & Readonly<{mode: 'hybrid'; owner: 'local';
      movementPolicyRef: string; cloudConnectionRef: string}>)
  | (WireConnectionBase & Readonly<{mode: 'hybrid'; owner: 'cloud';
      movementPolicyRef: string; cloudConnectionRef?: never}>);

export type WireRunRef = WireRunRefShape;
export type WireRunState = WireRunStateShape;
export type WireSubmitPreparationError = WireSubmitPreparationErrorShape;

type WireBodyBase = Readonly<{connection: WireConnection}>;
type WireRefBody = WireBodyBase & Readonly<{ref: WireRunRef}>;

export type WireClientBodyByOperation = Readonly<{
  connect: WireBodyBase;
  submit: WireBodyBase & Readonly<{
    requestId: string;
    parameters: unknown;
  }> & (Readonly<{kind: 'aql'; input: Readonly<{
    text: string;
    format: 'json' | 'yaml';
  }>}> | Readonly<{kind: 'program'; input: object}>);
  attach: WireRefBody;
  'lookup-request': WireBodyBase & Readonly<{requestId: string}>;
  status: WireRefBody;
  wait: WireRefBody & Readonly<{until: string | null}>;
  cancel: WireRefBody;
  reconcile: WireRefBody;
  read: WireRefBody & Readonly<{
    resultName: string;
    format: 'json' | 'jsonl' | 'csv';
    attemptId: string;
  }>;
  'delivery-attempt': WireRefBody & Readonly<{
    resultName: string;
    attemptId: string;
  }>;
  checkpoints: WireBodyBase & Readonly<{after: string; limit: number}>;
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
export declare function validSubmitPreparationError(value: unknown):
  value is WireSubmitPreparationError;
export declare function validClientConnection(value: unknown):
  value is WireConnection;
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
export declare function validCancellation(value: unknown): value is WireCancellation;

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
