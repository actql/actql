// Installed finite managed-profile realization for bounded Number/Text columns. The
// opaque setup fixes the checked query and completion owner; callers provide no
// SQL, verifier or content identity. Store pinning, native settlement and graph
// publication all remain inside this Host entry.
import {createLocalRetainedStore} from '../../../store-local/files.mjs';
import {registerManagedInput, withManagedInputFiles} from
  '../../../store-local/managed-representations.mjs';
import {computePhysicalCapacity} from './physical-capacity.mjs';
import {withComputeDatabase, DuckDBTransportError, validateLimits} from './session.mjs';
import {checked} from './runtime-result.mjs';
import {encodeManagedColumnFrame, managedColumnCodecContractCid,
  managedColumnTransferEstimate,
  managedColumnRowProvider} from './managed-column-codec.mjs';
import {managedParquetCodecContractCid} from './managed-parquet-codec.mjs';
import {managedPhysicalRepresentation} from
  '../../../store-local/managed-physical-representation.mjs';
import {settleFailedManagedDuckDB} from './managed-failure.mjs';

const runtimeUrl = new URL('../../../../_build/js/release/build/connectors/duckdb/host_node/host_node.js', import.meta.url);
let runtime;
const loadRuntime = () => runtime ??= import(runtimeUrl.href);

function logicalComparisonAccounting(values) {
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

function logicalMeasurementAccounting(values, prefix) {
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
  siteCompletionReady = () => true,
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
      typeof siteCompletionReady !== 'function' ||
      inputCodecContractCids.some(cid =>
        ![managedColumnCodecContractCid, managedParquetCodecContractCid]
          .includes(cid))) {
    throw new DuckDBTransportError('InvalidManagedStorageConfiguration');
  }
  const moon = await loadRuntime();
  const capacity = computePhysicalCapacity(limits);
  let store, writer, body, output, completed, run;
  let inputPhysicalBytes = 0, inputNativeScanBytes = 0;
  let inputIntegrityPasses = 0, outputFrames = 0;
  let outputValueAdmissionCells = 0, outputJsMaterializedCells = 0;
  let reusedMeasurementCells = 0;
  let outputRows = 0;
  const lifecycle = {
    sessionStarted: false,
    executionSettled: false,
    outputDisposed: false,
  };
  let authorized = true;
  const storageReleased = () => lifecycle.outputDisposed && (!store ||
    (store.status().reservedBytes === 0 && !store.status().cleanupPending));
  try {
    checked(moon.managedStrategyRetentionCapacity(setup));
    checked(moon.managedStrategyScratchCapacity(setup));
    run = checked(moon.managedStrategyHostOpen(setup, capacity.transferBytes,
      capacity.executionBytes, () => authorized && !signal?.aborted &&
        siteCompletionReady(), storageReleased));
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
    const viewSqls = inputs.map((_, index) =>
      inputCodecContractCids[index] === managedColumnCodecContractCid
        ? moon.managedStrategyInputFileViewSqlAt(run, index, limits.maxSqlBytes)
        : moon.managedStrategyInputParquetViewSqlAt(run, index, limits.maxSqlBytes));
    if (viewSqls.some(sql => typeof sql !== 'string')) {
      throw new DuckDBTransportError('UnsupportedManagedInputRepresentation');
    }
    const occurrenceSql = moon.managedStrategyOccurrenceSql(run);
    const preservesCheckedValues = typeof occurrenceSql === 'string';
    // The local Store currently offers a hard bound only through appendBytes.
    // DuckDB COPY-to-path can exceed a reservation before the post-write stat,
    // so even evidence-preserving results use the bounded sink here.
    await writer.start();
    const querySql = preservesCheckedValues
      ? occurrenceSql : checked(moon.managedStrategySql(run, false));
    const parameters = Array.from({length: moon.managedStrategyParameterCount(run)}, (_, index) =>
      JSON.parse(checked(moon.managedStrategyParameter(run, index))));
    const accounting = Object.freeze({
      started() { lifecycle.sessionStarted = true; },
      chargeTransfer(bytes) { checked(moon.managedStrategyCharge(run, BigInt(bytes))); },
      settled(confirmed) {
        checked(moon.managedStrategySettle(run, confirmed));
        if (confirmed) lifecycle.executionSettled = true;
      },
    });
    const occurrences = [];
    let storageOrder;
    const result = await withManagedInputFiles(
      inputs.map((input, index) => ({
        material: inputMaterials[index],
        input,
        codecContractCid: inputCodecContractCids[index],
      })),
      () => authorized && !signal?.aborted,
      async files => withComputeDatabase(limits, async session => {
        const discard = () => {};
        for (let index = 0; index < files.length; index++) {
          await session.createFileView(
            viewSqls[index], files[index].path, discard,
          );
        }
        if (preservesCheckedValues) {
          let outputFields;
          const fields = await session.command(querySql, parameters, async chunk => {
            signal?.throwIfAborted();
            if (chunk.fields[0]?.name !== '__actql_occurrence' ||
                chunk.fields[0]?.type.id !== 'BIGINT') {
              throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
            }
            const values = chunk.fields.slice(1);
            if (!outputFields) {
              outputFields = values;
              storageOrder = checked(moon.managedStrategyStorageOrder(
                run, fieldsFrame(outputFields)));
            }
            const valueColumns = chunk.columns.slice(1);
            for (let index = 0; index < chunk.rowCount; index++) {
              const occurrence = chunk.columns[0][index];
              if (typeof occurrence !== 'string' ||
                  !/^(0|[1-9][0-9]*)$/.test(occurrence)) {
                throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
              }
              const value = Number(occurrence);
              if (!Number.isSafeInteger(value)) {
                throw new DuckDBTransportError('InvalidManagedOccurrenceOutput');
              }
              occurrences.push(value);
            }
            const storedFields = storageOrder.map(index => outputFields[index]);
            const storedColumns = storageOrder.map(index => valueColumns[index]);
            await writer.appendBytes(encodeManagedColumnFrame(
              storedFields, storedColumns, chunk.rowCount, outputRows));
            outputRows += chunk.rowCount;
            outputJsMaterializedCells += chunk.rowCount * outputFields.length;
            reusedMeasurementCells += chunk.rowCount * outputFields.length;
            outputFrames++;
          });
          if (!outputFields) {
            outputFields = fields.slice(1);
            storageOrder = checked(moon.managedStrategyStorageOrder(
              run, fieldsFrame(outputFields)));
          }
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
          outputJsMaterializedCells += chunk.rowCount * outputFields.length;
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
      ]),
      signal,
      (indices, bytes) => {
        // A duplicate logical occurrence shares this integrity pass and pin,
        // but DuckDB still scans the admitted file once for every input view.
        // Logical consumer charges remain separate in managed demand.
        const scanBytes = bytes * indices.length;
        checked(moon.managedStrategyCharge(
          run, BigInt(bytes + scanBytes),
        ));
        inputPhysicalBytes += bytes;
        inputNativeScanBytes += scanBytes;
        inputIntegrityPasses++;
      },
    );
    signal?.throwIfAborted();
    if (preservesCheckedValues) {
      const selection = checked(moon.managedStrategySelection(run, occurrences));
      output = checked(moon.managedStrategySelectedOutputBegin(run, selection));
      checked(moon.managedStrategyOutputFinish(run, output));
    }
    body = await writer.sealPhysical();
    checked(moon.managedOutputRetain(output, BigInt(body.bytes), () => body.available()));
    completed = checked(moon.managedStrategyComplete(run, output));
    const outputMeasurement = checked(
      moon.managedOutputMeasurements(output),
    ).slice(1);
    const logicalDiagnostics = Object.freeze({
      ...logicalMeasurementAccounting(outputMeasurement, 'measuredGuard'),
      ...logicalMeasurementAccounting(
        checked(moon.managedOutputInputMeasurements(output)),
        'reusedGuard',
      ),
      ...logicalComparisonAccounting(
        checked(moon.managedStrategyComparisonUsage(run)),
      ),
    });
    const material = moon.managedOutputMaterial(output);
    if (material == null) throw new DuckDBTransportError('MissingManagedOutputMaterial');
    const codecContractCid = managedColumnCodecContractCid;
    const representation = managedPhysicalRepresentation(
      body,
      outputRows,
      codecContractCid,
      fieldsFrame(result.value),
      storageOrder,
      moon,
    );
    registerManagedInput(material,
      input => moon.managedInputMatchesMaterial(input, material),
      store, body, codecContractCid, representation.manifest,
      managedColumnRowProvider(representation.schemaContract),
      managedColumnTransferEstimate(body.bytes, outputRows, result.value));
    let closed = false;
    return Object.freeze({
      completed,
      material,
      representation: 'managed-column-file',
      usage: result.usage,
      diagnostics: Object.freeze({
        inputPhysicalBytes,
        inputNativeScanBytes,
        inputIntegrityPasses,
        nativeFileImportCommands: 0,
        nativeFileScanCommands: inputCount,
        parameterInsertRows: 0,
        logicalContentCidComputations: 0,
        outputValueAdmissionCells,
        reusedMeasurementCells,
        selectionOccurrenceRows: occurrences.length,
        outputFrames,
        outputPhysicalBytes: body.bytes,
        physicalManifestCid: representation.cid,
        directOutputCopies: 0,
        outputJsMaterializedCells,
        outputFrameReencodes: outputFrames,
        ...logicalDiagnostics,
      }),
      storageUsage: () => store.status(),
      close: async () => {
        if (closed) return;
        authorized = false;
        moon.managedOutputCancel(output);
        body.close();
        store.close();
        lifecycle.outputDisposed = true;
        try { await store.cleanup(); }
        finally {
          moon.managedStrategyClose(run);
          moon.managedStrategyRefreshRetention(run);
        }
        closed = true;
      },
    });
  } catch (reason) {
    authorized = false;
    // A pre-start failure has a confirmed zero execution. After native start,
    // only the native accounting callback may establish actual settlement.
    throw await settleFailedManagedDuckDB(moon, checked, {
      run,
      output,
      body,
      store,
      lifecycle,
    }, reason);
  }
}
