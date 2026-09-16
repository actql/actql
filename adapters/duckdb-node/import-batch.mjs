// Connector-private transport batching, not value admission or completion.
import {DuckDBTransportError} from './configuration.mjs';

const emptyFrameBytes = Buffer.byteLength('{"parameters":[]}\n', 'utf8');

export function createImportBatch(columns, rows, limits, sqlForRows, write, signal) {
  if (!Number.isSafeInteger(columns) || columns < 1 ||
      !Number.isSafeInteger(rows) || rows < 1 || rows > limits.maxChunkRows ||
      rows > Math.floor(limits.maxParameters / columns)) throw new DuckDBTransportError('InvalidImportBatch');
  let parameters = [], count = 0, bytes = emptyFrameBytes, live = true;
  const flush = async () => {
    signal?.throwIfAborted();
    if (!count) return;
    // The trusted MoonBit compiler owns identifiers and tuple construction.
    const compiled = sqlForRows(count);
    if (compiled.rows !== count || typeof compiled.sql !== 'string' ||
        Buffer.byteLength(compiled.sql, 'utf8') > limits.maxSqlBytes) {
      throw new DuckDBTransportError('InvalidImportBatch');
    }
    await write(compiled.sql, parameters);
    parameters = []; count = 0; bytes = emptyFrameBytes;
    signal?.throwIfAborted();
  };
  return Object.freeze({
    async append(row) {
      if (!live) throw new DuckDBTransportError('ImportBatchUnavailable');
      try {
        signal?.throwIfAborted();
        if (!Array.isArray(row) || row.length !== columns) throw new DuckDBTransportError('InvalidImportStream');
        const copied = [];
        let rowBytes = 0;
        for (const parameter of row) {
          const {type, value} = parameter ?? {};
          if ((value !== null && typeof value !== 'string' && typeof value !== 'boolean') ||
              !type || typeof type.id !== 'string' || type.id.length > 32 ||
              Object.keys(type).some(key => !['id', 'precision', 'scale'].includes(key)) ||
              ['precision', 'scale'].some(key => type[key] !== undefined && !Number.isSafeInteger(type[key]))) {
            throw new DuckDBTransportError('Parameters');
          }
          if (typeof value === 'string' && Buffer.byteLength(value, 'utf8') > limits.maxChunkBytes) {
            throw new DuckDBTransportError('ChunkBytes');
          }
          const item = {type: {...type}, value};
          const size = Buffer.byteLength(JSON.stringify(item), 'utf8') + (copied.length ? 1 : 0);
          if (size > limits.maxChunkBytes - emptyFrameBytes - rowBytes) {
            throw new DuckDBTransportError('ChunkBytes');
          }
          rowBytes += size;
          copied.push(item);
        }
        // A variable-width row may end the batch early. It is snapshotted before
        // awaiting native I/O, with both the pending batch and this row bounded.
        if (count && rowBytes + 1 > limits.maxChunkBytes - bytes) await flush();
        bytes += rowBytes + (count ? 1 : 0);
        parameters.push(...copied);
        count++;
        if (count === rows) await flush();
      } catch (error) {
        live = false; parameters = [];
        throw error;
      }
    },
    async finish() {
      if (!live) throw new DuckDBTransportError('ImportBatchUnavailable');
      live = false;
      try { await flush(); }
      finally { parameters = []; }
    },
  });
}
