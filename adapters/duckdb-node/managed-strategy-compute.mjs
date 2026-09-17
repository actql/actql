// Installed finite managed-profile realization for bounded Number/Text columns. The
// opaque setup fixes the checked query and completion owner; callers provide no
// SQL, verifier or content identity. Store pinning, native settlement and graph
// publication all remain inside this Host entry.
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {randomUUID} from 'node:crypto';
import {registerManagedInput, withManagedInputFile} from '../store-local/managed-representations.mjs';
import {computePhysicalCapacity} from './physical-capacity.mjs';
import {withComputeDatabase, DuckDBTransportError, validateLimits} from './session.mjs';
import {checked} from './runtime-result.mjs';
import {encodeManagedColumnFrame, managedColumnCodecContractCid} from './managed-column-codec.mjs';
import {managedParquetCodecContractCid} from './managed-parquet-codec.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/connectors/duckdb/host_node/host_node.js', import.meta.url);
let runtime;
const loadRuntime = () => runtime ??= import(runtimeUrl.href);
function fieldsFrame(fields) {
  return JSON.stringify(fields.map(({name, type}) => [name, type.id,
    type.precision === undefined ? null : String(type.precision),
    type.scale === undefined ? null : String(type.scale)]));
}
const identifier = name => `"${name.replaceAll('"', '""')}"`;
function directParquetSelect(querySql, fields, storageOrder) {
  if (fields[0]?.name !== '__actql_occurrence' ||
      storageOrder.length !== fields.length - 1) {
    throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
  }
  const source = '__actql_direct_output';
  const columns = storageOrder.map((field, index) =>
    `${identifier(source)}.${identifier(fields[field + 1].name)} AS ${identifier(`c${index}`)}`);
  return `SELECT ${identifier(source)}.${identifier('__actql_occurrence')} AS ` +
    `${identifier('__actql_occurrence')}, ${columns.join(', ')}, ` +
    `row_number() OVER () - 1 AS ${identifier('o')} FROM (${querySql}) AS ` +
    identifier(source);
}

async function withManagedInputFiles(
  materials, inputs, codecs, authorize, use, signal, charge,
) {
  const files = [];
  async function acquire(index) {
    if (index === inputs.length) return use(files);
    return withManagedInputFile(
      materials[index], inputs[index], codecs[index], authorize,
      async file => {
        files.push(file);
        try { return await acquire(index + 1); }
        finally { files.pop(); }
      },
      signal,
      bytes => charge(index, bytes),
    );
  }
  return acquire(0);
}

// outputStorage is Host policy, not Program input. Its directory and framing
// are admitted before native work; capacity comes from the selected MoonBit
// setup and cannot be enlarged here.
export async function runManagedColumnStrategyHostCompute(
  setup, inputMaterial, inputCodecContractCid, limits, outputStorage, signal,
) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  const inputMaterials = Array.isArray(inputMaterial)
    ? inputMaterial : [inputMaterial];
  const inputCodecContractCids = Array.isArray(inputCodecContractCid)
    ? inputCodecContractCid : [inputCodecContractCid];
  if (!outputStorage || typeof outputStorage.parentDirectory !== 'string' ||
      !Number.isSafeInteger(outputStorage.maxFrameBytes) || outputStorage.maxFrameBytes < 1 ||
      inputMaterials.length === 0 ||
      inputMaterials.length !== inputCodecContractCids.length ||
      inputCodecContractCids.some(cid =>
        ![managedColumnCodecContractCid, managedParquetCodecContractCid]
          .includes(cid))) {
    throw new DuckDBTransportError('InvalidManagedStorageConfiguration');
  }
  const moon = await loadRuntime();
  const capacity = computePhysicalCapacity(limits);
  let store, writer, body, output, completed, run, directLease, directReport;
  let inputPhysicalBytes = 0, outputFrames = 0;
  let outputValueAdmissionCells = 0, reusedMeasurementCells = 0;
  let outputRows = 0;
  let disposed = false;
  let authorized = true;
  let sessionStarted = false;
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
    const inputCount = moon.managedStrategyInputCount(run);
    if (!Number.isSafeInteger(inputCount) || inputCount !== inputMaterials.length) {
      throw new DuckDBTransportError('InvalidManagedInputCount');
    }
    const inputs = Array.from({length: inputCount}, (_, index) =>
      checked(moon.managedStrategyInputAt(run, index)));
    const createSqls = inputs.map((_, index) =>
      checked(moon.managedStrategyCreateSql(run, index)));
    const importSqls = inputs.map((_, index) =>
      inputCodecContractCids[index] === managedColumnCodecContractCid
        ? moon.managedStrategyInputFileSqlAt(run, index, limits.maxSqlBytes)
        : moon.managedStrategyInputParquetSqlAt(run, index, limits.maxSqlBytes));
    if (importSqls.some(sql => typeof sql !== 'string')) {
      throw new DuckDBTransportError('UnsupportedManagedInputRepresentation');
    }
    const occurrenceSql = moon.managedStrategyOccurrenceSql(run);
    const preservesCheckedValues = typeof occurrenceSql === 'string';
    if (preservesCheckedValues) {
      directLease = writer.delegateCreate(`duckdb-copy-${randomUUID()}`);
    } else {
      await writer.start();
    }
    const querySql = preservesCheckedValues
      ? occurrenceSql : checked(moon.managedStrategySql(run, false));
    const parameters = Array.from({length: moon.managedStrategyParameterCount(run)}, (_, index) =>
      JSON.parse(checked(moon.managedStrategyParameter(run, index))));
    const accounting = Object.freeze({
      started() { sessionStarted = true; },
      chargeTransfer(bytes) { checked(moon.managedStrategyCharge(run, BigInt(bytes))); },
      settled(confirmed) {
        checked(moon.managedStrategySettle(run, confirmed));
      },
    });
    const occurrences = [];
    let storageOrder;
    const result = await withManagedInputFiles(
      inputMaterials,
      inputs,
      inputCodecContractCids,
      () => authorized && !signal?.aborted,
      async files => withComputeDatabase(limits, async session => {
        const discard = () => {};
        for (let index = 0; index < files.length; index++) {
          await session.command(createSqls[index], [], discard);
          await session.command(importSqls[index],
            [{type: {id: 'VARCHAR'}, value: files[index].path}], discard);
        }
        if (preservesCheckedValues) {
          const fields = await session.command(
            `SELECT * FROM (${querySql}) AS ${identifier('__actql_metadata')} LIMIT 0`,
            parameters, discard);
          const outputFields = fields.slice(1);
          storageOrder = checked(moon.managedStrategyStorageOrder(
            run, fieldsFrame(outputFields)));
          directReport = await session.copyParquet(
            directParquetSelect(querySql, fields, storageOrder),
            parameters,
            directLease.path,
          );
          await session.command(
            `SELECT ${identifier('__actql_occurrence')}, ${identifier('o')} ` +
              `FROM read_parquet(?) ORDER BY ${identifier('o')}`,
            [{type: {id: 'VARCHAR'}, value: directLease.path}],
            async chunk => {
              if (chunk.fields[0]?.name !== '__actql_occurrence' ||
                  chunk.fields[0]?.type.id !== 'BIGINT' ||
                  chunk.fields[1]?.name !== 'o' ||
                  chunk.fields[1]?.type.id !== 'BIGINT') {
                throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
              }
              for (let index = 0; index < chunk.rowCount; index++) {
                const occurrence = chunk.columns[0][index];
                const ordinal = chunk.columns[1][index];
                if (typeof occurrence !== 'string' ||
                    !/^(0|[1-9][0-9]*)$/.test(occurrence) ||
                    typeof ordinal !== 'string' ||
                    ordinal !== String(outputRows)) {
                  throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
                }
                const value = Number(occurrence);
                if (!Number.isSafeInteger(value)) {
                  throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
                }
                occurrences.push(value);
                outputRows++;
              }
            },
          );
          reusedMeasurementCells = outputRows * outputFields.length;
          return outputFields;
        }
        const fields = await session.command(querySql, parameters, async chunk => {
          signal?.throwIfAborted();
          let outputFields = chunk.fields;
          let outputColumns = chunk.columns;
          if (!output) output = checked(moon.managedStrategyOutputBegin(run,
            fieldsFrame(outputFields)));
          checked(moon.managedOutputAccept(output, chunk.rowCount,
            JSON.stringify(outputColumns)));
          outputValueAdmissionCells += chunk.rowCount * outputFields.length;
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
      }, signal, accounting, [
        ...files.map(file => file.path),
        ...(directLease ? [directLease.path] : []),
      ]),
      signal,
      (_index, bytes) => {
        // One complete Store integrity pass and one native read of the exact
        // pinned file. Logical consumer charges are handled by managed demand.
        checked(moon.managedStrategyCharge(run, BigInt(bytes) * 2n));
        inputPhysicalBytes += bytes;
      },
    );
    signal?.throwIfAborted();
    if (preservesCheckedValues) {
      const selection = checked(moon.managedStrategySelection(run, occurrences));
      output = checked(moon.managedStrategySelectedOutputBegin(run, selection));
      checked(moon.managedStrategyOutputFinish(run, output));
    }
    body = directLease
      ? await writer.finishCreated({version: directLease.version,
        session: directLease.session, token: directLease.token,
        ...directReport})
      : await writer.sealPhysical();
    checked(moon.managedOutputRetain(output, BigInt(body.bytes), () => body.available()));
    completed = checked(moon.managedStrategyComplete(run, output));
    const material = moon.managedOutputMaterial(output);
    if (material == null) throw new DuckDBTransportError('MissingManagedOutputMaterial');
    registerManagedInput(material,
      input => moon.managedInputMatchesMaterial(input, material),
      store, body, directLease
        ? managedParquetCodecContractCid
        : managedColumnCodecContractCid);
    let closed = false;
    return Object.freeze({
      completed,
      material,
      representation: directLease ? 'managed-parquet-direct'
        : 'managed-column-file',
      usage: result.usage,
      diagnostics: Object.freeze({
        inputPhysicalBytes,
        inputIntegrityPasses: inputCount,
        nativeFileImportCommands: inputCount,
        parameterInsertRows: 0,
        logicalContentCidComputations: 0,
        outputValueAdmissionCells,
        reusedMeasurementCells,
        selectionOccurrenceRows: occurrences.length,
        outputFrames,
        outputPhysicalBytes: body.bytes,
        directOutputCopies: directLease ? 1 : 0,
        outputJsMaterializedCells: outputValueAdmissionCells,
        outputFrameReencodes: outputFrames,
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
    const nativeCleanup = error.cleanupPending ? error.cleanupHandle : undefined;
    const nativePending = () => {
      if (!nativeCleanup) return false;
      try { return nativeCleanup.status().pending === true; }
      catch { return true; }
    };
    const confirmDirectStopped = () => {
      if (directLease && !body && !nativePending()) {
        // Only terminal native cleanup, never an abort request, confirms that
        // DuckDB can no longer create or mutate the delegated path.
        writer?.confirmDelegatedStopped();
      }
    };
    if (directLease && !body) {
      writer?.cancel();
      confirmDirectStopped();
    }
    if (output) moon.managedOutputCancel(output);
    body?.close();
    store?.close();
    disposed = true;
    try {
      await store?.cleanup();
    } catch (cleanupError) {
      error.cleanupErrors = Object.freeze([
        ...(error.cleanupErrors ?? []), cleanupError,
      ]);
    } finally {
      if (run) {
        // A failure before the native session starts has a confirmed zero
        // physical execution. Settle that reservation before disposal; an
        // opened native session remains responsible for its own receipt.
        if (!sessionStarted) checked(moon.managedStrategySettle(run, true));
        moon.managedStrategyClose(run);
        moon.managedStrategyRefreshRetention(run);
      }
    }
    const cleanupStatus = () => Object.freeze({
      pending: nativePending() || (store?.status().cleanupPending ?? false),
    });
    if (cleanupStatus().pending || (error.cleanupErrors?.length ?? 0) > 0) {
      error.cleanupPending = cleanupStatus().pending;
      error.cleanupHandle = Object.freeze({
        status: cleanupStatus,
        retry: async () => {
          if (nativePending()) await nativeCleanup.retry();
          confirmDirectStopped();
          await store?.cleanup();
          if (run) moon.managedStrategyRefreshRetention(run);
          return cleanupStatus();
        },
      });
    }
    throw error;
  }
}
