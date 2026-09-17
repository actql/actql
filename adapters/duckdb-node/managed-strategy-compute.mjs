// Installed finite managed-profile realization for bounded Number/Text columns. The
// opaque setup fixes the checked query and completion owner; callers provide no
// SQL, verifier or content identity. Store pinning, native settlement and graph
// publication all remain inside this Host entry.
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {registerManagedInput, withManagedInputFile} from '../store-local/managed-representations.mjs';
import {computePhysicalCapacity} from './physical-capacity.mjs';
import {withComputeDatabase, DuckDBTransportError, validateLimits} from './session.mjs';
import {checked} from './runtime-result.mjs';
import {encodeManagedColumnFrame, managedColumnCodecContractCid} from './managed-column-codec.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/connectors/duckdb/host_node/host_node.js', import.meta.url);
let runtime;
const loadRuntime = () => runtime ??= import(runtimeUrl.href);
function fieldsFrame(fields) {
  return JSON.stringify(fields.map(({name, type}) => [name, type.id,
    type.precision === undefined ? null : String(type.precision),
    type.scale === undefined ? null : String(type.scale)]));
}

// outputStorage is Host policy, not Program input. Its directory and framing
// are admitted before native work; capacity comes from the selected MoonBit
// setup and cannot be enlarged here.
export async function runManagedColumnStrategyHostCompute(
  setup, inputMaterial, inputCodecContractCid, limits, outputStorage, signal,
) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  if (!outputStorage || typeof outputStorage.parentDirectory !== 'string' ||
      !Number.isSafeInteger(outputStorage.maxFrameBytes) || outputStorage.maxFrameBytes < 1 ||
      inputCodecContractCid !== managedColumnCodecContractCid) {
    throw new DuckDBTransportError('InvalidManagedStorageConfiguration');
  }
  const moon = await loadRuntime();
  const capacity = computePhysicalCapacity(limits);
  let store, writer, body, output, completed, run;
  let inputPhysicalBytes = 0, outputFrames = 0;
  let outputValueAdmissionCells = 0, reusedMeasurementCells = 0;
  let outputRows = 0;
  let disposed = false;
  let authorized = true;
  const storageReleased = () => disposed && (!store ||
    (store.status().reservedBytes === 0 && !store.status().cleanupPending));
  try {
    checked(moon.managedStrategyRetentionCapacity(setup));
    checked(moon.managedStrategyScratchCapacity(setup));
    run = checked(moon.managedStrategyHostOpen(setup, capacity.transferBytes,
      capacity.executionBytes, () => authorized && !signal?.aborted, storageReleased));
    const fileCapacity = Number(moon.managedStrategyOutputFileCapacity(run));
    if (!Number.isSafeInteger(fileCapacity) || fileCapacity < 1) {
      throw new DuckDBTransportError('InvalidManagedStorageCapacity');
    }
    store = await createLocalRetainedStore({parentDirectory: outputStorage.parentDirectory,
      capacityBytes: fileCapacity, maxFrameBytes: outputStorage.maxFrameBytes, maxEntries: 1});
    writer = store.reserve(fileCapacity);
    await writer.start();
    const input = checked(moon.managedStrategyInput(run));
    const createSql = checked(moon.managedStrategySql(run, true));
    const importSql = moon.managedStrategyInputFileSql(run, limits.maxSqlBytes);
    if (typeof importSql !== 'string') {
      throw new DuckDBTransportError('UnsupportedManagedInputRepresentation');
    }
    const occurrenceSql = moon.managedStrategyOccurrenceSql(run);
    const preservesCheckedValues = typeof occurrenceSql === 'string';
    const querySql = preservesCheckedValues
      ? occurrenceSql : checked(moon.managedStrategySql(run, false));
    const parameters = Array.from({length: moon.managedStrategyParameterCount(run)}, (_, index) =>
      JSON.parse(checked(moon.managedStrategyParameter(run, index))));
    const accounting = Object.freeze({
      started() {},
      chargeTransfer(bytes) { checked(moon.managedStrategyCharge(run, BigInt(bytes))); },
      settled(confirmed) { checked(moon.managedStrategySettle(run, confirmed)); },
    });
    const occurrences = [];
    let storageOrder;
    const result = await withManagedInputFile(inputMaterial, input, inputCodecContractCid,
      () => authorized && !signal?.aborted, async file => withComputeDatabase(limits, async session => {
        const discard = () => {};
        await session.command(createSql, [], discard);
        await session.command(importSql,
          [{type: {id: 'VARCHAR'}, value: file.path}], discard);
        const fields = await session.command(querySql, parameters, async chunk => {
          signal?.throwIfAborted();
          let outputFields = chunk.fields;
          let outputColumns = chunk.columns;
          if (preservesCheckedValues) {
            if (chunk.fields[0]?.name !== '__actql_occurrence' ||
                chunk.fields[0]?.type.id !== 'BIGINT' ||
                !Array.isArray(chunk.columns[0]) ||
                chunk.columns[0].length !== chunk.rowCount) {
              throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
            }
            for (const value of chunk.columns[0]) {
              if (typeof value !== 'string' || !/^(0|[1-9][0-9]*)$/.test(value)) {
                throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
              }
              const occurrence = Number(value);
              if (!Number.isSafeInteger(occurrence)) {
                throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
              }
              occurrences.push(occurrence);
            }
            outputFields = chunk.fields.slice(1);
            outputColumns = chunk.columns.slice(1);
            reusedMeasurementCells += chunk.rowCount * outputFields.length;
          } else {
            if (!output) output = checked(moon.managedStrategyOutputBegin(run,
              fieldsFrame(outputFields)));
            checked(moon.managedOutputAccept(output, chunk.rowCount,
              JSON.stringify(outputColumns)));
            outputValueAdmissionCells += chunk.rowCount * outputFields.length;
          }
          if (!storageOrder) storageOrder = checked(moon.managedStrategyStorageOrder(
            run, fieldsFrame(outputFields)));
          const storedFields = storageOrder.map(index => outputFields[index]);
          const storedColumns = storageOrder.map(index => outputColumns[index]);
          await writer.appendBytes(encodeManagedColumnFrame(
            storedFields, storedColumns, chunk.rowCount, outputRows));
          outputRows += chunk.rowCount;
          outputFrames++;
        });
        if (!preservesCheckedValues) {
          if (!output) output = checked(moon.managedStrategyOutputBegin(run, fieldsFrame(fields)));
          checked(moon.managedStrategyOutputFinish(run, output));
        }
        return fields;
      }, signal, accounting, [file.path]), signal, bytes => {
        // One complete Store integrity pass and one native read of the exact
        // pinned file. Logical consumer charges are handled by managed demand.
        checked(moon.managedStrategyCharge(run, BigInt(bytes) * 2n));
        inputPhysicalBytes = bytes;
      });
    signal?.throwIfAborted();
    if (preservesCheckedValues) {
      const selection = checked(moon.managedStrategySelection(run, occurrences));
      output = checked(moon.managedStrategySelectedOutputBegin(run, selection));
      checked(moon.managedStrategyOutputFinish(run, output));
    }
    body = await writer.sealPhysical();
    checked(moon.managedOutputRetain(output, BigInt(body.bytes), () => body.available()));
    completed = checked(moon.managedStrategyComplete(run, output));
    const material = moon.managedOutputMaterial(output);
    if (material == null) throw new DuckDBTransportError('MissingManagedOutputMaterial');
    registerManagedInput(material,
      input => moon.managedInputMatchesMaterial(input, material),
      store, body, managedColumnCodecContractCid);
    let closed = false;
    return Object.freeze({
      completed,
      material,
      usage: result.usage,
      diagnostics: Object.freeze({
        inputPhysicalBytes,
        inputIntegrityPasses: 1,
        nativeFileImportCommands: 1,
        parameterInsertRows: 0,
        logicalContentCidComputations: 0,
        outputValueAdmissionCells,
        reusedMeasurementCells,
        selectionOccurrenceRows: occurrences.length,
        outputFrames,
        outputPhysicalBytes: body.bytes,
      }),
      storageUsage: () => store.status(),
      close: async () => {
        if (closed) return;
        authorized = false;
        moon.managedOutputCancel(output);
        body.close();
        store.close();
        disposed = true;
        try { await store.cleanup(); }
        finally {
          moon.managedStrategyClose(run);
          moon.managedStrategyRefreshRetention(run);
        }
        closed = true;
      },
    });
  } catch (error) {
    authorized = false;
    if (output) moon.managedOutputCancel(output);
    body?.close();
    store?.close();
    disposed = true;
    try { await store?.cleanup(); }
    catch (cleanupError) {
      error.cleanupErrors = Object.freeze([...(error.cleanupErrors ?? []), cleanupError]);
      error.cleanupPending = true;
      error.cleanupHandle = Object.freeze({
        status: () => Object.freeze({pending: store?.status().cleanupPending ?? false}),
        retry: async () => {
          await store?.cleanup();
          if (run) moon.managedStrategyRefreshRetention(run);
          return Object.freeze({pending: store?.status().cleanupPending ?? false});
        },
      });
    } finally {
      if (run) {
        moon.managedStrategyClose(run);
        moon.managedStrategyRefreshRetention(run);
      }
    }
    throw error;
  }
}
