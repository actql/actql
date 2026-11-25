// Type views for the fault fixtures that interpose the original Node file port.
import type {ReadOptions, ReadOptionsWithBuffer, ReadPosition} from 'node:fs';
import type {FileHandle, FileReadResult} from 'node:fs/promises';

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
export type FixtureReadArguments =
  [buffer: NodeJS.ArrayBufferView, offset?: number | null, length?: number | null, position?: ReadPosition | null] |
  [buffer: NodeJS.ArrayBufferView, options?: ReadOptions] |
  [options?: ReadOptionsWithBuffer<NodeJS.ArrayBufferView>];
export type FixtureRead = (...args: FixtureReadArguments) => Promise<FileReadResult<NodeJS.ArrayBufferView>>;
export type FixtureFile = Omit<FileHandle, 'close'> & {close(): Promise<void | false>};

export type FixtureFailureFields = Readonly<{
  code?: unknown;
  cause?: unknown;
  primaryFailure?: unknown;
  cleanupError?: unknown;
  cleanupPending?: unknown;
  cleanupHandle?: FixtureCleanup;
}>;
export type FixtureCleanupFailure = FixtureFailureFields & Readonly<{cleanupHandle: FixtureCleanup}>;
