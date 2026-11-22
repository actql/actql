// Compile-time subset of the optional, lockfile-pinned Neo SDK used by Session.
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
  createAppender(table: string, schema?: string): Promise<DuckDBAppender>;
  extractStatements(sql: string): Promise<{
    readonly count: number;
    prepare(index: number): Promise<DuckDBPreparedStatement>;
  }>;
}

export interface DuckDBAppender {
  closeSync(): void;
  flushSync(): void;
}

export interface DuckDBPreparedStatement {
  readonly statementType: StatementType;
  readonly parameterCount: number;
  clearBindings(): void;
  destroySync(): void;
  stream(): Promise<{
    readonly columnCount: number;
    columnName(index: number): string;
    columnType(index: number): unknown;
    fetchChunk(): Promise<{
      readonly rowCount: number;
      getColumnVector(index: number): DuckDBVector;
    } | null>;
  }>;
}

interface DuckDBVector {
  getItem(index: number): unknown;
  slice(offset: number, length: number): DuckDBVector;
}
