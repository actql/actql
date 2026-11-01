import {validOriginalResultPublicationExtent} from './host-result-service-recipe.cjs';
import {join} from 'node:path';
import {ordinaryHostJournalInstallation} from './ordinary-host-journal.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {preparePrivateEvidenceKeyInstallation} from './local-continuation-evidence.mjs';

// Ordinary resource acquisition in the existing Result/Store responsibility.
// Same-Host identities and typed control remain, but a trusted in-process
// constructor does not need a whole-runtime/preload provenance certificate.
export function prepareOrdinaryHostResult(originals, subject, requirements, effectRequirements) {
  const journal = ordinaryHostJournalInstallation(originals);
  let closing = false, closed = false, attempted = false, store, storeClose;
  let openFlight, keyFlight, closeFlight, cleanup, cleanupStatus, cleanupRetry, failure;
  let keyInstallation;
  let contentEvidenceStore;
  let keyOperationPending = false;
  const keyDuty = Object.freeze({status: () => Object.freeze({pending: keyOperationPending})});
  let keyDutyRetained = false;
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
      if (keyFlight !== undefined) {try {await keyFlight;} catch {}}
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
      subject = requirements = effectRequirements = undefined; closed = true;
      return status();
    });
    closeFlight = flight;
    try {return await flight;} finally {if (closeFlight === flight) closeFlight = undefined;}
  }
  function retainFailure(cause) {
    if (cause?.cleanupHandle === undefined && cause?.cleanupPending !== true) keyOperationPending = false;
    // Keep the acquired child's original carrier, not this view's wrapper;
    // otherwise its cleanup would recursively wait for itself.
    failure ??= cause;
    const error = Object.assign(new Error('HostResultPublicationCleanupPending', {cause}),
      {code: 'HostResultPublicationCleanupPending', cleanupPending: true});
    error.cleanupHandle = Object.freeze({status, retry: close});
    return error;
  }
  function initializeKey() {
    if (keyFlight !== undefined) return keyFlight;
    keyFlight = Promise.resolve().then(async () => {
      try {
        current();
        if (subject.privateEvidenceKey !== undefined) return;
        const originalOwnership = journal.privateEvidenceInitializationOwnership();
        if (!keyDutyRetained) {
          journal.retainPrivateEvidenceInitialization(keyDuty); keyDutyRetained = true;
        }
        keyOperationPending = true;
        keyInstallation = await preparePrivateEvidenceKeyInstallation(join(subject.root, 'checkpoints'), {
          storeDirectory: join(subject.root, 'publication'), storeAuthorityCid: subject.storeAuthorityCid,
          preparedOwnership: originalOwnership,
          assertCurrent: () => {current(); journal.assertInitializationCurrent();},
          assertFirstInitialization: () => journal.assertPrivateEvidenceFirstInitialization(),
        });
        keyOperationPending = false;
        current();
      } catch (cause) {
        if (cause?.cleanupHandle === undefined && cause?.cleanupPending !== true) keyOperationPending = false;
        failure ??= cause;
        throw cause;
      }
    });
    return keyFlight;
  }
  function admitSelectedRun(prepared, value, kind) {
    // A terminal Effect may publish no Named Result. Its own publication
    // purpose still owns the checked command outcome; Pure requires a Result.
    const minimumResults = kind === 'effect' ? 0 : 1;
    // Both fixed requirement callbacks read the original nominal checked
    // Program inventory under the pending request's custody. Do not impose
    // a second structural Result-count cap here; Store bytes/objects remain
    // independently admitted before publication.
    // The fixed requirements callback already reads the checked original's
    // extent under its live request. Publication eligibility must not replace
    // that extent with the independent all() collection limit.
    if (!validOriginalResultPublicationExtent(value.resultCount, value.maxRows,
        value.maxContractBytes, minimumResults)) {
      throw new TypeError('HostResultPublicationUnsupported');
    }
    current();
    const prior = admittedRuns.get(prepared);
    if (prior !== undefined) {
      if (prior.kind !== kind || prior.resultCount !== value.resultCount || prior.maxRows !== value.maxRows ||
          prior.maxContractBytes !== value.maxContractBytes) {
        throw new TypeError('HostResultPublicationChanged');
      }
      return;
    }
    // Existing managed publication limits, not physical allocation or target
    // File IO credit. Those actual platform children retain their own duties.
    admittedRuns.set(prepared, Object.freeze({...value, kind, capacity: Object.freeze({
      retainedBytes: BigInt(value.maxContractBytes), workspaceBytes: BigInt(value.maxContractBytes),
    })}));
  }
  const view = Object.freeze({assertCurrent: current, close,
    initialize() {
      if (this !== view) throw new TypeError('ForeignInstalledHostPublicationStore');
      current();
      return initializeKey().catch(cause => {throw retainFailure(cause);});
    },
    assertContentCurrent() {
      if (this !== view) throw new TypeError('ForeignInstalledHostPublicationStore');
      current();
      if (store === undefined || store !== contentEvidenceStore || store.status().closed) {
        throw new TypeError('InstalledContentEvidenceUnavailable');
      }
    },
    beforeOperation() {
      current();
    },
    admitRun(prepared) {
      current();
      admitSelectedRun(prepared, requirements(originals, prepared), 'pure');
    },
    admitEffectRun(prepared) {
      current();
      if (typeof effectRequirements !== 'function') throw new TypeError('HostEffectResultPublicationUnavailable');
      admitSelectedRun(prepared, effectRequirements(originals, prepared), 'effect');
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
          await initializeKey();
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
          throw retainFailure(cause);
        }
      });
      openFlight = flight; return flight;
    },
  });
  return view;
}
