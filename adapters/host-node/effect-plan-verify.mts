import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
import type {withManagedOutputRows} from '../store-local/managed-memory-representations.mjs';

type ImportArguments = [preview: unknown, index: number, completed: unknown,
  material: unknown, limits: unknown, maxFields: number, maxWork: number];
type PlanRuntime = Readonly<{
  clientProgramEffectPreviewInputAt(preview: unknown, index: number): unknown;
  clientProgramEffectInputTask(input: unknown): number;
  clientProgramEffectPlanImportBegin(...args: ImportArguments): unknown;
  clientProgramEffectPlanImportBeginWithKey(...args: [...ImportArguments, key: unknown]): unknown;
  clientProgramEffectPlanImportBeginWithTarget(...args: [...ImportArguments, target: unknown]): unknown;
  clientProgramEffectPlanImportBeginWithTargetAndKey(
    ...args: [...ImportArguments, target: unknown, key: unknown]
  ): unknown;
  clientProgramEffectPlanImportAppend(importing: unknown, row: string): unknown;
  clientProgramEffectPlanImportFinish(importing: unknown): unknown;
  clientProgramEffectPlanAdvance(preparation: unknown, quantum: number): unknown;
  clientProgramEffectPlanReady(preparation: unknown): unknown;
  clientProgramEffectPlanNext(cursor: unknown, maxNodes: number, maxDepth: number,
    maxUtf16Units: number, maxFields: number, maxWork: number, maxBytes: number): unknown;
  clientProgramEffectPlanFinish(cursor: unknown): unknown;
  clientProgramEffectInputExportFields(receipt: unknown): readonly string[];
  clientProgramEffectInputExportLogicalCid(receipt: unknown): string;
  clientProgramEffectInputExportReleaseReceipt(receipt: unknown): void;
  clientProgramEffectPlanCancel(cursor: unknown): void;
  clientProgramEffectPlanCancelPreparation(preparation: unknown): boolean;
  clientProgramEffectPlanCancelImport(importing: unknown): void;
}>;
type PhysicalSource = Readonly<{
  completed: unknown;
  material: unknown;
  withRows?<Value>(accept: (row: string) => unknown, signal: AbortSignal | undefined,
    commit: () => Value): ReturnType<typeof withManagedOutputRows<Value>>;
}>;
type PlanLimits = Readonly<{
  maxFields: number; maxWork: number; maxBytes: number;
  maxNodes: number; maxDepth: number; maxUtf16Units: number;
}>;
type VerifyPlanOptions = Readonly<{
  moon: PlanRuntime;
  execution: Readonly<{effectPhysicalSource(task: number): PhysicalSource | undefined}>;
  previewInputs: unknown;
  previewIndex: number;
  limits: unknown;
  planLimits: PlanLimits;
  onChunk(chunk: string): unknown;
  signal?: AbortSignal;
  inputKey?: unknown;
  publishedTarget?: unknown;
  advanceQuantum?: number;
}>;

/**
 * Match an admitted private Preview against the checked, retained Result view.
 * This emits only prepared Result bytes. It does not grant Effect apply, target
 * authority, or publication commit; the caller owns partial-output cleanup.
 */
export async function verifyPinnedEffectPlan({
  moon, execution, previewInputs, previewIndex, limits, planLimits,
  onChunk, signal, inputKey, publishedTarget, advanceQuantum = 256,
}: VerifyPlanOptions) {
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
  let preparation: unknown, cursor: unknown, receipt: unknown;
  try {
    // The selected Preview source must expose its physical row borrow.
    preparation = await physical.withRows!(
      row => checked(moon.clientProgramEffectPlanImportAppend(importing, row)),
      signal,
      () => checked(moon.clientProgramEffectPlanImportFinish(importing)),
    );
    for (;;) {
      signal?.throwIfAborted();
      const progress = checked(moon.clientProgramEffectPlanAdvance(
        preparation, advanceQuantum));
      if (runtimeField(progress, 0)) break;
      if ((runtimeField(progress, 1) as number) <= 0) throw new Error('EffectPlanDidNotAdvance');
      await yieldEventLoop(undefined, {signal});
    }
    cursor = checked(moon.clientProgramEffectPlanReady(preparation));
    for (;;) {
      signal?.throwIfAborted();
      const chunk = checked(moon.clientProgramEffectPlanNext(
        cursor, ownedPlanLimits.maxNodes, ownedPlanLimits.maxDepth,
        ownedPlanLimits.maxUtf16Units, ownedPlanLimits.maxFields,
        ownedPlanLimits.maxWork, ownedPlanLimits.maxBytes)) as string | undefined;
      if (chunk === undefined) break;
      await onChunk(chunk);
    }
    signal?.throwIfAborted();
    const finished = checked(moon.clientProgramEffectPlanFinish(cursor));
    receipt = runtimeField(finished, 0);
    await onChunk(runtimeField(finished, 1) as string);
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
