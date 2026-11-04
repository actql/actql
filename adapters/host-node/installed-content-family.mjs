// Physical I/O for the original Effect task's common Content child. The child
// owns ordering, encoding and work; this port only appends its exact pieces to
// the existing Store and retains the resulting generation evidence.
import {issueStoredGeneratedContent, retainGeneratedContentEvidence,
  consumeStoredContentOriginal, closeStoredContentReaders} from './generated-content-holding.mjs';

export function installEffectContentFamily({moon, control, publications, bodies,
  prepared, plan, store, principalId, ownerPrincipal, now, authorize, signal,
  namespaceId, authorityScopeCid, storeAuthorityCid, installedBinding,
  referenceLimits, completionLimits, outputLimits, faultInjection, restored, retainCleanup, managedOriginal}) {
  if (retainCleanup !== undefined && typeof retainCleanup !== 'function') {
    throw new TypeError('InvalidInstalledContentCleanupRetention');
  }
  if (principalId !== ownerPrincipal || store.storeAuthorityCid !== storeAuthorityCid) {
    throw new TypeError('InvalidInstalledContentFamily');
  }
  const definition = JSON.parse(plan.runDefinition.wire);
  const sourceFree = moon.clientProgramEffectAcquisitionCount?.(prepared) === 0;
  const compiledLimits = publications.checkedClientSerializationGenerationLimits(
    plan.compiled, plan.serializationGraph);
  // These are the existing installed Local execution ceilings, not sampled
  // Source sizes. Authored generation bounds further constrain the encoder.
  const inputRows = managedOriginal?.inputRows;
  if (inputRows !== undefined && (!Number.isSafeInteger(inputRows) || inputRows < 0)) {
    throw new TypeError('Invalid Content input row bound');
  }
  const output = Object.freeze({...outputLimits,
    maxRows: Math.min(100, compiledLimits.maxRows, inputRows ?? compiledLimits.maxRows),
    maxValueNodes: 10000, maxValueTextBytes: 10000,
    maxWireBytes: 1000000, maxWireNodes: 10000,
    maxLogicalWireBytes: 1000000, maxLogicalWireNodes: 10003});
  const generationLimits = Object.freeze({maxRows: output.maxRows,
    maxBytes: Math.min(10000, compiledLimits.maxBytes),
    maxValueNodes: 10000, maxValueDepth: 64, maxFrames: 100});
  const contractLimits = Object.freeze({maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64});
  let active, capturedProof, writer, physical, byteHolding, retained, generation, recovery, storedOriginal;
  let cancelled = false, cleaned = false, durable = false, flight;
  let bound = managedOriginal === undefined;
  if (restored !== undefined) {
    if (restored.completion === undefined) throw new TypeError('ContentRecoveryCompletionMissing');
    generation = restored.generation;
    recovery = restored.recovery;
    storedOriginal = restored.storedOriginal;
    durable = true;
  }
  let failureCleanup;
  const contentReaders = new Set();
  const retirement = new Map();
  const live = () => !cancelled && store.status().closed === false &&
    Date.parse(now()) < Date.parse(definition.valid_until) && authorize(principalId) === true;
  // Keep the original issuance/confirmed holding with this generation, not a
  // wire-to-Reference index. Temporary encoder cleanup does not retire durable
  // Content; abandoned generation cleanup still owns its physical holdings.
  const selectedForContent = binding => {
    const original = storedOriginal;
    const current = () => durable && !cancelled && flight === undefined &&
      signal?.aborted !== true && original !== undefined && storedOriginal === original;
    if (binding === undefined || !current() || !live() || !current() ||
        typeof moon.clientProgramEffectCommandContentMatchesIssued !== 'function') return undefined;
    const matched = moon.clientProgramEffectCommandContentMatchesIssued(binding, original.issued);
    // Both the typed matcher and Host authority may invoke a current callback.
    // A prior match cannot hand off a retired/cancelled original occurrence.
    if (!current() || !live() || !current()) return undefined;
    return matched === true ? original : undefined;
  };
  const port = Object.freeze({
    cancel() { cancelled = true; return true; },
    stopped: () => flight === undefined,
    cleanup: () => cleaned,
  });
  const releaseTemporary = async () => {
    if (physical?.prepared.status().pending === true) await physical.prepared.release();
    if (physical?.prepared.status().pending === true) return false;
    if (writer !== undefined) {
      await writer.cancel();
      const status = writer.status();
      if (status.reservationHeld || status.custodyPending || status.cleanupPending) return false;
    }
    return true;
  };
  const cleanup = async () => {
    // Successful encoder cleanup may precede this explicit parent close. It
    // must not let the completed temporary-duty flag preserve a new borrower.
    cancelled = true;
    if (!await closeStoredContentReaders(contentReaders)) return false;
    if (cleaned) {
      storedOriginal = undefined;
      return true;
    }
    if (flight !== undefined) await flight.catch(() => {});
    if (cleaned) {
      storedOriginal = undefined;
      return true;
    }
    if (failureCleanup !== undefined) {
      if ((await failureCleanup.retry()).pending) return false;
      failureCleanup = undefined;
    }
    if (!await releaseTemporary()) return false;
    // Durable generation bytes retain their declared lifetime through approval.
    // Only an abandoned, unpublished generation is retired by its original
    // holdings; an uncertain retirement keeps those exact handles for retry.
    if (!durable) {
      for (const holding of retained?.holdings ?? []) await holding.abort();
      for (const cid of [byteHolding?.holding_cid,
        ...(retained?.bindings ?? []).map(binding => binding.holdingCid)].filter(Boolean)) {
        let child = retirement.get(cid);
        if (child === undefined) {
          child = (await store.retirePhysicalHolding(cid)).cleanup;
          retirement.set(cid, child);
        }
        if (child.status().pending) await child.retry();
        if (child.status().pending) return false;
      }
    }
    // Retire this family's selection alias, not the durable Store holding or
    // any escaped original/borrower still retained by its existing owner.
    storedOriginal = undefined;
    cleaned = true;
    return true;
  };
  // The existing parent retains this family's actual cleanup before the
  // fallible provider constructor. A thrown constructor cannot erase its duty.
  const cleanupOwner = Object.freeze({close: cleanup, cleanup,
    cleanupPending: () => !cleaned});
  retainCleanup?.(cleanupOwner);
  const selectedProvider = control.effectFamily(prepared, plan.serializationGraph, bodies,
    {generation: generationLimits, reference: referenceLimits, contract: contractLimits,
      output, identitySlots: 4 * output.maxWireNodes + 8 * output.maxColumns}, port,
    step => {
      if (!bound || active !== undefined) return false;
      active = step;
      return true;
    }, restored?.completion, managedOriginal);
  const provider = managedOriginal === undefined ? selectedProvider : selectedProvider.provider;
  return Object.freeze({provider,
    ...(managedOriginal === undefined ? {} : {
      preparation: selectedProvider.preparation,
      bindExecution(original) {
        if (bound || cancelled || original.prepared !== prepared || original.plan !== plan ||
            original.store !== store || original.principalId !== principalId) {
          throw new TypeError('ForeignInstalledContentFamily');
        }
        signal = original.signal; bound = true;
      },
    }),
    prepareLedger(sourceCapacity, additionalProviders = []) {
      if (!Array.isArray(additionalProviders)) throw new TypeError('Invalid Content family providers');
      const ledger = moon.clientProgramPrepareFamilyEffectCaptureLedger(prepared,
        sourceCapacity.capacity, sourceCapacity.transferBytes, sourceCapacity.executionBytes,
        bodies.registry, bodies.values, bodies.fragment, bodies.ordered,
        [provider, ...additionalProviders]);
      if (ledger === undefined) throw new TypeError('Content acquisition capacity unavailable');
      return ledger;
    },
    bindCapture(captured, observation) {
      if (sourceFree) throw new TypeError('ForeignSourceFreeContentCapture');
      if (capturedProof !== undefined) throw new TypeError('Content capture already bound');
      capturedProof = publications.bindCheckedClientEffectSerializationCapture(
        plan.compiled, prepared, captured, observation);
    },
    async handlePause(boundary) {
      if (restored !== undefined) throw new TypeError('RestoredContentCannotGenerate');
      if (flight !== undefined || cancelled || !live() || active === undefined ||
          (!sourceFree && capturedProof === undefined) || boundary.status !== 'settling') {
        throw new TypeError('InvalidContentPause');
      }
      const operation = (async () => {
        signal?.throwIfAborted();
        if (boundary.slot === 0) {
          const pending = control.familyPendingPiece(active);
          if (pending === undefined) throw new Error('ContentPieceUnavailable');
          writer ??= store.createPreparedObjectWriter(generationLimits.maxBytes);
          await writer.append(pending.piece);
          await faultInjection?.('effect_content_piece_appended',
            {revision: pending.revision, byteCount: pending.piece.length, signal});
          signal?.throwIfAborted();
          if (!live() || !control.familyAcknowledgePiece(active, pending.revision)) {
            throw new Error('ContentPieceAcknowledgementRejected');
          }
          return {action: 'resume'};
        }
        if (boundary.slot !== 1 || generation !== undefined) throw new Error('ContentCompletionMismatch');
        const input = control.familyInput(active);
        const evidence = publications.bindCheckedClientSerializationInputIdentity(
          plan.compiled, input.input, input.receipt, contractLimits, capturedProof);
        const completion = control.familyByteCompletion(active);
        const {graphPolicy, binding} = installedBinding(plan);
        const candidate = control.candidate(input.encoder, binding, referenceLimits);
        const description = control.inspect(candidate);
        // Empty encodings still own a real zero-byte Store object.
        writer ??= store.createPreparedObjectWriter(generationLimits.maxBytes);
        physical = await writer.seal(completion.contentCid);
        byteHolding = {version: 'actql-local-physical-holding/0.1', namespace: 'content',
          holding_cid: publications.checkedClientSerializationByteHoldingCid(
            plan.compiled, plan.runDefinition, storeAuthorityCid),
          manifest_cid: description.identity, objects: [{cid: physical.cid, byte_count: physical.bytes}]};
        await store.commitPhysicalHolding(byteHolding, [physical.prepared]);
        const content = await issueStoredGeneratedContent({store, control, candidate,
          holdingCid: byteHolding.holding_cid, workspaceScopeCid: authorityScopeCid,
          effectiveDataPolicyCid: graphPolicy.cid, available: live,
          authorize: () => live(), limits: referenceLimits,
          retainOriginal: original => { storedOriginal = original; }});
        signal?.throwIfAborted();
        generation = control.familyComplete(plan.compiled, plan.runDefinition, active,
          evidence, candidate, content, live, completionLimits);
        const completionRecord = publications.exportCheckedClientContentGenerationOutput(
          plan.compiled, plan.runDefinition, generation, storeAuthorityCid);
        await retainGeneratedContentEvidence({store, publications, compiled: plan.compiled,
          generation, signal, retainHoldings(_holdings, recovery) { retained = recovery; }});
        recovery = Object.freeze({referenceWire: description.wire,
          binding: Object.freeze({...binding}), byteHoldingCid: byteHolding.holding_cid,
          bindings: Object.freeze(retained.bindings.map(value => Object.freeze({...value}))),
          completion: completionRecord});
        durable = true;
        await faultInjection?.('effect_content_generation_retained',
          {holdingCid: byteHolding.holding_cid, contentCid: completion.contentCid,
            completion: completionRecord});
        if (!await releaseTemporary()) throw new Error('ContentPhysicalCleanupPending');
        cleaned = true;
        return {action: 'resume'};
      })();
      flight = operation;
      try { return await operation; }
      catch (error) {
        if (error?.cleanupPending === true && error.cleanupHandle !== undefined) {
          failureCleanup = error.cleanupHandle;
        }
        throw error;
      } finally { if (flight === operation) flight = undefined; }
    },
    generation: () => durable ? generation : undefined,
    recovery: () => durable ? recovery : undefined,
    issuedForContent: binding => selectedForContent(binding)?.issued,
    storageForContent: binding => selectedForContent(binding),
    storageCurrentForContent: (original, binding) => original !== undefined &&
      selectedForContent(binding) === original,
    consumeContent(binding, accept) {
      const original = selectedForContent(binding);
      if (original === undefined) throw new Error('OriginalEffectContentUnavailable');
      return consumeStoredContentOriginal({store, original, readers: contentReaders, accept,
        assertCurrent() {
          if (selectedForContent(binding) !== original) throw new Error('OriginalEffectContentUnavailable');
        }});
    },
    ...cleanupOwner,
  });
}
