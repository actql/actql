// Compile-time subset of the optional, lockfile-pinned Neo SDK used by Session, its physical transport and focused fixtures.
// When installed, the SDK declarations take precedence. Runtime uses the
// same original package import in both cases.
export declare const StatementType: {
  readonly SELECT: number;
  readonly CREATE: number;
  readonly INSERT: number;
  readonly DROP: number;
  readonly COPY: number;
};
export type StatementType = number;

export declare class DuckDBInstance {
  static create(path?: string, options?: Record<string, string>): Promise<DuckDBInstance>;
  connect(): Promise<DuckDBConnection>;
  closeSync(): void;
}

export interface DuckDBConnection {
  closeSync(): void;
  interrupt(): void;
  run(sql: string): Promise<unknown>;
  runAndReadAll(sql: string): Promise<{
    readonly columnCount: number;
    columnType(index: number): DuckDBType;
    getRows(): DuckDBValue[][];
    getRowObjects(): Record<string, DuckDBValue>[];
  }>;
  prepare(sql: string): Promise<DuckDBPreparedStatement>;
  createAppender(table: string, schema?: string | null, catalog?: string | null): Promise<DuckDBAppender>;
  extractStatements(sql: string): Promise<{
    readonly count: number;
    prepare(index: number): Promise<DuckDBPreparedStatement>;
  }>;
}

export interface DuckDBAppender {
  closeSync(): void;
  flushSync(): void;
  readonly columnCount: number;
  columnType(index: number): DuckDBType;
  appendDataChunk(chunk: DuckDBDataChunk): void;
  endRow(): void;
  appendBoolean(value: boolean): void;
  appendVarchar(value: string): void;
  appendFloat(value: number): void;
  appendDouble(value: number): void;
  appendTinyInt(value: number): void;
  appendSmallInt(value: number): void;
  appendInteger(value: number): void;
  appendBigInt(value: bigint): void;
  appendHugeInt(value: bigint): void;
  appendUTinyInt(value: number): void;
  appendUSmallInt(value: number): void;
  appendUInteger(value: number): void;
  appendUBigInt(value: bigint): void;
  appendUHugeInt(value: bigint): void;
  appendDate(value: DuckDBDateValue): void;
  appendDecimal(value: DuckDBDecimalValue): void;
  appendTimestamp(value: {readonly micros: bigint}): void;
  appendTimestampTZ(value: {readonly micros: bigint}): void;
  appendTimestampSeconds(value: {readonly seconds: bigint}): void;
  appendTimestampMilliseconds(value: {readonly millis: bigint}): void;
  appendTimestampNanoseconds(value: {readonly nanos: bigint}): void;
  appendNull(): void;
}

export interface DuckDBPreparedStatement {
  readonly statementType: StatementType;
  readonly parameterCount: number;
  clearBindings(): void;
  destroySync(): void;
  bindBoolean(parameterIndex: number, value: boolean): void;
  bindVarchar(parameterIndex: number, value: string): void;
  bindFloat(parameterIndex: number, value: number): void;
  bindDouble(parameterIndex: number, value: number): void;
  bindTinyInt(parameterIndex: number, value: number): void;
  bindSmallInt(parameterIndex: number, value: number): void;
  bindInteger(parameterIndex: number, value: number): void;
  bindBigInt(parameterIndex: number, value: bigint): void;
  bindHugeInt(parameterIndex: number, value: bigint): void;
  bindUTinyInt(parameterIndex: number, value: number): void;
  bindUSmallInt(parameterIndex: number, value: number): void;
  bindUInteger(parameterIndex: number, value: number): void;
  bindUBigInt(parameterIndex: number, value: bigint): void;
  bindUHugeInt(parameterIndex: number, value: bigint): void;
  bindDate(parameterIndex: number, value: DuckDBDateValue): void;
  bindDecimal(parameterIndex: number, value: DuckDBDecimalValue): void;
  bindTimestamp(parameterIndex: number, value: {readonly micros: bigint}): void;
  bindTimestampTZ(parameterIndex: number, value: {readonly micros: bigint}): void;
  bindTimestampSeconds(parameterIndex: number, value: {readonly seconds: bigint}): void;
  bindTimestampMilliseconds(parameterIndex: number, value: {readonly millis: bigint}): void;
  bindTimestampNanoseconds(parameterIndex: number, value: {readonly nanos: bigint}): void;
  bindNull(parameterIndex: number): void;
  runAndReadAll(): Promise<{getRows(): DuckDBValue[][]}>;
  stream(): Promise<{
    readonly columnCount: number;
    columnName(index: number): string;
    columnType(index: number): DuckDBType;
    fetchChunk(): Promise<DuckDBDataChunk | null>;
  }>;
}

export type DuckDBValue = null | boolean | number | bigint | string | object;

export interface DuckDBType {
  readonly typeId: number;
  readonly alias?: string;
}
export interface DuckDBDecimalType extends DuckDBType {
  readonly width: number;
  readonly scale: number;
}
export declare const DuckDBTypeId: Readonly<Record<number, string>>;
export declare const BOOLEAN: DuckDBType;
export declare const DOUBLE: DuckDBType;
export declare const INTEGER: DuckDBType;
export declare const VARCHAR: DuckDBType;

export interface DuckDBVector {
  readonly itemCount: number;
  getItem(index: number): DuckDBValue;
  slice(offset: number, length: number): DuckDBVector;
}

export declare const DuckDBVarCharVector: abstract new (...args: never[]) => DuckDBVector;

export declare class DuckDBDataChunk {
  static create(types: readonly DuckDBType[], rowCount?: number): DuckDBDataChunk;
  readonly rowCount: number;
  getColumnVector(index: number): DuckDBVector;
  getColumnValues(index: number): DuckDBValue[];
  setColumnValues(index: number, values: readonly DuckDBValue[]): void;
}

export interface DuckDBDateValue {readonly days: number}
export interface DuckDBDecimalValue {readonly value: bigint}
export declare function dateValue(days: number): DuckDBDateValue;
export declare function decimalValue(value: bigint | number, width: number, scale: number): DuckDBDecimalValue;
export declare function timestampValue(micros: bigint): {readonly micros: bigint};
export declare function timestampTZValue(micros: bigint): {readonly micros: bigint};
export declare function timestampSecondsValue(seconds: bigint): {readonly seconds: bigint};
export declare function timestampMillisValue(millis: bigint): {readonly millis: bigint};
export declare function timestampNanosValue(nanos: bigint): {readonly nanos: bigint};
