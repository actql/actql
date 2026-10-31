import {connectInProcess as rootConnectInProcess} from '@actql/sdk';
import {connectInProcess as hostConnectInProcess} from '@actql/sdk/host-port';
import type {CheckpointSigner, Client, Execution, RunState} from '@actql/sdk';
import type {InProcessHostPort} from '@actql/sdk/host-port';
import type {WireRunState} from '@actql/client-wire';

declare const client: Client;
declare const execution: Execution;
declare const signer: CheckpointSigner;
const state = await execution.wait();
if (state.status === 'waiting_checkpoint' && state.checkpoint !== undefined) {
  await client.approve(state.checkpoint.id);
  await client.reject(state.checkpoint.id, {signer});
  // @ts-expect-error The SDK alias is immutable.
  state.checkpoint.id = 'replacement';
}
// @ts-expect-error Ordinary wait may legitimately return no Checkpoint.
await client.approve(state.checkpoint.id);
// @ts-expect-error Status alone does not establish an optional reference.
if (state.status === 'waiting_checkpoint') await client.approve(state.checkpoint.id);
declare const raw: WireRunState;
if (raw.checkpoint !== undefined) {
  // @ts-expect-error The closed wire does not gain the SDK presentation alias.
  raw.checkpoint.id;
}
declare const projected: RunState;
await client.checkpoints({checkpointId: 'original-checkpoint'});
await client.approve('original-checkpoint', {signer});
await client.reject('original-checkpoint', {signer, signal: AbortSignal.timeout(100)});
// @ts-expect-error A reference is not an arbitrary object selector.
await client.approve({id: 'original-checkpoint'});
declare const port: InProcessHostPort;
if (port.answerCheckpoint && projected.checkpoint) {
  // @ts-expect-error A Run reference is not the original full Summary.
  await port.answerCheckpoint(projected.checkpoint, 'approved');
}

// Both intentional public aliases consume the same existing Host-port type.
// This file is compile-only; it constructs no Host or Client at runtime.
const rootHostPortEntry: typeof hostConnectInProcess = rootConnectInProcess;
const hostPortRootEntry: typeof rootConnectInProcess = hostConnectInProcess;
declare const originalLocalOptions: Parameters<typeof hostConnectInProcess>[0];
const rootConnected: ReturnType<typeof hostConnectInProcess> =
  rootHostPortEntry(originalLocalOptions, port);
const hostConnected: ReturnType<typeof rootConnectInProcess> =
  hostPortRootEntry(originalLocalOptions, port);
void [rootConnected, hostConnected];

// @ts-expect-error The root alias retains the existing local-only Host contract.
rootConnectInProcess({mode: 'remote', owner: 'remote'}, port);
// @ts-expect-error An original in-process Host port remains required.
rootConnectInProcess(originalLocalOptions);
