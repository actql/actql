// Standard source-checkout Host entry. Neither Program inputs nor ordinary
// Connector registration can supply a replacement runtime/verifier/SQL callback.
import { randomUUID } from 'node:crypto';
import { runNativeQuery } from './native-query.mjs';
import { runBroadQuery } from './broad-query.mjs';
import { runFixedCompute, runResidentFixedCompute, matchesFixedCompute, releaseFixedCompute } from './fixed-compute.mjs';
import { DuckDBTransportError, provisionComputeDatabase, validateLimits } from './session.mjs';
import { computePhysicalCapacity } from './physical-capacity.mjs';
import {boundedTransport} from './transport-bounds.mjs';
import {createImportBatch} from './import-batch.mjs';
import { checked } from './runtime-result.mjs';
import { retainedConfiguration } from './retained-configuration.mjs';
import { createLocalRetainedStore } from '../store-local/files.mjs';
import {createProcessStoreLease} from '../store-local/process-client.mjs';
import {retainedProcessStore} from './retained-configuration.mjs';
import { importRetainedRows } from '../store-local/import.mjs';
import { createRetainedRowFrames } from '../store-local/row-frames.mjs';
import {registerRetainedInput, retainedInputContract, consumeRetainedInput,
  retainedStorageBody, retainedStorageContract} from '../store-local/representations.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/connectors/duckdb/host_node/host_node.js', import.meta.url);
let runtime;
const loadRuntime = () => runtime ??= import(runtimeUrl.href);
const residentEnvironments = new WeakMap();
const retainedComputations = new WeakMap();

function registerRetained(output, material, readable, body, configuration) {
  const held = Object.freeze({ readable, body, configuration });
  registerRetainedInput(material, readable, body, configuration);
  retainedComputations.set(output, held);
}

// Connector/Store implementation access: a completed output alone does not
// select a consumer. The exact admitted ProducerRead must match its material.
// accept receives provisional bounded bytes; conversion/import must not publish
// until the full read has verified successfully.
export async function consumeRetainedComputeInput(output, input, accept, signal) {
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
export async function importRetainedComputeInput(output, input, limits, signal) {
  return importRetainedRows(output,
    (accept, readSignal) => consumeRetainedComputeInput(output, input, accept, readSignal),
    limits, signal);
}

// Supply a run-owned local environment only after MoonBit has reserved the
// selected capacity. No existing file or source connection can be attached.
export async function openResidentStrategyEnvironment(graph, task, limits) {
  const moon = await loadRuntime();
  limits = validateLimits(limits);
  const capacity = computePhysicalCapacity(limits);
  const env = checked(moon.residentBegin(graph, task, capacity.databaseBytes));
  let database;
  let started = false;
  let released = false;
  const cleanupStatus = () => Object.freeze({ pending: !released });
  const cleanup = async () => {
    if (!released) {
      checked(moon.residentClose(graph, env, false));
      if (database) await database.close();
      else if (!started) {
        // No provider work was sent. An absent returned handle alone is not
        // sufficient: started-but-unknown provision must keep its reservation.
        checked(moon.residentClose(graph, env, true));
        released = true;
      }
    }
    return cleanupStatus();
  };
  const cleanupHandle = Object.freeze({ status: cleanupStatus, retry: cleanup });
  try {
    database = await provisionComputeDatabase(limits, Object.freeze({
      started() { started = true; },
      settled(confirmed) {
        if (released) return;
        checked(moon.residentClose(graph, env, confirmed));
        if (confirmed) released = true;
      },
    }));
    checked(moon.residentConfirm(graph, env, BigInt(database.memoryBytes)));
  } catch (error) {
    try { await cleanup(); }
    catch (cleanupError) { error.cleanupErrors = Object.freeze([cleanupError]); }
    if (!released) {
      error.cleanupPending = true;
      error.cleanupHandle = cleanupHandle;
    }
    throw error;
  }
  const handle = Object.freeze({
    status: () => Object.freeze({ ...database.status(), pending: !released }),
    table(producer) { return checked(moon.residentTableAt(graph, env, producer)); },
    hasTable(producer) { return moon.residentHasTable(graph, env, producer); },
    async close() {
      if (released) return;
      try {
        await cleanup();
        if (!released) throw new DuckDBTransportError('CleanupInProgress');
      } catch (error) {
        error.cleanupPending = !released;
        if (!released) error.cleanupHandle = cleanupHandle;
        throw error;
      }
      residentEnvironments.delete(handle);
    },
  });
  residentEnvironments.set(handle, { graph, env, database, limits });
  return handle;
}

export async function importResidentStrategyInput(environment, producer, tableBytes, limits, mappingLimits, signal) {
  const owned = residentEnvironments.get(environment);
  if (!owned || !owned.database.status().live) throw new DuckDBTransportError('SessionClosed');
  const moon = await loadRuntime();
  limits = validateLimits(limits);
  if (limits.memoryBytes !== owned.database.memoryBytes || limits.threads !== owned.database.threads) {
    throw new DuckDBTransportError('EnvironmentMismatch');
  }
  const capacity = computePhysicalCapacity(limits);
  const table = checked(moon.residentTablePrepare(owned.graph, owned.env, producer,
    BigInt(tableBytes), mappingLimits.maxEntries, mappingLimits.maxNameBytes, limits.maxSqlBytes));
  let count, columns, transfer, batchRows = 1;
  const compileBatch = requested => {
    const {_0: rows, _1: sql} = checked(moon.residentImportBatch(table, requested,
      limits.maxParameters, limits.maxSqlBytes));
    return {rows, sql};
  };
  try {
    count = rows(checked(moon.residentImportCount(table, false)));
    columns = rows(checked(moon.residentImportCount(table, true)));
    if (count > limits.maxRows || columns > limits.maxColumns || columns > limits.maxParameters ||
        columns === 0 || count > Math.floor(limits.maxCells / columns)) {
      throw new DuckDBTransportError('InvalidImportLimits');
    }
    if (boundedTransport(limits) && count > 1) {
      batchRows = compileBatch(Math.min(count, limits.maxChunkRows,
        Math.floor(limits.maxParameters / columns))).rows;
    }
    transfer = checked(moon.residentTransferBegin(owned.graph, table,
      capacity.transferBytes, capacity.scratchBytes));
  } catch (error) {
    // Synchronous preparation only: no import attempt or native work exists.
    checked(moon.residentTableCancel(owned.graph, table));
    throw error;
  }
  let started = false;
  let storageReadBytes = 0, storageReadUnconfirmed = false;
  try {
    const result = await owned.database.run(limits, async session => {
      const discard = () => {};
      await session.command(checked(moon.residentImportSql(table, false)), [], discard);
      const sql = checked(moon.residentImportSql(table, true));
      const batch = batchRows > 1 ? createImportBatch(columns, batchRows, limits,
        compileBatch, (sql, parameters) => session.insert(sql, parameters, discard), signal) : undefined;
      const append = parameters => batch ? batch.append(parameters) : session.insert(sql, parameters, discard);
      const material = checked(moon.residentImportMaterial(table));
      if (material != null) {
        const body = retainedStorageBody(material);
        const {wire, maxFrameBytes} = retainedStorageContract(material);
        if (maxFrameBytes > (limits.maxChunkBytes ?? limits.maxTransportBytes)) {
          throw new DuckDBTransportError('RetainedFrameLimit');
        }
        const decode = {max_bytes: maxFrameBytes,
          max_nodes: Math.min(wire.max_nodes, maxFrameBytes),
          max_depth: Math.min(64, wire.max_depth), max_text_bytes: maxFrameBytes};
        const stream = checked(moon.residentImportStreamBegin(table, count,
          {max_nodes: wire.max_nodes, max_text_bytes: wire.max_bytes, max_work: wire.max_order_work},
          wire, maxFrameBytes));
        const frames = createRetainedRowFrames({maxBytes: wire.max_bytes, maxRows: count,
          maxRowBytes: maxFrameBytes, maxFrameBytes, maxDepth: decode.max_depth}, async row => {
          const parameters = JSON.parse(checked(moon.residentImportStreamAppend(stream, row, decode)));
          await append(parameters);
        });
        try {
          storageReadUnconfirmed = true;
          await body.consume(async chunk => {
            checked(moon.residentTransferCharge(owned.graph, transfer, BigInt(chunk.byteLength)));
            storageReadBytes += chunk.byteLength;
            await frames.feed(chunk, signal);
          }, signal);
          storageReadUnconfirmed = false;
          frames.finish();
          signal?.throwIfAborted();
          checked(moon.residentImportStreamFinish(stream));
          // Verify the complete immutable input before flushing its final
          // partial batch. Earlier writes remain transaction-local on failure.
          await batch?.finish();
        } finally {
          frames.cancel();
          moon.residentImportStreamCancel(stream);
        }
        return;
      }
      for (let row = 0; row < count; row++) {
        signal?.throwIfAborted();
        const parameters = [];
        for (let column = 0; column < columns; column++) {
          parameters.push(JSON.parse(checked(moon.residentImportParameter(table, row, column,
            limits.maxTransportBytes, mappingLimits.maxEntries))));
        }
        // The shared environment outlives this import, but the reusable INSERT
        // belongs only to its task connection and is explicitly destroyed at
        // settlement. Reuse does not bypass per-row transfer/parameter checks.
        await append(parameters);
      }
      await batch?.finish();
    }, signal, Object.freeze({
      started() { started = true; },
      chargeTransfer(bytes) { checked(moon.residentTransferCharge(owned.graph, transfer, BigInt(bytes))); },
      settled(confirmed) {
        checked(moon.residentTransferSettle(owned.graph, transfer, confirmed && !storageReadUnconfirmed));
      },
    }));
    checked(moon.residentTransferComplete(owned.graph, transfer));
    return Object.freeze({ table, importedRows: count, importedCells: count * columns, batchRows,
      usage: Object.freeze({...result.usage, storageReadBytes,
        transportBytes: result.usage.transportBytes + storageReadBytes}) });
  } catch (error) {
    checked(moon.residentTransferAbort(owned.graph, transfer));
    if (!started) checked(moon.residentTransferSettle(owned.graph, transfer, true));
    if (storageReadUnconfirmed) {
      const failure = new DuckDBTransportError('ResidentStorageReadUnconfirmed', {cause: error});
      failure.cleanupPending = true;
      // No file-close acknowledgement is available after a failed Store read.
      // Do not retry the import or claim that closing the DB closed this file.
      failure.cleanupHandle = Object.freeze({
        status: () => ({pending: true}),
        async retry() { await error?.cleanupHandle?.retry(); return {pending: true}; },
      });
      throw failure;
    }
    throw error;
  }
}

export async function runResidentStrategyHostCompute(setup, environment, tables, limits, mappingLimits, signal,
  retention, outputKey) {
  const retained = retention === undefined ? undefined : retainedConfiguration(retention);
  if (retained && (retained.maxFrameBytes > limits.maxTransportBytes ||
      (retainedProcessStore(retained) &&
        (typeof outputKey !== 'string' || !outputKey.length || outputKey.length > 256)))) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  const owned = residentEnvironments.get(environment);
  if (!owned || !owned.database.status().live) throw new DuckDBTransportError('SessionClosed');
  limits = Object.freeze({ ...limits });
  if (limits.memoryBytes !== owned.database.memoryBytes || limits.threads !== owned.database.threads) {
    throw new DuckDBTransportError('ResidentProfileMismatch');
  }
  const moon = await loadRuntime();
  const inputs = checked(moon.residentBorrowSetup(setup, owned.env, tables,
    mappingLimits.maxEntries, mappingLimits.maxNameBytes, limits.maxSqlBytes));
  return runHostCompute(setup, limits, undefined, signal, true, { ...owned, inputs }, retained, outputKey);
}

// No source grant or connection enters Compute. The fixed product runtime
// supplies the selected SQL and exact owned input; verifier wiring stays here.
export async function runFixedHostCompute(setup, limits, importLimits, signal) {
  return runHostCompute(setup, limits, importLimits, signal, false);
}

// Retained representation of the same owned Compute and installed completion
// verifier. The execution-process composition invokes this on its data side.
export async function runRetainedFixedHostCompute(setup, limits, importLimits, retention, signal) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  importLimits = Object.freeze({ maxRows: importLimits?.maxRows, maxCells: importLimits?.maxCells });
  if (Object.values(importLimits).some(value => !Number.isSafeInteger(value) || value < 0)) {
    throw new DuckDBTransportError('InvalidImportLimits');
  }
  const retained = retainedConfiguration(retention);
  return runHostCompute(setup, limits, importLimits, signal, false, undefined, retained);
}

// Same trusted transport wiring, with completion owned by the checked DAG.
export async function runStrategyHostCompute(setup, limits, importLimits, signal) {
  return runHostCompute(setup, limits, importLimits, signal, true);
}

// Same selected DAG task and common reservation/completion boundary, with
// additional independently reclaimed file storage. No private success path.
export async function runRetainedStrategyHostCompute(setup, limits, importLimits, retention, signal, outputKey) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  importLimits = Object.freeze({ maxRows: importLimits?.maxRows, maxCells: importLimits?.maxCells });
  if (Object.values(importLimits).some(value => !Number.isSafeInteger(value) || value < 0)) {
    throw new DuckDBTransportError('InvalidImportLimits');
  }
  const retained = retainedConfiguration(retention);
  if (retained.maxFrameBytes > limits.maxTransportBytes) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  if (retainedProcessStore(retained) && (typeof outputKey !== 'string' || !outputKey.length || outputKey.length > 256)) {
    throw new DuckDBTransportError('InvalidRetainedConfiguration');
  }
  return runHostCompute(setup, limits, importLimits, signal, true, undefined, retained, outputKey);
}

async function runHostCompute(setup, limits, importLimits, signal, strategy, resident, retained, outputKey) {
  const moon = await loadRuntime();
  // Freeze the same values used by both reservation and actual transport. A
  // caller mutating its limits during an await cannot enlarge the execution.
  limits = Object.freeze({ ...limits });
  let capacity;
  let result, port, consume, attempt;
  const verify = current => current === attempt && matchesFixedCompute(result, port, consume);
  let run;
  let store, writer, body, retainedHandle;
  let cleanupRun, disposed = false;
  const storageReleased = () => store === undefined ||
    (store.status().reservedBytes === 0 && !store.status().cleanupPending);
  try {
    capacity = strategy ? Object.freeze({
      ...computePhysicalCapacity(limits),
      retentionBytes: checked(moon.computeStrategyRetentionCapacity(setup, !!retained)) + BigInt(retained?.wire.max_bytes ?? 0),
      receiverScratchBytes: checked(moon.computeStrategyScratchCapacity(setup, !!retained)),
    }) : undefined;
    run = checked(resident && retained
    ? moon.computeRetainedResidentStrategyHostOpen(setup, verify, capacity.transferBytes, capacity.scratchBytes,
      resident.inputs, BigInt(retained.wire.max_bytes), storageReleased)
    : resident
    ? moon.computeResidentStrategyHostOpen(setup, verify, capacity.transferBytes, capacity.scratchBytes, resident.inputs)
    : strategy && retained
    ? moon.computeRetainedStrategyHostOpen(setup, verify, capacity.transferBytes, capacity.executionBytes,
      BigInt(retained.wire.max_bytes), storageReleased)
    : strategy
    ? moon.computeStrategyHostOpen(setup, verify, capacity.transferBytes, capacity.executionBytes)
    : moon.computeHostOpen(setup, verify));
  } catch (error) {
    if (resident) checked(moon.residentCancelInputs(resident.inputs));
    throw error;
  }
  if (strategy && retained) cleanupRun = run;
  attempt = moon.computeHostAttempt(run);
  let sessionStarted = false;
  let inputReadUnconfirmed = false;
  const accounting = strategy ? Object.freeze({
    started() { sessionStarted = true; },
    chargeTransfer(bytes) { checked(moon.computeHostPhysicalCharge(run, BigInt(bytes))); },
    settled(confirmed) { checked(moon.computeHostPhysicalSettle(run, confirmed && !inputReadUnconfirmed)); },
  }) : undefined;
  let began = false;
  let residentInputBytes = 0;
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
  const begin = fields => {
    if (!began) {
      if (retained) checked(moon.computeHostStreamBegin(run, fieldsFrame(fields), retained.wire, retained.maxFrameBytes));
      else checked(moon.computeHostBegin(run, fieldsFrame(fields)));
      began = true;
    }
  };
  port = Object.freeze({
    importCount: () => rows(moon.computeHostImportCount(run)),
    rowCount: port => rows(checked(moon.computeHostCount(run, port, false))),
    columnCount: port => rows(checked(moon.computeHostCount(run, port, true))),
    createSql: port => checked(moon.computeHostSql(run, 0, port)),
    insertSql: port => checked(moon.computeHostSql(run, 1, port)),
    insertBatch: (port, count) => {
      const {_0: batchRows, _1: sql} = checked(moon.computeHostImportBatch(
        run, port, count, limits.maxParameters, limits.maxSqlBytes));
      return Object.freeze({rows: batchRows, sql});
    },
    parameter: (port, row, column) => JSON.parse(checked(moon.computeHostParameter(run, row, column, false, port))),
    async consumeInput(port, accept) {
      const input = checked(moon.computeHostInputRead(run, port));
      const material = moon.computeHostInputMaterial(input);
      if (material == null) return false;
      const { wire, maxFrameBytes } = retainedInputContract(material, input);
      // Do not allocate a source-configured frame larger than this receiving
      // execution's admitted scratch framing allowance.
      if (maxFrameBytes > limits.maxTransportBytes) throw new DuckDBTransportError('RetainedFrameLimit');
      const depth = Math.min(64, Math.max(1, wire.max_depth));
      const decode = Object.freeze({ max_bytes: maxFrameBytes,
        max_nodes: Math.min(wire.max_nodes, maxFrameBytes), max_depth: depth, max_text_bytes: maxFrameBytes });
      const frames = createRetainedRowFrames({ maxBytes: wire.max_bytes,
        maxRows: rows(checked(moon.computeHostCount(run, port, false))),
        maxRowBytes: maxFrameBytes, maxDepth: depth, maxFrameBytes,
      }, async row => {
        signal?.throwIfAborted();
        if (resident) {
          checked(moon.computeHostInputStreamVerify(run, port, row, decode));
        } else {
          const parameters = JSON.parse(checked(moon.computeHostInputStreamAppend(run, port, row, decode)));
          await accept(parameters);
        }
      });
      checked(moon.computeHostInputStreamBegin(run, port, wire, maxFrameBytes));
      try {
        inputReadUnconfirmed = true;
        await consumeRetainedInput(material, input, chunk => {
          if (resident) {
            checked(moon.computeHostPhysicalCharge(run, BigInt(chunk.byteLength)));
            residentInputBytes += chunk.byteLength;
          }
          return frames.feed(chunk, signal);
        }, signal);
        inputReadUnconfirmed = false;
        frames.finish();
        signal?.throwIfAborted();
        checked(moon.computeHostInputStreamFinish(run, port));
        return true;
      } finally { frames.cancel(); }
    },
    querySql: () => checked(moon.computeHostSql(run, 2, 0)),
    queryParameters: () => Array.from({ length: moon.computeHostQueryParameterCount(run) },
      (_, index) => JSON.parse(checked(moon.computeHostParameter(run, 0, index, true, 0)))),
  });
  consume = async chunk => {
    begin(chunk.fields);
    if (!retained) {
      checked(moon.computeHostAccept(run, rows(chunk.rowCount), JSON.stringify(chunk.columns)));
      return;
    }
    checked(moon.computeHostStreamAccept(run, rows(chunk.rowCount), JSON.stringify(chunk.columns)));
    let parts = [], bufferedBytes = 0;
    const flush = async () => {
      if (!parts.length) return;
      // Storage framing only: canonical text comes exclusively from MoonBit.
      // One bounded frame avoids issuing a filesystem write for every row.
      const text = parts.join('');
      parts = []; bufferedBytes = 0;
      await writer.append(text);
      signal?.throwIfAborted();
    };
    for (;;) {
      signal?.throwIfAborted();
      const batch = checked(moon.computeHostStreamDrain(run));
      if (batch == null) break;
      const bytes = Buffer.byteLength(batch, 'utf8');
      if (bytes > retained.maxFrameBytes) throw new DuckDBTransportError('RetainedFrameLimit');
      if (bytes > retained.maxFrameBytes - bufferedBytes) await flush();
      parts.push(batch); bufferedBytes += bytes;
    }
    await flush();
  };
  const finishOutput = async fields => {
    signal?.throwIfAborted();
    begin(fields); // Empty results still require metadata and an identity.
    if (retained) {
      const { _0: token, _1: tail } = checked(moon.computeHostStreamFinish(run));
      await writer.append(tail);
      const { _0: cid, _1: bytes } = moon.computeHostStreamIdentity(token);
      body = await writer.seal({ cid, bytes });
      signal?.throwIfAborted();
      retainedHandle = checked(moon.computeHostStreamRetain(run, token, () => body.available()));
    } else checked(moon.computeHostFinish(run));
  };
  try {
    signal?.throwIfAborted();
    if (retained) {
      const binding = retainedProcessStore(retained);
      store = binding ? createProcessStoreLease(binding, outputKey, retained.wire.max_bytes, retained.maxFrameBytes, signal)
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
      result = await runResidentFixedCompute(resident.database, port, Object.freeze({
        viewSqls: () => moon.residentInputsSql(resident.inputs),
        createResultSql: () => checked(moon.computeResidentSql(run, 0)),
        readResultSql: () => checked(moon.computeResidentSql(run, 1)),
        cleanupSqls: () => checked(moon.computeResidentCleanupSql(run)),
      }), limits, consume, finishOutput, signal, accounting);
      checked(moon.computeResidentCommit(run));
    } else {
      result = await runFixedCompute(port, limits, importLimits, consume, signal, accounting);
    }
    if (signal?.aborted) throw new DuckDBTransportError('Cancelled');
    // Resident output must validate and secure independent holding before its
    // transaction commits. Fresh execution has no persistent DB table to publish.
    if (!resident) await finishOutput(result.value.fields);
    let output = checked(moon.computeHostComplete(run));
    if (retained) registerRetained(output, moon.computeHostStreamMaterial(retainedHandle),
      input => moon.computeHostStreamReadable(retainedHandle, input), body, retained);
    let closed = false;
    return Object.freeze({
      usage: Object.freeze({...result.usage,
        transportBytes: result.usage.transportBytes + residentInputBytes,
        residentInputBytes}),
      physicalCapacity: capacity === undefined ? undefined : Object.freeze({
        ...capacity, executionBytes: capacity.executionBytes + capacity.receiverScratchBytes,
      }),
      importedRows: result.value.importedRows,
      importedCells: result.value.importedCells,
      diagnostics: result.value.diagnostics,
      storageUsage: () => store?.status(),
      cleanupHandle: retained ? retainedCleanup : undefined,
      output() {
        if (closed) throw new DuckDBTransportError('ReleasedCompute');
        return output;
      },
      close() {
        if (closed) return;
        closed = true;
        if (retained) retainedComputations.delete(output);
        body?.close();
        store?.close();
        disposed = true;
        moon.computeHostClose(run);
        releaseFixedCompute(result);
        // This successful session is already settled. Do not keep otherwise
        // unused completion/input buffers alive through a retained closed handle.
        output = undefined;
        run = undefined;
        result = undefined;
        attempt = undefined;
        port = undefined;
        consume = undefined;
        if (retained && strategy) {
          return retainedCleanup.retry().then(status => {
            if (status.pending) throw new DuckDBTransportError('RetainedCleanupPending');
          }).catch(error => {
            const failure = error instanceof Error ? error : new DuckDBTransportError('RetainedCleanupFailed');
            failure.cleanupHandle = retainedCleanup;
            throw failure;
          });
        }
      },
    });
  } catch (error) {
    store?.close();
    if (strategy && !sessionStarted) checked(moon.computeHostPhysicalSettle(run, true));
    moon.computeHostAbort(run);
    disposed = true;
    moon.computeHostClose(run);
    if (result !== undefined) releaseFixedCompute(result);
    if (inputReadUnconfirmed) {
      const prior = error?.cleanupHandle;
      const failure = new DuckDBTransportError('RetainedInputReadUnconfirmed', {cause: error});
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
      const prior = error?.cleanupHandle;
      const failure = error instanceof Error ? error : new DuckDBTransportError('RetainedComputeFailed');
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

function fieldsFrame(fields) {
  // Structural transport only: physical type interpretation remains MoonBit's
  // shared descriptor decoder. Names are not NFC/LF-normalized here.
  return JSON.stringify(fields.map(({ name, type }) => [
    name, type.id, type.precision === undefined ? null : String(type.precision),
    type.scale === undefined ? null : String(type.scale),
  ]));
}

function rows(value) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 2147483647) {
    throw new DuckDBTransportError('InvalidHostRowCount');
  }
  return value;
}

// setup is an opaque NativeHostConfiguration from trusted MoonBit application
// preparation, not serialized Program JSON and not a source-file authorization.
export async function runNativeHostQuery(grant, setup, limits, signal) {
  return runHostNativeQuery(grant, setup, limits, signal);
}

// Same acquisition issuer, receipts and capture, with independently held output
// instead of a mandatory row-array materialization. No verifier is configurable.
export async function runRetainedNativeHostQuery(grant, setup, limits, retention, signal) {
  signal?.throwIfAborted();
  limits = validateLimits(limits);
  const retained = retainedConfiguration(retention);
  return runHostNativeQuery(grant, setup, limits, signal, undefined, retained);
}

// The same owned ledger will receive the capture root and every later task.
// No caller-supplied verifier or accounting callback enters this standard API.
export async function runStrategyNativeHostQuery(grant, setup, ledger, limits, signal) {
  return runHostNativeQuery(grant, setup, limits, signal, ledger);
}

export async function runRetainedStrategyNativeHostQuery(grant, setup, ledger, limits, retention, signal, outputKey = 'capture-0') {
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

async function runHostNativeQuery(grant, setup, limits, signal, ledger, retained, outputKey) {
  const moon = await loadRuntime();
  limits = Object.freeze({ ...limits });
  const capacity = ledger === undefined ? undefined : Object.freeze({
    ...computePhysicalCapacity(limits),
    retentionBytes: checked((retained ? moon.nativeRetainedHostCapacity : moon.nativeHostCapacity)(setup, true)) + BigInt(retained?.wire.max_bytes ?? 0),
    receiverScratchBytes: checked((retained ? moon.nativeRetainedHostCapacity : moon.nativeHostCapacity)(setup, false)),
  });
  let capturedRun;
  let store, writer, body, retainedHandle, retainedOutput;
  const retainedCleanup = Object.freeze({
    status: () => ({ pending: store?.status().cleanupPending ?? false }),
    retry: async () => {
      if (store) await store.cleanup();
      if (capacity !== undefined && capturedRun !== undefined) moon.nativeHostPhysicalRefresh(capturedRun);
      return retainedCleanup.status();
    },
  });
  let sessionStarted = false;
  const accounting = capacity === undefined ? undefined : Object.freeze({
    started() { sessionStarted = true; },
    chargeTransfer(bytes) { checked(moon.nativeHostPhysicalCharge(capturedRun, BigInt(bytes))); },
    settled(confirmed) { checked(moon.nativeHostPhysicalSettle(capturedRun, confirmed)); },
  });
  const captured = await runNativeQuery(grant, verify => {
    const run = checked(capacity === undefined
      ? moon.nativeHostOpen(setup, randomUUID(), verify)
      : retained
        ? moon.nativeRetainedStrategyHostOpen(setup, ledger, randomUUID(), verify,
          capacity.transferBytes, capacity.executionBytes, BigInt(retained.wire.max_bytes),
          retained.maxFrameBytes,
          () => !store || store.status().reservedBytes === 0)
        : moon.nativeStrategyHostOpen(setup, ledger, randomUUID(), verify,
          capacity.transferBytes, capacity.executionBytes));
    capturedRun = run;
    if (retained && capacity === undefined) checked(moon.nativeHostStreamPrepare(run, retained.maxFrameBytes));
    const attempt = moon.nativeHostAttempt(run);
    let view;
    const owns = current => {
      if (view === undefined) view = current;
      if (current !== view) throw new DuckDBTransportError('ForeignReadView');
    };
    const port = Object.freeze({
      metadataSql: () => checked(moon.nativeHostSql(run, 0)),
      metadataParameters: () => [0, 1].map(index => JSON.parse(checked(moon.nativeHostParameter(run, index)))),
      acceptMetadata(chunk, current) {
        owns(current);
        checked(moon.nativeHostMetadata(run, rows(chunk.rowCount), fieldsFrame(chunk.fields), JSON.stringify(chunk.columns)));
      },
      async finishMetadata(_fields, current) {
        owns(current);
        if (retained) {
          signal?.throwIfAborted();
          const binding = retainedProcessStore(retained);
          store = binding
            ? createProcessStoreLease(binding, outputKey, retained.wire.max_bytes, retained.maxFrameBytes, signal)
            : await createLocalRetainedStore({ parentDirectory: retained.parentDirectory,
              capacityBytes: retained.wire.max_bytes, maxFrameBytes: retained.maxFrameBytes, maxEntries: 1 });
          signal?.throwIfAborted();
          writer = store.reserve(retained.wire.max_bytes);
          await writer.start();
          signal?.throwIfAborted();
        }
      },
      validationSql: () => checked(moon.nativeHostSql(run, 1)),
      nativeSql: () => checked(moon.nativeHostSql(run, 2)),
      nativeParameters: () => [JSON.parse(checked(moon.nativeHostParameter(run, 2)))],
      beginReceipt(role, fields, current) {
        owns(current);
        checked(moon.nativeHostBegin(run, role === 'native_result', fieldsFrame(fields)));
      },
      async acceptChunk(role, chunk, current) {
        owns(current);
        checked(moon.nativeHostAccept(run, rows(chunk.rowCount), JSON.stringify(chunk.columns)));
        if (retained && role === 'native_result') {
          let parts = [], bytes = 0;
          const flush = async () => {
            if (parts.length) await writer.append(parts.join(''));
            parts = []; bytes = 0;
            signal?.throwIfAborted();
          };
          for (;;) {
            signal?.throwIfAborted();
            const text = checked(moon.nativeHostStreamDrain(run));
            if (text == null) break;
            const size = Buffer.byteLength(text, 'utf8');
            if (size > retained.maxFrameBytes) throw new DuckDBTransportError('RetainedFrameLimit');
            if (size > retained.maxFrameBytes - bytes) await flush();
            if (size) { parts.push(text); bytes += size; }
          }
          await flush();
        }
      },
      async finishReceipt(role, current) {
        owns(current);
        checked(moon.nativeHostFinish(run));
        if (retained && role === 'native_result') {
          const finished = checked(moon.nativeHostStreamFinish(run));
          if (finished != null) {
            const { _0: token, _1: tail } = finished;
            await writer.append(tail);
            const { _0: cid, _1: bytes } = moon.nativeHostStreamIdentity(token);
            body = await writer.seal({ cid, bytes });
            signal?.throwIfAborted();
            retainedHandle = checked(moon.nativeHostStreamRetain(run, token, () => body.available()));
          }
        }
        return attempt;
      },
      abort() { moon.nativeHostAbort(run); },
    });
    return Object.freeze({
      attempt, port,
      complete: () => checked(moon.nativeHostComplete(run)),
      bindInput: observation => checked(moon.nativeHostOutput(run, observation)),
      abort() { moon.nativeHostAbort(run); },
      close() { moon.nativeHostClose(run); },
    });
  }, limits, signal, accounting).catch(error => {
    store?.close();
    if (capacity !== undefined && capturedRun !== undefined && !sessionStarted) {
      checked(moon.nativeHostPhysicalSettle(capturedRun, true));
    }
    // prepare() may fail before the settlement driver receives its bridge.
    // The exact run was already captured here and still owns issuer cleanup.
    if (capturedRun !== undefined) moon.nativeHostClose(capturedRun);
    if (store) {
      const prior = error?.cleanupHandle;
      const failure = error instanceof Error ? error : new DuckDBTransportError('RetainedAcquisitionFailed');
      failure.cleanupHandle = Object.freeze({
        status: () => ({ pending: retainedCleanup.status().pending || !!prior?.status().pending }),
        async retry() {
          const failures = [];
          for (const handle of [prior, retainedCleanup]) {
            try { await handle?.retry(); } catch (error) { failures.push(error); }
          }
          if (failures.length) throw new AggregateError(failures, 'Retained acquisition cleanup failed');
          return { pending: retainedCleanup.status().pending || !!prior?.status().pending };
        },
      });
      throw failure;
    }
    throw error;
  });
  if (retained) {
    registerRetainedInput(moon.nativeHostStreamMaterial(retainedHandle),
      input => moon.nativeHostStreamReadable(retainedHandle, input), body, retained);
  }
  let closed = false;
  const liveRun = () => {
    if (closed) throw new DuckDBTransportError('IssuerClosed');
    return capturedRun;
  };
  const output = () => {
    liveRun();
    if (!retained) return captured.bindInput();
    if (retainedOutput === undefined) {
      retainedOutput = captured.bindInput();
      // The shared material is already installed for both source() and output()
      // access. Do not register it twice when an output getter is used later.
      retainedComputations.set(retainedOutput, Object.freeze({
        readable: input => moon.nativeHostStreamReadable(retainedHandle, input),
        body, configuration: retained,
      }));
    }
    return retainedOutput;
  };
  return Object.freeze({
    observation: captured.observation,
    usage: captured.usage,
    diagnostics: captured.diagnostics,
    physicalCapacity: capacity === undefined ? undefined : Object.freeze({
      ...capacity, executionBytes: capacity.executionBytes + capacity.receiverScratchBytes,
    }),
    document: () => moon.nativeHostDocument(captured.observation),
    storageUsage: () => store?.status(),
    cleanupHandle: retained ? retainedCleanup : undefined,
    ...(capacity === undefined ? {
      output,
      source: () => checked(moon.nativeHostCapturedSource(liveRun(), captured.observation)),
    } : {
      openDAG: graph => checked(moon.nativeHostOpenDAG(liveRun(), graph, captured.observation)),
    }),
    close() {
      if (closed) return;
      closed = true;
      if (retainedOutput !== undefined) retainedComputations.delete(retainedOutput);
      body?.close();
      store?.close();
      captured.close();
    },
  });
}

// The broad result binds directly to an owned consumer through the existing
// captured-input API. No caller-supplied expected producer or success proof.
export async function runBroadHostQuery(grant, setup, limits, signal) {
  const moon = await loadRuntime();
  const captured = await runBroadQuery(grant, verify => {
    const run = checked(moon.broadHostOpen(setup, randomUUID(), verify));
    const attempt = moon.broadHostAttempt(run);
    let view;
    const owns = current => {
      if (view === undefined) view = current;
      if (view !== current) throw new DuckDBTransportError('ForeignReadView');
    };
    const port = Object.freeze({
      metadataSql: () => moon.broadHostSql(run, true),
      metadataParameters: () => [0, 1].map(index => JSON.parse(checked(moon.broadHostParameter(run, index)))),
      acceptMetadata(chunk, current) {
        owns(current);
        checked(moon.broadHostMetadata(run, rows(chunk.rowCount), fieldsFrame(chunk.fields), JSON.stringify(chunk.columns)));
      },
      finishMetadata(_fields, current) { owns(current); },
      scanSql: () => moon.broadHostSql(run, false),
      beginReceipt(fields, current) {
        owns(current);
        checked(moon.broadHostBegin(run, fieldsFrame(fields)));
      },
      acceptChunk(chunk, current) {
        owns(current);
        checked(moon.broadHostAccept(run, rows(chunk.rowCount), JSON.stringify(chunk.columns)));
      },
      finishReceipt(current) {
        owns(current);
        checked(moon.broadHostFinish(run));
        return attempt;
      },
      abort() { moon.broadHostAbort(run); },
    });
    return Object.freeze({
      attempt, port,
      complete: () => checked(moon.broadHostComplete(run)),
      bindInput: (observation, receiver, inputIndex) => checked(moon.broadHostBind(run, observation, receiver, rows(inputIndex))),
      abort() { moon.broadHostAbort(run); },
      close() { moon.broadHostClose(run); },
    });
  }, limits, signal);
  return Object.freeze({
    observation: captured.observation,
    document: () => moon.broadHostDocument(captured.observation),
    bindInput: (receiver, inputIndex) => captured.bindInput(receiver, inputIndex),
    close: () => captured.close(),
  });
}
