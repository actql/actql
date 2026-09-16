// Installed control-side reader capability. This delegates physical access to
// an already admitted process, not Compute admission or logical re-admission.
// Only completion custody constructs it with its private, exact record.
import {snapshotCompletionTask} from './completion-record.mjs';

export function createCompletionReader(entry, limits, available) {
  let identity, channel, stopped = false, used = false, sequence, borrow;
  const fail = code => { throw Object.assign(new Error(code), {code}); };
  const confirmStopped = () => {
    stopped = true;
    borrow?.confirmStopped();
    borrow = undefined;
  };
  const cleanupHandle = Object.freeze({
    status: () => ({pending: !!borrow}),
    async retry() {
      // A rejected settlement promise is not proof of process exit. The
      // installed channel's actual-exit state is an independent confirmation.
      if (channel?.status().exited === true) confirmStopped();
      return cleanupHandle.status();
    },
  });
  const invoke = async (request, signal, owner) => {
    if (!identity || stopped || owner?.session !== identity.session || owner?.run !== identity.run ||
        !Number.isSafeInteger(owner.sequence) || owner.sequence < 1) fail('ForeignCompletionReader');
    signal.throwIfAborted();
    if (request?.command === 'read-completion' &&
        Object.keys(request).sort().join(',') === 'command,taskIdentity') {
      if (used) fail('CompletionReaderConsumed');
      if (!available()) fail('RetainedUnavailable');
      const task = snapshotCompletionTask(request.taskIdentity, limits);
      if (JSON.stringify(task) !== JSON.stringify(entry.taskIdentity)) fail('ForeignCompletionTask');
      // No await between liveness, exact binding, and physical borrow. A
      // failed, unstarted validation remains correctable; once access begins
      // this capability can never start another read.
      borrow = entry.body.delegateRead(identity.session);
      used = true;
      sequence = owner.sequence;
      return Object.freeze({origin: entry.origin, taskIdentity: entry.taskIdentity,
        descriptor: entry.descriptor, lease: borrow.descriptor});
    }
    if (request?.command === 'verify-completion-read' &&
        Object.keys(request).sort().join(',') === 'command,report') {
      if (!borrow || sequence !== owner.sequence) fail('ForeignCompletionReadReport');
      const result = borrow.verify(request.report);
      if (!available()) fail('RetainedUnavailable');
      return result;
    }
    if (request?.command === 'finish-completion-read' &&
        Object.keys(request).sort().join(',') === 'command,report') {
      if (!borrow || sequence !== owner.sequence) fail('ForeignCompletionReadReport');
      // finish checks the exact physical terminal report before settling the
      // borrow. Even a revoked body may still need this release confirmation.
      const result = borrow.finish(request.report);
      borrow = undefined;
      if (!available()) fail('RetainedUnavailable');
      return result;
    }
    fail('InvalidCompletionReadRequest');
  };
  return Object.freeze({
    service: Object.freeze({invoke, cleanupHandle}),
    cleanupHandle,
    observe(value) {
      if (identity) fail('CompletionReaderAlreadyBound');
      const candidate = value.identity();
      if (candidate.run !== entry.origin.run || candidate.session === entry.origin.session ||
          typeof candidate.session !== 'string' || !candidate.session.length ||
          candidate.session.length > 256) fail('ForeignCompletionReader');
      if (!available()) fail('RetainedUnavailable');
      channel = value;
      identity = Object.freeze({...candidate});
      value.cleanupHandle.whenStopped().then(confirmStopped, () => {
        // Fail closed for new calls, retaining outstanding physical custody.
        stopped = true;
      });
    },
  });
}
