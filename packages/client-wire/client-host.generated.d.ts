// Generated from the registered Client–Host machine contract.
export type ClientHostOperation = "connect" | "submit" | "attach" | "lookup-request" | "status" | "wait" | "cancel" | "reconcile" | "read" | "delivery-attempt";
export type WireRunRefShape = Readonly<{
  tenantId: string;
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
  tenantId: string;
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
  tenantId: string;
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

export type WireSubmitPreparationErrorShape = Readonly<{
  code: "ClientProgramInvalidInput" | "ClientParametersInvalid" | "ClientParametersTooLarge" | "ClientProgramUnsupported" | "ClientProgramNeedsInputs" | "ClientProgramRejected";
}>;

export type WireCancellationShape = Readonly<{
  ref: Readonly<{
  tenantId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;
  kind: "accepted" | "already_requested" | "already_terminal";
  revision: number;
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
