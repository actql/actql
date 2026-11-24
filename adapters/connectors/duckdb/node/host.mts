// Standard source-checkout Host entry. Neither Program inputs nor ordinary
// Connector registration can supply a replacement runtime/verifier/SQL callback.
import {runtimeField, runtimeOptionalField} from '../../../host-common/compiler-binding.generated.mjs';
import {createNativeHostQuery} from './native-host-query.mjs';
import {createBroadHostQuery} from './broad-host-query.mjs';
import { runFixedCompute, runResidentFixedCompute, matchesFixedCompute, releaseFixedCompute } from './fixed-compute.mjs';
import { DuckDBTransportError, validateLimits } from './session.mjs';
import { computePhysicalCapacity } from './physical-capacity.mjs';
import {boundedTransport} from './transport-bounds.mjs';
import {residentStrategyEnvironment} from './resident-environment.mjs';
import { checked } from './runtime-result.mjs';
import {finishManagedOutputReceipt} from './managed-output-finish.mjs';
import { retainedConfiguration } from './retained-configuration.mjs';
import { createLocalRetainedStore } from '../../../store-local/files.mjs';
import {createProcessStoreLease} from '../../../store-local/process-client.mjs';
import {retainedProcessStore} from './retained-configuration.mjs';
import { importRetainedRows } from '../../../store-local/import.mjs';
import {createMoonBitRetainedRowFrames} from
  '../../../store-local/moonbit-row-frames.mjs';
import {registerRetainedInput, retainedInputContract, consumeRetainedInput,
  retainedInputSupportsFile,
  withRetainedInputFile, retainedInputFilePath} from '../../../store-local/representations.mjs';
import {registerManagedInput} from '../../../store-local/managed-representations.mjs';
import {managedPhysicalRepresentation} from
  '../../../store-local/managed-physical-representation.mjs';
import {encodeManagedColumnFrame,
  managedColumnCodecContractCid,
  managedColumnTransferEstimate,
  managedColumnRowProvider} from './managed-column-codec.mjs';
import type {LocalRetainedStore} from '../../../store-local/files.mjs';
import type {BroadHostRuntime} from './broad-host-query.mjs';
import type {HeldRetainedComputation, NativeHostRuntime} from './native-host-query.mjs';
import type {OwnedResidentEnvironment, ResidentRuntime} from './resident-environment.mjs';
import type {OwnedSourceCapture, SourceEvidenceOptions} from './source-evidence-original.mjs';
import type {SourceFields} from './source-acquisition.mjs';
export {runManagedColumnStrategyHostCompute} from './managed-strategy-compute.mjs';
export {encodeManagedColumnFrame,
  managedColumnCodecContractCid} from './managed-column-codec.mjs';

type Limits = Parameters<typeof validateLimits>[0];
type ImportLimits = Readonly<{maxRows?: number; maxCells?: number}>;
type Retained = ReturnType<typeof retainedConfiguration>;
type Store = LocalRetainedStore | ReturnType<typeof createProcessStoreLease>;
type Writer = ReturnType<Store['reserve']>;
type Body = Awaited<ReturnType<Writer['seal']>>;
type MappingLimits = Readonly<{maxEntries: number; maxNameBytes: number}>;
type Resident = OwnedResidentEnvironment & Readonly<{inputs: unknown}>;
type FixedPort = Parameters<typeof runFixedCompute>[0];
type ResidentPort = Parameters<typeof runResidentFixedCompute>[1];
type ComputePort = FixedPort & Pick<ResidentPort, 'verifyResidentInput'>;
type FixedResult = Awaited<ReturnType<typeof runFixedCompute> | ReturnType<typeof runResidentFixedCompute>>;
type Consume = Parameters<typeof runFixedCompute>[3];
type AcceptBytes = Parameters<HeldRetainedComputation['body']['consume']>[0];
type CompletionReady = () => boolean;
type Cleanup = Readonly<{status(): {pending: boolean}; retry(): unknown}>;
type CleanupFailure = Error & {cleanupPending?: boolean; cleanupHandle?: Cleanup};
type Runtime = BroadHostRuntime & NativeHostRuntime & ResidentRuntime &
  Parameters<typeof managedPhysicalRepresentation>[5] & Readonly<{
    computeHostAbort(run: unknown): void;
    computeHostAccept(run: unknown, rows: number, data: string): unknown;
    computeHostAttempt(run: unknown): unknown;
    computeHostBegin(run: unknown, fields: string): unknown;
    computeHostCleanupRefresh(run: unknown): unknown;
    computeHostClose(run: unknown): void;
    computeHostComparisonUsage(run: unknown): unknown;
    computeHostComplete(run: unknown): unknown;
    computeHostCount(run: unknown, port: number, columns: boolean): unknown;
    computeHostFinish(run: unknown): unknown;
    computeHostImportBatch(run: unknown, port: number, rows: number,
      maxParameters: number, maxSqlBytes: number): unknown;
    computeHostImportCount(run: unknown): number;
    computeHostInputDemandColumn(run: unknown, port: number): number | undefined;
    computeHostInputDemandPhysicalAccept(run: unknown, port: number, physical: unknown,
      rows: number, data: string): unknown;
    computeHostInputDemandPhysicalBegin(run: unknown, port: number, fields: string): unknown;
    computeHostInputDemandReuse(run: unknown, port: number): boolean;
    computeHostInputFilePlan(run: unknown, port: number, wire: unknown,
      maxRowBytes: number, maxSqlBytes: number): unknown;
    computeHostInputFilePlanReuse(plan: unknown, run: unknown, port: number, verifiedCopy: () => boolean): boolean;
    computeHostInputFilePlanSql(plan: unknown): unknown;
    computeHostInputMaterial(input: unknown): object | undefined;
    computeHostInputPhysicalAccept(run: unknown, port: number, physical: unknown,
      rows: number, data: string): unknown;
    computeHostInputPhysicalBegin(run: unknown, port: number, fields: string): unknown;
    computeHostInputRead(run: unknown, port: number): unknown;
    computeHostInputStreamAppend(run: unknown, port: number, row: string, limits: unknown): unknown;
    computeHostInputStreamBegin(run: unknown, port: number, wire: unknown, maxBatchBytes: number): unknown;
    computeHostInputStreamFinish(run: unknown, port: number): unknown;
    computeHostInputStreamVerify(run: unknown, port: number, row: string, limits: unknown): unknown;
    computeHostInputValuesReuse(run: unknown, port: number): boolean;
    computeHostLogicalColumnCount(run: unknown, port: number): unknown;
    computeHostManagedOutputBegin(run: unknown, fields: string): unknown;
    computeHostManagedOutputEnableIndex(output: unknown, maxCells: number): unknown;
    computeHostMeasurementUsage(run: unknown): unknown;
    computeHostOpen(setup: unknown, verify: (attempt: unknown) => boolean): unknown;
    computeHostParameter(run: unknown, row: number, column: number, predicate: boolean, port: number): unknown;
    computeHostPhysicalCharge(run: unknown, bytes: bigint): unknown;
    computeHostPhysicalSettle(run: unknown, confirmed: boolean): unknown;
    computeHostPhysicalStart(run: unknown): unknown;
    computeHostQueryParameterCount(run: unknown): number;
    computeHostResidentInputReuse(run: unknown, inputs: unknown, port: number): unknown;
    computeHostSelectedManagedPrepare(run: unknown, authorize: () => boolean): unknown;
    computeHostSql(run: unknown, kind: number, port: number): unknown;
    computeHostStreamAccept(run: unknown, rows: number, data: string): unknown;
    computeHostStreamBegin(run: unknown, fields: string, wire: unknown, maxBatchBytes: number): unknown;
    computeHostStreamDrainBatch(run: unknown, maxBytes: number, maxRows: number): unknown;
    computeHostStreamFinish(run: unknown): unknown;
    computeHostStreamIdentity(token: unknown): unknown;
    computeHostStreamMaterial(handle: unknown): object;
    computeHostStreamReadable(handle: unknown, input: unknown): boolean;
    computeHostStreamRetain(run: unknown, token: unknown, available: () => boolean): unknown;
    computeManagedRetainedStrategyHostOpen(setup: unknown, verify: (attempt: unknown) => boolean, transferBytes: bigint,
      executionBytes: bigint, fileBytes: bigint, released: () => boolean, maxIndexCells: number): unknown;
    computeResidentCleanupSql(run: unknown): unknown;
    computeResidentCommit(run: unknown): unknown;
    computeResidentSql(run: unknown, kind: number): unknown;
    computeResidentStrategyHostOpen(setup: unknown, verify: (attempt: unknown) => boolean, transferBytes: bigint,
      executionBytes: bigint, resident: unknown): unknown;
    computeRetainedResidentStrategyHostOpen(setup: unknown, verify: (attempt: unknown) => boolean, transferBytes: bigint,
      executionBytes: bigint, resident: unknown, fileBytes: bigint, released: () => boolean): unknown;
    computeRetainedStrategyHostOpen(setup: unknown, verify: (attempt: unknown) => boolean, transferBytes: bigint,
      executionBytes: bigint, fileBytes: bigint, released: () => boolean): unknown;
    computeStrategyHostOpen(setup: unknown, verify: (attempt: unknown) => boolean, transferBytes: bigint,
      executionBytes: bigint): unknown;
    computeStrategyManagedIndexCells(setup: unknown): unknown;
    computeStrategyRetentionCapacity(setup: unknown, retained: boolean): unknown;
    computeStrategyScratchCapacity(setup: unknown, retained: boolean): unknown;
    managedInputMatchesMaterial(input: unknown, material: unknown): boolean;
    managedOutputAccept(value: unknown, rows: number, data: string): unknown;
    managedOutputAdvanceFinish(value: unknown, quantum: number): unknown;
    managedOutputCancel(value: unknown): void;
    managedOutputCompleteStrategyCompute(value: unknown, completion: unknown): unknown;
    managedOutputInputMeasurements(value: unknown): unknown;
    managedOutputLogicalComparisonUsage(value: unknown): unknown;
    managedOutputMaterial(value: unknown): object | undefined;
    managedOutputMeasurements(value: unknown): unknown;
    managedOutputRetain(value: unknown, bytes: bigint, available: () => boolean): unknown;
    managedOutputStorageOrder(value: unknown): unknown;
    managedOutputVerifyCompute(value: unknown): unknown;
    residentBorrowSetup(setup: unknown, env: unknown, tables: unknown,
      entries: number, names: number, sql: number): unknown;
    residentCancelInputs(inputs: unknown): unknown;
    residentInputDemandScanSql(inputs: unknown, port: number, column: number, maxBytes: number): string | undefined;
    residentInputScanSql(inputs: unknown, port: number, maxBytes: number): string | undefined;
    residentInputsSql(inputs: unknown): readonly string[];
}>;

const runtimeUrl = new URL('../../../../_build/js/release/build/connectors/duckdb/host_node/host_node.js', import.meta.url);
let runtime: Promise<Runtime> | undefined;
const loadRuntime = () => runtime ??= import(runtimeUrl.href);
const residentEnvironments = new WeakMap<object, OwnedResidentEnvironment>();
const {openResidentStrategyEnvironment, importResidentStrategyInput} =
  residentStrategyEnvironment(loadRuntime, residentEnvironments, rows);
export {openResidentStrategyEnvironment, importResidentStrategyInput};
const retainedComputations = new WeakMap<object, HeldRetainedComputation>();
const ownedSourceCaptures = new WeakMap<object, OwnedSourceCapture>();
const runBroadHostQuery = createBroadHostQuery(loadRuntime, ownedSourceCaptures, rows, fieldsFrame);
export {runBroadHostQuery};
const runHostNativeQuery = createNativeHostQuery(loadRuntime, ownedSourceCaptures,
  retainedComputations, rows, fieldsFrame, logicalMeasurementAccounting, logicalComparisonAccounting);

// Only a completed acquisition from this adapter has issuer custody. The
// common owner checks exact source identity and liveness without rehashing.
export function nativeSourceIdentityMatches(capture: unknown, identity: unknown) {
  const owned = ownedSourceCaptures.get(capture as object);
  return owned === undefined ? false : owned.matches(identity);
}

// Only connector-owned captures can issue evidence. The grant is never exposed
// as a JSON authority token; the current read decision is checked at issuance.
export async function issueNativeSourceEvidence(capture: unknown, options: SourceEvidenceOptions) {
  const owned = ownedSourceCaptures.get(capture as object);
  if (owned === undefined) throw new DuckDBTransportError('UnknownSourceCapture');
  return owned.issue(options);
}


// Only the original physical capture can prepare this nominal evidence. The
// existing wire-returning entry above keeps its compatibility behavior.
export async function prepareNativeSourceEvidenceOriginal(capture: unknown, options: SourceEvidenceOptions) {
  const owned = ownedSourceCaptures.get(capture as object);
  if (owned === undefined) throw new DuckDBTransportError('UnknownSourceCapture');
  return owned.prepare(options);
}

function logicalComparisonAccounting(values: unknown) {
  if (values == null) return Object.freeze({
    comparisonWork: 0, comparisonBytes: 0, comparisonNodes: 0,
  });
  if (!Array.isArray(values) || values.length !== 10) {
    throw new DuckDBTransportError('InvalidLogicalComparisonUsage');
  }
  const [comparisonWork, comparisonBytes, comparisonNodes] = values
    .slice(7)
    .map(Number);
  if (![comparisonWork, comparisonBytes, comparisonNodes].every(value =>
    Number.isSafeInteger(value) && value >= 0)) {
    throw new DuckDBTransportError('InvalidLogicalComparisonUsage');
  }
  return Object.freeze({comparisonWork, comparisonBytes, comparisonNodes});
}

function logicalMeasurementAccounting(values: unknown, prefix: 'measuredGuard' | 'reusedGuard') {
  if (values == null) return Object.freeze({
    [`${prefix}Work`]: 0, [`${prefix}Bytes`]: 0, [`${prefix}Nodes`]: 0,
  });
  if (!Array.isArray(values) || values.length !== 3 ||
      !values.every(value => Number.isSafeInteger(value) && value >= 0)) {
    throw new DuckDBTransportError('InvalidLogicalMeasurementUsage');
  }
  return Object.freeze({
    [`${prefix}Work`]: values[0],
    [`${prefix}Bytes`]: values[1],
    [`${prefix}Nodes`]: values[2],
  });
}

function registerRetained(output: object, material: object, readable: HeldRetainedComputation['readable'],
  body: HeldRetainedComputation['body'], configuration: Retained) {
  const held = Object.freeze({ readable, body, configuration });
  registerRetainedInput(material, readable, body, configuration);
  retainedComputations.set(output, held);
}

// Connector/Store implementation access: a completed output alone does not
// select a consumer. The exact admitted ProducerRead must match its material.
// accept receives provisional bounded bytes; conversion/import must not publish
// until the full read has verified successfully.
export async function consumeRetainedComputeInput(output: object, input: unknown, accept: AcceptBytes, signal?: AbortSignal) {
  const held = retainedComputations.get(output);
  if (!held || input == null || !held.readable(input)) {
    throw new DuckDBTransportError('RetainedInputUnavailable');
  }
  await held.body.consume(accept, signal);
  if (!held.readable(input)) {
    throw new DuckDBTransportError('RetainedInputUnavailable');
  }
}

// Explicit, bounded conversion for a consumer that requires Local cells. The
// source remains independently retained; no producer recomputation is involved.
export async function importRetainedComputeInput(output: object, input: unknown, limits: Parameters<typeof importRetainedRows>[2],
  signal?: AbortSignal) {
  return importRetainedRows(output,
    (accept, readSignal) => consumeRetainedComputeInput(output, input, accept, readSignal),
    limits, signal);
}

export async function runResidentStrategyHostCompute(setup: unknown, environment: unknown, tables: unknown, limits: Limits,
  mappingLimits: MappingLimits | undefined, signal?: AbortSignal, retention?: unknown, outputKey?: string,
  completionReady?: CompletionReady) {
  const retained = retention === undefined ? undefined : retainedConfiguration(retention);
  if (retained && (retained.maxFrameBytes > limits.maxTransportBytes! ||
      (retainedProcessStore(retained) &&
        (typeof outputKey !== 'string' || !outputKey.length || outputKey.length > 256)))) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  const owned = residentEnvironments.get(environment as object);
  if (!owned || !owned.database.status().live) throw new DuckDBTransportError('SessionClosed');
  limits = Object.freeze({ ...limits });
  if (limits.memoryBytes !== owned.database.memoryBytes || limits.threads !== owned.database.threads) {
    throw new DuckDBTransportError('ResidentProfileMismatch');
  }
  const moon = await loadRuntime();
  const inputs = checked(moon.residentBorrowSetup(setup, owned.env, tables,
    mappingLimits!.maxEntries, mappingLimits!.maxNameBytes, limits.maxSqlBytes!));
  return runHostCompute(
    setup, limits, undefined, signal, true, {...owned, inputs}, retained,
    outputKey, completionReady,
  );
}

// No source grant or connection enters Compute. The fixed product runtime
// supplies the selected SQL and exact owned input; verifier wiring stays here.
export async function runFixedHostCompute(setup: unknown, limits: Limits, importLimits: ImportLimits, signal?: AbortSignal) {
  return runHostCompute(setup, limits, importLimits, signal, false);
}

// Retained representation of the same owned Compute and installed completion
// verifier. The execution-process composition invokes this on its data side.
export async function runRetainedFixedHostCompute(setup: unknown, limits: Limits, importLimits: ImportLimits,
  retention: unknown, signal?: AbortSignal) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  importLimits = Object.freeze({ maxRows: importLimits?.maxRows, maxCells: importLimits?.maxCells });
  if (Object.values(importLimits).some(value => !Number.isSafeInteger(value) || value! < 0)) {
    throw new DuckDBTransportError('InvalidImportLimits');
  }
  const retained = retainedConfiguration(retention);
  return runHostCompute(setup, limits, importLimits, signal, false, undefined, retained);
}

// Same trusted transport wiring, with completion owned by the checked DAG.
export async function runStrategyHostCompute(
  setup: unknown, limits: Limits, importLimits: ImportLimits, signal?: AbortSignal, completionReady?: CompletionReady,
) {
  return runHostCompute(
    setup, limits, importLimits, signal, true, undefined, undefined,
    undefined, completionReady,
  );
}

// Same selected DAG task and common reservation/completion boundary, with
// additional independently reclaimed file storage. No private success path.
export async function runRetainedStrategyHostCompute(
  setup: unknown, limits: Limits, importLimits: ImportLimits, retention: unknown,
  signal?: AbortSignal, outputKey?: string, completionReady?: CompletionReady,
) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  importLimits = Object.freeze({ maxRows: importLimits?.maxRows, maxCells: importLimits?.maxCells });
  if (Object.values(importLimits).some(value => !Number.isSafeInteger(value) || value! < 0)) {
    throw new DuckDBTransportError('InvalidImportLimits');
  }
  const retained = retainedConfiguration(retention);
  if (retained.maxFrameBytes > limits.maxTransportBytes!) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  if (retainedProcessStore(retained) && (typeof outputKey !== 'string' || !outputKey.length || outputKey.length > 256)) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  return runHostCompute(
    setup, limits, importLimits, signal, true, undefined, retained, outputKey,
    completionReady,
  );
}

// The first managed task consumes the standard checked dispatch ticket, but
// publishes the selected task through the managed completion boundary. This
// is the product counterpart of downstream managed-to-managed dispatch.
export async function runManagedRetainedStrategyHostCompute(
  setup: unknown, limits: Limits, importLimits: ImportLimits, retention: unknown,
  signal?: AbortSignal, outputKey?: string, completionReady?: CompletionReady,
) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  importLimits = Object.freeze({
    maxRows: importLimits?.maxRows, maxCells: importLimits?.maxCells,
  });
  if (Object.values(importLimits).some(value =>
    !Number.isSafeInteger(value) || value! < 0)) {
    throw new DuckDBTransportError('InvalidImportLimits');
  }
  const retained = retainedConfiguration(retention);
  if (retained.maxFrameBytes > limits.maxTransportBytes! ||
      (retainedProcessStore(retained) &&
       (typeof outputKey !== 'string' || !outputKey.length || outputKey.length > 256))) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  return runHostCompute(
    setup, limits, importLimits, signal, true, undefined, retained, outputKey,
    completionReady, true,
  );
}

async function runHostCompute(
  setup: unknown, limits: Limits, importLimits: ImportLimits | undefined, signal: AbortSignal | undefined,
  strategy: boolean, resident?: Resident, retained?: Retained, outputKey?: string,
  completionReady: CompletionReady = () => true, managed = false,
) {
  if (typeof completionReady !== 'function') {
    throw new DuckDBTransportError('InvalidCompletionAdmission');
  }
  const moon = await loadRuntime();
  const startedInputStreams = new Set<number>();
  const beginInputStream = (port: number, wire: Retained['wire'], maxFrameBytes: number) => {
    if (!startedInputStreams.has(port)) {
      checked(moon.computeHostInputStreamBegin(run, port, wire, maxFrameBytes));
      startedInputStreams.add(port);
    }
  };
  // Freeze the same values used by both reservation and actual transport. A
  // caller mutating its limits during an await cannot enlarge the execution.
  limits = Object.freeze({ ...limits });
  let capacity: (ReturnType<typeof computePhysicalCapacity> & Readonly<{retentionBytes: bigint; receiverScratchBytes: bigint}>) | undefined;
  let result: FixedResult | undefined, port: ComputePort | undefined, consume: Consume | undefined, attempt: unknown;
  const verify = (current: unknown) => current === attempt && matchesFixedCompute(result, port, consume);
  let run: unknown;
  let store: Store | undefined, writer: Writer | undefined, body: Body | undefined, retainedHandle: unknown;
  let managedOutput: unknown, managedCompletion: unknown, managedRows = 0;
  let managedStorageOrder: readonly number[] | undefined, managedFieldsFrame: string | undefined;
  let managedIndexCells = 0;
  let cleanupRun: unknown, disposed = false;
  const storageReleased = () => store === undefined ||
    (store.status().reservedBytes === 0 && !store.status().cleanupPending);
  try {
    capacity = strategy ? Object.freeze({
      ...computePhysicalCapacity(limits),
      retentionBytes: (checked(moon.computeStrategyRetentionCapacity(setup, !!retained)) as bigint) + BigInt(retained?.wire.max_bytes ?? 0),
      receiverScratchBytes: checked(moon.computeStrategyScratchCapacity(setup, !!retained)) as bigint,
    }) : undefined;
    if (managed) managedIndexCells = checked(
      moon.computeStrategyManagedIndexCells(setup),
    ) as number;
    run = checked(managed
    ? moon.computeManagedRetainedStrategyHostOpen(
      setup, verify, capacity!.transferBytes, capacity!.executionBytes,
      BigInt(retained!.wire.max_bytes), storageReleased, managedIndexCells,
    )
    : resident && retained
    ? moon.computeRetainedResidentStrategyHostOpen(setup, verify, capacity!.transferBytes, capacity!.scratchBytes,
      resident.inputs, BigInt(retained.wire.max_bytes), storageReleased)
    : resident
    ? moon.computeResidentStrategyHostOpen(setup, verify, capacity!.transferBytes, capacity!.scratchBytes, resident.inputs)
    : strategy && retained
    ? moon.computeRetainedStrategyHostOpen(setup, verify, capacity!.transferBytes, capacity!.executionBytes,
      BigInt(retained.wire.max_bytes), storageReleased)
    : strategy
    ? moon.computeStrategyHostOpen(setup, verify, capacity!.transferBytes, capacity!.executionBytes)
    : moon.computeHostOpen(setup, verify));
  } catch (error) {
    if (resident) checked(moon.residentCancelInputs(resident.inputs));
    throw error;
  }
  if (strategy && retained) cleanupRun = run;
  attempt = moon.computeHostAttempt(run);
  if (managed) {
    managedCompletion = checked(
      moon.computeHostSelectedManagedPrepare(run, () => !disposed),
    );
  }
  let sessionStarted = false;
  let inputReadUnconfirmed = false;
  const accounting = strategy ? Object.freeze({
    started() {
      checked(moon.computeHostPhysicalStart(run));
      sessionStarted = true;
    },
    chargeTransfer(bytes: number) { checked(moon.computeHostPhysicalCharge(run, BigInt(bytes))); },
    settled(confirmed: boolean) { checked(moon.computeHostPhysicalSettle(run, confirmed && !inputReadUnconfirmed)); },
  }) : undefined;
  let began = false;
  let retainedInputBytes = 0;
  let directInputBytes = 0;
  const measureCost = process.env.ACTQL_DUCKDB_COST_DIAGNOSTICS === '1';
  const semantic = {
    costDiagnosticsEnabled: measureCost,
    nativeSemanticRows: 0,
    nativeSemanticCells: 0,
    nativeSemanticBytes: 0,
    jsMaterializedCells: 0,
    inputJsonEncodeMilliseconds: 0,
    inputMoonAdmissionMilliseconds: 0,
    outputJsonEncodeMilliseconds: 0,
    outputMoonAdmissionMilliseconds: 0,
    outputStorageMilliseconds: 0,
    outputDrainMilliseconds: 0,
    outputWriteMilliseconds: 0,
    outputDrainFrames: 0,
    outputDrainCalls: 0,
    outputWriteCalls: 0,
  };
  const retainedCleanup = Object.freeze({
    status: () => ({ pending: (store?.status().cleanupPending ?? false) || (disposed && cleanupRun !== undefined) }),
    retry: async () => {
      if (store) await store.cleanup();
      if (disposed && cleanupRun !== undefined && checked(moon.computeHostCleanupRefresh(cleanupRun))) {
        cleanupRun = undefined;
      }
      return retainedCleanup.status();
    },
  });
  const begin = (fields: SourceFields) => {
    if (!began) {
      if (managed) {
        managedFieldsFrame = fieldsFrame(fields);
        managedOutput = checked(
          moon.computeHostManagedOutputBegin(run, managedFieldsFrame),
        );
        managedStorageOrder = checked(
          moon.managedOutputStorageOrder(managedOutput),
        ) as readonly number[];
        checked(moon.computeHostManagedOutputEnableIndex(
          managedOutput, managedIndexCells,
        ));
      } else if (retained) checked(moon.computeHostStreamBegin(run, fieldsFrame(fields), retained.wire, retained.maxFrameBytes));
      else checked(moon.computeHostBegin(run, fieldsFrame(fields)));
      began = true;
    }
  };
  port = Object.freeze<ComputePort>({
    importCount: () => rows(moon.computeHostImportCount(run)),
    rowCount: port => rows(checked(moon.computeHostCount(run, port, false))),
    columnCount: port => rows(checked(moon.computeHostCount(run, port, true))),
    logicalColumnCount: port => rows(checked(
      moon.computeHostLogicalColumnCount(run, port),
    )),
    createSql: port => checked(moon.computeHostSql(run, 0, port)) as string,
    insertSql: port => checked(moon.computeHostSql(run, 1, port)) as string,
    insertBatch: (port, count) => {
      let compilerTuple2 = checked(moon.computeHostImportBatch(
        run, port, count, limits.maxParameters!, limits.maxSqlBytes!));
      const batchRows = runtimeField(compilerTuple2, 0) as number, sql = runtimeField(compilerTuple2, 1) as string;
      compilerTuple2 = undefined;
      return Object.freeze({rows: batchRows, sql});
    },
    parameter: (port, row, column) => JSON.parse(checked(moon.computeHostParameter(run, row, column, false, port)) as string),
    prepareDirectInput(port) {
      const input = checked(moon.computeHostInputRead(run, port));
      const material = moon.computeHostInputMaterial(input);
      if (material == null || !retainedInputSupportsFile(material, input)) return undefined;
      const {wire, maxFrameBytes} = retainedInputContract(material, input) as Pick<Retained, 'wire' | 'maxFrameBytes'>;
      if (maxFrameBytes > limits.maxTransportBytes!) throw new DuckDBTransportError('RetainedFrameLimit');
      const plan = checked(moon.computeHostInputFilePlan(run, port, wire, maxFrameBytes, limits.maxSqlBytes!));
      if (plan == null) return undefined; // Unsupported before native I/O, not retry.
      const sql = moon.computeHostInputFilePlanSql(plan);
      const path = retainedInputFilePath(material, input)!;
      if (/[\u0000*?\[\]]/.test(path)) return undefined;
      return Object.freeze({path, run: async session => {
        beginInputStream(port, wire, maxFrameBytes);
        inputReadUnconfirmed = true;
        let fileBytes = 0, validationRows = 0, validationCells = 0;
        await withRetainedInputFile(material, input, async file => {
          if (file.path !== path) throw new DuckDBTransportError('ForeignRetainedFile');
          fileBytes = file.bytes!;
          await session.command(runtimeField(sql, 0) as string, [{type: {id: 'VARCHAR'}, value: file.path}], () => {});
        }, signal, bytes => {
          // Physical integrity scan plus native file read, before either starts.
          // Logical consumer measurements are charged by the typed scan below.
          checked(moon.computeHostPhysicalCharge(run, BigInt(bytes) * 2n));
          directInputBytes += bytes * 2;
        });
        // The borrow has completed its final identity/integrity checks. Import
        // uses this compiled plan and the exact admitted immutable source; the
        // session is private and no table mutation occurs before this scan.
        // Number/Boolean/Text conversion is an adopted trusted implementation,
        // not evidence obtained merely from read_json accepting arbitrary JSON.
        signal?.throwIfAborted();
        const identityReused = boundedTransport(limits) && limits.threads === 1 && moon.computeHostInputFilePlanReuse(plan, run, port,
          () => !disposed && !signal?.aborted);
        let physical: unknown;
        const begin = (fields: SourceFields) => physical ??= checked(moon.computeHostInputPhysicalBegin(run, port, fieldsFrame(fields)));
        const fields = await session.command(runtimeField(sql, 1) as string, [], chunk => {
          signal?.throwIfAborted();
          begin(chunk.fields);
          const encodeStarted = measureCost ? performance.now() : 0;
          const text = JSON.stringify(chunk.columns);
          semantic.nativeSemanticRows += chunk.rowCount;
          semantic.nativeSemanticCells += chunk.rowCount * chunk.fields.length;
          semantic.nativeSemanticBytes += Buffer.byteLength(text);
          semantic.jsMaterializedCells += chunk.rowCount * chunk.fields.length;
          if (measureCost) semantic.inputJsonEncodeMilliseconds += performance.now() - encodeStarted;
          const admissionStarted = measureCost ? performance.now() : 0;
          checked(moon.computeHostInputPhysicalAccept(run, port, physical,
            rows(chunk.rowCount), text));
          if (measureCost) semantic.inputMoonAdmissionMilliseconds += performance.now() - admissionStarted;
          validationRows += chunk.rowCount;
          validationCells += chunk.rowCount * chunk.fields.length;
        });
        begin(fields);
        checked(moon.computeHostInputStreamFinish(run, port));
        inputReadUnconfirmed = false;
        return Object.freeze({fileBytes, physicalIntegrityPasses: 1, nativeFileReads: 1,
          validationRows, validationCells, logicalCidPasses: identityReused ? 0 : 1,
          identityReused,
          storedRowJsonDecodes: 0, parameterInsertRows: 0});
      }});
    },
    async verifyResidentInput(port, session) {
      const sql = moon.residentInputScanSql(resident!.inputs, port, limits.maxSqlBytes!);
      if (sql == null) return false;
      const input = checked(moon.computeHostInputRead(run, port));
      const material = moon.computeHostInputMaterial(input);
      if (material == null) return false;
      const {wire, maxFrameBytes} = retainedInputContract(material, input) as Pick<Retained, 'wire' | 'maxFrameBytes'>;
      beginInputStream(port, wire, maxFrameBytes);
      const identityReused = checked(moon.computeHostResidentInputReuse(run, resident!.inputs, port)) as boolean;
      const demandColumn = moon.computeHostInputDemandColumn(run, port);
      const demandSql = demandColumn == null ? undefined :
        moon.residentInputDemandScanSql(resident!.inputs, port, demandColumn, limits.maxSqlBytes!);
      if (identityReused && (demandColumn == null || demandSql != null) &&
          moon.computeHostInputValuesReuse(run, port)) {
        signal?.throwIfAborted();
        // Canonical per-value facts of the same reused generation discharge the
        // demand exactly; limits that need a failure position keep the scan.
        const demandReused = demandSql != null && moon.computeHostInputDemandReuse(run, port);
        if (demandSql != null && !demandReused) {
          let physical: unknown;
          const begin = (fields: SourceFields) => physical ??= checked(moon.computeHostInputDemandPhysicalBegin(
            run, port, fieldsFrame(fields)));
          const fields = await session.command(demandSql, [], chunk => {
            signal?.throwIfAborted();
            begin(chunk.fields);
            const text = JSON.stringify(chunk.columns);
            semantic.nativeSemanticRows += chunk.rowCount;
            semantic.nativeSemanticCells += chunk.rowCount;
            semantic.nativeSemanticBytes += Buffer.byteLength(text);
            semantic.jsMaterializedCells += chunk.rowCount;
            checked(moon.computeHostInputDemandPhysicalAccept(run, port, physical,
              rows(chunk.rowCount), text));
          });
          begin(fields);
        }
        checked(moon.computeHostInputStreamFinish(run, port));
        return Object.freeze({identityReused, valuesReused: true,
          demandColumnScan: demandSql != null && !demandReused, demandReused});
      }
      let physical: unknown;
      const begin = (fields: SourceFields) => physical ??= checked(moon.computeHostInputPhysicalBegin(run, port, fieldsFrame(fields)));
      const fields = await session.command(sql, [], chunk => {
        signal?.throwIfAborted();
        begin(chunk.fields);
        const encodeStarted = measureCost ? performance.now() : 0;
        const text = JSON.stringify(chunk.columns);
        semantic.nativeSemanticRows += chunk.rowCount;
        semantic.nativeSemanticCells += chunk.rowCount * chunk.fields.length;
        semantic.nativeSemanticBytes += Buffer.byteLength(text);
        semantic.jsMaterializedCells += chunk.rowCount * chunk.fields.length;
        if (measureCost) semantic.inputJsonEncodeMilliseconds += performance.now() - encodeStarted;
        const admissionStarted = measureCost ? performance.now() : 0;
        checked(moon.computeHostInputPhysicalAccept(run, port, physical,
          rows(chunk.rowCount), text));
        if (measureCost) semantic.inputMoonAdmissionMilliseconds += performance.now() - admissionStarted;
      });
      begin(fields);
      signal?.throwIfAborted();
      checked(moon.computeHostInputStreamFinish(run, port));
      return Object.freeze({identityReused});
    },
    async consumeInput(port, accept) {
      const input = checked(moon.computeHostInputRead(run, port));
      const material = moon.computeHostInputMaterial(input);
      if (material == null) return false;
      const { wire, maxFrameBytes } = retainedInputContract(material, input) as Pick<Retained, 'wire' | 'maxFrameBytes'>;
      // Do not allocate a source-configured frame larger than this receiving
      // execution's admitted scratch framing allowance.
      if (maxFrameBytes > limits.maxTransportBytes!) throw new DuckDBTransportError('RetainedFrameLimit');
      const depth = Math.min(64, Math.max(1, wire.max_depth));
      const decode = Object.freeze({ max_bytes: maxFrameBytes,
        max_nodes: Math.min(wire.max_nodes, maxFrameBytes), max_depth: depth, max_text_bytes: maxFrameBytes });
      const frames = createMoonBitRetainedRowFrames(moon,
        { maxBytes: wire.max_bytes,
        maxRows: rows(checked(moon.computeHostCount(run, port, false))),
        maxRowBytes: maxFrameBytes, maxDepth: depth, maxFrameBytes,
      }, async row => {
        signal?.throwIfAborted();
        if (resident) {
          checked(moon.computeHostInputStreamVerify(run, port, row, decode));
        } else {
          const parameters = JSON.parse(checked(moon.computeHostInputStreamAppend(run, port, row, decode)) as string);
          await accept(parameters);
        }
      });
      beginInputStream(port, wire, maxFrameBytes);
      try {
        inputReadUnconfirmed = true;
        await consumeRetainedInput(material, input, chunk => {
          // Reading retained storage is additional physical work even when
          // its decoded values are then imported through native parameters.
          // Session accounting covers those parameters, not this file read.
          checked(moon.computeHostPhysicalCharge(run, BigInt(chunk.byteLength)));
          retainedInputBytes += chunk.byteLength;
          return frames.feed(chunk, signal);
        }, signal);
        inputReadUnconfirmed = false;
        frames.finish();
        signal?.throwIfAborted();
        checked(moon.computeHostInputStreamFinish(run, port));
        return true;
      } finally { frames.cancel(); }
    },
    querySql: () => checked(moon.computeHostSql(run, 2, 0)) as string,
    queryParameters: () => Array.from({ length: moon.computeHostQueryParameterCount(run) },
      (_, index) => JSON.parse(checked(moon.computeHostParameter(run, 0, index, true, 0)) as string)),
  });
  consume = async chunk => {
    begin(chunk.fields);
    const encodeStarted = measureCost ? performance.now() : 0;
    const text = JSON.stringify(chunk.columns);
    semantic.nativeSemanticRows += chunk.rowCount;
    semantic.nativeSemanticCells += chunk.rowCount * chunk.fields.length;
    semantic.nativeSemanticBytes += Buffer.byteLength(text);
    semantic.jsMaterializedCells += chunk.rowCount * chunk.fields.length;
    if (measureCost) semantic.outputJsonEncodeMilliseconds += performance.now() - encodeStarted;
    const admissionStarted = measureCost ? performance.now() : 0;
    if (managed) {
      checked(moon.managedOutputAccept(
        managedOutput, rows(chunk.rowCount), text,
      ));
      if (measureCost) semantic.outputMoonAdmissionMilliseconds += performance.now() - admissionStarted;
      const storedFields = managedStorageOrder!.map(index => chunk.fields[index]);
      const storedColumns = managedStorageOrder!.map(index => chunk.columns[index]);
      const storageStarted = measureCost ? performance.now() : 0;
      await writer!.appendBytes(encodeManagedColumnFrame(
        storedFields, storedColumns, chunk.rowCount, managedRows,
      ));
      if (measureCost) semantic.outputStorageMilliseconds += performance.now() - storageStarted;
      managedRows += chunk.rowCount;
      signal?.throwIfAborted();
      return;
    }
    if (!retained) {
      checked(moon.computeHostAccept(run, rows(chunk.rowCount), text));
      if (measureCost) semantic.outputMoonAdmissionMilliseconds += performance.now() - admissionStarted;
      return;
    }
    checked(moon.computeHostStreamAccept(run, rows(chunk.rowCount), text));
    if (measureCost) semantic.outputMoonAdmissionMilliseconds += performance.now() - admissionStarted;
    const storageStarted = measureCost ? performance.now() : 0;
    for (;;) {
      signal?.throwIfAborted();
      const drainStarted = measureCost ? performance.now() : 0;
      const batch = checked(moon.computeHostStreamDrainBatch(
        run, retained.maxFrameBytes, Math.min(64, limits.maxChunkRows ?? 64))) as string | undefined;
      if (measureCost) semantic.outputDrainMilliseconds += performance.now() - drainStarted;
      if (batch == null) break;
      if (measureCost) {
        semantic.outputDrainCalls++;
        semantic.outputDrainFrames++;
      }
      const bytes = Buffer.byteLength(batch, 'utf8');
      if (bytes > retained.maxFrameBytes) throw new DuckDBTransportError('RetainedFrameLimit');
      const writeStarted = measureCost ? performance.now() : 0;
      await writer!.append(batch);
      if (measureCost) semantic.outputWriteMilliseconds += performance.now() - writeStarted;
      if (measureCost) semantic.outputWriteCalls++;
    }
    if (measureCost) semantic.outputStorageMilliseconds += performance.now() - storageStarted;
  };
  const finishOutput = async (fields: SourceFields) => {
    signal?.throwIfAborted();
    begin(fields); // Empty results still require metadata and an identity.
    if (managed) {
      await finishManagedOutputReceipt(quantum => checked(
        moon.managedOutputAdvanceFinish(managedOutput, quantum)), signal);
      body = await writer!.sealPhysical();
      signal?.throwIfAborted();
      checked(moon.managedOutputRetain(
        managedOutput, BigInt(body.bytes), () => body!.available(),
      ));
    } else if (retained) {
      let compilerTuple3 = checked(moon.computeHostStreamFinish(run));
      const token = runtimeField(compilerTuple3, 0), tail = runtimeField(compilerTuple3, 1) as string;
      compilerTuple3 = undefined;
      await writer!.append(tail);
      let compilerTuple4 = moon.computeHostStreamIdentity(token);
      const cid = runtimeField(compilerTuple4, 0) as string, bytes = runtimeField(compilerTuple4, 1) as number;
      compilerTuple4 = undefined;
      body = await writer!.seal({ cid, bytes });
      signal?.throwIfAborted();
      retainedHandle = checked(moon.computeHostStreamRetain(run, token, () => body!.available()));
    } else checked(moon.computeHostFinish(run));
  };
  try {
    signal?.throwIfAborted();
    if (retained) {
      const binding = retainedProcessStore(retained);
      store = binding ? createProcessStoreLease(binding, outputKey!, retained.wire.max_bytes, retained.maxFrameBytes, signal)
        : await createLocalRetainedStore({
        parentDirectory: retained.parentDirectory, capacityBytes: retained.wire.max_bytes,
        maxFrameBytes: retained.maxFrameBytes, maxEntries: 1,
      });
      signal?.throwIfAborted();
      writer = store.reserve(retained.wire.max_bytes);
      await writer.start();
      signal?.throwIfAborted();
    }
    if (resident) {
      result = await runResidentFixedCompute(resident.database, port, Object.freeze<Parameters<typeof runResidentFixedCompute>[2]>({
        viewSqls: () => moon.residentInputsSql(resident.inputs),
        createResultSql: () => checked(moon.computeResidentSql(run, 0)) as string,
        readResultSql: () => checked(moon.computeResidentSql(run, 1)) as string,
        cleanupSqls: () => checked(moon.computeResidentCleanupSql(run)) as readonly string[],
      }), limits, consume, finishOutput, signal, accounting);
      if (!completionReady()) {
        throw new DuckDBTransportError('ExecutionSiteCompletionNotReady');
      }
      checked(moon.computeResidentCommit(run));
    } else {
      result = await runFixedCompute(port, limits, importLimits as Parameters<typeof runFixedCompute>[2], consume, signal, accounting);
    }
    if (signal?.aborted) throw new DuckDBTransportError('Cancelled');
    // Resident output must validate and secure independent holding before its
    // transaction commits. Fresh execution has no persistent DB table to publish.
    if (!resident) await finishOutput(result.value.fields);
    let output: unknown;
    let material: object | undefined;
    let logicalDiagnostics = {};
    if (managed) {
      checked(moon.managedOutputVerifyCompute(managedOutput));
      if (!completionReady()) {
        throw new DuckDBTransportError('ExecutionSiteCompletionNotReady');
      }
      output = checked(moon.managedOutputCompleteStrategyCompute(
        managedOutput, managedCompletion,
      ));
      material = moon.managedOutputMaterial(managedOutput);
      if (material == null) {
        throw new DuckDBTransportError('MissingManagedOutputMaterial');
      }
      const physicalRepresentation = managedPhysicalRepresentation(
        body!,
        managedRows,
        managedColumnCodecContractCid,
        managedFieldsFrame!,
        managedStorageOrder!,
        moon,
      );
      registerManagedInput(
        material,
        input => moon.managedInputMatchesMaterial(input, material),
        store as LocalRetainedStore,
        body as Awaited<ReturnType<ReturnType<LocalRetainedStore['reserve']>['sealPhysical']>>,
        managedColumnCodecContractCid,
        physicalRepresentation.manifest,
        managedColumnRowProvider(physicalRepresentation.schemaContract),
        managedColumnTransferEstimate(
          body!.bytes,
          managedRows,
          result.value.fields,
        ),
      );
      const outputMeasurement = (checked(
        moon.managedOutputMeasurements(managedOutput),
      ) as readonly number[]).slice(1);
      logicalDiagnostics = {
        ...logicalMeasurementAccounting(outputMeasurement, 'measuredGuard'),
        ...logicalMeasurementAccounting(
          checked(moon.managedOutputInputMeasurements(managedOutput)),
          'reusedGuard',
        ),
        ...logicalComparisonAccounting(
          checked(moon.managedOutputLogicalComparisonUsage(managedOutput)),
        ),
      };
    } else {
      if (!completionReady()) {
        throw new DuckDBTransportError('ExecutionSiteCompletionNotReady');
      }
      output = checked(moon.computeHostComplete(run));
      if (retained) registerRetained(output as object, moon.computeHostStreamMaterial(retainedHandle),
        input => moon.computeHostStreamReadable(retainedHandle, input), body!, retained);
      logicalDiagnostics = {
        ...logicalMeasurementAccounting(
          checked(moon.computeHostMeasurementUsage(run)),
          'measuredGuard',
        ),
        reusedGuardWork: 0,
        reusedGuardBytes: 0,
        reusedGuardNodes: 0,
        ...logicalComparisonAccounting(
          checked(moon.computeHostComparisonUsage(run)),
        ),
      };
    }
    let closed = false;
    return Object.freeze({
      usage: Object.freeze({...result.usage,
        transportBytes: result.usage.transportBytes + retainedInputBytes + directInputBytes,
        retainedInputBytes, residentInputBytes: resident ? retainedInputBytes : 0, directInputBytes}),
      physicalCapacity: capacity === undefined ? undefined : Object.freeze({
        ...capacity, executionBytes: capacity!.executionBytes + capacity.receiverScratchBytes,
      }),
      importedRows: result.value.importedRows,
      importedCells: result.value.importedCells,
      diagnostics: Object.freeze({
        ...result.value.diagnostics,
        ...semantic,
        ...logicalDiagnostics,
      }),
      storageUsage: () => store?.status(),
      cleanupHandle: retained ? retainedCleanup : undefined,
      completed: managed ? output : undefined,
      material,
      output() {
        if (closed) throw new DuckDBTransportError('ReleasedCompute');
        return output;
      },
      async readRetained(accept: AcceptBytes, readSignal?: AbortSignal) {
        if (closed || !retained || !body?.available()) {
          throw new DuckDBTransportError('RetainedInputUnavailable');
        }
        const receipt = await body.consume(accept, readSignal);
        if (closed || !body.available()) {
          throw new DuckDBTransportError('RetainedInputUnavailable');
        }
        return receipt;
      },
      close() {
        if (closed) return;
        closed = true;
        if (managed) moon.managedOutputCancel(managedOutput);
        else if (retained) retainedComputations.delete(output as object);
        body?.close();
        store?.close();
        disposed = true;
        moon.computeHostClose(run);
        releaseFixedCompute(result!);
        // This successful session is already settled. Do not keep otherwise
        // unused completion/input buffers alive through a retained closed handle.
        output = undefined;
        material = undefined;
        managedOutput = undefined;
        managedCompletion = undefined;
        run = undefined;
        result = undefined;
        attempt = undefined;
        port = undefined;
        consume = undefined;
        if (retained && strategy) {
          return retainedCleanup.retry().then(status => {
            if (status.pending) throw new DuckDBTransportError('RetainedCleanupPending');
          }).catch(error => {
            const failure = (error instanceof Error ? error : new DuckDBTransportError('RetainedCleanupFailed')) as CleanupFailure;
            failure.cleanupHandle = retainedCleanup;
            throw failure;
          });
        }
      },
    });
  } catch (error) {
    if (managedOutput) moon.managedOutputCancel(managedOutput);
    store?.close();
    if (strategy && !sessionStarted) checked(moon.computeHostPhysicalSettle(run, true));
    moon.computeHostAbort(run);
    disposed = true;
    moon.computeHostClose(run);
    if (result !== undefined) releaseFixedCompute(result);
    if (inputReadUnconfirmed) {
      const prior = (error as CleanupFailure | null | undefined)?.cleanupHandle;
      const failure = new DuckDBTransportError('RetainedInputReadUnconfirmed', {cause: error}) as CleanupFailure;
      failure.cleanupPending = true;
      // Native settlement cannot acknowledge a failed Store read/descriptor
      // close. Without an explicit stop receipt, preserve responsibility until
      // the supervising Host confirms execution-process exit; never reread.
      failure.cleanupHandle = Object.freeze({
        status: () => ({pending: true}),
        async retry() {
          const errors = [];
          for (const handle of [prior, retainedCleanup]) {
            try { if (handle?.status().pending) await handle.retry(); }
            catch (issue) { errors.push(issue); }
          }
          if (errors.length) throw new AggregateError(errors, 'Retained input cleanup failed');
          return {pending: true};
        },
      });
      throw failure;
    }
    if (store || cleanupRun !== undefined) {
      const prior = (error as CleanupFailure | null | undefined)?.cleanupHandle;
      const failure = (error instanceof Error ? error : new DuckDBTransportError('RetainedComputeFailed')) as CleanupFailure;
      failure.cleanupHandle = Object.freeze({
        status: () => ({ pending: retainedCleanup.status().pending || !!prior?.status().pending }),
        async retry() {
          const errors = [];
          for (const handle of [prior, retainedCleanup]) {
            try { if (handle?.status().pending) await handle.retry(); }
            catch (error) { errors.push(error); }
          }
          if (errors.length) throw new AggregateError(errors, 'Retained compute cleanup failed');
          return this.status();
        },
      });
      throw failure;
    }
    throw error;
  }
}

function fieldsFrame(fields: SourceFields) {
  // Structural transport only: physical type interpretation remains MoonBit's
  // shared descriptor decoder. Names are not NFC/LF-normalized here.
  return JSON.stringify(fields.map(({ name, type }) => [
    name, type.id, type.precision === undefined ? null : String(type.precision),
    type.scale === undefined ? null : String(type.scale),
  ]));
}

function rows(value: unknown) {
  if (!Number.isSafeInteger(value) || (value as number) < 0 || (value as number) > 2147483647) {
    throw new DuckDBTransportError('InvalidHostRowCount');
  }
  return value as number;
}

// setup is an opaque NativeHostConfiguration from trusted MoonBit application
// preparation, not serialized Program JSON and not a source-file authorization.
export async function runNativeHostQuery(grant: object, setup: unknown, limits: Limits, signal?: AbortSignal) {
  return runHostNativeQuery(grant, setup, limits, signal);
}

// Same acquisition issuer, receipts and capture, with independently held output
// instead of a mandatory row-array materialization. No verifier is configurable.
export async function runRetainedNativeHostQuery(grant: object, setup: unknown, limits: Limits, retention: unknown, signal?: AbortSignal) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  const retained = retainedConfiguration(retention);
  return runHostNativeQuery(grant, setup, limits, signal, undefined, retained);
}

// The same owned ledger will receive the capture root and every later task.
// No caller-supplied verifier or accounting callback enters this standard API.
export async function runStrategyNativeHostQuery(grant: object, setup: unknown, ledger: unknown, limits: Limits, signal?: AbortSignal) {
  return runHostNativeQuery(grant, setup, limits, signal, ledger);
}

export async function runRetainedStrategyNativeHostQuery(grant: object, setup: unknown, ledger: unknown, limits: Limits,
  retention: unknown, signal?: AbortSignal, outputKey = 'capture-0') {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  const retained = retainedConfiguration(retention);
  if (ledger == null) throw new DuckDBTransportError('MissingPhysicalLedger');
  if (retainedProcessStore(retained) &&
      (typeof outputKey !== 'string' || !outputKey.length || outputKey.length > 256)) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  return runHostNativeQuery(grant, setup, limits, signal, ledger, retained, outputKey);
}
