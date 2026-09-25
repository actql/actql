import {createHash} from 'node:crypto';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';

const preparedEffectSourceOwners = new WeakMap();

/**
 * Stream one pinned Effect source through the shared checked Result view.
 * The installed Site owns physical reading; MoonBit owns generation matching,
 * row admission, projection, ordering, and logical identity. This is not an
 * Effect Preview or a mutation permit. The caller retains the input pin.
 */
export async function exportPinnedEffectInput({
  moon, execution, inputs, memberIndex, limits, onChunk,
  onReceipt,
  signal, advanceQuantum = 256,
}) {
  if (typeof onChunk !== 'function' ||
      (onReceipt !== undefined && typeof onReceipt !== 'function') ||
      !Number.isSafeInteger(advanceQuantum) || advanceQuantum <= 0) {
    throw new TypeError('InvalidEffectInputExport');
  }
  signal?.throwIfAborted();
  const input = moon.clientProgramEffectInputAt(inputs, memberIndex);
  if (input === undefined) {
    throw new TypeError('MissingEffectInput');
  }
  const task = moon.clientProgramEffectInputTask(input);
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
    const artifact = onReceipt === undefined
      ? undefined : await onReceipt(input, receipt);
    return Object.freeze({
      fields: moon.clientProgramEffectInputExportFields(receipt),
      logicalCid: moon.clientProgramEffectInputExportLogicalCid(receipt),
      schemaCid: moon.clientProgramEffectInputExportSchemaCid(receipt),
      rowCount: moon.clientProgramEffectInputExportRowCount(receipt),
      ...(artifact === undefined ? {} : {artifact}),
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

/**
 * Prepare bounded bytes from the exact checked input. The returned Store
 * owner must be committed to an independent holding or explicitly released.
 * Neither sealing bytes nor this summary claims a completed Captured Run.
 */
export async function preparePinnedEffectSourcePayload({
  moon, execution, inputs, memberIndex, limits, store, maxBytes,
  control, invocation, retention, sourceBindingCid, contractLimits, signal,
}) {
  if (typeof store?.createPreparedObjectWriter !== 'function' ||
      typeof store.storeAuthorityCid !== 'string' ||
      typeof control?.issueEffectSourceArtifactFromExport !== 'function' ||
      typeof sourceBindingCid !== 'string' ||
      !Number.isSafeInteger(maxBytes) || maxBytes < 0) {
    throw new TypeError('InvalidEffectSourceStore');
  }
  signal?.throwIfAborted();
  const writer = store.createPreparedObjectWriter(maxBytes);
  let sealed;
  let byteCount = 0;
  const digest = createHash('sha256');
  try {
    const summary = await exportPinnedEffectInput({
      moon, execution, inputs, memberIndex, limits, signal,
      onReceipt: (input, receipt) =>
        control.issueEffectSourceArtifactFromExport(
          input, receipt, invocation, retention, sourceBindingCid,
          store.storeAuthorityCid, contractLimits),
      async onChunk(chunk) {
        if (typeof chunk !== 'string') {
          throw new TypeError('InvalidEffectSourceChunk');
        }
        const bytes = Buffer.byteLength(chunk, 'utf8');
        if (bytes > maxBytes - byteCount) {
          throw new RangeError('EffectSourceByteLimit');
        }
        await writer.append(chunk);
        digest.update(chunk, 'utf8');
        byteCount += bytes;
      },
    });
    const physicalCid = `sha256:${digest.digest('hex')}`;
    sealed = await writer.seal(physicalCid);
    if (sealed.cid !== physicalCid || sealed.bytes !== byteCount) {
      throw new Error('EffectSourcePhysicalIdentityMismatch');
    }
    const payload = Object.freeze({
      summary,
      physical: Object.freeze({cid: sealed.cid, bytes: sealed.bytes}),
      prepared: sealed.prepared,
    });
    preparedEffectSourceOwners.set(payload, store);
    return payload;
  } catch (failure) {
    const pendingOwners = [];
    if (failure?.cleanupPending === true &&
        failure.cleanupHandle !== undefined) {
      pendingOwners.push(failure.cleanupHandle);
    }
    let cleanupError;
    try {
      if (sealed === undefined) await writer.cancel();
      else await sealed.prepared.release();
    } catch (error) {
      cleanupError = error;
      pendingOwners.push(Object.freeze({
        status: () => Object.freeze({pending: sealed === undefined
          ? writer.status().reservationHeld === true ||
            writer.status().custodyPending === true
          : sealed.prepared.status().pending === true}),
        retry: sealed === undefined
          ? () => writer.cancel() : () => sealed.prepared.retry(),
      }));
    }
    if (pendingOwners.some(owner => owner.status().pending === true)) {
      const error = new Error('EffectSourceCleanupPending', {cause: failure});
      error.cleanupPending = true;
      error.cleanupError = cleanupError;
      error.cleanupHandle = Object.freeze({
        status: () => Object.freeze({pending: pendingOwners.some(
          owner => owner.status().pending === true)}),
        async retry() {
          const errors = [];
          for (const owner of pendingOwners) {
            if (owner.status().pending !== true) continue;
            try { await owner.retry(); }
            catch (reason) { errors.push(reason); }
          }
          return Object.freeze({
            pending: pendingOwners.some(owner =>
              owner.status().pending === true),
            errors: Object.freeze(errors),
          });
        },
      });
      throw error;
    }
    throw failure;
  }
}

/**
 * Reconcile one exact physical holding without re-exporting the source. A
 * failed commit leaves the prepared owner with the caller for same-record
 * retry or explicit cleanup; it never authorizes another Compute attempt.
 */
export async function commitPinnedEffectSourceHolding({
  payload, store, control, preview, memberIndex, invocation,
  shareFromHoldingCid,
}) {
  if (preparedEffectSourceOwners.get(payload) !== store ||
      typeof store?.commitPhysicalHolding !== 'function' ||
      typeof control?.admitCapturedEffectSourceArtifact !== 'function' ||
      typeof control?.capturedEffectSourceHoldingCid !== 'function' ||
      payload.summary.artifact === undefined) {
    throw new TypeError('InvalidEffectSourceHoldingOwner');
  }
  const source = control.admitCapturedEffectSourceArtifact(
    preview, memberIndex, invocation, payload.summary.artifact,
    store.storeAuthorityCid);
  const holdingCid = control.capturedEffectSourceHoldingCid(source);
  const record = Object.freeze({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'effect-source', holding_cid: holdingCid,
    manifest_cid: payload.summary.artifact.identity,
    objects: Object.freeze([Object.freeze({
      cid: payload.physical.cid, byte_count: payload.physical.bytes,
    })]),
  });
  if (shareFromHoldingCid === undefined) {
    await store.commitPhysicalHolding(record, [payload.prepared]);
  } else {
    if (typeof store.sharePhysicalHolding !== 'function' ||
        typeof shareFromHoldingCid !== 'string') {
      throw new TypeError('InvalidEffectSourceHoldingShare');
    }
    // The Store verifies the existing exact immutable allocation and gives
    // this member independent durable holding and retirement responsibility.
    await store.sharePhysicalHolding(shareFromHoldingCid, record);
  }
  return Object.freeze({source, artifact: payload.summary.artifact,
    holdingCid, record});
}
