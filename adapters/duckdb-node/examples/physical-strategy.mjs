import { readFile, stat } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { authorizeLocalDatabase } from '../session.mjs';
import { runStrategyNativeHostQuery, runRetainedStrategyNativeHostQuery } from '../host.mjs';
import { runCapturedStrategy } from '../../host-node/entry.mjs';
import {
  prepareDuckDBStrategyConfiguration,
  preparedStrategyConfiguration,
} from '../configuration.mjs';
import {retainedConfiguration, bindRetainedProcessStore} from '../retained-configuration.mjs';
import { checked } from '../runtime-result.mjs';
import {configureLocalProcessStore} from '../../local-node/retained-process.mjs';
import {completionObserver} from '../../host-common/completion-observer.mjs';
import {snapshotDataProfile} from './data-profile.mjs';

const root = new URL('../../../', import.meta.url);
const runtimeUrl = new URL('_build/js/release/build/physical_strategy_example/physical_strategy_example.js', root);
const limits = Object.freeze({ maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 });

export function exampleDatabaseMemoryBytes(
  dataProfile,
  resourceLimits,
  managedOutput,
) {
  const data = snapshotDataProfile(dataProfile);
  const configured = resourceLimits?.execution_bytes;
  if (data && managedOutput !== undefined && configured !== undefined &&
      (typeof configured !== 'bigint' || configured < 2n ||
       configured > BigInt(Number.MAX_SAFE_INTEGER))) {
    throw new Error('Invalid execution memory limit');
  }
  return data && managedOutput !== undefined && configured !== undefined
    ? Number(configured / 2n) : limits.memoryBytes;
}

async function boundedText(path) {
  if ((await stat(path)).size > 1000000) throw new Error('Example input exceeds 1000000 bytes');
  const bytes = await readFile(path);
  if (bytes.length > 1000000) throw new Error('Example input exceeds 1000000 bytes');
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}

// Application settings select the source file; Program/Catalog text cannot grant
// filesystem access. Preparation and semantic decisions stay in MoonBit.
export async function runExample({ database, environment, environmentCid, program,
  parameters, schema = 'main', table = 'records', nativeMilliseconds = '5', resident = false,
  retainedOutput, acquisitionRetainedOutput, managedOutput,
  retainedWorkMilliseconds,
  localImportWorkMilliseconds, localExportWorkMilliseconds,
  nativeTaskMilliseconds, dataProfile, signal }, observer) {
  completionObserver(observer); // Validate installed supervision before source/file I/O.
  if (!/^\d{1,18}$/.test(nativeMilliseconds)) throw new Error('Invalid native estimate');
  const [programText, environmentText, parameterText, adoptedText, query, evidence, receipts] =
    await Promise.all([program, environment, parameters,
      new URL('../contracts/adopted-relation.json', import.meta.url),
      new URL('spec/contracts/actql-query-acquisition.json', root),
      new URL('spec/contracts/actql-query-process-evidence.json', root),
      new URL('spec/contracts/actql-query-two-receipt.json', root)].map(boundedText));
  const plan = await prepareExampleText({database, environmentCid, schema, table,
    nativeMilliseconds, resident, programText, environmentText, parameterText,
    adoptedText, query, evidence, receipts, retainedOutput,
    acquisitionRetainedOutput, managedOutput,
    retainedWorkMilliseconds, localImportWorkMilliseconds,
    localExportWorkMilliseconds, nativeTaskMilliseconds, dataProfile});
  const opened = await plan.open(signal);
  let execution;
  try {
    execution = await runCapturedStrategy(opened.setup, opened.configurations, signal, observer);
    return Object.freeze({report: opened.describe(execution), execution, capture: opened.capture,
      close() {
        // Revoke both result ports synchronously; await independent physical
        // cleanup without postponing capture close behind the task finalizers.
        let taskClose;
        try { taskClose = execution.close(); }
        catch (error) { taskClose = Promise.reject(error); }
        return Promise.all([taskClose, opened.close()]).then(() => {});
      }});
  } catch (error) {
    try { await execution?.close(); } finally { await opened.close(); }
    throw error;
  }
}

// The same bounded example application can construct its owned setup inside
// an execution process. Source access belongs only to open, after preparation.
// This remains the documented example profile, not a general Program runner.
export async function prepareExampleText({database, environmentCid, programText,
  environmentText, parameterText, adoptedText, query, evidence, receipts,
  schema = 'main', table = 'records', nativeMilliseconds = '5', resident = false,
  retainedOutput, acquisitionRetainedOutput, managedOutput,
  retainedWorkMilliseconds,
  localImportWorkMilliseconds, localExportWorkMilliseconds,
  nativeTaskMilliseconds, dataProfile}, resourceLimits) {
  const data = snapshotDataProfile(dataProfile);
  const memoryBytes = exampleDatabaseMemoryBytes(
    data,
    resourceLimits,
    managedOutput,
  );
  const transportLimits = data ? {...limits,
    // One session reads one table-metadata cell, validation and selected output.
    // Metadata is outside the receipts but still consumes transport capacity.
    // Do not reset usage between statements or borrow a spare data row for it.
    maxRows: data.source_rows + data.task_rows + 1,
    maxCells: (data.source_rows + data.task_rows) * data.columns + 1,
    maxChunkRows: 128, maxChunkBytes: data.batch_bytes,
    // Explicitly reserve the bounded batch parameter capacity before selecting
    // a candidate. SQL/frame ceilings may choose fewer rows at import time.
    maxColumns: data.columns, maxParameters: data.columns * 128,
    // The bounded application ledger covers both the native database and the
    // independently admitted transport/semantic scratch. This example policy
    // gives each side half; it does not double-count the full limit for DuckDB.
    memoryBytes,
    // Acquisition scans and result frames are distinct from Compute imports.
    maxTransportBytes: data.wire_bytes * 3} : limits;
  if (!/^\d{1,18}$/.test(nativeMilliseconds) || typeof resident !== 'boolean' || typeof database !== 'string') {
    throw new Error('Invalid example configuration');
  }
  if (retainedOutput !== undefined && managedOutput !== undefined) {
    throw new Error('Conflicting output profiles');
  }
  const retained = retainedOutput === undefined
    ? undefined : retainedConfiguration(retainedOutput);
  const managed = managedOutput === undefined
    ? undefined : retainedConfiguration(managedOutput);
  const acquisitionRetained = acquisitionRetainedOutput === undefined
    ? undefined : retainedConfiguration(acquisitionRetainedOutput);
  const stored = retained ?? managed;
  if (nativeTaskMilliseconds !== undefined &&
      (localExportWorkMilliseconds === undefined || !Array.isArray(nativeTaskMilliseconds))) {
    throw new Error('Invalid native task estimates');
  }
  const taskEstimates = Object.freeze(Array.from(nativeTaskMilliseconds ?? []));
  if (taskEstimates.some(value => typeof value !== 'string' || !/^\d{1,18}$/.test(value))) {
    throw new Error('Invalid native task estimates');
  }
  if (localExportWorkMilliseconds !== undefined &&
      (!retained || localImportWorkMilliseconds === undefined || !/^\d{1,18}$/.test(localExportWorkMilliseconds) ||
        retained.maxFrameBytes !== (data?.batch_bytes ?? 100000) || retained.wire.max_bytes !== (data?.wire_bytes ?? 100000))) {
    throw new Error('Invalid Local export estimate');
  }
  if (localImportWorkMilliseconds !== undefined &&
      (!retained || !/^\d{1,18}$/.test(localImportWorkMilliseconds))) {
    throw new Error('InvalidLocalImportWork');
  }
  if ((retainedWorkMilliseconds !== undefined && !/^\d{1,18}$/.test(retainedWorkMilliseconds)) ||
      (stored && retainedWorkMilliseconds === undefined)) {
    throw new Error('Invalid retained example configuration');
  }
  const app = await import(runtimeUrl);
  const adopted = JSON.parse(adoptedText);
  let prepared;
  try {
    const args = [programText, environmentText, environmentCid,
      parameterText, JSON.stringify(adopted.registry), JSON.stringify(adopted.values),
      JSON.stringify(adopted.fragment), query, evidence, receipts, schema, table];
    prepared = checked(data ? app.prepareApplicationWithData(...args, data) : app.prepareApplication(...args));
  } catch (cause) {
    throw new Error('Example preparation rejected: check the filter or join/count profile, Environment CID, Parameters and selected contracts', { cause });
  }
  if (nativeTaskMilliseconds !== undefined && taskEstimates.length !== app.applicationComputeCount(prepared)) {
    throw new Error('Invalid native task estimate count');
  }
  const computeTransport = data ? {...transportLimits,
    // Each input INSERT yields a one-cell acknowledgement. These rows are
    // transport, not logical output, and are charged in addition to that output.
    // Two full input scans plus output, with bounded SQL acknowledgement rows.
    // These are cumulative physical transport counts, not logical row limits.
    maxRows: data.task_rows * 3 + 8,
    maxCells: data.task_rows * data.columns * 3 + 8,
    maxColumns: data.columns + (managed === undefined ? 0 : 2),
    maxTransportBytes: Number(app.applicationComputeTransferCapacity(prepared)),
  } : transportLimits;
  const duckdbConfiguration = prepareDuckDBStrategyConfiguration({transportLimits: computeTransport,
    importLimits: {maxRows: data?.task_rows ?? 100,
      maxCells: data ? 2 * data.task_rows * data.columns : 1000},
    retainedOutput: retained, managedOutput: managed});
  const ledger = resourceLimits === undefined ? app.applicationLedger() : checked(app.applicationBoundedLedger(resourceLimits));
  const taskReferences = Array.from({length: app.applicationComputeCount(prepared)},
    (_, index) => checked(app.applicationTaskReference(prepared, index + 1)));
  return Object.freeze({resourceLimits: Object.freeze({...app.applicationLedgerLimits(ledger)}),
    taskIdentities: () => taskReferences.map(reference => app.applicationTaskIdentity(reference)),
    contentRead(task, descriptor) {
      return checked(app.applicationTaskContentRead(prepared, task, descriptor));
    },
    completionPreparation(task) {
      return checked(app.applicationTaskCompletionPreparation(prepared, task));
    },
    bindReadmittedOutput(producer, consumer, input, output) {
      return checked(app.applicationBindReadmittedOutput(prepared, producer, consumer, input, output));
    },
    completionTask(task, output) {
      const reference = taskReferences[task - 1];
      if (!Number.isSafeInteger(task) || !reference || !app.applicationTaskOutputMatches(reference, output)) {
        throw new Error('ForeignCompletionTask');
      }
      return app.applicationTaskIdentity(reference);
    },
    usage: () => Object.freeze({...app.applicationLedgerUsage(ledger)}), async open(signal, storeBinding) {
    signal?.throwIfAborted();
    if (localExportWorkMilliseconds !== undefined && !storeBinding) throw new Error('Local export requires the installed process Store');
    const acquisitionSource = acquisitionRetained ??
      (storeBinding ? retained : undefined);
    if (storeBinding && (!acquisitionSource ||
        localImportWorkMilliseconds === undefined)) {
      throw new Error('Retained acquisition requires an explicit Local import policy');
    }
    const acquisitionRetention = acquisitionSource === undefined
      ? undefined
      : storeBinding
        ? bindRetainedProcessStore(acquisitionSource, storeBinding)
        : acquisitionSource;
    const computeRetention = storeBinding && retained
      ? acquisitionSource === retained
        ? acquisitionRetention
        : bindRetainedProcessStore(retained, storeBinding)
      : undefined;
    const configuration = computeRetention
      ? prepareDuckDBStrategyConfiguration({
        ...preparedStrategyConfiguration(duckdbConfiguration),
        retainedOutput: computeRetention,
      })
      : duckdbConfiguration;
    const grant = await authorizeLocalDatabase(database);
    signal?.throwIfAborted();
    const capture = acquisitionRetention
      ? await runRetainedStrategyNativeHostQuery(grant, app.applicationAcquisition(prepared),
        ledger, transportLimits, acquisitionRetention, signal)
      : await runStrategyNativeHostQuery(grant, app.applicationAcquisition(prepared),
        ledger, transportLimits, signal);
    const closeCapture = async () => {
      capture.close();
      try {
        await capture.cleanupHandle?.retry();
        if (capture.cleanupHandle?.status().pending) throw new Error('CaptureCleanupPending');
      } catch (error) {
        error.cleanupHandle = capture.cleanupHandle;
        throw error;
      }
    };
    try {
      const graph = capture.openDAG(app.applicationGraph(prepared));
      const setup = checked(managed
        ? app.applicationManagedDispatch(prepared, graph,
          BigInt(nativeMilliseconds), BigInt(managed.wire.max_bytes),
          BigInt(retainedWorkMilliseconds), resident)
        : retained
        ? localExportWorkMilliseconds !== undefined
          ? app.applicationRetainedLocalDispatch(prepared, graph, BigInt(nativeMilliseconds),
            BigInt(retained.wire.max_bytes), BigInt(retainedWorkMilliseconds),
            BigInt(localImportWorkMilliseconds), BigInt(localExportWorkMilliseconds), taskEstimates.map(BigInt), resident)
          : localImportWorkMilliseconds !== undefined
          ? app.applicationMaterializingDispatch(prepared, graph, BigInt(nativeMilliseconds),
            BigInt(retained.wire.max_bytes), BigInt(retainedWorkMilliseconds), BigInt(localImportWorkMilliseconds), resident)
          : app.applicationRetainedDispatch(prepared, graph, BigInt(nativeMilliseconds),
            BigInt(retained.wire.max_bytes), BigInt(retainedWorkMilliseconds), resident)
        : app.applicationDispatch(prepared, graph, BigInt(nativeMilliseconds), resident));
      const describe = execution => Object.freeze({ status: execution.status, program_success: false,
      estimate_model: 'supplied example estimates, not measured speed',
      completed: execution.completed,
      internal_output_cids: execution.completed.map(({ task }) => ({ task, cid: app.applicationProfileOutputCid(prepared, graph, task) ?? null })),
      failure: execution.failure?.code ?? (execution.failure ? 'HostFailure' : null),
      cleanup_pending: execution.cleanupPending(),
      explanation: execution.explain() });
      return Object.freeze({setup, capture, describe,
        configurations: {duckdb: configuration,
          ...(localExportWorkMilliseconds !== undefined ? {local: configureLocalProcessStore(storeBinding)} : {})},
        close: closeCapture});
    } catch (error) {
      try { await closeCapture(); }
      catch { error.cleanupHandle = capture.cleanupHandle; }
      throw error;
    }
  }});
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  let result;
  try {
    const { values } = parseArgs({ options: {
      database: { type: 'string' }, environment: { type: 'string' },
      'environment-cid': { type: 'string' }, program: { type: 'string' },
      parameters: { type: 'string' }, schema: { type: 'string', default: 'main' },
      table: { type: 'string', default: 'records' }, 'native-ms': { type: 'string', default: '5' },
      resident: { type: 'boolean', default: false },
    } });
    for (const key of ['database', 'environment', 'environment-cid', 'program', 'parameters']) {
      if (!values[key]) throw new Error(`Required --${key}`);
    }
    result = await runExample({ ...values, environmentCid: values['environment-cid'], nativeMilliseconds: values['native-ms'] });
    console.log(JSON.stringify(result.report, (_, value) => typeof value === 'bigint' ? value.toString() : value, 2));
    if (result.execution.failure) {
      // Cleanup only: this cannot retry a query or turn failure into success.
      if (result.execution.cleanupPending()) await result.execution.cleanup();
      if (result.execution.cleanupPending()) console.error('Cleanup remains pending; no release or durable recovery is claimed.');
      process.exitCode = 1;
    }
  } catch (error) {
    console.error(error);
    if (error.cleanupHandle?.status().pending) await error.cleanupHandle.retry();
    process.exitCode = 1;
  } finally { await result?.close(); }
}
