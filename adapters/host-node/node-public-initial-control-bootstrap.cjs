'use strict';

// Actual installed public-package prefix. This instance is constructed by its
// fixed delivery module, not by a caller's factory, receipt or options. It is
// deliberately separate from the preload recipe: no eager bytecode, preload
// ancestor, frozen-intrinsic history or earlier application work is claimed.
const {createRequire} = require('node:module');
const {join, dirname} = require('node:path');
const {getHeapStatistics} = require('node:v8');
const {isMainThread,threadId} = require('node:worker_threads');
const {isProxy} = require('node:util').types;
const {Buffer} = require('node:buffer');
const {open: openSourceFile} = require('node:fs/promises');
const processOriginal = require('node:process');
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const own = Object.hasOwn, freeze = Object.freeze;
const journalFacilityFields = require('./host-journal-facility-fields.cjs');
// Capture this private loader before namespace callbacks. This loads only its
// JS control body; native image acquisition still requires the separate full
// Journal disposition and is never funded by this reference alone.
const directoryNativeImage = require('./host-journal-native-image.cjs');
const {createHostJournalDirectoryInspector} = require('./host-journal-directory.mjs');
const {createInitialControlInstallationOwner} = require('./initial-control-installation-owner.cjs');
const {declareOrdinaryInitialControlPhaseEnvelope, inspectOrdinaryInitialControlPhaseEnvelope}
  = require('./initial-control-phase-envelope.cjs');
const {declareSourceManagedPhaseEnvelope,declareSourceComputePhaseEnvelope} = require('./source-managed-phase-envelope.cjs');
const fail = code => {throw Object.assign(new TypeError(code), {code});};
const unavailable = () => fail('NodeInitialControlAdmissionUnavailable');
const inputUnavailable = () => fail('NodeInitialControlInputUnavailable');
const field = (value,name) => {
  const entry = value === undefined ? undefined : descriptor(value,name);
  if (entry === undefined || !own(entry,'value')) unavailable();
  return entry.value;
};
const localRoot = join(__dirname,'..','..');
const delivery = module.parent;
const loadingModule = module;
let state, firstFailure, preparation, intake, closed = false;
// These originals belong to this actual installed prefix, not to an exported
// factory accepting a runtime label, caller callback, capacity or trust flag.
let sourceInstallation;
let journalInstallation;
const journalUnavailable = () => fail('HostJournalPreparationUnavailable');
const journalPromise = Promise, journalPromiseResolve = Promise.resolve;
const journalPromiseThen = Promise.prototype.then;

function journalOriginal(original, held, allowClosing = false) {
  const entry = journalInstallation;
  if (entry === undefined || entry.original !== original || entry.originals !== held ||
      entry.closed || (!allowClosing && entry.closing)) journalUnavailable();
  return entry;
}
function journalFailure(entry, cause) {
  const failure = freeze({cause});
  entry.firstError ??= failure;
  entry.latestError = failure;
}
function journalCurrent(original, held) {
  const entry = journalOriginal(original, held);
  try {
    assertSamePreparation(held);
    if (entry.disposition !== state.journalDisposition) journalUnavailable();
    apply(state.journal.current, state.namespace,
      [state.journalNative.DatabaseSync, state.journalNative.StatementSync, state.journalNative.bindings]);
    if (entry.nativeImage !== undefined) {
      if (typeof entry.nativeImageCurrent !== 'function') journalUnavailable();
      apply(entry.nativeImageCurrent, entry.nativeImage, []);
    }
    // The existing selected control recipe bounds path/control Strings. This
    // is only a support condition on the SAME nominal Host subject, never a
    // replacement issuer or credit from the initial-control disposition.
    const limit = field(field(state.declaration, 'limits'), 'pathCodeUnits');
    const root = field(entry.subject, 'root');
    const principalId = field(entry.subject, 'principalId');
    const journalDirectory = field(entry.subject, 'journalDirectory');
    if (limit !== 4096 || typeof root !== 'string' || root.length === 0 || root.length > limit ||
        typeof principalId !== 'string' || principalId.length === 0 || principalId.length > limit ||
        typeof journalDirectory !== 'string' || journalDirectory.length === 0 ||
        journalDirectory.length > limit) journalUnavailable();
    // Bound the originals BEFORE constructing this derived path or entering
    // Store/SQLite path conversion. Keep their aliases through the same joint
    // close; copying/equal DATA does not establish this subject's provenance.
    if (journalDirectory !== join(root, 'requests')) journalUnavailable();
    if (entry.paths === undefined) entry.paths = freeze({root, principalId, journalDirectory});
    const paths = entry.paths;
    if (root !== paths.root || principalId !== paths.principalId ||
        journalDirectory !== paths.journalDirectory) journalUnavailable();
    apply(entry.subjectCurrent, entry.subject, []);
    if (entry.ownership !== undefined) {
      apply(state.journal.ownershipCurrent, state.namespace,
        [entry.ownership, join(paths.root, 'publication')]);
    }
    // Current/native callbacks may fail or invalidate the original. Do not
    // continue from a changed path merely because its first check succeeded.
    if (field(entry.subject, 'root') !== paths.root ||
        field(entry.subject, 'principalId') !== paths.principalId ||
        field(entry.subject, 'journalDirectory') !== paths.journalDirectory) journalUnavailable();
    return entry;
  } catch (cause) {
    entry.closing = true;
    journalFailure(entry, cause);
    throw cause;
  }
}
function journalStatus(entry) {
  return freeze({pending: !entry.closed,
    nativePending: entry.journal !== undefined,
    constructorCleanupPending: entry.cleanup !== undefined,
    ownershipPending: entry.ownership !== undefined,
    // Retiring this facility never returns the process-lived module/native
    // domain or escaped immutable records as physical byte credit.
    physicalBackingReleased: false});
}
function journalCleanup(entry, cause) {
  const property = cause !== null && typeof cause === 'object'
    ? descriptor(cause, 'cleanupHandle') : undefined;
  if (property === undefined || !own(property, 'value')) return;
  // Retain the original handle BEFORE reading its fallible members. An
  // inaccessible cleanup remains pending, not an invented successful close.
  entry.cleanup = property.value;
  const status = descriptor(entry.cleanup, 'status');
  const retry = descriptor(entry.cleanup, 'retry');
  if (status === undefined || retry === undefined || !own(status, 'value') ||
      !own(retry, 'value') || typeof status.value !== 'function' ||
      typeof retry.value !== 'function') journalUnavailable();
  entry.cleanupStatus = status.value;
  entry.cleanupRetry = retry.value;
}
function journalAcknowledged(observation) {
  const pending = observation !== null && typeof observation === 'object'
    ? descriptor(observation, 'pending') : undefined;
  return pending !== undefined && own(pending, 'value') && pending.value === false;
}
function journalExclusionDependency(entry) {
  // This is the actual Root's original native custody, not a caller status
  // flag. Ownership-opening cleanup is not a native Journal dependency on
  // itself; it is retained and drained separately by closeJournal.
  if (entry.nativeAttempted && entry.cleanup !== undefined) return freeze({pending: true});
  if (entry.journal === undefined) return freeze({pending: false});
  const observation = apply(state.journal.observe, state.namespace, [entry.journal]);
  return freeze({pending: field(observation, 'databaseClosed') !== true ||
    field(observation, 'observationDatabaseClosed') !== true});
}
function closeJournal(entry) {
  entry.closing = true;
  if (entry.closeFlight !== undefined) return entry.closeFlight;
  // Publish before callbacks, including synchronous reentry from a retained
  // native/constructor cleanup. Retry observes this same duty, not a re-open.
  const flight = apply(journalPromiseThen, apply(journalPromiseResolve, journalPromise, []), [async () => {
    try {
      // An acquired child must be retained by the original opening flight
      // before close can inspect it. Closing prevents that flight from
      // starting native work after its awaited ownership/current boundary.
      if (entry.rootFormatFlight !== undefined) {
        try { await entry.rootFormatFlight; } catch {}
      }
      if (entry.openFlight !== undefined) {
        try { await entry.openFlight; } catch {}
      }
      if (entry.cleanup !== undefined) {
        if (typeof entry.cleanupStatus !== 'function' ||
            typeof entry.cleanupRetry !== 'function') return journalStatus(entry);
        let observation = await apply(entry.cleanupStatus, entry.cleanup, []);
        if (!journalAcknowledged(observation)) {
          observation = await apply(entry.cleanupRetry, entry.cleanup, []);
        }
        if (!journalAcknowledged(observation)) return journalStatus(entry);
        entry.cleanup = entry.cleanupStatus = entry.cleanupRetry = undefined;
      }
      if (entry.journal !== undefined) {
        if (typeof entry.journalClose !== 'function') return journalStatus(entry);
        apply(entry.journalClose, entry.journal, []);
        const observation = apply(state.journal.observe, state.namespace, [entry.journal]);
        // The original nominal observer, never a public closed flag, owns
        // primary native close. The separate observation connection has its
        // own original close observation, not its historical attempted flag.
        if (field(observation, 'databaseClosed') !== true ||
            field(observation, 'observationDatabaseClosed') !== true) return journalStatus(entry);
        entry.journal = entry.journalClose = undefined;
      }
      if (entry.ownership !== undefined) {
        const observation = await apply(state.journal.ownershipClose, state.namespace,
          [entry.ownership]);
        if (!journalAcknowledged(observation)) return journalStatus(entry);
        entry.ownership = undefined;
      }
      entry.closed = true;
      entry.subject = entry.subjectCurrent = entry.paths = undefined;
      entry.directoryInspection = entry.ownershipDirectoryInspection = entry.rootDirectoryInspection = undefined;
      entry.inspectionTemporaryDirectory = undefined;
      entry.nativeImage = entry.nativeImageCurrent = undefined;
      return journalStatus(entry);
    } catch (cause) {
      journalFailure(entry, cause);
      return journalStatus(entry);
    }
  }]);
  entry.closeFlight = flight;
  const settled = () => { if (entry.closeFlight === flight) entry.closeFlight = undefined; };
  apply(journalPromiseThen, flight, [settled, settled]);
  return flight;
}
function journalCarrier(entry, cause) {
  entry.closing = true;
  journalFailure(entry, cause);
  const carrier = new Error('HostJournalInstallationCleanupPending', {cause});
  carrier.code = 'HostJournalInstallationCleanupPending';
  carrier.cleanupHandle = freeze({status: () => journalStatus(entry),
    retry: () => closeJournal(entry)});
  return carrier;
}
function prepareJournal(held) {
  // The complete separate native/external disposition must already have
  // been adopted by this actual prefix before image/namespace acquisition.
  // Namespace functions, support bounds or the initial/Source declarations
  // alone cannot supply it. Until that original exists, refuse before reads.
  assertSamePreparation(held);
  if (state.journalDisposition === undefined || journalInstallation !== undefined ||
      state.journal === undefined || Object.values(state.journal)
        .some(value => typeof value !== 'function')) journalUnavailable();
  const original = freeze(Object.create(null));
  const entry = journalInstallation = {original, originals: held,
    disposition: state.journalDisposition, subject: undefined, subjectCurrent: undefined, paths: undefined,
    argumentsForJournal: undefined, nativeImage: undefined, nativeImageCurrent: undefined,
    directoryInspection: undefined, directoryEntryBound: undefined, inspectionTemporaryDirectory: undefined,
    ownershipDirectoryInspection: undefined, rootDirectoryInspection: undefined,
    rootFormatAttempted: false, rootFormatFlight: undefined,
    attempted: false, nativeAttempted: false, openFlight: undefined,
    ownership: undefined, ownershipForwarded: false, dependency: undefined,
    journal: undefined, journalClose: undefined,
    cleanup: undefined, cleanupStatus: undefined, cleanupRetry: undefined,
    closing: false, closed: false, closeFlight: undefined,
    firstError: undefined, latestError: undefined};
  try {
    entry.argumentsForJournal = field(entry.disposition, 'argumentsForOriginalJournal');
    if (typeof entry.argumentsForJournal !== 'function') journalUnavailable();
    entry.ownershipBounds = field(entry.disposition, 'ownershipBounds');
    entry.dependency = freeze({status: () => journalExclusionDependency(entry)});
    // These constructors were captured from this startup's builtin module
    // before the Host namespace. The fixed namespace operation must agree
    // on the same native facility before any subject read or DB acquisition.
    apply(state.journal.current, state.namespace,
      [state.journalNative.DatabaseSync, state.journalNative.StatementSync, state.journalNative.bindings]);
    const images = field(state.inventory, 'nativeImages');
    const limits = field(entry.disposition, 'directoryImageLimits');
    entry.inspectionTemporaryDirectory = field(limits, 'temporaryDirectory');
    if (typeof entry.inspectionTemporaryDirectory !== 'string' ||
        entry.inspectionTemporaryDirectory.length === 0 ||
        entry.inspectionTemporaryDirectory.length > 4096) journalUnavailable();
    if (!Array.isArray(images) || images.length !== 1 ||
        typeof state.directoryNativeImageLoader !== 'function') journalUnavailable();
    entry.nativeImage = apply(state.directoryNativeImageLoader, undefined,
      [localRoot, images[0], limits, assertPrefixCurrent]);
    // Retain the acquired module/custody BEFORE fallible operation/current
    // reads. Its process-lived domain is not retired by this Host's close.
    entry.nativeImageCurrent = field(entry.nativeImage, 'assertCurrent');
    if (typeof entry.nativeImageCurrent !== 'function') journalUnavailable();
    apply(entry.nativeImageCurrent, entry.nativeImage, []);
    assertSamePreparation(held);
    entry.directoryEntryBound = field(limits, 'maxEntries');
    entry.directoryInspection = createHostJournalDirectoryInspector(
      field(entry.nativeImage, 'operations'), limits, () => journalCurrent(original, held));
    // Store exclusion precedes Journal acquisition, so its directory reads
    // need the same retained native module, not a later stock Dir fallback.
    // This separate view's complete construction history is explicitly part
    // of the original disposition, not another copy of a credited allowance.
    const ownershipLimits = field(entry.disposition, 'ownershipDirectoryLimits');
    if (field(ownershipLimits, 'maxEntries') !== field(entry.ownershipBounds, 'maxDirectoryEntries')) {
      journalUnavailable();
    }
    entry.ownershipDirectoryInspection = createHostJournalDirectoryInspector(
      field(entry.nativeImage, 'operations'), ownershipLimits, () => journalCurrent(original, held));
    const rootLimits = field(entry.disposition, 'rootFormatDirectoryLimits');
    if (field(rootLimits, 'maxEntries') !== 1 || field(rootLimits, 'maxInspections') !== 2 ||
        field(rootLimits, 'maxNameBytes') !== 1024 || field(rootLimits, 'maxWork') !== 4096) {
      journalUnavailable();
    }
    entry.rootDirectoryInspection = createHostJournalDirectoryInspector(
      field(entry.nativeImage, 'operations'), rootLimits, () => journalCurrent(original, held));
    entry.subject = apply(state.journal.read, state.namespace, [held]);
    entry.subjectCurrent = field(entry.subject, 'assertCurrent');
    if (typeof entry.subjectCurrent !== 'function') journalUnavailable();
    journalCurrent(original, held);
    return original;
  } catch (cause) {
    try { journalCleanup(entry, cause); }
    catch (cleanupFailure) { journalFailure(entry, cleanupFailure); }
    throw journalCarrier(entry, cause);
  }
}
function admitJournalRootFormat(original, held, root) {
  const entry = journalCurrent(original, held);
  if (root !== entry.paths.root || entry.rootFormatAttempted || entry.attempted) journalUnavailable();
  entry.rootFormatAttempted = true;
  // Publish before invoking the captured namespace or an awaited marker/FD
  // operation. Host close retains this same flight and all partial cleanup.
  const flight = apply(journalPromiseThen, apply(journalPromiseResolve, journalPromise, []), [async () => {
    try {
      journalCurrent(original, held);
      const outcome = await apply(state.journal.rootFormat, state.namespace,
        [root, freeze({directoryInspection: entry.rootDirectoryInspection})]);
      journalCurrent(original, held);
      if (outcome !== 'new' && outcome !== 'current') journalUnavailable();
      return outcome;
    } catch (cause) {
      try { journalCleanup(entry, cause); }
      catch (cleanupFailure) { journalFailure(entry, cleanupFailure); }
      throw journalCarrier(entry, cause);
    }
  }]);
  entry.rootFormatFlight = flight;
  const settled = () => { if (entry.rootFormatFlight === flight) entry.rootFormatFlight = undefined; };
  apply(journalPromiseThen, flight, [settled, settled]);
  return flight;
}
function captureJournalNativeBindings(fsOriginal, cryptoOriginal, fsPromisesOriginal) {
  const bindings = Object.create(null);
  for (const [group,receiver] of [['fs',fsOriginal],['crypto',cryptoOriginal],
    ['promises',fsPromisesOriginal],
    ['constants',field(fsOriginal,'constants')],
    ['directory',field(field(fsOriginal,'Dir'),'prototype')],
    ['realpath',field(fsOriginal,'realpathSync')],
    ['hash',field(field(cryptoOriginal,'Hash'),'prototype')],
    ['hmac',field(field(cryptoOriginal,'Hmac'),'prototype')]]) {
    const values = Object.create(null);
    for (const name of journalFacilityFields[group]) {
      const value = field(receiver,name);
      if (typeof value !== (group === 'constants' ? 'number' : 'function')) unavailable();
      values[name] = value;
    }
    bindings[group] = freeze(values);
  }
  return freeze(bindings);
}
function openJournal(original, held, directory, options) {
  const entry = journalCurrent(original, held);
  if (entry.attempted || entry.rootFormatFlight !== undefined ||
      directory !== entry.paths.journalDirectory) journalUnavailable();
  // The selected disposition's fixed argument boundary must precede native
  // work. No caller option object or scalar may select a facility/limit.
  entry.attempted = true;
  let selected;
  try {
    selected = apply(entry.argumentsForJournal, entry.disposition,
      [entry.subject, options, entry.directoryInspection, entry.inspectionTemporaryDirectory]);
    if (field(selected, 'primaryDirectoryInspection') !== entry.directoryInspection ||
        field(selected, 'maxInspectionEntries') !== entry.directoryEntryBound ||
        field(selected, 'inspectionTemporaryDirectory') !== entry.inspectionTemporaryDirectory) journalUnavailable();
  } catch (cause) {
    try { journalCleanup(entry, cause); }
    catch (cleanupFailure) { journalFailure(entry, cleanupFailure); }
    throw journalCarrier(entry, cause);
  }
  const flight = apply(journalPromiseThen, apply(journalPromiseResolve, journalPromise, []), [async () => {
    try {
      journalCurrent(original, held);
      // Root format admission has already completed in the Host caller.
      // Acquire the same Store exclusion before the native Journal; no fresh
      // publication prefix is created during the earlier preparation phase.
      const ownership = await apply(state.journal.ownershipPrepare, state.namespace,
        [join(entry.paths.root, 'publication'), entry.ownershipBounds, entry.dependency,
          entry.ownershipDirectoryInspection]);
      entry.ownership = ownership;
      if (ownership === undefined) journalUnavailable();
      journalCurrent(original, held);
      entry.nativeAttempted = true;
      const journal = apply(state.journal.open, state.namespace, [directory, selected]);
      entry.journal = journal;
      // Retain returned native custody before all fallible field/current reads.
      entry.journalClose = field(journal, 'close');
      if (typeof entry.journalClose !== 'function') journalUnavailable();
      apply(state.journal.observe, state.namespace, [journal]);
      journalCurrent(original, held);
      return journal;
    } catch (cause) {
      try { journalCleanup(entry, cause); }
      catch (cleanupFailure) { journalFailure(entry, cleanupFailure); }
      throw journalCarrier(entry, cause);
    }
  }]);
  entry.openFlight = flight;
  const settled = () => { if (entry.openFlight === flight) entry.openFlight = undefined; };
  apply(journalPromiseThen, flight, [settled, settled]);
  return flight;
}
function journalPublicationOwnership(original, held) {
  const entry = journalCurrent(original, held);
  if (entry.journal === undefined || entry.ownership === undefined || entry.ownershipForwarded) {
    journalUnavailable();
  }
  // Forward the existing physical original once to the same Host's Store.
  // Its fifth-argument adoption owns validation/one adoption; this operation
  // creates neither another owner nor Store/key/payload resource authority.
  entry.ownershipForwarded = true;
  return entry.ownership;
}
const sourceChildren = new WeakMap();
const sourceUnavailable = () => fail('SourceManagedPreparationUnavailable');
const sourceTypedArrayPrototype = Object.getPrototypeOf(Object.getPrototypeOf(Buffer.prototype));
const sourceOperations = freeze([
  [Buffer, 'alloc'], [Buffer, 'isBuffer'], [Buffer.prototype, 'subarray'], [Buffer.prototype, 'equals'],
  [sourceTypedArrayPrototype, 'buffer'], [sourceTypedArrayPrototype, 'byteOffset'],
  [sourceTypedArrayPrototype, 'byteLength'],
  [WeakMap.prototype, 'get'], [WeakMap.prototype, 'set'], [Object, 'defineProperty'],
].map(([receiver, name]) => freeze({receiver, name, property: descriptor(receiver, name)})));
const sourceAlloc = sourceOperations[0].property?.value;
const sourceIsBuffer = sourceOperations[1].property?.value;
const sourceSubarray = sourceOperations[2].property?.value;
const sourceEquals = sourceOperations[3].property?.value;
const sourceArrayBuffer = sourceOperations[4].property?.get;
const sourceByteOffset = sourceOperations[5].property?.get;
const sourceByteLength = sourceOperations[6].property?.get;
const sourceMapGet = sourceOperations[7].property?.value;
const sourceMapSet = sourceOperations[8].property?.value;
const sourceDefineProperty = sourceOperations[9].property?.value;
function appendSourceOriginal(array, value) {
  apply(sourceDefineProperty, Object, [array, array.length,
    {value, writable: true, enumerable: true, configurable: true}]);
}
function sourceOperationsChanged() {
  const entry = sourceInstallation;
  const cause = entry?.operationFailure?.cause ?? Object.assign(
    new TypeError('SourceManagedPreparationUnavailable'), {code: 'SourceManagedPreparationUnavailable'});
  if (entry !== undefined) {
    entry.operationFailure ??= freeze({cause});
    entry.closing = true;
    sourceFailure(entry, cause);
  }
  throw cause;
}
function assertSourceOperationsCurrent() {
  if (![sourceAlloc, sourceIsBuffer, sourceSubarray, sourceEquals,
    sourceArrayBuffer, sourceByteOffset, sourceByteLength, sourceMapGet, sourceMapSet,
    sourceDefineProperty].every(value => typeof value === 'function')) sourceOperationsChanged();
  for (const held of sourceOperations) {
    const current = descriptor(held.receiver, held.name), original = held.property;
    if (current === undefined || original === undefined || current.value !== original.value ||
        current.get !== original.get || current.set !== original.set ||
        current.writable !== original.writable || current.enumerable !== original.enumerable ||
        current.configurable !== original.configurable) sourceOperationsChanged();
  }
}
function sourceBackingRange(value, bytes) {
  // Native typed-array accessors reject a Proxy/fake without invoking its
  // getters. A valid Buffer wrapper is still not a distinct physical holding.
  if (isProxy(value) || !apply(sourceIsBuffer, Buffer, [value]) ||
      apply(sourceByteLength, value, []) !== bytes) sourceUnavailable();
  return freeze({buffer: apply(sourceArrayBuffer, value, []),
    offset: apply(sourceByteOffset, value, []), bytes});
}
function allocateSourceBacking(entry, bytes) {
  assertSourceOperationsCurrent();
  entry.backingUnknown = true;
  const value = apply(sourceAlloc, Buffer, [bytes]);
  // Retain every constructor observation before validation/current checks.
  appendSourceOriginal(entry.backings, value);
  const range = sourceBackingRange(value, bytes);
  entry.backingUnknown = false;
  for (let index = 0; index < entry.backingRanges.length; index++) {
    if (entry.backingRanges[index].buffer === range.buffer) sourceUnavailable();
  }
  appendSourceOriginal(entry.backingRanges, range);
  assertSourceOperationsCurrent();
  return value;
}
function sourceOriginal(original, held, allowClosing = false) {
  const entry = sourceInstallation;
  if (entry === undefined || entry.original !== original || entry.originals !== held ||
      entry.closed || (!allowClosing && entry.closing)) sourceUnavailable();
  return entry;
}
function sourceCurrent(original, held) {
  const entry = sourceOriginal(original, held);
  try {
    assertSamePreparation(held);
    assertSourceOperationsCurrent();
    apply(state.source.validator, state.namespace, [held]);
    return entry;
  } catch(cause) {
    sourceFailure(entry,cause);entry.closing=true;
    throw cause;
  }
}
function sourceReceipt(entry, receipt) {
  if (entry.receipt === undefined || entry.receipt.original !== receipt) sourceUnavailable();
  return entry.receipt;
}
function sourceFailure(entry, cause) {
  const error = freeze({cause});
  entry.firstError ??= error;
  entry.latestError = error;
}
function sourceChildrenPending(entry) {
  for (let index = 0; index < entry.children.length; index++) {
    const child = entry.children[index];
    if (!child.stopped || !child.released || child.flight !== undefined) return true;
  }
  return false;
}
function sourceStatus(entry) {
  return freeze({pending: !entry.closed, fdPending: entry.file !== undefined,
    managedRunPending: entry.receipt?.managedRun?.admitted === true && !entry.receipt.managedRun.stopped,
    backingUnknown: entry.backingUnknown,
    childrenPending: sourceChildrenPending(entry),
    physicalBackingReleased: false});
}
async function closeSource(entry) {
  entry.closing = true;
  if (entry.closeFlight !== undefined) return entry.closeFlight;
  const flight = (async () => {
    if (entry.backingUnknown) return sourceStatus(entry);
    if (entry.receipt !== undefined && !entry.receipt.finished) return sourceStatus(entry);
    if (entry.receipt?.managedRun?.admitted === true && !entry.receipt.managedRun.stopped) return sourceStatus(entry);
    if (sourceChildrenPending(entry)) {
      return sourceStatus(entry);
    }
    if (entry.openFlight !== undefined) {
      try {await entry.openFlight;} catch (cause) {sourceFailure(entry, cause);}
    }
    if (entry.file !== undefined) {
      try {
        if (entry.fileClose === undefined) entry.fileClose = entry.file.close;
        if (typeof entry.fileClose !== 'function' || await apply(entry.fileClose, entry.file, []) === false) {
          sourceUnavailable();
        }
        entry.file = undefined;
        entry.fileClose = entry.fileRead = entry.fileStat = undefined;
      } catch (cause) {sourceFailure(entry, cause);return sourceStatus(entry);}
    }
    entry.closed = true;
    // Body backings and escaped byte aliases remain charged for their actual
    // process lifetime. This managed retirement never returns byte credit.
    entry.bundle = undefined;
    return sourceStatus(entry);
  })();
  entry.closeFlight = flight;
  try {return await flight;} finally {if (entry.closeFlight === flight) entry.closeFlight = undefined;}
}
async function prepareSource(held) {
  if (state === undefined || sourceInstallation !== undefined || state.source === undefined ||
      Object.values(state.source).some(value => typeof value !== 'function')) sourceUnavailable();
  assertSamePreparation(held);
  const original = freeze(Object.create(null));
  const entry = sourceInstallation = {original, originals: held, bundle: undefined,
    closing: false, closed: false, children: [], receipt: undefined,
    file: undefined, fileClose: undefined, fileRead: undefined, fileStat: undefined,
    fileIdentity: undefined, openFlight: undefined, closeFlight: undefined,
    firstError: undefined, latestError: undefined, backings: [], backingRanges: [],
    backingUnknown: false, lookahead: undefined};
  try {
    // Real distinct ArrayBuffers, not an unused arena lent to another allocator.
    // The two original full-document acquisitions retain these independent
    // backings even though the same file/managed declarations are shared.
    for (let ordinal = 0; ordinal < state.sourceEnvelope.limits.sourceOccurrences; ordinal++) {
      allocateSourceBacking(entry, state.sourceEnvelope.limits.responseBytes);
    }
    entry.lookahead = allocateSourceBacking(entry, 1);
    sourceCurrent(original, held);
    await apply(state.source.prepare, state.namespace, [held, original]);
    sourceCurrent(original, held);
    const bundle = apply(state.source.read, state.namespace, [held]);
    if (bundle === null || typeof bundle !== 'object' || !Object.isFrozen(bundle) ||
        typeof bundle.dataPath !== 'string' || bundle.dataPath.length > 65536 ||
        !Array.isArray(bundle.sources) || bundle.sources.length !== state.sourceEnvelope.limits.sourceOccurrences) sourceUnavailable();
    entry.bundle = bundle;
    sourceCurrent(original, held);
    return original;
  } catch (cause) {
    entry.closing = true;
    sourceFailure(entry, cause);
    const carrier = new Error('SourceManagedInstallationCleanupPending', {cause});
    carrier.code = 'SourceManagedInstallationCleanupPending';
    carrier.cleanupHandle = freeze({status: () => sourceStatus(entry), retry: () => closeSource(entry)});
    throw carrier;
  }
}
function assertSourceRequest(entry, derived) {
  sourceCurrent(entry.original, entry.originals);
  if (entry.receipt === undefined || entry.receipt.finished) sourceUnavailable();
  // Only the captured actual Host namespace can follow its own bounded
  // clone/preparation chain back to the original pending SDK packet.
  const request = apply(state.source.request, state.namespace, [entry.originals, derived]);
  if (entry.receipt.request !== request) sourceUnavailable();
  return request;
}
function sourceChildCurrent(child) {
  const entry = sourceCurrent(child.entry.original, child.entry.originals);
  if (apply(sourceMapGet, sourceChildren, [child.originalSource]) !== child || child.entry !== entry ||
      child.producer !== entry.receipt || child.request !== child.producer.request ||
      child.stopped || child.released) sourceUnavailable();
  if (child.managedRun !== undefined) managedRunCurrent(child.managedRun);
  // This exact child was issued while the original request was pending.
  // SDK reply/alias retirement cannot reconstruct or revoke this independent
  // original read duty; no new lookup, value/CID match or grant is made here.
}
function sourceFileIdentity(value) {
  return [value.dev, value.ino, value.size, value.mtimeNs, value.ctimeNs];
}
async function assertSourceFile(entry) {
  const observed = await apply(entry.fileStat, entry.file, [{bigint: true}]);
  const identity = sourceFileIdentity(observed);
  if (!observed.isFile() || observed.size > BigInt(state.sourceEnvelope.limits.responseBytes)) sourceUnavailable();
  if (entry.fileIdentity === undefined) entry.fileIdentity = identity;
  else if (identity.some((value, ordinal) => value !== entry.fileIdentity[ordinal])) sourceUnavailable();
}
async function readSourceBytes(entry, child) {
  sourceChildCurrent(child);
  if (!child.admitted || child.stopped || child.released || child.readAttempted) sourceUnavailable();
  child.readAttempted = true;
  const flight = (async () => {
    if (entry.openFlight === undefined) {
      entry.openFlight = (async () => {
        // This happens only at the existing authorized read consumer, never
        // during Project/connection metadata preparation or a Source snapshot.
        entry.file = await openSourceFile(entry.bundle.dataPath, 'r');
        entry.fileClose = entry.file.close;
        entry.fileRead = entry.file.read;
        entry.fileStat = entry.file.stat;
        if (![entry.fileClose, entry.fileRead, entry.fileStat].every(value => typeof value === 'function')) {
          sourceUnavailable();
        }
      })();
    }
    await entry.openFlight;
    sourceChildCurrent(child);
    await assertSourceFile(entry);
    sourceChildCurrent(child);
    let used = 0;
    const backing = entry.backings[child.ordinal], range = entry.backingRanges[child.ordinal];
    while (used < range.bytes) {
      const {bytesRead} = await apply(entry.fileRead, entry.file, [backing, used, range.bytes - used, used]);
      sourceChildCurrent(child);
      if (!Number.isSafeInteger(bytesRead) || bytesRead < 0 || bytesRead > range.bytes - used) sourceUnavailable();
      if (bytesRead === 0) break;
      used += bytesRead;
    }
    if (used === range.bytes) {
      const {bytesRead} = await apply(entry.fileRead, entry.file, [entry.lookahead, 0, 1, used]);
      sourceChildCurrent(child);
      if (bytesRead !== 0) sourceUnavailable();
    }
    await assertSourceFile(entry);
    sourceChildCurrent(child);
    const bytes = apply(sourceSubarray, backing, [0, used]);
    const observed = sourceBackingRange(bytes, used);
    if (observed.buffer !== range.buffer || observed.offset !== range.offset) sourceUnavailable();
    for (let index = 0; index < entry.children.length; index++) {
      const sibling = entry.children[index];
      if (sibling !== child && sibling.bytes !== undefined &&
          apply(sourceEquals, bytes, [sibling.bytes]) !== true) sourceUnavailable();
    }
    sourceChildCurrent(child);
    child.bytes = bytes;
    return bytes;
  })();
  child.flight = flight;
  try {return await flight;} catch (cause) {sourceFailure(entry, cause);throw cause;}
  finally {if (child.flight === flight) child.flight = undefined;}
}
function prepareSourceRead(original, held, derived, declaration, originalRun) {
  const entry = sourceCurrent(original, held);
  const request = assertSourceRequest(entry, derived);
  let managedRun;
  if (originalRun !== undefined) {
    managedRun = entry.receipt.managedRun;
    if (managedRun === undefined || managedRun.original !== originalRun ||
        managedRun.derived !== derived || !managedRun.admitted) sourceUnavailable();
    managedRunCurrent(managedRun);
  } else if (entry.receipt.managedRun !== undefined) {
    // A joint Run cannot fall back to two independent Source-only Ledgers.
    sourceUnavailable();
  }
  let ordinal = -1;
  for (let index = 0; index < entry.bundle.sources.length; index++) {
    if (entry.bundle.sources[index].declaration === declaration) ordinal = index;
  }
  if (ordinal < 0) sourceUnavailable();
  for (let index = 0; index < entry.children.length; index++) {
    if (entry.children[index].ordinal === ordinal) sourceUnavailable();
  }
  const originalSource = freeze(Object.create(null));
  const child = {entry, ordinal, derived, request, producer: entry.receipt, originalSource, managedRun, portsTaken: false,
    admitted: managedRun !== undefined, stopped: false, released: false, readAttempted: false,
    flight: undefined, bytes: undefined, usage: undefined};
  appendSourceOriginal(entry.children, child);
  apply(sourceMapSet, sourceChildren, [originalSource, child]);
  return freeze({originalSource,
    readOriginalBytes() {return readSourceBytes(entry, child);},
    close() {
      if (!child.portsTaken && child.managedRun === undefined) child.stopped = true;
      child.released = true;
      return freeze({pending: child.flight !== undefined});
    },
    status() {return freeze({pending: !child.stopped || !child.released || child.flight !== undefined,
      fdPending: entry.file !== undefined, physicalBackingReleased: false});}});
}
function prepareOriginalSourceChildPorts(original) {
  // A missing original is refused without inspecting a caller reference.
  if (sourceInstallation === undefined || typeof sourceMapGet !== 'function') return null;
  const child = apply(sourceMapGet, sourceChildren, [original]);
  if (child === undefined || child.managedRun !== undefined || child.portsTaken || child.stopped || child.released) return null;
  try {sourceChildCurrent(child);}
  catch (cause) {
    sourceFailure(child.entry, cause);
    child.entry.closing = true;
    child.stopped = true;
    return null;
  }
  child.portsTaken = true;
  const envelope = state.sourceEnvelope, partition = envelope.occurrencePartitions[child.ordinal];
  const quotas = [BigInt(Math.floor(envelope.limits.sourceWork / envelope.limits.sourceOccurrences)),
    BigInt(partition.responses), BigInt(partition.responses), BigInt(partition.responseBackingBytes),
    BigInt(partition.responseBackingBytes), BigInt(envelope.limits.decodedWireBytes)];
  const current = () => {
    if (child.stopped || child.released || child.entry.closing) return 1;
    try {sourceChildCurrent(child);return 0;}
    catch {return 1;}
  };
  return freeze({
    status(operation) {
      if (operation === 2) {
        if (!child.admitted || child.stopped || child.usage === undefined || child.flight !== undefined) return -42;
        child.stopped = true;
        return 0;
      }
      if (operation === 1) return current();
      if (current() !== 0) return -42;
      if (operation === 0) {
        if (child.admitted) return -42;
        child.admitted = true;
      } else return -42;
      return 0;
    },
    limit(ordinal) {return Number.isInteger(ordinal) && ordinal >= 0 && ordinal < quotas.length ? quotas[ordinal] : -42n;},
    report(planning, attempts, holdings, transferred, uncertain, reservedTransfer,
      heldBytes, reservedRetention, reservedExecution, peakRetention) {
      // Core supplies this usage; these counters never acknowledge the FD or
      // return the actual process-lived response ArrayBuffers to a sibling.
      if (!child.admitted || child.stopped || ![planning, attempts, holdings].every(Number.isSafeInteger) ||
          planning < 0 || attempts < 0 || holdings < 0 || BigInt(planning) > quotas[0] ||
          BigInt(attempts) > quotas[1] || BigInt(holdings) > quotas[2] ||
          ![transferred, uncertain, reservedTransfer, heldBytes, reservedRetention, reservedExecution, peakRetention]
            .every(value => typeof value === 'bigint' && value >= 0n) ||
          transferred + uncertain + reservedTransfer > quotas[3] ||
          heldBytes + reservedRetention > quotas[4] || peakRetention > quotas[4] || reservedExecution > quotas[5]) return -42;
      child.usage = freeze({planning, attempts, holdings, transferred, uncertain, reservedTransfer,
        heldBytes, reservedRetention, reservedExecution, peakRetention});
      return 0;
    },
  });
}
function managedRunCurrent(run) {
  const entry = sourceCurrent(run.entry.original,run.entry.originals);
  if (run.entry !== entry || entry.receipt !== run.producer ||
      run.producer.managedRun !== run || run.stopped ||
      run.request !== run.producer.request || run.derived === undefined) sourceUnavailable();
}
function claimManagedRun(original,held,derived) {
  const entry = sourceCurrent(original,held), request = assertSourceRequest(entry,derived);
  const run = entry.receipt.managedRun;
  if (run === undefined || run.claimed) sourceUnavailable();
  // This is a claim of the pre-snapshot original, not a late Compute issuer.
  // Retain the exact opaque prepared/request pointers before the fixed Owner's
  // fallible sizing/current fences. A failure never issues another original.
  run.claimed = true;run.derived = derived;run.request = request;
  try {
    const required = apply(state.runRequirements,state.namespace,[held,derived]);
    const bounds = state.sourceComputeEnvelope.limits;
    const names = ['planningWork','attempts','holdings','transferBytes','retainedBytes','executionBytes'];
    if (required === null || typeof required !== 'object' || isProxy(required) || !Object.isFrozen(required)) sourceUnavailable();
    const quotas = [];
    for (let index=0;index<names.length;index++) {
      const name=names[index], property=descriptor(required,name);
      if (property === undefined || !own(property,'value')) sourceUnavailable();
      const value=property.value;
      if (index<3 ? !Number.isSafeInteger(value) || value<0 || value>2147483647 :
          typeof value!=='bigint' || value<0n) sourceUnavailable();
      const amount=BigInt(value);
      if (amount>BigInt(bounds[name])) sourceUnavailable();
      appendSourceOriginal(quotas,amount);
    }
    run.quotas=freeze(quotas);
    managedRunCurrent(run);
    return run.original;
  } catch(cause) {
    sourceFailure(entry,cause);entry.closing=true;
    throw cause;
  }
}
function prepareOriginalManagedRunPorts(original,prepared) {
  const entry=sourceInstallation,run=entry?.receipt?.managedRun;
  if (run===undefined || run.original!==original || run.derived!==prepared || !run.claimed ||
      run.quotas===undefined || run.portsTaken || run.stopped) return null;
  try {managedRunCurrent(run);} catch(cause) {
    sourceFailure(entry,cause);entry.closing=true;return null;
  }
  run.portsTaken=true;
  const current=()=>{
    if (run.stopped || entry.closing) return 1;
    try {managedRunCurrent(run);return 0;} catch {return 1;}
  };
  return freeze({cancelUnpublished() {
    // Only the retained typed Resource child calls this after proving it has
    // never published a Ledger. This is a distinct initialization outcome,
    // not zero usage or an FD/backing/escaped-object acknowledgement.
    if (run.unpublished===true) return 0;
    if (run.stopped || run.usage!==undefined) return -42;
    for (let index=0;index<entry.children.length;index++) {
      const child=entry.children[index];
      if (child.managedRun===run && (child.readAttempted || child.flight!==undefined || !child.released)) return -42;
    }
    run.unpublished=true;run.stopped=true;
    return 0;
  },status(operation) {
    if (operation===2) {
      if (!run.admitted || run.stopped || run.usage===undefined ||
          run.usage.uncertain!==0n || run.usage.reservedTransfer!==0n ||
          run.usage.heldBytes!==0n || run.usage.reservedRetention!==0n ||
          run.usage.reservedExecution!==0n) return -42;
      for (let index=0;index<entry.children.length;index++) {
        const child=entry.children[index];
        if (child.managedRun===run && child.flight!==undefined) return -42;
      }
      run.stopped=true;
      for (let index=0;index<entry.children.length;index++) {
        const child=entry.children[index];
        if (child.managedRun===run) child.stopped=true;
      }
      return 0;
    }
    if (operation===1) return current();
    if (operation!==0 || current()!==0 || run.admitted) return -42;
    run.admitted=true;return 0;
  },limit(ordinal) {
    return Number.isInteger(ordinal)&&ordinal>=0&&ordinal<run.quotas.length?run.quotas[ordinal]:-42n;
  },report(planning,attempts,holdings,transferred,uncertain,reservedTransfer,
    heldBytes,reservedRetention,reservedExecution,peakRetention) {
    const quota=run.quotas;
    if (!run.admitted || run.stopped || ![planning,attempts,holdings].every(Number.isSafeInteger) ||
        planning<0 || attempts<0 || holdings<0 || BigInt(planning)>quota[0] ||
        BigInt(attempts)>quota[1] || BigInt(holdings)>quota[2] ||
        ![transferred,uncertain,reservedTransfer,heldBytes,reservedRetention,reservedExecution,peakRetention]
          .every(value=>typeof value==='bigint'&&value>=0n) ||
        transferred+uncertain+reservedTransfer>quota[3] || heldBytes+reservedRetention>quota[4] ||
        peakRetention>quota[4] || reservedExecution>quota[5]) return -42;
    run.usage=freeze({planning,attempts,holdings,transferred,uncertain,reservedTransfer,
      heldBytes,reservedRetention,reservedExecution,peakRetention});return 0;
  }});
}
const inputLimits = freeze({maxProperties:40,maxNodes:40,maxDepth:4,
  maxStringCodeUnits:4096,maxTotalStringCodeUnits:8192,maxArrayItems:0,maxOpaqueAliases:0,maxWork:65536});
// Capture actual prefix-time descriptors without evaluating a global accessor
// (Node's standard lazy Buffer binding is an accessor). They stay original
// observations, not evidence that arbitrary prior application code was covered.
const prefixIntrinsics = [];
const intrinsicSource = Function.prototype.toString;
for (const [receiver,names] of [[Object,['getOwnPropertyDescriptor','hasOwn','freeze','create']],
  [Reflect,['apply','ownKeys']],[Array,['isArray']],[globalThis,['Object','Reflect','Array','Promise','Buffer']]]) {
  for (const name of names) prefixIntrinsics.push(freeze({receiver,name,property:descriptor(receiver,name)}));
}
freeze(prefixIntrinsics);
function assertSupportedIntrinsics() {
  if (isProxy(intrinsicSource) || apply(intrinsicSource,intrinsicSource,[]) !==
      'function toString() { [native code] }') unavailable();
  for (const held of prefixIntrinsics) {
    const value=held.property?.value;
    if (typeof value !== 'function') continue;
    if (isProxy(value) || apply(intrinsicSource,value,[]) !==
        `function ${held.name}() { [native code] }`) unavailable();
  }
  // This exact Node 22.22 global lazy accessor is implementation input, not a
  // caller getter protocol. Refuse substitutions before invoking it, then
  // require its original value to be the selected node:buffer constructor.
  const buffer=descriptor(globalThis,'Buffer');
  if (typeof buffer?.get !== 'function' || typeof buffer?.set !== 'function' ||
      isProxy(buffer.get) || isProxy(buffer.set) ||
      apply(intrinsicSource,buffer.get,[]) !== 'get() {\n      return _Buffer;\n    }' ||
      apply(intrinsicSource,buffer.set,[]) !== 'set(value) {\n      _Buffer = value;\n    }' ||
      apply(buffer.get,globalThis,[]) !== require('node:buffer').Buffer) unavailable();
}
function assertIntrinsicsCurrent() {
  for (const held of prefixIntrinsics) {
    const current=descriptor(held.receiver,held.name), original=held.property;
    if (current === undefined || original === undefined || current.value !== original.value ||
        current.get !== original.get || current.set !== original.set ||
        current.writable !== original.writable || current.enumerable !== original.enumerable ||
        current.configurable !== original.configurable) unavailable();
  }
}

function sameOriginals(left,right) {
  return left.host === right.host && left.installation === right.installation &&
    left.generation === right.generation && left.supplier === right.supplier &&
    left.moduleLifetime === right.moduleLifetime;
}
function assertPrefixCurrent() {
  if (firstFailure !== undefined) throw firstFailure.cause;
  if (state === undefined) unavailable();
  if (processOriginal !== process || loadingModule !== require.cache[__filename] ||
      loadingModule.exports !== table || delivery !== require.cache[delivery.filename] ||
      processOriginal.execArgv.length !== 0 || processOriginal.env.NODE_OPTIONS !== undefined) unavailable();
  assertIntrinsicsCurrent();
  state.images.assertCurrent();
}
function assertSamePreparation(held) {
  if (preparation === undefined || closed || !sameOriginals(held,preparation.originals)) inputUnavailable();
  assertPrefixCurrent();
  apply(state.validator,state.namespace,[held]);
}
const operational = freeze({
  prepare(held,raw) {
    assertPrefixCurrent();
    if (preparation !== undefined || intake === undefined || intake.raw !== raw || intake.consumed) inputUnavailable();
    apply(state.validator,state.namespace,[held]);
    // Retain original scope/candidate before any subsequent fallible current
    // observation. This process recipe cannot be replenished by Host close.
    preparation = {originals:held,input:intake.snapshot.packet};
    intake.consumed = true;
    intake.raw = undefined;
  },
  assertCurrent: assertSamePreparation,
  readInput(held) {assertSamePreparation(held);return preparation.input;},
  readAsset(held,path) {assertSamePreparation(held);return state.images.readAsset(path);},
  close(held) {
    if (preparation === undefined || !sameOriginals(held,preparation.originals)) inputUnavailable();
    // Called only by the same Owner after child ACKs and preparation alias
    // release. Images, lazy compiled code/native domains and escaped outputs
    // remain process-lived; this observation returns no business capacity.
    preparation.input = undefined;
    intake = undefined;
    closed = true;
    return freeze({pending:false});
  },
});
const owner = createInitialControlInstallationOwner(operational);
function connectInitialControlHostPreparation(kind,raw) {
  // One fixed own-DATA selector belongs to this prefix's finite scaffolding,
  // not complete packet admission. It invokes no getter/Proxy trap and keeps
  // existing unselected routes independent of Local image/preparation failure.
  if (kind === 'connect') {
    if (raw === null || typeof raw !== 'object' || isProxy(raw)) return undefined;
    const mode = descriptor(raw,'mode');
    if (mode === undefined || !own(mode,'value') || mode.value !== 'local') return undefined;
    const endpoint=descriptor(raw,'endpoint');
    if (endpoint !== undefined && own(endpoint,'value') && endpoint.value !== undefined) return undefined;
  } else if (kind !== 'open') inputUnavailable();
  assertPrefixCurrent();
  if (preparation !== undefined || intake !== undefined) inputUnavailable();
  // The actual selected prefix's finite runtime/packet envelope precedes this
  // FIRST enumeration. Reader bounds do not retroactively fund acquisition.
  const snapshot = kind === 'open' && raw === undefined ? freeze({packet:freeze(Object.create(null)),originalReferences:freeze([])}) :
    apply(state.reader,state.namespace,[raw,inputLimits]);
  const packet = snapshot.packet;
  if (snapshot.originalReferences.length !== 0) inputUnavailable();
  if (kind === 'open') {
    // This selected recipe covers own DATA, not inherited option getters.
    // Refuse that unsupported backing without invoking or silently dropping it.
    for (const name of ['stateDir', 'installation', 'durability', 'consentRefs']) {
      if (!own(packet,name) && name in packet) inputUnavailable();
    }
  }
  if (kind === 'connect') {
    const keys = Reflect.ownKeys(packet);
    if (keys.length !== 3 || !keys.includes('mode') || !keys.includes('installation') || !keys.includes('profile') ||
        packet.mode !== 'local' || packet.profile !== 'mock' || packet.installation === null ||
        typeof packet.installation !== 'object') inputUnavailable();
    const names = Reflect.ownKeys(packet.installation);
    if (names.length !== 1 || names[0] !== 'directory' ||
        typeof packet.installation.directory !== 'string' || packet.installation.directory.length === 0) inputUnavailable();
  }
  intake = {raw,snapshot,consumed:false};
  // A synchronous refusal or partial begin retains intake under this same
  // prefix. Never clear/reissue merely because a Promise rejected.
  return apply(state.consumer,state.namespace,[kind,raw]);
}
const table = module.exports = {
  selectedInitialControlHostPreparation:connectInitialControlHostPreparation,
  beginInitialControlInstallation(originals,raw) {return owner.begin(originals,raw);},
  assertInitialControlInstallationCurrent(scope,originals) {return owner.assertCurrent(scope,originals);},
  readInitialControlInstallationInput(scope,originals) {return owner.readInput(scope,originals);},
  readInitialControlInstallationAsset(scope,originals,path) {return owner.readAsset(scope,originals,path);},
  prepareHostJournalInstallation: prepareJournal,
  assertHostJournalInstallationCurrent(original, originals) {journalCurrent(original, originals);},
  closeHostJournalInstallation(original, originals) {
    return closeJournal(journalOriginal(original, originals, true));
  },
  openHostJournalRequestJournal: openJournal,
  originalHostPublicationOwnership: journalPublicationOwnership,
  admitHostJournalRootFormat: admitJournalRootFormat,
  prepareSourceManagedInstallation: prepareSource,
  assertSourceManagedInstallationCurrent(original, originals) {sourceCurrent(original, originals);},
  beforeSourceSnapshot(original, originals, kind, input, options) {
    const entry = sourceCurrent(original, originals);
    if (entry.receipt !== undefined) sourceUnavailable();
    const receipt = freeze(Object.create(null));
    const producer = entry.receipt = {original: receipt, snapshot: undefined,
      body: undefined, request: undefined, finished: false};
    if (typeof state.runRequirements === 'function') {
      // The selected startup adopted the complete separate joint disposition
      // before its namespace loaded. Fix this one original BEFORE input and
      // Common preparation; a later typed claim only binds its original pair.
      producer.managedRun={original:freeze(Object.create(null)),entry,producer,
        claimed:false,derived:undefined,request:undefined,quotas:undefined,
        portsTaken:false,admitted:false,stopped:false,usage:undefined};
    }
    // First ownKeys/clone is covered by the separately declared Source phase,
    // not an initial-control credit or admission of the resulting DATA. Retain
    // the one attempt before this fallible read: rejection cannot refill it.
    try {
      producer.snapshot = apply(state.source.input, state.namespace,
        [kind, input, options, state.sourceEnvelope.inputLimits]);
      if (producer.snapshot.originalReferences.length !== 0) sourceUnavailable();
      sourceCurrent(original, originals);
      return receipt;
    } catch (cause) {
      sourceFailure(entry, cause);
      producer.finished = true;
      entry.closing = true;
      throw cause;
    }
  },
  bindSourceSnapshot(original, originals, receipt, body) {
    const entry = sourceCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    if (producer.body !== undefined || producer.finished || body === null ||
        typeof body !== 'object' || isProxy(body) || !Object.isFrozen(body) ||
        body.kind !== producer.snapshot.packet.kind || body.input !== producer.snapshot.packet.input) sourceUnavailable();
    producer.body = body;
  },
  bindSourceRequest(original, originals, receipt, body, request) {
    const entry = sourceCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    if (producer.body !== body || producer.request !== undefined || producer.finished ||
        request === null || typeof request !== 'object' || isProxy(request)) sourceUnavailable();
    // The receiving Host's fixed transform binding must later recover this
    // same original, rather than identifying a clone by fields or intent CID.
    producer.request = request;
  },
  sourceIntentCid(original, originals, receipt, body) {
    const entry = sourceCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    if (producer.body !== body || producer.finished) sourceUnavailable();
    const identity = apply(state.source.intent, state.namespace, [originals, original, body]);
    sourceCurrent(original, originals);
    return identity;
  },
  finishSourceProducer(original, originals, receipt, terminal) {
    const entry = sourceOriginal(original, originals, true), producer = sourceReceipt(entry, receipt);
    if (terminal !== 'returned' && terminal !== 'failed') sourceUnavailable();
    producer.finished = true;
    producer.snapshot = undefined;
    // Children retain their actual request/byte duties; producer settlement is
    // not their logical stop, physical FD close or returned backing credit.
  },
  closeSourceManagedInstallation(original, originals) {
    return closeSource(sourceOriginal(original, originals, true));
  },
  prepareSourceManagedRead: prepareSourceRead,
  prepareSourceManagedRun: claimManagedRun,
  prepareOriginalSourceChildPorts,
  prepareOriginalManagedRunPorts,
};
Object.setPrototypeOf(table,null);
// Same synchronous receiver handoff for the Host namespace while it loads;
// no callable table can pass assertPrefixCurrent until initialization closes.
freeze(table);
try {
  if (module.isPreloading !== false || processOriginal.execArgv.length !== 0 ||
      isMainThread !== true || threadId !== 0 ||
      processOriginal.env.NODE_OPTIONS !== undefined || processOriginal.version !== 'v22.22.0' ||
      processOriginal.platform !== 'darwin' || processOriginal.arch !== 'arm64' ||
      processOriginal.versions.openssl !== '3.5.4' || delivery === undefined ||
      delivery.filename !== join(dirname(delivery.filename),'initial-control-public-dispatch.cjs') ||
      require.cache[delivery.filename] !== delivery) unavailable();
  assertSupportedIntrinsics();
  // The actual prefix owns its fixed initialization and ordinary compiler
  // disposition before loading the generated inventory or covered images.
  const declaration = declareOrdinaryInitialControlPhaseEnvelope(getHeapStatistics().heap_size_limit);
  // Retain selected builtin constructor identities before namespace callbacks.
  // This is module/control custody only: no DatabaseSync is constructed and
  // no writable Journal capacity is issued by loading this builtin.
  const sqliteOriginal = require('node:sqlite');
  const journalNative = freeze({DatabaseSync:field(sqliteOriginal,'DatabaseSync'),
    StatementSync:field(sqliteOriginal,'StatementSync'),
    bindings:captureJournalNativeBindings(require('node:fs'),require('node:crypto'),
      require('node:fs/promises'))});
  if (typeof journalNative.DatabaseSync !== 'function' ||
      typeof journalNative.StatementSync !== 'function') unavailable();
  // Adopt the separate joint Source recipe before namespace, managed Source
  // metadata or raw SDK acquisition. This is not a second whole VM allowance.
  const sourceEnvelope = declareSourceManagedPhaseEnvelope(declaration);
  const sourceComputeEnvelope = declareSourceComputePhaseEnvelope(sourceEnvelope);
  const runtime = freeze({node:processOriginal.versions.node,v8:processOriginal.versions.v8,
    openssl:processOriginal.versions.openssl,platform:processOriginal.platform,arch:processOriginal.arch,
    eager:false,libraries:freeze({...processOriginal.versions})});
  const inventory = require('./initial-control-package-original.cjs').imageInventory;
  if (inventory === undefined) unavailable();
  const envelope = inspectOrdinaryInitialControlPhaseEnvelope(inventory,declaration,runtime);
  const consumerRequire = createRequire(processOriginal.argv[1]);
  // Actual installed consumer resolution must select this physical Local
  // package, not a source tree, copied helper or an equal foreign installation.
  if (dirname(consumerRequire.resolve('@actql/local-node')) !== localRoot) unavailable();
  let publicDeliveryEntry;
  if (delivery.filename !== join(localRoot,'initial-control-public-dispatch.cjs')) {
    const nodeRoot=dirname(consumerRequire.resolve('@actql/node'));
    if (delivery.filename !== join(nodeRoot,'initial-control-public-dispatch.cjs')) unavailable();
    publicDeliveryEntry=delivery.filename;
  } else if (delivery.parent?.filename !== undefined &&
      delivery.parent.filename.endsWith('/initial-control-public-dispatch.cjs')) {
    const nodeRoot=dirname(consumerRequire.resolve('@actql/node'));
    if (delivery.parent.filename !== join(nodeRoot,'initial-control-public-dispatch.cjs') ||
        require.cache[delivery.parent.filename] !== delivery.parent) unavailable();
    publicDeliveryEntry=delivery.parent.filename;
  }
  const images = require('./initial-control-package-custody.cjs')
    .captureOrdinaryInitialControlPackageCustody(inventory,localRoot,processOriginal.argv[1],publicDeliveryEntry);
  const namespace = images.initializeHostNamespace();
  const consumer = field(namespace,'connectInitialControlHostPreparation');
  const validator = field(namespace,'assertInitialControlHostPreparation');
  const reader = field(namespace,'readInitialControlHostInput');
  if ([consumer,validator,reader].some(value=>typeof value !== 'function')) unavailable();
  assertIntrinsicsCurrent();
  const source = {};
  for (const [name, exported] of Object.entries({prepare: 'prepareInstalledMockSourcePreparation',
    read: 'readInstalledMockPreparation', validator: 'assertSourceManagedHostPreparation',
    request: 'originalSourceManagedHostRequest', intent: 'sourceManagedSubmittedIntentCid',
    input: 'readSourceManagedOriginalInput'})) {
    const entry = descriptor(namespace, exported);
    source[name] = entry !== undefined && own(entry, 'value') ? entry.value : undefined;
  }
  freeze(source);
  const runRequirementProperty=descriptor(namespace,'readSourceManagedRunRequirements');
  const runRequirements=runRequirementProperty!==undefined&&own(runRequirementProperty,'value')
    ?runRequirementProperty.value:undefined;
  const journal = {};
  for (const [name, exported] of Object.entries({read: 'readHostJournalPreparation',
    open: 'openOriginalHostRequestJournal', observe: 'observeOriginalHostRequestJournalCustody',
    ownershipPrepare: 'prepareOriginalHostPublicationOwnership',
    ownershipCurrent: 'assertOriginalHostPublicationOwnershipCurrent',
    ownershipClose: 'closeOriginalHostPublicationOwnership',
    rootFormat: 'admitOriginalHostRootFormat',
    current: 'assertOriginalHostRequestJournalFacilityCurrent'})) {
    const entry = descriptor(namespace, exported);
    journal[name] = entry !== undefined && own(entry, 'value') ? entry.value : undefined;
  }
  freeze(journal);
  state = {declaration,runtime,envelope,sourceEnvelope,sourceComputeEnvelope,runRequirements,
    inventory,images,namespace,consumer,validator,reader,source,journal,journalNative,prefixIntrinsics,
    directoryNativeImageLoader:field(directoryNativeImage,'loadHostJournalDirectoryNative')};
} catch(cause) {
  // Keep original FD/namespace/compile failure and its close-only duty. A
  // failed prefix never becomes a second factory or a retrying image read.
  firstFailure = freeze({cause});
}
