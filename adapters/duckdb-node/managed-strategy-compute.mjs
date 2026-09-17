// Installed finite managed-profile realization for one numeric column. The
// opaque setup fixes the checked query and completion owner; callers provide no
// SQL, verifier or content identity. Store pinning, native settlement and graph
// publication all remain inside this Host entry.
import {createHash} from 'node:crypto';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {registerManagedInput, withManagedInputFile} from '../store-local/managed-representations.mjs';
import {computePhysicalCapacity} from './physical-capacity.mjs';
import {withComputeDatabase, DuckDBTransportError, validateLimits} from './session.mjs';
import {checked} from './runtime-result.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/connectors/duckdb/host_node/host_node.js', import.meta.url);
let runtime;
const loadRuntime = () => runtime ??= import(runtimeUrl.href);
const codecContract = 'actql-duckdb-managed-numeric-column-file/0.1\n' +
  'newline-delimited-object:native_columns=DOUBLE[][]\n' +
  'one-column;ordered;duplicates-preserved;store-integrity-required';

export const managedNumericColumnCodecContractCid =
  `sha256:${createHash('sha256').update(codecContract).digest('hex')}`;

function fieldsFrame(fields) {
  return JSON.stringify(fields.map(({name, type}) => [name, type.id,
    type.precision === undefined ? null : String(type.precision),
    type.scale === undefined ? null : String(type.scale)]));
}

function physicalDouble(value) {
  if (value === null) return null;
  if (typeof value !== 'string' || !/^[0-9a-f]{16}$/.test(value)) {
    throw new DuckDBTransportError('UnsupportedManagedNumericValue');
  }
  return Buffer.from(value, 'hex').readDoubleBE();
}

// outputStorage is Host policy, not Program input. Its directory and framing
// are admitted before native work; capacity comes from the selected MoonBit
// setup and cannot be enlarged here.
export async function runManagedNumericStrategyHostCompute(
  setup, inputMaterial, inputCodecContractCid, limits, outputStorage, signal,
) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  if (!outputStorage || typeof outputStorage.parentDirectory !== 'string' ||
      !Number.isSafeInteger(outputStorage.maxFrameBytes) || outputStorage.maxFrameBytes < 1 ||
      inputCodecContractCid !== managedNumericColumnCodecContractCid) {
    throw new DuckDBTransportError('InvalidManagedStorageConfiguration');
  }
  const moon = await loadRuntime();
  const capacity = computePhysicalCapacity(limits);
  let store, writer, body, output, completed, run;
  let inputPhysicalBytes = 0, outputFrames = 0;
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
    const querySql = checked(moon.managedStrategySql(run, false));
    const parameters = Array.from({length: moon.managedStrategyParameterCount(run)}, (_, index) =>
      JSON.parse(checked(moon.managedStrategyParameter(run, index))));
    const accounting = Object.freeze({
      started() {},
      chargeTransfer(bytes) { checked(moon.managedStrategyCharge(run, BigInt(bytes))); },
      settled(confirmed) { checked(moon.managedStrategySettle(run, confirmed)); },
    });
    const result = await withManagedInputFile(inputMaterial, input, inputCodecContractCid,
      () => authorized && !signal?.aborted, async file => withComputeDatabase(limits, async session => {
        const discard = () => {};
        await session.command(createSql, [], discard);
        await session.command(importSql,
          [{type: {id: 'VARCHAR'}, value: file.path}], discard);
        const fields = await session.command(querySql, parameters, async chunk => {
          signal?.throwIfAborted();
          if (!output) output = checked(moon.managedStrategyOutputBegin(run,
            fieldsFrame(chunk.fields)));
          checked(moon.managedOutputAccept(output, chunk.rowCount,
            JSON.stringify(chunk.columns)));
          if (chunk.fields.length !== 1 || chunk.fields[0].type.id !== 'DOUBLE') {
            throw new DuckDBTransportError('UnsupportedManagedNumericOutput');
          }
          const native = chunk.columns[0].map(physicalDouble);
          await writer.appendBytes(Buffer.from(JSON.stringify({native_columns: [native]}) + '\n'));
          outputFrames++;
        });
        if (!output) output = checked(moon.managedStrategyOutputBegin(run, fieldsFrame(fields)));
        checked(moon.managedStrategyOutputFinish(run, output));
        return fields;
      }, signal, accounting, [file.path]), signal, bytes => {
        // One complete Store integrity pass and one native read of the exact
        // pinned file. Logical consumer charges are handled by managed demand.
        checked(moon.managedStrategyCharge(run, BigInt(bytes) * 2n));
        inputPhysicalBytes = bytes;
      });
    signal?.throwIfAborted();
    body = await writer.sealPhysical();
    checked(moon.managedOutputRetain(output, BigInt(body.bytes), () => body.available()));
    completed = checked(moon.managedStrategyComplete(run, output));
    const material = moon.managedOutputMaterial(output);
    if (material == null) throw new DuckDBTransportError('MissingManagedOutputMaterial');
    registerManagedInput(material,
      input => moon.managedInputMatchesMaterial(input, material),
      store, body, managedNumericColumnCodecContractCid);
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
