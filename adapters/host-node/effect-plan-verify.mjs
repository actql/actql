import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';

/**
 * Match an admitted private Preview against the checked, retained Result view.
 * This emits only prepared Result bytes. It does not grant Effect apply, target
 * authority, or publication commit; the caller owns partial-output cleanup.
 */
export async function verifyPinnedEffectPlan({
  moon, execution, previewInputs, previewIndex, limits, planLimits,
  onChunk, signal, inputKey, publishedTarget, advanceQuantum = 256,
}) {
  if (typeof onChunk !== 'function' ||
      !Number.isSafeInteger(advanceQuantum) || advanceQuantum <= 0) {
    throw new TypeError('InvalidEffectPlanVerification');
  }
  const ownedPlanLimits = Object.freeze({
    maxFields: planLimits.maxFields,
    maxWork: planLimits.maxWork,
    maxBytes: planLimits.maxBytes,
    maxNodes: planLimits.maxNodes,
    maxDepth: planLimits.maxDepth,
    maxUtf16Units: planLimits.maxUtf16Units,
  });
  if (!Object.values(ownedPlanLimits).every(value =>
    Number.isSafeInteger(value) && value >= 0) ||
    ownedPlanLimits.maxNodes === 0 || ownedPlanLimits.maxDepth === 0) {
    throw new TypeError('InvalidEffectPlanLimits');
  }
  signal?.throwIfAborted();
  const input = moon.clientProgramEffectPreviewInputAt(
    previewInputs, previewIndex);
  if (input === undefined) throw new TypeError('MissingEffectPreviewInput');
  const task = moon.clientProgramEffectInputTask(input);
  const physical = execution.effectPhysicalSource(task);
  if (physical === undefined) throw new TypeError('MissingEffectPhysicalSource');
  // The same capture-owned target/key enter the existing Common owner.
  // No decoding, fallback, current-config lookup or new target issuance occurs.
  const importing = checked(publishedTarget === undefined
    ? inputKey === undefined
      ? moon.clientProgramEffectPlanImportBegin(previewInputs, previewIndex,
        physical.completed, physical.material, limits,
        ownedPlanLimits.maxFields, ownedPlanLimits.maxWork)
      : moon.clientProgramEffectPlanImportBeginWithKey(previewInputs, previewIndex,
        physical.completed, physical.material, limits,
        ownedPlanLimits.maxFields, ownedPlanLimits.maxWork, inputKey)
    : inputKey === undefined
      ? moon.clientProgramEffectPlanImportBeginWithTarget(previewInputs, previewIndex,
        physical.completed, physical.material, limits,
        ownedPlanLimits.maxFields, ownedPlanLimits.maxWork, publishedTarget)
      : moon.clientProgramEffectPlanImportBeginWithTargetAndKey(previewInputs, previewIndex,
        physical.completed, physical.material, limits,
        ownedPlanLimits.maxFields, ownedPlanLimits.maxWork, publishedTarget, inputKey));
  let preparation, cursor, receipt;
  try {
    preparation = await physical.withRows(
      row => checked(moon.clientProgramEffectPlanImportAppend(importing, row)),
      signal,
      () => checked(moon.clientProgramEffectPlanImportFinish(importing)),
    );
    for (;;) {
      signal?.throwIfAborted();
      const progress = checked(moon.clientProgramEffectPlanAdvance(
        preparation, advanceQuantum));
      if (runtimeField(progress, 0)) break;
      if (runtimeField(progress, 1) <= 0) throw new Error('EffectPlanDidNotAdvance');
      await yieldEventLoop(undefined, {signal});
    }
    cursor = checked(moon.clientProgramEffectPlanReady(preparation));
    for (;;) {
      signal?.throwIfAborted();
      const chunk = checked(moon.clientProgramEffectPlanNext(
        cursor, ownedPlanLimits.maxNodes, ownedPlanLimits.maxDepth,
        ownedPlanLimits.maxUtf16Units, ownedPlanLimits.maxFields,
        ownedPlanLimits.maxWork, ownedPlanLimits.maxBytes));
      if (chunk === undefined) break;
      await onChunk(chunk);
    }
    signal?.throwIfAborted();
    const finished = checked(moon.clientProgramEffectPlanFinish(cursor));
    receipt = runtimeField(finished, 0);
    await onChunk(runtimeField(finished, 1));
    return Object.freeze({
      fields: moon.clientProgramEffectInputExportFields(receipt),
      logicalCid: moon.clientProgramEffectInputExportLogicalCid(receipt),
      proof: runtimeField(finished, 2),
    });
  } finally {
    if (receipt !== undefined) {
      moon.clientProgramEffectInputExportReleaseReceipt(receipt);
    }
    if (cursor !== undefined) {
      moon.clientProgramEffectPlanCancel(cursor);
    } else if (preparation !== undefined) {
      moon.clientProgramEffectPlanCancelPreparation(preparation);
    }
    moon.clientProgramEffectPlanCancelImport(importing);
  }
}
