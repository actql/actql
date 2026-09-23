export type ClientHostOperation =
  | 'connect' | 'submit' | 'attach' | 'lookup-request' | 'status'
  | 'wait' | 'cancel' | 'reconcile' | 'read' | 'delivery-attempt';

export declare const clientHostOperations: readonly ClientHostOperation[];

type WireConnectionBase = Readonly<{
  durability?: 'volatile' | 'durable';
  consentRefs: readonly string[];
  runners: readonly string[];
}>;

export type WireConnection =
  | (WireConnectionBase & Readonly<{mode: 'local'; owner: 'local';
      movementPolicyRef?: never; cloudConnectionRef?: never}>)
  | (WireConnectionBase & Readonly<{mode: 'remote'; owner: 'remote';
      movementPolicyRef?: never; cloudConnectionRef?: never}>)
  | (WireConnectionBase & Readonly<{mode: 'hybrid'; owner: 'local';
      movementPolicyRef: string; cloudConnectionRef: string}>)
  | (WireConnectionBase & Readonly<{mode: 'hybrid'; owner: 'cloud';
      movementPolicyRef: string; cloudConnectionRef?: never}>);

export type WireRunRef = Readonly<{
  tenantId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;

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
}>;

export type WireClientBody =
  WireClientBodyByOperation[ClientHostOperation];

export declare function validRunRef(value: unknown): value is WireRunRef;
export declare function validClientConnection(value: unknown):
  value is WireConnection;
export declare function validClientBody<O extends ClientHostOperation>(
  operation: O, body: unknown): body is WireClientBodyByOperation[O];

type WireProfileSelection =
  | Readonly<{mode: 'local'; owner: 'local'}>
  | Readonly<{mode: 'remote'; owner: 'remote'}>
  | Readonly<{mode: 'hybrid'; owner: 'local' | 'cloud'}>;

export type WireClientProfile = WireProfileSelection & Readonly<{
  version: 'actql-client-host/0.1';
  durability: 'volatile' | 'durable';
  scopeRef: string;
  capabilities: readonly string[];
  limits: Readonly<{
    maxReadWireBytes: number;
    maxRowWireBytes: number;
    maxRowRetainedValueBytes: number;
    maxRetainedValueBytes: number;
    maxRows: number;
    maxBatchRows: number;
    maxBatchRetainedValueBytes: number;
  }>;
}>;

export type WireClientAdmission = Readonly<{
  ref: WireRunRef;
  durability: 'volatile' | 'durable';
  revision: number;
}>;

export type WireRequestLookup =
  | Readonly<{kind: 'found'; requestId: string; ref: WireRunRef;
      durability: 'volatile' | 'durable'; lookupExpiresAt: string}>
  | Readonly<{kind: 'not_found'}>
  | Readonly<{kind: 'unknown'; reason: string}>;

export declare function validClientProfile(value: unknown,
  selected: WireConnection): value is WireClientProfile;
export declare function validClientAdmission(value: unknown,
  selected: WireConnection): value is WireClientAdmission;
export declare function validRequestLookup(value: unknown,
  expectedRequestId: string):
  value is WireRequestLookup;

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
