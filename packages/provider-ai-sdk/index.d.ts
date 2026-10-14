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
export type OpenAIChatRegistrationOptions = Readonly<{
  providerId: string; modelSelector: string; modelId: string;
  baseURL: string; apiKey: string;
  taskCid: Sha256Cid; promptCid: Sha256Cid; outputSchemaCid: Sha256Cid;
  promptPayloadWire: string;
  /** Already selected original Host/Run installation; never reconstructed
   * from Program fields, matching CIDs or caller-owned byte declarations. */
  originalReadInstallation: object;
  rawCaptureSelection: object;
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
