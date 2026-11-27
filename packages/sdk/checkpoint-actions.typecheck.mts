import {signCheckpointAnswer, connectInProcess as rootConnectInProcess} from '@actql/sdk';
import {connectInProcess as hostConnectInProcess} from '@actql/sdk/host-port';
import type {CheckpointSigner, CheckpointSummary, SignedCheckpointAnswer, Client, Execution, RunState} from '@actql/sdk';
import type {InProcessHostPort} from '@actql/sdk/host-port';
import type {WireRunState} from '@actql/client-wire';

declare const client: Client;
declare const execution: Execution;
declare const signer: CheckpointSigner;
declare const summary: CheckpointSummary;
const answer: SignedCheckpointAnswer = await signCheckpointAnswer(summary, 'approved', signer);
void answer;
// @ts-expect-error The sign-only helper accepts decision values, not operations.
await signCheckpointAnswer(summary, 'approve', signer);
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

// The generated codec distinguishes its two existing WeakMap stage kinds.
// This compile-only distinction is not a current/owner/authority check: the
// runtime must still authenticate each original stage in its own WeakMap.
import {createCheckpointAnswerCodec} from './internal/checkpoint-answer-construction.generated.mjs';
declare const codec: ReturnType<typeof createCheckpointAnswerCodec>;
declare const candidate: Awaited<ReturnType<typeof codec.prepareAnswerCandidate>>;
declare const resolution: Awaited<ReturnType<typeof codec.prepareAnswerResolution>>;
const approvalPreimage: string | undefined = codec.answerCandidateApprovalPreimage(candidate);
const resolutionPreimage: string = codec.answerResolutionPreimage(resolution);
void [approvalPreimage, resolutionPreimage];
// @ts-expect-error A structural object is not an admitted original candidate stage.
codec.answerCandidateApprovalPreimage({});
// @ts-expect-error A candidate has not yet become a resolution stage.
codec.answerResolutionPreimage(candidate);
// @ts-expect-error A resolution is not the earlier candidate stage.
codec.prepareAnswerResolution(resolution);
