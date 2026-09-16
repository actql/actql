// Installed local-process assembly, not an execution option or public verifier
// factory. Custody owns the original completion; this runtime owns the exact
// admitted receipt and its receiving scope. IPC never supplies callbacks.
import {checked} from '../host-common/runtime-result.mjs';
import {completionRecordLimits, snapshotCompletionDescriptor, snapshotCompletionTask} from './completion-record.mjs';
import * as runtime from '../../_build/js/release/build/retained_host_bridge/retained_host_bridge.js';

const defaultLimits = Object.freeze({maxCompletions: 4, maxInputs: 2, maxColumns: 10});
const fail = code => { throw Object.assign(new Error(code), {code}); };

export function prepareProcessReadmission(preparation, expectedTask, handoff, context, signal,
  suppliedLimits = defaultLimits) {
  // Installed receiving profile, never inferred from the supplied descriptor.
  // Snapshot it before any custody acknowledgement can yield control.
  const limits = completionRecordLimits(suppliedLimits);
  signal.throwIfAborted();
  const task = snapshotCompletionTask(expectedTask, limits);
  const actualTask = snapshotCompletionTask(handoff?.taskIdentity, limits);
  const descriptor = snapshotCompletionDescriptor(handoff?.descriptor, limits);
  const origin = Object.freeze({...handoff?.origin});
  const lease = Object.freeze({...handoff?.lease});
  if (JSON.stringify(task) !== JSON.stringify(actualTask) ||
      task.task !== origin.task || descriptor.output_step !== task.output_step ||
      descriptor.input_count !== task.inputs.length ||
      origin.run !== context.run || typeof origin.session !== 'string' || !origin.session.length ||
      origin.session === context.session || !Number.isSafeInteger(origin.request) || origin.request < 1 ||
      typeof origin.output !== 'string' || !origin.output.length || origin.output.length > 256 ||
      lease.session !== context.session || lease.bytes !== descriptor.bytes || lease.cid !== descriptor.rows_cid ||
      typeof context.callHost !== 'function') fail('ForeignCompletionHandoff');
  const callHost = context.callHost;
  let live = true, used = false, accepted;
  const permitted = () => live && !signal.aborted;
  // The callback is fixed here and checks exact opaque receipt identity. It is
  // enabled only by this installed channel's verified custody response below.
  const installed = checked(runtime.retainedReadmissionInstall(preparation, descriptor,
    receipt => permitted() && accepted === receipt, permitted));
  return Object.freeze({
    async admit(receipt, report) {
      if (used || !permitted()) fail('CompletionReadmissionUnavailable');
      used = true;
      if (!report || report.version !== lease.version || report.session !== lease.session ||
          report.token !== lease.token || report.bytes !== lease.bytes || report.cid !== lease.cid) {
        fail('ForeignCompletionReadReport');
      }
      const confirmed = await callHost({command: 'verify-completion-read', report});
      signal.throwIfAborted();
      if (!live || !confirmed || Object.keys(confirmed).sort().join(',') !== 'bytes,cid' ||
          confirmed.bytes !== descriptor.bytes || confirmed.cid !== descriptor.rows_cid) {
        fail('ForeignCompletionReadAcknowledgement');
      }
      accepted = receipt;
      try { return checked(runtime.retainedReadmissionComplete(installed, receipt)); }
      catch (error) { live = false; throw error; }
    },
    readable: input => permitted() && runtime.retainedReadmissionReadable(installed, input),
    close() {
      live = false;
      accepted = undefined;
      runtime.retainedReadmissionClose(installed);
    },
  });
}
