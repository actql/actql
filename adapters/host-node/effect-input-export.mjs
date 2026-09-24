import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';

/**
 * Stream one pinned Effect source through the shared checked Result view.
 * The installed Site owns physical reading; MoonBit owns generation matching,
 * row admission, projection, ordering, and logical identity. This is not an
 * Effect Preview or a mutation permit. The caller retains the input pin.
 */
export async function exportPinnedEffectInput({
  moon, execution, inputs, memberIndex, task, limits, onChunk,
  signal, advanceQuantum = 256,
}) {
  if (typeof onChunk !== 'function' ||
      !Number.isSafeInteger(advanceQuantum) || advanceQuantum <= 0) {
    throw new TypeError('InvalidEffectInputExport');
  }
  signal?.throwIfAborted();
  const input = moon.clientProgramEffectInputAt(inputs, memberIndex);
  if (input === undefined) {
    throw new TypeError('MissingEffectInput');
  }
  const physical = execution.effectPhysicalSource(task);
  if (physical === undefined) {
    throw new TypeError('MissingEffectPhysicalSource');
  }
  const importing = checked(moon.clientProgramEffectManagedInputBegin(
    input, physical.completed, physical.material, limits));
  let preparation, stream, receipt;
  try {
    preparation = await physical.withRows(
      row => checked(moon.clientProgramEffectManagedInputAppend(
        importing, row)),
      signal,
      () => checked(moon.clientProgramEffectManagedInputFinish(importing)),
    );
    for (;;) {
      signal?.throwIfAborted();
      const progress = checked(moon.clientProgramEffectInputExportAdvance(
        preparation, advanceQuantum));
      if (progress._0) break;
      if (progress._1 <= 0) {
        throw new Error('EffectInputExportDidNotAdvance');
      }
      await yieldEventLoop(undefined, {signal});
    }
    stream = checked(moon.clientProgramEffectInputExportReady(preparation));
    for (;;) {
      signal?.throwIfAborted();
      const chunk = checked(moon.clientProgramEffectInputExportNext(stream));
      if (chunk === undefined) break;
      await onChunk(chunk);
    }
    signal?.throwIfAborted();
    const finished = checked(moon.clientProgramEffectInputExportFinish(stream));
    receipt = finished._0;
    await onChunk(finished._1);
    return Object.freeze({
      fields: moon.clientProgramEffectInputExportFields(receipt),
      logicalCid: moon.clientProgramEffectInputExportLogicalCid(receipt),
    });
  } finally {
    if (receipt !== undefined) {
      moon.clientProgramEffectInputExportReleaseReceipt(receipt);
    }
    if (stream !== undefined) {
      moon.clientProgramEffectInputExportCancel(stream);
    } else if (preparation !== undefined) {
      moon.clientProgramEffectInputExportCancelPreparation(preparation);
    }
    moon.clientProgramEffectManagedInputCancel(importing);
  }
}
