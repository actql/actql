// Trusted Host port backed by MoonBit FixedCompute accessors. This does not
// accept Program SQL, discharge logical guards, or issue completed output.
import { DuckDBTransportError, withComputeDatabase } from './session.mjs';

const attempted = new WeakSet();
const completed = new WeakMap();

// The trusted bridge creates a fresh port/receiver for each attempt. Its
// immutable completed input may be reused through another port and fresh budget.
export async function runFixedCompute(port, limits, importLimits, consume, signal, accounting) {
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
  const rows = port.rowCount();
  const columns = port.columnCount();
  for (const value of [rows, columns, importLimits.maxRows, importLimits.maxCells]) {
    if (!Number.isSafeInteger(value) || value < 0) throw new DuckDBTransportError('InvalidImportLimits');
  }
  if (rows > importLimits.maxRows) throw new DuckDBTransportError('ImportRows');
  if (columns === 0 || columns > limits.maxParameters || columns > limits.maxColumns) {
    throw new DuckDBTransportError('ImportColumns');
  }
  if (rows > Math.floor(importLimits.maxCells / columns)) throw new DuckDBTransportError('ImportCells');
  return withComputeDatabase(limits, async session => {
    retainSession(session);
    const discard = () => {};
    await session.command(port.createSql(), [], discard);
    const insert = port.insertSql();
    for (let row = 0; row < rows; row++) {
      if (signal?.aborted) throw new DuckDBTransportError('Cancelled');
      // Only the current parameter row is materialized. The MoonBit side retains
      // the immutable completed input; Node never receives a source connection.
      const parameters = [];
      for (let column = 0; column < columns; column++) parameters.push(port.parameter(row, column));
      await session.command(insert, parameters, discard);
    }
    const fields = await session.command(port.querySql(), port.queryParameters(), consume);
    return Object.freeze({ fields, importedRows: rows, importedCells: rows * columns });
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
// validate finishes Host guards/receiving before committing the resident result.
export async function runResidentFixedCompute(
  environment, port, resident, limits, consume, validate, signal, accounting,
) {
  if (attempted.has(port)) throw new DuckDBTransportError('AttemptAlreadyStarted');
  attempted.add(port);
  if (!environment.status().live) throw new DuckDBTransportError('SessionClosed');
  const result = await environment.run(limits, async session => {
    const discard = () => {};
    await session.command(resident.viewSql(), [], discard);
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
