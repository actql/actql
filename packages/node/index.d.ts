import type {HostCapacityPolicy, HostLookupExecutionPolicy, SourceProfilePaths, EffectProfilePaths,
  InstalledConnectorTable, HostInstallation} from '@actql/local-node';
export type {HostCapacityPolicy, HostLookupExecutionPolicy, SourceProfilePaths, EffectProfilePaths,
  InstalledConnectorTable, CalendarArtifactInstallation} from '@actql/local-node';
import type {Client, ConnectionOptions, ConnectionStringOptions, Durability} from '@actql/sdk';

export {ClientError, RequestHeld} from '@actql/sdk';
export type {Client, Execution, Result, Reader, RunReference,
  ConfirmedProfile, ReadOptions, RequestLookup, RequestLookupTarget, RequestRecovery,
  DeliveryAttemptLookup, ResultPromise, ResultReference, DynamicRow,
  QueryOptions, QueryParameters, StandardSchemaV1} from '@actql/sdk';

export type EmbeddedHostInstallation = Readonly<{
  directory?: string;
  connectorTable?: InstalledConnectorTable;
  /** Explicit row bound for the installed source-free, single-task Values profile.
   * Positive signed 32-bit integer; the upper bound is the Core integer representation,
   * not an admitted workload size. Work, value, byte and resource admission still apply. */
  valuesMaxRows?: number;
  /** Explicit positive signed-32-bit work limit for each source-free Local
   * Compute fragment/sequence counter. Core supplies the default when omitted.
   * This is not a global Run/Host quota, memory grant or compiler/check limit. */
  sourceFreeMaxWork?: number;
  /** Finite initial Request/Run Ledger memory limits, selected before admission.
   * Both safe-integer byte quantities are required; Core checks the installed
   * envelope. Omission preserves the Core default. Not reserved RAM or RSS.
   * Reopen with the same installation selection for original Saved reads. */
  requestMemory?: Readonly<{retainedBytes: number; executionBytes: number}>;
  hostCapacityPolicy?: HostCapacityPolicy;
  hostLookupExecutionPolicy?: HostLookupExecutionPolicy;
  sourceProfilePath?: string;
  sourceProfilePaths?: SourceProfilePaths;
  sourceNamespace?: HostInstallation['sourceNamespace'];
  sourceSelectorNamespace?: HostInstallation['sourceSelectorNamespace'];
  resolveSourceSecret?: (...args: any[]) => any;
  effectProfilePath?: string;
  effectProfilePaths?: EffectProfilePaths;
  resolveEffectSecret?: (...args: any[]) => any;
  authorization?: Readonly<Record<string, unknown>>;
  modelInstallation?: HostInstallation['modelInstallation'];
  calendarArtifact?: HostInstallation['calendarArtifact'];
  registerModelProviders?: HostInstallation['registerModelProviders'];
  verifyRequestValuePolicy?: HostInstallation['verifyRequestValuePolicy'];
  resultDataPolicy?: HostInstallation['resultDataPolicy'];
  inferEvidence?: HostInstallation['inferEvidence'];
  observation?: HostInstallation['observation'];
}>;

export type EmbeddedLocalOptions = Readonly<{
  mode: 'local';
  /** Embedded Local selects its existing Local Host when omitted. */
  owner?: 'local';
  runtime?: 'embedded';
  endpoint?: never;
  token?: never;
  durability?: Durability;
  consentRefs?: readonly string[];
  /** Original project profile override; unavailable physical suppliers refuse before Host I/O. */
  profile?: string;
  installation?: EmbeddedHostInstallation;
}>;

export type EmbeddedLocalHybridOptions = Readonly<{
  mode: 'hybrid';
  owner: 'local';
  runtime?: 'embedded';
  endpoint?: never;
  token?: never;
  durability?: Durability;
  consentRefs?: readonly string[];
  runners?: readonly string[];
  movementPolicyRef: string;
  cloudConnectionRef: string;
}>;

export type NodeConnectionOptions = ConnectionOptions |
  EmbeddedLocalOptions | EmbeddedLocalHybridOptions;

export declare function connect(options: NodeConnectionOptions): Promise<Client>;
export declare function connect(connectionString: string,
  options?: ConnectionStringOptions): Promise<Client>;

export type OpenOptions = Readonly<{
  /** Absolute or relative state directory; defaults to CWD/.actql. */
  stateDir?: string;
  /** Explicit Project profile selection; Mock consents to its limited initial setup. */
  profile?: string;
  durability?: Durability;
  consentRefs?: readonly string[];
  installation?: Omit<EmbeddedHostInstallation, 'directory'>;
}>;
export interface LocalSession extends Client {
  readonly info: Readonly<{stateDir: string}>;
}
/** Reuses the installed Local Host and its awaited close/async-dispose owner. */
export declare function open(options?: OpenOptions): Promise<LocalSession>;
