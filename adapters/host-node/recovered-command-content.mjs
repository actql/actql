// Restore the saved Command occurrence through the existing Content/Store
// owners. The parent retains this child before prepare; no provider, encoder,
// new holding, Model scope or replacement Run is opened.
import {restoreStoredGeneratedContentOriginal, consumeStoredContentOriginal,
  closeStoredContentReaders} from './generated-content-holding.mjs';

export function prepareRecoveredCommandContent({moon, publications, control,
  prepared, compiled, definition, captured, preview, invocation, source, store,
  principalId, ownerPrincipal, storeAuthorityCid, authorityScopeCid, now, authorize,
  installedBinding, referenceLimits, memberIndex, row, inputName, referenceWire,
  assertCurrent, signal, limits}) {
  if (principalId !== ownerPrincipal || store.storeAuthorityCid !== storeAuthorityCid ||
      typeof assertCurrent !== 'function' || typeof referenceWire !== 'string') {
    throw new TypeError('InvalidRecoveredCommandContent');
  }
  const plan = {compiled, runDefinition: definition};
  const expiresAt = JSON.parse(definition.wire).valid_until;
  const {graphPolicy, binding} = installedBinding(plan);
  let stopping = false, released = false, attempted = false, flight, original, borrow;
  const readers = new Set();
  const live = () => !stopping && !released && store.status().closed === false &&
    Date.parse(now()) < Date.parse(expiresAt) && authorize(principalId) === true;
  const current = () => {
    signal?.throwIfAborted();
    const result = assertCurrent();
    if (result !== undefined) {
      if (result instanceof Promise) void result.catch(() => {});
      throw new TypeError('InvalidRecoveredContentCurrentFence');
    }
    if (!live()) throw new Error('RecoveredContentUnavailable');
  };
  const selected = value => {
    current();
    const retained = original, retainedBorrow = borrow;
    if (retained === undefined || retainedBorrow === undefined || value !== retainedBorrow.binding ||
        !retainedBorrow.current() || !retainedBorrow.matchesIssued(retained.issued)) {
      throw new Error('OriginalEffectContentUnavailable');
    }
    current();
    if (retained !== original || retainedBorrow !== borrow || stopping) {
      throw new Error('OriginalEffectContentUnavailable');
    }
    return retained;
  };
  const contentOwner = Object.freeze({
    storageForContent: selected,
    storageCurrentForContent: (value, binding) => selected(binding) === value,
    consumeContent(value, accept) {
      const retained = selected(value);
      return consumeStoredContentOriginal({store, original: retained, readers, accept,
        assertCurrent() {
          if (selected(value) !== retained) throw new Error('OriginalEffectContentUnavailable');
        }});
    },
  });
  const child = Object.freeze({
    prepare() {
      if (attempted || stopping || released) throw new Error('RecoveredContentAlreadyAttempted');
      attempted = true;
      const operation = (async () => {
        current();
        const candidate = control.recoveryCandidate(referenceWire, binding, referenceLimits);
        const description = control.inspect(candidate);
        const count = publications.capturedContentGenerationCount(captured);
        if (!Number.isSafeInteger(count) || count < 1 || count > 32) {
          throw new TypeError('InvalidRecoveredContentInventory');
        }
        let generationIndex;
        for (let index = 0; index < count; index++) {
          current();
          const occurrence = publications.capturedContentGenerationStorage(
            captured, definition, storeAuthorityCid, index);
          if (occurrence.manifestCid !== description.identity) continue;
          if (generationIndex !== undefined) throw new Error('AmbiguousRecoveredContentOccurrence');
          generationIndex = index;
        }
        if (generationIndex === undefined) throw new Error('OriginalEffectContentUnavailable');
        const issued = await restoreStoredGeneratedContentOriginal({store, publications, control,
          capturedRun: captured, runDefinition: definition, index: generationIndex, candidate,
          workspaceScopeCid: authorityScopeCid, effectiveDataPolicyCid: graphPolicy.cid,
          available: live, authorize: () => live(), assertCurrent: current,
          limits: referenceLimits, readers, signal,
          retainOriginal(value) { original = value; }});
        current();
        borrow = publications.recoverEffectCommandContent({compiled, prepared, definition,
          captured, preview, invocation, source, storeAuthorityCid, generationIndex,
          memberIndex, row, inputName, candidate, issued, limits});
        current();
        selected(borrow.binding);
        return Object.freeze({borrow, contentOwner});
      })();
      flight = operation;
      return operation.finally(() => { if (flight === operation) flight = undefined; });
    },
    async release() {
      stopping = true;
      if (flight !== undefined || !await closeStoredContentReaders(readers)) return false;
      borrow?.release();
      borrow = original = undefined;
      released = true;
      return true;
    },
    status: () => Object.freeze({pending: !released || flight !== undefined || readers.size !== 0}),
  });
  return child;
}
