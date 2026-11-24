import { readFile, stat } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { authorizeLocalDatabase } from '../session.mjs';
import { runStrategyNativeHostQuery, runRetainedStrategyNativeHostQuery } from '../host.mjs';
import { runCapturedStrategy } from '../../../../host-node/entry.mjs';
import {
  prepareDuckDBStrategyConfiguration,
  preparedStrategyConfiguration,
} from '../configuration.mjs';
import {retainedConfiguration, bindRetainedProcessStore} from '../retained-configuration.mjs';
import { checked } from '../runtime-result.mjs';
import {configureLocalProcessStore} from '../../../../local-node/retained-process.mjs';
import {completionObserver} from '../../../../host-common/completion-observer.mjs';
import {snapshotDataProfile} from './data-profile.mjs';
import {createLocalAuthorizationGate, sourceReadAccountConfiguration} from
  '../../../../host-node/local-account-config.mjs';
import {requireAuthorizedDispatch} from '../../../../host-common/authorization-gate.mjs';

import type { PathLike } from 'node:fs';
import type {decodeProcessLimits, decodeProcessUsage} from '../../../../host-node/process-accounting.mjs';
import type {ProcessStoreBinding} from '../../../../store-local/process-binding.mjs';

type ResourceLimits = ReturnType<typeof decodeProcessLimits>;
type ResourceUsage = ReturnType<typeof decodeProcessUsage>;
type Execution = Awaited<ReturnType<typeof runCapturedStrategy>>;
type DataProfile = NonNullable<ReturnType<typeof snapshotDataProfile>>;
type SourceScope = Readonly<{database: string; schema?: string; table?: string}>;
type Gate = Parameters<typeof requireAuthorizedDispatch>[0];
type Authorization = Pick<NonNullable<Parameters<typeof createLocalAuthorizationGate>[0]>,
  'accountConfig' | 'accountConfiguration' | 'principal'> & {authorization?: Gate};
type ExampleProfile = SourceScope & Authorization & Readonly<{
  environmentCid: string;
  nativeMilliseconds?: string;
  resident?: boolean;
  retainedOutput?: unknown;
  acquisitionRetainedOutput?: unknown;
  managedOutput?: unknown;
  retainedWorkMilliseconds?: string;
  localImportWorkMilliseconds?: string;
  localExportWorkMilliseconds?: string;
  nativeTaskMilliseconds?: readonly unknown[];
  localTaskMilliseconds?: readonly unknown[];
  localEligible?: boolean;
  dataProfile?: unknown;
}>;
type CapturedTexts = Readonly<{programText: string; environmentText: string; parameterText: string}>;
type PrepareInput = ExampleProfile & CapturedTexts & Readonly<{
  adoptedText: string; query: string; evidence: string; receipts: string; acquisitionSubjectCid?: string;
}>;
type RunInput = ExampleProfile & Readonly<{
  program: PathLike;
  environment: PathLike;
  parameters: PathLike;
  signal?: AbortSignal;
  invocation?: Readonly<{
    requestCid?: string;
    seal?: NonNullable<Parameters<typeof requireAuthorizedDispatch>[3]>['sealDeferredSubject'];
    texts?: CapturedTexts;
    identify?: (texts: CapturedTexts) => string | undefined;
  }>;
  continuation?: Readonly<{beforeAcquisition?: () => unknown; beforeRun?: () => unknown}>;
}>;
type Capture = Extract<Awaited<ReturnType<typeof runStrategyNativeHostQuery | typeof runRetainedStrategyNativeHostQuery>>,
  {openDAG: (graph: unknown) => unknown}>;
type ExampleReport = Readonly<{
  status: Execution['status'];
  program_success: false;
  estimate_model: string;
  preparation_diagnostics: Readonly<Record<string, number>>;
  acquisition_evidence: ReturnType<Capture['evidence']>;
  acquisition_diagnostics: Capture['diagnostics'];
  completed: Execution['completed'];
  internal_output_cids: readonly {task: Execution['completed'][number]['task']; cid: string | null}[];
  failure: unknown;
  cleanup_pending: boolean;
  explanation: ReturnType<Execution['explain']>;
}>;
type OpenedExample = Readonly<{
  setup: Parameters<typeof runCapturedStrategy>[0];
  capture: Capture;
  describe: (execution: Execution) => ExampleReport;
  configurations: Readonly<{
    duckdb: ReturnType<typeof prepareDuckDBStrategyConfiguration>;
    local?: ReturnType<typeof configureLocalProcessStore>;
  }>;
  close: () => Promise<void>;
}>;
type CaptureError = {cleanupHandle?: Capture['cleanupHandle']};
type ExampleError = CaptureError & {runtimeCode?: string; code?: unknown};

declare const exampleHandle: unique symbol;
type ExampleHandle<Kind extends string> = {readonly [exampleHandle]: Kind};
type Application = ExampleHandle<'application'>;
type CapturedGraph = ExampleHandle<'captured-graph'>;
type Ledger = ExampleHandle<'ledger'>;
type TaskReference = ExampleHandle<'task-reference'>;
type ApplicationDocuments = readonly [
  program: string, environment: string, environmentCid: string, parameters: string,
  registry: string, values: string, fragment: string, query: string,
  evidence: string, receipts: string, schema: string, table: string,
];
type RetainedCosts = [nativeMs: bigint, bytes: bigint, retainedMs: bigint];
type MaterializingCosts = [...RetainedCosts, localImportMs: bigint];
type LocalCosts = [...MaterializingCosts, localExportMs: bigint];
type ExampleRuntime = Readonly<{
  // Raising exports return the pinned compiler's Result representation.
  prepareApplication(...documents: ApplicationDocuments): unknown;
  prepareApplicationWithData(...arguments_: [...ApplicationDocuments, DataProfile]): unknown;
  applicationAcquisition(prepared: Application): unknown;
  applicationGraph(prepared: Application): unknown;
  applicationComputeCount(prepared: Application): number;
  applicationComputeTransferCapacity(prepared: Application): bigint;
  applicationLedger(): Ledger;
  applicationBoundedLedger(limits: ResourceLimits): unknown;
  applicationLedgerLimits(ledger: Ledger): ResourceLimits;
  applicationLedgerUsage(ledger: Ledger): ResourceUsage;
  applicationTaskReference(prepared: Application, task: number): unknown;
  applicationTaskIdentity(task: TaskReference): unknown;
  applicationTaskContentRead(prepared: Application, task: number, descriptor: unknown): unknown;
  applicationTaskCompletionPreparation(prepared: Application, task: number): unknown;
  applicationBindReadmittedOutput(prepared: Application, producer: number, consumer: number, input: number, output: unknown): unknown;
  applicationTaskOutputMatches(task: TaskReference, output: unknown): boolean;
  applicationDispatch(prepared: Application, graph: CapturedGraph, nativeMs: bigint, resident: boolean): unknown;
  applicationManagedDispatch(prepared: Application, graph: CapturedGraph, ...arguments_: [...RetainedCosts, boolean]): unknown;
  applicationRetainedDispatch(prepared: Application, graph: CapturedGraph, ...arguments_: [...RetainedCosts, boolean]): unknown;
  applicationMaterializingDispatch(prepared: Application, graph: CapturedGraph, ...arguments_: [...MaterializingCosts, boolean]): unknown;
  applicationRetainedLocalDispatch(prepared: Application, graph: CapturedGraph, ...arguments_: [...LocalCosts, bigint[], boolean]): unknown;
  applicationRetainedTaskEstimateDispatch(prepared: Application, graph: CapturedGraph,
    ...arguments_: [...LocalCosts, localEstimates: bigint[], nativeEstimates: bigint[], localEligible: boolean, resident: boolean]): unknown;
  applicationProfileOutputCid(prepared: Application, graph: CapturedGraph, task: number): string | undefined;
}>;


const root = new URL('../../../../../', import.meta.url);
const runtimeUrl = new URL('_build/js/release/build/physical_strategy_example/physical_strategy_example.js', root);
const limits = Object.freeze({ maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 });

export function exampleDatabaseMemoryBytes(
  dataProfile: unknown,
  resourceLimits: Readonly<{execution_bytes?: unknown}> | undefined,
  managedOutput: unknown,
) {
  const data = snapshotDataProfile(dataProfile);
  const configured = resourceLimits?.execution_bytes;
  if (data && managedOutput !== undefined && configured !== undefined &&
      (typeof configured !== 'bigint' || configured < 2n ||
       configured > BigInt(Number.MAX_SAFE_INTEGER))) {
    throw new Error('Invalid execution memory limit');
  }
  return data && managedOutput !== undefined && configured !== undefined
    ? Number((configured as bigint) / 2n) : limits.memoryBytes;
}

// Text of an explicit execution-account configuration that allows reading
// exactly the example's source table (`outcome` may be `delegate` or `deny`).
// It is a convenience for writing an operator-owned file; the example never
// installs it by itself.
export function exampleAccountConfiguration({database, schema = 'main',
  table = 'records', outcome = 'allow', accountId = 'example-application'}:
    SourceScope & Pick<Parameters<typeof sourceReadAccountConfiguration>[0], 'outcome' | 'accountId'>) {
  return sourceReadAccountConfiguration({connection: database,
    resource: `${schema}.${table}`, outcome, accountId, entryId: 'example-source'});
}

// The installed execution account is explicit Host installation, never
// Program input: a gate supplied by the embedding application, the
// operator-selected configuration file `accountConfig`, or the exact
// configuration text `accountConfiguration` a trusted parent Host passes to
// its managed worker. With none, the Missing gate denies every protected
// boundary (ACTQL_E_ACCOUNT_CONFIG_INVALID); there is no allow-all default.
export function exampleAuthorization({authorization, accountConfig,
  accountConfiguration, principal = 'example-application'}: Authorization = {}): Gate | PromiseLike<Gate> {
  if (authorization !== undefined) return authorization;
  return createLocalAuthorizationGate({accountConfig, accountConfiguration,
    principal});
}

const exampleSourceScope = ({database, schema = 'main', table = 'records'}: SourceScope) =>
  Object.freeze({connection: database, resource: `${schema}.${table}`});

async function boundedText(path: PathLike) {
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
  nativeTaskMilliseconds, localTaskMilliseconds, localEligible, dataProfile, signal,
  authorization, accountConfig, accountConfiguration, invocation, continuation }: RunInput,
  observer?: Parameters<typeof runCapturedStrategy>[3]) {
  completionObserver(observer); // Validate installed supervision before source/file I/O.
  if (!/^\d{1,18}$/.test(nativeMilliseconds)) throw new Error('Invalid native estimate');
  if (typeof database !== 'string') throw new Error('Invalid example configuration');
  // Preparation boundary: decided on the invocation request before any
  // Program/Environment path read, source capture or Run creation. Only a
  // deferred delegated decision calls the Host's `seal`, which captures the
  // inputs and returns the prepared invocation the Checkpoint requires.
  const gate = await exampleAuthorization({authorization, accountConfig,
    accountConfiguration});
  await requireAuthorizedDispatch(gate, 'preparation',
    {...exampleSourceScope({database, schema, table}), operation: 'read'},
    {signal, subjectCid: invocation?.requestCid,
      sealDeferredSubject: invocation?.seal});
  // A resumed preparation continuation supplies the immutable bytes captured
  // before its Checkpoint; it never rereads the mutable operator paths.
  const captured = invocation?.texts;
  const [programText, environmentText, parameterText, adoptedText, query, evidence, receipts] =
    captured !== undefined ? [captured.programText, captured.environmentText,
      captured.parameterText, ...await Promise.all([
        new URL('../contracts/adopted-relation.json', import.meta.url),
        new URL('spec/contracts/actql-query-acquisition.json', root),
        new URL('spec/contracts/actql-query-process-evidence.json', root),
        new URL('spec/contracts/actql-query-two-receipt.json', root)].map(boundedText))] :
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
    localExportWorkMilliseconds, nativeTaskMilliseconds, localTaskMilliseconds,
    localEligible, dataProfile, authorization: gate,
    acquisitionSubjectCid: invocation?.identify?.({programText, environmentText,
      parameterText})});
  // A resumed continuation re-proves its fence before provider I/O and
  // creates its Run only once capture completed.
  await continuation?.beforeAcquisition?.();
  const opened = await plan.open(signal);
  let execution: Execution | undefined;
  try {
    await continuation?.beforeRun?.();
    execution = await runCapturedStrategy(opened.setup,
      {...opened.configurations, authorization: gate}, signal, observer);
    return Object.freeze({report: opened.describe(execution), execution, capture: opened.capture,
      close() {
        // Revoke both result ports synchronously; await independent physical
        // cleanup without postponing capture close behind the task finalizers.
        let taskClose;
        try { taskClose = execution!.close(); }
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
export {prepareExampleTaskManifest} from './task-manifest.mjs';

export async function prepareExampleText({database, environmentCid, programText,
  environmentText, parameterText, adoptedText, query, evidence, receipts,
  schema = 'main', table = 'records', nativeMilliseconds = '5', resident = false,
  retainedOutput, acquisitionRetainedOutput, managedOutput,
  retainedWorkMilliseconds,
  localImportWorkMilliseconds, localExportWorkMilliseconds,
  nativeTaskMilliseconds, localTaskMilliseconds, localEligible, dataProfile,
  authorization, accountConfig, accountConfiguration, acquisitionSubjectCid}: PrepareInput,
  resourceLimits?: ResourceLimits) {
  const preparationStarted = performance.now();
  const data = snapshotDataProfile(dataProfile);
  const memoryBytes = exampleDatabaseMemoryBytes(
    data,
    resourceLimits,
    managedOutput ?? retainedOutput,
  );
  const transportLimits = data ? {...limits,
    maxSourceRows: data.source_rows,
    // One session reads one table-metadata cell, validation and selected output.
    // Metadata is outside the receipts but still consumes transport capacity.
    // Do not reset usage between statements or borrow a spare data row for it.
    maxRows: data.source_rows + data.task_rows + 1,
    maxCells: (data.source_rows + data.task_rows) * data.columns + 1,
    maxChunkRows: 512, maxChunkBytes: data.batch_bytes,
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
  if (localTaskMilliseconds !== undefined &&
      (localExportWorkMilliseconds === undefined || !Array.isArray(localTaskMilliseconds))) {
    throw new Error('Invalid local task estimates');
  }
  const localTaskEstimates = Object.freeze(Array.from(localTaskMilliseconds ?? []));
  if (localEligible !== undefined && typeof localEligible !== 'boolean') {
    throw new Error('Invalid local candidate eligibility');
  }
  if (localEligible === false && nativeTaskMilliseconds === undefined) {
    throw new Error('Local exclusion requires task estimates');
  }
  if (localTaskEstimates.some(value => typeof value !== 'string' || !/^\d{1,18}$/.test(value))) {
    throw new Error('Invalid local task estimates');
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
  const configuredAt = performance.now();
  const app: ExampleRuntime = await import(runtimeUrl.href);
  const importedAt = performance.now();
  const adopted = JSON.parse(adoptedText);
  let prepared: Application;
  try {
    const args: ApplicationDocuments = [programText, environmentText, environmentCid,
      parameterText, JSON.stringify(adopted.registry), JSON.stringify(adopted.values),
      JSON.stringify(adopted.fragment), query, evidence, receipts, schema, table];
    prepared = checked(data ? app.prepareApplicationWithData(...args, data) : app.prepareApplication(...args)) as Application;
  } catch (cause) {
    throw new Error('Example preparation rejected: check the filter or join/count profile, Environment CID, Parameters and selected contracts', { cause });
  }
  const preparedAt = performance.now();
  if (nativeTaskMilliseconds !== undefined && taskEstimates.length !== app.applicationComputeCount(prepared)) {
    throw new Error('Invalid native task estimate count');
  }
  if (localTaskMilliseconds !== undefined && localTaskEstimates.length !== app.applicationComputeCount(prepared)) {
    throw new Error('Invalid local task estimate count');
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
  const ledger = resourceLimits === undefined ? app.applicationLedger() : checked(app.applicationBoundedLedger(resourceLimits)) as Ledger;
  const taskReferences = Array.from({length: app.applicationComputeCount(prepared)},
    (_, index) => checked(app.applicationTaskReference(prepared, index + 1)) as TaskReference);
  const projectedAt = performance.now();
  const preparationDiagnostics = Object.freeze({
    applicationPrepareCalls: 1,
    configurationMs: configuredAt - preparationStarted,
    moduleImportMs: importedAt - configuredAt,
    applicationPreparationMs: preparedAt - importedAt,
    hostProjectionMs: projectedAt - preparedAt,
  });
  return Object.freeze({resourceLimits: Object.freeze({...app.applicationLedgerLimits(ledger)}),
    preparationDiagnostics,
    taskIdentities: () => taskReferences.map(reference => app.applicationTaskIdentity(reference)),
    contentRead(task: number, descriptor: unknown) {
      return checked(app.applicationTaskContentRead(prepared, task, descriptor));
    },
    completionPreparation(task: number) {
      return checked(app.applicationTaskCompletionPreparation(prepared, task));
    },
    bindReadmittedOutput(producer: number, consumer: number, input: number, output: unknown) {
      return checked(app.applicationBindReadmittedOutput(prepared, producer, consumer, input, output));
    },
    completionTask(task: number, output: unknown) {
      const reference = taskReferences[task - 1];
      if (!Number.isSafeInteger(task) || !reference || !app.applicationTaskOutputMatches(reference, output)) {
        throw new Error('ForeignCompletionTask');
      }
      return app.applicationTaskIdentity(reference);
    },
    usage: () => Object.freeze({...app.applicationLedgerUsage(ledger)}), async open(signal?: AbortSignal, storeBinding?: ProcessStoreBinding): Promise<OpenedExample> {
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
    // Acquisition boundary: the source grant carries the installed gate and
    // the exact source scope; no provider session opens without a dispatch
    // decision for it.
    const grant = await authorizeLocalDatabase(database, {
      authorization: await exampleAuthorization({authorization, accountConfig,
        accountConfiguration}),
      ...exampleSourceScope({database, schema, table}),
      subjectCid: acquisitionSubjectCid,
    });
    signal?.throwIfAborted();
    const capture = (acquisitionRetention
      ? await runRetainedStrategyNativeHostQuery(grant, app.applicationAcquisition(prepared),
        ledger, transportLimits, acquisitionRetention, signal)
      : await runStrategyNativeHostQuery(grant, app.applicationAcquisition(prepared),
        ledger, transportLimits, signal)) as Capture;
    const closeCapture = async () => {
      capture.close();
      try {
        await capture.cleanupHandle?.retry();
        if (capture.cleanupHandle?.status().pending) throw new Error('CaptureCleanupPending');
      } catch (error) {
        (error as CaptureError).cleanupHandle = capture.cleanupHandle;
        throw error;
      }
    };
    try {
      const graph = capture.openDAG(app.applicationGraph(prepared)) as CapturedGraph;
      const setup = checked(managed
        ? app.applicationManagedDispatch(prepared, graph,
          BigInt(nativeMilliseconds), BigInt(managed.wire.max_bytes),
          BigInt(retainedWorkMilliseconds!), resident)
        : retained
        ? localExportWorkMilliseconds !== undefined
          ? localTaskMilliseconds !== undefined || localEligible === false
            ? app.applicationRetainedTaskEstimateDispatch(prepared, graph, BigInt(nativeMilliseconds),
            BigInt(retained.wire.max_bytes), BigInt(retainedWorkMilliseconds!),
            BigInt(localImportWorkMilliseconds!), BigInt(localExportWorkMilliseconds),
            (localTaskEstimates as readonly string[]).map(BigInt), (taskEstimates as readonly string[]).map(BigInt), localEligible !== false, resident)
            : app.applicationRetainedLocalDispatch(prepared, graph, BigInt(nativeMilliseconds),
            BigInt(retained.wire.max_bytes), BigInt(retainedWorkMilliseconds!),
            BigInt(localImportWorkMilliseconds!), BigInt(localExportWorkMilliseconds), (taskEstimates as readonly string[]).map(BigInt), resident)
          : localImportWorkMilliseconds !== undefined
          ? app.applicationMaterializingDispatch(prepared, graph, BigInt(nativeMilliseconds),
            BigInt(retained.wire.max_bytes), BigInt(retainedWorkMilliseconds!), BigInt(localImportWorkMilliseconds!), resident)
          : app.applicationRetainedDispatch(prepared, graph, BigInt(nativeMilliseconds),
            BigInt(retained.wire.max_bytes), BigInt(retainedWorkMilliseconds!), resident)
        : app.applicationDispatch(prepared, graph, BigInt(nativeMilliseconds), resident)) as Parameters<typeof runCapturedStrategy>[0];
      const describe = (execution: Execution): ExampleReport => Object.freeze({ status: execution.status, program_success: false,
      estimate_model: 'supplied example estimates, not measured speed',
      preparation_diagnostics: preparationDiagnostics,
      acquisition_evidence: capture.evidence(),
      acquisition_diagnostics: capture.diagnostics,
      completed: execution.completed,
      internal_output_cids: execution.completed.map(({ task }) => ({ task, cid: app.applicationProfileOutputCid(prepared, graph, task) ?? null })),
      failure: (execution.failure as {code?: unknown} | null | undefined)?.code ?? (execution.failure ? 'HostFailure' : null),
      cleanup_pending: execution.cleanupPending(),
      explanation: execution.explain() });
      return Object.freeze({setup, capture, describe,
        configurations: {duckdb: configuration,
          ...(localExportWorkMilliseconds !== undefined ? {local: configureLocalProcessStore(storeBinding!)} : {})},
        close: closeCapture});
    } catch (error) {
      try { await closeCapture(); }
      catch { (error as CaptureError).cleanupHandle = capture.cleanupHandle; }
      throw error;
    }
  }});
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  let result: Awaited<ReturnType<typeof runExample>> | undefined;
  try {
    const { values } = parseArgs({ options: {
      database: { type: 'string' }, environment: { type: 'string' },
      'environment-cid': { type: 'string' }, program: { type: 'string' },
      parameters: { type: 'string' }, schema: { type: 'string', default: 'main' },
      table: { type: 'string', default: 'records' }, 'native-ms': { type: 'string', default: '5' },
      resident: { type: 'boolean', default: false },
      // Operator-selected execution-account configuration. Without it every
      // protected boundary is denied (ACTQL_E_ACCOUNT_CONFIG_INVALID).
      'account-config': { type: 'string' },
    } });
    for (const key of ['database', 'environment', 'environment-cid', 'program', 'parameters'] as const) {
      if (!values[key]) throw new Error(`Required --${key}`);
    }
    result = await runExample({ ...values as typeof values & Required<Pick<typeof values,
      'database' | 'environment' | 'program' | 'parameters'>>, environmentCid: values['environment-cid']!,
      nativeMilliseconds: values['native-ms'], accountConfig: values['account-config'] });
    console.log(JSON.stringify(result.report, (_, value) => typeof value === 'bigint' ? value.toString() : value, 2));
    if (result.execution.failure) {
      // Cleanup only: this cannot retry a query or turn failure into success.
      if (result.execution.cleanupPending()) await result.execution.cleanup();
      if (result.execution.cleanupPending()) console.error('Cleanup remains pending; no release or durable recovery is claimed.');
      process.exitCode = 1;
    }
  } catch (error) {
    if ((error as ExampleError).runtimeCode) console.error(`${(error as ExampleError).runtimeCode}: ${(error as ExampleError).code}`);
    console.error(error);
    if ((error as ExampleError).cleanupHandle?.status().pending) await (error as ExampleError).cleanupHandle!.retry();
    process.exitCode = 1;
  } finally { await result?.close(); }
}
