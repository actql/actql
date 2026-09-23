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
