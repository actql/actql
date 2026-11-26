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

type InstalledModelSdkImage = Readonly<{
  packageName: string; version: string; path: string; cid: `sha256:${string}`;
}>;
type InstalledModelSdkPackageImage = Readonly<{
  name: string;
  version: string;
  images: readonly Readonly<{path: string; bytes: number; sha256: string}>[];
  dependencies: readonly Readonly<{name: string; package: number}>[];
}>;
type InstalledModelSdkSupport = 'supported' | 'experimental' | 'unsupported' | 'unavailable';
type InstalledModelSdkRoute = Readonly<{
  selector: string; modelId: string; apiMode: string; endpoint: string;
  /** Only supported grants structured generation on this selected route. */
  structuredCapability: Readonly<{operation: 'structured_generate';
    adapter: InstalledModelSdkSupport; model: InstalledModelSdkSupport}>;
  providerOptions: Readonly<Record<string, string | boolean | number>>;
  /** Nonsecret reference and header, checked against the verified adapter. */
  credential?: Readonly<{reference: string; header: string}>;
}>;
export type InstalledModelSdkRegistration = Readonly<{
  providerId: string;
  adapter: InstalledModelSdkImage;
  sdk: InstalledModelSdkImage & Readonly<{exportName: string}>;
  lock: InstalledModelSdkImage;
  /** Host-approved file facts for an externally installed adapter and its dependencies.
   * Entry zero describes the adapter. Dependency indices refer to this same frozen array.
   * Registrations for the same adapter reuse the approved frozen array. */
  packageImages?: readonly InstalledModelSdkPackageImage[];
  defaultSelector: string;
  /** Every exact alias resolves to one approved model, API mode and endpoint. */
  routes: readonly InstalledModelSdkRoute[];
}>;

export type EmbeddedHostInstallation = Readonly<{
  directory?: string;
  connectorTable?: InstalledConnectorTable;
  /** Explicit row bound for the installed source-free, single-task Values profile.
   * Positive signed 32-bit integer; the upper bound is the Core integer representation,
   * not an admitted workload size. Work, value, byte and resource admission still apply. */
  valuesMaxRows?: number;
  /** Explicit positive signed-32-bit work limit for each source-free Local
   * Compute fragment/sequence counter. Core supplies the default when omitted.
   * The same selection also bounds preparation of those runtime Fragments.
   * It does not limit original Program parsing/checking and is not a global
   * Run/Host quota or memory grant. */
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
  /** Trusted registrations selected before Node imports the Local Host. Supply a frozen array of frozen records. */
  modelSdkRegistrations?: readonly InstalledModelSdkRegistration[];
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
