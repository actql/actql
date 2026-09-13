// Trusted Host port backed by MoonBit FixedCompute accessors. This does not
// accept Program SQL, discharge logical guards, or issue completed output.
import { DuckDBTransportError, withComputeDatabase } from './session.mjs';

export async function runFixedCompute(port, limits, importLimits, consume, signal) {
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
  }, signal);
}
