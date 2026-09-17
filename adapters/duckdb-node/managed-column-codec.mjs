// Finite installed physical representation for managed DuckDB values. This is
// not an ActQL logical content identity. It preserves column/row occurrence
// order in bounded frames and supports only the explicitly listed types.
import {createHash} from 'node:crypto';
import {createReadStream} from 'node:fs';
import {createInterface} from 'node:readline';
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

// Registered representation provider for Local managed execution. It emits
// canonical JSON objects in logical occurrence order and cannot approve a
// completion or content identity. File access and lifetime remain owned by the
// Store borrow surrounding this provider.
export function managedColumnRowProvider(fieldsFrame) {
  let fields;
  try {
    const decoded = JSON.parse(fieldsFrame);
    fields = Array.isArray(decoded) ? decoded : decoded?.fields;
  }
  catch { throw new DuckDBTransportError('UnsupportedManagedColumnFrame'); }
  if (!Array.isArray(fields) || fields.length === 0 || fields.some(field =>
    !Array.isArray(field) || field.length !== 4 ||
    typeof field[0] !== 'string' || !['DOUBLE', 'VARCHAR'].includes(field[1]))) {
    throw new DuckDBTransportError('UnsupportedManagedColumnFrame');
  }
  return Object.freeze({
    async read(file, emit, signal) {
      if (!file || typeof file.path !== 'string' || typeof emit !== 'function') {
        throw new DuckDBTransportError('UnsupportedManagedColumnFrame');
      }
      let expectedOrdinal = 0;
      const lines = createInterface({
        input: createReadStream(file.path, {encoding: 'utf8'}),
        crlfDelay: Infinity,
      });
      try {
        for await (const line of lines) {
          signal?.throwIfAborted();
          if (line.length === 0) continue;
          let frame;
          try { frame = JSON.parse(line); }
          catch { throw new DuckDBTransportError('UnsupportedManagedColumnFrame'); }
          const keys = Object.keys(frame);
          const expectedKeys = [
            ...fields.map((_, index) => `c${index}`),
            'o',
          ];
          if (keys.length !== expectedKeys.length ||
              expectedKeys.some(key => !Object.hasOwn(frame, key)) ||
              !Array.isArray(frame.o)) {
            throw new DuckDBTransportError('UnsupportedManagedColumnFrame');
          }
          const rows = frame.o.length;
          if (fields.some((_, index) => !Array.isArray(frame[`c${index}`]) ||
            frame[`c${index}`].length !== rows)) {
            throw new DuckDBTransportError('UnsupportedManagedColumnFrame');
          }
          for (let row = 0; row < rows; row++) {
            if (frame.o[row] !== expectedOrdinal) {
              throw new DuckDBTransportError('UnsupportedManagedColumnFrame');
            }
            const object = Object.create(null);
            for (let column = 0; column < fields.length; column++) {
              const value = frame[`c${column}`][row];
              if (value !== null &&
                  (fields[column][1] === 'DOUBLE'
                    ? typeof value !== 'number' || !Number.isFinite(value)
                    : typeof value !== 'string')) {
                throw new DuckDBTransportError('UnsupportedManagedColumnValue');
              }
              object[fields[column][0]] = value;
            }
            await emit(JSON.stringify(object));
            expectedOrdinal++;
          }
        }
      } finally {
        lines.close();
      }
    },
  });
}
