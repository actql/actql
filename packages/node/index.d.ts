import type {Client, ConnectionOptions, Durability} from '@actql/sdk';

export {ClientError, RequestHeld} from '@actql/sdk';
export type {Client, Execution, Result, Reader, RunReference,
  ConfirmedProfile, ReadOptions, RequestLookup,
  DeliveryAttemptLookup} from '@actql/sdk';

export type EmbeddedHostInstallation = Readonly<{
  directory?: string;
  /** Explicit row bound for the installed source-free, single-task Values profile.
   * Defaults to 100; 1..10000. Other work, cell and byte ceilings remain fixed. */
  valuesMaxRows?: number;
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
