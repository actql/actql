import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
  from './client-request-journal.mjs';
import {prepareLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership}
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
  let ownershipForwarded = false, flight, openingFlight;
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
    if (!openAttempted) return false;
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
  const dependency = Object.freeze({status() {return Object.freeze({pending: nativePending()});}});
  const status = () => Object.freeze({pending: !closed, journalPending: nativePending(),
    ownershipPending: ownership !== undefined});
  async function close() {
    if (closed) return status();
    if (flight !== undefined) return flight;
    closing = true;
    const pending = Promise.resolve().then(async () => {
      // Close may race the asynchronous ownership acquisition. Observe that
      // same acquisition before deciding there is no child left to release.
      if (openingFlight !== undefined) {try {await openingFlight;} catch {}}
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
      if (ownership !== undefined) {
        const result = await closePreparedLocalPublicationStoreOwnership(ownership);
        if (result?.pending !== false) return status();
        ownership = undefined;
      }
      journal = journalClose = openingFailure = openingCleanup = openingStatus = openingRetry = undefined;
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
      await admitHostRootFormat(root); current();
    },
    openRequestJournal(directory, options) {
      current();
      if (acquisitionAttempted || ownership !== undefined || directory !== join(root, 'requests')) {
        return Promise.reject(new TypeError('ForeignInstalledHostJournal'));
      }
      acquisitionAttempted = true;
      const work = Promise.resolve().then(async () => {try {
        // Same-root exclusion is held before SQLite, and remains until BOTH
        // this original native Journal and the adopted Store acknowledge close.
        ownership = await prepareLocalPublicationStoreOwnership(join(root, 'publication'),
          recipe.ownershipBounds, dependency);
        current(); openAttempted = true;
        journal = openClientRequestJournal(directory, {...recipe.journal, ...options,
          inspectionTemporaryDirectory: tmpdir(), primaryCurrent: current});
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
        throw error;
      }});
      openingFlight = work;
      return work;
    },
    publicationOwnership() {
      current();
      if (journal === undefined || ownership === undefined || ownershipForwarded) {
        throw new TypeError('ForeignInstalledHostPublicationOwnership');
      }
      ownershipForwarded = true; return ownership;
    },
  });
  installations.set(originals.host, {originals, view});
  return view;
}
