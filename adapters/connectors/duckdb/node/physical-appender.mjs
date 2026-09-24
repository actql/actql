// Connector-private physical transport. This does not grant completion, own
// resource cleanup or replace MoonBit value/guard admission.
import {bindPhysicalValue, physicalType, PhysicalValueError} from './physical-values.mjs';
import {DuckDBDataChunk} from '@duckdb/node-api';

const suffixes = ['Null', 'Boolean', 'Varchar', 'Float', 'Double', 'Date', 'Decimal',
  'TinyInt', 'SmallInt', 'Integer', 'BigInt', 'HugeInt',
  'UTinyInt', 'USmallInt', 'UInteger', 'UBigInt', 'UHugeInt',
  'Timestamp', 'TimestampTZ', 'TimestampSeconds', 'TimestampMilliseconds', 'TimestampNanoseconds'];

export function createPhysicalAppender(appender, maxColumns, batch) {
  if (!Number.isSafeInteger(maxColumns) || maxColumns < 1 ||
      !Number.isSafeInteger(appender.columnCount) || appender.columnCount < 1 ||
      appender.columnCount > maxColumns) throw new PhysicalValueError('ImportColumns');
  const nativeTypes = Array.from({length: appender.columnCount}, (_, i) => appender.columnType(i));
  const types = Object.freeze(nativeTypes.map(physicalType));
  if (batch !== undefined && (!Number.isSafeInteger(batch.rows) || batch.rows < 1 ||
      batch.rows > 2048 || !Number.isSafeInteger(batch.bytes) || batch.bytes < 1 ||
      typeof appender.appendDataChunk !== 'function')) {
    throw new PhysicalValueError('InvalidAppenderBatch');
  }
  const columns = batch && Array.from({length: types.length}, () => []);
  let bufferedRows = 0, bufferedBytes = 0;
  let pending = false, live = true;
  const methods = new Array(types.length);
  const values = new Array(types.length);
  // Reuse the same conversion/range rules as prepared-parameter binding. Stage
  // the complete row first so a bad later cell cannot partially append a row.
  const staging = Object.freeze(Object.fromEntries(suffixes.map(suffix => {
    const method = `append${suffix}`;
    return [`bind${suffix}`, (index, value) => {
      methods[index - 1] = method;
      values[index - 1] = value;
    }];
  })));
  const flushBuffered = () => {
    if (!bufferedRows) return;
    try {
      const chunk = DuckDBDataChunk.create(nativeTypes, bufferedRows);
      for (let i = 0; i < columns.length; i++) chunk.setColumnValues(i, columns[i]);
      appender.appendDataChunk(chunk);
      for (const column of columns) column.length = 0;
      bufferedRows = 0;
      bufferedBytes = 0;
    } catch (error) {
      live = false;
      throw error;
    }
  };
  return Object.freeze({
    types,
    invalidate() {
      live = false;
      if (columns) for (const column of columns) column.length = 0;
    },
    flush() {
      if (!live || pending) throw new PhysicalValueError('AppenderUnavailable');
      pending = true;
      try { flushBuffered(); } finally { pending = false; }
    },
    append(parameters, beforeWrite) {
      if (!live || pending) throw new PhysicalValueError('AppenderUnavailable');
      if (!Array.isArray(parameters) || parameters.length !== types.length) {
        throw new PhysicalValueError('ImportColumns');
      }
      pending = true;
      try {
        let bytes = 16;
        for (let i = 0; i < types.length; i++) {
          const parameter = parameters[i];
          const expected = types[i];
          if (!parameter?.type || parameter.type.id !== expected.id ||
              parameter.type.precision !== expected.precision || parameter.type.scale !== expected.scale) {
            throw new PhysicalValueError('ImportPhysicalType');
          }
          const value = parameter.value;
          if (value !== null && typeof value !== 'string' && typeof value !== 'boolean') {
            throw new PhysicalValueError('InvalidPhysicalValue');
          }
          bytes += 8 + (typeof value === 'string' ? Buffer.byteLength(value, 'utf8') : 1);
          bindPhysicalValue(staging, i + 1, parameter);
        }
        beforeWrite?.(bytes);
        if (columns) {
          // Flush before staging the next complete row. The buffer is bounded
          // independently of DuckDB's native vector capacity.
          if (bufferedRows >= batch.rows || bufferedBytes + bytes > batch.bytes) {
            flushBuffered();
          }
          for (let i = 0; i < columns.length; i++) columns[i].push(values[i]);
          bufferedRows++;
          bufferedBytes += bytes;
        } else {
          try {
            for (let i = 0; i < methods.length; i++) appender[methods[i]](values[i]);
            appender.endRow();
          } catch (error) {
            // A partial native row is not correctable by resending another row.
            // The owning attempt must stop and reclaim its native resources.
            live = false;
            throw error;
          }
        }
      } finally {
        values.fill(undefined);
        pending = false;
      }
    },
  });
}
