import type {Client, Durability} from './index.d.ts';
import type {ClientHostOperation, WireClientBodyByOperation} from
  '@actql/client-wire';

export type EmbeddedLocalOptions = Readonly<{
  mode: 'local';
  owner: 'local';
  runtime?: 'embedded';
  durability?: Durability;
  consentRefs?: readonly string[];
}>;

export type LocalResultFrame = Readonly<{
  value: Record<string, unknown>;
  /** Bytes transferred by this in-process Host API, measured by the provider. */
  byteLength: number;
}>;

export type LocalResultRows = Readonly<{
  kind: 'rows';
  frames: AsyncIterable<LocalResultFrame>;
}>;

export type InProcessHostRequest =
  | WireClientBodyByOperation[Exclude<ClientHostOperation, 'read'>]
  | (Omit<WireClientBodyByOperation['read'], 'format'> &
      Readonly<{format: 'typed'}>);

/** Physical operations only; MoonBit owns admission and Run transitions. */
export interface InProcessHostPort {
  perform(operation: ClientHostOperation, request: InProcessHostRequest,
    signal?: AbortSignal): Promise<unknown | LocalResultRows>;
}

export declare function connectInProcess(options: EmbeddedLocalOptions,
  port: InProcessHostPort): Promise<Client>;
