// Private adapter transport, NOT ActQL canonical values or semantic admission.
// Physical type matching and ActQL conversion belong to the MoonBit adapter.
import {
  DuckDBTypeId, dateValue, decimalValue, timestampValue, timestampTZValue,
  timestampSecondsValue, timestampMillisValue, timestampNanosValue,
} from '@duckdb/node-api';

import type {
  DuckDBDateValue, DuckDBDecimalType, DuckDBDecimalValue, DuckDBPreparedStatement, DuckDBType, DuckDBValue,
} from '@duckdb/node-api';

type IntegerMethod = 'bindTinyInt' | 'bindSmallInt' | 'bindInteger' | 'bindBigInt' | 'bindHugeInt' |
  'bindUTinyInt' | 'bindUSmallInt' | 'bindUInteger' | 'bindUBigInt' | 'bindUHugeInt';
type TimestampMethod = 'bindTimestamp' | 'bindTimestampTZ' | 'bindTimestampSeconds' |
  'bindTimestampMilliseconds' | 'bindTimestampNanoseconds';
type TimestampUnit = 'micros' | 'seconds' | 'millis' | 'nanos';
export type PhysicalBinder = Pick<DuckDBPreparedStatement, IntegerMethod | TimestampMethod |
  'bindNull' | 'bindBoolean' | 'bindVarchar' | 'bindFloat' | 'bindDouble' | 'bindDate' | 'bindDecimal'>;
export type PhysicalType = Readonly<{id: string; precision?: number; scale?: number}>;
export type PhysicalField = Readonly<{name: string; type: PhysicalType}>;
export type PhysicalParameter = Readonly<{type: PhysicalType; value: unknown}>;
export type PhysicalScalar = string | boolean | null;

const integers = new Map<string, readonly [bigint, boolean, IntegerMethod]>([
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
const timestamps = new Map<string, readonly [TimestampUnit, (value: bigint) => DuckDBValue, TimestampMethod]>([
  ['TIMESTAMP', ['micros', timestampValue, 'bindTimestamp']],
  ['TIMESTAMP_TZ', ['micros', timestampTZValue, 'bindTimestampTZ']],
  ['TIMESTAMP_S', ['seconds', timestampSecondsValue, 'bindTimestampSeconds']],
  ['TIMESTAMP_MS', ['millis', timestampMillisValue, 'bindTimestampMilliseconds']],
  ['TIMESTAMP_NS', ['nanos', timestampNanosValue, 'bindTimestampNanoseconds']],
]);

export class PhysicalValueError extends Error {
  declare code: string;
  constructor(code: string) { super(code); this.name = 'PhysicalValueError'; this.code = code; }
}

const canonicalIntegerPattern = /^(0|-?[1-9][0-9]*)$/;
const canonicalHexPattern = /^[0-9a-f]+$/;

function requireValue(condition: unknown): asserts condition {
  if (!condition) throw new PhysicalValueError('InvalidPhysicalValue');
}

function canonicalIntegerText(text: unknown): asserts text is string {
  requireValue(typeof text === 'string' && text.length <= 40 && canonicalIntegerPattern.test(text));
}

function exactInteger(text: unknown, bits: bigint, signed: boolean) {
  canonicalIntegerText(text);
  const n = BigInt(text);
  const top = signed ? (1n << (bits - 1n)) : (1n << bits);
  requireValue(n >= (signed ? -top : 0n) && n < top);
  return n;
}

function exactSmallInteger(text: unknown, bits: number, signed: boolean) {
  canonicalIntegerText(text);
  const n = Number(text);
  const top = signed ? 2 ** (bits - 1) : 2 ** bits;
  requireValue(Number.isSafeInteger(n) && n >= (signed ? -top : 0) && n < top);
  return n;
}

// Use bits rather than JSON numbers: negative zero and nonfinite physical values
// survive transport for MoonBit to admit/reject under the selected value contract.
// Only the returned hex string escapes this synchronous function. Reusing the
// fully overwritten scratch buffer avoids one native allocation per number.
const floatBitsScratch = Buffer.allocUnsafe(8);
function floatBits(value: number, width: 4 | 8) {
  if (width === 4) floatBitsScratch.writeFloatBE(value);
  else floatBitsScratch.writeDoubleBE(value);
  return floatBitsScratch.toString('hex', 0, width);
}

function floatFromBits(text: unknown, width: 4 | 8) {
  requireValue(typeof text === 'string' && text.length === width * 2 && canonicalHexPattern.test(text));
  requireValue(floatBitsScratch.write(text, 0, width, 'hex') === width);
  return width === 4 ? floatBitsScratch.readFloatBE() : floatBitsScratch.readDoubleBE();
}

export function physicalType(type: DuckDBType): PhysicalType {
  const id = DuckDBTypeId[type.typeId];
  if (type.alias || !(integers.has(id) || timestamps.has(id) ||
    ['BOOLEAN', 'VARCHAR', 'FLOAT', 'DOUBLE', 'DATE', 'DECIMAL'].includes(id))) {
    throw new PhysicalValueError('UnsupportedPhysicalType');
  }
  return Object.freeze(id === 'DECIMAL'
    ? { id, precision: (type as DuckDBDecimalType).width, scale: (type as DuckDBDecimalType).scale }
    : { id });
}

export function exportPhysicalValue(value: DuckDBValue, type: PhysicalType): PhysicalScalar {
  if (value === null) return null;
  const { id } = type;
  if (integers.has(id)) return value.toString();
  if (timestamps.has(id)) return (value as Partial<Record<TimestampUnit, bigint>>)[timestamps.get(id)![0]]!.toString();
  switch (id) {
    case 'BOOLEAN': case 'VARCHAR': return value as boolean | string;
    case 'FLOAT': return floatBits(value as number, 4);
    case 'DOUBLE': return floatBits(value as number, 8);
    case 'DECIMAL': return (value as DuckDBDecimalValue).value.toString();
    case 'DATE': return (value as DuckDBDateValue).days.toString();
    default: throw new PhysicalValueError('UnsupportedPhysicalType');
  }
}

// The native transport exports only JSON scalars. Most numeric encodings and
// ordinary identifiers are printable ASCII and need no JSON escaping. Avoid
// allocating an encoded string solely to enforce the physical frame ceiling;
// preserve JSON.stringify's exact byte count for every other string.
export function physicalJsonScalarBytes(value: unknown) {
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
export function bindPhysicalValue(statement: PhysicalBinder, index: number, { type, value }: PhysicalParameter) {
  if (!type || typeof type.id !== 'string') throw new PhysicalValueError('InvalidPhysicalType');
  const { id } = type;
  if (!(integers.has(id) || timestamps.has(id) ||
    ['BOOLEAN', 'VARCHAR', 'FLOAT', 'DOUBLE', 'DATE', 'DECIMAL'].includes(id))) {
    throw new PhysicalValueError('UnsupportedPhysicalType');
  }
  if (id === 'DECIMAL') {
    requireValue(Number.isInteger(type.precision) && type.precision! >= 1 && type.precision! <= 38 &&
      Number.isInteger(type.scale) && type.scale! >= 0 && type.scale! <= type.precision!);
  }
  if (value === null) { statement.bindNull(index); return; }
  if (integers.has(id)) {
    const [bits, signed, method] = integers.get(id)!;
    const n = bits <= 32n
      ? exactSmallInteger(value, Number(bits), signed)
      : exactInteger(value, bits, signed);
    statement[method](index, n as never);
    return;
  }
  if (timestamps.has(id)) {
    const [, make, method] = timestamps.get(id)!;
    statement[method](index, make(exactInteger(value, 64n, true)) as never);
    return;
  }
  switch (id) {
    case 'BOOLEAN': requireValue(typeof value === 'boolean'); statement.bindBoolean(index, value); break;
    case 'VARCHAR': requireValue(typeof value === 'string'); statement.bindVarchar(index, value); break;
    case 'FLOAT': statement.bindFloat(index, floatFromBits(value, 4)); break;
    case 'DOUBLE': statement.bindDouble(index, floatFromBits(value, 8)); break;
    case 'DATE': statement.bindDate(index, dateValue(exactSmallInteger(value, 32, true))); break;
    case 'DECIMAL': {
      const n = exactInteger(value, 128n, true);
      const bound = 10n ** BigInt(type.precision!);
      requireValue(n > -bound && n < bound);
      statement.bindDecimal(index, decimalValue(n, type.precision!, type.scale!));
      break;
    }
  }
}
