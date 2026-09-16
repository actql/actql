// Surviving control-side custody of internal task completion facts. Only the
// exact installed execution session can deliver them, separately from Store
// sealing. A record is not permission to run a consumer or publish a Result.
import {completionRecordLimits, snapshotCompletionDescriptor, snapshotCompletionTask} from './completion-record.mjs';
import {createCompletionReader} from './completion-reader.mjs';

export function createProcessCompletionCustody(store, options, expectedTasks) {
  const limits = completionRecordLimits(options);
  if (!Array.isArray(expectedTasks) || expectedTasks.length === 0 || expectedTasks.length > limits.maxCompletions) {
    throw new TypeError('InvalidCompletionTaskSet');
  }
  const expected = new Map();
  for (const supplied of expectedTasks) {
    const task = snapshotCompletionTask(supplied, limits);
    if (expected.has(task.task)) throw new TypeError('InvalidCompletionTaskSet');
    expected.set(task.task, task);
  }
  const expectedProgram = expected.values().next().value;
  for (const task of expected.values()) {
    if (task.program_definition_cid !== expectedProgram.program_definition_cid ||
        task.program_parameters_cid !== expectedProgram.program_parameters_cid ||
        task.inputs.some(input => input.producer !== 0 && !expected.has(input.producer)) ||
        task.controls.some(prior => prior !== 0 && !expected.has(prior))) {
      throw new TypeError('InvalidCompletionTaskSet');
    }
  }
  if (typeof store?.service?.invoke !== 'function' || typeof store.observe !== 'function' ||
      typeof store.body !== 'function' || typeof store.close !== 'function') {
    throw new TypeError('InvalidCompletionStore');
  }
  const entries = new Map(), bodies = new Set(), records = new WeakMap();
  let identity, stopped = false, closed = false;
  const fail = code => { throw Object.assign(new Error(code), {code}); };
  const exact = owner => {
    if (!identity || closed || stopped || owner?.session !== identity.session || owner?.run !== identity.run) {
      fail('ForeignCompletionSession');
    }
  };
  const invoke = async (request, signal, owner) => {
    exact(owner);
    signal.throwIfAborted();
    if (request?.command !== 'retain-completion') return store.service.invoke(request, signal, owner);
    if (Object.keys(request).sort().join(',') !== 'command,descriptor,output,task,taskIdentity' ||
        !Number.isSafeInteger(request.task) || request.task < 1 || request.task > 2147483647 ||
        !Number.isSafeInteger(owner.sequence) || owner.sequence < 1 ||
        typeof request.output !== 'string' || !request.output.length || request.output.length > 256) {
      fail('InvalidCompletionRecord');
    }
    if (entries.has(request.task)) fail('DuplicateCompletionRecord');
    if (entries.size >= limits.maxCompletions) fail('CompletionRecordLimit');
    const descriptor = snapshotCompletionDescriptor(request.descriptor, limits);
    const taskIdentity = snapshotCompletionTask(request.taskIdentity, limits);
    if (JSON.stringify(taskIdentity) !== JSON.stringify(expected.get(request.task))) fail('ForeignCompletionTask');
    if (taskIdentity.task !== request.task || taskIdentity.output_step !== descriptor.output_step ||
        taskIdentity.inputs.length !== descriptor.input_count) fail('ForeignCompletionTask');
    for (const input of taskIdentity.inputs) {
      if (input.producer === 0) continue; // Acquisition has its own capture contract.
      const prior = entries.get(input.producer);
      if (!prior || input.producer_target_is_input ||
          prior.taskIdentity.output_step !== input.producer_target_index) fail('ForeignCompletionDependency');
    }
    for (const predecessor of taskIdentity.controls) {
      if (predecessor !== 0 && !entries.has(predecessor)) fail('ForeignCompletionDependency');
    }
    const body = store.body(request.output);
    if (!body || bodies.has(body) || !body.available() ||
        body.bytes !== descriptor.bytes || body.cid !== descriptor.rows_cid) fail('ForeignCompletionHolding');
    // No await between validation and ownership installation. The process
    // channel binds this report to its one active request; the installed
    // completion observer supplies the exact common-core task, not diagnostics.
    const handle = Object.freeze({});
    const entry = Object.freeze({handle, body, descriptor, taskIdentity,
      origin: Object.freeze({session: identity.session, run: identity.run,
        request: owner.sequence, task: request.task, output: request.output})});
    entries.set(request.task, entry);
    records.set(handle, entry);
    bodies.add(body);
    return Object.freeze({task: request.task});
  };
  return Object.freeze({
    service: Object.freeze({invoke, cleanupHandle: store.cleanupHandle}),
    observe(channel) {
      if (identity || closed) fail('CompletionCustodyAlreadyBound');
      store.observe(channel);
      identity = Object.freeze({...channel.identity()});
      channel.cleanupHandle.whenStopped().then(() => { stopped = true; }, () => {
        // An unconfirmed stop cannot make an old session available for reuse.
        stopped = true;
      });
    },
    completion(task) { return entries.get(task)?.handle; },
    prepareReader(handle) {
      const entry = records.get(handle);
      if (!entry) fail('ForeignCompletionRecord');
      if (closed || !entry.body.available()) fail('RetainedUnavailable');
      return createCompletionReader(entry, limits, () => !closed && entry.body.available());
    },
    inspect(handle) {
      const entry = records.get(handle);
      if (!entry) fail('ForeignCompletionRecord');
      return Object.freeze({origin: entry.origin, descriptor: entry.descriptor, taskIdentity: entry.taskIdentity,
        retained: !closed && entry.body.available()});
    },
    count: () => entries.size,
    cleanupHandle: store.cleanupHandle,
    async close() {
      closed = true;
      // Closing authority is immediate; physical deletion and existing borrows
      // keep their own cleanup responsibility even if this operation rejects.
      await store.close();
    },
  });
}
