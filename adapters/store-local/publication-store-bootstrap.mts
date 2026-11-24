import type {Dir, Dirent} from 'node:fs';
import {lstat, opendir, rm, rmdir, unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import {Buffer as OriginalBuffer} from 'node:buffer';
import {assertHostJournalDirectoryInspector, inspectHostJournalDirectory}
  from '../host-node/host-journal-directory.mjs';
import type {createPublicationCustodyRecords} from './publication-custody-records.mjs';
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

type OpeningNamespaces = Readonly<{
  stagingDirectory: string;
  custodyDirectory: string;
  preparedSchemasDirectory: string;
  metadataDeletionsDirectory: string;
  physicalHoldingDeletionsDirectory: string;
  clocksDirectory: string;
}>;

export async function readOpeningStoreInventory(
  {stagingDirectory, custodyDirectory, preparedSchemasDirectory, metadataDeletionsDirectory,
    physicalHoldingDeletionsDirectory, clocksDirectory}: OpeningNamespaces,
  custodyNamePattern: RegExp,
  readOpeningDirectory: (path: string) => Promise<readonly string[]>,
  syncDirectory: (path: string) => unknown,
) {
  let removedStaging = false;
  for (const name of await readOpeningDirectory(stagingDirectory)) {
    const path = resolve(stagingDirectory, name);
    if (!/^object-[0-9a-f-]{36}$/u.test(name) ||
        !(await lstat(path)).isFile()) {
      fail('InvalidPublicationStagingObject');
    }
    await unlink(path);
    removedStaging = true;
  }
  if (removedStaging) await syncDirectory(stagingDirectory);

  for (const name of await readOpeningDirectory(custodyDirectory)) {
    const path = resolve(custodyDirectory, name);
    if (!custodyNamePattern.test(name) || !(await lstat(path)).isFile()) {
      fail('InvalidPublicationPreparedCustody');
    }
  }
  // Opening only observes these names. The selected custody recovery below
  // owns any actual unlink and its acknowledgement.
  let removedSchemaStaging = false;
  for (const name of await readOpeningDirectory(preparedSchemasDirectory)) {
    const path = resolve(preparedSchemasDirectory, name);
    if (/^\.staging-[0-9a-f-]{36}\.json$/u.test(name)) {
      await unlink(path);
      removedSchemaStaging = true;
      continue;
    }
    if (!custodyNamePattern.test(name) || !(await lstat(path)).isFile()) {
      fail('InvalidPublicationPreparedSchema');
    }
  }
  if (removedSchemaStaging) await syncDirectory(preparedSchemasDirectory);

  // Delivery coverage and pending recovery below own the selected entries.
  // Ordinary opens must not enumerate every historical delivery directory.
  // Manifest use admission and legacy staging recovery belong to the selected
  // grant. Committed grants are not another all-history opening inventory.
  const openingMetadataDeletionNames: string[] = [];
  let removedMetadataStaging = false;
  for (const name of await readOpeningDirectory(metadataDeletionsDirectory)) {
    const path = resolve(metadataDeletionsDirectory, name);
    if (name.startsWith('.staging-')) {
      await unlink(path);
      removedMetadataStaging = true;
      continue;
    }
    if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
        !(await lstat(resolve(metadataDeletionsDirectory, name))).isFile()) {
      fail('InvalidPublicationMetadataDeletionStore');
    }
    openingMetadataDeletionNames.push(name);
  }
  if (removedMetadataStaging) await syncDirectory(metadataDeletionsDirectory);
  // Immutable holdings are checked through their selected original FD, not
  // by enumerating all committed names at every open. Pending deletion
  // records still require bounded opening admission and actual recovery.
  for (const name of await readOpeningDirectory(physicalHoldingDeletionsDirectory)) {
    if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
        !(await lstat(resolve(physicalHoldingDeletionsDirectory, name))).isFile()) {
      fail('InvalidPublicationPhysicalHoldingStore');
    }
  }
  // Each selected extension reader owns its directory types, complete chain
  // and actual Result-directory ACK. Unrelated committed histories are not
  // another ordinary opening admission or durability transition.
  // Result deletion recovery owns its bounded names only after the native
  // lifecycle reports unfinished or legacy cleanup, not on every clean open.
  let removedClockStaging = false;
  for (const name of await readOpeningDirectory(clocksDirectory)) {
    const path = resolve(clocksDirectory, name);
    if (name.startsWith('.staging-')) {
      await rm(path, {force: false});
      removedClockStaging = true;
      continue;
    }
    // The selected clock reader owns its actual file/type/checksum admission.
    // Opening retains only name admission and legacy staging cleanup here.
    if (!/^[0-9a-f]{64}\.json$/u.test(name)) {
      fail('InvalidPublicationClockObservation');
    }
  }
  if (removedClockStaging) await syncDirectory(clocksDirectory);
  return openingMetadataDeletionNames;
}

type ReclaimNativePreparation = ReturnType<typeof createPublicationCustodyRecords>['reclaimNativePreparation'];
type RecoverStorePorts = Readonly<{
  initializeDeliveryIndex(): Promise<void>;
  currentDeliveryIndex(): Readonly<{pendingPhysicalObjects(): readonly Parameters<ReclaimNativePreparation>[0][]}> | undefined;
  reclaimNativePreparation: ReclaimNativePreparation;
  recoverPreparedCustodies(): Promise<unknown>;
  recoverPreparedSchemas(): Promise<unknown>;
  recoverPhysicalHoldingDeletions(): Promise<unknown>;
  recoverUncommittedPublications(): Promise<unknown>;
  recoverRetiredResults(): Promise<unknown>;
  recoverRetiredMetadata(): Promise<unknown>;
}>;

export async function recoverPublicationStoreOnOpen(
  configuration: Readonly<{capacityBytes: number; maxObjects: number}>,
  capacityUsage: Readonly<{storedBytes: number; objectCount: number}>,
  {initializeDeliveryIndex, currentDeliveryIndex, reclaimNativePreparation, recoverPreparedCustodies,
    recoverPreparedSchemas, recoverPhysicalHoldingDeletions, recoverUncommittedPublications, recoverRetiredResults,
    recoverRetiredMetadata}: RecoverStorePorts,
) {
  // Immutable holding bodies are admitted at their selected read. Pending
  // deletion recovery below still owns its exact records and original ACKs;
  // unrelated history is not another ordinary opening admission boundary.
  // Recover process-crash custody before accepting new Store work. A
  // committed or shared allocation survives; an unpublished allocation is
  // reclaimed using its exact recorded generation.
  // Native publication bodies and their persisted capacity are available to
  // the same targeted recovery/retirement paths as legacy file originals.
  await initializeDeliveryIndex();
  const physicalPreparations = currentDeliveryIndex()!.pendingPhysicalObjects();
  for (const original of physicalPreparations) await reclaimNativePreparation(original);
  if(capacityUsage.storedBytes>configuration.capacityBytes||capacityUsage.objectCount>configuration.maxObjects) {
    fail('PublicationStoreCapacity');
  }
  await recoverPreparedCustodies();
  await recoverPreparedSchemas();
  // A crash between semantic alias creation and physical-custody handoff
  // leaves both records. Revisit physical custody after alias reclamation.
  await recoverPreparedCustodies();

  // A retiring Transfer holding is unavailable before physical reclamation.
  // Recovery resumes the exact durable cleanup without treating an absent
  // object name as proof that another live holding was released.
  await recoverPhysicalHoldingDeletions();

  // A terminal attempt that never won the public index retains an exact
  // inventory until every unshared metadata allocation is durably reclaimed.
  // Live and outcome-unknown attempts remain available for legal retry.
  await recoverUncommittedPublications();

  // Reconcile durable deletion markers before accepting new Store work. A
  // failed physical cleanup remains owned by the returned Store and can be
  // retried without making the deleted Result visible again.
  await recoverRetiredResults();

  // Metadata deletion markers hide the public index before physical cleanup.
  // Restart resumes every exact contract and payload responsibility recorded
  // by the marker rather than treating an absent index as successful cleanup.
  await recoverRetiredMetadata();
}
