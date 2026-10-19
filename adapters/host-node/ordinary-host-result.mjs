import {join} from 'node:path';
import {ordinaryHostJournalInstallation} from './ordinary-host-journal.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';

// Ordinary resource acquisition in the existing Result/Store responsibility.
// Same-Host identities and typed control remain, but a trusted in-process
// constructor does not need a whole-runtime/preload provenance certificate.
export function prepareOrdinaryHostResult(originals, subject, requirements) {
  const journal = ordinaryHostJournalInstallation(originals);
  let closing = false, closed = false, attempted = false, store, storeClose;
  let openFlight, closeFlight, cleanup, cleanupStatus, cleanupRetry, failure;
  let operations = 0;
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
      }
      if (store !== undefined) {
        storeClose ??= store.close;
        if (typeof storeClose !== 'function') return status();
        await Reflect.apply(storeClose, store, []);
        if (!store.status().closed) return status();
      }
      store = storeClose = failure = cleanup = cleanupStatus = cleanupRetry = undefined;
      subject = requirements = undefined; closed = true;
      return status();
    });
    closeFlight = flight;
    try {return await flight;} finally {if (closeFlight === flight) closeFlight = undefined;}
  }
  return Object.freeze({assertCurrent: current, close,
    beforeOperation() {
      current();
      if (operations === 4096) throw new TypeError('HostResultOperationLimit');
      operations++;
    },
    admitRun(prepared) {
      current();
      const value = requirements(originals, prepared);
      if (!Number.isSafeInteger(value.resultCount) || value.resultCount < 1 || value.resultCount > 10 ||
          !Number.isSafeInteger(value.maxRows) || value.maxRows < 0 || value.maxRows > 10000) {
        throw new TypeError('HostResultPublicationUnsupported');
      }
      current();
    },
    openStore(options, control) {
      current();
      if (openFlight !== undefined) return openFlight;
      if (attempted || control !== subject.control || options.directory !== join(subject.root, 'publication') ||
          options.storeAuthorityCid !== subject.storeAuthorityCid || options.privateEvidenceKey !== undefined) {
        throw new TypeError('ForeignInstalledHostPublicationStore');
      }
      attempted = true;
      const originalOwnership = journal.publicationOwnership();
      const flight = Promise.resolve().then(async () => {
        try {
          current();
          store = await openLocalPublicationStore(options, control, undefined, undefined,
            originalOwnership, current);
          storeClose = store.close;
          if (typeof storeClose !== 'function') throw new TypeError('HostResultPublicationCleanupPending');
          current(); return store;
        } catch (cause) {
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
}
