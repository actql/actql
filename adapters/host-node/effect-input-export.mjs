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
  onReceipt, onCanonicalRow, canonicalRowLimits,
  signal, advanceQuantum = 256,
}) {
  if (typeof onChunk !== 'function' ||
      (onReceipt !== undefined && typeof onReceipt !== 'function') ||
      (onCanonicalRow !== undefined &&
        (typeof onCanonicalRow !== 'function' ||
          !Number.isSafeInteger(canonicalRowLimits?.maxNodes) ||
          canonicalRowLimits.maxNodes < 1 ||
          !Number.isSafeInteger(canonicalRowLimits?.maxDepth) ||
          canonicalRowLimits.maxDepth < 1 ||
          !Number.isSafeInteger(canonicalRowLimits?.maxUtf16Units) ||
          canonicalRowLimits.maxUtf16Units < 0)) ||
      !Number.isSafeInteger(advanceQuantum) || advanceQuantum <= 0) {
    throw new TypeError('InvalidEffectInputExport');
  }
  const rowLimits = onCanonicalRow === undefined ? undefined :
    Object.freeze({maxNodes: canonicalRowLimits.maxNodes,
      maxDepth: canonicalRowLimits.maxDepth,
      maxUtf16Units: canonicalRowLimits.maxUtf16Units});
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
      if (onCanonicalRow === undefined) {
        const chunk = checked(moon.clientProgramEffectInputExportNext(stream));
        if (chunk === undefined) break;
        await onChunk(chunk);
      } else {
        const row = checked(moon.clientProgramEffectInputExportNextCanonicalRow(
          stream, rowLimits.maxNodes, rowLimits.maxDepth,
          rowLimits.maxUtf16Units));
        if (row === undefined) break;
        await onCanonicalRow(row._0, row._2);
        await onChunk(row._1);
      }
    }
    signal?.throwIfAborted();
    const finished = checked(moon.clientProgramEffectInputExportFinish(stream));
    receipt = finished._0;
    await onChunk(finished._1);
    const artifact = onReceipt === undefined
      ? undefined : await onReceipt(input, receipt, importing);
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
  moon, checkedOwner, execution, inputs, memberIndex, limits, store, maxBytes,
  control, invocation, retention, sourceBindingCid, contractLimits, signal,
  localEvidenceContext,
  onProposalRow, proposalMemberIndexes, proposalLimits,
}) {
  if (typeof store?.createPreparedObjectWriter !== 'function' ||
      typeof store.storeAuthorityCid !== 'string' ||
      typeof moon?.clientProgramIssueCapturedEffectInputLocalResultDefinition !==
        'function' ||
      typeof moon?.clientProgramIssueCapturedEffectInputLocalInvocation !==
        'function' ||
      checkedOwner === undefined ||
      !['maxWireBytes', 'maxNodes', 'maxDepth'].every(key =>
        Number.isSafeInteger(contractLimits?.[key]) &&
        contractLimits[key] > 0) ||
      typeof control?.issueEffectSourceArtifactFromExport !== 'function' ||
      typeof control?.issueSourceFreeLocalEffectResultArtifact !== 'function' ||
      typeof sourceBindingCid !== 'string' ||
      !['scopeCid', 'effectiveDataPolicyCid', 'authorityScopeCid'].every(
        key => /^sha256:[0-9a-f]{64}$/u.test(localEvidenceContext?.[key])) ||
      (proposalMemberIndexes !== undefined &&
        (onProposalRow === undefined ||
          !Array.isArray(proposalMemberIndexes) ||
          proposalMemberIndexes.length === 0 ||
          new Set(proposalMemberIndexes).size !==
            proposalMemberIndexes.length ||
          proposalMemberIndexes.some(index =>
            !Number.isSafeInteger(index) || index < 0))) ||
      (onProposalRow !== undefined &&
        (typeof onProposalRow !== 'function' ||
          !['maxFields', 'maxWork', 'maxBytes', 'maxNodes', 'maxDepth',
            'maxUtf16Units'].every(key =>
            Number.isSafeInteger(proposalLimits?.[key]) &&
            proposalLimits[key] >= 0) ||
          proposalLimits.maxBytes === 0 ||
          proposalLimits.maxNodes === 0 ||
          proposalLimits.maxDepth === 0)) ||
      !Number.isSafeInteger(maxBytes) || maxBytes < 0) {
    throw new TypeError('InvalidEffectSourceStore');
  }
  const proposalBounds = onProposalRow === undefined ? undefined :
    Object.freeze({maxFields: proposalLimits.maxFields,
      maxWork: proposalLimits.maxWork, maxBytes: proposalLimits.maxBytes,
      maxNodes: proposalLimits.maxNodes, maxDepth: proposalLimits.maxDepth,
      maxUtf16Units: proposalLimits.maxUtf16Units});
  const proposalMembers = onProposalRow === undefined ? undefined :
    Object.freeze([...(proposalMemberIndexes ?? [memberIndex])]);
  if (proposalMembers?.some(index =>
    moon.clientProgramEffectInputsShareView(inputs, memberIndex, index) !==
      true)) {
    throw new TypeError('ForeignEffectProposalSource');
  }
  signal?.throwIfAborted();
  const localDefinition = checked(
    moon.clientProgramIssueCapturedEffectInputLocalResultDefinition(
      checkedOwner, inputs, memberIndex,
      contractLimits.maxWireBytes, contractLimits.maxNodes,
      contractLimits.maxDepth));
  const localResultDefinition = Object.freeze({
    identity: moon.clientProgramLocalEffectResultDefinitionCid(
      localDefinition),
    wire: moon.clientProgramLocalEffectResultDefinitionJson(localDefinition),
  });
  const localInvocationToken = checked(
    moon.clientProgramIssueCapturedEffectInputLocalInvocation(
      checkedOwner, inputs, memberIndex,
      contractLimits.maxWireBytes, contractLimits.maxNodes,
      contractLimits.maxDepth));
  const localInvocation = Object.freeze({
    identity: moon.clientProgramLocalEffectInvocationCid(
      localInvocationToken),
    wire: moon.clientProgramLocalEffectInvocationJson(
      localInvocationToken),
  });
  const localContext = Object.freeze({
    scopeCid: localEvidenceContext.scopeCid,
    effectiveDataPolicyCid: localEvidenceContext.effectiveDataPolicyCid,
    authorityScopeCid: localEvidenceContext.authorityScopeCid,
  });
  const proposalPlans = [];
  try {
    for (const index of proposalMembers ?? []) {
      proposalPlans.push(checked(moon.clientProgramEffectProposalBegin(
        inputs, index, proposalBounds.maxFields, proposalBounds.maxWork)));
    }
  } catch (error) {
    for (const plan of proposalPlans) {
      moon.clientProgramEffectProposalCancel(plan);
    }
    throw error;
  }
  let writer;
  try {
    writer = store.createPreparedObjectWriter(maxBytes);
  } catch (error) {
    for (const plan of proposalPlans) {
      moon.clientProgramEffectProposalCancel(plan);
    }
    throw error;
  }
  let sealed;
  let localResultArtifact;
  let byteCount = 0;
  const digest = createHash('sha256');
  try {
    const summary = await exportPinnedEffectInput({
      moon, execution, inputs, memberIndex, limits, signal,
      ...(onProposalRow === undefined ? {} : {
        canonicalRowLimits: {maxNodes: proposalBounds.maxNodes,
          maxDepth: proposalBounds.maxDepth,
          maxUtf16Units: proposalBounds.maxUtf16Units},
        onCanonicalRow: async (index, row) => {
          for (const [planIndex, proposalMemberIndex] of
            proposalMembers.entries()) {
            const projected = checked(moon.clientProgramEffectProposalRow(
              proposalPlans[planIndex], row, index,
              proposalBounds.maxFields, proposalBounds.maxWork,
              proposalBounds.maxBytes, proposalBounds.maxNodes,
              proposalBounds.maxDepth));
            await onProposalRow(proposalMemberIndex, index,
              Object.freeze({selectorWire: projected._0,
                changesWire: projected._1}));
          }
        },
      }),
      onReceipt: (input, receipt, importing) => {
        localResultArtifact = control.issueSourceFreeLocalEffectResultArtifact(
          checkedOwner, inputs, memberIndex, importing, localDefinition,
          localInvocationToken, receipt, retention, localContext,
          contractLimits);
        return control.issueEffectSourceArtifactFromExport(
          input, receipt, invocation, retention, sourceBindingCid,
          store.storeAuthorityCid, contractLimits);
      },
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
    for (const plan of proposalPlans) {
      checked(moon.clientProgramEffectProposalFinish(plan,
        summary.rowCount));
    }
    const physicalCid = `sha256:${digest.digest('hex')}`;
    sealed = await writer.seal(physicalCid);
    if (sealed.cid !== physicalCid || sealed.bytes !== byteCount) {
      throw new Error('EffectSourcePhysicalIdentityMismatch');
    }
    const payload = Object.freeze({
      summary,
      localResultDefinition,
      localInvocation,
      localResultArtifact,
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
  } finally {
    for (const plan of proposalPlans) {
      moon.clientProgramEffectProposalCancel(plan);
    }
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
