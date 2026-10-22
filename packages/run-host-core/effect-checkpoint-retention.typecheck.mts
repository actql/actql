import {effectReviewCheckpointBinding, effectReviewCheckpointBindingFacts,
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
