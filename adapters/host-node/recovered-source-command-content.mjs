// Restore an acquired Source's saved Content through its original keyed Run,
// authenticated Command occurrence and existing physical Store holding. This
// path neither creates a generation nor reacquires a provider response.
import {issueStoredCapturedContent, consumeStoredContentOriginal,
  closeStoredContentReaders} from './generated-content-holding.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';

export function prepareRecoveredSourceCommandContent({publications, control,
  sourceOriginal, prepared, request, definition, captured, preview, invocation,
  source, store, principalId, ownerPrincipal, storeAuthorityCid, authorityScopeCid,
  now, authorize, binding, sourcePolicyCid, referenceLimits, memberIndex, row,
  inputName, referenceWire, assertCurrent, signal, limits, recoveryResources,
  sourceConstruction}) {
  if (principalId !== ownerPrincipal || store.storeAuthorityCid !== storeAuthorityCid ||
      typeof assertCurrent !== 'function' || typeof authorize !== 'function' ||
      typeof referenceWire !== 'string' || typeof sourceConstruction !== 'function' ||
      typeof recoveryResources?.constructCaptured !== 'function' ||
      binding?.effective_data_policy_cid !== sourcePolicyCid ||
      !Number.isFinite(Date.parse(binding?.expires_at))) {
    throw new TypeError('InvalidRecoveredSourceCommandContent');
  }
  const expiresAt = Date.parse(binding.expires_at);
  // The caller creates this child inside its already-funded metadata phase.
  // Later native phases quote this same complete spelling before allocation.
  const bindingWire = canonicalJson(binding);
  let stopping = false, released = false, attempted = false, flight, candidate, original, borrow;
  const readers = new Set();
  const available = () => !stopping && !released && store.status().closed === false &&
    Date.parse(now()) < expiresAt;
  const live = () => available() && authorize(principalId) === true && available();
  const fence = () => {
    const result = assertCurrent();
    if (result !== undefined) {
      if (result instanceof Promise) void result.catch(() => {});
      throw new TypeError('InvalidRecoveredContentCurrentFence');
    }
  };
  const current = () => {
    signal?.throwIfAborted();
    fence();
    if (!live()) throw new Error('RecoveredContentUnavailable');
    // Authority/current callbacks can retire this same child while returning
    // their prior decision. No old availability fact crosses that boundary.
    fence();
    signal?.throwIfAborted();
    if (!available()) throw new Error('RecoveredContentUnavailable');
  };
  const construct = (receiver, method, args, role) => {
    current();
    const value = sourceConstruction(receiver, method, args, bindingWire, role);
    current();
    return value;
  };
  const storedControl = Object.freeze({
    inspect: value => construct(control, control.inspect, [value], 'inspect'),
    issuer: (...args) => construct(control, control.issuer, args, 'issuer'),
    issue: (...args) => construct(control, control.issue, args, 'issue'),
  });
  const selected = value => {
    current();
    const retained = original, retainedBorrow = borrow;
    if (retained === undefined || retainedBorrow === undefined ||
        value !== retainedBorrow.binding || !retainedBorrow.current() ||
        !retainedBorrow.matchesIssued(retained.issued)) {
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
    storageCurrentForContent: (value, valueBinding) => selected(valueBinding) === value,
    consumeContent(value, accept) {
      const retained = selected(value);
      return consumeStoredContentOriginal({store, original: retained, readers, accept,
        assertCurrent() {
          if (selected(value) !== retained) throw new Error('OriginalEffectContentUnavailable');
        }});
    },
  });
  return Object.freeze({
    prepare() {
      if (attempted || stopping || released) throw new Error('RecoveredContentAlreadyAttempted');
      attempted = true;
      const operation = (async () => {
        current();
        const makeCandidate = () => {
          // Retain before either original constructor's success/current cut.
          candidate = control.recoveryCandidateForEffectOriginal(sourceOriginal,
            prepared, request, referenceWire, bindingWire, referenceLimits);
          return candidate;
        };
        recoveryResources.constructCaptured(captured, undefined,
          () => construct(undefined, makeCandidate, [], 'candidate'), undefined);
        const holdingCid = construct(control, control.holdingCid, [candidate], 'holding');
        const issued = await issueStoredCapturedContent({store, control: storedControl, candidate,
          holdingCid, workspaceScopeCid: authorityScopeCid,
          effectiveDataPolicyCid: sourcePolicyCid, available: live, authorize: live,
          limits: referenceLimits, retainOriginal(value) { original = value; }});
        current();
        const argument = {sourceOriginal, prepared, request, definition, captured,
          preview, invocation, source, storeAuthorityCid, memberIndex, row, inputName,
          candidate, issued, limits};
        const recover = value => {
          borrow = publications.recoverSourceEffectCommandContent(value);
          return borrow;
        };
        recoveryResources.constructCaptured(captured, undefined,
          value => construct(undefined, recover, [value], 'view'), argument);
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
      borrow = original = candidate = undefined;
      released = true;
      return true;
    },
    status: () => Object.freeze({pending: !released || flight !== undefined || readers.size !== 0}),
  });
}
