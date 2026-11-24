// The original Source acquisition child retains its physical reader and any
// cleanup it owes. The installing Host still owns admission and membership.
import {open} from 'node:fs/promises';
import type {FileHandle} from 'node:fs/promises';
import type {BigIntStats} from 'node:fs';
import {withOriginalFile} from './source-profile-json.mjs';

type Callback = () => unknown;
type ReaderCleanup = Readonly<{status: Callback; retry: Callback}>;
type Reader = object & Readonly<{close?: Callback; status?: Callback}>;
type Pending = Readonly<{pending: boolean}>;
export type SourceReaderChild = {
  reader?: Reader; readerClose?: Callback; readerStatus?: Callback; readerCloseSeen: boolean; readerStatusSeen: boolean;
  readerCloseAcknowledged: boolean; cleanup?: ReaderCleanup; cleanupStatus?: Callback; cleanupRetry?: Callback;
  attempted: boolean; closed: boolean; closing: boolean; flight?: Promise<Pending | Buffer>;
  bytes?: Buffer; failure?: unknown;
};
type FileIdentityOwner = {fileIdentity?: readonly bigint[]; children: readonly SourceReaderChild[]};
type Ports = Readonly<{
  bundle?: Readonly<{dataPath: string}>; current(): void; pending(value: unknown): boolean; fail(code: string): never;
}>;

const fileIdentity = (stat: BigIntStats) => [stat.dev, stat.ino, stat.size, stat.mtimeNs, stat.ctimeNs];

export function createOrdinarySourceReaders(ports: Ports) {
  const {current, pending, fail} = ports;
  function captureReader(child: SourceReaderChild) {
    if (!child.readerCloseSeen) {
      const method = child.reader!.close;
      child.readerClose = method; child.readerCloseSeen = true;
    }
    if (typeof child.readerClose !== 'function') fail('InstalledSourceReaderCleanupUnavailable');
    if (!child.readerStatusSeen) {
      const method = child.reader!.status;
      child.readerStatus = method; child.readerStatusSeen = true;
    }
    if (typeof child.readerStatus !== 'function') fail('InstalledSourceReaderCleanupUnavailable');
  }
  async function closeChild(child: SourceReaderChild) {
    if (child.closed) return Object.freeze({pending: false});
    if (child.flight !== undefined) return Object.freeze({pending: true});
    child.closing = true;
    const work = Promise.resolve().then(async () => {
      if (child.reader !== undefined) {
        // Retention precedes these getters. Only a getter which never
        // returned can be read again; a captured callback is never replaced.
        captureReader(child);
        if (!child.readerCloseAcknowledged) {
          const observed = await Reflect.apply(child.readerClose!, child.reader, []);
          if (pending(observed)) return Object.freeze({pending: true});
          child.readerCloseAcknowledged = true;
        }
        if (pending(Reflect.apply(child.readerStatus!, child.reader, []))) {
          return Object.freeze({pending: true});
        }
        child.reader = child.readerClose = child.readerStatus = undefined;
      }
      if (child.cleanup !== undefined) {
        if (pending(Reflect.apply(child.cleanupStatus!, child.cleanup, []))) {
          await Reflect.apply(child.cleanupRetry!, child.cleanup, []);
        }
        if (pending(Reflect.apply(child.cleanupStatus!, child.cleanup, []))) return Object.freeze({pending: true});
        child.cleanup = child.cleanupStatus = child.cleanupRetry = undefined;
      }
      child.bytes = undefined; child.closed = true;
      return Object.freeze({pending: false});
    });
    child.flight = work;
    try {return await work;} finally {if (child.flight === work) child.flight = undefined;}
  }
  async function readBytes(run: FileIdentityOwner, child: SourceReaderChild) {
    current();
    if (child.closed || child.attempted) fail('InstalledSourcePreparationMismatch');
    child.attempted = true;
    const work = (async () => {
      try {
        const bytes = await withOriginalFile<Buffer, FileHandle>(ports.bundle!.dataPath, open, async original => {
          const read = original.read, stat = original.stat;
          if (typeof read !== 'function' || typeof stat !== 'function') fail('InstalledMockSourceUnavailable');
          const before = await Reflect.apply(stat, original, [{bigint: true}]) as BigIntStats;
          if (!before.isFile() || before.size > 1048576n) fail('InstalledMockSourceInputLimit');
          const identity = fileIdentity(before);
          if (run.fileIdentity === undefined) run.fileIdentity = identity;
          else if (identity.some((value, index) => value !== run.fileIdentity![index])) fail('InstalledMockSourceChanged');
          const chunks = []; let used = 0;
          for (;;) {
            current();
            const buffer = Buffer.allocUnsafe(Math.min(65536, 1048576 - used + 1));
            const {bytesRead} = await Reflect.apply(read, original, [buffer, 0, buffer.length, null]);
            if (!Number.isSafeInteger(bytesRead) || bytesRead < 0 || bytesRead > buffer.length) fail('InstalledMockSourceUnavailable');
            if (bytesRead === 0) break;
            used += bytesRead;
            if (used > 1048576) fail('InstalledMockSourceInputLimit');
            chunks.push(buffer.subarray(0, bytesRead));
          }
          const after = await Reflect.apply(stat, original, [{bigint: true}]) as BigIntStats;
          if (fileIdentity(after).some((value, index) => value !== identity[index])) fail('InstalledMockSourceChanged');
          return Buffer.concat(chunks, used);
        });
        current();
        for (const sibling of run.children) if (sibling !== child && sibling.bytes !== undefined &&
            !bytes.equals(sibling.bytes)) fail('InstalledMockSourceChanged');
        child.bytes = bytes; return bytes;
      } catch (cause) {
        child.failure = cause;
        // The bounded reader retains its same physical FileHandle on failed
        // close. Keep its original cleanup before another current check.
        child.cleanup = (cause as Readonly<{cleanupHandle?: ReaderCleanup}> | null | undefined)?.cleanupHandle;
        if (child.cleanup !== undefined) {
          child.cleanupStatus = child.cleanup.status; child.cleanupRetry = child.cleanup.retry;
        }
        throw cause;
      }
    })();
    child.flight = work;
    try {return await work;} finally {if (child.flight === work) child.flight = undefined;}
  }
  return {captureReader, closeChild, readBytes};
}
