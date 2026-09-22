// Process integration uses the shipped example and the real standard Host.
// The only test-owned material is the input environment and independent result.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdtemp, readdir, rm} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {createHash} from 'node:crypto';
import {DuckDBInstance} from '@duckdb/node-api';
import {createManagedProcessHost} from '../../../../host-node/process-capacity.mjs';
import {createProcessRetainedStore} from '../../../../store-local/process-service.mjs';
import {createProcessCompletionCustody} from '../../../../host-node/completion-custody.mjs';
import {prepareExampleText} from '../examples/physical-strategy.mjs';
import {createManagedExampleHost} from '../examples/managed-host.mjs';

export async function exerciseManagedExample(database, environmentText, environmentCid, expectedCid) {
  const root = new URL('../../../../../', import.meta.url);
  const input = {
    database, environmentText, environmentCid,
    programText: await readFile(new URL('../examples/program.json', import.meta.url), 'utf8'),
    parameterText: '{"minimum":1}',
    adoptedText: await readFile(new URL('../contracts/adopted-relation.json', import.meta.url), 'utf8'),
    query: await readFile(new URL('spec/contracts/actql-query-acquisition.json', root), 'utf8'),
    evidence: await readFile(new URL('spec/contracts/actql-query-process-evidence.json', root), 'utf8'),
    receipts: await readFile(new URL('spec/contracts/actql-query-two-receipt.json', root), 'utf8'),
  };
  // Invalid estimates are pure preparation errors, before either source access
  // or a process/Store reservation. No invented usage is needed to correct them.
  const estimateInput = {...input, database: `${database}.missing`,
    localImportWorkMilliseconds: '0', localExportWorkMilliseconds: '0',
    retainedWorkMilliseconds: '0', retainedOutput: {
      parentDirectory: dirname(database), maxFrameBytes: 100000,
      wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
        max_columns: 10, max_order_work: 10000},
    }};
  for (const nativeTaskMilliseconds of [['20', '1'], [], ['20', '-1', '1'], ['20', 1, '1']]) {
    await assert.rejects(prepareExampleText({...estimateInput, nativeTaskMilliseconds}),
      /Invalid native task estimate/);
  }
  const corrected = await prepareExampleText({...estimateInput, nativeTaskMilliseconds: ['20', '20', '1']});
  assert.equal(typeof corrected.open, 'function');
  const childLimits = {planning_work: 100000, attempts: 10, holdings: 10,
    transfer_bytes: 500000n, retained_bytes: 200000000n, execution_bytes: 268435456n};
  // Explicit data profile crosses the old 100-row boundary through the same
  // process entry, with real acquisition and file-backed intermediate results.
  for (const rowCount of [1000, 10000]) {
  const largeDirectory = await mkdtemp(join(dirname(database), 'managed-data-profile-'));
  let larger;
  try {
    const path = join(largeDirectory, 'source.duckdb');
    const db = await DuckDBInstance.create(path);
    const connection = await db.connect();
    try {
      await connection.run(`CREATE TABLE records AS SELECT CAST(i AS DOUBLE) id, CAST(i AS DOUBLE) amount FROM range(${rowCount}) r(i) ORDER BY i`);
    } finally { connection.closeSync(); db.closeSync(); }
    const resourceLimits = {...childLimits, attempts: 12, retained_bytes: 1073741824n,
      execution_bytes: 4294967296n, transfer_bytes: 30000000n};
    const controller = await createManagedExampleHost(resourceLimits);
    const largeInput = {...input, database: path, nativeMilliseconds: '1',
      localImportWorkMilliseconds: '0', localExportWorkMilliseconds: '0', retainedWorkMilliseconds: '0',
      dataProfile: {source_rows: rowCount, task_rows: rowCount, columns: 2, value_bytes: 2048,
        wire_bytes: 2000000, value_nodes: rowCount * 32, text_bytes: rowCount * 32,
        work: rowCount * 10000, entries: rowCount * 8, batch_bytes: 100000},
      retainedOutput: {parentDirectory: largeDirectory, maxFrameBytes: 100000,
        wire: {max_bytes: 2000000, max_nodes: rowCount * 32, max_depth: 64,
          max_columns: 2, max_order_work: 10000}},
    };
    larger = await controller.run(largeInput, {run: 'explicit-data-profile', childLimits: {...resourceLimits, attempts: 10}}).catch(error => {
      throw new Error(`${rowCount}-row data-profile process failed at ${error.examplePhase}: ${JSON.stringify(error.cause)}`, {cause: error});
    });
    assert.equal(larger.report.status, 'host-tasks-completed', JSON.stringify(larger.report));
    // Even after completed predecessors are retained at the last re-selection,
    // holdings stay below the old source-only full-row reservation (>450 MB).
    // Evidence metadata and actual files remain accounted.
    assert(BigInt(larger.report.explanation.selection.ledger_at_selection.held_bytes) < 400000000n,
      `${rowCount}: ${JSON.stringify(larger.report.explanation.selection.ledger_at_selection)}`);
    assert.equal(larger.completion(1).descriptor.rows, rowCount - 3);
    assert.equal(larger.completion(2).descriptor.rows, rowCount - 2);
    assert.equal(larger.completion(3).descriptor.rows, 6);
    const wire = '[{"id":3},{"id":4},{"id":5},{"id":6},{"id":7},{"id":8}]';
    assert.equal(larger.completion(3).descriptor.rows_cid, `sha256:${createHash('sha256').update(wire).digest('hex')}`);
    assert(larger.report.completed.every(task => task.outputRepresentation === 'retained-file'));
    assert.equal(larger.process().exited, true);
    const reading = larger.prepareReader(1);
    const readerHost = await createManagedProcessHost(resourceLimits);
    const fresh = await readerHost.start({
      entry: new URL('../examples/managed-reader.mjs', import.meta.url),
      run: 'explicit-data-profile',
      frames: {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64},
      maxRequests: 1, maxHostCalls: 3, graceMs: 1000, startupMs: 10000,
      hostService: reading.service,
    }, {retainedBytes: 0n, executionBytes: 268435456n,
      childLimits: {...childLimits, retained_bytes: 0n, holdings: 0, attempts: 1,
        transfer_bytes: 1000000n}});
    reading.observe(fresh);
    try {
      const verified = await fresh.request({task: 1, consumer: {task: 3, port: 0},
        application: {...largeInput, database: `${path}.must-not-be-read`}});
      assert.equal(verified.kind, 'completion-readmitted');
      assert.equal(verified.rows, rowCount - 3);
      const expectedRows = Array.from({length: rowCount - 3}, (_, index) => ({id: index + 3}));
      assert.equal(verified.rows_cid, `sha256:${createHash('sha256').update(JSON.stringify(expectedRows)).digest('hex')}`);
      assert.equal(larger.report.internal_output_cids.find(value => value.task === 1).cid, verified.rows_cid);
      assert.equal(verified.producer_bound, true);
    } finally { await fresh.close(); }
    assert.equal(reading.cleanupHandle.status().pending, false);
    assert.equal(readerHost.usage().reserved_execution_bytes, 0n);
  } finally {
    await larger?.close();
    await rm(largeDirectory, {recursive: true, force: true});
  }
  }
  // Product controller: no manual process, Store, observer or release wiring.
  const controller = await createManagedExampleHost({...childLimits, attempts: 24,
    planning_work: 200000, holdings: 20, transfer_bytes: 1000000n});
  const controllerDirectory = await mkdtemp(join(dirname(database), 'managed-controller-'));
  const controllerInput = {...input, nativeMilliseconds: '1', localImportWorkMilliseconds: '0',
    localExportWorkMilliseconds: '0', retainedWorkMilliseconds: '0', retainedOutput: {
      parentDirectory: controllerDirectory, maxFrameBytes: 100000,
      wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
        max_columns: 10, max_order_work: 10000},
    }};
  let controlled;
  try {
    const initial = controller.usage();
    await assert.rejects(controller.run(controllerInput,
      {run: 'standard-controller', childLimits, entry: 'unapproved-worker.mjs'}),
    /InvalidManagedExampleOptions/);
    const cancelled = new AbortController();
    cancelled.abort();
    await assert.rejects(controller.run(controllerInput,
      {run: 'standard-controller', childLimits}, cancelled.signal), {name: 'AbortError'});
    await assert.rejects(controller.run({...controllerInput, nativeMilliseconds: '-1'},
      {run: 'standard-controller', childLimits}), /Invalid example configuration/);
    assert.deepEqual(controller.usage(), initial);
    assert.deepEqual(await readdir(controllerDirectory), []);
    controlled = await controller.run(controllerInput, {run: 'standard-controller', childLimits});
    assert.equal(controlled.report.status, 'host-tasks-completed');
    assert.equal(controlled.program_success, false);
    assert.equal(controlled.process().exited, true);
    assert.equal(controlled.completion(3).descriptor.rows_cid, expectedCid);
    assert.equal(controlled.completion(3).retained, true);
    assert.equal(controlled.storageUsage().holdings, 4);
    assert.equal(controlled.usage().reserved_execution_bytes, 0n);
    const spent = controller.usage();
    await assert.rejects(controller.run(controllerInput, {run: 'overlapping-result', childLimits}),
      /ManagedExampleHoldingActive/);
    await assert.rejects(controller.run(controllerInput, {run: 'standard-controller', childLimits}),
      /InvalidOrUsedExampleRun/);
    assert.deepEqual(controller.usage(), spent);
    assert.equal(typeof controlled.prepareReader(1).service.invoke, 'function');
    await controlled.close();
    assert.equal(controlled.completion(3).retained, false);
    assert.throws(() => controlled.prepareReader(1), /ReleasedManagedExample/);
    assert.equal(controlled.cleanupHandle.status().pending, false);
    assert.deepEqual(controller.usage(), spent, 'closing holdings never refunds consumed work');
    const failing = JSON.parse(await readFile(new URL('../examples/join-count.json', import.meta.url), 'utf8'));
    failing.stages[3].steps[0].join.cardinality = 'one_to_one';
    controlled = await controller.run({...controllerInput, programText: JSON.stringify(failing)},
      {run: 'standard-controller-failure', childLimits});
    assert.equal(controlled.report.status, 'host-tasks-failed');
    assert.equal(controlled.program_success, false);
    assert.equal(controlled.report.completed.length, 2);
    assert.equal(controlled.completion(1).retained, true);
    assert.equal(controlled.completion(2).retained, true);
    assert.equal(controlled.completion(3), undefined);
    assert.equal(controlled.process().exited, true);
    assert(controller.usage().attempts > spent.attempts, 'second Run cannot reset the shared ledger');
    assert(controller.usage().transferred_bytes > spent.transferred_bytes);
  } finally {
    await controlled?.close();
    assert.deepEqual(await readdir(controllerDirectory), []);
    await rm(controllerDirectory, {recursive: true, force: true});
  }
  for (const nativeMilliseconds of ['1', '20']) {
  const residentDirectory = await mkdtemp(join(dirname(database), 'managed-retained-resident-'));
  let residentResult;
  try {
    const residentController = await createManagedExampleHost({...childLimits, attempts: 24,
      planning_work: 200000, holdings: 20, transfer_bytes: 1000000n});
    residentResult = await residentController.run({...controllerInput, resident: true, nativeMilliseconds,
      retainedOutput: {...controllerInput.retainedOutput, parentDirectory: residentDirectory}},
    {run: 'retained-resident-process', childLimits});
    assert.equal(residentResult.report.status, 'host-tasks-completed', JSON.stringify(residentResult.report));
    assert.deepEqual(residentResult.report.completed.map(task => [task.realization, task.outputRepresentation]),
      Array.from({length: 3}, () => [nativeMilliseconds === '1' ? 'duckdb' : 'duckdb-resident', 'retained-file']));
    assert.deepEqual(residentResult.report.completed.map(task => task.preparation.imports.length),
      nativeMilliseconds === '1' ? [0, 0, 0] : [1, 0, 0]);
    assert.equal(residentResult.process().exited, true);
    assert.equal(residentResult.completion(3).descriptor.rows_cid, expectedCid);
    assert.equal(residentResult.completion(3).retained, true);
    assert.equal(residentResult.storageUsage().holdings, 4);
    assert.equal(residentResult.usage().reserved_execution_bytes, 0n);
  } finally {
    await residentResult?.close();
    if (residentResult) assert.equal(residentResult.cleanupHandle.status().pending, false);
    assert.deepEqual(await readdir(residentDirectory), []);
    await rm(residentDirectory, {recursive: true, force: true});
  }
  }
  const host = await createManagedProcessHost({...childLimits,
    planning_work: 800000, attempts: 88, holdings: 80, transfer_bytes: 4000000n,
  });
  const open = (run, store) => host.start({
    entry: new URL('../examples/managed-worker.mjs', import.meta.url), run,
    frames: {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64},
    maxRequests: 5, graceMs: 1000, startupMs: 10000,
    ...(store ? {hostService: store.service, maxHostCalls: 32} : {}),
  }, {retainedBytes: 200000000n, executionBytes: 268435456n, childLimits});
  const pids = [];
  for (const [estimate, realization, retained, mixed, taskEstimates] of [
    ['1', 'duckdb', false, false], ['20', 'local', false, false],
    ['1', 'duckdb', true, false], ['5', 'duckdb', true, true],
    ['20', 'local', true, false],
    ['20', 'local', true, false, ['20', '20', '1']],
  ]) {
    const directory = retained ? await mkdtemp(join(dirname(database), 'managed-retained-')) : undefined;
    const store = retained ? createProcessRetainedStore({parentDirectory: directory,
      capacityBytes: 400000, maxFrameBytes: 100000, maxEntries: 4}) : undefined;
    const custody = store ? createProcessCompletionCustody(store,
      {maxCompletions: 4, maxInputs: 2, maxColumns: 10}, corrected.taskIdentities()) : undefined;
    const channel = await open(`example-${estimate}`, custody);
    custody?.observe(channel);
    assert.equal(host.usage().reserved_execution_bytes, 268435456n);
    const beforeExecution = host.usage();
    try {
      const prepared = await channel.request({command: 'prepare', input: {...input, nativeMilliseconds: estimate,
        ...(retained ? {localImportWorkMilliseconds: '0', localExportWorkMilliseconds: '0'} : {}),
        ...(taskEstimates ? {nativeTaskMilliseconds: taskEstimates} : {}),
        ...(retained ? {controlStore: true, retainedWorkMilliseconds: '0', retainedOutput: {parentDirectory: directory, maxFrameBytes: 100000,
          wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
            max_columns: 10, max_order_work: 10000}}} : {})}});
      assert.equal(prepared.kind, 'strategy-prepared');
      assert.notEqual(prepared.pid, process.pid);
      if (store) {
        assert.equal(store.status(), undefined);
        assert.deepEqual(await readdir(directory), []);
      }
      pids.push(prepared.pid);
      const result = await channel.request({command: 'execute'});
      assert.equal(result.pid, prepared.pid);
      assert.equal(result.kind, 'strategy-report');
      assert.equal(result.program_success, false);
      assert.equal(result.report.status, 'host-tasks-completed', JSON.stringify(result.report));
      assert.equal(host.usage().attempts, beforeExecution.attempts + 4);
      assert(host.usage().planning_work > beforeExecution.planning_work);
      assert(host.usage().transferred_bytes > beforeExecution.transferred_bytes);
      assert.deepEqual(result.report.completed.map(task => task.realization),
        taskEstimates ? ['local', 'local', 'duckdb'] : mixed ? ['duckdb', 'duckdb', 'local'] : Array(3).fill(realization));
      assert.equal(result.report.internal_output_cids[2].cid, expectedCid);
      if (retained) {
        assert(result.report.completed.every(task => task.outputRepresentation === 'retained-file'));
        assert.equal(store.status().holdings, 4);
        assert.equal(store.body('capture-0').available(), true);
        assert.equal(custody.count(), 3);
        for (let task = 1; task <= 3; task++) {
          const record = custody.inspect(custody.completion(task));
          assert.deepEqual(record.origin, {...channel.identity(), request: 2, task, output: `task-${task}`});
          assert.equal(record.retained, true);
          assert.equal(record.descriptor.rows_cid, store.body(`task-${task}`).cid);
          assert.equal(record.descriptor.bytes, store.body(`task-${task}`).bytes);
          assert.equal(record.descriptor.input_count, 1);
          assert.equal(record.descriptor.output_step, 1);
          assert.deepEqual(record.taskIdentity, JSON.parse(JSON.stringify(corrected.taskIdentities()[task - 1])));
        }
        assert.throws(() => custody.inspect({...custody.completion(1)}), {code: 'ForeignCompletionRecord'});
        if (realization === 'local' && !taskEstimates) {
          assert.deepEqual(result.report.completed.map(task => task.importedRows), [3, 3, 2]);
        }
        if (mixed) {
          assert.equal(result.report.completed[2].importedRows, 2);
          assert.equal(result.report.completed[2].importedBytes, '19');
        }
      }
      assert.equal(result.report.cleanup_pending, false);
      assert.deepEqual(Object.keys(result).sort(), ['kind', 'pid', 'program_success', 'report']);
      assert.equal((await channel.request({command: 'release'})).complete, true);
      if (store) assert.equal(store.body('capture-0').available(), true);
      assert.equal((await channel.request({command: 'release'})).complete, true);
      assert.equal(channel.status().exited, false);
      // Released work never regains dispatch permission in this Run process.
      await assert.rejects(channel.request({command: 'execute'}), {code: 'ExecutionFailed'});
    } finally {
      await channel.close();
      assert.equal(channel.cleanupHandle.status().pending, false);
      assert.equal(host.usage().reserved_execution_bytes, 0n);
      assert.equal(host.usage().reserved_retention_bytes, 0n);
      if (store) {
        assert.equal(store.body('capture-0')?.available(), true);
        if (custody.completion(1)) assert.equal(custody.inspect(custody.completion(1)).retained, true);
        // Physical holding survives child release and actual process exit.
        // This is not logical completion re-admission into another process.
        {
          assert.equal(store.body('task-1')?.available(), true);
          assert.equal(store.body('task-1').cid, expectedCid);
          const chunks = [];
          await store.body('task-1').consume(chunk => chunks.push(Buffer.from(chunk)));
          assert.equal(Buffer.concat(chunks).toString('utf8'), '[{"id":3},{"id":3}]');
        }
        const capturedChunks = [];
        await store.body('capture-0').consume(chunk => capturedChunks.push(Buffer.from(chunk)));
        assert.equal(Buffer.concat(capturedChunks).toString('utf8'), '[{"id":3},{"id":2},{"id":3}]');
        const completed = custody.completion(1) ? custody.inspect(custody.completion(1)) : undefined;
        if (realization === 'duckdb' && !mixed) {
          const reading = custody.prepareReader(custody.completion(1));
          const beforeRead = host.usage();
          const fresh = await host.start({
            entry: new URL('../examples/managed-reader.mjs', import.meta.url),
            run: channel.identity().run,
            frames: {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64},
            maxRequests: 1, maxHostCalls: 3, graceMs: 1000, startupMs: 10000,
            hostService: reading.service,
          }, {retainedBytes: 0n, executionBytes: 268435456n,
            childLimits: {...childLimits, retained_bytes: 0n, holdings: 0, attempts: 1,
              transfer_bytes: 100000n}});
          reading.observe(fresh);
          try {
            const verified = await fresh.request({task: 1, consumer: {task: 3, port: 0},
              application: {...input, database: `${database}.must-not-be-read`}}).catch(error => {
                assert.fail(JSON.stringify(error.cause));
              });
            assert.notEqual(verified.pid, pids[pids.length - 1]);
            assert.notEqual(verified.pid, process.pid);
            assert.deepEqual({...verified, pid: 0}, {kind: 'completion-readmitted', program_success: false,
              pid: 0, rows: 2, bytes: 19, rows_cid: expectedCid, producer_bound: true,
              producer_read_bytes: 19});
          } finally { await fresh.close(); }
          assert.equal(reading.cleanupHandle.status().pending, false);
          assert.equal(host.usage().attempts, beforeRead.attempts + 2);
          assert.equal(host.usage().transferred_bytes, beforeRead.transferred_bytes + 38n);
          assert.equal(host.usage().reserved_execution_bytes, 0n);
          assert.equal(custody.inspect(custody.completion(1)).retained, true);
          const rejectedAdmission = custody.prepareReader(custody.completion(1));
          const beforeRejected = host.usage();
          const unacknowledged = await host.start({
            entry: new URL('../examples/managed-reader.mjs', import.meta.url),
            run: channel.identity().run,
            frames: {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64},
            maxRequests: 1, maxHostCalls: 3, graceMs: 1000, startupMs: 10000,
            hostService: {...rejectedAdmission.service,
              async invoke(request, signal, owner) {
                const reply = await rejectedAdmission.service.invoke(request, signal, owner);
                return request.command === 'verify-completion-read'
                  ? {...reply, cid: `sha256:${'0'.repeat(64)}`} : reply;
              }},
          }, {retainedBytes: 0n, executionBytes: 268435456n,
            childLimits: {...childLimits, retained_bytes: 0n, holdings: 0, attempts: 1,
              transfer_bytes: 100000n}});
          rejectedAdmission.observe(unacknowledged);
          try {
            await assert.rejects(unacknowledged.request({task: 1,
              application: {...input, database: `${database}.must-not-be-read`}}),
            error => error.code === 'ExecutionFailed' && error.cause?.code === 'ContentReader:readmission');
          } finally { await unacknowledged.close(); }
          assert.equal(rejectedAdmission.cleanupHandle.status().pending, false);
          assert.equal(host.usage().attempts, beforeRejected.attempts + 2);
          assert.equal(host.usage().transferred_bytes, beforeRejected.transferred_bytes + 19n);
          assert.equal(host.usage().reserved_execution_bytes, 0n);
          assert.equal(custody.inspect(custody.completion(1)).retained, true);
          assert.equal(custody.count(), 3);
          // External mutation is not hidden by a recomputation or equal-size
          // physical file. Reject it in a second independently admitted reader.
          const mutation = store.body('task-1').delegateRead('test-mutation');
          mutation.confirmStopped();
          await writeFile(mutation.descriptor.path, '[{"id":4},{"id":3}]');
          const failedRead = custody.prepareReader(custody.completion(1));
          const beforeFailure = host.usage();
          const corrupted = await host.start({
            entry: new URL('../examples/managed-reader.mjs', import.meta.url),
            run: channel.identity().run,
            frames: {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64},
            maxRequests: 1, maxHostCalls: 3, graceMs: 1000, startupMs: 10000,
            hostService: failedRead.service,
          }, {retainedBytes: 0n, executionBytes: 268435456n,
            childLimits: {...childLimits, retained_bytes: 0n, holdings: 0, attempts: 1,
              transfer_bytes: 100000n}});
          failedRead.observe(corrupted);
          try {
            await assert.rejects(corrupted.request({task: 1,
              application: {...input, database: `${database}.must-not-be-read`}}),
            error => error.code === 'ExecutionFailed' && error.cause?.code === 'ContentReader:read');
          } finally { await corrupted.close(); }
          assert.equal(failedRead.cleanupHandle.status().pending, false);
          assert.equal(host.usage().attempts, beforeFailure.attempts + 2);
          assert.equal(host.usage().transferred_bytes, beforeFailure.transferred_bytes + 19n);
          assert.equal(host.usage().reserved_execution_bytes, 0n);
          assert.equal(custody.count(), 3);
        }
        await custody.close();
        if (completed) {
          assert.deepEqual(custody.inspect(custody.completion(1)).descriptor, completed.descriptor);
          assert.equal(custody.inspect(custody.completion(1)).retained, false);
        }
        await store.cleanupHandle.retry();
        assert.deepEqual(await readdir(directory), []);
      }
      if (directory) await rm(directory, {recursive: true, force: true});
    }
  }
  assert.notEqual(pids[0], pids[1]);
  // Preparation has no source I/O: a nonexistent source can be prepared and
  // cancelled without ever trying to authorize/open it or allocating a DB.
  const unstarted = await open('unstarted-example');
  try {
    assert.equal((await unstarted.request({command: 'prepare', input: {
      ...input, database: `${database}.missing`,
    }})).kind, 'strategy-prepared');
    assert.equal((await unstarted.request({command: 'release'})).complete, true);
  } finally { await unstarted.close(); }
  const invalid = await open('invalid-example');
  try {
    await assert.rejects(invalid.request({command: 'prepare', input: {
      ...input, environmentCid: `sha256:${'0'.repeat(64)}`,
    }}), {code: 'ExecutionFailed'});
    await assert.rejects(invalid.request({command: 'execute'}), {code: 'ExecutionNotReady'});
  } finally { await invalid.close(); }
  assert.equal(host.usage().attempts, 38);
  assert.equal(host.usage().reserved_execution_bytes, 0n);

  // A lost/foreign custody acknowledgement is not permission to run the next
  // task. The already accepted independent result remains the parent's duty;
  // it is not erased when child delivery fails or its finalizer is unconfirmed.
  const failedDirectory = await mkdtemp(join(dirname(database), 'managed-delivery-failure-'));
  const failedStore = createProcessRetainedStore({parentDirectory: failedDirectory,
    capacityBytes: 400000, maxFrameBytes: 100000, maxEntries: 4});
  const failedCustody = createProcessCompletionCustody(failedStore,
    {maxCompletions: 4, maxInputs: 2, maxColumns: 10}, corrected.taskIdentities());
  const failingService = {service: {...failedCustody.service,
    async invoke(request, signal, owner) {
      const reply = await failedCustody.service.invoke(request, signal, owner);
      return request.command === 'retain-completion' ? {task: request.task + 1} : reply;
    }}};
  const failedDelivery = await open('failed-completion-delivery', failingService);
  failedCustody.observe(failedDelivery);
  try {
    await failedDelivery.request({command: 'prepare', input: {...input,
      nativeMilliseconds: '1', localImportWorkMilliseconds: '0', localExportWorkMilliseconds: '0',
      controlStore: true, retainedWorkMilliseconds: '0', retainedOutput: {
        parentDirectory: failedDirectory, maxFrameBytes: 100000,
        wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
          max_columns: 10, max_order_work: 10000},
      }}});
    const failed = await failedDelivery.request({command: 'execute'});
    assert.equal(failed.report.status, 'host-tasks-failed');
    assert.deepEqual(failed.report.completed.map(task => task.task), [1]);
    assert.equal(failed.report.cleanup_pending, true);
    assert.equal(failedCustody.count(), 1);
    assert.equal(failedCustody.inspect(failedCustody.completion(1)).descriptor.rows_cid, expectedCid);
    assert.equal(failedStore.body('task-2'), undefined);
    assert.equal(failedStore.body('task-3'), undefined);
  } finally {
    await failedDelivery.close();
    assert.equal(failedCustody.inspect(failedCustody.completion(1)).retained, true);
    await failedCustody.close();
    await failedStore.cleanupHandle.retry();
    assert.deepEqual(await readdir(failedDirectory), []);
    await rm(failedDirectory, {recursive: true, force: true});
  }
  // No exact terminal report: remaining delegated attempt quota is consumed,
  // not reset by the process's confirmed exit or the Store's independent close.
  assert.equal(host.usage().attempts, 49);
  assert(host.usage().uncertain_transfer_bytes > 0n);
  assert.equal(host.usage().reserved_execution_bytes, 0n);

  // Binary retained fan-in and count run in the same installed process Host,
  // with no result rows in control messages and no cell-backed intermediate.
  const joinDirectory = await mkdtemp(join(dirname(database), 'managed-retained-join-'));
  const joinProgram = JSON.parse(await readFile(new URL('../examples/join-count.json', import.meta.url), 'utf8'));
  joinProgram.stages[3].steps[0].join.null_key = 'fail';
  const joinInput = {...input, programText: JSON.stringify(joinProgram),
    nativeMilliseconds: '1', localImportWorkMilliseconds: '0', localExportWorkMilliseconds: '0',
    controlStore: true, retainedWorkMilliseconds: '0', retainedOutput: {
      parentDirectory: joinDirectory, maxFrameBytes: 100000,
      wire: {max_bytes: 100000, max_nodes: 10000, max_depth: 64,
        max_columns: 10, max_order_work: 10000},
    }};
  const joinPlan = await prepareExampleText(joinInput, childLimits);
  const joinStore = createProcessRetainedStore({parentDirectory: joinDirectory,
    capacityBytes: 500000, maxFrameBytes: 100000, maxEntries: 5});
  const joinCustody = createProcessCompletionCustody(joinStore,
    {maxCompletions: 4, maxInputs: 2, maxColumns: 10}, joinPlan.taskIdentities());
  const beforeJoin = host.usage();
  const joinChannel = await open('retained-join-count', joinCustody);
  joinCustody.observe(joinChannel);
  try {
    await joinChannel.request({command: 'prepare', input: joinInput});
    const result = await joinChannel.request({command: 'execute'});
    assert.equal(
      result.report.status,
      'host-tasks-completed',
      JSON.stringify({report: result.report, failure: {
        code: result.execution?.failure?.code,
        message: result.execution?.failure?.message,
        cause: String(result.execution?.failure?.cause ?? ''),
      }}),
    );
    assert.equal(result.program_success, false);
    assert.equal(result.report.completed.length, 4);
    assert(result.report.completed.every(task => task.realization === 'duckdb' && task.outputRepresentation === 'retained-file'));
    assert.equal(joinCustody.count(), 4);
    const joined = joinCustody.inspect(joinCustody.completion(3));
    assert.equal(joined.descriptor.rows, 4);
    assert.equal(joined.descriptor.input_count, 2);
    assert.equal(joined.descriptor.rows_cid,
      `sha256:${createHash('sha256').update('[{"id":3},{"id":3},{"id":3},{"id":3}]').digest('hex')}`);
    const last = joinCustody.inspect(joinCustody.completion(4));
    assert.equal(last.descriptor.rows, 1);
    assert.equal(last.descriptor.rows_cid,
      `sha256:${createHash('sha256').update('[{"id":3,"n":4,"present":4}]').digest('hex')}`);
    await joinChannel.request({command: 'release'});
  } finally {
    await joinChannel.close();
    try {
      assert.equal(host.usage().attempts, beforeJoin.attempts + 6);
      assert.equal(host.usage().reserved_execution_bytes, 0n);
      assert.equal(host.usage().reserved_retention_bytes, 0n);
      for (let task = 1; task <= 4; task++) {
        assert.equal(joinStore.body(`task-${task}`)?.available(), true);
      }
      assert.equal(joinStore.body('capture-0')?.available(), true);
    } finally {
      await joinCustody.close();
      await joinStore.cleanupHandle.retry();
      assert.deepEqual(await readdir(joinDirectory), []);
      await rm(joinDirectory, {recursive: true, force: true});
    }
  }
}
