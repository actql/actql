import {join} from 'node:path';
import {ordinaryHostJournalInstallation} from './ordinary-host-journal.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {preparePrivateEvidenceKeyInstallation} from './local-continuation-evidence.mjs';

// Ordinary resource acquisition in the existing Result/Store responsibility.
// Same-Host identities and typed control remain, but a trusted in-process
// constructor does not need a whole-runtime/preload provenance certificate.
export function prepareOrdinaryHostResult(originals, subject, requirements) {
  const journal = ordinaryHostJournalInstallation(originals);
  let closing = false, closed = false, attempted = false, store, storeClose;
  let openFlight, closeFlight, cleanup, cleanupStatus, cleanupRetry, failure;
  let keyInstallation;
  let contentEvidenceStore;
  let keyOperationPending = false;
  const keyDuty = Object.freeze({status: () => Object.freeze({pending: keyOperationPending})});
  let keyDutyRetained = false;
  let operations = 0;
  let admittedRuns = new WeakMap();
  const current = () => {
    if (closing || closed) throw Object.assign(new Error('HostResultPublicationUnavailable'),
      {code: 'HostResultPublicationUnavailable'});
    journal.assertCurrent();
  };
  const ack = value => {
    const field = value !== null && typeof value === 'object'
      ? Object.getOwnPropertyDescriptor(value, 'pending') : undefined;
    return field !== undefined && Object.hasOwn(field, 'value') && field.value === false;
  };
  const status = () => Object.freeze({pending: !closed, storePending: store !== undefined && !store.status().closed,
    constructorCleanupPending: cleanup !== undefined || failure?.cleanupPending === true});
  async function close() {
    if (closed) return status();
    if (closeFlight !== undefined) return closeFlight;
    closing = true;
    const flight = Promise.resolve().then(async () => {
      if (openFlight !== undefined) {try {await openFlight;} catch {}}
      if (failure !== undefined && cleanup === undefined) {
        cleanup = failure.cleanupHandle;
        if (cleanup !== undefined) {cleanupStatus = cleanup.status; cleanupRetry = cleanup.retry;}
        else if (failure.cleanupPending === true) return status();
      }
      if (cleanup !== undefined) {
        if (typeof cleanupStatus !== 'function' || typeof cleanupRetry !== 'function') return status();
        if (!ack(Reflect.apply(cleanupStatus, cleanup, []))) await Reflect.apply(cleanupRetry, cleanup, []);
        if (!ack(Reflect.apply(cleanupStatus, cleanup, []))) return status();
        cleanup = cleanupStatus = cleanupRetry = failure = undefined;
        keyOperationPending = false;
      }
      if (store !== undefined) {
        storeClose ??= store.close;
        if (typeof storeClose !== 'function') return status();
        await Reflect.apply(storeClose, store, []);
        if (!store.status().closed) return status();
      }
      store = storeClose = failure = cleanup = cleanupStatus = cleanupRetry = undefined;
      contentEvidenceStore = undefined;
      keyInstallation?.key.fill(0); keyInstallation = undefined;
      admittedRuns = new WeakMap();
      subject = requirements = undefined; closed = true;
      return status();
    });
    closeFlight = flight;
    try {return await flight;} finally {if (closeFlight === flight) closeFlight = undefined;}
  }
  const view = Object.freeze({assertCurrent: current, close,
    assertContentCurrent() {
      if (this !== view) throw new TypeError('ForeignInstalledHostPublicationStore');
      current();
      if (store === undefined || store !== contentEvidenceStore || store.status().closed) {
        throw new TypeError('InstalledContentEvidenceUnavailable');
      }
    },
    beforeOperation() {
      current();
      if (operations === 4096) throw new TypeError('HostResultOperationLimit');
      operations++;
    },
    admitRun(prepared) {
      current();
      const value = requirements(originals, prepared);
      if (!Number.isSafeInteger(value.resultCount) || value.resultCount < 1 || value.resultCount > 10 ||
          !Number.isSafeInteger(value.maxRows) || value.maxRows < 0 || value.maxRows > 10000 ||
          !Number.isSafeInteger(value.maxContractBytes) || value.maxContractBytes < 1 ||
          value.maxContractBytes > 2147483647) {
        throw new TypeError('HostResultPublicationUnsupported');
      }
      current();
      const prior = admittedRuns.get(prepared);
      if (prior !== undefined) {
        if (prior.resultCount !== value.resultCount || prior.maxRows !== value.maxRows ||
            prior.maxContractBytes !== value.maxContractBytes) {
          throw new TypeError('HostResultPublicationChanged');
        }
        return;
      }
      // Existing Contract/evidence document ceilings select finite managed
      // publication allowances. They are not physical allocation coefficients,
      // reserved RAM or permission; Core still reserves the actual same Model
      // and Run, and ordinary Store/native cleanup retains its own duties.
      admittedRuns.set(prepared, Object.freeze({...value, capacity: Object.freeze({
        retainedBytes: BigInt(value.maxContractBytes), workspaceBytes: BigInt(value.maxContractBytes),
      })}));
    },
    modelPublicationCapacity(prepared) {
      if (this !== view) throw new TypeError('ForeignInstalledHostPublicationStore');
      current();
      const admitted = admittedRuns.get(prepared);
      if (admitted === undefined || store === undefined || store.status().closed) {
        throw new TypeError('HostResultPublicationRunUnavailable');
      }
      return admitted.capacity;
    },
    openStore(options, control) {
      current();
      if (openFlight !== undefined) return openFlight;
      if (attempted || control !== subject.control || options.directory !== join(subject.root, 'publication') ||
          options.storeAuthorityCid !== subject.storeAuthorityCid ||
          options.privateEvidenceKey !== subject.privateEvidenceKey) {
        throw new TypeError('ForeignInstalledHostPublicationStore');
      }
      attempted = true;
      const originalOwnership = journal.publicationOwnership();
      const flight = Promise.resolve().then(async () => {
        try {
          current();
          if (subject.privateEvidenceKey === undefined) {
            if (!keyDutyRetained) {
              journal.retainPrivateEvidenceInitialization(keyDuty); keyDutyRetained = true;
            }
            keyOperationPending = true;
            keyInstallation = await preparePrivateEvidenceKeyInstallation(join(subject.root, 'checkpoints'), {
              storeDirectory: options.directory, storeAuthorityCid: subject.storeAuthorityCid,
              preparedOwnership: originalOwnership,
              assertCurrent: () => {current(); journal.assertInitializationCurrent();},
            });
            keyOperationPending = false;
          }
          current();
          store = await openLocalPublicationStore({...options,
            privateEvidenceKey: subject.privateEvidenceKey ?? keyInstallation?.key}, control, undefined, undefined,
            originalOwnership, current);
          storeClose = store.close;
          if (typeof storeClose !== 'function') throw new TypeError('HostResultPublicationCleanupPending');
          if (keyInstallation !== undefined) {
            keyOperationPending = true;
            await keyInstallation.adoptStore(store);
            keyOperationPending = false;
          }
          if (subject.privateEvidenceKey !== undefined || keyInstallation !== undefined) {
            contentEvidenceStore = store;
          }
          keyInstallation?.key.fill(0);
          current(); return store;
        } catch (cause) {
          if (cause?.cleanupHandle === undefined && cause?.cleanupPending !== true) keyOperationPending = false;
          failure = cause;
          const error = Object.assign(new Error('HostResultPublicationCleanupPending', {cause}),
            {code: 'HostResultPublicationCleanupPending', cleanupPending: true});
          error.cleanupHandle = Object.freeze({status, retry: close});
          throw error;
        }
      });
      openFlight = flight; return flight;
    },
  });
  return view;
}
