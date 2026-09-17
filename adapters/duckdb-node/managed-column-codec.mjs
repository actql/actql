// Finite installed physical representation for managed DuckDB values. This is
// not an ActQL logical content identity. It preserves column/row occurrence
// order in bounded frames and supports only the explicitly listed types.
import {createHash} from 'node:crypto';
import {DuckDBTransportError} from './session.mjs';

const codecContract = 'actql-duckdb-managed-column-frames/0.2\n' +
  'newline-delimited-object:c0..cN=typed-column-lists;o=logical-row-ordinals\n' +
  'supported=DOUBLE,VARCHAR;ordered;duplicates-preserved;store-integrity-required';

export const managedColumnCodecContractCid =
  `sha256:${createHash('sha256').update(codecContract).digest('hex')}`;

function physicalDouble(value) {
  if (value === null) return null;
  if (typeof value !== 'string' || !/^[0-9a-f]{16}$/.test(value)) {
    throw new DuckDBTransportError('UnsupportedManagedColumnValue');
  }
  return Buffer.from(value, 'hex').readDoubleBE();
}

function physicalValue(value, type) {
  if (value === null) return null;
  if (type.id === 'DOUBLE') return physicalDouble(value);
  if (type.id === 'VARCHAR' && typeof value === 'string') return value;
  throw new DuckDBTransportError('UnsupportedManagedColumnValue');
}

export function encodeManagedColumnFrame(fields, columns, rowCount, firstRow) {
  if (!Array.isArray(fields) || !fields.length || !Array.isArray(columns) ||
      fields.length !== columns.length || !Number.isSafeInteger(rowCount) || rowCount < 0 ||
      !Number.isSafeInteger(firstRow) || firstRow < 0 ||
      firstRow > Number.MAX_SAFE_INTEGER - rowCount) {
    throw new DuckDBTransportError('UnsupportedManagedColumnFrame');
  }
  const frame = Object.create(null);
  for (let column = 0; column < fields.length; column++) {
    if (!fields[column]?.type || !['DOUBLE', 'VARCHAR'].includes(fields[column].type.id) ||
        !Array.isArray(columns[column]) || columns[column].length !== rowCount) {
      throw new DuckDBTransportError('UnsupportedManagedColumnFrame');
    }
    frame[`c${column}`] = columns[column].map(value => physicalValue(value, fields[column].type));
  }
  frame.o = Array.from({length: rowCount}, (_, index) => firstRow + index);
  return Buffer.from(`${JSON.stringify(frame)}\n`);
}
