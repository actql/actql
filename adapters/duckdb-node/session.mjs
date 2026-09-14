// Host-private native transport. SQL must come from the trusted MoonBit adapter;
// this is not a Program SQL API, semantic verifier or completion issuer.
import { realpath, stat } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { DuckDBInstance, StatementType } from '@duckdb/node-api';
import { bindPhysicalValue, exportPhysicalValue, physicalType } from './physical-values.mjs';

const files = new WeakMap();

export class DuckDBTransportError extends Error {
  constructor(code, options) { super(code, options); this.name = 'DuckDBTransportError'; this.code = code; }
}

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

function validateLimits(limits) {
  if (limits.cancelWaitMs !== undefined &&
      (!Number.isSafeInteger(limits.cancelWaitMs) || limits.cancelWaitMs < 0 || limits.cancelWaitMs > 2147483647)) {
    throw new DuckDBTransportError('InvalidLimits');
  }
  for (const name of ['maxRows', 'maxCells', 'maxTransportBytes', 'maxSqlBytes', 'maxParameters', 'maxColumns', 'memoryBytes', 'threads']) {
    if (!Number.isSafeInteger(limits[name]) || limits[name] < (['memoryBytes', 'threads'].includes(name) ? 1 : 0)) {
      throw new DuckDBTransportError('InvalidLimits');
    }
  }
  return Object.freeze({ ...limits });
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
    error => { settled = true; terminalError = error; return { error }; },
  );
  if (signal.aborted) onAbort();
  let outcome = await Promise.race([operation, deadline]);
  signal.removeEventListener('abort', onAbort);
  clearTimeout(timer);
  if (outcome.expired && settled) outcome = await operation;
  if (!outcome.expired) {
    if (outcome.error) throw outcome.error;
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

async function usingSession(path, readonly, suppliedLimits, body, signal, accounting) {
  const limits = validateLimits(suppliedLimits);
  accounting?.started();
  let cancelled = signal?.aborted ?? false;
  let active = true;
  let busy = false;
  let pending = false;
  let instance;
  let connection;
  let transaction = false;
  let commandFailure;
  const inFlight = new Set();
  const usage = { rows: 0, cells: 0, transportBytes: 0, statements: 0, chunks: 0 };
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
  const runCommand = async (sql, parameters, consume) => {
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
    const bound = parameters.map(({ type, value }) => ({ type: { ...type }, value }));
    chargeBytes(Buffer.byteLength('{"parameters":[]}\n', 'utf8'));
    for (let i = 0; i < bound.length; i++) {
      chargeBytes(Buffer.byteLength(JSON.stringify(bound[i]), 'utf8') + (i === 0 ? 0 : 1));
    }
    busy = true;
    let prepared;
    try {
      pending = true;
      const extracted = await connection.extractStatements(sql);
      pending = false;
      assertLive();
      if (extracted.count !== 1) throw new DuckDBTransportError('StatementCount');
      pending = true;
      prepared = await extracted.prepare(0);
      pending = false;
      assertLive();
      const allowed = readonly ? [StatementType.SELECT]
        : [StatementType.SELECT, StatementType.CREATE, StatementType.INSERT];
      if (!allowed.includes(prepared.statementType)) throw new DuckDBTransportError('StatementKind');
      if (prepared.parameterCount !== bound.length) throw new DuckDBTransportError('ParameterCount');
      for (let i = 0; i < bound.length; i++) bindPhysicalValue(prepared, i + 1, bound[i]);
      usage.statements++;
      pending = true;
      const result = await prepared.stream();
      pending = false;
      assertLive();
      if (result.columnCount > limits.maxColumns) throw new DuckDBTransportError('Columns');
      const fields = Object.freeze(Array.from({ length: result.columnCount }, (_, i) =>
        Object.freeze({ name: result.columnName(i), type: physicalType(result.columnType(i)) })));
      // Charge even an empty result's metadata; rows alone do not bound schema.
      chargeBytes(Buffer.byteLength(JSON.stringify({ fields }) + '\n', 'utf8'));
      for (;;) {
        pending = true;
        const chunk = await result.fetchChunk();
        pending = false;
        assertLive();
        if (!chunk || chunk.rowCount === 0) break;
        if (chunk.rowCount > limits.maxRows - usage.rows) throw new DuckDBTransportError('Rows');
        if (fields.length !== 0 && chunk.rowCount > Math.floor((limits.maxCells - usage.cells) / fields.length)) {
          throw new DuckDBTransportError('Cells');
        }
        usage.rows += chunk.rowCount;
        usage.cells += chunk.rowCount * fields.length;
        chargeBytes(Buffer.byteLength(JSON.stringify({
          rowCount: chunk.rowCount, columns: fields.map(() => []),
        }) + '\n', 'utf8'));
        const columns = [];
        for (let i = 0; i < fields.length; i++) {
          const values = [];
          chunk.visitColumnValues(i, (value) => {
            const cell = exportPhysicalValue(value, fields[i].type);
            // This is the explicit transport encoding cost, not canonical value
            // bytes, DuckDB allocator capacity or whole-process RSS.
            chargeBytes(Buffer.byteLength(JSON.stringify(cell), 'utf8') + (values.length === 0 ? 0 : 1));
            values.push(cell);
          });
          columns.push(Object.freeze(values));
        }
        usage.chunks++;
        await consume(Object.freeze({ fields, rowCount: chunk.rowCount, columns: Object.freeze(columns) }));
        assertLive();
      }
      return fields;
    } finally {
      pending = false;
      prepared?.destroySync();
      busy = false;
    }
  };
  const command = (...args) => {
    const promise = runCommand(...args);
    inFlight.add(promise);
    // Observe failures even if trusted orchestration accidentally catches or
    // forgets to await a command. Such an attempt must never return success.
    promise.then(
      () => inFlight.delete(promise),
      (error) => { commandFailure ??= error; inFlight.delete(promise); },
    );
    return promise;
  };
  let result;
  let failure;
  const cleanupErrors = [];
  let cleaning = false;
  const cleanupStatus = () => Object.freeze({
    pending: connection !== undefined || instance !== undefined,
    errors: Object.freeze([...cleanupErrors]),
  });
  const cleanOwnedResources = async () => {
    if (cleaning) throw new DuckDBTransportError('CleanupInProgress');
    cleaning = true;
    try {
      try {
        if (transaction && connection) await connection.run('ROLLBACK');
        transaction = false;
      } catch (error) { cleanupErrors.push(error); }
      try {
        connection?.closeSync();
        connection = undefined;
        transaction = false; // closing the owned connection ends its transaction
      } catch (error) { cleanupErrors.push(error); }
      // Retain the instance while its connection still needs cleanup.
      if (!connection) {
        try { instance?.closeSync(); instance = undefined; }
        catch (error) { cleanupErrors.push(error); }
      }
      const status = cleanupStatus();
      accounting?.settled(!status.pending);
      return status;
    } finally { cleaning = false; }
  };
  try {
    assertLive();
    instance = await DuckDBInstance.create(path, {
      access_mode: readonly ? 'READ_ONLY' : 'READ_WRITE',
      threads: String(limits.threads), memory_limit: `${limits.memoryBytes}B`,
      max_temp_directory_size: '0B', preserve_insertion_order: 'true',
      enable_external_access: 'false', autoinstall_known_extensions: 'false',
      autoload_known_extensions: 'false', allow_unsigned_extensions: 'false',
    });
    assertLive();
    connection = await instance.connect();
    assertLive();
    await connection.run('BEGIN TRANSACTION');
    transaction = true;
    assertLive();
    // Callback is trusted Host code. Its chunks are provisional, not a public
    // success channel. Only this function's resolution denotes clean completion.
    result = await body(Object.freeze({
      command,
      usage: () => Object.freeze({ ...usage }),
    }));
    assertLive();
    if (inFlight.size !== 0) throw new DuckDBTransportError('UnawaitedCommand');
    if (commandFailure) throw commandFailure;
  } catch (error) {
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
    const combined = new DuckDBTransportError(failure?.code ?? 'CleanupFailed', { cause: failure ?? cleanupErrors[0] });
    combined.primaryFailure = failure;
    combined.cleanupErrors = Object.freeze([...cleanupErrors]);
    combined.cleanupPending = cleanupStatus().pending;
    if (combined.cleanupPending) combined.cleanupHandle = Object.freeze({
      status: cleanupStatus, retry: cleanOwnedResources,
    });
    throw combined;
  }
  if (signal?.aborted && !failure) failure = new DuckDBTransportError('Cancelled');
  if (failure) throw failure;
  return Object.freeze({ value: result, usage: Object.freeze({ ...usage }) });
}

export async function withSourceDatabase(grant, limits, body, signal, accounting) {
  const path = files.get(grant);
  if (!path) throw new DuckDBTransportError('UnauthorizedSource');
  return cancellationBoundary(fixedLimits => usingSession(path, true, fixedLimits, body, signal, accounting), limits, signal, accounting);
}

export async function withComputeDatabase(limits, body, signal, accounting) {
  return cancellationBoundary(fixedLimits => usingSession(':memory:', false, fixedLimits, body, signal, accounting), limits, signal, accounting);
}
