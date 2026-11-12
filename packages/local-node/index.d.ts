import type {Client} from '@actql/sdk';
import type {HostCapacityPolicy, HostLookupExecutionPolicy, HostRequestValuePolicyVerifier} from './host-policy.js';
import type {HostObservationConnection} from './observation.js';
export type {HostCapacityPolicy, HostLookupExecutionPolicy,
  HostRequestValuePolicySubject, HostRequestValuePolicyValue,
  HostRequestValuePolicyVerifier} from './host-policy.js';

declare const installedConnectorTableBrand: unique symbol;
/** An admitted, process-local table of trusted Host installation loaders. */
export type InstalledConnectorTable = Readonly<{
  [installedConnectorTableBrand]: true;
}>;
export type InstalledConnectorEntry = Readonly<{
  name: string;
  registration?: string;
  revision?: string;
  providerBundle?: string;
  responseHeaders?: readonly string[];
  /** Finite Connector-owned files consumed by implementation binding. */
  implementationFiles?: readonly Readonly<{path: string; href: string}>[];
  /** The selected loader's returned module is checked before use. */
  source?: Readonly<{profileVersion: string; load: () => unknown}>;
  effect?: Readonly<{
    profileVersion: string;
    load: () => unknown;
    identityProfile?: Readonly<{
      continuation: string;
      continuationBinding: 'binding_cid' | 'publication_generation_cid';
      dispatch: string;
      recovery: string;
      source: string;
      targetCheck: string;
      unit: string;
    }>;
  }>;
}>;
/** Snapshot explicit trusted bootstrap entries without invoking their loaders.
 * This handle does not identify or retain executable artifact bytes. */
export declare function createInstalledConnectorTable(
  entries: readonly InstalledConnectorEntry[]): InstalledConnectorTable;

/** Multiple independently published Sources: 2–128 profiles and at most
 * 128 total read bindings. Execution keeps its existing acquisition bounds. */
export type SourceProfilePaths = readonly [string, string, ...string[]];
/** Independently published Effect installations. The shared Environment bounds
 * their inventory; every complete Effect Set must select one installation. */
export type EffectProfilePaths = readonly [string, string, ...string[]];

/** Explicit immutable semantic artifact; no OS TZDB or default profile is selected. */
export type CalendarArtifactInstallation = Readonly<{
  selection: Readonly<{version: 'actql-calendar-selection/0.1'; tzdb_version: string;
    conversion_law: 'actql-calendar-boundaries/0.1'; table_bytes_cid: string}>;
  /** Exact canonical artifact body bytes, including no file-framing newline. */
  tableBytes: Uint8Array;
  limits: Readonly<{max_bytes: number; max_nodes: number; max_depth: number;
    max_zones: number; max_transitions: number}>;
  maxSelectionWork: number;
}>;

export type HostInstallation = Readonly<{
  directory?: string;
  connectorTable?: InstalledConnectorTable;
  sourceProfilePath?: string;
  sourceProfilePaths?: SourceProfilePaths;
  /** Trusted closed query-alias namespace over this Host's complete installed Source range.
   * Negative membership requires its own current inspect_absence authorization. */
  sourceNamespace?: string;
  /** Complete installed selector-registration namespace; absence needs a separate current grant. */
  sourceSelectorNamespace?: string;
  effectProfilePath?: string;
  effectProfilePaths?: EffectProfilePaths;
  hostCapacityPolicy?: HostCapacityPolicy;
  /** Explicit positive signed-32-bit work limit for each source-free Local
   * Compute fragment/sequence counter. Core supplies the default when omitted.
   * The same selection also bounds preparation of those runtime Fragments.
   * It does not limit original Program parsing/checking and is not a global
   * Run/Host quota or memory grant. */
  sourceFreeMaxWork?: number;
  /** Finite initial Request/Run Ledger memory limits, selected before admission.
   * Both safe-integer byte quantities are required; Core checks the installed
   * envelope and derives checking/collection row ceilings from the same pair.
   * Omission preserves 512 MiB per counter. Not reserved RAM or RSS; the same
   * owner funds actual demand. Explicit row limits may narrow this selection.
   * Reopen with the same installation selection for original Saved reads. */
  requestMemory?: Readonly<{retainedBytes: number; executionBytes: number}>;
  hostLookupExecutionPolicy?: HostLookupExecutionPolicy;
  resolveSourceSecret?: (...args: any[]) => any;
  resolveEffectSecret?: (...args: any[]) => any;
  authorization?: Readonly<Record<string, unknown>>;
  modelInstallation?: Readonly<Record<string, unknown>>;
  calendarArtifact?: CalendarArtifactInstallation;
  registerModelProviders?: (...args: any[]) => any;
  verifyRequestValuePolicy?: HostRequestValuePolicyVerifier;
  resultDataPolicy?: Readonly<Record<string, unknown>>;
  inferEvidence?: Readonly<{
    target: string | readonly string[]; destination: string; maxBytes: number;
    authorize: (binding: Readonly<Record<string, unknown>>) => boolean | Promise<boolean>;
    sink: Readonly<{
      capture: (originals: Readonly<Record<string, unknown>>) => Promise<Readonly<Record<string, unknown>>>;
      record: (receipt: Readonly<Record<string, unknown>>) => Promise<void>;
    }>;
  }>;
  retainedRelationOutput?: boolean;
  observation?: HostObservationConnection;
}>;
export declare function connect(options: Readonly<{
  mode: 'local'; owner?: 'local'; runtime?: 'embedded'; durability?: 'volatile' | 'durable';
  consentRefs?: readonly string[]; profile?: string; installation?: HostInstallation;
}>): Promise<Client>;
export declare function publishSource(options?: Pick<HostInstallation,
  'directory' | 'sourceProfilePath' | 'resolveSourceSecret' | 'connectorTable'> & {signal?: AbortSignal}): Promise<unknown>;
export declare function publishEffect(options?: Pick<HostInstallation,
  'directory' | 'effectProfilePath' | 'resolveEffectSecret' | 'hostCapacityPolicy' | 'hostLookupExecutionPolicy' | 'connectorTable'> & {signal?: AbortSignal}): Promise<unknown>;
