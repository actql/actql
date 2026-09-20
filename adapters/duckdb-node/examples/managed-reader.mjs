// Installed, one-shot reader and retained completion re-admission. No source
// acquisition, Compute rerun, or failed-Program continuation is performed.
import {serveManagedExecution} from '../../host-node/worker-channel.mjs';
import {emptyProcessUsage} from '../../host-node/process-accounting.mjs';
import {checked} from '../../host-common/runtime-result.mjs';
import {snapshotCompletionTask} from '../../host-node/completion-record.mjs';
import {prepareProcessReadmission} from '../../host-node/process-readmission.mjs';
import {consumeDelegatedFile} from '../../store-local/delegated-reader.mjs';
import {createMoonBitRetainedRowFrames} from '../../store-local/moonbit-row-frames.mjs';
import {registerRetainedInput, consumeRetainedInput} from '../../store-local/representations.mjs';
import {prepareExampleText} from './physical-strategy.mjs';
import {retainedReaderPolicy} from './reader-policy.mjs';
import * as budget from '../../../_build/js/release/build/process_host_bridge/process_host_bridge.js';
import * as content from '../../../_build/js/release/build/retained_host_bridge/retained_host_bridge.js';

let ledger, used = false;
async function readContent(input, signal, context, progress) {
  if (used || !context.resourceLimits) throw Error('ContentReaderUnavailable');
  used = true;
  ledger = checked(budget.processLedgerCreate(context.resourceLimits));
  const policy = retainedReaderPolicy(input.application.dataProfile);
  const {columns, recordLimits} = policy;
  const plan = await prepareExampleText(input.application, context.resourceLimits);
  if (!Number.isSafeInteger(input.task) || input.task < 1) throw Error('InvalidContentTask');
  const suppliedTask = plan.taskIdentities()[input.task - 1];
  if (!suppliedTask) throw Error('InvalidContentTask');
  const taskIdentity = snapshotCompletionTask(suppliedTask, recordLimits);
  let consumerRequest;
  if (input.consumer !== undefined) {
    const {task, port} = input.consumer ?? {};
    if (!Number.isSafeInteger(task) || task < 1 || !Number.isSafeInteger(port) || port < 0 ||
        Object.keys(input.consumer).sort().join(',') !== 'port,task') throw Error('InvalidConsumerPort');
    const consumerTask = plan.taskIdentities()[task - 1];
    if (!consumerTask?.inputs.some(edge => edge.input === port && edge.producer === input.task &&
        !edge.producer_target_is_input && edge.producer_target_index === taskIdentity.output_step)) {
      throw Error('ForeignConsumerPort');
    }
    consumerRequest = Object.freeze({task, port});
  }
  signal.throwIfAborted();
  progress.stage = 'custody';
  const handoff = await context.callHost({command: 'read-completion', taskIdentity});
  signal.throwIfAborted();
  // A file lease is still provisional. Reserve before opening/allocating the
  // bounded parser, charge each received chunk, and verify complete framing.
  let reservation, frames, reading, admission, readUnconfirmed = false;
  try {
    progress.stage = 'reservation';
    // This diagnostic performs admission, then an actual consumer-format read.
    // Reserve both transfers up front; a successful admission does not make the
    // subsequent access free. They are serial and share bounded scratch only.
    reservation = checked(budget.processReadReserve(ledger,
      BigInt(handoff.descriptor.bytes) * (consumerRequest ? 2n : 1n),
      policy.scratchBytes));
    progress.stage = 'content-contract';
    reading = plan.contentRead(input.task, handoff.descriptor);
    admission = prepareProcessReadmission(plan.completionPreparation(input.task), taskIdentity,
      handoff, context, signal, recordLimits);
    frames = createMoonBitRetainedRowFrames(content, policy.frameLimits, row => {
      checked(content.retainedContentAppend(reading, row, policy.decodeLimits));
    });
    progress.stage = 'read';
    readUnconfirmed = true;
    const report = await consumeDelegatedFile(handoff.lease, async chunk => {
      checked(budget.processReadCharge(ledger, reservation, BigInt(chunk.byteLength)));
      await frames.feed(chunk, signal);
    }, signal);
    readUnconfirmed = false;
    const usage = frames.finish();
    progress.stage = 'identity';
    const receipt = checked(content.retainedContentFinish(reading));
    progress.stage = 'readmission';
    const output = await admission.admit(receipt, report);
    progress.stage = 'completion-evidence';
    plan.completionTask(input.task, output); // Exact newly checked owner/target.
    const evidence = checked(content.retainedCompletionEvidence(output, 2, columns));
    const verified = content.retainedCompletionDescriptor(evidence);
    let producerBound = false;
    let producerReadBytes = 0;
    if (consumerRequest) {
      progress.stage = 'producer-binding';
      const {task, port} = consumerRequest;
      const read = plan.bindReadmittedOutput(input.task, task, port, output);
      producerBound = admission.readable(read);
      if (!producerBound) throw Error('ReadmittedProducerUnavailable');
      const material = content.retainedCompletionMaterial(evidence, output);
      if (!material) throw Error('ReadmittedMaterialUnavailable');
      // Keep the original physical borrow until all reads finish. A lease is
      // not a task-start permit; registration only connects an exactly admitted
      // ProducerRead to the shared physical access contract.
      registerRetainedInput(material, admission.readable, {
        async consume(accept, readSignal) {
          readUnconfirmed = true;
          await consumeDelegatedFile(handoff.lease, async chunk => {
            checked(budget.processReadCharge(ledger, reservation, BigInt(chunk.byteLength)));
            await accept(chunk);
          }, readSignal);
          readUnconfirmed = false;
        },
      }, {wire: policy.wire,
        maxFrameBytes: handoff.lease.maxFrameBytes});
      progress.stage = 'producer-read';
      // Exercise the same Store access used by Local and DuckDB, rather than
      // treating successful binding as evidence that a consumer can read bytes.
      await consumeRetainedInput(material, read, chunk => {
        producerReadBytes += chunk.byteLength;
      }, signal);
      if (producerReadBytes !== verified.bytes) throw Error('ReadmittedReadSizeMismatch');
    }
    await context.callHost({command: 'finish-completion-read', report});
    signal.throwIfAborted();
    return {kind: 'completion-readmitted', program_success: false, pid: process.pid,
      rows: usage.rows, bytes: usage.bytes, rows_cid: verified.rows_cid,
      producer_bound: producerBound, producer_read_bytes: producerReadBytes};
  } finally {
    admission?.close();
    frames?.cancel();
    if (reading) content.retainedContentCancel(reading);
    // Success confirms fd close. An exception (including close failure) is not
    // stop evidence: preserve the reservation until the parent observes actual
    // process exit and settles the delegated envelope. Do not retry the read.
    if (reservation && !readUnconfirmed) checked(budget.processStopped(ledger, reservation));
  }
}

serveManagedExecution(async (input, signal, context) => {
  const progress = {stage: 'prepare'};
  try {
    return await readContent(input, signal, context, progress);
  } catch (error) {
    const stage = progress.stage;
    throw Object.assign(new Error(`ContentReader:${stage}`, {cause: error}), {code: `ContentReader:${stage}`});
  }
}, {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64}, {
  accounting: () => ledger ? budget.processLedgerUsage(ledger) : emptyProcessUsage(),
});
