import type {Dir, Dirent} from 'node:fs';
import {lstat, opendir, rm, rmdir, unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import {Buffer as OriginalBuffer} from 'node:buffer';
import {assertHostJournalDirectoryInspector, inspectHostJournalDirectory}
  from '../host-node/host-journal-directory.mjs';
import {exactKeys, fail, quantity, readBounded} from './publication-store-io.mjs';

type BootstrapCloseStatus = Readonly<{pending: boolean}>;
type DirectoryBufferView = Pick<Dir, 'close'> & {read(): Promise<Dirent<Buffer | string> | null>};
type OpenBufferDirectory = (path: string, options: {encoding: 'buffer'; bufferSize: number}) =>
  Promise<DirectoryBufferView>;
type BootstrapFailure = {
  cleanupHandle?: Readonly<{status(): BootstrapCloseStatus; retry(): Promise<BootstrapCloseStatus>}>;
  cleanupPending?: true;
  cleanupError?: unknown;
};

const originalByteLength = OriginalBuffer.byteLength;
const originalApply = Reflect.apply;

export async function processIsAlive(pid: unknown) {
  if (!Number.isSafeInteger(pid) || (pid as number) < 1) return false;
  try {
    process.kill(pid as number, 0);
    return true;
  } catch (error) {
    if ((error as {code?: unknown} | null | undefined)?.code === 'ESRCH') return false;
    if ((error as {code?: unknown} | null | undefined)?.code === 'EPERM') return true;
    throw error;
  }
}

// One physical opening's acquisition controls, not a capacity Owner/grant.
// Names and metadata are conservatively kept in this opening's raw footprint
// until it completes: no earlier Buffer/String/Promise retirement is assumed.
// The original Host envelope separately funds decode/tree/backing, the one
// excess Dirent/EOF probe, FD/Dir/cleanup controls and generated Host baseline.
export function storeBootstrapAcquisition(supplied: unknown, maxMetadataBytes: number,
  directoryInspection?: unknown) {
  if (!exactKeys(supplied, ['maxWireBytes', 'maxDirectoryEntries']) ||
      !quantity(supplied.maxWireBytes) || supplied.maxWireBytes === 0 ||
      !quantity(supplied.maxDirectoryEntries)) {
    fail('InvalidPublicationStoreBootstrapBounds');
  }
  // Capture before I/O. A mutated argument never widens this opening.
  const {maxWireBytes, maxDirectoryEntries} = supplied;
  if (directoryInspection !== undefined) {
    assertHostJournalDirectoryInspector(directoryInspection, maxDirectoryEntries);
  }
  let entries = 0, rawBytes = 0;
  const readMetadata = async (path: string) => {
    const bytes = await readBounded(path,
      Math.min(maxMetadataBytes, maxWireBytes - rawBytes));
    rawBytes += bytes.byteLength;
    return bytes;
  };
  const readDirectory = async (path: string) => {
    if (directoryInspection !== undefined) {
      // The same Root owns this nominal native view and its cumulative scan
      // allowance before acquisition. A whole scan's retained names/backing
      // precedes these Store processing bounds; it is not a stock Dir lease.
      // Unknown close propagates the view's original cleanup duty unchanged.
      const names = inspectHostJournalDirectory(directoryInspection, path, maxDirectoryEntries);
      for (const name of names) {
        if (entries === maxDirectoryEntries) fail('PublicationStoreBootstrapEntriesLimit');
        entries++;
        const bytes = originalApply(originalByteLength, OriginalBuffer, [name, 'utf8']);
        if (!Number.isSafeInteger(bytes) || bytes < name.length || bytes > maxWireBytes - rawBytes) {
          fail('PublicationStoreBootstrapWireLimit');
        }
        rawBytes += bytes;
      }
      return names;
    }
    // Node supplies raw names for this option; the standard Dir type only exposes string names.
    const directory = await (opendir as unknown as OpenBufferDirectory)(path, {encoding: 'buffer', bufferSize: 1});
    let primary: unknown, failed = false;
    try {
      const names: string[] = [];
      for (;;) {
        const entry = await directory.read();
        if (entry === null) break;
        // Count every actually acquired entry, before filtering or descent.
        // The one excess native Dirent is a separately funded refusal probe.
        if (entries === maxDirectoryEntries) fail('PublicationStoreBootstrapEntriesLimit');
        entries++;
        if (!(entry.name instanceof Uint8Array) ||
            entry.name.byteLength > maxWireBytes - rawBytes) {
          fail('PublicationStoreBootstrapWireLimit');
        }
        rawBytes += entry.name.byteLength;
        let name: string;
        try { name = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(entry.name); }
        catch (cause) { fail('InvalidPublicationStoreDirectoryName', cause); }
        names.push(name);
      }
      return names;
    } catch (cause) { primary = cause; failed = true; throw cause; }
    finally {
      try {
        if ((await directory.close() as unknown) === false) fail('PublicationStoreBootstrapCleanupPending');
      }
      catch (closeFailure) {
        let original: DirectoryBufferView | undefined = directory,
          flight: Promise<BootstrapCloseStatus> | undefined;
        const status = () => Object.freeze({pending: original !== undefined});
        const cleanup = Object.freeze({status, retry() {
          if (flight !== undefined) return flight;
          if (original === undefined) return Promise.resolve(status());
          flight = Promise.resolve().then(() => original!.close() as Promise<unknown>).then(result => {
            if (result === false) fail('PublicationStoreBootstrapCleanupPending');
            original = undefined;
            return status();
          }).finally(() => { flight = undefined; });
          return flight;
        }});
        const reason = failed ? primary : closeFailure;
        const failure: BootstrapFailure = reason !== null && typeof reason === 'object' &&
          Object.isExtensible(reason) && (reason as BootstrapFailure).cleanupHandle === undefined
          ? reason as BootstrapFailure
          : new Error('PublicationStoreBootstrapCleanupPending', {cause: reason}) as Error & BootstrapFailure;
        failure.cleanupHandle = cleanup;
        failure.cleanupPending = true;
        failure.cleanupError = closeFailure;
        throw failure;
      }
    }
  };
  return Object.freeze({readMetadata, readDirectory});
}

// Use the same cumulative opening scan for old temporary trees too. Native
// recursive rm would acquire their entries behind the physical clamp. This
// retains existing cleanup semantics; it creates no new cleanup authority.
export async function removeOpeningTree(path: string,
  bootstrap: Pick<ReturnType<typeof storeBootstrapAcquisition>, 'readDirectory'> | undefined): Promise<void> {
  if (bootstrap === undefined) return rm(path, {recursive: true, force: false});
  const state = await lstat(path);
  if (state.isDirectory() && !state.isSymbolicLink()) {
    for (const name of await bootstrap.readDirectory(path)) {
      await removeOpeningTree(resolve(path, name), bootstrap);
    }
    await rmdir(path);
  } else await unlink(path);
}
