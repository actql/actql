import {connectInProcess as connectRuntime} from './internal/client.mjs';
import {canonicalJson as encodeValue} from './checkpoints.mjs';

import type {CheckpointSummary, Client, Durability, SignedCheckpointAnswer} from './index.mjs';
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
  /** Retry this delivery's retained cleanup; never opens another read. */
  close?: () => Promise<void>;
}>;

export type InProcessHostRequest =
  | WireClientBodyByOperation[Exclude<ClientHostOperation, 'read'>]
  | (Omit<WireClientBodyByOperation['read'], 'format'> &
      Readonly<{format: 'typed'}>);

/** Physical operations only; MoonBit owns admission and Run transitions. */
export interface InProcessHostPort {
  perform(operation: ClientHostOperation, request: InProcessHostRequest,
    signal?: AbortSignal): Promise<unknown | LocalResultRows>;
  /** Release only this Client's lease after its reads settle. */
  close?(): Promise<void>;
  /** Synchronously revoke this lease's ingress before reader cleanup. */
  seal?(): void;
  /** Same original Host's signed answer only. The provider independently
   * checks original Checkpoint/Run/key/use/current authority before signing;
   * a supplied summary is DATA, not proof or a generic signing capability.
   * Uncertain signing keeps its original claim/cleanup responsibility. */
  answerCheckpoint?(summary: CheckpointSummary, decision: 'approved' | 'rejected',
    signal?: AbortSignal): Promise<SignedCheckpointAnswer>;
}

// Installed providers use the same Client facade without an HTTP transport.
export const connectInProcess: (options: EmbeddedLocalOptions,
  port: InProcessHostPort) => Promise<Client> = connectRuntime;

/** Canonical value encoding: preserves String values; opaque data may also
 * preserve member names. Artifact/identifier member names normalize by default. */
export const canonicalJson: (value: unknown, options?: Readonly<{dataKeys?: boolean}>) => string = encodeValue;
