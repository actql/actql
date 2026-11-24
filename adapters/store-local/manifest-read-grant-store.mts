import {createHash} from 'node:crypto';
import {lstat, mkdir, readdir, unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {ActivePhysicalRecordWriter, createPhysicalHoldingRecordWriter} from './physical-holding-record-writer.mjs';
import type {createPublicationContractStore, PublicationContract} from './publication-contract-store.mjs';
import type {validateConfiguration} from './publication-store-inputs.mjs';
import {fail, PublicationStoreError, readBounded} from './publication-store-io.mjs';

type ManifestReadGrant = Readonly<{run_definition_cid: string; max_uses: number}>;
type StoreFailure = Readonly<{code?: unknown; cleanupHandle?: unknown}> | null | undefined;
type CleanupObservation = Readonly<{pending: boolean}>;
type PendingManifestReadFailure = PublicationStoreError & {
  primaryFailure: unknown;
  cleanupPending: boolean;
  cleanupHandle: ActivePhysicalRecordWriter['cleanup'];
};
type ManifestReadPorts<Contract extends PublicationContract> =
  Pick<ReturnType<typeof createPublicationContractStore<Contract>>,
    'admitContract' | 'parseContract' | 'putAdmittedPublicationContract'> & Readonly<{
    active(): unknown;
    cidHex(value: unknown): string;
    runMetadataDeletionStarted(cid: string): Promise<boolean>;
    syncDirectory(path: string): unknown;
    writePhysicalHoldingRecord: ReturnType<typeof createPhysicalHoldingRecordWriter>;
  }>;

export function createManifestReadGrantStore<Contract extends PublicationContract>(
  configuration: Pick<ReturnType<typeof validateConfiguration>, 'maxObjectBytes'>,
  manifestReadsDirectory: string,
  activePhysicalRecordWriters: Set<ActivePhysicalRecordWriter>,
  {active, cidHex, runMetadataDeletionStarted, syncDirectory, writePhysicalHoldingRecord,
    admitContract, parseContract, putAdmittedPublicationContract}: ManifestReadPorts<Contract>,
) {
  // One bounded durability observation, not a retained contract or Allow.
  // Each public confirmation still acquires and checks its selected record.
  let lastConfirmedManifestRead: string | undefined;
  let manifestReadAdmissionBusy: Promise<unknown> = Promise.resolve();
  const manifestReadGrantPath = (cid: string) =>
    resolve(manifestReadsDirectory, cidHex(cid));

  const consumeManifestReadGrant = (suppliedWire: unknown, attemptId: unknown) => {
    active();
    if (typeof attemptId !== 'string' || attemptId.length === 0 ||
        attemptId.length > 256) {
      fail('InvalidManifestReadAttempt');
    }
    const operation = manifestReadAdmissionBusy.then(async () => {
      for (const pending of activePhysicalRecordWriters) {
        if (pending.failed) fail('PublicationStoreCleanupPending');
      }
      const admitted = admitContract('manifest_read_grant', suppliedWire);
      const grant = parseContract(admitted) as ManifestReadGrant;
      if (await runMetadataDeletionStarted(grant.run_definition_cid)) {
        fail('PublicationMetadataDeleted');
      }
      await putAdmittedPublicationContract(admitted, grant);
      const writer: ActivePhysicalRecordWriter = {failed: false, cleanup: undefined};
      activePhysicalRecordWriters.add(writer);
      let retainedChild = false;
      try {
      const directory = manifestReadGrantPath(admitted.identity);
      let createdDirectory = false;
      try {
        await mkdir(directory, {mode: 0o700});
        createdDirectory = true;
      } catch (error) {
        if ((error as StoreFailure)?.code !== 'EEXIST') throw error;
        if (!(await lstat(directory)).isDirectory()) {
          fail('InvalidManifestReadStore');
        }
      }
      if (createdDirectory) await syncDirectory(manifestReadsDirectory);
      const attemptDigest = createHash('sha256')
        .update(attemptId, 'utf8').digest('hex');
      const target = resolve(directory, `${attemptDigest}.json`);
      const value = Object.freeze({
        manifestReadGrantCid: admitted.identity,
        attemptId,
      });
      const bytes = Buffer.from(JSON.stringify(value), 'utf8');
      try {
        const existing = await readBounded(
          target, configuration.maxObjectBytes,
        );
        if (!existing.equals(bytes)) fail('ManifestReadAttemptConflict');
        // Visibility after a lost sync reply is not durability. Only this
        // Store's real ACK of the same immutable target avoids another ACK.
        if (lastConfirmedManifestRead !== target) {
          await syncDirectory(directory);
          if (!(await readBounded(target, configuration.maxObjectBytes)).equals(bytes)) {
            fail('ManifestReadAttemptConflict');
          }
          lastConfirmedManifestRead = target;
        }
        return Object.freeze({grant, created: false, idempotent: true});
      } catch (error) {
        if ((error as StoreFailure)?.code !== 'ENOENT') throw error;
      }
      let uses = 0, recovered = false;
      for (const name of await readdir(directory)) {
        if (name.startsWith('.staging-')) {
          await unlink(resolve(directory, name));
          recovered = true;
        } else {
          if (!/^[0-9a-f]{64}\.json$/u.test(name) ||
              !(await lstat(resolve(directory, name))).isFile()) {
            fail('InvalidManifestReadStore');
          }
          uses++;
        }
      }
      if (recovered) await syncDirectory(directory);
      if (uses >= grant.max_uses) fail('ManifestReadGrantUseLimit');
      // Reuse the existing Store writer's FD/temporary/final-link custody.
      // Future writes leave no private per-grant staging traversal at open.
      await writePhysicalHoldingRecord(target, bytes, false, directory);
      lastConfirmedManifestRead = target;
      return Object.freeze({grant, created: true, idempotent: false});
      } catch (primary) {
        const child = (primary as StoreFailure)?.cleanupHandle as
          Readonly<{status?: unknown; retry?: unknown}> | undefined;
        if (child === undefined) throw primary;
        const childStatus = child.status, childRetry = child.retry;
        let pending = true;
        let flight: Promise<CleanupObservation> | undefined;
        const failure = new PublicationStoreError('PublicationStoreCleanupPending', primary) as PendingManifestReadFailure;
        failure.primaryFailure = primary;
        failure.cleanupPending = true;
        writer.failed = retainedChild = true;
        const status = () => Object.freeze({pending});
        writer.cleanup = Object.freeze({status, retry() {
          if (flight !== undefined) return flight;
          if (!pending) return Promise.resolve(status());
          flight = Promise.resolve().then(async () => {
            if (typeof childStatus !== 'function' || typeof childRetry !== 'function') {
              fail('PublicationStoreCleanupPending');
            }
            await Reflect.apply(childRetry, child, []);
            const observation = await Reflect.apply(childStatus, child, []);
            const descriptor = observation !== null && typeof observation === 'object'
              ? Object.getOwnPropertyDescriptor(observation, 'pending') : undefined;
            if (descriptor?.value !== false) fail('PublicationStoreCleanupPending');
            pending = false;
            activePhysicalRecordWriters.delete(writer);
            return status();
          }).finally(() => {failure.cleanupPending = pending; flight = undefined;});
          return flight;
        }});
        failure.cleanupHandle = writer.cleanup;
        throw failure;
      } finally {
        if (!retainedChild) activePhysicalRecordWriters.delete(writer);
      }
    });
    manifestReadAdmissionBusy = operation.catch(() => {});
    return operation;
  };

  return {consumeManifestReadGrant};
}
