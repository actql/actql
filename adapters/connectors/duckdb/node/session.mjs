// Host-private native transport. SQL must come from the trusted MoonBit adapter;
// this is not a Program SQL API, semantic verifier or completion issuer.
import { realpath, stat, lstat } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { DuckDBInstance, StatementType } from '@duckdb/node-api';
import { bindPhysicalValue, exportPhysicalValue, physicalJsonScalarBytes,
  physicalType } from './physical-values.mjs';
import {createPhysicalAppender} from './physical-appender.mjs';
import { DuckDBTransportError, validateLimits } from './configuration.mjs';
import {boundedTransport, maxNativeVectorRows} from './transport-bounds.mjs';
import {assertBoundedVectorRuntime, boundedVectorItem} from './bounded-vector.mjs';
import environmentContract from '../environment-contract.json' with {type: 'json'};
export { DuckDBTransportError, validateLimits } from './configuration.mjs';

const files = new WeakMap();


// Call only from explicit Host setup, never from Program/source wire decoding.
// The returned grant cannot be reconstructed by serializing its properties.
export async function authorizeLocalDatabase(path) {
  if (typeof path !== 'string' || !isAbsolute(path)) throw new DuckDBTransportError('InvalidSourcePath');
  const resolved = await realpath(path);
  if (!(await stat(resolved)).isFile()) throw new DuckDBTransportError('SourceNotFile');
  const grant = Object.freeze({});
  files.set(grant, resolved);
  return grant;
}

// A caller's cancellation deadline is not native settlement. Keep observing the
// original operation and retain its cleanup responsibility after returning early.
async function cancellationBoundary(start, limits, signal, accounting) {
  limits = validateLimits(limits);
  if (limits.cancelWaitMs === undefined || !signal) return start(limits);
  let settled = false;
  let terminalError;
  let timer;
  let resolveDeadline;
  const deadline = new Promise(resolve => { resolveDeadline = resolve; });
  const onAbort = () => {
    if (timer !== undefined || settled) return;
    timer = setTimeout(() => resolveDeadline({ expired: true }), limits.cancelWaitMs);
  };
  signal.addEventListener('abort', onAbort, { once: true });
  const operation = Promise.resolve().then(() => start(limits)).then(
    value => { settled = true; return { value }; },
    error => { settled = true; terminalError = error; return { failed: true, error }; },
  );
  if (signal.aborted) onAbort();
  let outcome = await Promise.race([operation, deadline]);
  signal.removeEventListener('abort', onAbort);
  clearTimeout(timer);
  if (outcome.expired && settled) outcome = await operation;
  if (!outcome.expired) {
    if (outcome.failed) throw outcome.error;
    return outcome.value;
  }
  const status = () => Object.freeze({
    pending: !settled || (terminalError?.cleanupHandle?.status().pending ?? false),
    errors: terminalError?.cleanupHandle?.status().errors ?? terminalError?.cleanupErrors ?? Object.freeze([]),
  });
  const failure = new DuckDBTransportError('Cancelled');
  failure.primaryFailure = new DuckDBTransportError('Cancelled');
  failure.cleanupErrors = Object.freeze([]);
  failure.cleanupPending = true;
  failure.cleanupHandle = Object.freeze({
    status,
    async retry() {
      await operation;
      if (terminalError?.cleanupHandle?.status().pending) await terminalError.cleanupHandle.retry();
      return status();
    },
  });
  accounting?.settled(false);
  throw failure;
}

async function usingSession(path, readonly, suppliedLimits, body, signal, accounting, shared, inputFiles = []) {
  const limits = validateLimits(suppliedLimits);
  const bounded = boundedTransport(limits);
  if (bounded) assertBoundedVectorRuntime();
  accounting?.started();
  let cancelled = signal?.aborted ?? false;
  let active = true;
  let busy = false;
  let pending = false;
  let instance;
  let connection;
  let transaction = false;
  let commandFailure;
  let commandFailed = false;
  // At most one prepared INSERT, owned by this exact session. It replaces, not
  // supplements, the ordinary per-command statement allocation.
  let cachedInsert;
  let activeAppender;
  let appenderFailure;
  let appenderFailed = false;
  const inFlight = new Set();
  const recordAppenderFailure = error => {
    if (!appenderFailed) appenderFailure = error;
    appenderFailed = true;
  };
  const recordCommandFailure = error => {
    if (!commandFailed) commandFailure = error;
    commandFailed = true;
  };
  const trackFlight = (promise, recordFailure) => {
    inFlight.add(promise);
    promise.then(
      () => inFlight.delete(promise),
      error => {
        recordFailure(error);
        inFlight.delete(promise);
      },
    );
    return promise;
  };
  const usage = { rows: 0, cells: 0, transportBytes: 0, statements: 0, preparations: 0, chunks: 0,
    appendedRows: 0,
    commandMilliseconds: 0, prepareMilliseconds: 0, receiveCallbackMilliseconds: 0, cleanupMilliseconds: 0 };
  const destroyCachedInsert = () => {
    cachedInsert?.prepared.destroySync();
    cachedInsert = undefined;
  };
  const assertLive = () => {
    if (cancelled) throw new DuckDBTransportError('Cancelled');
    if (!active) throw new DuckDBTransportError('SessionClosed');
  };
  const onAbort = () => {
    cancelled = true;
    // Do not interrupt a subsequent rollback/cleanup operation.
    if (pending) connection?.interrupt();
  };
  signal?.addEventListener('abort', onAbort, { once: true });
  const chargeBytes = (n) => {
    if (n > limits.maxTransportBytes - usage.transportBytes) throw new DuckDBTransportError('TransportBytes');
    accounting?.chargeTransfer(n);
    usage.transportBytes += n;
  };
  const startResidentAppender = async (table, columns) => {
    assertLive();
    if (busy || readonly || !shared || activeAppender ||
        typeof table !== 'string' || !/^resident_(0|[1-9][0-9]{0,9})$/.test(table) ||
        !Number.isSafeInteger(columns) || columns < 1 || columns > limits.maxColumns) {
      throw new DuckDBTransportError('InvalidResidentAppender');
    }
    busy = true;
    try {
      pending = true;
      activeAppender = await connection.createAppender(table, 'main');
      pending = false;
      assertLive();
      const physical = createPhysicalAppender(activeAppender, columns, {
        rows: Math.min(limits.maxChunkRows ?? 64, 64),
        bytes: Math.min(limits.maxChunkBytes ?? limits.maxTransportBytes, 1024 * 1024),
      });
      let live = true;
      const ensure = () => {
        assertLive();
        if (!live) throw new DuckDBTransportError('AppenderUnavailable');
      };
      return Object.freeze({
        append(parameters) {
          try {
            ensure();
            if (!Array.isArray(parameters) || parameters.length !== columns) {
              throw new DuckDBTransportError('ImportColumns');
            }
            pending = true;
            try {
              // Stage every typed value before charging or writing a native row.
              // The same bounded pass measures the physical transport charge.
              physical.append(parameters, bytes => {
                if (bytes > (limits.maxChunkBytes ?? limits.maxTransportBytes)) {
                  throw new DuckDBTransportError('ChunkBytes');
                }
                chargeBytes(bytes);
              });
            }
            finally { pending = false; }
            usage.appendedRows++;
          } catch (error) {
            live = false;
            recordAppenderFailure(error);
            throw error;
          }
        },
        flush() {
          try {
            ensure();
            pending = true;
            try {
              physical.flush();
              activeAppender.flushSync();
            }
            finally { pending = false; }
          } catch (error) {
            live = false;
            recordAppenderFailure(error);
            throw error;
          }
        },
        finish() {
          try {
            ensure();
            pending = true;
            try {
              physical.flush();
              activeAppender.closeSync();
              activeAppender = undefined;
              live = false;
              busy = false;
            } finally { pending = false; }
          } catch (error) {
            live = false;
            recordAppenderFailure(error);
            throw error;
          }
        },
      });
    } catch (error) {
      recordAppenderFailure(error);
      busy = false;
      pending = false;
      throw error;
    }
  };
  const openResidentAppender = (...args) =>
    trackFlight(startResidentAppender(...args), recordAppenderFailure);
  const runCommand = async (sql, parameters, consume, reuseInsert = false,
    statementMode = 'ordinary') => {
    assertLive();
    if (busy) throw new DuckDBTransportError('ConcurrentCommand');
    if (typeof sql !== 'string' || Buffer.byteLength(sql, 'utf8') > limits.maxSqlBytes) {
      throw new DuckDBTransportError('SqlBytes');
    }
    if (!Array.isArray(parameters) || parameters.length > limits.maxParameters) {
      throw new DuckDBTransportError('Parameters');
    }
    // Snapshot plain transport parameters before the first await. No Neo object
    // or caller-owned mutable array may change a bound command during execution.
    const bound = parameters.map(({ type, value }) => {
      if (bounded) {
        if (typeof value === 'string' && Buffer.byteLength(value, 'utf8') > limits.maxChunkBytes) {
          throw new DuckDBTransportError('ChunkBytes');
        }
        if ((value !== null && typeof value !== 'string' && typeof value !== 'boolean') ||
            !type || typeof type.id !== 'string' || type.id.length > 32 ||
            Object.keys(type).some(key => !['id', 'precision', 'scale'].includes(key)) ||
            ['precision', 'scale'].some(key => type[key] !== undefined && !Number.isSafeInteger(type[key]))) {
          throw new DuckDBTransportError('Parameters');
        }
      }
      return {type: {...type}, value};
    });
    let parameterBytes = Buffer.byteLength('{"parameters":[]}\n', 'utf8');
    if (bounded && parameterBytes > limits.maxChunkBytes) throw new DuckDBTransportError('ChunkBytes');
    chargeBytes(parameterBytes);
    for (let i = 0; i < bound.length; i++) {
      const bytes = Buffer.byteLength(JSON.stringify(bound[i]), 'utf8') + (i === 0 ? 0 : 1);
      if (bounded && bytes > limits.maxChunkBytes - parameterBytes) throw new DuckDBTransportError('ChunkBytes');
      chargeBytes(bytes);
      parameterBytes += bytes;
    }
    busy = true;
    const commandStarted = performance.now();
    let prepared;
    let succeeded = false;
    try {
      if (reuseInsert && cachedInsert?.sql === sql) {
        prepared = cachedInsert.prepared;
      } else {
        destroyCachedInsert();
        const prepareStarted = performance.now();
        try {
          pending = true;
          const extracted = await connection.extractStatements(sql);
          pending = false;
          assertLive();
          if (extracted.count !== 1) throw new DuckDBTransportError('StatementCount');
          pending = true;
          prepared = await extracted.prepare(0);
          usage.preparations++;
          pending = false;
          assertLive();
        } finally { usage.prepareMilliseconds += performance.now() - prepareStarted; }
      }
      if (reuseInsert && (readonly || prepared.statementType !== StatementType.INSERT)) {
        throw new DuckDBTransportError('StatementKind');
      }
      const allowed = statementMode === 'copy-parquet'
        ? [StatementType.COPY]
        : readonly ? [StatementType.SELECT]
        : [StatementType.SELECT, StatementType.CREATE, StatementType.INSERT,
          ...(shared ? [StatementType.DROP] : [])];
      if (!allowed.includes(prepared.statementType)) throw new DuckDBTransportError('StatementKind');
      if (prepared.parameterCount !== bound.length) throw new DuckDBTransportError('ParameterCount');
      for (let i = 0; i < bound.length; i++) bindPhysicalValue(prepared, i + 1, bound[i]);
      usage.statements++;
      pending = true;
      const result = await prepared.stream();
      pending = false;
      assertLive();
      if (result.columnCount > limits.maxColumns) throw new DuckDBTransportError('Columns');
      const fieldItems = [];
      let fieldBytes = Buffer.byteLength('{"fields":[]}\n', 'utf8');
      for (let i = 0; i < result.columnCount; i++) {
        const name = result.columnName(i);
        if (bounded && Buffer.byteLength(name, 'utf8') > limits.maxChunkBytes) throw new DuckDBTransportError('ChunkBytes');
        const field = Object.freeze({name, type: physicalType(result.columnType(i))});
        const bytes = Buffer.byteLength(JSON.stringify(field), 'utf8') + (i === 0 ? 0 : 1);
        if (bounded && bytes > limits.maxChunkBytes - fieldBytes) throw new DuckDBTransportError('ChunkBytes');
        fieldBytes += bytes;
        fieldItems.push(field);
      }
      const fields = Object.freeze(fieldItems);
      // Charge even an empty result's metadata; rows alone do not bound schema.
      const metadataBytes = Buffer.byteLength(JSON.stringify({ fields }) + '\n', 'utf8');
      if (bounded && metadataBytes > limits.maxChunkBytes) throw new DuckDBTransportError('ChunkBytes');
      chargeBytes(metadataBytes);
      for (;;) {
        pending = true;
        const chunk = await result.fetchChunk();
        pending = false;
        assertLive();
        if (!chunk || chunk.rowCount === 0) break;
        if (bounded && chunk.rowCount > maxNativeVectorRows) throw new DuckDBTransportError('NativeChunkRows');
        if (chunk.rowCount > limits.maxRows - usage.rows) throw new DuckDBTransportError('Rows');
        if (fields.length !== 0 && chunk.rowCount > Math.floor((limits.maxCells - usage.cells) / fields.length)) {
          throw new DuckDBTransportError('Cells');
        }
        usage.rows += chunk.rowCount;
        usage.cells += chunk.rowCount * fields.length;
        const rowsPerBatch = limits.maxChunkRows ?? chunk.rowCount;
        const frameLimit = limits.maxChunkBytes ?? limits.maxTransportBytes;
        for (let start = 0; start < chunk.rowCount;) {
          const maximumRows = Math.min(rowsPerBatch, chunk.rowCount - start);
          const columns = fields.map(() => []);
          const emptyFrameBytes = Buffer.byteLength(JSON.stringify({
            rowCount: 0, columns,
          }) + '\n', 'utf8');
          if (emptyFrameBytes > frameLimit) throw new DuckDBTransportError('ChunkBytes');
          // Variable-width SDK vectors cache decoded values. Use a fresh view
          // for each delivered batch, including a batch split by byte size.
          const vectors = fields.map((_, i) => chunk.getColumnVector(i).slice(start, maximumRows));
          let rowCount = 0;
          let batchBytes = emptyFrameBytes;
          const candidate = [];
          while (rowCount < maximumRows) {
            candidate.length = 0;
            let nextBytes = batchBytes + String(rowCount + 1).length - String(rowCount).length;
            for (let i = 0; i < fields.length; i++) {
              const item = bounded
                ? boundedVectorItem(vectors[i], rowCount, fields[i].type, frameLimit)
                : vectors[i].getItem(rowCount);
              const cell = exportPhysicalValue(item, fields[i].type);
              nextBytes += physicalJsonScalarBytes(cell) + (rowCount === 0 ? 0 : 1);
              if (nextBytes > frameLimit) break;
              candidate.push(cell);
            }
            if (candidate.length !== fields.length) {
              if (rowCount === 0) throw new DuckDBTransportError('ChunkBytes');
              break;
            }
            for (let i = 0; i < fields.length; i++) columns[i].push(candidate[i]);
            batchBytes = nextBytes;
            rowCount++;
          }
          chargeBytes(batchBytes);
          usage.chunks++;
          const receiveStarted = performance.now();
          try {
            await consume(Object.freeze({ fields, rowCount,
              columns: Object.freeze(columns.map(column => Object.freeze(column))) }));
          } finally { usage.receiveCallbackMilliseconds += performance.now() - receiveStarted; }
          assertLive();
          start += rowCount;
        }
      }
      succeeded = true;
      return fields;
    } finally {
      pending = false;
      try {
        if (prepared && reuseInsert) {
          // Keep ownership until explicit destruction succeeds, including on a
          // failed command. Cleanup must not forget a native statement.
          cachedInsert = {sql, prepared};
          if (succeeded) prepared.clearBindings();
          else destroyCachedInsert();
        } else prepared?.destroySync();
      } finally {
        usage.commandMilliseconds += performance.now() - commandStarted;
        busy = false;
      }
    }
  };
  const command = (...args) => {
    const promise = runCommand(...args);
    // Observe failures even if trusted orchestration accidentally catches or
    // forgets to await a command. Such an attempt must never return success.
    return trackFlight(promise, recordCommandFailure);
  };
  const createFileView = (sql, inputPath, consume) => {
    if (typeof sql !== 'string' || typeof inputPath !== 'string' ||
        typeof consume !== 'function' || !inputFiles.includes(inputPath) ||
        !sql.startsWith('CREATE TEMP VIEW ') ||
        sql.indexOf('?') < 0 || sql.indexOf('?') !== sql.lastIndexOf('?')) {
      throw new DuckDBTransportError('InvalidFileView');
    }
    // DuckDB does not allow prepared parameters in CREATE VIEW. Only this
    // installed Host operation may substitute one exact session-authorized
    // path into an adapter-compiled template. General external access remains
    // disabled and the resulting complete SQL is checked by runCommand.
    const quoted = `'${inputPath.replaceAll("'", "''")}'`;
    const pathBytes = Buffer.byteLength(JSON.stringify({
      type: {id: 'VARCHAR'}, value: inputPath,
    }), 'utf8');
    chargeBytes(pathBytes);
    return command(sql.replace('?', quoted), [], consume);
  };
  const runCopyParquet = async (selectSql, parameters, outputPath) => {
    if (typeof selectSql !== 'string' || !inputFiles.includes(outputPath)) {
      throw new DuckDBTransportError('UnauthorizedOutputPath');
    }
    const quoted = `'${outputPath.replaceAll("'", "''")}'`;
    await command(`COPY (${selectSql}) TO ${quoted} (FORMAT PARQUET)`,
      parameters, () => {}, false, 'copy-parquet');
    assertLive();
    const state = await lstat(outputPath);
    if (!state.isFile() || !Number.isSafeInteger(state.dev) ||
        !Number.isSafeInteger(state.ino) || !Number.isSafeInteger(state.size) ||
        state.size < 0) throw new DuckDBTransportError('InvalidNativeOutput');
    return Object.freeze({device: state.dev, inode: state.ino,
      bytes: state.size});
  };
  const copyParquet = (...args) =>
    trackFlight(runCopyParquet(...args), recordCommandFailure);
  let result;
  let failure;
  let failed = false;
  const cleanupErrors = [];
  let cleaning = false;
  const cleanupStatus = () => Object.freeze({
    pending: activeAppender !== undefined || cachedInsert !== undefined ||
      connection !== undefined || instance !== undefined,
    errors: Object.freeze([...cleanupErrors]),
  });
  const cleanOwnedResources = async () => {
    if (cleaning) throw new DuckDBTransportError('CleanupInProgress');
    cleaning = true;
    const cleanupStarted = performance.now();
    try {
      try { activeAppender?.closeSync(); activeAppender = undefined; }
      catch (error) { cleanupErrors.push(error); }
      try { destroyCachedInsert(); }
      catch (error) { cleanupErrors.push(error); }
      try {
        if (transaction && connection) await connection.run('ROLLBACK');
        transaction = false;
      } catch (error) { cleanupErrors.push(error); }
      try {
        if (!activeAppender && !cachedInsert) {
          connection?.closeSync();
          connection = undefined;
          transaction = false; // closing the owned connection ends its transaction
        }
      } catch (error) { cleanupErrors.push(error); }
      // Retain the instance while its connection still needs cleanup.
      if (!connection && !shared) {
        try { instance?.closeSync(); instance = undefined; }
        catch (error) { cleanupErrors.push(error); }
      }
      // This task borrows the DB. Its transaction/connection has settled, but
      // the environment owner continues reserving the shared instance capacity.
      if (!connection && shared) instance = undefined;
      const status = cleanupStatus();
      accounting?.settled(!status.pending);
      return status;
    } finally {
      usage.cleanupMilliseconds += performance.now() - cleanupStarted;
      cleaning = false;
    }
  };
  try {
    assertLive();
    instance = shared?.instance ?? await createInstance(path, readonly, limits, inputFiles);
    assertLive();
    connection = await instance.connect();
    assertLive();
    if (inputFiles.length) {
      // List settings are not accepted by the pinned C configuration setter.
      // Configure before exposing the private connection to any task SQL, then
      // irreversibly disable general external access for this instance.
      await connection.run(`SET allowed_paths = [${inputFiles.map(path => `'${path.replaceAll("'", "''")}'`).join(',')}]`);
      assertLive();
      await connection.run('SET enable_external_access = false');
      assertLive();
    }
    await connection.run('BEGIN TRANSACTION');
    transaction = true;
    assertLive();
    // Callback is trusted Host code. Its chunks are provisional, not a public
    // success channel. Only this function's resolution denotes clean completion.
    result = await body(Object.freeze({
      command,
      insert: (sql, parameters, consume) => command(sql, parameters, consume, true),
      openResidentAppender,
      createFileView,
      // Installed Host operation only. The output path must be one of the exact
      // paths admitted when this private session was created; callers cannot
      // choose a format, option, glob or arbitrary destination.
      copyParquet,
      usage: () => Object.freeze({ ...usage }),
    }));
    assertLive();
    if (inFlight.size !== 0) throw new DuckDBTransportError('UnawaitedCommand');
    if (commandFailed) throw commandFailure;
    if (appenderFailed) throw appenderFailure;
    if (activeAppender) throw new DuckDBTransportError('UnclosedAppender');
    if (shared) {
      // The trusted body must finish provisional-output validation before
      // returning. Only successful transactions may publish resident tables.
      await connection.run('COMMIT');
      transaction = false;
      assertLive();
    }
  } catch (error) {
    failed = true;
    failure = cancelled ? new DuckDBTransportError('Cancelled', { cause: error }) : error;
  } finally {
    active = false;
    signal?.removeEventListener('abort', onAbort);
    if (pending) connection?.interrupt();
    // Await actual native settlement before rollback/disconnect. No racing
    // cleanup or success while an ignored command is still accessing the DB.
    await Promise.allSettled([...inFlight]);
    // Source is read-only and Compute ephemeral. Roll back owned temporary
    // resources in both cases. No pool or source handle survives this attempt.
    await cleanOwnedResources();
  }
  if (cleanupErrors.length) {
    const combined = new DuckDBTransportError(failure?.code ?? 'CleanupFailed', {
      cause: failed ? failure : cleanupErrors[0],
    });
    combined.primaryFailure = failure;
    combined.cleanupErrors = Object.freeze([...cleanupErrors]);
    combined.cleanupPending = cleanupStatus().pending;
    if (combined.cleanupPending) combined.cleanupHandle = Object.freeze({
      status: cleanupStatus, retry: cleanOwnedResources,
    });
    throw combined;
  }
  if (signal?.aborted && !failed) {
    failed = true;
    failure = new DuckDBTransportError('Cancelled');
  }
  if (failed) throw failure;
  return Object.freeze({ value: result, usage: Object.freeze({ ...usage }) });
}

function createInstance(path, readonly, limits, inputFiles = []) {
  return DuckDBInstance.create(path, {
    ...environmentContract.settings,
    access_mode: readonly ? 'READ_ONLY' : 'READ_WRITE',
    threads: String(limits.threads), memory_limit: `${limits.memoryBytes}B`,
    enable_external_access: inputFiles.length ? 'true' : 'false',
  });
}

// Trusted resource-provider operation, not candidate enumeration. The caller
// must reserve the DB capacity before calling. Each task has its own connection,
// transaction, cancellation scope, transfer budget and scratch accounting.
// No source grant or arbitrary existing instance can be attached here.
export async function provisionComputeDatabase(suppliedLimits, accounting) {
  const limits = validateLimits(suppliedLimits);
  accounting.started();
  let instance;
  try {
    instance = await createInstance(':memory:', false, limits);
  } catch (error) {
    accounting.settled(true);
    throw error;
  }
  let closing = false;
  let busy = false;
  let pendingCleanup;
  const status = () => Object.freeze({
    live: instance !== undefined && !closing,
    pending: instance !== undefined,
    busy,
  });
  const close = async () => {
    closing = true;
    if (busy) {
      accounting.settled(false);
      throw new DuckDBTransportError('CleanupInProgress');
    }
    try {
      if (pendingCleanup) {
        const state = await pendingCleanup.retry();
        if (state.pending) {
          accounting.settled(false);
          return status();
        }
        pendingCleanup = undefined;
      }
      instance?.closeSync();
      instance = undefined;
      accounting.settled(true);
      return status();
    } catch (error) {
      accounting.settled(false);
      throw error;
    }
  };
  return Object.freeze({
    status,
    close,
    memoryBytes: limits.memoryBytes,
    threads: limits.threads,
    async run(taskLimits, body, signal, taskAccounting) {
      taskLimits = validateLimits(taskLimits);
      if (!instance || closing || pendingCleanup) throw new DuckDBTransportError('SessionClosed');
      if (busy) throw new DuckDBTransportError('ConcurrentCommand');
      if (taskLimits.memoryBytes !== limits.memoryBytes || taskLimits.threads !== limits.threads) {
        throw new DuckDBTransportError('EnvironmentMismatch');
      }
      busy = true;
      // busy tracks actual native settlement, not the cancellation deadline.
      return cancellationBoundary(async fixedLimits => {
        try {
          return await usingSession(':memory:', false, fixedLimits, body, signal,
            taskAccounting, { instance });
        } catch (error) {
          if (error?.cleanupPending) {
            pendingCleanup = error.cleanupHandle;
            closing = true;
          }
          throw error;
        } finally {
          busy = false;
        }
      }, taskLimits, signal, taskAccounting);
    },
  });
}

export async function withSourceDatabase(grant, limits, body, signal, accounting) {
  const path = files.get(grant);
  if (!path) throw new DuckDBTransportError('UnauthorizedSource');
  return cancellationBoundary(fixedLimits => usingSession(path, true, fixedLimits, body, signal, accounting), limits, signal, accounting);
}

export async function withComputeDatabase(limits, body, signal, accounting, suppliedFiles = []) {
  // Trusted transport wiring, never a Program path. Freeze before any await;
  // admit exact files only, not directories, globs, URLs or external access.
  if (!Array.isArray(suppliedFiles) || suppliedFiles.length > 2 || suppliedFiles.some(path =>
    typeof path !== 'string' || !isAbsolute(path) || /[\u0000*?\[\]]/.test(path) ||
    Buffer.byteLength(path, 'utf8') > limits.maxSqlBytes)) throw new DuckDBTransportError('InvalidInputFileGrant');
  const inputFiles = Object.freeze([...new Set(suppliedFiles)]);
  return cancellationBoundary(fixedLimits => usingSession(':memory:', false, fixedLimits, body, signal, accounting,
    undefined, inputFiles), limits, signal, accounting);
}
