import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
  from './client-request-journal.mjs';
import {prepareLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership,
  assertOriginalPreparedLocalPublicationStoreOwnership}
  from '../store-local/publication-store.mjs';
import {admitHostRootFormat} from './host-root-format.mjs';
import recipeModule from './host-journal-service-recipe.cjs';
const installations = new WeakMap();

export function ordinaryHostJournalInstallation(originals) {
  const held = installations.get(originals.host);
  if (held === undefined || held.originals.installation !== originals.installation ||
      held.originals.generation !== originals.generation) throw new TypeError('ForeignInstalledHostJournal');
  held.view.assertCurrent(); return held.view;
}

// The existing Host/Journal owner acquires ordinary platform resources here.
// No preload, process-once slot or closure/allocator ancestry is required.
// Limits restrict controlled SQL, records and work; they are not an RSS lease.
export function prepareOrdinaryHostJournal(originals) {
  if (installations.has(originals.host)) throw new TypeError('InstalledHostJournalAlreadyPrepared');
  const installation = originals.installation, root = installation.root;
  if (typeof root !== 'string' || root.length === 0) throw new TypeError('InvalidInstalledHostRoot');
  const recipe = recipeModule.declareHostJournalServiceRecipe({ordinary: true});
  let closing = false, closed = false, acquisitionAttempted = false, openAttempted = false, ownership, journal;
  let journalClose, openingFailure, openingCleanup, openingStatus, openingRetry;
  let ownershipForwarded = false, flight, openingFlight, ownershipFlight;
  let privateEvidenceInitialization, privateEvidenceStatus;
  let rootFormatAdmission;
  const current = () => {
    if (closing || closed || originals.installation !== installation || installation.root !== root) {
      throw Object.assign(new Error('HostJournalPreparationUnavailable'), {code: 'HostJournalPreparationUnavailable'});
    }
  };
  function nativePending() {
    if (journal !== undefined) {
      const value = observeOriginalClientRequestJournalCustody(journal);
      return value.databaseClosed !== true || value.observationDatabaseClosed !== true;
    }
    if (!openAttempted && openingFailure === undefined) return false;
    if (openingFailure === undefined) return true;
    if (openingCleanup === undefined) {
      openingCleanup = openingFailure.cleanupHandle;
      if (openingCleanup === undefined) return openingFailure.cleanupPending === true;
      openingStatus = openingCleanup.status; openingRetry = openingCleanup.retry;
    }
    if (typeof openingStatus !== 'function') return true;
    const result = Reflect.apply(openingStatus, openingCleanup, []);
    return result?.pending !== false;
  }
  function privateEvidencePending() {
    if (privateEvidenceInitialization === undefined) return false;
    try {
      const value = Reflect.apply(privateEvidenceStatus, privateEvidenceInitialization, []);
      const field = value !== null && typeof value === 'object'
        ? Object.getOwnPropertyDescriptor(value, 'pending') : undefined;
      return field === undefined || !Object.hasOwn(field, 'value') || field.value !== false;
    } catch {return true;}
  }
  const dependency = Object.freeze({status() {
    return Object.freeze({pending: nativePending() || privateEvidencePending()});
  }});
  function retainOwnership() {
    if (ownershipFlight !== undefined) return ownershipFlight;
    ownershipFlight = Promise.resolve().then(async () => {
      try {
        ownership = await prepareLocalPublicationStoreOwnership(join(root, 'publication'),
          recipe.ownershipBounds, dependency);
        current();
      } catch (cause) {openingFailure = cause; throw cause;}
    });
    return ownershipFlight;
  }
  const status = () => Object.freeze({pending: !closed, journalPending: nativePending(),
    privateEvidencePending: privateEvidencePending(), ownershipPending: ownership !== undefined});
  async function close() {
    if (closed) return status();
    if (flight !== undefined) return flight;
    closing = true;
    const pending = Promise.resolve().then(async () => {
      // Close may race the asynchronous ownership acquisition. Observe that
      // same acquisition before deciding there is no child left to release.
      if (openingFlight !== undefined) {try {await openingFlight;} catch {}}
      if (ownershipFlight !== undefined) {try {await ownershipFlight;} catch {}}
      if (journal !== undefined && nativePending()) {
        journalClose ??= journal.close;
        if (typeof journalClose !== 'function') return status();
        Reflect.apply(journalClose, journal, []);
      }
      else if (openingCleanup !== undefined && nativePending()) {
        if (typeof openingRetry !== 'function') return status();
        await Reflect.apply(openingRetry, openingCleanup, []);
      }
      if (nativePending()) return status();
      // Key initialization retains its own failed FD/cleanup. The Journal
      // may close independently, but the same shared exclusion cannot retire
      // before that original child acknowledges close.
      if (privateEvidencePending()) return status();
      if (ownership !== undefined) {
        const result = await closePreparedLocalPublicationStoreOwnership(ownership);
        if (result?.pending !== false) return status();
        ownership = undefined;
      }
      journal = journalClose = openingFailure = openingCleanup = openingStatus = openingRetry = undefined;
      privateEvidenceInitialization = privateEvidenceStatus = undefined;
      openAttempted = false; closed = true;
      if (installations.get(originals.host)?.view === view) installations.delete(originals.host);
      return status();
    });
    flight = pending;
    try {return await pending;} finally {if (flight === pending) flight = undefined;}
  }
  const view = Object.freeze({assertCurrent: current, close,
    async admitRootFormat(directory) {
      current(); if (directory !== root) throw new TypeError('ForeignInstalledHostRoot');
      const admission = await admitHostRootFormat(root);
      rootFormatAdmission ??= admission;
      current();
      // The same exclusion also serializes explicitly authorized first
      // setup, before its external configuration/key files are created.
      await retainOwnership(); current();
      return rootFormatAdmission;
    },
    openRequestJournal(directory, options) {
      current();
      if (acquisitionAttempted || directory !== join(root, 'requests')) {
        return Promise.reject(new TypeError('ForeignInstalledHostJournal'));
      }
      acquisitionAttempted = true;
      const work = Promise.resolve().then(async () => {try {
        // Same-root exclusion is held before SQLite, and remains until BOTH
        // this original native Journal and the adopted Store acknowledge close.
        await retainOwnership();
        current(); openAttempted = true;
        journal = openClientRequestJournal(directory, {...recipe.journal, ...options,
          inspectionTemporaryDirectory: tmpdir(), primaryCurrent: current}, ownership);
        journalClose = journal.close;
        if (typeof journalClose !== 'function') throw new TypeError('InstalledHostJournalCleanupPending');
        observeOriginalClientRequestJournalCustody(journal);
        current(); return journal;
      } catch (cause) {
        openingFailure = cause;
        // The same child remains reachable before any later current check;
        // failed acquisition never creates a replacement Journal or lock.
        const error = Object.assign(new Error('InstalledHostJournalCleanupPending', {cause}),
          {code: 'InstalledHostJournalCleanupPending', cleanupPending: true});
        error.cleanupHandle = Object.freeze({status, retry: close});
        // Preserve the original acquisition failure across this additional
        // custody carrier. Diagnostic observation cannot discard its cleanup.
        error.primaryFailure = cause;
        try {
          if (cause !== null && (typeof cause === 'object' || typeof cause === 'function') &&
              Object.hasOwn(cause, 'primaryFailure')) error.primaryFailure = cause.primaryFailure;
          if (Array.isArray(cause?.cleanupErrors)) error.cleanupErrors = cause.cleanupErrors;
        } catch { /* Keep the original cause and same cleanup owner. */ }
        throw error;
      }});
      openingFlight = work;
      return work;
    },
    publicationOwnership() {
      current();
      // Explicit pre-start publication adopts the Store without opening SQLite.
      // The same acquired exclusion and its native/key dependencies still own
      // the one transfer; an absent Journal supplies no additional authority.
      if (ownership === undefined || ownershipForwarded) {
        throw new TypeError('ForeignInstalledHostPublicationOwnership');
      }
      ownershipForwarded = true; return ownership;
    },
    assertInitializationCurrent() {
      current();
      assertOriginalPreparedLocalPublicationStoreOwnership(ownership, join(root, 'publication'));
    },
    privateEvidenceInitializationOwnership() {
      current();
      assertOriginalPreparedLocalPublicationStoreOwnership(ownership, join(root, 'publication'));
      return ownership;
    },
    assertPrivateEvidenceFirstInitialization() {
      current();
      assertOriginalPreparedLocalPublicationStoreOwnership(ownership, join(root, 'publication'));
      // This initializer's actual marker creation, not absent key/Store
      // directories, establishes the first setup. A saved intent separately
      // resumes its original generation on later installations.
      if (rootFormatAdmission !== 'new') {
        throw Object.assign(new Error('PrivateEvidenceFirstInitializationUnavailable'),
          {code: 'PrivateEvidenceFirstInitializationUnavailable'});
      }
    },
    retainPrivateEvidenceInitialization(duty) {
      current();
      if (privateEvidenceInitialization === duty) return;
      const field = duty !== null && typeof duty === 'object'
        ? Object.getOwnPropertyDescriptor(duty, 'status') : undefined;
      if (privateEvidenceInitialization !== undefined || field === undefined ||
          !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
        throw new TypeError('ForeignPrivateEvidenceInitialization');
      }
      privateEvidenceInitialization = duty; privateEvidenceStatus = field.value;
    },
  });
  installations.set(originals.host, {originals, view});
  return view;
}
