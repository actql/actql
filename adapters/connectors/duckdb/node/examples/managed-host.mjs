// Bounded example controller. All acquisition and Compute I/O runs in the
// installed child; this process retains only accounting and completion custody.
import {createManagedProcessHost} from '../../../../host-node/process-capacity.mjs';
import {createProcessRetainedStore} from '../../../../store-local/process-service.mjs';
import {createProcessCompletionCustody} from '../../../../host-node/completion-custody.mjs';
import {snapshotProcessLimits} from '../../../../host-node/process-accounting.mjs';
import {prepareExampleText} from './physical-strategy.mjs';

export async function createManagedExampleHost(limits) {
  const capacity = snapshotProcessLimits(limits);
  const host = await createManagedProcessHost(capacity);
  const runs = new Set();
  let active = false;
  return Object.freeze({
    usage: host.usage,
    async run(supplied, options, signal) {
      // Snapshot before the first await. No module name, verifier or executable
      // crosses this entry; the worker assembly is fixed below.
      const input = structuredClone(supplied);
      if (!options || Object.keys(options).sort().join(',') !== 'childLimits,run') {
        throw new TypeError('InvalidManagedExampleOptions');
      }
      const {run, childLimits: requested} = options ?? {};
      const childLimits = snapshotProcessLimits(requested);
      if (typeof run !== 'string' || !run.length || run.length > 256 || runs.has(run)) {
        throw new TypeError('InvalidOrUsedExampleRun');
      }
      if (runs.size >= capacity.attempts) throw new TypeError('ExampleRunRecordLimit');
      if (active) throw new TypeError('ManagedExampleHoldingActive');
      const plan = await prepareExampleText(input, childLimits);
      if (!input.retainedOutput || input.localImportWorkMilliseconds === undefined) {
        throw new TypeError('ManagedExampleRequiresIndependentRetention');
      }
      signal?.throwIfAborted();
      const tasks = plan.taskIdentities();
      const capacityBytes = input.retainedOutput.wire.max_bytes * (tasks.length + 1);
      if (!Number.isSafeInteger(capacityBytes) || BigInt(capacityBytes) > childLimits.retained_bytes) {
        throw new TypeError('InvalidRetainedCapacity');
      }
      const store = createProcessRetainedStore({
        parentDirectory: input.retainedOutput.parentDirectory,
        capacityBytes, maxFrameBytes: input.retainedOutput.maxFrameBytes,
        maxEntries: tasks.length + 1,
      });
      const custody = createProcessCompletionCustody(store,
        {maxCompletions: tasks.length, maxInputs: 2, maxColumns: input.dataProfile?.columns ?? 10}, tasks);
      // Accepted runs never retry automatically, even if process start or
      // execution later fails. Invalid pure requests above remain correctable.
      if (runs.has(run)) throw new TypeError('InvalidOrUsedExampleRun');
      if (runs.size >= capacity.attempts) throw new TypeError('ExampleRunRecordLimit');
      if (active) throw new TypeError('ManagedExampleHoldingActive');
      runs.add(run);
      active = true;
      let channel, priorCleanup, closed = false, phase = 'provision';
      const cleanupHandle = Object.freeze({
        status() {
          return {pending: !!priorCleanup?.status().pending ||
            !!channel?.cleanupHandle.status().pending || store.cleanupHandle.status().pending};
        },
        async retry() {
          const errors = [];
          for (const handle of [priorCleanup, channel?.cleanupHandle, store.cleanupHandle]) {
            try { if (handle?.status().pending) await handle.retry(); }
            catch (error) { errors.push(error); }
          }
          if (errors.length) throw new AggregateError(errors, 'ManagedExampleCleanupFailed');
          if (closed && !cleanupHandle.status().pending) active = false;
          return cleanupHandle.status();
        },
      });
      const close = async () => {
        closed = true;
        const errors = [];
        // Custody close revokes new use even when child stop cannot be confirmed.
        for (const release of [() => custody.close(), () => channel?.close()]) {
          try { await release(); } catch (error) { errors.push(error); }
        }
        try { await cleanupHandle.retry(); } catch (error) { errors.push(error); }
        if (errors.length || cleanupHandle.status().pending) {
          throw Object.assign(new AggregateError(errors, 'ManagedExampleCleanupPending'), {cleanupHandle});
        }
      };
      try {
        channel = await host.start({entry: new URL('./managed-worker.mjs', import.meta.url), run,
          frames: {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64},
          maxRequests: 3, graceMs: 1000, startupMs: 10000,
          hostService: custody.service, maxHostCalls: 32},
        {retainedBytes: childLimits.retained_bytes, executionBytes: childLimits.execution_bytes, childLimits}, signal);
        custody.observe(channel);
        phase = 'prepare';
        await channel.request({command: 'prepare', input: {...input, controlStore: true}}, signal);
        phase = 'execute';
        const result = await channel.request({command: 'execute'}, signal);
        phase = 'release';
        await channel.request({command: 'release'});
        await channel.close();
        return Object.freeze({report: result.report, program_success: false,
          process: () => channel.status(), usage: host.usage,
          storageUsage: () => store.status(), cleanupHandle, close,
          completion(task) {
            const handle = custody.completion(task);
            return handle === undefined ? undefined : custody.inspect(handle);
          },
          prepareReader(task) {
            if (closed) throw new Error('ReleasedManagedExample');
            return custody.prepareReader(custody.completion(task));
          },
        });
      } catch (error) {
        priorCleanup = error?.cleanupHandle;
        let releaseError;
        try { await close(); } catch (failure) { releaseError = failure; }
        const failure = error instanceof Error ? error : new Error('ManagedExampleFailed', {cause: error});
        failure.examplePhase = phase;
        if (releaseError || cleanupHandle.status().pending) failure.cleanupHandle = cleanupHandle;
        throw failure;
      }
    },
  });
}
