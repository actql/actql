// Generated from the registered Client–Host machine contract.
export declare const checkOutcomeProtocol: Readonly<{version: "actql-check-outcome/0.1"; reasonSchemaCid: string; outcomeSchemaCid: string; outcomes: readonly ("completed" | "failed" | "unavailable")[]}>;
export declare const runStateProtocol: Readonly<{version: "actql-run-state/0.1"; statuses: readonly ("preparing" | "running" | "waiting_checkpoint" | "resuming" | "needs_reconciliation" | "succeeded" | "failed" | "cancelled")[]}>;
export type ClientHostOperation = "connect" | "submit" | "submit-intent" | "submit-named-intent" | "restart-intent" | "lookup-submission" | "check" | "plan" | "inspect-run" | "attach" | "lookup-request" | "status" | "wait" | "cancel" | "lookup-cancellation" | "reconcile" | "read" | "result-describe" | "delivery-attempt" | "checkpoints" | "checkpoint-review" | "resolve" | "cancel-request" | "resources" | "resource-inspect" | "resource-peek" | "owner-observations" | "run-plan";
export type WireValueContractShape = Readonly<{
  type: "decimal";
  nullable: boolean;
  precision: number;
  scale: number;
}> | Readonly<{
  type: "string";
  nullable: boolean;
  min_length?: number;
  max_codepoints?: number;
  max_utf8_bytes?: number;
  enum?: readonly string[];
}> | Readonly<{
  type: "number" | "boolean" | "timestamp" | "date" | "json";
  nullable: boolean;
}> | Readonly<{
  type: "array";
  nullable: boolean;
  items: WireValueContractShape;
  max_items?: number;
}> | Readonly<{
  type: "object";
  nullable: boolean;
  additional_properties: false;
  fields: Readonly<Record<string, WireValueContractShape>>;
}> | Readonly<{
  type: "vector";
  nullable: boolean;
  dimensions: number;
  element_type: "f32";
}> | Readonly<{
  type: "resource_ref";
  nullable: boolean;
  resource_kind: string;
}> | Readonly<{
  type: "content_ref";
  nullable: boolean;
  media_type?: string;
}> | Readonly<{
  type: "int64";
  nullable: boolean;
}>;
export type WireSubmissionEpochShape = Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;

export type WireSubmissionRefShape = Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;

export type WireSubmissionOutcomeShape = Readonly<{
  kind: "ready";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  admission: Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  durability: "volatile" | "durable";
  revision: number;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "held";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  held: Readonly<{
  kind: "held";
  requestId: string;
  prepareAttemptId: string;
  state: "waiting_checkpoint" | "resuming" | "ended";
  durability: "durable";
  lookupExpiresAt: string;
  checkpoint?: Readonly<{
  checkpointId: string;
  checkpointCid: string;
  kind: "run_scope" | "read_access" | "data_egress" | "cost_scope" | "effect_set";
  expiresAt: string;
}>;
  endReason?: string;
  terminalErrorCode?: string;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "preparing";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "not_accepted";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  checkObservation?: (WireCheckOutcomeShape) & (Readonly<{
  report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
  partial_report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
}>);
  problem: Readonly<{
  code: string;
  classification: "invalid_input" | "requirements" | "implementation_limit" | "authorization" | "operation_failed";
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "preparation_failed";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  checkObservation?: (WireCheckOutcomeShape) & (Readonly<{
  report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
  partial_report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
}>);
  problem: Readonly<{
  code: string;
  classification: "invalid_input" | "requirements" | "implementation_limit" | "authorization" | "operation_failed";
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}>;

export type WireSubmissionLookupShape = Readonly<{
  kind: "ready";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  admission: Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  durability: "volatile" | "durable";
  revision: number;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "held";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  held: Readonly<{
  kind: "held";
  requestId: string;
  prepareAttemptId: string;
  state: "waiting_checkpoint" | "resuming" | "ended";
  durability: "durable";
  lookupExpiresAt: string;
  checkpoint?: Readonly<{
  checkpointId: string;
  checkpointCid: string;
  kind: "run_scope" | "read_access" | "data_egress" | "cost_scope" | "effect_set";
  expiresAt: string;
}>;
  endReason?: string;
  terminalErrorCode?: string;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "preparing";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "not_accepted";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  problem: Readonly<{
  code: string;
  classification: "invalid_input" | "requirements" | "implementation_limit" | "authorization" | "operation_failed";
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "preparation_failed";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  problem: Readonly<{
  code: string;
  classification: "invalid_input" | "requirements" | "implementation_limit" | "authorization" | "operation_failed";
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "unresolvable";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  problem: Readonly<{
  code: string;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}>;

export type WireSubmissionRestartShape = Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;

export type WireSubmissionAttemptShape = Readonly<{
  kind: "recorded" | "already_satisfied";
  attemptRef: Readonly<{
  operation: "submit";
  attemptId: string;
}>;
  outcome: Readonly<{
  kind: "ready";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  admission: Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  durability: "volatile" | "durable";
  revision: number;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "held";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  held: Readonly<{
  kind: "held";
  requestId: string;
  prepareAttemptId: string;
  state: "waiting_checkpoint" | "resuming" | "ended";
  durability: "durable";
  lookupExpiresAt: string;
  checkpoint?: Readonly<{
  checkpointId: string;
  checkpointCid: string;
  kind: "run_scope" | "read_access" | "data_egress" | "cost_scope" | "effect_set";
  expiresAt: string;
}>;
  endReason?: string;
  terminalErrorCode?: string;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "preparing";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "not_accepted";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  checkObservation?: (WireCheckOutcomeShape) & (Readonly<{
  report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
  partial_report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
}>);
  problem: Readonly<{
  code: string;
  classification: "invalid_input" | "requirements" | "implementation_limit" | "authorization" | "operation_failed";
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "preparation_failed";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  checkObservation?: (WireCheckOutcomeShape) & (Readonly<{
  report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
  partial_report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
}>);
  problem: Readonly<{
  code: string;
  classification: "invalid_input" | "requirements" | "implementation_limit" | "authorization" | "operation_failed";
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}>;
}> | Readonly<{
  kind: "refused";
  attemptRef: Readonly<{
  operation: "submit";
  attemptId: string;
}>;
  guarantee: "attempt_uncommitted_unconsumed";
  reason: "authorization";
}> | Readonly<{
  kind: "refused";
  attemptRef: Readonly<{
  operation: "submit";
  attemptId: string;
}>;
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  guarantee: "attempt_uncommitted_unconsumed";
  reason: "admission_capacity" | "epoch_expired" | "epoch_not_yet_valid";
}> | Readonly<{
  kind: "conflict";
  attemptRef: Readonly<{
  operation: "submit";
  attemptId: string;
}>;
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  reason: "intent" | "restart_decision";
}>;

export type WireSubmissionNameShape = string;

export type WireNamedSubmissionAttemptShape = Readonly<{
  kind: "observed";
  requestName: string;
  intentCid: string;
  attemptRef: Readonly<{
  operation: "submit";
  attemptId: string;
}>;
  outcome: Readonly<{
  kind: "ready";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  admission: Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  durability: "volatile" | "durable";
  revision: number;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "held";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  held: Readonly<{
  kind: "held";
  requestId: string;
  prepareAttemptId: string;
  state: "waiting_checkpoint" | "resuming" | "ended";
  durability: "durable";
  lookupExpiresAt: string;
  checkpoint?: Readonly<{
  checkpointId: string;
  checkpointCid: string;
  kind: "run_scope" | "read_access" | "data_egress" | "cost_scope" | "effect_set";
  expiresAt: string;
}>;
  endReason?: string;
  terminalErrorCode?: string;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "preparing";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "not_accepted";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  checkObservation?: (WireCheckOutcomeShape) & (Readonly<{
  report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
  partial_report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
}>);
  problem: Readonly<{
  code: string;
  classification: "invalid_input" | "requirements" | "implementation_limit" | "authorization" | "operation_failed";
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "preparation_failed";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  intentCid: string;
  checkObservation?: (WireCheckOutcomeShape) & (Readonly<{
  report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
  partial_report?: Readonly<{
  scope?: Readonly<{
  kind?: "bound_input";
}>;
}>;
}>);
  problem: Readonly<{
  code: string;
  classification: "invalid_input" | "requirements" | "implementation_limit" | "authorization" | "operation_failed";
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}> | Readonly<{
  kind: "unresolvable";
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  problem: Readonly<{
  code: string;
}>;
  unresolvedHistory?: Readonly<{
  submissionRef: Readonly<{
  epoch: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  nonce: string;
}>;
  acknowledgement: "possible_prior_execution_and_effects";
}>;
}>;
}> | Readonly<{
  kind: "refused";
  requestName: string;
  intentCid: string;
  attemptRef: Readonly<{
  operation: "submit";
  attemptId: string;
}>;
  guarantee: "attempt_uncommitted_unconsumed";
  reason: "authorization" | "admission_capacity" | "epoch_expired" | "epoch_not_yet_valid";
}> | Readonly<{
  kind: "conflict";
  requestName: string;
  intentCid: string;
  attemptRef: Readonly<{
  operation: "submit";
  attemptId: string;
}>;
  reason: "intent";
}>;

export type WireRunRefShape = Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;

export type WireConnectionShape = Readonly<{
  mode: "local" | "remote" | "hybrid";
  owner: "local" | "remote" | "cloud";
  workspaceId?: string;
  consentRefs: readonly string[];
  runners: readonly string[];
  durability?: "volatile" | "durable";
  movementPolicyRef?: string;
  cloudConnectionRef?: string;
}>;

export type WireProfileShape = Readonly<{
  version: "actql-client-host/0.1";
  mode: "local" | "remote" | "hybrid";
  owner: "local" | "remote" | "cloud";
  durability: "volatile" | "durable";
  submissionEpoch?: Readonly<{
  version: "actql-submission-epoch/0.1";
  authorityScopeCid: string;
  epochNonce: string;
  notBefore: number;
  expiresAt: number;
  authenticator: string;
}>;
  scopeRef: string;
  workspaceId?: string;
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

export type WireAdmissionShape = Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  durability: "volatile" | "durable";
  revision: number;
}>;

export type WireLookupFoundShape = Readonly<{
  kind: "found";
  requestId: string;
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  durability: "volatile" | "durable";
  lookupExpiresAt: string;
}>;

export type WireLookupNotFoundShape = Readonly<{
  kind: "not_found";
}>;

export type WireLookupUnknownShape = Readonly<{
  kind: "unknown";
  reason: string;
}>;

export type WireHeldShape = Readonly<{
  kind: "held";
  requestId: string;
  prepareAttemptId: string;
  state: "waiting_checkpoint" | "resuming" | "ended";
  durability: "durable";
  lookupExpiresAt: string;
  checkpoint?: Readonly<{
  checkpointId: string;
  checkpointCid: string;
  kind: "run_scope" | "read_access" | "data_egress" | "cost_scope" | "effect_set";
  expiresAt: string;
}>;
  endReason?: string;
  terminalErrorCode?: string;
}>;

export type WireCheckpointSummaryShape = Readonly<{
  checkpointId: string;
  checkpointCid: string;
  kind: "run_scope" | "read_access" | "data_egress" | "cost_scope" | "effect_set";
  phase: "preflight" | "commit";
  subject: Readonly<{
  kind: "prepare_attempt";
  prepareAttemptId: string;
  requestId: string;
}> | Readonly<{
  kind: "run_unit";
  runId: string;
  runDefinitionCid: string;
}>;
  requiredArtifact: Readonly<{
  type: string;
  cid: string;
}>;
  reviewProjectionCid: string;
  requirements: readonly string[];
  createdAt: string;
  expiresAt: string;
  humanSummary: string;
}> | Readonly<{
  checkpointId: string;
  checkpointCid: string;
  kind: "model_invocation";
  phase: "preflight";
  subject: Readonly<{
  kind: "run_unit";
  runId: string;
  runDefinitionCid: string;
}>;
  requiredArtifact: Readonly<{
  type: "model_invocation_scope";
  cid: string;
}>;
  reviewProjectionCid: string;
  requirements: readonly "invocation_scope_approved"[];
  createdAt: string;
  expiresAt: string;
  humanSummary: string;
  preparedInvocationCid: string;
}>;

export type WireCheckpointReviewShape = Readonly<{
  kind: "review";
  checkpointCid: string;
  artifactCid: string;
  byteLength: number;
  contentBase64: string;
}>;

export type WireResolveItemShape = Readonly<{
  checkpointCid: string;
  resolutionWire: string;
  approvalEvidenceWire: string;
}>;

export type WireResolveResultShape = Readonly<{
  checkpointCid: string;
  status: "committed" | "duplicate" | "conflicting" | "expired" | "cancelled" | "invalid";
  decision?: "approved" | "rejected";
  resolutionCid?: string;
  reason?: string;
}>;

export type WireSubmitPreparationErrorShape = Readonly<{
  code: "ClientProgramInvalidInput" | "ClientParametersInvalid" | "ClientParametersTooLarge" | "ClientProgramUnsupported" | "ClientProgramAnalysisLimit" | "ClientProgramImplementationLimit" | "ClientProgramNeedsInputs" | "ClientProgramRejected";
}>;

export type WireCancellationShape = Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  kind: "accepted" | "already_requested" | "already_terminal";
  revision: number;
  cancelRef: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
  cancelId: string;
  expectedRevision: number;
}>;
}>;

export type WireCancellationRefShape = Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
  cancelId: string;
  expectedRevision: number;
}>;

export type WireCancellationLookupShape = Readonly<{
  kind: "found";
  cancellation: Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  kind: "accepted" | "already_requested" | "already_terminal";
  revision: number;
  cancelRef: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
  cancelId: string;
  expectedRevision: number;
}>;
}>;
}> | Readonly<{
  kind: "unknown";
  cancelRef: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
  cancelId: string;
  expectedRevision: number;
}>;
}>;

export type WireOperationAttemptRefShape = Readonly<{
  operation: "submit" | "cancel";
  attemptId: string;
}>;

export type WireCancellationAttemptShape = Readonly<{
  kind: "accepted";
  attemptRef: Readonly<{
  operation: "cancel";
  attemptId: string;
}>;
  cancellation: Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  kind: "accepted";
  revision: number;
  cancelRef: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
  cancelId: string;
  expectedRevision: number;
}>;
}>;
}> | Readonly<{
  kind: "already_satisfied";
  attemptRef: Readonly<{
  operation: "cancel";
  attemptId: string;
}>;
  cancellation: Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  kind: "already_requested" | "already_terminal";
  revision: number;
  cancelRef: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
  cancelId: string;
  expectedRevision: number;
}>;
}>;
}> | Readonly<{
  kind: "refused";
  attemptRef: Readonly<{
  operation: "cancel";
  attemptId: string;
}>;
  guarantee: "attempt_uncommitted_unconsumed";
  reason: "authorization" | "admission_capacity";
  cancelRef?: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
  cancelId: string;
  expectedRevision: number;
}>;
}> | Readonly<{
  kind: "conflict";
  attemptRef: Readonly<{
  operation: "cancel";
  attemptId: string;
}>;
  reason: "intent" | "control_revision";
  cancelRef: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
  cancelId: string;
  expectedRevision: number;
}>;
}>;

export type WireRequestCancellationShape = Readonly<{
  requestId: string;
  kind: "accepted" | "already_requested" | "already_terminal";
  ref?: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  revision?: number;
}>;

export type WireResourceListingShape = Readonly<{
  resourceConnection: string;
  observationCid: string;
  resources: readonly Readonly<{
  name: string;
  outcome: string;
}>[];
  snapshotComplete: boolean;
  snapshotTruncated: boolean;
  resultTruncated: boolean;
}>;

export type WireResourceInspectionShape = Readonly<{
  resourceConnection: string;
  resource: string;
  observationCid: string;
  status: "ready" | "catalog_required";
  reason?: "listing_truncated" | "not_visible" | "not_observed" | "not_found" | "describe_unavailable";
  summaryJson?: string;
}>;

export type WireResourcePeekShape = Readonly<{
  resourceConnection: string;
  resource: string;
  observationCid: string;
  fields: readonly string[];
  rowsJson: string;
  limited: boolean;
}>;

export type WireResultDescriptionShape = Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  resultName: string;
  programDefinitionCid: string;
  resultDefinitionCid: string;
  resultArtifactCid: string;
  resultSchemaCid: string;
  columns: readonly Readonly<{
  name: string;
  contract: WireValueContractShape;
}>[];
  serialization: Readonly<{
  format: "json" | "jsonl" | "csv";
  version: "actql-json/0.1" | "actql-jsonl/0.1" | "actql-csv/0.1";
  contractCid: string;
}>;
}>;

export type WireOwnerRefShape = Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;

export type WireOwnerCursorShape = Readonly<{
  owner: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  value: string;
}>;

export type WireOwnerObservationsShape = Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  consistency: "non_atomic";
  ordering: "owner_local";
  owners: readonly (Readonly<{
  owner: "run" | "effect" | "publication" | "delivery" | "site";
  kind: "unavailable";
  problem?: Readonly<{
  kind: "acquisition_failed" | "limit_exceeded" | "history_unrecoverable" | "cursor_mismatch";
}>;
}> | Readonly<{
  owner: "run";
  ownerRef: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  kind: "observed";
  history: Readonly<{
  kind: "not_provided";
}> | Readonly<{
  kind: "retention_expired";
}> | Readonly<{
  kind: "history_unrecoverable";
}> | Readonly<{
  kind: "cursor_mismatch";
}> | Readonly<{
  kind: "cursor_expired";
}> | Readonly<{
  kind: "limit_exceeded";
}> | Readonly<{
  kind: "acquisition_failed";
}> | Readonly<{
  kind: "page";
  entries: readonly Readonly<{
  revision: number;
  entryCid: string;
  state: "prepared" | "dispatching" | "applied" | "accepted" | "failed" | "unknown";
}>[];
  cursor?: Readonly<{
  owner: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  value: string;
}>;
}>;
  snapshot: Readonly<{
  revision?: number;
  value: WireRunStateShape;
}>;
}> | Readonly<{
  owner: "run";
  ownerRef: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  kind: "observed";
  history: Readonly<{
  kind: "not_provided";
}> | Readonly<{
  kind: "retention_expired";
}> | Readonly<{
  kind: "history_unrecoverable";
}> | Readonly<{
  kind: "cursor_mismatch";
}> | Readonly<{
  kind: "cursor_expired";
}> | Readonly<{
  kind: "limit_exceeded";
}> | Readonly<{
  kind: "acquisition_failed";
}> | Readonly<{
  kind: "page";
  entries: readonly Readonly<{
  revision: number;
  entryCid: string;
  state: "prepared" | "dispatching" | "applied" | "accepted" | "failed" | "unknown";
}>[];
  cursor?: Readonly<{
  owner: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  value: string;
}>;
}>;
  snapshotProblem: Readonly<{
  kind: "limit_exceeded" | "acquisition_failed";
}>;
}> | Readonly<{
  owner: "effect";
  ownerRef: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  kind: "observed";
  history: Readonly<{
  kind: "not_provided";
}> | Readonly<{
  kind: "retention_expired";
}> | Readonly<{
  kind: "history_unrecoverable";
}> | Readonly<{
  kind: "cursor_mismatch";
}> | Readonly<{
  kind: "cursor_expired";
}> | Readonly<{
  kind: "limit_exceeded";
}> | Readonly<{
  kind: "acquisition_failed";
}> | Readonly<{
  kind: "page";
  entries: readonly Readonly<{
  revision: number;
  entryCid: string;
  state: "prepared" | "dispatching" | "applied" | "accepted" | "failed" | "unknown";
}>[];
  cursor?: Readonly<{
  owner: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  value: string;
}>;
}>;
  snapshot: Readonly<{
  revision?: number;
  value: Readonly<{
  state: "prepared" | "dispatching" | "applied" | "accepted" | "failed" | "unknown";
}>;
}>;
}> | Readonly<{
  owner: "effect";
  ownerRef: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  kind: "observed";
  history: Readonly<{
  kind: "not_provided";
}> | Readonly<{
  kind: "retention_expired";
}> | Readonly<{
  kind: "history_unrecoverable";
}> | Readonly<{
  kind: "cursor_mismatch";
}> | Readonly<{
  kind: "cursor_expired";
}> | Readonly<{
  kind: "limit_exceeded";
}> | Readonly<{
  kind: "acquisition_failed";
}> | Readonly<{
  kind: "page";
  entries: readonly Readonly<{
  revision: number;
  entryCid: string;
  state: "prepared" | "dispatching" | "applied" | "accepted" | "failed" | "unknown";
}>[];
  cursor?: Readonly<{
  owner: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  value: string;
}>;
}>;
  snapshotProblem: Readonly<{
  kind: "limit_exceeded" | "acquisition_failed";
}>;
}>)[];
  revisionVector: readonly Readonly<{
  owner: Readonly<{
  kind: "run" | "effect" | "publication" | "delivery" | "site";
  scopeCid: string;
  streamCid: string;
}>;
  snapshotCid?: string;
  historyHead?: null | Readonly<{
  generation: string;
  revision: number;
  entryCid: string;
}>;
}>[];
  unmatchedCursors?: readonly Readonly<{
  index: number;
  kind: "unavailable";
}>[];
}>;

export type WireRunStateShape = Readonly<{
  version: "actql-run-state/0.1";
  run_id: string;
  status: "preparing" | "running" | "waiting_checkpoint" | "resuming" | "needs_reconciliation" | "succeeded" | "failed" | "cancelled";
  updated_at: string;
  checkpoint?: Readonly<{
  checkpoint_id: string;
  checkpoint_cid: string;
  kind: "run_scope" | "read_access" | "data_egress" | "cost_scope" | "effect_set" | "model_invocation";
}>;
  next_action: Readonly<{
  kind: "resolve_checkpoint";
  checkpoint_id: string;
}> | Readonly<{
  kind: "reconcile";
  effects: readonly string[];
}> | Readonly<{
  kind: "read_result";
  results: readonly string[];
}> | Readonly<{
  kind: "refresh_availability";
  results: readonly string[];
}> | Readonly<{
  kind: "none";
}> | Readonly<{
  kind: "reconcile_run";
  reason: "execution_unknown";
}>;
  result_available: boolean;
  terminal_error?: Readonly<{
  code: string;
  message: string;
}>;
  result_availability: Readonly<Record<string, Readonly<{
  state: "available" | "unavailable" | "unknown";
  observed_at: string;
  reason: "confirmed_present" | "retention_expired" | "deleted" | "policy_unavailable" | "integrity_failed" | "not_published" | "store_query_failed" | "clock_uncertain" | "verification_pending";
  cause_cid?: string;
}>>>;
  control?: Readonly<{
  revision: number;
  cancellation_requested: boolean;
  physical_stop: "unknown" | "confirmed";
}>;
  revision: number;
}>;
export type WireCheckOutcomeShape = Readonly<{
  outcome: "completed";
  report: Readonly<{
  runnable: Readonly<{
  verdict: "yes" | "no";
  reasons: readonly Readonly<{
  code: string;
}>[];
}>;
  context_ref: string;
  omissions?: Readonly<{
  requirements: true;
}>;
  inputs: readonly Readonly<{
  document_id: "source" | "program" | "parameter_declarations" | "parameters";
  revision: string;
  kind: "text" | "structured";
  byte_length: number;
}>[];
  coverage: Readonly<{
  limits: readonly (Readonly<{
  code: string;
}> | Readonly<{
  code: "implementation_limit" | "analysis_budget_exhausted";
  location: Readonly<{
  kind: "structured";
  document_id: "program";
  revision: string;
  pointer: string;
}>;
}> | Readonly<{
  code: "implementation_limit";
  facts: Readonly<{
  issue: "function_lowering_unresolved";
}>;
  location?: Readonly<{
  kind: "text";
  document_id: "source";
  revision: string;
  start_byte: number;
  end_byte: number;
  precision: "exact" | "approximate";
}>;
}>)[];
  unresolved: readonly Readonly<{
  boundary: string;
  reason: "unresolved_protected";
}>[];
}>;
  reasons: readonly Readonly<{
  code: string;
  location?: Readonly<{
  kind: "text";
  document_id: "source";
  revision: string;
  start_byte: number;
  end_byte: number;
  precision: "exact" | "approximate";
}> | Readonly<{
  kind: "structured";
  document_id: "program" | "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
  fixes?: readonly Readonly<{
  code: "close_block_comment";
  applicability: "requires_review";
  risk: "syntax_structure";
  target: Readonly<{
  document_id: "source";
  revision: string;
}>;
  edits: readonly Readonly<{
  start_byte: number;
  end_byte: number;
  replacement: "*/";
}>[];
}>[];
  facts?: Readonly<{
  parameter: string;
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
  actual_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
  admission?: Readonly<{
  contract_schema_cid: "sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1";
  kind: "parameter_declaration";
  contract: WireValueContractShape;
  supplier: "caller";
  constraints: readonly (Readonly<{
  kind: "numeric";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
  integer: boolean;
  minimum?: number;
  maximum?: number;
}> | Readonly<{
  kind: "duration";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
}> | Readonly<{
  kind: "array_length";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
  length: number;
}>)[];
}>;
}> | Readonly<{
  parameter: string;
  constraint: "numeric" | "duration" | "array_length" | "array_size";
}> | Readonly<{
  expected_type: "number" | "boolean" | "string";
}> | Readonly<{
  parameter: string;
  domain: "positive_safe_integer" | "nonnegative_safe_integer" | "unit_fraction" | "finite_number" | "duration" | "positive_milliseconds" | "signed_milliseconds" | "timestamp";
}> | Readonly<{
  operation: "components";
  issue: "invalid_kind" | "invalid_output_rows";
}> | Readonly<{
  operation: "subgraph";
  issue: "invalid_node_selector";
}> | Readonly<{
  document: "parameters" | "parameter_declarations";
  issue: "invalid_unicode" | "unexpected_end" | "unexpected_token" | "invalid_string" | "invalid_escape" | "invalid_number" | "number_out_of_range" | "negative_zero" | "expected_colon" | "expected_array_separator" | "expected_object_separator" | "duplicate_key" | "trailing_content";
}> | Readonly<{
  issue: "unexpected_end" | "unexpected_token" | "invalid_escape" | "invalid_scalar" | "empty_identifier" | "unterminated_comment" | "invalid_number" | "invalid_parameter" | "unknown_reference" | "invalid_arguments" | "expected_boolean" | "invalid_bounds" | "function_lowering_unresolved" | "missing_field" | "wrong_type" | "unexpected_null" | "invalid_structure";
}> | Readonly<{
  contract_cid: "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9";
  schema_cid: "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265";
  schema_pointer: "/schema";
  supplier: "checking_context_owner";
  stage: "checking";
}> | Readonly<{
  profile_cid: "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df";
  supplier: "checking_context_owner";
  stage: "checking";
}> | Readonly<{
  namespace: string;
  connector: string;
  resource: string;
  view?: string;
}> | Readonly<{
  namespace: string;
  reference: readonly Readonly<{
  value: string;
  quoted: boolean;
}>[];
}> | Readonly<{
  argument: "count" | "offset";
  constraint: "safe_integer";
  expected_type: "number" | "int64";
  maximum: 9007199254740991;
  minimum: 0 | 1;
  operation: "take";
  parameter: string;
  stage: "binding";
}> | Readonly<{
  domain: "key_comparable_operands" | "matching_numeric_domains";
}> | Readonly<{
  expected_carrier: "relation" | "vectors";
  actual_carrier: "relation" | "graph" | "events" | "vectors";
}>;
}>[];
  requirements: readonly Readonly<{
  code: "parameter_value_required" | "parameter_consumer_condition" | "host_capacity_policy_required" | "numeric_reduction_profile_required";
  location?: Readonly<{
  kind: "text";
  document_id: "source";
  revision: string;
  start_byte: number;
  end_byte: number;
  precision: "exact" | "approximate";
}> | Readonly<{
  kind: "structured";
  document_id: "program" | "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
  fixes?: readonly Readonly<{
  code: "close_block_comment";
  applicability: "requires_review";
  risk: "syntax_structure";
  target: Readonly<{
  document_id: "source";
  revision: string;
}>;
  edits: readonly Readonly<{
  start_byte: number;
  end_byte: number;
  replacement: "*/";
}>[];
}>[];
  facts: Readonly<{
  parameter: string;
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
  actual_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
  admission?: Readonly<{
  contract_schema_cid: "sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1";
  kind: "parameter_declaration";
  contract: WireValueContractShape;
  supplier: "caller";
  constraints: readonly (Readonly<{
  kind: "numeric";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
  integer: boolean;
  minimum?: number;
  maximum?: number;
}> | Readonly<{
  kind: "duration";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
}> | Readonly<{
  kind: "array_length";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
  length: number;
}>)[];
}>;
}> | Readonly<{
  parameter: string;
  constraint: "numeric" | "duration" | "array_length" | "array_size";
}> | Readonly<{
  expected_type: "number" | "boolean" | "string";
}> | Readonly<{
  parameter: string;
  domain: "positive_safe_integer" | "nonnegative_safe_integer" | "unit_fraction" | "finite_number" | "duration" | "positive_milliseconds" | "signed_milliseconds" | "timestamp";
}> | Readonly<{
  operation: "components";
  issue: "invalid_kind" | "invalid_output_rows";
}> | Readonly<{
  operation: "subgraph";
  issue: "invalid_node_selector";
}> | Readonly<{
  document: "parameters" | "parameter_declarations";
  issue: "invalid_unicode" | "unexpected_end" | "unexpected_token" | "invalid_string" | "invalid_escape" | "invalid_number" | "number_out_of_range" | "negative_zero" | "expected_colon" | "expected_array_separator" | "expected_object_separator" | "duplicate_key" | "trailing_content";
}> | Readonly<{
  issue: "unexpected_end" | "unexpected_token" | "invalid_escape" | "invalid_scalar" | "empty_identifier" | "unterminated_comment" | "invalid_number" | "invalid_parameter" | "unknown_reference" | "invalid_arguments" | "expected_boolean" | "invalid_bounds" | "function_lowering_unresolved" | "missing_field" | "wrong_type" | "unexpected_null" | "invalid_structure";
}> | Readonly<{
  contract_cid: "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9";
  schema_cid: "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265";
  schema_pointer: "/schema";
  supplier: "checking_context_owner";
  stage: "checking";
}> | Readonly<{
  profile_cid: "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df";
  supplier: "checking_context_owner";
  stage: "checking";
}> | Readonly<{
  namespace: string;
  connector: string;
  resource: string;
  view?: string;
}> | Readonly<{
  namespace: string;
  reference: readonly Readonly<{
  value: string;
  quoted: boolean;
}>[];
}> | Readonly<{
  argument: "count" | "offset";
  constraint: "safe_integer";
  expected_type: "number" | "int64";
  maximum: 9007199254740991;
  minimum: 0 | 1;
  operation: "take";
  parameter: string;
  stage: "binding";
}> | Readonly<{
  domain: "key_comparable_operands" | "matching_numeric_domains";
}> | Readonly<{
  expected_carrier: "relation" | "vectors";
  actual_carrier: "relation" | "graph" | "events" | "vectors";
}>;
}>[];
  scope: Readonly<{
  kind: "template_only" | "bound_input";
}>;
  verdict: "invalid" | "undetermined" | "verified";
}>;
  outcome_schema_cid: string;
  reason_schema_cid: "sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511";
  version: "actql-check-outcome/0.1";
}> | Readonly<{
  outcome: "failed";
  partial_report?: Readonly<{
  runnable: Readonly<{
  verdict: "yes" | "no";
  reasons: readonly Readonly<{
  code: string;
}>[];
}>;
  context_ref: string;
  omissions?: Readonly<{
  requirements: true;
}>;
  inputs: readonly Readonly<{
  document_id: "source" | "program" | "parameter_declarations" | "parameters";
  revision: string;
  kind: "text" | "structured";
  byte_length: number;
}>[];
  coverage: Readonly<{
  limits: readonly (Readonly<{
  code: string;
}> | Readonly<{
  code: "implementation_limit" | "analysis_budget_exhausted";
  location: Readonly<{
  kind: "structured";
  document_id: "program";
  revision: string;
  pointer: string;
}>;
}> | Readonly<{
  code: "implementation_limit";
  facts: Readonly<{
  issue: "function_lowering_unresolved";
}>;
  location?: Readonly<{
  kind: "text";
  document_id: "source";
  revision: string;
  start_byte: number;
  end_byte: number;
  precision: "exact" | "approximate";
}>;
}>)[];
  unresolved: readonly Readonly<{
  boundary: string;
  reason: "unresolved_protected";
}>[];
}>;
  reasons: readonly Readonly<{
  code: string;
  location?: Readonly<{
  kind: "text";
  document_id: "source";
  revision: string;
  start_byte: number;
  end_byte: number;
  precision: "exact" | "approximate";
}> | Readonly<{
  kind: "structured";
  document_id: "program" | "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
  fixes?: readonly Readonly<{
  code: "close_block_comment";
  applicability: "requires_review";
  risk: "syntax_structure";
  target: Readonly<{
  document_id: "source";
  revision: string;
}>;
  edits: readonly Readonly<{
  start_byte: number;
  end_byte: number;
  replacement: "*/";
}>[];
}>[];
  facts?: Readonly<{
  parameter: string;
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
  actual_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
  admission?: Readonly<{
  contract_schema_cid: "sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1";
  kind: "parameter_declaration";
  contract: WireValueContractShape;
  supplier: "caller";
  constraints: readonly (Readonly<{
  kind: "numeric";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
  integer: boolean;
  minimum?: number;
  maximum?: number;
}> | Readonly<{
  kind: "duration";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
}> | Readonly<{
  kind: "array_length";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
  length: number;
}>)[];
}>;
}> | Readonly<{
  parameter: string;
  constraint: "numeric" | "duration" | "array_length" | "array_size";
}> | Readonly<{
  expected_type: "number" | "boolean" | "string";
}> | Readonly<{
  parameter: string;
  domain: "positive_safe_integer" | "nonnegative_safe_integer" | "unit_fraction" | "finite_number" | "duration" | "positive_milliseconds" | "signed_milliseconds" | "timestamp";
}> | Readonly<{
  operation: "components";
  issue: "invalid_kind" | "invalid_output_rows";
}> | Readonly<{
  operation: "subgraph";
  issue: "invalid_node_selector";
}> | Readonly<{
  document: "parameters" | "parameter_declarations";
  issue: "invalid_unicode" | "unexpected_end" | "unexpected_token" | "invalid_string" | "invalid_escape" | "invalid_number" | "number_out_of_range" | "negative_zero" | "expected_colon" | "expected_array_separator" | "expected_object_separator" | "duplicate_key" | "trailing_content";
}> | Readonly<{
  issue: "unexpected_end" | "unexpected_token" | "invalid_escape" | "invalid_scalar" | "empty_identifier" | "unterminated_comment" | "invalid_number" | "invalid_parameter" | "unknown_reference" | "invalid_arguments" | "expected_boolean" | "invalid_bounds" | "function_lowering_unresolved" | "missing_field" | "wrong_type" | "unexpected_null" | "invalid_structure";
}> | Readonly<{
  contract_cid: "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9";
  schema_cid: "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265";
  schema_pointer: "/schema";
  supplier: "checking_context_owner";
  stage: "checking";
}> | Readonly<{
  profile_cid: "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df";
  supplier: "checking_context_owner";
  stage: "checking";
}> | Readonly<{
  namespace: string;
  connector: string;
  resource: string;
  view?: string;
}> | Readonly<{
  namespace: string;
  reference: readonly Readonly<{
  value: string;
  quoted: boolean;
}>[];
}> | Readonly<{
  argument: "count" | "offset";
  constraint: "safe_integer";
  expected_type: "number" | "int64";
  maximum: 9007199254740991;
  minimum: 0 | 1;
  operation: "take";
  parameter: string;
  stage: "binding";
}> | Readonly<{
  domain: "key_comparable_operands" | "matching_numeric_domains";
}> | Readonly<{
  expected_carrier: "relation" | "vectors";
  actual_carrier: "relation" | "graph" | "events" | "vectors";
}>;
}>[];
  requirements: readonly Readonly<{
  code: "parameter_value_required" | "parameter_consumer_condition" | "host_capacity_policy_required" | "numeric_reduction_profile_required";
  location?: Readonly<{
  kind: "text";
  document_id: "source";
  revision: string;
  start_byte: number;
  end_byte: number;
  precision: "exact" | "approximate";
}> | Readonly<{
  kind: "structured";
  document_id: "program" | "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
  fixes?: readonly Readonly<{
  code: "close_block_comment";
  applicability: "requires_review";
  risk: "syntax_structure";
  target: Readonly<{
  document_id: "source";
  revision: string;
}>;
  edits: readonly Readonly<{
  start_byte: number;
  end_byte: number;
  replacement: "*/";
}>[];
}>[];
  facts: Readonly<{
  parameter: string;
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
  actual_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "content_ref" | "int64";
  admission?: Readonly<{
  contract_schema_cid: "sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1";
  kind: "parameter_declaration";
  contract: WireValueContractShape;
  supplier: "caller";
  constraints: readonly (Readonly<{
  kind: "numeric";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
  integer: boolean;
  minimum?: number;
  maximum?: number;
}> | Readonly<{
  kind: "duration";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
}> | Readonly<{
  kind: "array_length";
  path: readonly (Readonly<{
  kind: "field";
  name: string;
}> | Readonly<{
  kind: "items";
}>)[];
  length: number;
}>)[];
}>;
}> | Readonly<{
  parameter: string;
  constraint: "numeric" | "duration" | "array_length" | "array_size";
}> | Readonly<{
  expected_type: "number" | "boolean" | "string";
}> | Readonly<{
  parameter: string;
  domain: "positive_safe_integer" | "nonnegative_safe_integer" | "unit_fraction" | "finite_number" | "duration" | "positive_milliseconds" | "signed_milliseconds" | "timestamp";
}> | Readonly<{
  operation: "components";
  issue: "invalid_kind" | "invalid_output_rows";
}> | Readonly<{
  operation: "subgraph";
  issue: "invalid_node_selector";
}> | Readonly<{
  document: "parameters" | "parameter_declarations";
  issue: "invalid_unicode" | "unexpected_end" | "unexpected_token" | "invalid_string" | "invalid_escape" | "invalid_number" | "number_out_of_range" | "negative_zero" | "expected_colon" | "expected_array_separator" | "expected_object_separator" | "duplicate_key" | "trailing_content";
}> | Readonly<{
  issue: "unexpected_end" | "unexpected_token" | "invalid_escape" | "invalid_scalar" | "empty_identifier" | "unterminated_comment" | "invalid_number" | "invalid_parameter" | "unknown_reference" | "invalid_arguments" | "expected_boolean" | "invalid_bounds" | "function_lowering_unresolved" | "missing_field" | "wrong_type" | "unexpected_null" | "invalid_structure";
}> | Readonly<{
  contract_cid: "sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9";
  schema_cid: "sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265";
  schema_pointer: "/schema";
  supplier: "checking_context_owner";
  stage: "checking";
}> | Readonly<{
  profile_cid: "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df";
  supplier: "checking_context_owner";
  stage: "checking";
}> | Readonly<{
  namespace: string;
  connector: string;
  resource: string;
  view?: string;
}> | Readonly<{
  namespace: string;
  reference: readonly Readonly<{
  value: string;
  quoted: boolean;
}>[];
}> | Readonly<{
  argument: "count" | "offset";
  constraint: "safe_integer";
  expected_type: "number" | "int64";
  maximum: 9007199254740991;
  minimum: 0 | 1;
  operation: "take";
  parameter: string;
  stage: "binding";
}> | Readonly<{
  domain: "key_comparable_operands" | "matching_numeric_domains";
}> | Readonly<{
  expected_carrier: "relation" | "vectors";
  actual_carrier: "relation" | "graph" | "events" | "vectors";
}>;
}>[];
  scope: Readonly<{
  kind: "template_only" | "bound_input";
}>;
  verdict: "invalid" | "undetermined";
}>;
  problem: Readonly<{
  code: string;
}>;
  correlation_ref: string;
  outcome_schema_cid: string;
  reason_schema_cid: "sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511";
  version: "actql-check-outcome/0.1";
}> | Readonly<{
  correlation_ref: string;
  outcome: "unavailable";
  problem: Readonly<{
  code: string;
}>;
  outcome_schema_cid: string;
  reason_schema_cid: "sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511";
  version: "actql-check-outcome/0.1";
}>;
export type WireCheckLocationShape = Readonly<{
  kind: "text";
  document_id: "source";
  revision: string;
  start_byte: number;
  end_byte: number;
  precision: "exact" | "approximate";
}> | Readonly<{
  kind: "structured";
  document_id: "program" | "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
export type WireCheckFixShape = Readonly<{
  code: "close_block_comment";
  applicability: "requires_review";
  risk: "syntax_structure";
  target: Readonly<{
  document_id: "source";
  revision: string;
}>;
  edits: readonly Readonly<{
  start_byte: number;
  end_byte: number;
  replacement: "*/";
}>[];
}>;
