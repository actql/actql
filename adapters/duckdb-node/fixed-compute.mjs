// Trusted Host port backed by MoonBit FixedCompute accessors. This does not
// accept Program SQL, discharge logical guards, or issue completed output.
import { DuckDBTransportError, withComputeDatabase, validateLimits } from './session.mjs';
import {boundedTransport} from './transport-bounds.mjs';
import {createImportBatch} from './import-batch.mjs';

const attempted = new WeakSet();
const completed = new WeakMap();

// The trusted bridge creates a fresh port/receiver for each attempt. Its
// immutable completed input may be reused through another port and fresh budget.
export async function runFixedCompute(port, limits, importLimits, consume, signal, accounting) {
  limits = validateLimits(limits);
  importLimits = Object.freeze({...importLimits});
  if (attempted.has(port)) throw new DuckDBTransportError('AttemptAlreadyStarted');
  attempted.add(port);
  let ownedSession;
  const result = await executeFixedCompute(port, limits, importLimits, consume, signal,
    session => { ownedSession = session; }, accounting);
  // Register only after all native commands, transaction settlement and cleanup.
  // This anchors the actual closed session; it grants no source-read capability.
  completed.set(result, { port, consume, session: ownedSession });
  return result;
}

async function executeFixedCompute(port, limits, importLimits, consume, signal, retainSession, accounting) {
  const count = port.importCount();
  for (const value of [count, importLimits.maxRows, importLimits.maxCells]) {
    if (!Number.isSafeInteger(value) || value < 0) throw new DuckDBTransportError('InvalidImportLimits');
  }
  // Validate every port before creating a DB. Row limits are per input;
  // imported cells accumulate even when two ports have identical contents.
  if (count < 1 || count > 2) throw new DuckDBTransportError('ImportCount');
  const imports = [];
  let importedRows = 0;
  let importedCells = 0;
  for (let input = 0; input < count; input++) {
    const rows = port.rowCount(input);
    const columns = port.columnCount(input);
    if (!Number.isSafeInteger(rows) || rows < 0 || !Number.isSafeInteger(columns) || columns < 0) {
      throw new DuckDBTransportError('InvalidImportLimits');
    }
    if (rows > importLimits.maxRows) throw new DuckDBTransportError('ImportRows');
    if (columns === 0 || columns > limits.maxParameters || columns > limits.maxColumns) {
      throw new DuckDBTransportError('ImportColumns');
    }
    if (rows > Math.floor((importLimits.maxCells - importedCells) / columns)) {
      throw new DuckDBTransportError('ImportCells');
    }
    if (rows > Number.MAX_SAFE_INTEGER - importedRows) throw new DuckDBTransportError('ImportRows');
    importedRows += rows;
    importedCells += rows * columns;
    // Batch sizing is pure and precedes DB creation. Old trusted test ports can
    // keep the single-row path; installed ports use the exact MoonBit compiler.
    let batchRows = 1;
    if (boundedTransport(limits) && typeof port.insertBatch === 'function' && rows > 1) {
      const requested = Math.min(rows, limits.maxChunkRows, Math.floor(limits.maxParameters / columns));
      const batch = port.insertBatch(input, requested);
      if (!Number.isSafeInteger(batch.rows) || batch.rows < 1 || batch.rows > requested ||
          typeof batch.sql !== 'string' || Buffer.byteLength(batch.sql, 'utf8') > limits.maxSqlBytes) {
        throw new DuckDBTransportError('InvalidImportBatch');
      }
      batchRows = batch.rows;
    }
    imports.push({ rows, columns, batchRows });
  }
  return withComputeDatabase(limits, async session => {
    retainSession(session);
    const discard = () => {};
    const inputTimings = [];
    for (let input = 0; input < imports.length; input++) {
      const inputStarted = performance.now();
      let insertMilliseconds = 0;
      const { rows, columns, batchRows } = imports[input];
      await session.command(port.createSql(input), [], discard);
      const insert = port.insertSql(input);
      const write = async (sql, parameters) => {
        const started = performance.now();
        try { await session.insert(sql, parameters, discard); }
        finally { insertMilliseconds += performance.now() - started; }
      };
      const batch = batchRows > 1 ? createImportBatch(columns, batchRows, limits,
        count => port.insertBatch(input, count), write, signal) : undefined;
      const importRow = parameters => batch ? batch.append(parameters) : write(insert, parameters);
      let accepted = 0;
      const streamed = await port.consumeInput?.(input, async parameters => {
        signal?.throwIfAborted();
        if (accepted >= rows || !Array.isArray(parameters) || parameters.length !== columns) {
          throw new DuckDBTransportError('InvalidImportStream');
        }
        await importRow(parameters);
        accepted++;
      });
      signal?.throwIfAborted();
      if (streamed) {
        if (accepted !== rows) throw new DuckDBTransportError('InvalidImportStream');
        await batch?.finish();
        inputTimings.push(Object.freeze({input, rows, milliseconds: performance.now() - inputStarted,
          insertMilliseconds, batchRows}));
        continue;
      }
      if (accepted !== 0) throw new DuckDBTransportError('InvalidImportStream');
      for (let row = 0; row < rows; row++) {
        if (signal?.aborted) throw new DuckDBTransportError('Cancelled');
        // Only the current parameter row is materialized. No source connection
        // crosses this fixed-input boundary.
        const parameters = [];
        for (let column = 0; column < columns; column++) parameters.push(port.parameter(input, row, column));
        await importRow(parameters);
      }
      await batch?.finish();
      inputTimings.push(Object.freeze({input, rows, milliseconds: performance.now() - inputStarted,
        insertMilliseconds, batchRows}));
    }
    const outputStarted = performance.now();
    const fields = await session.command(port.querySql(), port.queryParameters(), consume);
    return Object.freeze({ fields, importedRows, importedCells,
      diagnostics: Object.freeze({inputs: Object.freeze(inputTimings),
        queryAndReceiveMilliseconds: performance.now() - outputStarted}) });
  }, signal, accounting);
}

// Transport provenance only. The MoonBit completion issuer must independently
// check the exact fixed input, semantics, guards, output and retained evidence.
export function matchesFixedCompute(result, port, consume) {
  const owned = completed.get(result);
  return owned !== undefined && owned.port === port && owned.consume === consume
    && owned.session !== undefined;
}

export function releaseFixedCompute(result) {
  completed.delete(result);
}

// Trusted resident bridge only. Every SQL fragment and the checked receiver
// mapping come from the MoonBit adapter, not application callbacks. The
// environment is borrowed: task settlement does not close the shared DB.
// validate finishes receiving before committing the resident table. The common
// MoonBit completion boundary still validates demand, guards and retention before
// publishing success; a later failure leaves only owned cleanup responsibility.
export async function runResidentFixedCompute(
  environment, port, resident, limits, consume, validate, signal, accounting,
) {
  if (attempted.has(port)) throw new DuckDBTransportError('AttemptAlreadyStarted');
  attempted.add(port);
  if (!environment.status().live) throw new DuckDBTransportError('SessionClosed');
  const result = await environment.run(limits, async session => {
    const discard = () => {};
    // Reusing an exact DB copy skips import, not this consumer's measurement
    // or demand checks. Retained inputs use the same bounded common decoder.
    if (port.consumeInput) {
      for (let input = 0; input < port.importCount(); input++) {
        signal?.throwIfAborted();
        await port.consumeInput(input, discard);
      }
    }
    for (const sql of resident.viewSqls()) await session.command(sql, [], discard);
    await session.command(resident.createResultSql(), port.queryParameters(), discard);
    const fields = await session.command(resident.readResultSql(), [], consume);
    // Includes empty-result metadata. Throwing here rolls back this task only.
    await validate(fields);
    for (const sql of resident.cleanupSqls?.() ?? []) {
      await session.command(sql, [], discard);
    }
    return Object.freeze({ fields, importedRows: 0, importedCells: 0 });
  }, signal, accounting);
  // Preserve completed Host-output provenance independently of future DB loss.
  // Reusing the DB table still requires its separate live table-generation proof.
  completed.set(result, { port, consume, session: environment });
  return result;
}
