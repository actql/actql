import type {Client} from '@actql/sdk';
import type {HostCapacityPolicy} from './host-policy.js';
import type {HostObservationConnection} from './observation.js';
export type {HostCapacityPolicy} from './host-policy.js';

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
  resolveSourceSecret?: (...args: any[]) => any;
  resolveEffectSecret?: (...args: any[]) => any;
  authorization?: Readonly<Record<string, unknown>>;
  modelInstallation?: Readonly<Record<string, unknown>>;
  registerModelProviders?: (...args: any[]) => any;
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
  mode: 'local'; owner: 'local'; runtime?: 'embedded'; durability?: 'volatile' | 'durable';
  consentRefs?: readonly string[]; installation?: HostInstallation;
}>): Promise<Client>;
export declare function publishSource(options?: Pick<HostInstallation,
  'directory' | 'sourceProfilePath' | 'resolveSourceSecret' | 'connectorTable'> & {signal?: AbortSignal}): Promise<unknown>;
export declare function publishEffect(options?: Pick<HostInstallation,
  'directory' | 'effectProfilePath' | 'resolveEffectSecret' | 'hostCapacityPolicy' | 'connectorTable'> & {signal?: AbortSignal}): Promise<unknown>;
