// Explicit real process cancellation; no copied process binding or fake owner.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {retainedCase, workloads} from './fixtures.mjs';
import {managedCaseConfiguration} from './managed-configuration.mjs';
import {prepareExampleTaskManifest} from '../../adapters/connectors/duckdb/node/examples/task-manifest.mjs';
import {createManagedProcessHost} from '../../adapters/host-node/process-capacity.mjs';
import {createProcessRetainedStore} from '../../adapters/store-local/process-service.mjs';
import {createProcessCompletionCustody} from '../../adapters/host-node/completion-custody.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const json = value => JSON.stringify(value, (_, v) => typeof v === 'bigint' ? v.toString() : v);

test('100 rows: acknowledged resident completion survives formal request cancellation',
  {timeout: 30000}, async () => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-managed-cancel-bench-'));
    let channel, custody, store;
    try {
      const fixture = retainedCase(workloads[0], 'narrow', 100);
      const database = join(directory, 'source.duckdb');
      await promisify(execFile)(process.execPath, [join(root,
        'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
      database, fixture.workload, fixture.layout, String(fixture.rows)],
      {cwd: root, timeout: fixture.limits.timeoutMs});
      const contracts = Object.fromEntries(await Promise.all([
        ['adoptedText', 'adapters/connectors/duckdb/node/contracts/adopted-relation.json'],
        ['query', 'spec/contracts/actql-query-acquisition.json'],
        ['evidence', 'spec/contracts/actql-query-process-evidence.json'],
        ['receipts', 'spec/contracts/actql-query-two-receipt.json'],
      ].map(async ([key, path]) => [key, await readFile(join(root, path), 'utf8')])));
      const config = managedCaseConfiguration(fixture, contracts, database, directory);
      const input = {...config.input, controlStore: true, resident: true, nativeMilliseconds: '1000'};
      const tasks = await prepareExampleTaskManifest(input);
      const host = await createManagedProcessHost(config.limits);
      const completionLimits = {maxCompletions: tasks.length, maxInputs: 2,
        maxColumns: input.dataProfile.columns};
      store = createProcessRetainedStore({parentDirectory: directory,
        capacityBytes: input.retainedOutput.wire.max_bytes * (tasks.length + 1),
        maxFrameBytes: input.retainedOutput.maxFrameBytes, maxEntries: tasks.length + 1});
      custody = createProcessCompletionCustody(store, completionLimits, tasks);
      const controller = new AbortController();
      const reason = new Error('BenchmarkCancellationRequested');
      const calls = [];
      let retainedAtRequest, boundary;
      const service = {...custody.service, async invoke(request, signal, owner) {
        calls.push({command: request.command, output: request.output, task: request.task});
        if (request.command === 'benchmark-before-compute') {
          assert.equal(owner.session, channel.identity().session);
          assert.equal(owner.run, channel.identity().run);
          assert.equal(owner.sequence, 2);
          boundary = request;
          const {observation, usage} = boundary;
          assert.equal(observation.task, 2);
          assert.equal(observation.registrationKey, 'duckdb');
          assert.equal(observation.explanation.selection_state, 'selected');
          const selection = observation.explanation.selection;
          assert.equal(selection.dispatch_authorized, true);
          assert.equal(selection.revision, observation.explanation.assessment_revision);
          const selected = selection.tasks.find(task => task.task === 2);
          assert.equal(selected.completed, false);
          assert.equal(selected.capability, 'duckdb');
          assert.notEqual(selected.resident_profile, null);
          assert.equal(usage.attempts, 4); // Acquisition + environment/import + Compute.
          assert(BigInt(usage.reserved_execution_bytes) > 0n);
          assert.equal(custody.count(), 1);
          const completion = custody.inspect(custody.completion(1));
          assert.equal(completion.descriptor.rows_cid, fixture.identity().rowsCid);
          assert.equal(completion.retained, true);
          assert.equal(store.body('task-1').available(), true);
          retainedAtRequest = store.status();
          assert(retainedAtRequest.reservedBytes >= completion.descriptor.bytes);
          const delegated = host.usage();
          assert(delegated.reserved_execution_bytes > 0n);
          assert(delegated.reserved_retention_bytes > 0n);
          controller.abort(reason); // Existing request cancellation sends real stop.
          assert.equal(signal.aborted, true);
          assert.equal(channel.status().exited, false);
          assert.equal(host.usage().reserved_execution_bytes, delegated.reserved_execution_bytes,
            'CancellationReleasedDelegationBeforeObservedExit');
          assert.equal(host.usage().reserved_retention_bytes, delegated.reserved_retention_bytes,
            'CancellationReleasedRetentionBeforeObservedExit');
          throw signal.reason; // No late observation reply after cancellation.
        }
        return custody.service.invoke(request, signal, owner);
      }};
      channel = await host.start({
        entry: new URL('./node-cancellation-worker.mjs', import.meta.url),
        run: fixture.id + '/cancel-before-second-compute',
        frames: {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64},
        maxRequests: 3, maxHostCalls: 32, graceMs: 1000, startupMs: 10000,
        hostService: service,
      }, {retainedBytes: config.childLimits.retained_bytes,
        executionBytes: config.childLimits.execution_bytes, childLimits: config.childLimits});
      custody.observe(channel);
      const prepared = await channel.request({command: 'prepare', input});
      // IPC records and MoonBit structs have different JS prototypes. Compare
      // the exact identity payload, as the existing managed controller does.
      assert.equal(json(prepared.taskIdentities), json(tasks));
      await assert.rejects(channel.request({command: 'execute'}, controller.signal),
        {code: 'ExecutionCancelled'});
      assert.equal(controller.signal.reason, reason);
      assert(retainedAtRequest, 'CancellationBeforeAcceptedHolding');
      const exit = await channel.close();
      const stopped = channel.status();
      const usage = host.usage();
      console.log('MANAGED_CANCELLATION_OBSERVATION:' + json({exit, stopped, usage,
        retainedAtRequest, retainedAfterStop: store.status(), boundary, calls}));
      assert.equal(stopped.stopped, true);
      assert.equal(stopped.exited, true);
      assert.equal(stopped.pending, false);
      assert.equal(channel.cleanupHandle.status().pending, false);
      assert.equal(exit.signal, null, 'CancellationRequiredForcedProcessTermination');
      assert.equal(exit.code, 0, 'CancellationFinishFailed');
      assert.equal(usage.attempts, boundary.usage.attempts + 1, 'CancellationStartedAnotherAttempt');
      assert.equal(usage.uncertain_transfer_bytes, 0n, 'MissingTerminalUsage');
      assert.equal(usage.reserved_execution_bytes, 0n);
      assert.equal(usage.reserved_retention_bytes, 0n);
      assert.equal(calls.filter(call => call.command === 'retain-completion').length, 1);
      assert.equal(custody.count(), 1);
      assert.equal(custody.completion(2), undefined);
      assert.equal(store.body('task-2'), undefined);
      assert.equal(store.body('task-3'), undefined);
      assert.equal(custody.inspect(custody.completion(1)).retained, true);
      assert.equal(store.body('task-1').available(), true);
      await assert.rejects(channel.request({command: 'execute'}), {code: 'ExecutionNotReady'});
      await custody.close();
      await store.cleanupHandle.retry();
      assert.equal(store.status().reservedBytes, 0);
      assert.equal(store.cleanupHandle.status().pending, false);
      const returned = host.usage();
      const returnedStore = store.status();
      await channel.close();
      await custody.close();
      await store.cleanupHandle.retry();
      assert.deepEqual(host.usage(), returned, 'CancellationDuplicateReturn');
      assert.deepEqual(store.status(), returnedStore, 'CancellationDuplicateStoreReturn');
      assert.deepEqual((await readdir(directory)).sort(), ['source.duckdb']);
    } finally {
      try {await channel?.close();} finally {
        try {await custody?.close(); await store?.cleanupHandle.retry();} finally {
          await rm(directory, {recursive: true, force: true});
        }
      }
    }
  });
