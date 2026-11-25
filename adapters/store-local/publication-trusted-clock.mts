import {createHash, randomUUID} from 'node:crypto';
import {constants} from 'node:fs';
import type {BigIntStats} from 'node:fs';
import {lstat, open, rename, unlink} from 'node:fs/promises';
import type {FileHandle} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {ActivePhysicalRecordWriter} from './physical-holding-record-writer.mjs';
import type {PhysicalReadHandle, ReadCleanupStatus} from './publication-object-verifier.mjs';
import {exactKeys, fail, PublicationStoreError, readBounded, writeExclusive} from './publication-store-io.mjs';

type ClockObservation = Readonly<{clockContractCid: string; observedAt: string}>;
type ClockSnapshot = Readonly<{clockContractCid: string; state: BigIntStats; value: ClockObservation; checksummed: boolean}>;
type ClockHandle = Omit<FileHandle, 'close'> & Pick<PhysicalReadHandle, 'close'>;
type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type ClockFailure = PublicationStoreError & {
  primaryFailure: unknown;
  cleanupPending: true;
  cleanupHandle: NonNullable<ActivePhysicalRecordWriter['cleanup']>;
};

export function createPublicationTrustedClock(
  configuration: Readonly<{maxObjectBytes: number}>,
  clocksDirectory: string,
  contractControl: Readonly<{trustedClockNotBefore(previous: string | undefined, observedAt: unknown): unknown}>,
  activePhysicalRecordWriters: Set<ActivePhysicalRecordWriter>,
  active: () => unknown,
  cidHex: (value: unknown) => string,
  syncDirectory: (path: string) => unknown,
) {
  const durablyConfirmedClocks = new Map<string, string>();
  const durablyConfirmedClockFiles = new Map<string, BigIntStats>();
  let clockObservationBusy: Promise<unknown> = Promise.resolve();
  let clockObservationsPending = 0;
  const clockObservationPath = (cid: string) =>
    resolve(clocksDirectory, `${cidHex(cid)}.json`);

  // One bounded metadata snapshot. A cache hit still checks the physical file;
  // inode, size and both timestamps prevent reuse after replacement or mutation.
  let lastClockObservation: ClockSnapshot | undefined;
  const sameClockFile = (left: Partial<BigIntStats>, right: BigIntStats) => (['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'] as const)
    .every(field => left[field] === right[field]);
  const readClockSnapshot = async (clockContractCid: string) => {
    const path = clockObservationPath(clockContractCid);
    let before;
    try {
      before = await lstat(path, {bigint: true});
    } catch (error) {
      if ((error as CodedCause)?.code === 'ENOENT') return undefined;
      throw error;
    }
    if (!before.isFile() || before.size > BigInt(configuration.maxObjectBytes)) {
      fail('InvalidPublicationStoreObject');
    }
    if (lastClockObservation?.clockContractCid === clockContractCid &&
        sameClockFile(lastClockObservation.state, before)) {
      return lastClockObservation;
    }
    // Keep this original metadata size as the receive ceiling, not merely the
    // Store-wide limit. Growth cannot allocate a larger readFile buffer before
    // the clock/cache mutation check below observes it.
    const bytes = await readBounded(path, Number(before.size));
    const after = await lstat(path, {bigint: true});
    if (!sameClockFile(before, after)) fail('PublicationClockUncertain');
    let value: Readonly<{clockContractCid?: unknown; observedAt?: unknown; contentSha256?: unknown}>;
    try { value = JSON.parse(bytes.toString('utf8')) as typeof value; }
    catch (error) { fail('InvalidPublicationClockObservation', error); }
    const checksummed = exactKeys(value, ['clockContractCid', 'observedAt', 'contentSha256']);
    if ((!checksummed && !exactKeys(value, ['clockContractCid', 'observedAt'])) ||
        value.clockContractCid !== clockContractCid ||
        typeof value.observedAt !== 'string' ||
        contractControl.trustedClockNotBefore(
          undefined, value.observedAt,
        ) !== true) {
      fail('InvalidPublicationClockObservation');
    }
    const observation = Object.freeze({clockContractCid, observedAt: value.observedAt});
    if (checksummed && (value as {contentSha256: unknown}).contentSha256 !== createHash('sha256')
      .update(JSON.stringify(observation), 'utf8').digest('hex')) {
      fail('InvalidPublicationClockObservation');
    }
    lastClockObservation = {clockContractCid, state: after, value: observation, checksummed};
    return lastClockObservation;
  };
  const readClockObservation = async (clockContractCid: string) =>
    (await readClockSnapshot(clockContractCid))?.value;

  // A confirmed directory entry needs no new directory commit when neither
  // name nor inode changes. Flush every new value on that SAME file instead.
  // Its checksum detects interrupted fixed-length writes; a torn record is
  // unavailable, never an excuse to recover an older floor or create a clock.
  const flushClockFile = async (clockContractCid: string, snapshot: ClockSnapshot, bytes?: Buffer) => {
    const writer: ActivePhysicalRecordWriter = {cleanup: undefined, failed: false};
    let handle: ClockHandle | undefined;
    let closeOriginal: ClockHandle['close'] | undefined;
    let flight: Promise<ReadCleanupStatus> | undefined;
    const status = () => Object.freeze({pending: handle !== undefined});
    const cleanup = Object.freeze({status, retry() {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(async () => {
        if (handle !== undefined) {
          if (await Reflect.apply(closeOriginal!, handle, []) === false) {
            fail('PublicationStoreCleanupPending');
          }
          handle = undefined;
          closeOriginal = undefined;
        }
        activePhysicalRecordWriters.delete(writer);
        return status();
      }).finally(() => { flight = undefined; });
      return flight;
    }});
    activePhysicalRecordWriters.add(writer);
    try {
      handle = await open(clockObservationPath(clockContractCid),
        constants.O_RDWR | constants.O_NOFOLLOW);
      closeOriginal = handle.close;
      const before = await handle.stat({bigint: true});
      if (!before.isFile() || !sameClockFile(before, snapshot.state) ||
          bytes !== undefined && BigInt(bytes.byteLength) !== before.size) {
        fail('PublicationClockUncertain');
      }
      if (bytes !== undefined) {
        let offset = 0;
        while (offset < bytes.byteLength) {
          const {bytesWritten} = await handle.write(bytes, offset,
            bytes.byteLength - offset, offset);
          if (!Number.isSafeInteger(bytesWritten) || bytesWritten <= 0 ||
              bytesWritten > bytes.byteLength - offset) fail('IncompletePublicationWrite');
          offset += bytesWritten;
        }
      }
      await handle.sync();
      const written = bytes === undefined ? undefined : await handle.stat({bigint: true});
      if (written !== undefined && (!written.isFile() || written.dev !== before.dev || written.ino !== before.ino ||
          written.size !== before.size)) fail('PublicationClockUncertain');
      await cleanup.retry();
      if (written === undefined) return;
      const current = await lstat(clockObservationPath(clockContractCid), {bigint: true});
      if (!current.isFile() || !sameClockFile(written,current)) fail('PublicationClockUncertain');
      return current;
    } catch (primary) {
      writer.failed = true;
      writer.cleanup = cleanup;
      try { await cleanup.retry(); } catch {}
      if (!status().pending) throw primary;
      const failure = new PublicationStoreError('PublicationStoreCleanupPending', primary) as ClockFailure;
      failure.primaryFailure = primary;
      failure.cleanupPending = true;
      failure.cleanupHandle = cleanup;
      throw failure;
    }
  };

  const updateTrustedClock = (clockContractCid: string, suppliedAt: unknown, sample?: () => unknown) => {
    active();
    cidHex(clockContractCid);
    if (sample === undefined && (typeof suppliedAt !== 'string' ||
        contractControl.trustedClockNotBefore(
          undefined, suppliedAt,
        ) !== true)) {
      fail('InvalidPublicationClockObservation');
    }
    clockObservationsPending++;
    const operation = clockObservationBusy.then(async () => {
      for (const writer of activePhysicalRecordWriters) {
        if (writer.failed) fail('PublicationStoreCleanupPending');
      }
      const confirmed = durablyConfirmedClocks.get(clockContractCid);
      const snapshot = await readClockSnapshot(clockContractCid);
      const previous = snapshot?.value;
      // The same queue reads the latest original floor BEFORE sampling. A
      // concurrent accepted observation cannot make an earlier caller sample
      // into a false rollback. A returned sample still owns the full commit.
      const observedAt = sample === undefined ? suppliedAt as string : sample() as string;
      if (sample !== undefined && (typeof observedAt !== 'string' ||
          contractControl.trustedClockNotBefore(undefined, observedAt) !== true)) {
        fail('InvalidPublicationClockObservation');
      }
      const confirmedFile = durablyConfirmedClockFiles.get(clockContractCid);
      const sameConfirmedInode = confirmedFile !== undefined && snapshot !== undefined &&
        (['dev', 'ino', 'size'] as const).every(field => confirmedFile[field] === snapshot.state[field]);
      // A known durable floor cannot disappear or move backwards while this
      // owner is live. Missing history is not a fresh clock admission.
      if (confirmed !== undefined && (previous === undefined ||
          !contractControl.trustedClockNotBefore(confirmed, previous.observedAt))) {
        fail('PublicationClockUncertain');
      }
      if (contractControl.trustedClockNotBefore(
        previous?.observedAt, observedAt,
      ) !== true) {
        fail('PublicationClockUncertain');
      }
      if (previous?.observedAt === observedAt) {
        if (confirmed !== observedAt || !sameClockFile(confirmedFile ?? {}, snapshot!.state)) {
          if (snapshot!.checksummed) await flushClockFile(clockContractCid, snapshot!);
          if (!sameConfirmedInode) await syncDirectory(clocksDirectory);
          const current = await readClockSnapshot(clockContractCid);
          if (current?.value.observedAt !== observedAt ||
              !(['dev', 'ino', 'size'] as const).every(field =>
                current.state[field] === snapshot!.state[field])) {
            fail('PublicationClockUncertain');
          }
          durablyConfirmedClocks.set(clockContractCid, observedAt);
          durablyConfirmedClockFiles.set(clockContractCid, current.state);
        }
        return previous!;
      }
      const value = Object.freeze({clockContractCid, observedAt});
      const plain = JSON.stringify(value);
      const checked = Buffer.from(JSON.stringify({...value,
        contentSha256: createHash('sha256').update(plain, 'utf8').digest('hex')}), 'utf8');
      // Preserve small legacy Store configurations rather than imposing a new
      // limit. They retain the original atomic replacement protocol.
      const bytes = checked.byteLength <= configuration.maxObjectBytes
        ? checked : Buffer.from(plain, 'utf8');
      if (bytes.byteLength > configuration.maxObjectBytes) {
        fail('PublicationObjectLimit');
      }
      if (snapshot?.checksummed && sameConfirmedInode &&
          snapshot.state.size === BigInt(bytes.byteLength)) {
        const state = (await flushClockFile(clockContractCid, snapshot, bytes))!;
        // This same original FD wrote the already typed value and really
        // synced/closed it. Trusted internal I/O is not another wire input.
        // Keep its physical version so the next operation still detects any
        // intervening change and reads/adopts that new original normally.
        lastClockObservation = {clockContractCid,state,value,checksummed:true};
        durablyConfirmedClocks.set(clockContractCid, observedAt);
        durablyConfirmedClockFiles.set(clockContractCid, state);
        return value;
      }
      const staging = resolve(clocksDirectory, `.staging-${randomUUID()}`);
      try {
        await writeExclusive(staging, bytes);
        await rename(staging, clockObservationPath(clockContractCid));
        await syncDirectory(clocksDirectory);
      } catch (error) {
        try { await unlink(staging); }
        catch (cleanupError) {
          if ((cleanupError as CodedCause)?.code !== 'ENOENT') throw cleanupError;
        }
        throw error;
      }
      const current = await readClockSnapshot(clockContractCid);
      if (current?.value.observedAt !== observedAt) {
        fail('PublicationClockUncertain');
      }
      durablyConfirmedClocks.set(clockContractCid, observedAt);
      durablyConfirmedClockFiles.set(clockContractCid, current.state);
      return current.value;
    });
    clockObservationBusy = operation.catch(() => {});
    return operation.finally(() => { clockObservationsPending--; });
  };
  const observeTrustedClock = (clockContractCid: string, observedAt: unknown) =>
    updateTrustedClock(clockContractCid, observedAt);
  const sampleTrustedClock = (clockContractCid: string, sample: () => unknown) => {
    if (typeof sample !== 'function') fail('InvalidPublicationClockObservation');
    return updateTrustedClock(clockContractCid, undefined, sample)
      .then(observation => observation.observedAt);
  };

  return {observeTrustedClock, sampleTrustedClock, readClockObservation,
    get clockObservationsPending() { return clockObservationsPending; }};
}
