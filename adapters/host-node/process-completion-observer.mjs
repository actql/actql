// Installed local execution wiring, never loaded from a Program or IPC URL.
import {installCompletionObserver} from '../host-common/completion-observer.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {retainedStorageBody} from '../store-local/representations.mjs';
import {processStoreContext} from '../store-local/process-binding.mjs';
import {processRetainedBodyIdentity} from '../store-local/process-client.mjs';
import {completionRecordLimits, snapshotCompletionDescriptor, snapshotCompletionTask} from './completion-record.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/retained_host_bridge/retained_host_bridge.js', import.meta.url);

export async function installProcessCompletionObserver(binding, options, completionTask) {
  const context = processStoreContext(binding);
  const limits = completionRecordLimits(options);
  if (typeof completionTask !== 'function') throw new TypeError('MissingCompletionTaskProjection');
  const runtime = await import(runtimeUrl.href);
  let delivered = 0;
  return installCompletionObserver(async ({task, output}) => {
    if (delivered >= limits.maxCompletions) throw new Error('CompletionRecordLimit');
    const evidence = checked(runtime.retainedCompletionEvidence(output, limits.maxInputs, limits.maxColumns));
    const descriptor = snapshotCompletionDescriptor(runtime.retainedCompletionDescriptor(evidence), limits);
    const taskIdentity = snapshotCompletionTask(completionTask(task, output), limits);
    if (taskIdentity.task !== task || taskIdentity.output_step !== descriptor.output_step ||
        taskIdentity.inputs.length !== descriptor.input_count) throw new Error('ForeignCompletionTask');
    const material = runtime.retainedCompletionMaterial(evidence, output);
    if (material == null) throw new Error('RetainedCompletionUnavailable');
    const body = retainedStorageBody(material);
    const physical = processRetainedBodyIdentity(body, binding);
    if (physical.cid !== descriptor.rows_cid || physical.bytes !== descriptor.bytes) {
      throw new Error('ForeignCompletionHolding');
    }
    const receipt = await context.callHost({command: 'retain-completion', task,
      output: physical.output, descriptor, taskIdentity});
    if (!receipt || Object.keys(receipt).join(',') !== 'task' || receipt.task !== task) {
      throw new Error('ForeignCompletionReceipt');
    }
    delivered++;
    // Source-port revocation cannot grant another handoff. Any custody already
    // accepted is independently owned by the surviving Host, not forgotten on
    // a failed reply/cancellation. It remains non-public internal task evidence.
    if (!runtime.retainedCompletionCanHandoff(evidence, output)) throw new Error('RetainedCompletionUnavailable');
  });
}
