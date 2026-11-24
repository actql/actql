import {constants} from 'node:fs';
import type {BigIntStats} from 'node:fs';
import {lstat, mkdir, open, readFile, rename, rmdir, unlink} from 'node:fs/promises';
import type {FileHandle} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {openPublicationOwnerLease} from './publication-owner-lease.mjs';
import {processIsAlive, removeOpeningTree} from './publication-store-bootstrap.mjs';
import {fail, PublicationStoreError, readBounded, retainStoreOpeningFailure, syncDirectoryPath}
  from './publication-store-io.mjs';

type Inode = Pick<BigIntStats, 'dev' | 'ino'>;
type MetadataIdentity = Inode & Pick<BigIntStats, 'size' | 'mtimeNs' | 'ctimeNs'>;
type PartialMetadataIdentity = Inode & Partial<MetadataIdentity>;
type Lease = NonNullable<ReturnType<typeof openPublicationOwnerLease>>;
type Bootstrap = Readonly<{
  readDirectory(path: string): Promise<readonly string[]>;
  readMetadata(path: string): Promise<Buffer>;
}>;
type MetadataOwner = Readonly<{
  token: string;
  attachLease(lease: Lease): Promise<void>;
  assertCurrent(): Promise<void>;
  release(): Promise<boolean>;
}>;
type Close = () => unknown;
type RetirementReadCleanup = Readonly<{handle: unknown; status?: Close; retry?: Close}>;
type PendingStatus = Readonly<{pending?: unknown}> | null | undefined;
type OpeningCause = Readonly<{code?: string; cleanupHandle?: {retry(): unknown}}> | null | undefined;
type OwnerRecord = Readonly<{version?: unknown; pid?: unknown; token?: unknown; leaseAnchor?: unknown}>;
type PriorReceipt = Readonly<{token?: unknown; anchor?: unknown}> | null | undefined;

const originalApply = Reflect.apply;

export async function acquireStoreOwnership(root: string, bootstrap: Bootstrap | undefined,
  key: Uint8Array | undefined, fresh = false, directoryInspection?: unknown) {
  let lease: Lease | undefined, metadata: MetadataOwner | undefined,
    failureCleanup: NonNullable<OpeningCause>['cleanupHandle'], qualificationAttempted = false;
  const release = async () => {
    if (failureCleanup !== undefined) {
      const result = await failureCleanup.retry() as PendingStatus;
      if (result?.pending !== false) fail('PublicationStoreCleanupPending');
      failureCleanup = undefined;
    }
    // A consumed/uncertain native metadata child must drain before its
    // original directory/token, lease, key or root may retire.
    lease?.drainMetadata();
    if (metadata !== undefined) {
      if (await metadata.release() !== true) return false;
      metadata = undefined;
    }
    return lease?.close() ?? true;
  };
  try {
    qualificationAttempted = !fresh;
    lease = openPublicationOwnerLease(root, directoryInspection, fresh);
    metadata = await acquireStoreMetadataOwnership(root, bootstrap, key, lease);
    const token = metadata.token;
    return Object.freeze({
      async assertCurrent() {lease?.current(); await metadata!.assertCurrent(); lease?.current();},
      async qualifyExecutionOwner() {
        if (!qualificationAttempted) {
          qualificationAttempted = true;
          try {
            if (lease === undefined) lease = openPublicationOwnerLease(root, directoryInspection);
            else if (!lease.qualify()) lease = undefined;
            if (lease?.anchor !== undefined) await metadata!.attachLease(lease);
          } catch (cause) {failureCleanup = (cause as OpeningCause)?.cleanupHandle; throw cause;}
        }
        lease?.current();
      },
      release,
      executionReceipt() {if (lease?.anchor === undefined) return undefined; lease.current(); if (metadata === undefined) fail('PublicationStoreOwnershipLost');
        return Object.freeze({token, anchor: lease.anchor});},
      priorExecutionStopped(receipt: PriorReceipt) {
        if (lease?.anchor === undefined) return false;
        try {
          lease.current(); return metadata !== undefined && typeof receipt?.token === 'string' &&
            receipt.token !== token && lease.matches(receipt.anchor);
        } catch (cause) {
          if ((['PublicationStoreLeaseChanged','PublicationStoreLeaseUnavailable','LocalFileOriginalChanged'] as
            readonly (string | undefined)[]).includes((cause as OpeningCause)?.code)) return false;
          throw cause;
        }
      },
    });
  } catch (cause) {
    failureCleanup = (cause as OpeningCause)?.cleanupHandle;
    throw await retainStoreOpeningFailure(cause, Object.freeze({release}), key);
  }
}

async function acquireStoreMetadataOwnership(root: string, bootstrap: Bootstrap | undefined,
  key: Uint8Array | undefined, lease: Lease | undefined): Promise<MetadataOwner> {
  const ownershipDirectory = resolve(root, 'owner');
  const finalOwnerPath = resolve(ownershipDirectory, 'owner.json');
  const token = randomUUID();
  // Read before acquiring ownership: a failed identity observation cannot
  // strand a newly created owner. Keep scalars, not the entire Stats object.
  const {dev: rootDevice, ino: rootInode} = await lstat(root, {bigint: true});
  while (true) {
    let directoryPath = ownershipDirectory, ownerPath = finalOwnerPath;
    let staging = false;
    try {
      if (lease !== undefined) {
        // An existence check selects old-owner validation; only the native
        // no-replace rename below is the publication condition.
        try {await lstat(directoryPath); throw Object.assign(new Error('Owner exists'), {code: 'EEXIST'});}
        catch (cause) {if ((cause as OpeningCause)?.code !== 'ENOENT') throw cause;}
        directoryPath = resolve(root, `.owner-opening-${token}`);
        ownerPath = resolve(directoryPath, 'owner.json');
        staging = true;
      }
      await mkdir(directoryPath, {mode: 0o700});
      const owner = Buffer.from(JSON.stringify({
        version: 'actql-local-publication-store-owner/0.1',
        pid: process.pid,
        token,
        ...(lease?.anchor === undefined ? {} : {leaseAnchor: lease.anchor}),
      }), 'utf8');
      let released = false, ownerRemoved = false, directoryRemoved = false;
      let ownershipDevice: bigint | undefined, ownershipInode: bigint | undefined;
      let retirementDirectory: FileHandle | undefined, retirementSynced = false;
      let ownerWriter: FileHandle | undefined, ownerWriterClose: Close | undefined, ownerFileIdentity: PartialMetadataIdentity | undefined;
      let retirementReadCleanup: RetirementReadCleanup | undefined, retirementReadFailure: unknown;
      let ownerFileCreated = false, ownerWritten = false;
      let leaseStaging: string | undefined, leaseStagingIdentity: Inode | undefined;
      const ownership: MetadataOwner = Object.freeze({
        token,
        async attachLease(currentLease: Lease) {
          await ownership.assertCurrent(); currentLease.current();
          const bytes = Buffer.from(JSON.stringify({version: 'actql-local-publication-store-owner/0.1',
            pid: process.pid, token, leaseAnchor: currentLease.anchor}), 'utf8');
          leaseStaging = resolve(directoryPath, `.lease-${token}.json`);
          ownerWriter = await open(leaseStaging, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
          ownerWriterClose = ownerWriter.close;
          const original = await ownerWriter.stat({bigint: true});
          leaseStagingIdentity = {dev: original.dev, ino: original.ino};
          let offset = 0;
          while (offset < bytes.byteLength) {
            const {bytesWritten} = await ownerWriter.write(bytes, offset, bytes.byteLength - offset, offset);
            if (bytesWritten === 0) fail('IncompletePublicationWrite');
            offset += bytesWritten;
          }
          await ownerWriter.sync();
          const written = await ownerWriter.stat({bigint: true});
          const replacement = Object.fromEntries(['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].map(name =>
            [name, written[name as keyof MetadataIdentity]])) as MetadataIdentity;
          if (await Reflect.apply(ownerWriterClose, ownerWriter, []) === false) fail('PublicationStoreCleanupPending');
          ownerWriter = undefined;
          await ownership.assertCurrent(); currentLease.current();
          currentLease.replaceMetadata(`.lease-${token}.json`, ownerFileIdentity as MetadataIdentity, replacement,
            {dev: ownershipDevice!, ino: ownershipInode!}, () => {
            // Commit precedes any child-close or durability failure. Cleanup
            // owns this exact replacement without another rename/reissue.
            ownerFileIdentity = replacement;
            leaseStaging = leaseStagingIdentity = undefined;
          });
          const committed = await lstat(ownerPath, {bigint: true});
          if (committed.dev !== replacement.dev || committed.ino !== replacement.ino ||
              !committed.isFile() || committed.isSymbolicLink()) fail('PublicationStoreOwnershipLost');
          ownerFileIdentity = Object.fromEntries(['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].map(name =>
            [name, committed[name as keyof MetadataIdentity]])) as MetadataIdentity;
          await syncDirectoryPath(directoryPath); currentLease.current();
        },
        async assertCurrent() {
          if (!ownerWritten || ownerWriter !== undefined || released || ownerRemoved ||
              directoryRemoved || retirementDirectory !== undefined) {
            fail('PublicationStoreOwnershipLost');
          }
          const currentRoot = await lstat(root, {bigint: true});
          const directory = await lstat(directoryPath, {bigint: true});
          if (!currentRoot.isDirectory() || currentRoot.isSymbolicLink() ||
              currentRoot.dev !== rootDevice || currentRoot.ino !== rootInode ||
              !directory.isDirectory() || directory.isSymbolicLink()) fail('PublicationStoreOwnershipLost');
          const before = await lstat(ownerPath, {bigint: true});
          const sameFile = (state: BigIntStats) => state.isFile() && !state.isSymbolicLink() &&
            ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].every(name => state[name as keyof MetadataIdentity] === ownerFileIdentity?.[name as keyof MetadataIdentity]);
          if (!sameFile(before)) fail('PublicationStoreOwnershipLost');
          const existing = JSON.parse(await readBounded(ownerPath, 4096) as unknown as string) as OwnerRecord | null;
          if (!sameFile(await lstat(ownerPath, {bigint: true}))) fail('PublicationStoreOwnershipLost');
          if (existing?.token !== token || existing?.pid !== process.pid) fail('PublicationStoreOwnershipLost');
          if (ownershipDevice === undefined) {
            ownershipDevice = directory.dev;
            ownershipInode = directory.ino;
          } else if (directory.dev !== ownershipDevice || directory.ino !== ownershipInode) {
            fail('PublicationStoreOwnershipLost');
          }
        },
        async release() {
          if (released) return false;
          if (retirementReadCleanup !== undefined) {
            const child = retirementReadCleanup;
            const acknowledged = (state: unknown) => {
              const pending = state !== null && typeof state === 'object'
                ? Object.getOwnPropertyDescriptor(state, 'pending') : undefined;
              return pending !== undefined && Object.hasOwn(pending, 'value') && pending.value === false;
            };
            if (child.status === undefined || child.retry === undefined) throw retirementReadFailure;
            let state = await originalApply(child.status, child.handle, []);
            if (!acknowledged(state)) state = await originalApply(child.retry, child.handle, []);
            if (!acknowledged(state)) throw retirementReadFailure;
            retirementReadCleanup = retirementReadFailure = undefined;
          }
          // The opener owns this exact metadata writer even if writing or
          // closing failed before an ownership handle could be returned.
          if (ownerWriter !== undefined) {
            ownerWriterClose ??= ownerWriter.close;
            if (typeof ownerWriterClose !== 'function' ||
                await Reflect.apply(ownerWriterClose, ownerWriter, []) === false) {
              fail('PublicationStoreCleanupPending');
            }
            ownerWriter = undefined;
          }
          // This FD is already owned independently of the current pathname.
          // Drain it even if root has vanished or names a foreign directory;
          // successful FD close alone does not retire the Store or its key.
          if (retirementDirectory !== undefined) {
            if ((await retirementDirectory.close() as unknown) === false) fail('PublicationStoreCleanupPending');
            retirementDirectory = undefined;
          }
          let currentRoot;
          try { currentRoot = await lstat(root, {bigint: true}); }
          catch (error) { if ((error as OpeningCause)?.code === 'ENOENT') return false; throw error; }
          if (!currentRoot.isDirectory() || currentRoot.dev !== rootDevice ||
              currentRoot.ino !== rootInode) fail('PublicationStoreOwnershipLost');
          if (retirementSynced) {
            released = true;
            return true;
          }
          if (!directoryRemoved) {
            let directory;
            try { directory = await lstat(directoryPath, {bigint: true}); }
            catch (error) { if ((error as OpeningCause)?.code === 'ENOENT') return false; throw error; }
            if (!directory.isDirectory() || directory.isSymbolicLink()) {
              fail('PublicationStoreOwnershipLost');
            }
            if (!ownerRemoved) {
              if (ownerWritten) {
                const sameOwnerFile = (state: BigIntStats) => state.isFile() && !state.isSymbolicLink() &&
                  state.dev === ownerFileIdentity?.dev && state.ino === ownerFileIdentity?.ino;
                if (!sameOwnerFile(await lstat(ownerPath, {bigint: true}))) fail('PublicationStoreOwnershipLost');
                let existing: OwnerRecord | null;
                try { existing = JSON.parse(bootstrap === undefined
                  ? await readFile(ownerPath, 'utf8') : await readBounded(ownerPath, 4096) as unknown as string); }
                catch (error) {
                  const handle: unknown = error !== null && typeof error === 'object'
                    ? Object.getOwnPropertyDescriptor(error, 'cleanupHandle')?.value : undefined;
                  if (handle !== undefined) {
                    const status = Object.getOwnPropertyDescriptor(handle, 'status')?.value;
                    const retry = Object.getOwnPropertyDescriptor(handle, 'retry')?.value;
                    retirementReadCleanup = {handle,
                      status: typeof status === 'function' ? status as Close : undefined,
                      retry: typeof retry === 'function' ? retry as Close : undefined};
                    retirementReadFailure = error;
                    throw error;
                  }
                  if ((error as OpeningCause)?.code === 'ENOENT') return false;
                  throw error;
                }
                if (!sameOwnerFile(await lstat(ownerPath, {bigint: true})) ||
                    existing?.token !== token || existing?.pid !== process.pid) {
                  fail('PublicationStoreOwnershipLost');
                }
              } else if (ownerFileCreated) {
                // Incomplete bytes do not contain a readable token yet. Only
                // the exact file identity from our own writer may be removed.
                const state = await lstat(ownerPath, {bigint: true});
                if (ownerFileIdentity === undefined || !state.isFile() || state.isSymbolicLink() ||
                    state.dev !== ownerFileIdentity.dev || state.ino !== ownerFileIdentity.ino) {
                  fail('PublicationStoreOwnershipLost');
                }
              } else {
                try { await lstat(ownerPath); fail('PublicationStoreOwnershipLost'); }
                catch (cause) { if ((cause as OpeningCause)?.code !== 'ENOENT') throw cause; }
              }
            }
            if (ownershipDevice === undefined) {
              ownershipDevice = directory.dev;
              ownershipInode = directory.ino;
            } else if (directory.dev !== ownershipDevice || directory.ino !== ownershipInode) {
              fail('PublicationStoreOwnershipLost');
            }
            if (leaseStaging !== undefined) {
              const state = await lstat(leaseStaging, {bigint: true});
              if (!state.isFile() || state.isSymbolicLink() ||
                  state.dev !== leaseStagingIdentity?.dev || state.ino !== leaseStagingIdentity?.ino) {
                fail('PublicationStoreOwnershipLost');
              }
              await unlink(leaseStaging);
              leaseStaging = leaseStagingIdentity = undefined;
            }
            // Record only actually acknowledged phases in this original
            // handle. Never reconstruct an absent record or unlink again.
            if (!ownerRemoved) {
              if (ownerFileCreated) await unlink(ownerPath);
              ownerRemoved = true;
            }
            await rmdir(directoryPath);
            directoryRemoved = true;
          }
          // A successor may now own root/owner. It must never be inspected
          // or removed by this old handle's remaining durability retry.
          retirementDirectory = await open(root, constants.O_RDONLY);
          let syncFailure: unknown, syncFailed = false;
          try {
            const physical = await retirementDirectory.stat({bigint: true});
            if (!physical.isDirectory() || physical.dev !== rootDevice || physical.ino !== rootInode) {
              fail('PublicationStoreOwnershipLost');
            }
            await retirementDirectory.sync();
            retirementSynced = true;
          } catch (cause) { syncFailed = true; syncFailure = cause; }
          try {
            if ((await retirementDirectory.close() as unknown) === false) fail('PublicationStoreCleanupPending');
            retirementDirectory = undefined;
          } catch (closeFailure) {
            if (!syncFailed) throw closeFailure;
            const failure: PublicationStoreError & {primaryFailure?: unknown; cleanupError?: unknown} =
              new PublicationStoreError('PublicationStoreCleanupPending', syncFailure);
            failure.primaryFailure = syncFailure;
            failure.cleanupError = closeFailure;
            throw failure;
          }
          if (syncFailed) throw syncFailure;
          released = true;
          return true;
        },
      });
      try {
        const originalDirectory = await lstat(directoryPath, {bigint: true});
        if (!originalDirectory.isDirectory() || originalDirectory.isSymbolicLink()) fail('PublicationStoreOwnershipLost');
        ownershipDevice = originalDirectory.dev; ownershipInode = originalDirectory.ino;
        ownerWriter = await open(ownerPath, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
        ownerFileCreated = true;
        ownerWriterClose = ownerWriter.close;
        if (typeof ownerWriterClose !== 'function') fail('PublicationStoreCleanupPending');
        const physical = await ownerWriter.stat({bigint: true});
        ownerFileIdentity = {dev: physical.dev, ino: physical.ino};
        let offset = 0;
        while (offset < owner.byteLength) {
          const {bytesWritten} = await ownerWriter.write(owner, offset, owner.byteLength - offset, offset);
          if (bytesWritten === 0) fail('IncompletePublicationWrite');
          offset += bytesWritten;
        }
        await ownerWriter.sync();
        const written = await ownerWriter.stat({bigint: true});
        ownerFileIdentity = Object.fromEntries(
          ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].map(name => [name, written[name as keyof MetadataIdentity]])) as MetadataIdentity;
        if (await Reflect.apply(ownerWriterClose, ownerWriter, []) === false) fail('PublicationStoreCleanupPending');
        ownerWriter = undefined;
        ownerWritten = true;
        await syncDirectoryPath(directoryPath);
        if (staging) {
          lease!.publishDirectory(`.owner-opening-${token}`, {dev: ownershipDevice!, ino: ownershipInode!});
          directoryPath = ownershipDirectory; ownerPath = finalOwnerPath; staging = false;
        }
        await syncDirectoryPath(root);
        // A fresh preparer may still own another unpublished stage before
        // qualifying its kernel lease. Our lease proves no custody or stop
        // for that writer: only its original handle may retire its stage.
        return ownership;
      } catch (cause) {
        // The original token/release closure exists before either awaited
        // durability operation. Drain its failed FD before retiring ownership.
        throw await retainStoreOpeningFailure(cause, ownership, key);
      }
    } catch (error) {
      if ((error as OpeningCause)?.cleanupHandle !== undefined) throw error;
      if ((error as OpeningCause)?.code !== 'EEXIST') throw error;
      let existing: OwnerRecord | null;
      try { existing = JSON.parse(bootstrap === undefined
        ? await readFile(finalOwnerPath, 'utf8') : await bootstrap.readMetadata(finalOwnerPath) as unknown as string); }
      catch (readError) {
        if ((readError as OpeningCause)?.cleanupHandle !== undefined) throw readError;
        if ((readError as OpeningCause)?.code === 'ENOENT') {
          fail('PublicationStoreBusy');
        }
        fail('InvalidPublicationStoreOwner', readError);
      }
      if (existing?.version !== 'actql-local-publication-store-owner/0.1' ||
          typeof existing.token !== 'string' ||
          !Number.isSafeInteger(existing.pid) || (existing.pid as number) < 1) {
        fail('InvalidPublicationStoreOwner');
      }
      // New owners may be reclaimed only under the SAME stable lock. Legacy
      // metadata retains its prior conservative live-PID refusal, but cannot
      // supply a new execution-stop receipt.
      if (existing.leaseAnchor !== undefined) {
        if (lease === undefined) fail('PublicationStoreBusy');
        if (!lease.matches(existing.leaseAnchor)) fail('PublicationStoreLeaseChanged');
      } else if (await processIsAlive(existing.pid)) fail('PublicationStoreBusy');
      const stale = resolve(root, `stale-owner-${randomUUID()}`);
      try { await rename(ownershipDirectory, stale); }
      catch (renameError) {
        if ((renameError as OpeningCause)?.code === 'ENOENT') continue;
        throw renameError;
      }
      await removeOpeningTree(stale, bootstrap);
      await syncDirectoryPath(root);
    }
  }
}
