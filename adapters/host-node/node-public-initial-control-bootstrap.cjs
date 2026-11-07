'use strict';

// Actual installed public-package prefix. This instance is constructed by its
// fixed delivery module, not by a caller's factory, receipt or options. It is
// deliberately separate from the preload recipe: no eager bytecode, preload
// ancestor, frozen-intrinsic history or earlier application work is claimed.
const {createRequire} = require('node:module');
const {join, dirname, isAbsolute} = require('node:path');
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
const {declareSourceManagedPhaseEnvelope,declareSourceComputePhaseEnvelope,
  declareSourceFreeManagedComputePhaseEnvelope} = require('./source-managed-phase-envelope.cjs');
const {declareHostJournalServiceRecipe} = require('./host-journal-service-recipe.cjs');
const {declareHostResultServiceRecipe, validOriginalResultPublicationExtent, facilityFields: resultFacilityFields}
  = require('./host-result-service-recipe.cjs');
const {declareHostLocalMockModelServiceRecipe}
  = require('./host-local-mock-model-service-recipe.cjs');
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
let managedComputeInstallation;
let journalInstallation;
let journalService;
let resultService, resultInstallation;
let localMockModelService;
const journalUnavailable = () => fail('HostJournalPreparationUnavailable');
const journalPromise = Promise, journalPromiseResolve = Promise.resolve;
const journalPromiseThen = Promise.prototype.then;

function beginJournalService(recipe, declaration, runtime) {
  // This private call is made only by this actual selected startup, before
  // its covered builtin/native or namespace work. Neither a returned native
  // receiver nor a caller's DATA packet can reconstruct the original later.
  if (journalService !== undefined || state !== undefined || firstFailure !== undefined ||
      recipe.sharedControl !== declaration || processOriginal !== process ||
      loadingModule !== require.cache[__filename] || delivery !== require.cache[delivery.filename]) {
    journalUnavailable();
  }
  const original = journalService = {recipe, declaration, runtime, process: processOriginal,
    module: loadingModule, delivery, phase: 'declared',
    sqlite: undefined, native: undefined, nativeOperations: undefined, facilities: undefined,
    os: undefined, tmpdir: undefined, temporaryDirectory: undefined,
    namespace: undefined, originals: undefined, disposition: undefined};
  // Bound the selected original environment before tmpdir's native/string
  // acquisition. Retain this choice before namespace callbacks; later ambient
  // environment changes cannot select another cold-copy/image directory.
  const environment = field(processOriginal, 'env');
  if (environment === null || typeof environment !== 'object' || isProxy(environment)) journalUnavailable();
  for (const name of ['TMPDIR', 'TMP', 'TEMP']) {
    const property = descriptor(environment, name);
    if (property !== undefined && (!own(property, 'value') ||
        typeof property.value !== 'string' || property.value.length > 4096)) journalUnavailable();
  }
  original.os = require('node:os');
  original.tmpdir = field(original.os, 'tmpdir');
  if (typeof original.tmpdir !== 'function' || isProxy(original.tmpdir)) journalUnavailable();
  const temporaryDirectory = apply(original.tmpdir, original.os, []);
  if (typeof temporaryDirectory !== 'string' || temporaryDirectory.length === 0 ||
      temporaryDirectory.length > 4096 || !isAbsolute(temporaryDirectory) ||
      temporaryDirectory.includes('\0')) journalUnavailable();
  original.temporaryDirectory = temporaryDirectory;
  return original;
}
function bindJournalServiceNative(original, sqlite, native, facilities) {
  if (original !== journalService || original.phase !== 'declared' ||
      field(sqlite, 'DatabaseSync') !== native.DatabaseSync ||
      field(sqlite, 'StatementSync') !== native.StatementSync) journalUnavailable();
  // The returned builtin originals complete the already admitted acquisition;
  // this does not turn constructor success into retrospective supply.
  original.sqlite = sqlite;
  original.native = native;
  original.nativeOperations = captureJournalServiceNativeOperations(native);
  original.facilities = facilities;
  original.phase = 'native-bound';
}
function captureJournalServiceNativeOperations(native) {
  const database = field(native.DatabaseSync, 'prototype');
  const statement = field(native.StatementSync, 'prototype');
  if (isProxy(native.DatabaseSync) || isProxy(native.StatementSync) ||
      database === null || typeof database !== 'object' || isProxy(database) ||
      statement === null || typeof statement !== 'object' || isProxy(statement)) journalUnavailable();
  const selected = [[database, 'open'], [database, 'close'], [database, 'prepare'],
    [database, 'exec'], [statement, 'get'], [statement, 'run'], [statement, 'iterate']];
  const operations = [];
  for (let index = 0; index < selected.length; index++) {
    const [receiver, name] = selected[index];
    const property = descriptor(receiver, name);
    if (property === undefined || !own(property, 'value') ||
        typeof property.value !== 'function' || isProxy(property.value)) journalUnavailable();
    operations[index] = freeze({receiver, name, property: freeze(property)});
  }
  return freeze({database, statement, operations: freeze(operations)});
}
function assertJournalServiceNativeCurrent(original) {
  const native = original.native, held = original.nativeOperations;
  if (field(original.sqlite, 'DatabaseSync') !== native.DatabaseSync ||
      field(original.sqlite, 'StatementSync') !== native.StatementSync ||
      field(native.DatabaseSync, 'prototype') !== held.database ||
      field(native.StatementSync, 'prototype') !== held.statement) journalUnavailable();
  for (let index = 0; index < held.operations.length; index++) {
    const operation = held.operations[index], before = operation.property;
    const current = descriptor(operation.receiver, operation.name);
    if (current === undefined || current.value !== before.value ||
        current.get !== before.get || current.set !== before.set ||
        current.writable !== before.writable || current.configurable !== before.configurable ||
        current.enumerable !== before.enumerable) journalUnavailable();
  }
}
function bindJournalServiceNamespace(original, namespace, journal) {
  if (original !== journalService || original.phase !== 'native-bound') journalUnavailable();
  // Small component namespaces can omit the Journal. They retain only their
  // original initial-control qualification; no partial Journal is issued.
  if (Object.values(journal).some(value => typeof value !== 'function')) return undefined;
  // Compare against the pre-namespace capture, not only the namespace's own
  // later baseline. Constructor equality alone cannot preserve method originals.
  assertJournalServiceNativeCurrent(original);
  if (apply(journal.current, namespace,
    [original.native.DatabaseSync, original.native.StatementSync, original.native.bindings]) !== undefined) {
    journalUnavailable();
  }
  assertJournalServiceNativeCurrent(original);
  const temporaryDirectory = original.temporaryDirectory;
  original.namespace = namespace;
  const recipe = original.recipe;
  const disposition = freeze({serviceOriginal: original,
    ownershipBounds: recipe.ownershipBounds,
    ownershipDirectoryLimits: recipe.ownershipDirectoryLimits,
    rootFormatDirectoryLimits: recipe.rootFormatDirectoryLimits,
    directoryImageLimits: freeze({...recipe.directoryLimits, temporaryDirectory}),
    argumentsForOriginalJournal(subject, options, inspection, temporary) {
      const entry = journalInstallation;
      if (this !== disposition || entry === undefined || entry.disposition !== disposition ||
          entry.subject !== subject || entry.directoryInspection !== inspection ||
          temporary !== temporaryDirectory) journalUnavailable();
      assertJournalServiceCurrent(original);
      return recipe.selectArguments(options, inspection, temporaryDirectory, entry.serviceCurrent);
    }});
  original.disposition = disposition;
  original.phase = 'bound';
  return disposition;
}
function assertJournalServiceCurrent(original) {
  if (original !== journalService) journalUnavailable();
  try {
    if (original.phase !== 'bound' || state?.journalService !== original ||
        state.journalDisposition !== original.disposition || state.journalNative !== original.native ||
        state.namespace !== original.namespace || state.journalServiceRecipe !== original.recipe ||
        state.declaration !== original.declaration || state.runtime !== original.runtime ||
        original.process !== processOriginal || original.module !== loadingModule ||
        original.delivery !== delivery || field(original.os, 'tmpdir') !== original.tmpdir) journalUnavailable();
    assertPrefixCurrent();
    assertJournalServiceNativeCurrent(original);
  } catch (cause) {
    original.phase = 'retiring';
    throw cause;
  }
}

const resultUnavailable = () => fail('HostResultPublicationUnavailable');
const localMockModelUnavailable = () => fail('LocalMockModelPreparationUnavailable');
function beginLocalMockModelService(recipe, journal, result, runtime) {
  if (localMockModelService !== undefined || state !== undefined ||
      journal !== journalService || result !== resultService ||
      recipe.sharedControl !== journal.declaration || recipe.result !== result.recipe ||
      recipe.sourceCompute !== result.recipe.sourceCompute || journal.runtime !== runtime) {
    localMockModelUnavailable();
  }
  // The selected startup retains the actual stock clock before namespace or
  // Model callbacks. This is not caller clock DATA or trusted-now authority.
  const dateProperty = descriptor(globalThis, 'Date');
  const date = dateProperty?.value, prototype = descriptor(date, 'prototype');
  const iso = prototype?.value === undefined ? undefined : descriptor(prototype.value, 'toISOString');
  if (typeof date !== 'function' || isProxy(date) || typeof iso?.value !== 'function' ||
      isProxy(iso.value) || apply(intrinsicSource, date, []) !== 'function Date() { [native code] }' ||
      apply(intrinsicSource, iso.value, []) !== 'function toISOString() { [native code] }') {
    localMockModelUnavailable();
  }
  return localMockModelService = {recipe, journal, result, runtime,
    process: processOriginal, module: loadingModule, delivery, phase: 'declared',
    dateProperty: freeze(dateProperty), date, prototype: freeze(prototype), iso: freeze(iso),
    namespace: undefined, callbacks: undefined};
}
function bindLocalMockModelServiceNamespace(original, namespace) {
  if (original !== localMockModelService || original.phase !== 'declared') localMockModelUnavailable();
  const requirements = descriptor(namespace, 'readHostLocalMockModelRunRequirements');
  const current = descriptor(namespace, 'assertHostLocalMockModelRunCurrent');
  // A namespace without the actual semantic/current/custody consumer cannot
  // receive a Model service by borrowing its Source/Compute qualification.
  if ([requirements, current].some(property => property === undefined || !own(property, 'value') ||
      typeof property.value !== 'function')) return;
  original.namespace = namespace;
  original.callbacks = freeze({requirements: requirements.value, current: current.value});
  original.phase = 'bound';
}
function assertLocalMockModelServiceCurrent(original, held) {
  if (original !== localMockModelService) localMockModelUnavailable();
  try {
    if (original.phase !== 'bound' || state?.localMockModelService !== original ||
        state.localMockModelServiceRecipe !== original.recipe || state.runtime !== original.runtime ||
        state.namespace !== original.namespace || original.process !== processOriginal ||
        original.module !== loadingModule || original.delivery !== delivery) localMockModelUnavailable();
    assertSamePreparation(held);
    assertJournalServiceCurrent(original.journal);
    if (original.result !== resultService || original.recipe.result !== original.result.recipe) localMockModelUnavailable();
    const journal = journalCurrent(journalInstallation?.original, held);
    if (journal.journal === undefined || journal.ownership === undefined) localMockModelUnavailable();
    const date = descriptor(globalThis, 'Date'), prototype = descriptor(original.date, 'prototype');
    const iso = descriptor(original.prototype.value, 'toISOString');
    for (const [actual, expected] of [[date, original.dateProperty], [prototype, original.prototype], [iso, original.iso]]) {
      if (actual === undefined || actual.value !== expected.value || actual.get !== expected.get ||
          actual.set !== expected.set || actual.writable !== expected.writable ||
          actual.enumerable !== expected.enumerable || actual.configurable !== expected.configurable) {
        localMockModelUnavailable();
      }
    }
  } catch (cause) {
    original.phase = 'retiring';
    throw cause;
  }
}
function localMockModelNow(held) {
  const original = localMockModelService;
  assertLocalMockModelServiceCurrent(original, held);
  return apply(original.iso.value, new original.date(), []);
}
function beginResultService(recipe, journal, runtime) {
  if (resultService !== undefined || state !== undefined || journal !== journalService ||
      recipe.sharedControl !== journal.declaration || recipe.journal !== journal.recipe ||
      journal.runtime !== runtime) resultUnavailable();
  return resultService = {recipe, journal, runtime, process: processOriginal,
    module: loadingModule, delivery, phase: 'declared', facilities: undefined,
    bindings: undefined, namespace: undefined, callbacks: undefined, originals: undefined};
}
function bindResultServiceFacilities(original, facilities) {
  if (original !== resultService || original.phase !== 'declared') resultUnavailable();
  const receivers = {promises: facilities.promises, crypto: facilities.crypto, buffer: Buffer};
  const bindings = Object.create(null);
  for (const group of Object.keys(resultFacilityFields)) {
    const values = Object.create(null);
    for (const name of resultFacilityFields[group]) {
      const value = field(receivers[group], name);
      if (typeof value !== 'function' || isProxy(value)) resultUnavailable();
      values[name] = value;
    }
    bindings[group] = freeze(values);
  }
  original.facilities = freeze(receivers);
  original.bindings = freeze(bindings);
  // The SDK's original Result reader uses global WebCrypto before its first
  // Host request. Bind that SAME stock singleton and callback before namespace
  // code/reader acquisition, not only node:crypto's different randomUUID.
  const globalCrypto = descriptor(globalThis, 'crypto');
  const webcrypto = facilities.crypto.webcrypto;
  if (globalCrypto === undefined || typeof globalCrypto.get !== 'function' ||
      isProxy(globalCrypto.get) || apply(intrinsicSource, globalCrypto.get, []) !==
      'function get() {\n      if (check !== undefined) {\n        FunctionPrototypeCall(check, this);\n      }\n      if (setterCalled) {\n        return value;\n      }\n      mod ??= require(id);\n      value ??= mod[key];\n      return value;\n    }' ||
      apply(globalCrypto.get, globalThis, []) !== webcrypto) resultUnavailable();
  const prototype = Object.getPrototypeOf(webcrypto);
  const randomUUID = field(prototype, 'randomUUID');
  if (typeof randomUUID !== 'function' || isProxy(randomUUID)) resultUnavailable();
  original.webcrypto = freeze({global: freeze(globalCrypto), value: webcrypto, prototype, randomUUID});
  original.phase = 'native-bound';
}
function bindResultServiceNamespace(original, namespace) {
  if (original !== resultService || original.phase !== 'native-bound') resultUnavailable();
  const callbacks = Object.create(null);
  for (const [name, exported] of Object.entries({open: 'openOriginalHostPublicationStore',
    current: 'assertOriginalHostPublicationStoreFacilityCurrent',
    read: 'readHostResultPublicationPreparation',
    requirements: 'readHostResultPublicationRunRequirements'})) {
    const property = descriptor(namespace, exported);
    callbacks[name] = property !== undefined && own(property, 'value') ? property.value : undefined;
  }
  // Component-only namespaces can omit Result. They do not receive a partial
  // Result service, nor does their Journal qualification supply this purpose.
  if (Object.values(callbacks).some(value => typeof value !== 'function')) return;
  apply(callbacks.current, namespace, [original.bindings]);
  original.namespace = namespace;
  original.callbacks = freeze(callbacks);
  original.phase = 'bound';
}
function assertResultServiceCurrent(original) {
  if (original !== resultService) resultUnavailable();
  try {
    if (original.phase !== 'bound' || state?.resultService !== original ||
        state.resultServiceRecipe !== original.recipe || state.namespace !== original.namespace ||
        state.runtime !== original.runtime || original.process !== processOriginal ||
        original.module !== loadingModule || original.delivery !== delivery) resultUnavailable();
    assertJournalServiceCurrent(original.journal);
    const crypto = original.webcrypto, globalCrypto = descriptor(globalThis, 'crypto');
    if (globalCrypto === undefined || globalCrypto.get !== crypto.global.get ||
        globalCrypto.set !== crypto.global.set || globalCrypto.value !== crypto.global.value ||
        apply(crypto.global.get, globalThis, []) !== crypto.value ||
        Object.getPrototypeOf(crypto.value) !== crypto.prototype ||
        field(crypto.prototype, 'randomUUID') !== crypto.randomUUID) resultUnavailable();
    for (const group of Object.keys(resultFacilityFields)) for (const name of resultFacilityFields[group]) {
      if (field(original.facilities[group], name) !== original.bindings[group][name]) resultUnavailable();
    }
    apply(original.callbacks.current, original.namespace, [original.bindings]);
  } catch (cause) {original.phase = 'retiring'; throw cause;}
}
function resultOriginal(original, held, closing = false) {
  const entry = resultInstallation;
  if (entry === undefined || entry.original !== original || entry.originals !== held ||
      (!closing && (entry.closed || entry.closing))) resultUnavailable();
  return entry;
}
function resultCurrent(original, held) {
  const entry = resultOriginal(original, held);
  try {
    assertSamePreparation(held);
    assertResultServiceCurrent(entry.service);
    const journal = journalCurrent(entry.journal.original, held);
    if (journal !== entry.journal || journal.journal === undefined ||
        journal.ownership !== entry.ownership || field(entry.subject, 'root') !== journal.paths.root ||
        field(entry.subject, 'principalId') !== journal.paths.principalId ||
        field(entry.subject, 'runtime') !== field(held.installation, 'projectRuntime')) resultUnavailable();
    return entry;
  } catch (cause) {entry.closing = true; entry.failure ??= cause; throw cause;}
}
function resultStatus(entry) {
  return freeze({pending: !entry.closed, storePending: entry.store !== undefined,
    constructorCleanupPending: entry.cleanup !== undefined || entry.unknownCleanup,
    physicalBackingReleased: false});
}
function closeResult(entry) {
  if (entry.closed) return apply(journalPromiseResolve, journalPromise, [entry.closedObservation]);
  entry.closing = true;
  if (entry.closeFlight !== undefined) return entry.closeFlight;
  const flight = apply(journalPromiseThen, apply(journalPromiseResolve, journalPromise, []), [async () => {
    try {
      if (entry.openFlight !== undefined) {try {await entry.openFlight;} catch {}}
      if (entry.unknownCleanup) return resultStatus(entry);
      if (entry.cleanup !== undefined) {
        if (!journalAcknowledged(apply(entry.cleanupStatus, entry.cleanup, []))) {
          await apply(entry.cleanupRetry, entry.cleanup, []);
        }
        if (!journalAcknowledged(apply(entry.cleanupStatus, entry.cleanup, []))) return resultStatus(entry);
        entry.cleanup = entry.cleanupStatus = entry.cleanupRetry = undefined;
      }
      if (entry.store !== undefined) {
        // This exact Store's close/status are independent of Journal, source
        // and parent scope ACKs. No current check is needed to finish cleanup.
        if (field(apply(entry.storeStatus, entry.store, []), 'closed') !== true) {
          await apply(entry.storeClose, entry.store, []);
        }
        if (field(apply(entry.storeStatus, entry.store, []), 'closed') !== true) return resultStatus(entry);
        entry.store = entry.storeClose = entry.storeStatus = undefined;
      }
      entry.closed = true;
      entry.ownership = entry.journal = entry.candidate = entry.subject = undefined;
      // The failure carrier and the returned view can observe the SAME
      // completed duty. Keep its actual original ACK, not a second close or a
      // revived current admission when one observer finished cleanup first.
      entry.closedObservation = resultStatus(entry);
      return entry.closedObservation;
    } catch (cause) {entry.failure ??= cause; return resultStatus(entry);}
  }]);
  entry.closeFlight = flight;
  const settled = () => {if (entry.closeFlight === flight) entry.closeFlight = undefined;};
  apply(journalPromiseThen, flight, [settled, settled]);
  return flight;
}
function resultCarrier(entry, cause) {
  entry.failure ??= cause; entry.closing = true;
  const carrier = new Error('HostResultPublicationCleanupPending', {cause});
  carrier.code = 'HostResultPublicationCleanupPending';
  carrier.cleanupHandle = freeze({status: () => resultStatus(entry), retry: () => closeResult(entry)});
  return carrier;
}
function prepareResult(held) {
  assertSamePreparation(held);
  assertResultServiceCurrent(state.resultService);
  if (resultInstallation !== undefined || state.resultService.originals !== undefined ||
      journalInstallation?.originals !== held || journalInstallation.closed || journalInstallation.closing ||
      journalInstallation.journal === undefined || journalInstallation.ownership === undefined) resultUnavailable();
  const journal = journalCurrent(journalInstallation.original, held);
  state.resultService.originals = held;
  const entry = resultInstallation = {original: freeze(Object.create(null)), originals: held,
    service: state.resultService, journal, ownership: journal.ownership, subject: undefined,
    openAttempted: false, openFlight: undefined, store: undefined, storeClose: undefined, storeStatus: undefined,
    runAttempted: false, candidate: undefined, failure: undefined,
    cleanup: undefined, cleanupStatus: undefined, cleanupRetry: undefined, unknownCleanup: false,
    closing: false, closed: false, closeFlight: undefined};
  entry.current = () => resultCurrent(entry.original, held);
  // Each Store operation still checks this SAME live owner. Actual object,
  // inventory, durable byte/debt and pending-I/O limits belong to that Store;
  // a historical number of current checks is not a lifetime resource quota.
  entry.storeCurrent = () => void resultCurrent(entry.original, held);
  try {
    entry.subject = apply(entry.service.callbacks.read, entry.service.namespace, [held]);
    resultCurrent(entry.original, held);
  } catch (cause) {throw resultCarrier(entry, cause);}
  return entry.original;
}
function openResultStore(original, held, options, control) {
  const entry = resultCurrent(original, held);
  if (entry.openAttempted) resultUnavailable();
  entry.openAttempted = true;
  const flight = apply(journalPromiseThen, apply(journalPromiseResolve, journalPromise, []), [async () => {
    try {
      resultCurrent(original, held);
      const selected = entry.service.recipe.selectStoreArguments(options, join(entry.journal.paths.root, 'publication'));
      if (selected.storeAuthorityCid !== field(entry.subject, 'storeAuthorityCid') ||
          control !== field(entry.subject, 'control')) resultUnavailable();
      const store = await apply(entry.service.callbacks.open, entry.service.namespace,
        [selected, control, undefined, undefined, entry.ownership, entry.storeCurrent]);
      // Retain before the first post-constructor read/current callback.
      entry.store = store;
      entry.storeClose = field(store, 'close');
      entry.storeStatus = field(store, 'status');
      if (typeof entry.storeClose !== 'function' || typeof entry.storeStatus !== 'function') resultUnavailable();
      resultCurrent(original, held);
      return store;
    } catch (cause) {
      try {journalCleanup(entry, cause);} catch {entry.unknownCleanup = true;}
      const pending = cause !== null && typeof cause === 'object' ? descriptor(cause, 'cleanupPending') : undefined;
      if (pending !== undefined && (!own(pending, 'value') || pending.value === true && entry.cleanup === undefined)) {
        entry.unknownCleanup = true;
      }
      throw resultCarrier(entry, cause);
    }
  }]);
  entry.openFlight = flight;
  return flight;
}
function beforeResultOperation(original, held, operation) {
  resultCurrent(original, held);
  if (typeof operation !== 'string' || operation.length > 128) resultUnavailable();
}
function beforeResultRead(held, schemaOrOptions, options) {
  if (resultInstallation?.originals !== held) resultUnavailable();
  resultCurrent(resultInstallation.original, held);
  // The SDK captures selected row/transfer/collection limits and charges the
  // original decoded row before retaining all() or invoking a validator. Do
  // not read getters or replace that policy with absent-options-only support.
  // Each actual Reader retains its original attempt and pending cleanup; this
  // current check grants neither a new Run nor a refund of any live debt.
}
function admitResultRun(original, held, prepared) {
  const entry = resultCurrent(original, held);
  const run = managedComputeInstallation?.receipt?.managedRun ?? sourceInstallation?.receipt?.managedRun;
  if (run === undefined || run.derived !== prepared || run.entry.originals !== held || !run.admitted) resultUnavailable();
  managedRunCurrent(run);
  if (entry.runAttempted) {
    if (entry.candidate?.prepared !== prepared || entry.candidate.run !== run) resultUnavailable();
    return;
  }
  entry.runAttempted = true;
  const required = apply(entry.service.callbacks.requirements, entry.service.namespace, [held, prepared]);
  const results = field(required, 'resultCount'), rows = field(required, 'maxRows');
  if (!validOriginalResultPublicationExtent(results, rows, field(required, 'maxContractBytes'), 1) ||
      results > entry.service.recipe.result.maxResults) resultUnavailable();
  resultCurrent(original, held);
  managedRunCurrent(run);
  entry.candidate = freeze({prepared, run, results, rows});
}

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
    if (state.journalService !== undefined) assertJournalServiceCurrent(state.journalService);
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
  if (state.journalService !== undefined) {
    assertJournalServiceCurrent(state.journalService);
    if (state.journalService.originals !== undefined) journalUnavailable();
    state.journalService.originals = held;
  }
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
  entry.serviceCurrent = () => journalCurrent(original, held);
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
  // Native StatementSync::Iterate performs these JS reads before returning
  // the cursor. Refuse accessors/proxies without entering their callbacks.
  const iteratorOriginal = field(globalThis, 'Iterator');
  if (typeof iteratorOriginal !== 'function' || isProxy(iteratorOriginal)) unavailable();
  const iteratorPrototype = field(iteratorOriginal, 'prototype');
  if (iteratorPrototype === null || typeof iteratorPrototype !== 'object' ||
      isProxy(iteratorPrototype)) unavailable();
  const bindings = Object.create(null);
  for (const [group,receiver] of [['fs',fsOriginal],['crypto',cryptoOriginal],
    ['promises',fsPromisesOriginal],
    ['iteratorGlobal',globalThis],['iteratorConstructor',iteratorOriginal],
    ['constants',field(fsOriginal,'constants')],
    ['directory',field(field(fsOriginal,'Dir'),'prototype')],
    ['realpath',field(fsOriginal,'realpathSync')],
    ['hash',field(field(cryptoOriginal,'Hash'),'prototype')],
    ['hmac',field(field(cryptoOriginal,'Hmac'),'prototype')]]) {
    const values = Object.create(null);
    for (const name of journalFacilityFields[group]) {
      const value = field(receiver,name);
      if (typeof value !== (group === 'constants' ? 'number' :
          group === 'iteratorConstructor' ? 'object' : 'function')) unavailable();
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
// Compare only the bounded, already captured DATA projection. The original
// receipt/installation and later body/request pointer lineage remain nominal;
// equal DATA alone can never create a producer or grant a child.
function sameSourceData(left, right) {
  if (Object.is(left, right)) return true;
  if (left === null || right === null || typeof left !== 'object' || typeof right !== 'object') return false;
  const keys = Reflect.ownKeys(left), other = Reflect.ownKeys(right);
  if (keys.length !== other.length) return false;
  for (let index = 0; index < keys.length; index++) {
    const name = keys[index];
    if (!own(right, name) || !sameSourceData(left[name], right[name])) return false;
  }
  return true;
}
function optionalSourceData(value, name) {
  const property = descriptor(value, name);
  if (property === undefined) return undefined;
  if (!own(property, 'value')) sourceUnavailable();
  return property.value;
}
function sourceSubmissionProjection(entry, producer, body) {
  if (producer.finished || producer.snapshot === undefined || body === null ||
      typeof body !== 'object' || isProxy(body)) sourceUnavailable();
  const limits = entry.envelope?.inputLimits ?? state.sourceEnvelope.inputLimits;
  // This SAME Source/Compute phase covers the reader's traversal and copies;
  // using the initial reader function does not import initial-control credit.
  const captured = apply(state.reader, state.namespace, [body, limits]);
  if (captured.originalReferences.length !== 0) sourceUnavailable();
  const pending = [body];
  for (let index = 0; index < pending.length; index++) {
    const original = pending[index];
    if (!Object.isFrozen(original)) sourceUnavailable();
    for (const name of Reflect.ownKeys(original)) {
      const value = field(original, name);
      if (value !== null && typeof value === 'object' && !pending.includes(value)) {
        if (pending.length === limits.maxNodes) sourceUnavailable();
        pending[pending.length] = value;
      }
    }
  }
  const packet = producer.snapshot.packet, actual = captured.packet;
  const options = packet.options ?? Object.create(null);
  const option = name => optionalSourceData(options, name);
  if (field(actual, 'kind') !== packet.kind || !sameSourceData(field(actual, 'parameters'), option('parameters') ?? null) ||
      optionalSourceData(actual, 'readOnly') !== option('readOnly') ||
      optionalSourceData(actual, 'stopBefore') !== option('stopBefore') ||
      !sameSourceData(optionalSourceData(actual, 'unresolvedHistory'), option('unresolvedHistory'))) sourceUnavailable();
  const allowed = ['submissionRef', 'attemptRef', 'kind', 'input', 'parameters',
    'readOnly', 'stopBefore', 'unresolvedHistory'];
  for (const name of Reflect.ownKeys(actual)) if (!allowed.includes(name)) sourceUnavailable();
  if (option('submissionRef') !== undefined && !sameSourceData(optionalSourceData(actual, 'submissionRef'), option('submissionRef')) ||
      option('attemptId') !== undefined && optionalSourceData(field(actual, 'attemptRef'), 'attemptId') !== option('attemptId')) sourceUnavailable();
  if (packet.kind === 'aql') {
    const expected = {text: packet.input, format: option('format')};
    if (option('parameterDeclarations') !== undefined) expected.parameterDeclarations = option('parameterDeclarations');
    if (!sameSourceData(field(actual, 'input'), expected)) sourceUnavailable();
  } else if (packet.kind !== 'program' || !sameSourceData(field(actual, 'input'), packet.input)) sourceUnavailable();
  return captured;
}
function bindSourceSubmission(entry, receipt, body) {
  const producer = sourceReceipt(entry, receipt);
  if (producer.body !== undefined) sourceUnavailable();
  producer.boundSnapshot = sourceSubmissionProjection(entry, producer, body);
  producer.body = body;
}
function currentSourceSubmission(entry, producer, body) {
  if (producer.body !== body || producer.finished) sourceUnavailable();
  const captured = sourceSubmissionProjection(entry, producer, body);
  if (!sameSourceData(captured.packet, producer.boundSnapshot.packet)) sourceUnavailable();
}
function beforeSourceQuery(original, held, format, text, parameters, options, compute) {
  if (compute) managedComputeCurrent(original, held);
  else sourceCurrent(original, held);
  // The initial supported public query has no external options/parameter
  // graph. Refuse that unsupported backing BEFORE any getter/ownKeys; never
  // silently discard a valid option or manufacture another admission.
  if (options !== undefined || parameters !== undefined && parameters !== null ||
      typeof text !== 'string' || !['sql', 'aql', 'aql-text'].includes(format)) sourceUnavailable();
  const selected = freeze({format, parameters: null, readOnly: true});
  return compute ? beforeManagedComputeSnapshot(original, held, 'aql', text, selected) :
    table.beforeSourceSnapshot(original, held, 'aql', text, selected);
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
      heldBytes, reservedRetention, reservedExecution, peakRetention, reservedAttempts, liveReservations, liveDelegations) {
      // Core supplies this usage; these counters never acknowledge the FD or
      // return the actual process-lived response ArrayBuffers to a sibling.
      if (!child.admitted || child.stopped || ![planning, attempts, holdings, reservedAttempts, liveReservations, liveDelegations].every(Number.isSafeInteger) ||
          planning < 0 || attempts < 0 || holdings < 0 || reservedAttempts < 0 || liveReservations < 0 || liveDelegations < 0 ||
          [planning, attempts, holdings, reservedAttempts, liveReservations, liveDelegations].some(value => value > 2147483647) || BigInt(planning) > quotas[0] ||
          BigInt(attempts) + BigInt(reservedAttempts) > quotas[1] || BigInt(holdings) > quotas[2] ||
          ![transferred, uncertain, reservedTransfer, heldBytes, reservedRetention, reservedExecution, peakRetention]
            .every(value => typeof value === 'bigint' && value >= 0n) ||
          transferred + uncertain + reservedTransfer > quotas[3] ||
          heldBytes + reservedRetention > quotas[4] || peakRetention > quotas[4] || reservedExecution > quotas[5]) return -42;
      child.usage = freeze({planning, attempts, holdings, transferred, uncertain, reservedTransfer,
        heldBytes, reservedRetention, reservedExecution, peakRetention, reservedAttempts, liveReservations, liveDelegations});
      return 0;
    },
  });
}
function managedComputeOriginal(original, held, allowClosing = false) {
  const entry = managedComputeInstallation;
  if (entry === undefined || entry.original !== original || entry.originals !== held ||
      entry.closed || (!allowClosing && entry.closing)) sourceUnavailable();
  return entry;
}
function managedComputeCurrent(original, held) {
  const entry = managedComputeOriginal(original, held);
  try {
    assertSamePreparation(held);
    if (entry.envelope !== state.managedComputeEnvelope ||
        entry.envelope.controlDeclaration !== state.declaration ||
        entry.envelope.sourceOccurrences !== 0 || entry.requestService !== state.journalService ||
        entry.requestService?.originals !== held || journalInstallation?.originals !== held ||
        journalInstallation.closing || journalInstallation.closed ||
        journalInstallation.journal === undefined) sourceUnavailable();
    // SDK request/control UUID/epoch work uses this SAME separately supplied
    // facility. Managed Compute itself supplies no native crypto or Journal.
    assertJournalServiceCurrent(entry.requestService);
    apply(state.compute.validator, state.namespace, [held]);
    return entry;
  } catch (cause) {
    sourceFailure(entry, cause); entry.closing = true;
    throw cause;
  }
}
function prepareManagedCompute(held) {
  assertSamePreparation(held);
  if (managedComputeInstallation !== undefined || state.compute === undefined ||
      Object.values(state.compute).some(value => typeof value !== 'function') ||
      state.managedComputeEnvelope?.sourceOccurrences !== 0 ||
      state.journalService?.originals !== held || journalInstallation?.originals !== held ||
      journalInstallation.closing || journalInstallation.closed ||
      journalInstallation.journal === undefined) sourceUnavailable();
  assertJournalServiceCurrent(state.journalService);
  // This separate purpose has no Source bundle, FD or response backings.
  // It shares the selected runtime original, not an initial/Source allowance.
  const original = freeze(Object.create(null));
  const entry = managedComputeInstallation = {original, originals: held,
    envelope: state.managedComputeEnvelope, requestService: state.journalService, bundle: undefined,
    closing: false, closed: false, children: [], receipt: undefined,
    file: undefined, openFlight: undefined, closeFlight: undefined,
    firstError: undefined, latestError: undefined, backingUnknown: false};
  try { managedComputeCurrent(original, held); return original; }
  catch (cause) {
    const carrier = new Error('ManagedComputeInstallationCleanupPending', {cause});
    carrier.code = 'ManagedComputeInstallationCleanupPending';
    carrier.cleanupHandle = freeze({status: () => sourceStatus(entry), retry: () => closeSource(entry)});
    throw carrier;
  }
}
function beforeManagedComputeSnapshot(original, held, kind, input, options) {
  const entry = managedComputeCurrent(original, held);
  if (entry.receipt !== undefined) sourceUnavailable();
  const receipt = freeze(Object.create(null));
  const producer = entry.receipt = {original: receipt, snapshot: undefined,
    body: undefined, request: undefined, finished: false};
  // The actual original exists BEFORE SDK traversal/clone and Common
  // preparation. A later typed claim binds this original; it cannot issue it.
  producer.managedRun = {original: freeze(Object.create(null)), entry, producer,
    claimed: false, derived: undefined, request: undefined, quotas: undefined,
    portsTaken: false, admitted: false, stopped: false, usage: undefined};
  try {
    producer.snapshot = apply(state.compute.input, state.namespace,
      [kind, input, options, entry.envelope.inputLimits]);
    if (producer.snapshot.originalReferences.length !== 0) sourceUnavailable();
    managedComputeCurrent(original, held);
    return receipt;
  } catch (cause) {
    sourceFailure(entry, cause); producer.finished = true; entry.closing = true;
    throw cause;
  }
}
function claimManagedComputeRun(original, held, derived) {
  const entry = managedComputeCurrent(original, held), producer = entry.receipt;
  if (producer === undefined || producer.finished || producer.managedRun?.claimed) sourceUnavailable();
  const request = apply(state.compute.request, state.namespace, [held, derived]);
  if (producer.request !== request) sourceUnavailable();
  const run = producer.managedRun;
  run.claimed = true; run.derived = derived; run.request = request; run.purpose = 'source-compute';
  try {
    const required = apply(state.compute.requirements, state.namespace, [held, derived]);
    const names = ['planningWork', 'attempts', 'holdings', 'transferBytes', 'retainedBytes', 'executionBytes'];
    if (required === null || typeof required !== 'object' || isProxy(required) ||
        !Object.isFrozen(required)) sourceUnavailable();
    const quotas = [];
    for (let index = 0; index < names.length; index++) {
      const name = names[index], property = descriptor(required, name);
      if (property === undefined || !own(property, 'value')) sourceUnavailable();
      const value = property.value;
      if (index < 3 ? !Number.isSafeInteger(value) || value < 0 || value > 2147483647 :
          typeof value !== 'bigint' || value < 0n) sourceUnavailable();
      const amount = BigInt(value);
      if (amount > BigInt(entry.envelope.limits[name])) sourceUnavailable();
      appendSourceOriginal(quotas, amount);
    }
    run.quotas = freeze(quotas);
    managedRunCurrent(run);
    return run.original;
  } catch (cause) {
    sourceFailure(entry, cause); entry.closing = true;
    throw cause;
  }
}
function managedRunCurrent(run) {
  const entry = run.entry === managedComputeInstallation
    ? managedComputeCurrent(run.entry.original,run.entry.originals)
    : sourceCurrent(run.entry.original,run.entry.originals);
  if (run.entry !== entry || entry.receipt !== run.producer ||
      run.producer.managedRun !== run || run.stopped ||
      run.request !== run.producer.request || run.derived === undefined) sourceUnavailable();
  if (run.purpose === 'local-mock-model') {
    assertLocalMockModelServiceCurrent(run.modelService, entry.originals);
    const observation = apply(run.modelService.callbacks.current, state.namespace,
      [entry.originals, run.derived, run.modelCandidate]);
    if (observation !== undefined) localMockModelUnavailable();
  }
}
function claimManagedRun(original,held,derived) {
  const entry = sourceCurrent(original,held), request = assertSourceRequest(entry,derived);
  const run = entry.receipt.managedRun;
  if (run === undefined || run.claimed) sourceUnavailable();
  // This is a claim of the pre-snapshot original, not a late Compute issuer.
  // Retain the exact opaque prepared/request pointers before the fixed Owner's
  // fallible sizing/current fences. A failure never issues another original.
  run.claimed = true;run.derived = derived;run.request = request;run.purpose = 'source-compute';
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
function claimLocalMockModelRun(original, held, derived, candidate) {
  // The request original can belong to a Source-bearing or source-free Host.
  // Neither original supplies Model capacity: the separately selected service
  // below must bind this SAME request and semantic candidate before use.
  const entry = sourceInstallation?.original === original ? sourceCurrent(original, held) :
    managedComputeCurrent(original, held);
  const request = entry === sourceInstallation ? assertSourceRequest(entry, derived) :
    apply(state.compute.request, state.namespace, [held, derived]);
  if (entry.receipt?.request !== request) localMockModelUnavailable();
  const run = entry.receipt.managedRun;
  if (run === undefined || run.claimed) localMockModelUnavailable();
  assertLocalMockModelServiceCurrent(localMockModelService, held);
  // One original parent, consumed before the fixed semantic Owner's fallible
  // projection. The candidate itself is not an issuer or self-authentication.
  run.claimed = true; run.derived = derived; run.request = request;
  run.purpose = 'local-mock-model'; run.modelCandidate = candidate;
  run.modelService = localMockModelService;
  try {
    const required = apply(localMockModelService.callbacks.requirements, state.namespace,
      [held, derived, candidate, localMockModelService.recipe]);
    const names = ['planningWork', 'attempts', 'holdings', 'transferBytes', 'retainedBytes', 'executionBytes'];
    if (required === null || typeof required !== 'object' || isProxy(required) || !Object.isFrozen(required)) {
      localMockModelUnavailable();
    }
    const quotas = [];
    for (let index = 0; index < names.length; index++) {
      const property = descriptor(required, names[index]);
      if (property === undefined || !own(property, 'value')) localMockModelUnavailable();
      const value = property.value;
      if (index < 3 ? !Number.isSafeInteger(value) || value < 0 || value > 2147483647 :
          typeof value !== 'bigint' || value < 0n || value > 9223372036854775807n) localMockModelUnavailable();
      appendSourceOriginal(quotas, BigInt(value));
    }
    run.quotas = freeze(quotas);
    managedRunCurrent(run);
    return run.original;
  } catch (cause) {
    sourceFailure(entry, cause); entry.closing = true;
    throw cause;
  }
}
function prepareOriginalManagedRunPorts(original, prepared) {
  return prepareOriginalRunPorts(original, prepared, 'source-compute');
}
function prepareOriginalLocalMockModelRunPorts(original, prepared) {
  return prepareOriginalRunPorts(original, prepared, 'local-mock-model');
}
function prepareOriginalRunPorts(original,prepared,purpose) {
  const sourceRun=sourceInstallation?.receipt?.managedRun;
  const entry=sourceRun?.original===original ? sourceInstallation : managedComputeInstallation;
  const run=entry?.receipt?.managedRun;
  if (run===undefined || run.original!==original || run.derived!==prepared || !run.claimed ||
      run.quotas===undefined || run.portsTaken || run.stopped || run.purpose !== purpose) return null;
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
  [Reflect,['apply','ownKeys']],[Array,['isArray']],[globalThis,['Object','Reflect','Array','Promise','Buffer','Iterator']]]) {
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
  prepareManagedComputeInstallation: prepareManagedCompute,
  assertManagedComputeInstallationCurrent(original, originals) {
    managedComputeCurrent(original, originals);
  },
  closeManagedComputeInstallation(original, originals) {
    return closeSource(managedComputeOriginal(original, originals, true));
  },
  beforeManagedComputeSnapshot,
  beforeManagedComputeQuery(original, originals, format, text, parameters, options) {
    return beforeSourceQuery(original, originals, format, text, parameters, options, true);
  },
  bindManagedComputeSnapshot(original, originals, receipt, body) {
    bindSourceSubmission(managedComputeCurrent(original, originals), receipt, body);
  },
  bindManagedComputeRequest(original, originals, receipt, body, request) {
    const entry = managedComputeCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    if (producer.body !== body || producer.request !== undefined || producer.finished ||
        request === null || typeof request !== 'object' || isProxy(request)) sourceUnavailable();
    currentSourceSubmission(entry, producer, body);
    producer.request = request;
  },
  managedComputeIntentCid(original, originals, receipt, body) {
    const entry = managedComputeCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    currentSourceSubmission(entry, producer, body);
    const identity = apply(state.compute.intent, state.namespace, [originals, original, body]);
    managedComputeCurrent(original, originals);
    return identity;
  },
  finishManagedComputeProducer(original, originals, receipt, terminal) {
    const entry = managedComputeOriginal(original, originals, true), producer = sourceReceipt(entry, receipt);
    if (terminal !== 'returned' && terminal !== 'failed') sourceUnavailable();
    producer.finished = true;
    producer.snapshot = undefined;
  },
  prepareManagedComputeRun: claimManagedComputeRun,
  beforeManagedComputeResultRead(original, originals, schemaOrOptions, options) {
    managedComputeCurrent(original, originals);
    beforeResultRead(originals, schemaOrOptions, options);
  },
  assertManagedComputeResultReadCurrent(original, originals) {
    managedComputeCurrent(original, originals);
    if (resultInstallation?.originals !== originals) resultUnavailable();
    resultCurrent(resultInstallation.original, originals);
  },
  beforeSourceManagedResultRead(original, originals, schemaOrOptions, options) {
    sourceCurrent(original, originals);
    beforeResultRead(originals, schemaOrOptions, options);
  },
  assertSourceManagedResultReadCurrent(original, originals) {
    sourceCurrent(original, originals);
    if (resultInstallation?.originals !== originals) resultUnavailable();
    resultCurrent(resultInstallation.original, originals);
  },
  prepareHostResultPublicationInstallation: prepareResult,
  assertHostResultPublicationInstallationCurrent(original, originals) {resultCurrent(original, originals);},
  closeHostResultPublicationInstallation(original, originals) {return closeResult(resultOriginal(original, originals, true));},
  openHostResultPublicationStore: openResultStore,
  beforeHostResultPublicationOperation: beforeResultOperation,
  admitHostResultPublicationRun: admitResultRun,
  prepareSourceManagedInstallation: prepareSource,
  assertSourceManagedInstallationCurrent(original, originals) {sourceCurrent(original, originals);},
  beforeSourceManagedQuery(original, originals, format, text, parameters, options) {
    return beforeSourceQuery(original, originals, format, text, parameters, options, false);
  },
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
    bindSourceSubmission(sourceCurrent(original, originals), receipt, body);
  },
  bindSourceRequest(original, originals, receipt, body, request) {
    const entry = sourceCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    if (producer.body !== body || producer.request !== undefined || producer.finished ||
        request === null || typeof request !== 'object' || isProxy(request)) sourceUnavailable();
    currentSourceSubmission(entry, producer, body);
    // The receiving Host's fixed transform binding must later recover this
    // same original, rather than identifying a clone by fields or intent CID.
    producer.request = request;
  },
  sourceIntentCid(original, originals, receipt, body) {
    const entry = sourceCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    currentSourceSubmission(entry, producer, body);
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
  prepareSourceLocalMockModelRun: claimLocalMockModelRun,
  assertLocalMockModelPreparationCurrent(held) {
    assertLocalMockModelServiceCurrent(localMockModelService, held);
  },
  readLocalMockModelNow: localMockModelNow,
  prepareOriginalSourceChildPorts,
  prepareOriginalManagedRunPorts,
  prepareOriginalLocalMockModelRunPorts,
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
  // Fix the separate Journal support recipe before builtin/namespace/native
  // acquisition. Retaining this DATA is not yet its operational disposition;
  // the complete service and the same actual originals must still be bound.
  const journalServiceRecipe = declareHostJournalServiceRecipe(declaration);
  const runtime = freeze({node:processOriginal.versions.node,v8:processOriginal.versions.v8,
    openssl:processOriginal.versions.openssl,platform:processOriginal.platform,arch:processOriginal.arch,
    eager:false,libraries:freeze({...processOriginal.versions})});
  const originalJournalService = beginJournalService(journalServiceRecipe, declaration, runtime);
  const sourceEnvelope = declareSourceManagedPhaseEnvelope(declaration);
  const sourceComputeEnvelope = declareSourceComputePhaseEnvelope(sourceEnvelope);
  const managedComputeEnvelope = declareSourceFreeManagedComputePhaseEnvelope(declaration);
  const resultServiceRecipe = declareHostResultServiceRecipe(declaration, journalServiceRecipe,
    sourceComputeEnvelope, managedComputeEnvelope);
  const originalResultService = beginResultService(resultServiceRecipe, originalJournalService, runtime);
  const localMockModelServiceRecipe = declareHostLocalMockModelServiceRecipe(declaration,
    sourceComputeEnvelope, resultServiceRecipe);
  const originalLocalMockModelService = beginLocalMockModelService(localMockModelServiceRecipe,
    originalJournalService, originalResultService, runtime);
  // Retain selected builtin constructor identities before namespace callbacks.
  // This is module/control custody only: no DatabaseSync is constructed and
  // no writable Journal capacity is issued by loading this builtin.
  const sqliteOriginal = require('node:sqlite');
  const journalFacilities = freeze({fs:require('node:fs'), crypto:require('node:crypto'),
    promises:require('node:fs/promises')});
  const journalNative = freeze({DatabaseSync:field(sqliteOriginal,'DatabaseSync'),
    StatementSync:field(sqliteOriginal,'StatementSync'),
    bindings:captureJournalNativeBindings(journalFacilities.fs,journalFacilities.crypto,
      journalFacilities.promises)});
  if (typeof journalNative.DatabaseSync !== 'function' ||
      typeof journalNative.StatementSync !== 'function') unavailable();
  bindJournalServiceNative(originalJournalService, sqliteOriginal, journalNative, journalFacilities);
  bindResultServiceFacilities(originalResultService, journalFacilities);
  // Adopt the separate joint Source recipe before namespace, managed Source
  // metadata or raw SDK acquisition. This is not a second whole VM allowance.
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
  const compute = {};
  for (const [name, exported] of Object.entries({validator: 'assertSourceManagedHostPreparation',
    request: 'originalSourceManagedHostRequest', input: 'readSourceManagedOriginalInput',
    intent: 'managedComputeSubmittedIntentCid', requirements: 'readManagedComputeRunRequirements'})) {
    const entry = descriptor(namespace, exported);
    compute[name] = entry !== undefined && own(entry, 'value') ? entry.value : undefined;
  }
  freeze(compute);
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
  const journalDisposition = bindJournalServiceNamespace(originalJournalService, namespace, journal);
  bindResultServiceNamespace(originalResultService, namespace);
  bindLocalMockModelServiceNamespace(originalLocalMockModelService, namespace);
  state = {declaration,runtime,envelope,sourceEnvelope,sourceComputeEnvelope,runRequirements,
    managedComputeEnvelope,compute,resultServiceRecipe,resultService:originalResultService,
    localMockModelServiceRecipe,localMockModelService:originalLocalMockModelService,
    inventory,images,namespace,consumer,validator,reader,source,journal,journalNative,journalServiceRecipe,
    journalService:originalJournalService,journalDisposition,prefixIntrinsics,
    directoryNativeImageLoader:field(directoryNativeImage,'loadHostJournalDirectoryNative')};
} catch(cause) {
  // Keep original FD/namespace/compile failure and its close-only duty. A
  // failed prefix never becomes a second factory or a retrying image read.
  firstFailure = freeze({cause});
  if (journalService !== undefined) journalService.phase = 'failed';
  if (resultService !== undefined) resultService.phase = 'failed';
  if (localMockModelService !== undefined) localMockModelService.phase = 'failed';
}
