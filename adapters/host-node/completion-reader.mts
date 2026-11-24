// Installed control-side reader capability. This delegates physical access to
// an already admitted process, not Compute admission or logical re-admission.
// Only completion custody constructs it with its private, exact record.
import {snapshotCompletionTask} from './completion-record.mjs';
import type {completionRecordLimits, snapshotCompletionDescriptor} from './completion-record.mjs';
import type {DelegatedReadLease} from '../store-local/files.mjs';

type CompletionSession = Readonly<{session: string; run: string}>;
export type CompletionCall = CompletionSession & Readonly<{sequence: number}>;
export type CompletionChannel = Readonly<{
  identity: () => CompletionSession;
  cleanupHandle: Readonly<{whenStopped: () => Promise<unknown>}>;
}>;
type ReaderChannel = CompletionChannel & Readonly<{status: () => Readonly<{exited?: boolean}>}>;
type CompletionReadRequest = Readonly<{command?: unknown; taskIdentity?: unknown; report?: unknown}>;
// These ports synchronously return DATA from the existing delegated file.
export type CompletionReadLease = Pick<DelegatedReadLease, 'session' | 'bytes' | 'cid'> &
  Readonly<{token: string; then?: never}>;
type CompletionReadReport = Pick<DelegatedReadLease, 'bytes' | 'cid'> & Readonly<{then?: never}>;
type ReadBorrow<Lease extends CompletionReadLease> = Readonly<{
  descriptor: Lease;
  verify: (report: unknown) => CompletionReadReport;
  finish: (report: unknown) => CompletionReadReport;
  confirmStopped: () => boolean | void;
}>;
export type CompletionBody<Lease extends CompletionReadLease> = Readonly<{
  cid: string;
  bytes: number;
  available: () => boolean;
  delegateRead: (session: string) => ReadBorrow<Lease>;
}>;
export type CompletionEntry<Lease extends CompletionReadLease> = Readonly<{
  origin: CompletionSession & Readonly<{request: number; task: number; output: string}>;
  body: CompletionBody<Lease>;
  descriptor: ReturnType<typeof snapshotCompletionDescriptor>;
  taskIdentity: ReturnType<typeof snapshotCompletionTask>;
}>;

export function createCompletionReader<Lease extends CompletionReadLease>(entry: CompletionEntry<Lease>,
  limits: ReturnType<typeof completionRecordLimits>, available: () => boolean) {
  let identity: CompletionSession | undefined, channel: ReaderChannel | undefined,
    stopped = false, used = false, sequence: number | undefined, borrow: ReadBorrow<Lease> | undefined;
  const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
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
  const invoke = async (request: CompletionReadRequest | null | undefined, signal: AbortSignal, owner: CompletionCall) => {
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
    observe(value: ReaderChannel) {
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
