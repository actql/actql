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
/** Private original Host/Call clamps, not pre-acquisition funding or a grant.
 * Backing bytes conservatively bound distinct allocations over the Call's
 * lifetime. Node/TLS queue/allocator coverage must be supplied separately. */
export type PhysicalAcquisitionLimits = Readonly<{
  maxPlaintextBytes: number; maxBorrowedBackingBytes: number; maxReads: number;
}>;
/** Explicit positive finite milliseconds. Phase/idle clocks and the optional
 * complete request/read clock are not observed duration or remote-stop ACK. */
export type PhysicalTransportTimeouts = Readonly<{
  connectMs: number; headersMs: number; bodyMs: number;
  /** Same original physical request through bounded body-read settlement.
   * Includes continuous/trickling bodies; excludes Core/Store/Saved work. */
  callMs?: number;
}>;
/** Borrowed existing Host selections. These DATA types issue no grants. */
export type QuantityCapacity = Readonly<{
  limits: Readonly<{tokens: bigint; costUnits: bigint; durationMs: bigint}>;
  perAttempt: Readonly<{tokens: bigint; costUnits: bigint; durationMs: bigint}>;
}>;
/** One fresh callback per installed Host. The Host supplies both arguments;
 * applications never construct the runtime, configuration context or Resource. */
export type ConfiguredModelProviderRegistration =
  (runtime: unknown, context: unknown) => Promise<readonly Readonly<Record<string, unknown>>[]>;
/** Explicit trusted Host selection. Positive finite amounts are checked by
 * Common and the original Resource; these declarations do not grant capacity. */
export type RegisteredSdkProviderOptions = Readonly<{
  /** Original request_data_handling contract, checked by the same Common owner. */
  dataHandlingContractWire: string;
  providerId: string;
  maxSecretBytes?: number;
  /** Frozen per-route settings. Omitted routes use the Provider's defaults. */
  modelGeneration?: readonly RegisteredSdkModelGeneration[];
  transportTimeouts: PhysicalTransportTimeouts & Readonly<{callMs: number}>;
  generation: Readonly<{temperature: number; topP: number; maxOutputTokens: number; seed?: number}>;
  budget: Readonly<{maxCalls: bigint; maxRows: number; maxTokens: bigint;
    maxCostUnits: bigint; maxDurationMs: bigint}>;
  /** Reobserved by the existing current egress admission. */
  observeEgress: () => Readonly<{classification: string; region: string;
    providerRetention: boolean; trainingUse: boolean}>;
}>;
/** Trusted generation settings for one admitted SDK route. The checked Task
 * may set max_output_tokens up to taskMaxOutputTokens. */
export type RegisteredSdkModelGeneration = RegisteredSdkProviderOptions['generation'] & Readonly<{
  selector: string;
  taskMaxOutputTokens: number;
}>;
export declare function createRegisteredSdkProvider(
  options: RegisteredSdkProviderOptions,
): ConfiguredModelProviderRegistration;
/** Configure the selected registered Providers together before preparing the
 * project's Tasks. Supply a frozen list of distinct frozen Provider options. */
export declare function createRegisteredSdkProviders(
  options: readonly RegisteredSdkProviderOptions[],
): ConfiguredModelProviderRegistration;
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
/** The same Host binds these identities from each actual checked Graph.
 * A recipe is not an opaque read installation or a resource grant. */
export type OriginalReadRecipeData =
  Omit<OriginalReadInstallationData, 'nodeInstallation'> & Readonly<{
    nodeInstallation: Omit<OriginalReadInstallationData['nodeInstallation'], 'layout'> & Readonly<{
      layout: Omit<OriginalReadInstallationData['nodeInstallation']['layout'],
        'program_definition_cid' | 'parameter_values_cid' | 'barrier_cid'> &
        Readonly<{program_definition_cid?: never; parameter_values_cid?: never; barrier_cid?: never}>;
    }>;
  }>;
