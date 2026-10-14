/** Exact identity syntax is checked by the original runtime, not this type. */
export type Sha256Cid = `sha256:${string}`;
export type ProjectionLimits = Readonly<{
  maxBytes: number; maxNodes: number; maxDepth: number;
  maxFrames: number; maxWork: number;
}>;
export type RequestLimits = Readonly<{
  maxBytes: number; maxHeaderBytes: number; maxHeaders: number;
}>;
export type ResponseLimits = Readonly<{
  maxBytes: number; maxChunkBytes: number; maxChunks: number;
  maxHeaderBytes: number; observedHeaders?: readonly string[];
}>;
/** Borrowed existing Host selections. These DATA types issue no grants. */
export type QuantityCapacity = Readonly<{
  limits: Readonly<{tokens: bigint; costUnits: bigint; durationMs: bigint}>;
  perAttempt: Readonly<{tokens: bigint; costUnits: bigint; durationMs: bigint}>;
}>;
/** The installed Host supplies its actual consuming runtime, not the user. */
export type ModelProviderRegistration =
  (runtime: unknown) => readonly Readonly<Record<string, unknown>>[];
/** Original canonical bytes and claimed identity, admitted by Common only. */
export type OriginalBody = Readonly<{wire: string; cid: Sha256Cid}>;
/** Closed generation installation DATA. It is not a physical support grant. */
export type OpenAIInstallationData = Readonly<{
  builder_id: string; builder_revision: string; codec_id: string; codec_revision: string;
  build_artifact_cid: Sha256Cid;
  sdk: Readonly<{package_name: '@ai-sdk/openai'; version: '4.0.91'; interface: 'v4'; lock_artifact_cid: Sha256Cid}>;
  endpoint: string; http_method: 'POST'; streaming: false;
  validator_id: string; validator_revision: string; validator_artifact_cid: Sha256Cid;
  completion_basis: 'generation_finish';
}>;
/** Finite Host-selected read declarations, not physical adequacy or loans. */
export type OriginalReadInstallationData = Readonly<{
  bootstrap: Readonly<{bootstrapRetainedBytes: bigint; bootstrapExecutionBytes: bigint;
    maxReservations: number; maxHoldings: number; maxDelegations: number}>;
  modelRetainedBytes: bigint; modelExecutionBytes: bigint;
  nodeInstallation: Readonly<{runtimeArtifactCid: Sha256Cid; layoutArtifactCid: Sha256Cid;
    layout: Readonly<{runtime_artifact_cid: Sha256Cid; layout_artifact_cid: Sha256Cid;
      program_definition_cid: Sha256Cid; parameter_values_cid: Sha256Cid; barrier_cid: Sha256Cid;
      prepared_rows: bigint; retained_bytes: bigint; execution_bytes: bigint}>}>;
  metadataAcquisition?: Readonly<{retainedBytes: bigint; workspaceBytes: bigint;
    metadata: Readonly<{maxWireBytes: number; maxLedgerEntries: number}>;
    directory: Readonly<{maxWireBytes: number; maxDirectoryEntries: number}>}>;
  storeBootstrap?: Readonly<{maxWireBytes: number; maxDirectoryEntries: number}>;
  publicationCapacity?: Readonly<{retainedBytes: bigint; workspaceBytes: bigint}>;
  currentStateCodec?: Readonly<{quantum: number; comparisonWork: number;
    decode: Readonly<{maxWork: number;
      parse: Readonly<{max_input_bytes: number; max_nodes: number; max_depth: number}>;
      tree: Readonly<{max_nodes: number; max_depth: number; max_string_bytes: number; max_total_string_bytes: number}>}>}>;
}>;
/** Selected once, then admitted only when the actual Host calls registration.
 * This snapshot and its reader workspace need the original Host budget. */
export type OpenAIOriginalMaterials = Readonly<{
  responseProfile: OriginalBody;
  policyOriginals: Readonly<{retention: OriginalBody; metadata: OriginalBody; clock: OriginalBody; data: OriginalBody}>;
  readerLimits: Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxMembers: number; maxWork: number}>;
  installation: OpenAIInstallationData;
  originalReadInstallation: OriginalReadInstallationData;
  rawCaptureSelection: Readonly<{selectedAt: string; availableUntil: string; deleteBy: string;
    extensionCeilingAt: string; metadataDeleteBy: string; selectionAvailable: () => boolean}>;
}>;
export type OpenAIChatRegistrationOptions = Readonly<{
  providerId: string; modelSelector: string; modelId: string;
  baseURL: string; apiKey: string;
  taskCid: Sha256Cid; promptCid: Sha256Cid; outputSchemaCid: Sha256Cid;
  promptPayloadWire: string;
  /** Already selected original Host/Run installation; never reconstructed
   * from Program fields, matching CIDs or caller-owned byte declarations. */
  originalReadInstallation: object;
  rawCaptureSelection: object;
  originalMaterials?: never;
  bindingOriginals: object;
  quantityCapacity: QuantityCapacity;
  projectionLimits: ProjectionLimits;
  requestLimits: RequestLimits;
  responseLimits: ResponseLimits;
  /** Explicit trusted physical primitive; not an ambient fallback. */
  fetch: typeof globalThis.fetch;
  observeAt: () => string;
  observeEgress: (facts: unknown) => void;
}>;
/** Selects the existing exclusive async registration. Missing originals or
 * runtime refuse before send. No normal profile or live capability is implied. */
export declare function createInstalledOpenAIChatRegistration(
  options: OpenAIChatRegistrationOptions,
): ModelProviderRegistration;
/** Mutually exclusive with already opaque selections. One callback per Host. */
export type OpenAIChatMaterialsRegistrationOptions =
  Omit<OpenAIChatRegistrationOptions, 'originalReadInstallation' | 'rawCaptureSelection' | 'originalMaterials'> &
  Readonly<{originalMaterials: OpenAIOriginalMaterials;
    originalReadInstallation?: never; rawCaptureSelection?: never}>;
export declare function createInstalledOpenAIChatRegistration(
  options: OpenAIChatMaterialsRegistrationOptions,
): ModelProviderRegistration;
/** Explicit selected Node22.22/Undici7.30 physical route. Reuses the same
 * original Host admissions; it is not ambient fetch, numerical funding,
 * permission or accepted live/public capability. */
export type UndiciOpenAIChatRegistrationOptions =
  Omit<OpenAIChatRegistrationOptions, 'fetch'>;
export declare function createInstalledUndiciOpenAIChatRegistration(
  options: UndiciOpenAIChatRegistrationOptions,
): ModelProviderRegistration;
export type UndiciOpenAIChatMaterialsRegistrationOptions =
  Omit<OpenAIChatMaterialsRegistrationOptions, 'fetch'>;
export declare function createInstalledUndiciOpenAIChatRegistration(
  options: UndiciOpenAIChatMaterialsRegistrationOptions,
): ModelProviderRegistration;
