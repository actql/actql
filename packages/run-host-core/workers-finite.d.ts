/** Trusted finite installation limits, never Program or request JSON. */
export interface WorkersFiniteConfiguration {
  /** Optional installed expression capability. No budget is inferred when absent. */
  readonly fragments?: {
    readonly contract: string; readonly ordered?: string;
    readonly limits: {
      readonly roots: {readonly max_roots: number; readonly max_pointer_bytes: number;
        readonly max_work: number};
      readonly demands: {readonly max_roots: number; readonly max_nodes: number;
        readonly max_work: number; readonly max_text_bytes: number; readonly max_links: number};
      readonly physical: {readonly max_body_bytes: number; readonly max_body_nodes: number;
        readonly max_body_depth: number};
      readonly logical: {readonly max_input_rows: bigint; readonly max_value_bytes: bigint;
        readonly max_live_value_bytes: bigint; readonly max_work: bigint};
      readonly max_input_rows: bigint; readonly max_value_bytes: bigint;
    };
  };
  readonly environment: {
    readonly wire: string; readonly cid: string;
    /** Exact installed reduction contract; omission enables no numeric profile. */
    readonly numeric_profile_cid?: string;
    readonly expressions: {readonly text_time: boolean; readonly veca: boolean};
    readonly operations: {readonly rela: boolean; readonly sga: boolean;
      readonly tea: boolean; readonly calendar: boolean; readonly text_rank: boolean};
  };
  readonly contracts: {readonly registry: string; readonly values: string;
    readonly grammar: string; readonly barriers: string};
  readonly sequence: {readonly max_steps: number; readonly max_rows: number;
    readonly max_cells: number; readonly max_bindings: number;
    readonly max_name_bytes: number;
    readonly expressions: {readonly max_nodes: number; readonly max_work: number;
      readonly max_depth: number; readonly max_literal_nodes: number;
      readonly max_literal_text_bytes: number}};
  readonly execution: {readonly rows: {readonly max_rows: number;
    readonly metadata_entries: number; readonly retained_entries: number;
    readonly operation_entries: number; readonly input_values: WorkersValueLimits;
    readonly output_values: WorkersValueLimits};
    readonly max_work: number; readonly max_frames: number};
  readonly measurement: {readonly max_work: number; readonly max_bytes: number;
    readonly max_nodes: number; readonly max_depth: number};
  readonly capacity: {readonly contract_cid: string; readonly max_rows: number;
    readonly max_value_bytes: number};
  readonly search: {readonly max_offers: number; readonly max_strategies: number;
    readonly max_work: number; readonly max_revisions: number};
  readonly ledger: {readonly planning_work: number; readonly attempts: number;
    readonly holdings: number; readonly transfer_bytes: bigint;
    readonly retained_bytes: bigint; readonly execution_bytes: bigint};
  readonly milliseconds: bigint; readonly max_work: number; readonly max_entries: number;
}

export interface WorkersValueLimits {
  readonly max_nodes: number; readonly max_text_bytes: number;
  readonly max_depth: number; readonly max_work: number;
}

declare const owner: unique symbol;
export type WorkersFiniteHandle<Kind extends string> = Readonly<{[owner]: Kind}>;
export type WorkersFinitePreparation = WorkersFiniteHandle<'preparation'>;
export type WorkersFiniteSetup = WorkersFiniteHandle<'setup'>;
export type WorkersFiniteLedger = WorkersFiniteHandle<'ledger'>;
export interface WorkersFiniteOriginal {
  readonly preparation: WorkersFinitePreparation;
  readonly admission: WorkersFiniteHandle<'admission'>;
  readonly definition: WorkersFiniteHandle<'definition'>;
}

/** The low-level generic controls expose trusted ABI operations only. */
export type WorkersFiniteControl = Readonly<Record<string,
  (...args: unknown[]) => unknown>>;
export interface WorkersFiniteCore {
  managedExecutionProfileCid(): string;
  readonly remoteSiteControl: WorkersFiniteControl;
  readonly remoteTransferControl: WorkersFiniteControl;
  readonly remoteBundleControl: WorkersFiniteControl;
  readonly siteControl: WorkersFiniteControl;
  readonly outputExportControl: WorkersFiniteControl;
  readonly publicationControl: WorkersFiniteControl;
}

export interface WorkersFiniteAuthorization {
  authorize(...args: unknown[]): unknown;
  cover(...args: unknown[]): unknown;
  isProtectedSite(site: string): boolean;
  counters(): Readonly<Record<string, number>>;
  resourceUsage(): Readonly<Record<string, number>>;
  close(): void;
}

export interface WorkersFiniteExecution {
  readonly status: string;
  readonly completed: readonly Readonly<Record<string, unknown>>[];
  readonly resultInventory: readonly Readonly<Record<string, unknown>>[];
  output(task: number): WorkersFiniteHandle<'output'> | undefined;
  usage(): Readonly<Record<string, bigint | number>>;
  storePublicationResult(result: number, store: object,
    publication: object, signal?: AbortSignal): Promise<unknown>;
}

export interface WorkersFiniteHost {
  readonly core: WorkersFiniteCore;
  prepare(document: string): WorkersFinitePreparation;
  createLedger(): WorkersFiniteLedger;
  admitMaterials(body: string, expectedRunDefinitionCid: string): WorkersFiniteOriginal;
  open(preparation: WorkersFinitePreparation, original: {
    readonly admission: WorkersFiniteOriginal['admission'];
    readonly definition: WorkersFiniteOriginal['definition'];
    readonly ledger: WorkersFiniteLedger;
  }, authorization: WorkersFiniteAuthorization): WorkersFiniteSetup;
  withExecution<T>(setup: WorkersFiniteSetup,
    authorization: WorkersFiniteAuthorization,
    consume: (execution: WorkersFiniteExecution) => T | Promise<T>,
    signal?: AbortSignal): Promise<T>;
  usage(setup: WorkersFiniteSetup): unknown;
}

export interface WorkersFiniteAuthorizationOptions {
  readonly runtime?: never;
  readonly configuration?: string;
  readonly configurationCid?: string;
  readonly context: {readonly principal: string; readonly contextCid: string};
  readonly protectedSites: readonly string[];
  readonly answeringAuthorities?: readonly string[];
  readonly requiredClaims?: readonly string[];
  readonly decisionTimeoutMs?: number;
  readonly maxInFlightDecisions?: number;
  readonly maxRetainedDecisions?: number;
}

/**
 * Creates one invocation-scoped linked runtime for one original Run, with no
 * conformance issuer. Do not cache the returned assembly across requests.
 * Keep pending cleanup and its original Ledger within this invocation's custody.
 */
export function createWorkersFiniteRuntime(hashSeed: number,
  configuration: WorkersFiniteConfiguration): Readonly<{
    host: WorkersFiniteHost;
    core: WorkersFiniteCore;
    createAuthorizationGate(options: WorkersFiniteAuthorizationOptions):
      WorkersFiniteAuthorization;
  }>;

/** Exact audited payload bytes bound by the existing runtime_executable role. */
export const workersFiniteArtifact: Readonly<{
  componentCid: string;
  componentBytes: number;
}>;
