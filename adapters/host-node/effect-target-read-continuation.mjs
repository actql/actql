// Target-read approval is decided before any computation begins. The durable
// Checkpoint owner retains the submission and exact installed target inventory;
// this adapter neither retries a provider call nor owns another approval ledger.
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {recordCheckpointApproval} from '../host-common/checkpoint-approval.mjs';
import {ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {EFFECT_TARGET_CONTINUATION, effectTargetReadInventory} from
  './effect-target-read-inventory.mjs';

const same = (left, right) => canonicalValueJson(left, {dataKeys: true}) ===
  canonicalValueJson(right, {dataKeys: true});
const refusals = new WeakSet();
export const isEffectTargetReadRefusal = error => error !== null &&
  typeof error === 'object' && refusals.has(error);
const fail = code => {
  const error = Object.assign(new Error(code), {code});
  refusals.add(error);
  throw error;
};
const awaitingApproval = decision => decision.action === 'unsupported' &&
  decision.basis === 'delegate' && ['decision_function_not_configured',
    'checkpoint_journal_not_configured'].includes(decision.reason);

export function assertEffectTargetReadBinding(binding, expected) {
  if (binding?.version !== 'actql-effect-target-read-binding/0.1' ||
      binding.submission === null || typeof binding.submission !== 'object' ||
      !Array.isArray(binding.targets) || binding.targets.length === 0 ||
      !/^sha256:[0-9a-f]{64}$/u.test(binding.inventory_cid ?? '') ||
      expected !== undefined && !same(binding, expected)) {
    fail('EffectTargetBindingChanged');
  }
}

export async function effectTargetReadContinuation({checkpoints, runId,
  runDefinitionCid, unitId, declaredResults, submission, inventory,
  principalId, resume, signal, journalPort,
  allowDefer = true, assertCurrent = () => {}}) {
  if (checkpoints === undefined) fail('EffectTargetCheckpointUnavailable');
  submission = JSON.parse(canonicalValueJson(submission, {dataKeys: true}));
  const bound = effectTargetReadInventory(inventory);
  const states = bound.targets.map(target => ({target}));
  const savedRecords = await checkpoints.inspectEffectTargetApprovals(runId, runDefinitionCid);
  let live = true;
  let ready = false;
  let pendingTarget;
  let entered = false;
  const cleanupPending = () => states.some(state =>
    state.gate !== undefined && !state.released);
  const close = () => {
    // Revoke further use immediately, independently of physical completion.
    live = false;
    let failure;
    for (const state of states) {
      if (state.gate === undefined || state.released) continue;
      try {
        // Close-only gates must close synchronously and remain retryable on
        // false/throw. Full gates retain their existing cleanup owner.
        const recover = state.closeAttempted &&
          typeof state.gate.cleanup === 'function';
        state.closeAttempted = true;
        const result = recover ? state.gate.cleanup() : state.gate.close();
        state.released = result !== false &&
          (typeof state.gate.cleanupPending !== 'function' ||
            state.gate.cleanupPending() === false);
      } catch (error) { failure ??= error; }
    }
    if (failure !== undefined) throw failure;
    return !cleanupPending();
  };
  const approvalAt = checkpointCid => {
    try { return checkpoints.journal.committedApprovalAt(checkpointCid); }
    catch (error) {
      if (error?.code === 'ResolutionNotCommitted') fail('ResolutionNotCommitted');
      throw error;
    }
  };
  const current = () => {
    if (!live) fail('EffectTargetReadOwnerClosed');
    signal?.throwIfAborted();
    assertCurrent();
    resume?.assertCurrent();
  };
  const scopeCurrent = state => {
    current();
    if (state.checkpointCid !== undefined &&
        approvalAt(state.checkpointCid).current !== true) {
      fail('ApprovalExpired');
    }
  };
  const continuation = () => canonicalValueJson({version: EFFECT_TARGET_CONTINUATION,
    run_definition_cid: runDefinitionCid, unit_id: unitId,
    submission, inventory_cid: bound.inventoryCid, targets: bound.targets,
    pending_target: pendingTarget}, {dataKeys: true});
  const validate = saved => {
    if (saved?.version !== EFFECT_TARGET_CONTINUATION ||
        saved.run_definition_cid !== runDefinitionCid || saved.unit_id !== unitId ||
        saved.inventory_cid !== bound.inventoryCid || !same(saved.targets, bound.targets) ||
        !same(saved.submission, submission) || !Number.isSafeInteger(saved.pending_target) ||
        states[saved.pending_target] === undefined) fail('EffectTargetBindingChanged');
  };
  if (resume !== undefined) validate(resume.continuation);
  const port = resume === undefined ? journalPort : {...checkpoints.journal,
    persistCheckpoint: checkpoint => checkpoints.journal.completeResume(resume.claim, {checkpoint}),
  };
  try {
    for (const state of states) {
      state.gate = await checkpoints.effectTargetAuthorization({runId,
        runDefinitionCid, unitId, declaredResults, inventoryCid: bound.inventoryCid,
        target: state.target, continuation,
        beforeDefer() {
          current();
          if (!allowDefer) fail('EffectTargetReadRepeatDeferralUnsupported');
          pendingTarget = state.target.index;
        },
        ...(port === undefined ? {} : {journalPort: port}),
      });
    }
    for (const {view, continuation: saved} of savedRecords) {
      validate(saved);
      const state = states[saved.pending_target];
      if (view.requiredArtifact?.cid !== state.gate.scopeCid ||
          view.subject?.unit_id !== unitId || state.record !== undefined) {
        fail('EffectTargetBindingChanged');
      }
      state.record = view;
      if (view.closure === 'resolved') {
        // Currency and committed approval are checked below. A rejection is
        // never interpreted as permission, including after process restart.
        const approval = approvalAt(view.checkpointCid);
        if (approval.current !== true) fail('ApprovalExpired');
        state.checkpointCid = view.checkpointCid;
      }
    }
  } catch (error) {
    const errors = [];
    try { close(); } catch (failure) { errors.push(failure); }
    if (!cleanupPending()) throw error;
    // Construction has no returned owner. Transfer this same closure through
    // the dispatch owner's existing cleanup-handle protocol. Keep any cleanup
    // responsibility already attached to the primary construction failure.
    const earlier = error?.cleanupHandle;
    let earlierReleased = earlier === undefined && error?.cleanupPending !== true;
    const attachable = error !== null && typeof error === 'object' &&
      Object.isExtensible(error) && ['cleanupHandle', 'cleanupPending'].every(key => {
        const descriptor = Object.getOwnPropertyDescriptor(error, key);
        return descriptor === undefined || descriptor.writable === true;
      });
    const failure = attachable ? error
      : Object.assign(new Error('EffectTargetReadCleanupPending', {cause: error}),
        {code: error?.code ?? 'EffectTargetReadCleanupPending', primaryFailure: error});
    if (isEffectTargetReadRefusal(error)) refusals.add(failure);
    const status = () => Object.freeze({pending: cleanupPending() || !earlierReleased,
      errors: Object.freeze([...errors])});
    const handle = Object.freeze({status, async retry() {
      try { close(); } catch (failure) { errors.push(failure); }
      if (!earlierReleased) {
        try {
          if (typeof earlier?.retry !== 'function' ||
              typeof earlier?.status !== 'function') {
            throw new Error('EffectTargetReadCleanupOwnerMissing');
          }
          if (earlier.status().pending !== false) await earlier.retry();
          earlierReleased = earlier.status().pending === false;
        } catch (failure) { errors.push(failure); }
      }
      failure.cleanupPending = status().pending;
      return status();
    }});
    // Define own data fields so inherited setters/read-only fields cannot
    // intercept this handoff. Non-writable own metadata uses the wrapper.
    Object.defineProperties(failure, {
      cleanupHandle: {value: handle, writable: true},
      cleanupPending: {value: true, writable: true},
    });
    throw failure;
  }
  const owner = Object.freeze({
    inventoryCid: bound.inventoryCid,
    captureBinding: () => JSON.parse(canonicalValueJson({
      version: 'actql-effect-target-read-binding/0.1', submission,
      inventory_cid: bound.inventoryCid, targets: bound.targets}, {dataKeys: true})),
    enterComputation() {
      current();
      if (!ready) fail('EffectTargetReadNotPrepared');
      if (!entered && resume !== undefined) {
        const admission = states.find(state => state.admission !== undefined)?.admission;
        if (admission === undefined) fail('EffectTargetResumeAdmissionUnavailable');
        admission.enter();
        entered = true;
      }
    },
    async prepare() {
      for (const state of states) {
        current();
        const resumed = resume !== undefined &&
          resume.continuation.pending_target === state.target.index;
        let decision;
        if (resumed) {
          decision = await state.gate.resume({signal, resumption: {claim: {
            checkpointCid: resume.view.checkpointCid, claim: resume.claim}}});
          if (decision.action === 'dispatch') {
            state.checkpointCid = resume.view.checkpointCid;
            state.admission = decision.admission;
          }
        } else if (state.checkpointCid !== undefined) {
          scopeCurrent(state);
          decision = await state.gate.current({signal});
          if (awaitingApproval(decision)) {
            decision = {action: 'dispatch'};
          }
        } else {
          decision = await state.gate.authorize({signal});
        }
        if (decision.action === 'waiting') return {status: 'waiting_checkpoint',
          checkpoint: decision.checkpoint};
        current();
        if (isEffectTargetReadRefusal(decision.error)) throw decision.error;
        if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
        state.decision = decision;
      }
      ready = true;
      return {status: 'ready'};
    },
    async authorize(tuple, options = {}) {
      current();
      if (!ready) fail('EffectTargetReadNotPrepared');
      const state = states.find(item => same(item.target.readTuple, tuple));
      if (state === undefined) fail('EffectTargetBindingChanged');
      scopeCurrent(state);
      // Current account allow/deny remains authoritative. Only the exact
      // unsupported-delegation result can consume the retained read approval.
      const decision = await state.gate.current({signal: options.signal ?? signal});
      scopeCurrent(state);
      const delegated = awaitingApproval(decision);
      if (decision.action !== 'dispatch' &&
          !(delegated && (state.checkpointCid !== undefined ||
            state.decision?.basis === 'host_permit'))) return decision;
      return recordCheckpointApproval(Object.freeze({...decision,
        action: 'dispatch', basis: state.checkpointCid === undefined
          ? state.decision?.basis ?? decision.basis : 'resumed_approval', reason: undefined,
        boundary: 'acquisition', tuple: Object.freeze({...tuple}),
        subjectCid: state.gate.scopeCid}), {
        kind: 'effect_target', principalId, runDefinitionCid,
        configurationCid: state.gate.configurationCid,
        contextCid: state.gate.contextCid,
        inventoryCid: bound.inventoryCid, checkpointCid: state.checkpointCid,
        readTuple: state.target.readTuple, physicalBindings: state.target.physicalBindings,
        assertCurrent() { scopeCurrent(state); },
        enter() {
          scopeCurrent(state);
          if (!entered && resume !== undefined) {
            const admission = states.find(item => item.admission !== undefined)?.admission;
            if (admission === undefined) fail('EffectTargetResumeAdmissionUnavailable');
            admission.enter();
            entered = true;
          }
        },
      });
    },
    close,
    cleanup: close,
    cleanupPending,
  });
  return owner;
}
