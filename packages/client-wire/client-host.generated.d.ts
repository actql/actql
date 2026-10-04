// Generated from the registered Client–Host machine contract.
export type ClientHostOperation = "connect" | "submit" | "check" | "attach" | "lookup-request" | "status" | "wait" | "cancel" | "reconcile" | "read" | "result-describe" | "delivery-attempt" | "checkpoints" | "checkpoint-review" | "resolve" | "cancel-request" | "resources" | "resource-inspect" | "resource-peek";
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
  type: "artifact_ref";
  nullable: boolean;
  media_type?: string;
}>;
export type WireRunRefShape = Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;

export type WireConnectionShape = Readonly<{
  mode: "local" | "remote" | "hybrid";
  owner: "local" | "remote" | "cloud";
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
  code: "ClientProgramInvalidInput" | "ClientParametersInvalid" | "ClientParametersTooLarge" | "ClientProgramUnsupported" | "ClientProgramNeedsInputs" | "ClientProgramRejected";
}>;

export type WireCancellationShape = Readonly<{
  ref: Readonly<{
  namespaceId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  kind: "accepted" | "already_requested" | "already_terminal";
  revision: number;
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

export type WireRunStateShape = Readonly<{
  version: "actql-run-state/0.1";
  run_id: string;
  status: "preparing" | "running" | "waiting_checkpoint" | "resuming" | "needs_reconciliation" | "succeeded" | "failed" | "cancelled";
  updated_at: string;
  checkpoint?: Readonly<{
  checkpoint_id: string;
  checkpoint_cid: string;
  kind: "run_scope" | "read_access" | "data_egress" | "cost_scope" | "effect_set";
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
}>;
export type WireCheckOutcomeShape = Readonly<{
  outcome: "completed";
  report: Readonly<{
  context_ref: string;
  inputs: readonly Readonly<{
  document_id: "source" | "parameter_declarations" | "parameters";
  revision: string;
  kind: "text" | "structured";
  byte_length: number;
}>[];
  coverage: Readonly<{
  limits: readonly Readonly<{
  code: string;
}>[];
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
  document_id: "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
  facts?: Readonly<{
  parameter: string;
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
  actual_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
}> | Readonly<{
  parameter: string;
  constraint: "numeric" | "duration" | "array_length" | "array_size";
}>;
}>[];
  requirements: readonly Readonly<{
  code: "parameter_value_required";
  location?: Readonly<{
  kind: "text";
  document_id: "source";
  revision: string;
  start_byte: number;
  end_byte: number;
  precision: "exact" | "approximate";
}> | Readonly<{
  kind: "structured";
  document_id: "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
  facts: Readonly<{
  parameter: string;
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
  actual_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
}> | Readonly<{
  parameter: string;
  constraint: "numeric" | "duration" | "array_length" | "array_size";
}>;
}>[];
  scope: Readonly<{
  kind: "bound_input";
}>;
  verdict: "invalid" | "undetermined" | "verified";
}>;
  reason_schema_cid: "sha256:1565f0b7e8e32f70d97905797ccc37a872b08116c0ef3d9599e4e4509b568621";
  version: "actql-check-outcome/0.1";
}> | Readonly<{
  outcome: "failed";
  partial_report?: Readonly<{
  context_ref: string;
  inputs: readonly Readonly<{
  document_id: "source" | "parameter_declarations" | "parameters";
  revision: string;
  kind: "text" | "structured";
  byte_length: number;
}>[];
  coverage: Readonly<{
  limits: readonly Readonly<{
  code: string;
}>[];
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
  document_id: "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
  facts?: Readonly<{
  parameter: string;
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
  actual_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
}> | Readonly<{
  parameter: string;
  constraint: "numeric" | "duration" | "array_length" | "array_size";
}>;
}>[];
  requirements: readonly Readonly<{
  code: "parameter_value_required";
  location?: Readonly<{
  kind: "text";
  document_id: "source";
  revision: string;
  start_byte: number;
  end_byte: number;
  precision: "exact" | "approximate";
}> | Readonly<{
  kind: "structured";
  document_id: "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
  facts: Readonly<{
  parameter: string;
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
  actual_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
}> | Readonly<{
  parameter: string;
  expected_type: "null" | "boolean" | "number" | "string" | "array" | "object" | "date" | "timestamp" | "decimal" | "json" | "vector" | "resource_ref" | "artifact_ref";
}> | Readonly<{
  parameter: string;
  constraint: "numeric" | "duration" | "array_length" | "array_size";
}>;
}>[];
  scope: Readonly<{
  kind: "bound_input";
}>;
  verdict: "invalid" | "undetermined";
}>;
  problem: Readonly<{
  code: string;
}>;
  reason_schema_cid: "sha256:1565f0b7e8e32f70d97905797ccc37a872b08116c0ef3d9599e4e4509b568621";
  version: "actql-check-outcome/0.1";
}> | Readonly<{
  correlation_ref: string;
  outcome: "unavailable";
  problem: Readonly<{
  code: string;
}>;
  reason_schema_cid: "sha256:1565f0b7e8e32f70d97905797ccc37a872b08116c0ef3d9599e4e4509b568621";
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
  document_id: "parameter_declarations" | "parameters";
  revision: string;
  pointer: string;
}>;
