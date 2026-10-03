import {DuckDBVarCharVector} from '@duckdb/node-api';
import sdk from '@duckdb/node-api/package.json' with {type: 'json'};
import {DuckDBTransportError} from './configuration.mjs';
import {boundedVectorVersion} from './transport-bounds.mjs';

export function assertBoundedVectorRuntime() {
  if (sdk.version !== boundedVectorVersion) throw new DuckDBTransportError('UnsupportedBoundedVectorRuntime');
}

// Neo's public getItem() decodes VARCHAR before callers can inspect its size.
// This narrowly pinned adaptation reads only the length/validity metadata used
// by that same SDK decoder. No pointer is dereferenced here, and no ActQL value
// law is implemented. The 16-byte string descriptor and little-endian length
// must be re-audited together with the SDK pin; unknown layouts fail closed.
export function boundedVectorItem(vector, row, type, maxBytes) {
  if (type.id === 'DOUBLE_ARRAY' &&
      (!Number.isSafeInteger(type.length) || type.length < 1 ||
        type.length > Math.floor((maxBytes - 2) / 17))) {
    throw new DuckDBTransportError('ChunkBytes');
  }
  if (type.id === 'VARCHAR') {
    const {dataView, validity} = vector;
    if (!(vector instanceof DuckDBVarCharVector) || !(dataView instanceof DataView) ||
        typeof validity?.itemValid !== 'function' || !Number.isSafeInteger(row) || row < 0 ||
        row >= vector.itemCount || dataView.byteLength !== vector.itemCount * 16) {
      throw new DuckDBTransportError('UnsupportedBoundedVectorRuntime');
    }
    if (validity.itemValid(row) && dataView.getUint32(row * 16, true) > maxBytes) {
      throw new DuckDBTransportError('ChunkBytes');
    }
  }
  return vector.getItem(row);
}
