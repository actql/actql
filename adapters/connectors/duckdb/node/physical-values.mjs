// Private adapter transport, NOT ActQL canonical values or semantic admission.
// Physical type matching and ActQL conversion belong to the MoonBit adapter.
import {
  DuckDBTypeId, dateValue, decimalValue, timestampValue, timestampTZValue,
  timestampSecondsValue, timestampMillisValue, timestampNanosValue,
} from '@duckdb/node-api';

const integers = new Map([
  ['TINYINT', [8n, true, 'bindTinyInt']],
  ['SMALLINT', [16n, true, 'bindSmallInt']],
  ['INTEGER', [32n, true, 'bindInteger']],
  ['BIGINT', [64n, true, 'bindBigInt']],
  ['HUGEINT', [128n, true, 'bindHugeInt']],
  ['UTINYINT', [8n, false, 'bindUTinyInt']],
  ['USMALLINT', [16n, false, 'bindUSmallInt']],
  ['UINTEGER', [32n, false, 'bindUInteger']],
  ['UBIGINT', [64n, false, 'bindUBigInt']],
  ['UHUGEINT', [128n, false, 'bindUHugeInt']],
]);
const timestamps = new Map([
  ['TIMESTAMP', ['micros', timestampValue, 'bindTimestamp']],
  ['TIMESTAMP_TZ', ['micros', timestampTZValue, 'bindTimestampTZ']],
  ['TIMESTAMP_S', ['seconds', timestampSecondsValue, 'bindTimestampSeconds']],
  ['TIMESTAMP_MS', ['millis', timestampMillisValue, 'bindTimestampMilliseconds']],
  ['TIMESTAMP_NS', ['nanos', timestampNanosValue, 'bindTimestampNanoseconds']],
]);

export class PhysicalValueError extends Error {
  constructor(code) { super(code); this.name = 'PhysicalValueError'; this.code = code; }
}

function requireValue(condition) {
  if (!condition) throw new PhysicalValueError('InvalidPhysicalValue');
}

function exactInteger(text, bits, signed) {
  requireValue(typeof text === 'string' && text.length <= 40 && /^(0|-?[1-9][0-9]*)$/.test(text));
  const n = BigInt(text);
  const top = signed ? (1n << (bits - 1n)) : (1n << bits);
  requireValue(n >= (signed ? -top : 0n) && n < top);
  return n;
}

// Use bits rather than JSON numbers: negative zero and nonfinite physical values
// survive transport for MoonBit to admit/reject under the selected value contract.
function floatBits(value, width) {
  const buffer = Buffer.alloc(width);
  if (width === 4) buffer.writeFloatBE(value);
  else buffer.writeDoubleBE(value);
  return buffer.toString('hex');
}

function floatFromBits(text, width) {
  requireValue(typeof text === 'string' && text.length === width * 2 && /^[0-9a-f]+$/.test(text));
  const buffer = Buffer.from(text, 'hex');
  return width === 4 ? buffer.readFloatBE() : buffer.readDoubleBE();
}

export function physicalType(type) {
  const id = DuckDBTypeId[type.typeId];
  if (type.alias || !(integers.has(id) || timestamps.has(id) ||
    ['BOOLEAN', 'VARCHAR', 'FLOAT', 'DOUBLE', 'DATE', 'DECIMAL'].includes(id))) {
    throw new PhysicalValueError('UnsupportedPhysicalType');
  }
  return Object.freeze(id === 'DECIMAL'
    ? { id, precision: type.width, scale: type.scale }
    : { id });
}

export function exportPhysicalValue(value, type) {
  if (value === null) return null;
  const { id } = type;
  if (integers.has(id)) return value.toString();
  if (timestamps.has(id)) return value[timestamps.get(id)[0]].toString();
  switch (id) {
    case 'BOOLEAN': case 'VARCHAR': return value;
    case 'FLOAT': return floatBits(value, 4);
    case 'DOUBLE': return floatBits(value, 8);
    case 'DECIMAL': return value.value.toString();
    case 'DATE': return value.days.toString();
    default: throw new PhysicalValueError('UnsupportedPhysicalType');
  }
}

// The native transport exports only JSON scalars. Most numeric encodings and
// ordinary identifiers are printable ASCII and need no JSON escaping. Avoid
// allocating an encoded string solely to enforce the physical frame ceiling;
// preserve JSON.stringify's exact byte count for every other string.
export function physicalJsonScalarBytes(value) {
  if (value === null) return 4;
  if (value === true) return 4;
  if (value === false) return 5;
  if (typeof value !== 'string') throw new PhysicalValueError('InvalidPhysicalValue');
  for (let i = 0; i < value.length; i++) {
    const unit = value.charCodeAt(i);
    if (unit < 0x20 || unit > 0x7e || unit === 0x22 || unit === 0x5c) {
      return Buffer.byteLength(JSON.stringify(value), 'utf8');
    }
  }
  return value.length + 2;
}

// Only transport-shape/range validation here. This does not certify that a
// physical integer is representable as ActQL number, or that a timestamp is UTC.
export function bindPhysicalValue(statement, index, { type, value }) {
  if (!type || typeof type.id !== 'string') throw new PhysicalValueError('InvalidPhysicalType');
  const { id } = type;
  if (!(integers.has(id) || timestamps.has(id) ||
    ['BOOLEAN', 'VARCHAR', 'FLOAT', 'DOUBLE', 'DATE', 'DECIMAL'].includes(id))) {
    throw new PhysicalValueError('UnsupportedPhysicalType');
  }
  if (id === 'DECIMAL') {
    requireValue(Number.isInteger(type.precision) && type.precision >= 1 && type.precision <= 38 &&
      Number.isInteger(type.scale) && type.scale >= 0 && type.scale <= type.precision);
  }
  if (value === null) { statement.bindNull(index); return; }
  if (integers.has(id)) {
    const [bits, signed, method] = integers.get(id);
    const n = exactInteger(value, bits, signed);
    statement[method](index, bits <= 32n ? Number(n) : n);
    return;
  }
  if (timestamps.has(id)) {
    const [, make, method] = timestamps.get(id);
    statement[method](index, make(exactInteger(value, 64n, true)));
    return;
  }
  switch (id) {
    case 'BOOLEAN': requireValue(typeof value === 'boolean'); statement.bindBoolean(index, value); break;
    case 'VARCHAR': requireValue(typeof value === 'string'); statement.bindVarchar(index, value); break;
    case 'FLOAT': statement.bindFloat(index, floatFromBits(value, 4)); break;
    case 'DOUBLE': statement.bindDouble(index, floatFromBits(value, 8)); break;
    case 'DATE': statement.bindDate(index, dateValue(Number(exactInteger(value, 32n, true)))); break;
    case 'DECIMAL': {
      const n = exactInteger(value, 128n, true);
      const bound = 10n ** BigInt(type.precision);
      requireValue(n > -bound && n < bound);
      statement.bindDecimal(index, decimalValue(n, type.precision, type.scale));
      break;
    }
  }
}
