// Type views for the fault fixtures that interpose the original Node file port.
type PositionalBufferArguments = [buffer: NodeJS.ArrayBufferView, offset?: number | null,
  length?: number | null, position?: number | null];
type BufferOptions = Readonly<{offset?: number; length?: number; position?: number}>;
type FileWriteArguments = PositionalBufferArguments |
  [buffer: Uint8Array, options?: BufferOptions] |
  [data: string, position?: number | null, encoding?: BufferEncoding | null];
type FileWriteResult<Data> = Promise<{bytesWritten: number; buffer: Data}>;

export type PositionalBufferWrite = (...args: PositionalBufferArguments) => FileWriteResult<NodeJS.ArrayBufferView>;
export type FixtureWrite = (...args: FileWriteArguments) => FileWriteResult<string | NodeJS.ArrayBufferView>;

export type FixtureCleanup = Readonly<{
  status(): Readonly<{pending: boolean}>;
  retry(): Promise<Readonly<{pending: boolean}>>;
}>;
export type FixtureCleanupFailure = Readonly<{
  code?: unknown;
  primaryFailure?: unknown;
  cleanupHandle: FixtureCleanup;
}>;
