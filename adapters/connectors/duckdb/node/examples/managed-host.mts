// Bounded example controller. All acquisition and Compute I/O runs in the
// installed child; this process retains only accounting and completion custody.
import {createManagedProcessHost} from '../../../../host-node/process-capacity.mjs';
import {createProcessRetainedStore} from '../../../../store-local/process-service.mjs';
import {createProcessCompletionCustody} from '../../../../host-node/completion-custody.mjs';
import {snapshotProcessLimits} from '../../../../host-node/process-accounting.mjs';
import {enableNodeCompileCache} from '../../../../host-node/compile-cache.mjs';
import {snapshotCompletionTask} from '../../../../host-node/completion-record.mjs';
import {prepareExampleTaskManifestInThread, snapshotManagedExampleInput} from './task-manifest.mjs';

import type {ProcessFrameValue} from '../../../../host-node/process-frames.mjs';
import type {DelegatedReadLease} from '../../../../store-local/files.mjs';

type Host = Awaited<ReturnType<typeof createManagedProcessHost>>;
type Channel = Awaited<ReturnType<Host['start']>>;
type Store = ReturnType<typeof createProcessRetainedStore>;
type Custody = ReturnType<typeof createProcessCompletionCustody<
  DelegatedReadLease, Store['cleanupHandle'], ReturnType<Store['service']['invoke']>>>;
type CompletionInvoke = Custody['service']['invoke'];
type CleanupHandle = Readonly<{status(): {pending: boolean}; retry(): unknown}>;
type ExampleFailure = Error & {
  examplePhase?: string; exampleReport?: ProcessFrameValue; cleanupHandle?: CleanupHandle;
};
type ExampleOptions = Readonly<{run?: unknown; childLimits?: unknown}>;
type ControllerInput = ReturnType<typeof snapshotManagedExampleInput>['input'] & Readonly<{
  retainedOutput?: Readonly<{parentDirectory: string; maxFrameBytes: number; wire: Readonly<{max_bytes: number}>}>;
  dataProfile?: Readonly<{columns?: number}>;
}>;
type TimedPhase = 'workerExecutionMs' | 'workerReleaseMs' | 'processCloseMs';
type Phases = {parentPreparationCalls: number; parentTaskManifestCalls: number} &
  Partial<Record<TimedPhase | 'parentPreparationMs' | 'processStartMs' | 'workerPreparationMs' |
    'preparationWallMs' | 'custodySetupMs', number>>;

// The worker can prepare its checked Program while the controller derives the
// independent task manifest. No Store operation is available until the two
// task sets have been compared and the exact custody is installed.
function deferredCompletionService() {
  let installed: Custody | undefined;
  return Object.freeze({
    service: Object.freeze({
      invoke(request: unknown, signal: AbortSignal, owner: Parameters<CompletionInvoke>[2]) {
        if (!installed) throw new Error('CompletionCustodyNotReady');
        return installed.service.invoke(request as Parameters<CompletionInvoke>[0], signal, owner);
      },
      cleanupHandle: Object.freeze({
        status: () => installed?.cleanupHandle!.status() ?? {pending: false},
        retry: () => installed?.cleanupHandle!.retry() ?? Promise.resolve({pending: false}),
      }),
    }),
    install(custody: Custody) {
      if (installed) throw new Error('CompletionCustodyAlreadyBound');
      installed = custody;
    },
  });
}

export async function createManagedExampleHost(limits: unknown) {
  enableNodeCompileCache();
  const capacity = snapshotProcessLimits(limits);
  const host = await createManagedProcessHost(capacity);
  const runs = new Set<string>();
  let active = false;
  return Object.freeze({
    usage: host.usage,
    async run(supplied: unknown, options: unknown, signal?: AbortSignal) {
      // Snapshot before the first await. No module name, verifier or executable
      // crosses this entry; the worker assembly is fixed below. Oversized or
      // mistyped manifest documents are refused before any clone or thread.
      const {manifestInput, input} = snapshotManagedExampleInput(supplied) as
        ReturnType<typeof snapshotManagedExampleInput> & {input: ControllerInput};
      if (!options || Object.keys(options).sort().join(',') !== 'childLimits,run') {
        throw new TypeError('InvalidManagedExampleOptions');
      }
      const {run, childLimits: requested} = (options as ExampleOptions | undefined) ?? {};
      const childLimits = snapshotProcessLimits(requested);
      if (typeof run !== 'string' || !run.length || run.length > 256 || runs.has(run)) {
        throw new TypeError('InvalidOrUsedExampleRun');
      }
      if (runs.size >= capacity.attempts) throw new TypeError('ExampleRunRecordLimit');
      if (active) throw new TypeError('ManagedExampleHoldingActive');
      if (typeof input.nativeMilliseconds !== 'string' ||
          !/^\d{1,18}$/.test(input.nativeMilliseconds)) {
        throw new Error('Invalid example configuration');
      }
      const phases: Phases = {parentPreparationCalls: 0, parentTaskManifestCalls: 1};
      let phaseStarted: number;
      const finishPhase = (name: TimedPhase) => {
        phases[name] = performance.now() - phaseStarted;
        phaseStarted = performance.now();
      };
      signal?.throwIfAborted();
      if (!input.retainedOutput || input.localImportWorkMilliseconds === undefined) {
        throw new TypeError('ManagedExampleRequiresIndependentRetention');
      }
      // Accepted runs never retry automatically, even if process start or
      // execution later fails. The child validates physical configuration
      // before execution; its exact task graph is checked below.
      runs.add(run);
      active = true;
      const deferred = deferredCompletionService();
      let store: Store | undefined, custody: Custody | undefined;
      let channel: Channel | undefined, priorCleanup: CleanupHandle | undefined, closed = false, phase = 'provision';
      const cleanupHandle = Object.freeze({
        status() {
          return {pending: !!priorCleanup?.status().pending ||
            !!channel?.cleanupHandle.status().pending || !!store?.cleanupHandle.status().pending};
        },
        async retry() {
          const errors = [];
          for (const handle of [priorCleanup, channel?.cleanupHandle, store?.cleanupHandle]) {
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
        for (const release of [() => custody ? custody.close() : store?.close(),
          () => channel?.close()]) {
          try { await release(); } catch (error) { errors.push(error); }
        }
        try { await cleanupHandle.retry(); } catch (error) { errors.push(error); }
        if (errors.length || cleanupHandle.status().pending) {
          throw Object.assign(new AggregateError(errors, 'ManagedExampleCleanupPending'), {cleanupHandle});
        }
      };
      let executedReport: ProcessFrameValue | undefined;
      try {
        const preparationStarted = performance.now();
        const parentStarted = performance.now();
        const parentPreparation = (async () => {
          // Deriving the checked manifest is part of the preparation cost. It
          // runs off this event loop so the child starts and prepares meanwhile.
          const tasks = await prepareExampleTaskManifestInThread(manifestInput, signal);
          phases.parentPreparationMs = performance.now() - parentStarted;
          return tasks;
        })();
        const processStarted = performance.now();
        const workerPreparation = (async () => {
          channel = await host.start({entry: new URL('./managed-worker.mjs', import.meta.url), run,
            frames: {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64},
            maxRequests: 3, graceMs: 1000, startupMs: 10000,
            hostService: deferred.service, maxHostCalls: 32},
          {retainedBytes: childLimits.retained_bytes,
            executionBytes: childLimits.execution_bytes, childLimits}, signal);
          phases.processStartMs = performance.now() - processStarted;
          phase = 'prepare';
          const prepareStarted = performance.now();
          const prepared = await channel.request({command: 'prepare', input: {...input, controlStore: true}}, signal);
          phases.workerPreparationMs = performance.now() - prepareStarted;
          return prepared;
        })();
        const [parentResult, workerResult] = await Promise.allSettled([
          parentPreparation, workerPreparation,
        ]);
        phases.preparationWallMs = performance.now() - preparationStarted;
        if (parentResult.status !== 'fulfilled') throw parentResult.reason;
        if (workerResult.status !== 'fulfilled') throw workerResult.reason;
        signal?.throwIfAborted();
        // The fixed manifest worker posts the checked task list on success.
        const tasks = parentResult.value!;
        const prepared = workerResult.value as Readonly<{taskIdentities?: unknown}>;
        const completionLimits = {maxCompletions: tasks.length, maxInputs: 2,
          maxColumns: input.dataProfile?.columns ?? 10};
        const expected = tasks.map(task => snapshotCompletionTask(task, completionLimits));
        if (!Array.isArray(prepared.taskIdentities) ||
            prepared.taskIdentities.length !== expected.length ||
            prepared.taskIdentities.some((task, index) =>
              JSON.stringify(snapshotCompletionTask(task, completionLimits)) !== JSON.stringify(expected[index]))) {
          throw new Error('ForeignPreparedTaskManifest');
        }
        const custodyStarted = performance.now();
        const capacityBytes = input.retainedOutput.wire.max_bytes * (tasks.length + 1);
        if (!Number.isSafeInteger(capacityBytes) || BigInt(capacityBytes) > childLimits.retained_bytes) {
          throw new TypeError('InvalidRetainedCapacity');
        }
        store = createProcessRetainedStore({
          parentDirectory: input.retainedOutput.parentDirectory,
          capacityBytes, maxFrameBytes: input.retainedOutput.maxFrameBytes,
          maxEntries: tasks.length + 1,
        });
        custody = createProcessCompletionCustody(store, completionLimits, tasks);
        deferred.install(custody);
        custody.observe(channel!);
        phases.custodySetupMs = performance.now() - custodyStarted;
        phase = 'execute';
        phaseStarted = performance.now();
        const result = await channel!.request({command: 'execute'}, signal) as
          Readonly<{report: ProcessFrameValue}>;
        executedReport = result.report;
        finishPhase('workerExecutionMs');
        phase = 'release';
        await channel!.request({command: 'release'});
        finishPhase('workerReleaseMs');
        await channel!.close();
        finishPhase('processCloseMs');
        return Object.freeze({report: result.report, program_success: false,
          phases: Object.freeze(phases),
          process: () => channel!.status(), usage: host.usage,
          storageUsage: () => store!.status(), cleanupHandle, close,
          completion(task: number) {
            const handle = custody!.completion(task);
            return handle === undefined ? undefined : custody!.inspect(handle);
          },
          prepareReader(task: number) {
            if (closed) throw new Error('ReleasedManagedExample');
            return custody!.prepareReader(custody!.completion(task)!);
          },
        });
      } catch (error) {
        priorCleanup = (error as {cleanupHandle?: CleanupHandle} | null)?.cleanupHandle;
        let releaseError;
        try { await close(); } catch (failure) { releaseError = failure; }
        const failure: ExampleFailure = error instanceof Error ? error : new Error('ManagedExampleFailed', {cause: error});
        failure.examplePhase = phase;
        failure.exampleReport = executedReport;
        if (releaseError || cleanupHandle.status().pending) failure.cleanupHandle = cleanupHandle;
        throw failure;
      }
    },
  });
}
