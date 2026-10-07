import type {HostCapacityPolicy} from '@actql/local-node';
export type {HostCapacityPolicy} from '@actql/local-node';
import type {Client, ConnectionOptions, ConnectionStringOptions, Durability} from '@actql/sdk';

export {ClientError, RequestHeld} from '@actql/sdk';
export type {Client, Execution, Result, Reader, RunReference,
  ConfirmedProfile, ReadOptions, RequestLookup, RequestLookupTarget, RequestRecovery,
  DeliveryAttemptLookup, ResultPromise, ResultReference, DynamicRow,
  QueryOptions, QueryParameters, StandardSchemaV1} from '@actql/sdk';

export type EmbeddedHostInstallation = Readonly<{
  directory?: string;
  /** Explicit row bound for the installed source-free, single-task Values profile.
   * Defaults to 100; 1..10000. Other work, cell and byte ceilings remain fixed. */
  valuesMaxRows?: number;
  hostCapacityPolicy?: HostCapacityPolicy;
  sourceProfilePath?: string;
  sourceProfilePaths?: readonly [string, string];
  resolveSourceSecret?: (...args: any[]) => any;
  effectProfilePath?: string;
  resolveEffectSecret?: (...args: any[]) => any;
  authorization?: Readonly<Record<string, unknown>>;
}>;

export type EmbeddedLocalOptions = Readonly<{
  mode: 'local';
  owner: 'local';
  runtime?: 'embedded';
  endpoint?: never;
  token?: never;
  durability?: Durability;
  consentRefs?: readonly string[];
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
  durability?: Durability;
  consentRefs?: readonly string[];
  installation?: Omit<EmbeddedHostInstallation, 'directory'>;
}>;
export interface LocalSession extends Client {
  readonly info: Readonly<{stateDir: string}>;
}
/** Reuses the installed Local Host and its awaited close/async-dispose owner. */
export declare function open(options?: OpenOptions): Promise<LocalSession>;
