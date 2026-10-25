import {effectReviewCheckpointBinding, effectReviewCheckpointBindingFacts, effectReviewCheckpointWaitingState, effectReviewCheckpointReconciliationState,
  type AllowedEffectRun, type RunDefinition, type EffectReviewCheckpointBinding} from '@actql/run-host-core';
declare const allowed: AllowedEffectRun;
declare const definition: RunDefinition;
const binding: EffectReviewCheckpointBinding = effectReviewCheckpointBinding(allowed, definition, '{}');
effectReviewCheckpointBindingFacts(binding, allowed, definition);
// @ts-expect-error Plain metadata is not the original admitted binding.
effectReviewCheckpointBindingFacts({checkpointCid: '', checkpointWire: '', runId: '', unitId: '',
  runDefinitionCid: '', previewCid: '', reviewProjectionCid: '', continuationCid: ''}, allowed, definition);
// @ts-expect-error A Definition is not the original AllowedEffectRun.
effectReviewCheckpointBindingFacts(binding, definition, definition);

effectReviewCheckpointWaitingState(binding, allowed, definition, '{}', 'time', ['main'] as const);
// @ts-expect-error Stored physical bytes cannot be supplied as a Boolean ACK.
effectReviewCheckpointWaitingState(binding, allowed, definition, true, 'time', []);
// @ts-expect-error Declared Results remain typed Strings.
effectReviewCheckpointWaitingState(binding, allowed, definition, '{}', 'time', [1]);

effectReviewCheckpointReconciliationState(binding, allowed, definition, '{}', '{}', '{}', '{}',
  ['member'] as const, 'time', ['published'] as const);
// @ts-expect-error Physical stop Booleans cannot replace admitted member receipt DATA.
effectReviewCheckpointReconciliationState(binding, allowed, definition, '{}', '{}', '{}', '{}', [true], 'time', []);
