import type {Client, ConnectionOptions, Durability} from '@actql/sdk';

export {ClientError, RequestHeld} from '@actql/sdk';
export type {Client, Execution, Result, Reader, RunReference,
  ConfirmedProfile, ReadOptions, RequestLookup,
  DeliveryAttemptLookup} from '@actql/sdk';

export type EmbeddedLocalOptions = Readonly<{
  mode: 'local';
  owner: 'local';
  runtime?: 'embedded';
  endpoint?: never;
  token?: never;
  durability?: Durability;
  consentRefs?: readonly string[];
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
