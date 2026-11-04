import {snapshotClientRequest} from '@actql/client-wire';
import {requestPreparationAvailable,assertRequestPreparationControl,beginRequestInput,openRequestPreparation,cleanupRequestInput,checkedPreparation} from '../local-node/request-preparation-adapter.mjs';
import {matchesPublishedSubmissionSnapshot, freezeInput} from '../../packages/sdk/internal/private-source-preparation.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {open} from 'node:fs/promises';
import {types} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {checkedRequestProgramPreparation, requestProgramCapacityRefusal} from './client-program-preparation.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {runtimeIsError} from '../host-common/compiler-binding.generated.mjs';
import {withOriginalFile} from './source-profile-json.mjs';
import resourceRuntime from './ordinary-node-resource-runtime.cjs';

// Existing Source/Compute responsibility, using real ordinary Node allocation
// and FileHandles rather than a startup-wide provenance proof. Actual Account
// checks stay at the Source consumer; this view grants no read or Model use.
const installations = new WeakMap();
const fail = code => {throw Object.assign(new Error(code), {code});};
const pending = value => {
  const field = value !== null && typeof value === 'object'
    ? Object.getOwnPropertyDescriptor(value, 'pending') : undefined;
  return field === undefined || !Object.hasOwn(field, 'value') || field.value !== false;
};
const fileIdentity = stat => [stat.dev, stat.ino, stat.size, stat.mtimeNs, stat.ctimeNs];

function immutablePolicySubject(value) {
  if (value !== null && typeof value === 'object') {
    for (const item of Object.values(value)) immutablePolicySubject(item);
    Object.freeze(value);
  }
  return value;
}

export function assertOrdinarySourcePreparationCurrent(view, originals, source) {
  const state = installations.get(view);
  if (state === undefined || state.originals !== originals || state.source !== source) {
    fail('ForeignInstalledSourcePreparation');
  }
  state.current();
}

export async function prepareOrdinarySourceManagedInstallation(originals, callbacks, source) {
  return prepareOrdinaryManagedInstallation(originals, callbacks, source, false);
}

// Same ordinary Source owner, but the installed Connector supplies its real
// per-occurrence reader. It cannot borrow the Mock document read or its bytes.
// The fixed Host calls this after retaining the actual Project preparation.
export async function prepareOrdinaryProjectSourceManagedInstallation(originals, callbacks) {
  return prepareOrdinaryManagedInstallation(originals, callbacks, true, true);
}

async function prepareOrdinaryManagedInstallation(originals, callbacks, source, project) {
  const diagnostic = diagnosticObserver(originals.installation?.authorization?.observe);
  const reportCapacityRefusal = cause => {
    const capacity = requestProgramCapacityRefusal(cause);
    if (capacity !== undefined) diagnostic('preparation_capacity_refused', capacity);
  };
  let closing = false, closed = false, bundle, flight, checkingBundle = false;
  const receipts = new WeakMap(), producers = new Set(), runs = new WeakMap();
  // The existing live inventory owns producers. Request lookup retains only
  // a weak reference; a held retired Request cannot keep its payload alive or
  // be rebound to another producer after its original owner has retired.
  const requestProducers = new WeakMap();
  // Exact Prepared lookup is provenance, not a second strong payload root.
  // The live inventory owns each record until its actual retirement.
  const liveRuns = new Set();
  const pendingRunRegistrations = new Set();
  const retiredRuns = new WeakMap();
  const retireInitialPreparation = prepared => callbacks.retireInitialPreparation(originals, prepared);
  const borrowSourceInitialization = callbacks.borrowSourceInitializationMaterial;
  function captureSourceMaterialMethod(record, name) {
    const field = Object.getOwnPropertyDescriptor(record.view, name);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
      fail('InstalledSourceInitializationMethodUnavailable');
    }
    return field.value;
  }
  function joinSourceMaterialComputation(record, value) {
    // Unexpected async protocol results remain in this SAME producer inventory.
    // Their settlement permits another original return, never acknowledges it.
    record.computation = value;
    const native = types.isPromise(value), then = native ? undefined : value?.then;
    if (!native && typeof then !== 'function') return;
    record.pending = true;
    const settled = () => {record.pending = false;record.computation = undefined;};
    const rejected = cause => {record.failure ??= cause;settled();};
    if (native) {
      Reflect.apply(Promise.prototype.then,value,[settled,rejected]);
      void value.then;
    } else {
      const pending = new Promise((resolve,reject) => Reflect.apply(then,value,[resolve,reject]));
      void pending.then(settled,rejected);
    }
  }
  function retainSourceInitializationMaterial(producer) {
    if (closing || closed || producer.finished || receipts.get(producer.receipt) !== producer ||
        producer.sourceInitialization !== undefined) fail('ForeignInstalledSourceProducer');
    if (borrowSourceInitialization === undefined) return undefined;
    try {
      if (typeof borrowSourceInitialization !== 'function') fail('InstalledSourceInitializationUnavailable');
      const view = Reflect.apply(borrowSourceInitialization,callbacks,[originals]);
      if (view === undefined) return undefined; // This original Host has no Source material.
      const record = {view, environment:undefined, release:undefined, originalEnvironment:undefined,
        computation:undefined, pending:false, failure:undefined};
      producer.sourceInitialization = record; // Retain before any fallible observation.
      record.release = captureSourceMaterialMethod(record,'release');
      record.environment = captureSourceMaterialMethod(record,'environment');
      const environment = Reflect.apply(record.environment,record.view,[]);
      if (types.isPromise(environment) || typeof environment?.then === 'function') {
        joinSourceMaterialComputation(record,environment);
        fail('InstalledSourceInitializationNotSynchronous');
      }
      if (environment === undefined) fail('InstalledSourceInitializationUnavailable');
      if (closing || closed || producer.finished || receipts.get(producer.receipt) !== producer) {
        fail('ForeignInstalledSourceProducer');
      }
      record.originalEnvironment = environment;
      return environment;
    } catch (cause) {
      // The SDK may never receive its receipt. Existing close still owns this
      // same unreturned producer and its original Source material borrow.
      producer.finished = true;
      throw cause;
    }
  }
  function returnSourceInitializationMaterial(producer) {
    const record = producer.sourceInitialization;
    if (record === undefined) return true;
    if (record.pending) return false;
    record.release ??= captureSourceMaterialMethod(record,'release');
    const returned = Reflect.apply(record.release,record.view,[]);
    // Both Bool values acknowledge this borrow's return. False only says the
    // parent itself is still live; neither value is a Source/Run/physical ACK.
    if (typeof returned !== 'boolean') {
      joinSourceMaterialComputation(record,returned);
      fail('InstalledSourceInitializationNotSynchronous');
    }
    record.view = record.release = record.environment = record.originalEnvironment = record.computation = undefined;
    producer.sourceInitialization = undefined;
    return true;
  }
  const releaseFinishedProducer = producer => {
    if (producer.finished && producer.liveRuns === 0) {
      // Retain a failed return even after its last original Run left liveRuns.
      producers.add(producer);
      if (producer.preparation !== undefined || !returnSourceInitializationMaterial(producer)) return false;
      producer.request = undefined;
      producer.snapshotPublication = undefined;
      producers.delete(producer);
      return true;
    }
    return false;
  };
  const producerForRequest = request => {
    const producer = requestProducers.get(request)?.deref();
    return !closing && !closed && producer !== undefined && producers.has(producer) &&
      receipts.get(producer.receipt) === producer && producer.request === request &&
      !producer.finished ? producer : undefined;
  };
  const current = () => {
    if (closing || closed) fail('SourceManagedPreparationUnavailable');
    callbacks.validator(originals);
    if (bundle !== undefined && !checkingBundle) {
      // The original metadata view itself calls this current fence. Reentry
      // keeps the Host check above, without recursively reading that same
      // view forever. The outer read still verifies its exact retained pair.
      checkingBundle = true;
      try {if (callbacks.read(originals) !== bundle) fail('ForeignInstalledMockPreparation');}
      finally {checkingBundle = false;}
    }
  };
  const producerFor = receipt => {
    const producer = receipts.get(receipt);
    if (producer === undefined) fail('ForeignInstalledSourceProducer');
    return producer;
  };
  const status = () => Object.freeze({pending: !closed});
  function captureReader(child) {
    if (!child.readerCloseSeen) {
      const method = child.reader.close;
      child.readerClose = method; child.readerCloseSeen = true;
    }
    if (typeof child.readerClose !== 'function') fail('InstalledSourceReaderCleanupUnavailable');
    if (!child.readerStatusSeen) {
      const method = child.reader.status;
      child.readerStatus = method; child.readerStatusSeen = true;
    }
    if (typeof child.readerStatus !== 'function') fail('InstalledSourceReaderCleanupUnavailable');
  }
  async function closeChild(child) {
    if (child.closed) return Object.freeze({pending: false});
    if (child.flight !== undefined) return Object.freeze({pending: true});
    child.closing = true;
    const work = Promise.resolve().then(async () => {
      if (child.reader !== undefined) {
        // Retention precedes these getters. Only a getter which never
        // returned can be read again; a captured callback is never replaced.
        captureReader(child);
        if (!child.readerCloseAcknowledged) {
          const observed = await Reflect.apply(child.readerClose, child.reader, []);
          if (pending(observed)) return Object.freeze({pending: true});
          child.readerCloseAcknowledged = true;
        }
        if (pending(Reflect.apply(child.readerStatus, child.reader, []))) {
          return Object.freeze({pending: true});
        }
        child.reader = child.readerClose = child.readerStatus = undefined;
      }
      if (child.cleanup !== undefined) {
        if (pending(Reflect.apply(child.cleanupStatus, child.cleanup, []))) {
          await Reflect.apply(child.cleanupRetry, child.cleanup, []);
        }
        if (pending(Reflect.apply(child.cleanupStatus, child.cleanup, []))) return Object.freeze({pending: true});
        child.cleanup = child.cleanupStatus = child.cleanupRetry = undefined;
      }
      child.bytes = undefined; child.closed = true;
      return Object.freeze({pending: false});
    });
    child.flight = work;
    try {return await work;} finally {if (child.flight === work) child.flight = undefined;}
  }
  function retainedRunCurrent(run) {
    const producer = run?.producer, state = producer?.preparation;
    if (closed || run === undefined || runs.get(run.prepared) !== run ||
        !liveRuns.has(run) || state === undefined || !state.adopting ||
        state.prepared !== run.prepared || state.original !== run.original ||
        receipts.get(producer.receipt) !== producer || run.value === undefined) {
      fail('ForeignInstalledSourceProducer');
    }
    callbacks.retainedValidator(originals);
    // Keep exact custody across the currentness callback's possible reentry.
    if (closed || runs.get(run.prepared) !== run || !liveRuns.has(run) ||
        producer.preparation !== state || state.original !== run.original) {
      fail('ForeignInstalledSourceProducer');
    }
  }
  function publicationRunFor(prepared) {
    const run = runs.get(prepared);
    retainedRunCurrent(run);
    resourceRuntime.assertOrdinaryManagedRunCurrent(run.original, run.producer.receipt);
    return run;
  }
  function runFor(prepared) {
    current();
    const run = runs.get(prepared);
    if (run === undefined) fail('NodeManagedRunAdmissionUnavailable');
    resourceRuntime.assertOrdinaryManagedRunCurrent(run.original, (run.producer.preparation === undefined ? run.operationPlan ?? prepared : run.producer.receipt));
    return run;
  }
  function prepareRun(prepared, purpose, model, content) {
    current();
    if (retiredRuns.has(prepared)) fail('ForeignInstalledModelPreparation');
    const old = runs.get(prepared);
    if (old !== undefined) {
      if (old.purpose !== purpose || old.model !== model || old.effectful !== false || old.content !== content || old.operationPlan !== undefined) {
        fail('ForeignInstalledModelPreparation');
      }
      return runFor(prepared).original;
    }
    const request = callbacks.request(originals, prepared);
    const producer = producerForRequest(request);
    if (producer === undefined || pendingRunRegistrations.has(prepared) ||
        liveRuns.size + pendingRunRegistrations.size >= 4096) fail('ForeignInstalledSourceProducer');
    const run = {prepared, request, producer, purpose, model, effectful: false, content, operationPlan: undefined, original: undefined,
      children: [], fileIdentity: undefined};
    if (producer.liveRuns === Number.MAX_SAFE_INTEGER) fail('InstalledSourceProducerLimit');
    producer.liveRuns++;
    runs.set(prepared, run);
    liveRuns.add(run);
    // A failed quote remains attached to this one preparation. It cannot be
    // retried under a different purpose or replaced by another original.
    const required = callbacks.requirements(originals, prepared);
    run.required = required;
    const producerReceipt = producer.receipt;
    const requestOriginals = new WeakSet();
    requestOriginals.add(request);
    run.original = resourceRuntime.retainOrdinaryManagedRun(prepared, required,
      () => {
        current();
        if (run.producer.receipt !== producerReceipt ||
            !requestOriginals.has(run.producer.request)) fail('ForeignInstalledSourceProducer');
      },
      () => run.children.some(child => child.flight !== undefined || !child.closed), purpose);
    return run.original;
  }
  async function readBytes(run, child) {
    current();
    if (child.closed || child.attempted) fail('InstalledSourcePreparationMismatch');
    child.attempted = true;
    const work = (async () => {
      try {
        const bytes = await withOriginalFile(bundle.dataPath, open, async original => {
          const read = original.read, stat = original.stat;
          if (typeof read !== 'function' || typeof stat !== 'function') fail('InstalledMockSourceUnavailable');
          const before = await Reflect.apply(stat, original, [{bigint: true}]);
          if (!before.isFile() || before.size > 1048576n) fail('InstalledMockSourceInputLimit');
          const identity = fileIdentity(before);
          if (run.fileIdentity === undefined) run.fileIdentity = identity;
          else if (identity.some((value, index) => value !== run.fileIdentity[index])) fail('InstalledMockSourceChanged');
          const chunks = []; let used = 0;
          for (;;) {
            current();
            const buffer = Buffer.allocUnsafe(Math.min(65536, 1048576 - used + 1));
            const {bytesRead} = await Reflect.apply(read, original, [buffer, 0, buffer.length, null]);
            if (!Number.isSafeInteger(bytesRead) || bytesRead < 0 || bytesRead > buffer.length) fail('InstalledMockSourceUnavailable');
            if (bytesRead === 0) break;
            used += bytesRead;
            if (used > 1048576) fail('InstalledMockSourceInputLimit');
            chunks.push(buffer.subarray(0, bytesRead));
          }
          const after = await Reflect.apply(stat, original, [{bigint: true}]);
          if (fileIdentity(after).some((value, index) => value !== identity[index])) fail('InstalledMockSourceChanged');
          return Buffer.concat(chunks, used);
        });
        current();
        for (const sibling of run.children) if (sibling !== child && sibling.bytes !== undefined &&
            !bytes.equals(sibling.bytes)) fail('InstalledMockSourceChanged');
        child.bytes = bytes; return bytes;
      } catch (cause) {
        child.failure = cause;
        // The bounded reader retains its same physical FileHandle on failed
        // close. Keep its original cleanup before another current check.
        child.cleanup = cause?.cleanupHandle;
        if (child.cleanup !== undefined) {
          child.cleanupStatus = child.cleanup.status; child.cleanupRetry = child.cleanup.retry;
        }
        throw cause;
      }
    })();
    child.flight = work;
    try {return await work;} finally {if (child.flight === work) child.flight = undefined;}
  }
  function originalTimedInvocation(state, producer, prepared, construct, contracts) {
    if (state.requiresQueryTime !== true) return undefined;
    const moon = state.context.runtime, compile = moon.clientProgramPrepareRequestProgramCompilation;
    const issue = moon.clientProgramRequestProgramModuleIssueCode;
    const reserve = moon.clientProgramReserveRequestQueryTimeInvocation;
    if (typeof construct !== 'function' || typeof compile !== 'function' ||
        typeof reserve !== 'function' || typeof issue !== 'function' || contracts === undefined || contracts.moon !== moon) {
      fail('NodeManagedRunRuntimeUnavailable');
    }
    const assertOriginal = () => {
      current();
      if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
          originals.installation.sequenceContractOriginal !== contracts || state.parent === undefined || state.holder === undefined ||
          moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
    };
    assertOriginal();
    const artifact = checkedRequestProgramPreparation(moon,
      Reflect.apply(compile, moon, [state.parent, producer.receipt,
        contracts.admission, state.context.retainedRelationOutput]), issue);
    assertOriginal();
    checkedRequestProgramPreparation(moon,
      Reflect.apply(reserve, moon, [state.parent, producer.receipt, artifact]), issue);
    assertOriginal();
    // The typed bridge returns its original Option. Forward it unchanged;
    // JavaScript does not construct or inspect a tuple representation.
    const invocation = construct(artifact);
    assertOriginal();
    return invocation;
  }
  function constructRequestDomain(state, construct) {
    state.preparing = true;
    try {return construct();}
    catch (cause) {
      state.preparationFailed = true; state.preparationFailure = cause;
      throw cause;
    } finally {state.preparing = false;}
  }
  function reserveModelRecovery(producer, state, count, wireAt, containers) {
    if (state.recovery === undefined || producer.finished || state.preparing || state.adopting ||
        typeof wireAt !== 'function') fail('ForeignInstalledSourceProducer');
    const moon = state.context.runtime;
    const recovery = state.recovery;
    const reserve = moon.clientProgramReserveRequestModelRecoveryMaterials;
    if (typeof reserve !== 'function') fail('NodeManagedRunRuntimeUnavailable');
    try {
      checked(Reflect.apply(reserve, moon, [state.parent, producer.receipt,
        recovery.request, recovery.definition, count, wireAt, containers]));
      current();
      if (producer.finished || producer.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
      recovery.assertCurrent();
      if (producer.finished || producer.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
    } catch (cause) {
      state.preparationFailed = true; state.preparationFailure = cause;
      throw cause;
    }
  }
  function registerRequestRun(run, construct) {
    // Synchronous reentry must see the same duplicate/capacity reservation
    // before Core adoption. This transient set owns no native Resource.
    if (runs.has(run.prepared) || pendingRunRegistrations.has(run.prepared) ||
        run.producer.liveRuns === Number.MAX_SAFE_INTEGER ||
        liveRuns.size + pendingRunRegistrations.size >= 4096) fail('ForeignInstalledSourceProducer');
    pendingRunRegistrations.add(run.prepared);
    try {
      run.value = construct();
      // Nothing callbackful follows the returned native original before its
      // existing live bag owns cleanup. Current is checked by later consumers.
      run.producer.liveRuns++;
      runs.set(run.prepared, run); liveRuns.add(run);
      return run;
    } finally {pendingRunRegistrations.delete(run.prepared);}
  }
  function beginProducer(kind, openParent) {
    current();
    // A selected funded context cannot fall back to an unfunded snapshot
    // when its typed capability or installed output mode is unavailable.
    // Resolve it before allocating a producer, including a throwing lookup.
    const context = callbacks.preparationContext === undefined
      ? undefined : callbacks.preparationContext(originals);
    if (context !== undefined && !requestPreparationAvailable(context)) {
      fail('NodeLocalPreparationAdmissionUnavailable');
    }
    if (context !== undefined) assertRequestPreparationControl(context);
    if (producers.size === 32) fail('InstalledSourceProducerLimit');
    const receipt = Object.freeze({});
    const producer = {receipt, kind, body: undefined, request: undefined, finished: false, liveRuns: 0, snapshotPublication: undefined, preparation: undefined};
    receipts.set(receipt, producer); producers.add(producer);
    const sourceEnvironment = retainSourceInitializationMaterial(producer);
    // The same Request precedes every SDK snapshot, independent of options.
    // Original Program and Parameters continue to their checked compiler
    // module; no shape scan selects a second preparation protocol.
    if (context !== undefined) {
      const state = {context, original: undefined, admission: undefined, parent: undefined,
        prepared: undefined, holder: undefined, adopting: false,
        originalCheckResult: undefined,
        projectOriginalCheck: Object.getOwnPropertyDescriptor(context.runtime,
          'clientProgramProjectRequestCheckOutcome')?.value};
      producer.preparation = state;
      try {
        if (sourceEnvironment !== undefined &&
            Object.getOwnPropertyDescriptor(context, 'preparedEnvironment')?.value !== sourceEnvironment) {
          fail('ForeignInstalledSourceProducer');
        }
        const assertOriginalCurrent = () => {
          // Cleanup may continue while the manager is closing. Exact
          // membership/current installation, not raw Prepared, is retained.
          if (closed || receipts.get(receipt) !== producer || producer.preparation !== state) {
            fail('ForeignInstalledSourceProducer');
          }
          const adopted = state.prepared === undefined ? undefined : runs.get(state.prepared);
          if (adopted?.producer === producer && adopted.original === state.original &&
              adopted.value !== undefined) retainedRunCurrent(adopted);
          else callbacks.validator(originals);
          // The original external current callback may retire this same
          // input before opening returns. Cheap state fences, not another
          // external current call, preserve the exact original after reentry.
          if (closed || receipts.get(receipt) !== producer || producer.preparation !== state) {
            fail('ForeignInstalledSourceProducer');
          }
        };
        // The same initial Root survives Run adoption. Observe physical
        // children on its existing producer/Run inventory, rather than
        // freezing a no-children answer before those children can exist.
        const childrenPending = () => {
          for (const run of liveRuns) if (run.producer === producer &&
              run.children.some(child => child.flight !== undefined || !child.closed)) return true;
          return false;
        };
        const accepted = openParent(state, receipt, assertOriginalCurrent, childrenPending);
        if (!accepted) fail('NodeLocalPreparationAdmissionUnavailable');
      } catch (cause) {
        producer.finished = true;
        try {
          cleanupRequestInput(state);
          producer.preparation = undefined;
          releaseFinishedProducer(producer);
        } catch (cleanupCause) {
          throw Object.assign(new Error('NodeLocalPreparationCleanupPending', {cause}),
            {code: 'NodeLocalPreparationCleanupPending', cleanupPending: true,
              cleanupCause});
        }
        throw cause;
      }
    }
    return receipt;
  }
  const view = Object.freeze({
    assertCurrent: current,
    assertSourceSnapshotCurrent(receipt) {
      current();
      const producer = producerFor(receipt), preparation = producer.preparation;
      if (producer.finished || producer.body !== undefined) fail('ForeignInstalledSourceProducer');
      if (preparation !== undefined) {
        const original = preparation.original;
        if (original === undefined || preparation.adopting ||
            preparation.parent === undefined && preparation.phase === undefined) {
          fail('ForeignInstalledSourceProducer');
        }
        resourceRuntime.assertOrdinaryManagedRunCurrent(original, receipt);
        if (producer.preparation !== preparation || preparation.original !== original) {
          fail('ForeignInstalledSourceProducer');
        }
      }
      // A current callback may synchronously retire this same producer. Its
      // original receipt/Resource tuple must still own this pre-freeze phase.
      if (closing || closed || receipts.get(receipt) !== producer ||
          producer.finished || producer.body !== undefined) fail('ForeignInstalledSourceProducer');
    },
    beforeSourceSnapshot(kind, input, options, originalConnection) {
      return beginProducer(kind, (state, receipt, assertCurrent, childrenPending) =>
        beginRequestInput(state, receipt, originalConnection, assertCurrent, childrenPending));
    },
    // Only the installed Host supplies this Journal-retained opaque original.
    // It is a new physical-process input lifetime for the SAME logical Request,
    // not an SDK snapshot publication, semantic issuer or physical read grant.
    retainModelRecovery(request, identity, definition, assertRecoveryCurrent, childrenPending) {
      if (request === null || typeof request !== 'object' || requestProducers.has(request) ||
          typeof assertRecoveryCurrent !== 'function' ||
          typeof childrenPending !== 'function') fail('ForeignInstalledSourceProducer');
      const receipt = beginProducer(undefined, (state, original, assertCurrent, ownChildrenPending) => {
        openRequestPreparation(state, original, () => {assertCurrent(); assertRecoveryCurrent();},
          () => ownChildrenPending() || childrenPending());
        return true;
      });
      const producer = producerFor(receipt), state = producer.preparation;
      if (state === undefined) fail('NodeLocalPreparationAdmissionUnavailable');
      state.recovery = {request: identity, definition, restored: undefined,
        assertCurrent: assertRecoveryCurrent, childrenPending};
      state.compilationFamily = 'model-recovery';
      producer.request = request;
      requestProducers.set(request, new WeakRef(producer));
      return Object.freeze({receipt});
    },
    restoreModelOriginal(request, original, definition, identity, construct) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state?.recovery === undefined || state.recovery.restored !== undefined ||
          state.recovery.definition !== definition || state.recovery.request !== identity ||
          typeof construct !== 'function') fail('ForeignInstalledSourceProducer');
      const recovery = state.recovery;
      reserveModelRecovery(producer, state, 3, index => index === 0 ? original.materialsWire
        : index === 1 ? original.resultPolicyOriginal.wire : definition.wire, 3);
      return constructRequestDomain(state, () => {
        const restored = construct();
        if (restored?.runDefinition !== definition || restored.prepared === undefined ||
            restored.compiled === undefined || restored.graph === undefined) fail('ForeignInstalledSourceProducer');
        recovery.restored = restored;
        state.prepared = restored.prepared;
        current();
        if (producer.finished || producer.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
        recovery.assertCurrent();
        if (producer.finished || producer.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
        return restored;
      });
    },
    retainRequestInput(request, intent, captured, materialWire) {
      if (request === null || typeof request !== 'object' || requestProducers.has(request) ||
          (intent === undefined) === (captured === undefined) ||
          materialWire !== undefined && (typeof materialWire !== 'string' || captured !== undefined)) {
        fail('ForeignInstalledSourceProducer');
      }
      let retainIntent, intentWire, reserveMaterial;
      const receipt = beginProducer(undefined, (state, original, assertCurrent, childrenPending) => {
        const moon = state.context.runtime;
        if (captured === undefined) {
          retainIntent = Object.getOwnPropertyDescriptor(moon, 'clientProgramRetainRequestSubmittedIntent')?.value;
          intentWire = Object.getOwnPropertyDescriptor(moon, 'clientSubmittedIntentWire')?.value;
          reserveMaterial = Object.getOwnPropertyDescriptor(moon, 'clientProgramReserveRequestRetainedProgramMaterial')?.value;
          if (typeof retainIntent !== 'function' || typeof intentWire !== 'function') {
            fail('NodeManagedRunRuntimeUnavailable');
          }
        }
        openRequestPreparation(state, original, assertCurrent, childrenPending);
        return true;
      });
      const producer = producerFor(receipt), state = producer.preparation;
      try {
        if (state === undefined) fail('NodeLocalPreparationAdmissionUnavailable');
        state.preparing = true;
        if (captured !== undefined) {
          // Only the Host's admitted Checkpoint reconstruction supplies this
          // original capture. Reuse the existing Source snapshot observer and
          // SAME new physical-process Request; issue no intent/CID or epoch.
          const body = view.captureSourceSnapshot(receipt, captured, snapshotClientRequest);
          freezeInput(body);
          producer.kind = body.kind;
          view.bindSourceSnapshot(receipt, body);
          view.bindSourceRequest(receipt, body, request);
          return Object.freeze({receipt, body});
        }
        const moon = state.context.runtime;
        // Source observes geometry and grows this SAME parent before JSON.parse.
        // Retain the opaque intent itself; no serializer/hash/new identity runs.
        checked(Reflect.apply(retainIntent, moon, [state.parent, receipt, intent]));
        if (closing || closed || producer.finished || producer.preparation !== state ||
            receipts.get(receipt) !== producer || state.parent === undefined) fail('ForeignInstalledSourceProducer');
        const wire = Reflect.apply(intentWire, moon, [intent]);
        if (typeof wire !== 'string') fail('InvalidHostRuntimeResult');
        const body = JSON.parse(wire);
        if (body.kind === 'program' && materialWire !== undefined) {
          if (typeof reserveMaterial !== 'function') fail('NodeManagedRunRuntimeUnavailable');
          checked(Reflect.apply(reserveMaterial, moon, [state.parent, receipt, materialWire]));
          if (closing || closed || producer.finished || producer.preparation !== state ||
              receipts.get(receipt) !== producer || state.parent === undefined) fail('ForeignInstalledSourceProducer');
          const material = JSON.parse(materialWire);
          if (material?.program_format !== 'json' || typeof material.program !== 'string' ||
              material.parameters !== null && typeof material.parameters !== 'string') {
            fail('ForeignInstalledSourceProducer');
          }
          const program = JSON.parse(material.program);
          const parameters = material.parameters === null ? null : JSON.parse(material.parameters);
          // The canonical intent already binds the complete structured input.
          // Compare ALL metadata, values and exact data Strings once, then
          // retain the material's original field order before the sole native
          // Program checker/compiler. No reissued intent or changed material
          // bytes bypass the later exact Run/compilation binding.
          if (canonicalValueJson(program, {dataKeys: true}) !== canonicalValueJson(body.input, {dataKeys: true}) ||
              canonicalValueJson(parameters, {dataKeys: true}) !== canonicalValueJson(body.parameters, {dataKeys: true})) {
            fail('ForeignInstalledSourceProducer');
          }
          body.input = program;
          body.parameters = parameters;
        }
        // Keep the SDK envelope's literal null sentinel. The same native
        // bridge treats only null as absent; undefined is supplied input.
        freezeInput(body);
        producer.kind = body.kind;
        state.snapshot = producer.body = body;
        state.snapshotDocument = wire;
        producer.request = request;
        requestProducers.set(request, new WeakRef(producer));
        return Object.freeze({receipt, body});
      } catch (cause) {
        if (state !== undefined) state.preparing = false;
        producer.finished = true;
        producer.body = producer.request = producer.snapshotPublication = undefined;
        if (state !== undefined) state.snapshot = state.snapshotDocument = undefined;
        try {
          if (state !== undefined) cleanupRequestInput(state, retireInitialPreparation);
          producer.preparation = undefined;
          releaseFinishedProducer(producer);
        } catch (cleanupCause) {
          throw Object.assign(new Error('NodeLocalPreparationCleanupPending', {cause}),
            {code: 'NodeLocalPreparationCleanupPending', cleanupPending: true, cleanupCause});
        }
        throw cause;
      } finally {
        if (state !== undefined) state.preparing = false;
      }
    },
    beforeSourceQuery(format, text, parameters, options, originalConnection) {
      // SDK owns documented option and input validation/snapshot semantics.
      // No data-only restriction on the trusted embedding caller is added.
      return view.beforeSourceSnapshot('aql', text, options, originalConnection);
    },
    captureSourceSnapshot(receipt, value, snapshot) {
      const producer = producerFor(receipt), state = producer.preparation;
      if (producer.finished || producer.body !== undefined || typeof snapshot !== 'function') {
        fail('ForeignInstalledSourceProducer');
      }
      if (state === undefined) return snapshot(value);
      if (state.parent === undefined || state.snapshotting || state.snapshot !== undefined) {
        fail('ForeignInstalledSourceProducer');
      }
      state.snapshotting = true;
      try {
        const captured = snapshot(value, (units, document, values) => {
          if (producer.finished || producer.preparation !== state || state.parent === undefined) {
            fail('ForeignInstalledSourceProducer');
          }
          if (state.snapshotUnits !== units || state.snapshotValues !== values) {
            checked(state.context.runtime.clientProgramReserveRequestSnapshot(
              state.parent, receipt, BigInt(units), BigInt(values)));
            state.snapshotUnits = units;state.snapshotValues = values;
          }
          // Retain the existing serializer's original wire before JSON.parse.
          // No second serialization observes this caller's input or getters.
          if (document !== undefined) state.snapshotDocument = document;
        });
        state.snapshot = captured;
        return captured;
      } finally {state.snapshotting = false;}
    },
    bindSourceSnapshot(receipt, body) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== undefined || producer.finished) fail('ForeignInstalledSourceProducer');
      producer.body = body;
      const state = producer.preparation;
      if (state !== undefined && (state.snapshot !== body ||
          typeof state.snapshotDocument !== 'string' || state.snapshotting)) {
        fail('ForeignInstalledSourceProducer');
      }
    },
    publishSourceSnapshot(receipt, body, publication) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== body || producer.finished || producer.snapshotPublication !== undefined ||
          !matchesPublishedSubmissionSnapshot(publication, body)) fail('ForeignInstalledSourceProducer');
      producer.snapshotPublication = publication;
    },
    bindSourceRequest(receipt, body, request) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== body || producer.request !== undefined || producer.finished ||
          request === null || (typeof request !== 'object' && typeof request !== 'function') ||
          requestProducers.has(request)) {
        fail('ForeignInstalledSourceProducer');
      }
      requestProducers.set(request, new WeakRef(producer));
      producer.request = request;
      // Keep the original weak association through finish/retirement. Lookup
      // requires live inventory and the same request; a stale key cannot bind
      // another producer. No strong alias collection or cleanup owner is added.
    },
    submittedIntentOriginal(request) {
      current();
      const producer = producerForRequest(request);
      if (producer === undefined) fail('ForeignInstalledSourceProducer');
      const state = producer?.preparation;
      if (state === undefined) return undefined;
      if (producer.finished || state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      const intent = moon.clientProgramRequestSubmittedIntentOriginal(state.parent, producer.receipt);
      if (intent === undefined) fail('ForeignInstalledSourceProducer');
      return intent;
    },
    observeOriginalCheckOutcome(request, failure, visit) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      // No retained original is reconstructed after completion/retirement, or
      // for a foreign failure merely carrying a public-looking error code.
      if (state === undefined || state.parent === undefined || state.preparing ||
          !state.preparationFailed || state.preparationFailure !== failure ||
          state.originalCheckResult === undefined || typeof state.projectOriginalCheck !== 'function') return undefined;
      if (typeof visit !== 'function') fail('InvalidOriginalCheckObservation');
      const parent = state.parent, result = state.originalCheckResult;
      const project = state.projectOriginalCheck, moon = state.context.runtime;
      const assertSame = () => {
        current();
        if (producer.finished || producer.request !== request || producer.preparation !== state ||
            state.parent !== parent || state.originalCheckResult !== result ||
            state.preparing || !state.preparationFailed || state.preparationFailure !== failure) {
          fail('ForeignInstalledSourceProducer');
        }
      };
      // Availability is decided from this SAME failed state before any
      // Source/account/namespace metadata visitor can await or do work.
      assertSame();
      return visit(metadata => {
        if (!Array.isArray(metadata) || metadata.length !== 13) fail('InvalidOriginalCheckObservation');
        assertSame();
        // Preserve the original Result wrapper. Only the typed C bridge may
        // match its terminal; no Err/Option or Error.cause is rebuilt in JS.
        const wire = checked(Reflect.apply(project, moon,
          [parent, producer.receipt, result, ...metadata]));
        assertSame();
        if (wire !== undefined && typeof wire !== 'string') fail('InvalidOriginalCheckObservation');
        return wire;
      });
    },
    async fundedPreparation(request, environment, originalVerifier, signal) {
      current();
      const producer = producerForRequest(request);
      const state = producer?.preparation;
      if (state === undefined) return undefined;
      if (!requestPreparationAvailable(state.context)) fail('NodeLocalPreparationAdmissionUnavailable');
      if (state.context.environment !== environment || state.adopting || state.preparing ||
          state.parent === undefined ||
          originalVerifier !== undefined && typeof originalVerifier !== 'function' ||
          state.policyVerifierSelected &&
            (state.policyVerifier !== originalVerifier || state.policySignal !== signal)) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      // This SAME receipt owns the detached Program/Query and Parameters.
      // Its Core entry retains Source/check/compiler originals and typed
      // failure. No serializer, raw preparation or second parent fallback.
      if ((producer.kind !== 'program' && producer.kind !== 'aql') || producer.body !== state.snapshot) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.preparationFailed) throw state.preparationFailure;
      if (state.holder === undefined) {
        const contracts = originals.installation.sequenceContractOriginal;
        if (contracts === undefined || contracts.moon !== moon) fail('ForeignInstalledSourceProducer');
        const parent = state.parent;
        const assertPreparingOriginal = () => {
          if (closing || closed || producer.finished || producer.preparation !== state ||
              producer.request !== request || state.parent !== parent ||
              state.policyVerifier !== originalVerifier || state.policySignal !== signal) {
            fail('ForeignInstalledSourceProducer');
          }
          signal?.throwIfAborted();
        };
        state.policyVerifier = originalVerifier; state.policySignal = signal;
        state.policyVerifierSelected = true;
        state.preparing = true;
        try {
          if (state.compilationKind === undefined) {
            const prepareCheck = moon[producer.kind === 'program'
              ? 'clientProgramPrepareRequestNativeComputation' : 'clientProgramPrepareRequestSourceComputation'];
            const finishComputation = moon.clientProgramFinishRequestComputation;
            const projectIssue = moon.clientProgramRequestPreparationIssueCode;
            const policyMethods = originalVerifier === undefined ? [] : [
              'clientProgramPrepareRequestPolicySubjects', 'clientProgramReadRequestPolicySubject',
              'clientProgramBindRequestPolicySubject', 'clientProgramFinishRequestPolicySubjects',
            ].map(name => moon[name]);
            if ([prepareCheck, finishComputation, ...policyMethods].some(method => typeof method !== 'function')) {
              fail('NodeManagedRunRuntimeUnavailable');
            }
            assertPreparingOriginal();
            const valuesMaxRows = Object.getOwnPropertyDescriptor(state.context, 'valuesMaxRows')?.value;
            const originalCheckResult = Reflect.apply(prepareCheck, moon, [
              parent, producer.receipt, producer.body.input,
              producer.body.parameters === undefined ? null : producer.body.parameters,
              environment, state.context.preparedEnvironment, valuesMaxRows,
            ]);
            // This failed Request already owns the child and its cleanup.
            // Retain only its actual result until that same owner retires it.
            state.originalCheckResult = originalCheckResult;
            checkedRequestProgramPreparation(moon, originalCheckResult, projectIssue);
            state.originalCheckResult = undefined;
            assertPreparingOriginal();
            if (originalVerifier !== undefined) {
              const [prepareSubjects, readSubject, bindSubject, finishSubjects] = policyMethods;
              const count = checkedRequestProgramPreparation(moon, Reflect.apply(prepareSubjects, moon,
                [parent, producer.receipt, environment]), projectIssue);
              if (!Number.isSafeInteger(count) || count < 0 || count > 1024) fail('ClientProgramPreparationFailure');
              let wireBytes = 0;
              for (let index = 0; index < count; index++) {
                assertPreparingOriginal();
                const wire = checkedRequestProgramPreparation(moon, Reflect.apply(readSubject, moon,
                  [parent, producer.receipt, environment, index]), projectIssue);
                if (typeof wire !== 'string' || (wireBytes += Buffer.byteLength(wire)) > 1048576) {
                  fail('ClientProgramPreparationFailure');
                }
                const subject = immutablePolicySubject(JSON.parse(wire));
                const policyCid = await originalVerifier(subject, {signal});
                assertPreparingOriginal();
                if (policyCid !== undefined &&
                    (typeof policyCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(policyCid))) {
                  fail('ClientProgramPreparationFailure');
                }
                // Core rechecks the original current capacity after the Host
                // await. An explicit decline still consumes this SAME index.
                checkedRequestProgramPreparation(moon, Reflect.apply(bindSubject, moon,
                  [parent, producer.receipt, environment, index, policyCid]), projectIssue);
                assertPreparingOriginal();
              }
              checkedRequestProgramPreparation(moon, Reflect.apply(finishSubjects, moon,
                [parent, producer.receipt, environment]), projectIssue);
              assertPreparingOriginal();
            }
            // The supplemented Environment stays inside this SAME check child.
            // Finish still receives the original external Environment/publication.
            state.compilationKind = checkedRequestProgramPreparation(moon, Reflect.apply(finishComputation, moon,
              [parent, producer.receipt, environment, state.context.preparedEnvironment]), projectIssue);
            assertPreparingOriginal();
          }
          // Actual captured/Effect Plan construction belongs to its existing
          // Host caller. A logical compiler result cannot select a different
          // parent or claim that an unconstructed Plan is ready.
          if (state.compilationKind === 'effectful') {
            // The actual typed Effect borrow reserves construction on this SAME
            // Request. Never cast it to a Program borrow or select a new Root.
            const names = ['clientProgramBorrowRequestEffectPlanInput',
              'clientProgramEffectPreparationInputRead', 'clientProgramEffectPreparationInputReturn',
              'clientProgramEffectPreparationInputSibling', 'clientProgramEffectPreparationInputRetirementStarted',
              'clientProgramCompleteRequestEffectPreparation', 'clientProgramAdoptRequestEffectPreparation'];
            const methods = names.map(name => moon[name]);
            if (methods.some(method => typeof method !== 'function')) fail('NodeManagedRunRuntimeUnavailable');
            // Model is optional for a non-Model installation. Capture each
            // selected original once; later namespace replacement cannot supply
            // a different Scope constructor or adoption method.
            for (const name of ['clientProgramPrepareRequestEffectModelReadScope',
              'clientProgramAdoptRequestEffectModelPreparation']) {
              names.push(name);
              methods.push(Object.getOwnPropertyDescriptor(moon, name)?.value);
            }
            state.effectBorrowMethods = Object.freeze(Object.fromEntries(names.map((name, index) =>
              [name, typeof methods[index] === 'function'
                ? (...args) => Reflect.apply(methods[index], moon, args) : undefined])));
            state.holder = checked(state.effectBorrowMethods.clientProgramBorrowRequestEffectPlanInput(
              state.parent, producer.receipt));
          } else if (state.compilationKind === 'effect_free') {
            // This first borrow exposes only the SAME checked inventory. An
            // effect-free compiler result is not an ordinary Module witness:
            // INFER and Serialization retain their own construction inputs.
            state.holder = checked(moon.clientProgramBorrowRequestProgramPlanInput(
              state.parent, producer.receipt));
            const prepared = moon.clientProgramPreparationBorrowRead(state.holder);
            if (prepared === undefined) fail('ForeignInstalledSourceProducer');
            const inferOccurrences = moon.clientProgramComposedInferOccurrences;
            const serializationOccurrences = moon.clientProgramSerializationOccurrences;
            if (typeof inferOccurrences !== 'function' || typeof serializationOccurrences !== 'function') {
              fail('NodeManagedRunRuntimeUnavailable');
            }
            const infers = checked(Reflect.apply(inferOccurrences, moon, [prepared]));
            const serializations = Reflect.apply(serializationOccurrences, moon, [prepared]);
            if (!Array.isArray(infers) || !Array.isArray(serializations)) fail('InvalidHostRuntimeResult');
            // Model owns the mixed constructor borrow too. Its typed Graph
            // and prefix constructors validate the original composition;
            // inventory counts do not authorize an ordinary Pure module.
            state.compilationFamily = infers.length !== 0 ? 'model'
              : serializations.length !== 0 ? 'content' : 'pure';
            if (state.compilationFamily !== 'pure') {
              const select = moon[state.compilationFamily === 'model'
                ? 'clientProgramBorrowRequestModelPlanInput' : 'clientProgramBorrowRequestContentPlanInput'];
              if (typeof select !== 'function' || typeof moon.clientProgramPreparationBorrowReturn !== 'function') {
                fail('NodeManagedRunRuntimeUnavailable');
              }
              const selected = checked(Reflect.apply(select, moon, [state.parent, producer.receipt]));
              // Keep BOTH actual borrows before a read/return can fail. The
              // existing Request retirement owns a failed inventory return.
              state.inventoryHolder = state.holder;
              state.holder = selected;
              if (moon.clientProgramPreparationBorrowRead(selected) !== prepared) {
                fail('ForeignInstalledSourceProducer');
              }
              // Core consumes this borrower before reporting owner retirement.
              // false means the selected owner remains live, not a failed
              // return. A later settlement error must retry the SAME parent,
              // never invoke a consumed borrow token again.
              const inventory = state.inventoryHolder;
              state.inventoryHolder = undefined;
              checked(moon.clientProgramPreparationBorrowReturn(inventory));
            }
            const count = moon.clientProgramAcquisitionCount(prepared);
            if (!Number.isSafeInteger(count) || count < 0) fail('InvalidHostRuntimeResult');
            state.acquisitionCount = count;
            const requiresTime = moon.clientProgramRequiresQueryTime;
            state.requiresQueryTime = typeof requiresTime === 'function'
              ? checked(Reflect.apply(requiresTime, moon, [prepared, 100000, 100000])) : false;
            if (typeof state.requiresQueryTime !== 'boolean') fail('InvalidHostRuntimeResult');
            // A timed module needs the actual submission Request and first
            // bound Run. Keep this SAME borrower until that adoption caller.
            if (state.compilationFamily === 'pure' && count === 0 && !state.requiresQueryTime) {
              checkedRequestProgramPreparation(moon,
                moon.clientProgramPrepareRequestProgramModuleBody(state.parent,
                  producer.receipt, contracts.admission, state.context.retainedRelationOutput),
                moon.clientProgramRequestProgramModuleIssueCode);
            }
          } else fail('NodeManagedRunPlanUnavailable');
        } catch (cause) {
          reportCapacityRefusal(cause);
          state.preparationFailed = true;
          state.preparationFailure = cause;
          throw cause;
        } finally {state.preparing = false;}
      }
      const prepared = state.effectBorrowMethods === undefined
        ? moon.clientProgramPreparationBorrowRead(state.holder)
        : state.effectBorrowMethods.clientProgramEffectPreparationInputRead(state.holder);
      if (prepared === undefined || state.prepared !== undefined && state.prepared !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      state.prepared = prepared;
      if (!state.parameterMetadataLoaded) {
        state.parametersCursor = checked(moon.clientProgramRequestParametersOriginal(state.parent, producer.receipt));
        state.parameterMetadataLoaded = true;
      }
      return Object.freeze({kind: state.compilationKind, prepared,
        originalInputs: Object.freeze({environment, parameters: undefined,
          parametersCursor: state.parametersCursor})});
    },
    prepareModelMaterials(prepared, request, count, wireAt, containerCount) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state?.recovery !== undefined) {
        if (state.recovery.restored?.prepared !== prepared || state.prepared !== prepared) fail('ForeignInstalledSourceProducer');
        try {return reserveModelRecovery(producer, state, count, wireAt, containerCount);}
        catch (cause) {state.preparationFailed = true; state.preparationFailure = cause; throw cause;}
      }
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'model' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.modelCompilation !== undefined || typeof wireAt !== 'function') fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime;
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      const prepare = moon.clientProgramPrepareRequestModelContractMaterials;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      if (typeof prepare !== 'function' || typeof issue !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      return constructRequestDomain(state, () => {
        checkedRequestProgramPreparation(moon, Reflect.apply(prepare, moon,
          [state.parent, producer.receipt, count, wireAt, containerCount]), issue);
        current();
        if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
            moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      });
    },
    prepareModelBinding(prepared, request, providerId, installation, contract, configuration) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state?.recovery !== undefined) {
        if (state.recovery.restored?.prepared !== prepared || state.prepared !== prepared ||
            state.modelProviderBinding !== undefined) fail('ForeignInstalledSourceProducer');
        const recovery = state.recovery;
        reserveModelRecovery(producer, state, 3,
          index => index === 0 ? installation : index === 1 ? contract : configuration, 3);
        return constructRequestDomain(state, () => {
          state.modelProviderBinding = checked(state.context.runtime.clientProgramModelProviderBinding(
            providerId, installation, contract, configuration));
          current();
          if (producer.finished || producer.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
          recovery.assertCurrent();
          if (producer.finished || producer.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
          return state.modelProviderBinding;
        });
      }
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'model' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.modelCompilation !== undefined || state.modelProviderBinding !== undefined) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime;
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      const prepare = moon.clientProgramPrepareRequestModelProviderBinding;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      if (typeof prepare !== 'function' || typeof issue !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      return constructRequestDomain(state, () => {
        state.modelProviderBinding = checkedRequestProgramPreparation(moon, Reflect.apply(prepare, moon,
          [state.parent, producer.receipt, providerId, installation, contract, configuration]), issue);
        current();
        if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
            moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
        return state.modelProviderBinding;
      });
    },
    prepareModelGraph(prepared, request, occurrence, execution, serializationGraph, constructSerialized) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'model' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.modelGraph !== undefined ||
          state.contentGraph !== serializationGraph) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime, contracts = originals.installation.sequenceContractOriginal;
      if (contracts?.moon !== moon || moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      const construct = serializationGraph === undefined ? moon.clientProgramPrepareRequestModelGraph
        : moon.clientProgramPrepareRequestSerializedModelGraph;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      if (typeof construct !== 'function' || typeof issue !== 'function' ||
          serializationGraph !== undefined && typeof constructSerialized !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      return constructRequestDomain(state, () => {
        const result = serializationGraph === undefined
          ? Reflect.apply(construct, moon,
            [state.parent, producer.receipt, occurrence, execution, contracts.admission])
          : constructSerialized(state.parent, producer.receipt, occurrence,
            serializationGraph, execution, contracts.admission);
        state.modelGraph = checkedRequestProgramPreparation(moon, result, issue);
        if (state.modelGraph === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
            state.contentGraph !== serializationGraph ||
            moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
        return state.modelGraph;
      });
    },
    prepareModelCompilation(prepared, request, graph) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined; // An explicitly separate purpose.
      if (state.prepared !== prepared || state.compilationFamily !== 'model' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.modelGraph !== undefined && state.modelGraph !== graph) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime, contracts = originals.installation.sequenceContractOriginal;
      if (contracts?.moon !== moon || moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.modelCompilation !== undefined) return state.modelCompilation;
      const compile = moon.clientProgramPrepareRequestModelCompilation;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      if (typeof compile !== 'function' || typeof issue !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      state.modelGraph = graph;
      return constructRequestDomain(state, () => {
        // The typed Request compiler owns this SAME raw TaskCompilation.
        // The Model module and Run issuer must consume it without compiling
        // the graph again or reinterpreting it as the Values/Tasks sum.
        state.modelCompilation = checkedRequestProgramPreparation(moon, Reflect.apply(compile, moon,
          [state.parent, producer.receipt, graph, contracts.admission]), issue);
        if (state.modelCompilation === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
            state.modelGraph !== graph || moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
          fail('ForeignInstalledSourceProducer');
        }
        return state.modelCompilation;
      });
    },
    prepareContentGraph(prepared, request, constructOriginal) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined;
      if (state.prepared !== prepared || !['content', 'model'].includes(state.compilationFamily) ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || typeof constructOriginal !== 'function') fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime, contracts = originals.installation.sequenceContractOriginal;
      if (contracts?.moon !== moon || moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.contentGraph !== undefined) return state.contentGraph;
      return constructRequestDomain(state, () => {
        // Retain before post-callback current can fail. This same Request's
        // original cleanup owns the native component and its partial peak.
        state.contentGraph = Reflect.apply(constructOriginal, undefined,
          [state.parent, producer.receipt, contracts.admission]);
        if (state.contentGraph === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
            moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
        return state.contentGraph;
      });
    },
    prepareContentCompilation(prepared, request, graph, compileOriginal) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined;
      if (state.prepared !== prepared || state.compilationFamily !== 'content' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || typeof compileOriginal !== 'function' ||
          state.contentGraph !== undefined && state.contentGraph !== graph) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime, contracts = originals.installation.sequenceContractOriginal;
      if (contracts?.moon !== moon || moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.contentCompilation !== undefined) return state.contentCompilation;
      state.contentGraph = graph;
      return constructRequestDomain(state, () => {
        state.contentCompilation = Reflect.apply(compileOriginal, undefined,
          [state.parent, producer.receipt, graph, contracts.admission]);
        if (state.contentCompilation === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
            moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
        return state.contentCompilation;
      });
    },
    publicationPreparation(prepared) {
      const run = runFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared ||
          state.holder === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      if (run.value === undefined) fail('NodeManagedRunAdmissionUnavailable');
      return run.value;
    },
    reservePublication(prepared) {
      const run = publicationRunFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared ||
          state.holder === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      if (run.value === undefined) fail('NodeManagedRunAdmissionUnavailable');
      return checkedPreparation(state.context.runtime,
        state.context.runtime.clientProgramReservePublication(
          run.value, prepared));
    },
    compilationOriginal(prepared) {
      const run = runFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared || state.holder === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      if (run.value === undefined) fail('NodeManagedRunAdmissionUnavailable');
      const original = state.context.runtime.clientProgramInstalledManagedRunCompilationOriginal(run.value, prepared);
      if (original === undefined) fail('NodeManagedRunCompilationUnavailable');
      return original;
    },
    adoptPreparation(prepared, request, identity, constructInvocation) {
      current();
      const producer = producerForRequest(request);
      const state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined;
      if (state.prepared !== prepared || state.holder === undefined || state.adopting ||
          state.compilationFamily !== 'pure' || state.acquisitionCount !== 0) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime;
      const contracts = originals.installation.sequenceContractOriginal;
      const module = moon.clientProgramPrepareRequestProgramModuleBody;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      const adopt = moon.clientProgramAdoptRequestProgramPreparation;
      if (typeof adopt !== 'function' || state.requiresQueryTime &&
          (typeof module !== 'function' || typeof issue !== 'function')) {
        fail('NodeManagedRunRuntimeUnavailable');
      }
      const run = {prepared,request,producer,purpose:'source-compute',model:undefined,
        effectful:false,content:undefined,original:state.original,children:[],fileIdentity:undefined,value:undefined};
      state.adopting = true;
      try {
        registerRequestRun(run, () => {
          if (state.requiresQueryTime) {
            const invocation = originalTimedInvocation(state, producer, prepared, constructInvocation, contracts);
            checkedRequestProgramPreparation(moon, Reflect.apply(module, moon,
              [state.parent, producer.receipt, contracts.admission,
                state.context.retainedRelationOutput, invocation]), issue);
            current();
            if (producer.finished || producer.preparation !== state || state.prepared !== prepared) {
              fail('ForeignInstalledSourceProducer');
            }
          }
          return checked(Reflect.apply(adopt, moon, [state.parent, identity]));
        });
        return run;
      } catch (cause) {
        reportCapacityRefusal(cause);
        state.adopting = false;
        if (state.requiresQueryTime) {
          state.preparationFailed = true; state.preparationFailure = cause;
        }
        throw cause;
      }
    },
    adoptCapturePreparation(prepared, request, identity, constructPlan, constructInvocation) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined; // Other purposes retain their existing owner.
      if (state.prepared !== prepared || state.holder === undefined || state.adopting ||
          state.compilationKind !== 'effect_free' || state.compilationFamily !== 'pure' || !(state.acquisitionCount > 0) ||
          typeof constructPlan !== 'function') {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      const contracts = originals.installation.sequenceContractOriginal;
      const prepareModule = moon.clientProgramPrepareRequestCaptureModuleBody;
      const projectIssue = moon.clientProgramRequestProgramModuleIssueCode;
      const adopt = moon.clientProgramAdoptRequestCapturePreparation;
      if (typeof prepareModule !== 'function' || typeof projectIssue !== 'function' ||
          typeof adopt !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      const run = {prepared, request, producer, purpose: 'source-compute', model: undefined,
        effectful: false, content: undefined, original: state.original,
        children: [], fileIdentity: undefined, value: undefined};
      state.adopting = true;
      try {
        registerRequestRun(run, () => {
          // This private Host constructor uses its already retained Source
          // inventory, on the same input reservation. It is not a capacity or
          // authorization callback, and does not run for another purpose.
          const invocation = originalTimedInvocation(state, producer, prepared, constructInvocation, contracts);
          const plan = state.requiresQueryTime ? constructPlan(invocation) : constructPlan();
          state.capturePlan = plan;
          current();
          if (producer.finished || producer.preparation !== state || state.prepared !== prepared) {
            fail('ForeignInstalledSourceProducer');
          }
          // The SAME Request already backs this Plan and retains its input borrow.
          // Construct/measure its original compilation before adoption; bare
          // completion would lose that artifact and force later re-preparation.
          checkedRequestProgramPreparation(moon,
            Reflect.apply(prepareModule, moon, state.requiresQueryTime
              ? [state.parent, producer.receipt, plan, invocation] : [state.parent, producer.receipt, plan]),
            projectIssue);
          return checked(Reflect.apply(adopt, moon, [state.parent, identity]));
        });
        // The actual Core Run now retains this same Plan. Do not keep a
        // second strong Plan root after its completed handoff.
        state.capturePlan = undefined;
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    prepareModelRun(prepared, request, identity, model, constructPlan) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'model' ||
          state.adopting || state.preparing || typeof constructPlan !== 'function') {
        fail('ForeignInstalledSourceProducer');
      }
      const compilation = view.prepareModelCompilation(prepared, request, model.graph);
      constructRequestDomain(state, () => {
        // Retain before the adopter's first fallible current check. Partial
        // modules and this original Plan stay on the same Request for cleanup.
        state.modelPlan = Reflect.apply(constructPlan, undefined, [state.parent, producer.receipt, compilation]);
      });
      return view.adoptModelPreparation(prepared, identity, state.modelPlan, model);
    },
    adoptModelPreparation(prepared, identity, modelPlan, model) {
      current();
      const request = callbacks.request(originals, prepared);
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (model === null || typeof model !== 'object' || types.isProxy(model) ||
          state === undefined || state.prepared !== prepared || state.compilationFamily !== 'model' ||
          state.modelCompilation === undefined || state.modelGraph !== model?.graph ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing) {
        fail('ForeignInstalledSourceProducer');
      }
      // This is the existing physical caller's record, retained before entry.
      // Its Scope must survive a later completion/adoption failure.
      const scopeField = Object.getOwnPropertyDescriptor(model, 'scope');
      if (scopeField === undefined || !Object.hasOwn(scopeField, 'value') ||
          scopeField.value !== undefined || scopeField.writable !== true) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime;
      const quantityLimits = model.selection?.quantityCapacity?.limits;
      const scope = quantityLimits === undefined ? moon.clientProgramPrepareRequestModelReadScope
        : moon.clientProgramPrepareRequestModelReadScopeWithQuantities;
      const complete = moon.clientProgramCompleteRequestModelPreparation;
      const adopt = moon.clientProgramAdoptRequestModelPreparation;
      if (![scope, complete, adopt].every(method => typeof method === 'function')) {
        fail('NodeManagedRunRuntimeUnavailable');
      }
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      state.modelPlan = modelPlan;
      const run = {prepared, request, producer, purpose: 'local-mock-model', model,
        effectful: false, content: undefined, original: state.original,
        children: [], fileIdentity: undefined, value: undefined};
      state.adopting = true;
      try {
        registerRequestRun(run, () => {
          model.scope = checked(Reflect.apply(scope, moon, [state.parent, producer.receipt, modelPlan,
            ...(quantityLimits === undefined ? [] : [quantityLimits.tokens,
              quantityLimits.costUnits, quantityLimits.durationMs])]));
          if (model.scope === undefined) fail('NodeManagedRunAdmissionUnavailable');
          checked(Reflect.apply(complete, moon, [state.parent, producer.receipt, modelPlan]));
          return checked(Reflect.apply(adopt, moon, [state.parent, identity, model.scope]));
        });
        state.modelCompilation = state.modelGraph = state.modelPlan = state.modelProviderBinding = state.contentGraph = undefined;
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    selectDomainSourceInput(prepared, request, identity, stage, sourceIndex) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined; // A separately owned legacy purpose.
      if (state.prepared !== prepared || state.compilationKind !== 'effect_free') fail('ForeignInstalledSourceProducer');
      if (state.compilationFamily === 'pure') return undefined;
      if (!['model', 'content'].includes(state.compilationFamily) || state.holder === undefined ||
          state.parent === undefined || state.inventoryHolder !== undefined || state.preparing ||
          !Number.isSafeInteger(stage) || stage < 0 || !Number.isSafeInteger(sourceIndex) || sourceIndex < 0) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime, holder = state.holder, parent = state.parent;
      // Submission revisits the SAME Prepared after Plan adoption. The
      // original live Run bag, not another preparation, supplies that custody.
      const adopted = state.adopting === true;
      const run = adopted ? runs.get(prepared) : undefined;
      if (adopted && (run === undefined || run.closed || run.producer !== producer ||
          run.prepared !== prepared || run.request !== request || run.original !== state.original ||
          run.value === undefined)) fail('ForeignInstalledSourceProducer');
      const value = run?.value;
      const select = Object.getOwnPropertyDescriptor(moon, 'clientProgramSelectInstalledSourceInput')?.value;
      if (typeof select !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      if (moon.clientProgramPreparationBorrowRead(holder) !== prepared) fail('ForeignInstalledSourceProducer');
      // The actual Model/Content Plan borrow already owns this Request's
      // variable construction input. Select only its nominal Source original;
      // the backed domain constructor creates the complete Query exactly once.
      return constructRequestDomain(state, () => {
        const selected = checked(Reflect.apply(select, moon, [prepared, identity, stage, sourceIndex]));
        current();
        if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
            state.parent !== parent || state.holder !== holder || state.context.runtime !== moon ||
            (state.adopting === true) !== adopted ||
            adopted && (runs.get(prepared) !== run || run.closed || run.value !== value ||
              run.request !== request || run.producer !== producer || run.original !== state.original) ||
            moon.clientProgramPreparationBorrowRead(holder) !== prepared) fail('ForeignInstalledSourceProducer');
        return selected;
      });
    },
    retainContentPreparation(prepared, request, contentPreparation) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state === undefined || state.prepared !== prepared || !['model', 'content'].includes(state.compilationFamily) ||
          state.holder === undefined || state.adopting || state.preparing ||
          contentPreparation?.prepared !== prepared || contentPreparation.retired ||
          typeof Object.getOwnPropertyDescriptor(contentPreparation, 'releaseAliases')?.value !== 'function' ||
          state.contentPreparation !== undefined && state.contentPreparation !== contentPreparation ||
          state.context.runtime.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      // No fallible callback follows taking this original record. Failed
      // construction keeps it until the same Request's abort fence below.
      state.contentPreparation = contentPreparation;
      contentPreparation.inputHolder = state.holder;
    },
    prepareKeyedContentRun(prepared, request, identity, graph, constructPlan, compileOriginal, contentPreparation) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'content' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.contentGraph !== undefined && state.contentGraph !== graph ||
          state.contentPreparation !== contentPreparation ||
          typeof constructPlan !== 'function' || typeof compileOriginal !== 'function') {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      state.contentGraph = graph;
      constructRequestDomain(state, () => {
        // The same Request owns the original selected keyed Plan BEFORE its
        // compiler consumes that Plan, graph and immutable contract inputs.
        state.contentPlan = Reflect.apply(constructPlan, undefined, [state.parent, producer.receipt]);
        if (state.contentPlan === undefined) fail('InstalledContentRunPreparationUnavailable');
        state.contentCompilation = Reflect.apply(compileOriginal, undefined,
          [state.parent, producer.receipt, state.contentPlan, graph]);
        if (state.contentCompilation === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer.finished || producer.preparation !== state || state.prepared !== prepared ||
            moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      });
      return view.adoptContentPreparation(prepared, identity, state.contentPlan);
    },
    prepareSerializationRun(prepared, request, identity, constructPlan, contentPreparation) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'content' ||
          state.contentCompilation === undefined || state.holder === undefined || state.adopting ||
          state.preparing || state.contentPreparation !== contentPreparation || typeof constructPlan !== 'function') fail('ForeignInstalledSourceProducer');
      constructRequestDomain(state, () => {
        state.contentPlan = Reflect.apply(constructPlan, undefined, [state.parent, producer.receipt]);
      });
      return view.adoptContentPreparation(prepared, identity, state.contentPlan, true);
    },
    adoptContentPreparation(prepared, identity, contentPlan, serialization = false) {
      current();
      const request = callbacks.request(originals, prepared);
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'content' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime;
      const complete = serialization ? moon.clientProgramCompleteRequestSerializationPreparation
        : moon.clientProgramCompleteRequestContentPreparation;
      const adopt = moon.clientProgramAdoptRequestContentPreparation;
      if (typeof complete !== 'function' || typeof adopt !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      state.contentPlan = contentPlan;
      // Child-count DATA comes from this same typed selected Plan. It neither
      // retains another Resource original nor replaces the adopted Core Ledger.
      const run = {prepared, request, producer, purpose: 'local-content', model: undefined,
        effectful: false, content: contentPlan, original: state.original, required: undefined,
        children: [], fileIdentity: undefined, value: undefined};
      state.adopting = true;
      try {
        registerRequestRun(run, () => {
          run.required = serialization ? undefined : callbacks.contentRequirements(originals, prepared, contentPlan);
          checked(Reflect.apply(complete, moon, serialization
            ? [state.parent, producer.receipt, contentPlan] : [state.parent, producer.receipt, identity, contentPlan]));
          return checked(Reflect.apply(adopt, moon, [state.parent, identity]));
        });
        state.contentPlan = state.contentCompilation = state.contentGraph = undefined;
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    adoptEffectPreparation(prepared, request, identity, operationPlan) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.holder === undefined ||
          state.compilationKind !== 'effectful' || state.effectBorrowMethods === undefined ||
          state.adopting || runs.has(prepared) || pendingRunRegistrations.has(prepared) ||
          producer.liveRuns === Number.MAX_SAFE_INTEGER ||
          liveRuns.size + pendingRunRegistrations.size >= 4096 || operationPlan === null || typeof operationPlan !== 'object') {
        fail('ForeignInstalledSourceProducer');
      }
      const methods = state.effectBorrowMethods;
      if (methods.clientProgramEffectPreparationInputRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      // Retain the actual selected Plan before either fallible Core operation.
      // Failed completion stays on this same Request for original cleanup.
      state.effectPlan = operationPlan;
      state.adopting = true;
      try {
        checked(methods.clientProgramCompleteRequestEffectPreparation(state.parent, producer.receipt, operationPlan));
        const value = checked(methods.clientProgramAdoptRequestEffectPreparation(state.parent, identity));
        const run = {prepared, request, producer, purpose: 'source-compute', model: undefined,
          effectful: true, content: undefined, operationPlan, original: state.original,
          children: [], fileIdentity: undefined, value};
        producer.liveRuns++;
        runs.set(prepared, run); liveRuns.add(run);
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    adoptEffectModelPreparation(prepared, request, identity, operationPlan, retainedRun) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.holder === undefined ||
          state.compilationKind !== 'effectful' || state.effectBorrowMethods === undefined ||
          state.adopting || runs.has(prepared) || pendingRunRegistrations.has(prepared) ||
          producer.liveRuns === Number.MAX_SAFE_INTEGER ||
          liveRuns.size + pendingRunRegistrations.size >= 4096 || operationPlan === null || typeof operationPlan !== 'object' ||
          retainedRun === null || typeof retainedRun !== 'object' || types.isProxy(retainedRun)) {
        fail('ForeignInstalledSourceProducer');
      }
      const fields = Object.getOwnPropertyDescriptors(retainedRun);
      for (const [name, original] of [['manager', view], ['runtime', state.context.runtime],
        ['preparationKind', 'effect-plan'], ['prepared', prepared], ['request', identity],
        ['requestInput', request], ['operationPlan', operationPlan], ['original', undefined],
        ['modelScope', undefined], ['value', undefined], ['closed', false]]) {
        if (!Object.hasOwn(fields[name] ?? {}, 'value') ||
            fields[name]?.value !== original) fail('ForeignInstalledSourceProducer');
      }
      const methods = state.effectBorrowMethods;
      if (typeof methods.clientProgramPrepareRequestEffectModelReadScope !== 'function' ||
          typeof methods.clientProgramAdoptRequestEffectModelPreparation !== 'function') {
        fail('NodeManagedRunRuntimeUnavailable');
      }
      if (methods.clientProgramEffectPreparationInputRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      // The existing outer Run already owns this construction. Store its SAME
      // Scope before completion/adoption can fail; no cleanup callback, new
      // manager admission or second Scope owner is introduced.
      retainedRun.original = state.original;
      state.effectPlan = operationPlan;
      state.adopting = true;
      try {
        retainedRun.modelScope = checked(methods.clientProgramPrepareRequestEffectModelReadScope(
          state.parent, producer.receipt, operationPlan));
        checked(methods.clientProgramCompleteRequestEffectPreparation(state.parent, producer.receipt, operationPlan));
        const value = checked(methods.clientProgramAdoptRequestEffectModelPreparation(
          state.parent, identity, retainedRun.modelScope));
        const run = {prepared, request, producer, purpose: 'source-compute', model: undefined,
          effectful: true, content: undefined, operationPlan, original: state.original,
          children: [], fileIdentity: undefined, value};
        producer.liveRuns++;
        runs.set(prepared, run); liveRuns.add(run);
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    severPreparation(prepared, original) {
      const run = runs.get(prepared), producer = run?.producer, state = producer?.preparation;
      if (run === undefined || run.original !== original || state === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.holder === undefined) {
        // A valid return consumes the token before a possible settlement
        // failure. These fields are cut only after the exact Core sever
        // witness; retry continues the retained Run cleanup, never returns a
        // consumed holder or reconstructs a Prepared identity.
        if (state.prepared === undefined && run.prepared === undefined && run.request === undefined &&
            producer.body === undefined && producer.request === undefined) return;
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      const severed = state.effectBorrowMethods === undefined
        ? moon.clientProgramPreparationBorrowRead(state.holder) === prepared &&
          moon.clientProgramPreparationBorrowRetirementStarted(state.holder) === true
        : state.effectBorrowMethods.clientProgramEffectPreparationInputRead(state.holder) === prepared &&
          state.effectBorrowMethods.clientProgramEffectPreparationInputRetirementStarted(state.holder) === true;
      if (state.prepared !== prepared || severed !== true) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.contentPreparation !== undefined) {
        if (state.contentPreparation.retired !== true) fail('InstalledContentRunCleanupPending');
        state.contentPreparation = undefined;
      }
      // Original membership/currentness depends only on this receipt/state,
      // not the heavy request after retirement has fenced new operations.
      producer.body = producer.request = producer.snapshotPublication = undefined;
      run.prepared = run.request = undefined;
      state.prepared = state.snapshot = state.snapshotDocument = state.parametersCursor = undefined;
      state.capturePlan = state.effectPlan = run.operationPlan = run.content = undefined;
      state.modelProviderBinding = undefined;
      state.preparationFailure = state.originalCheckResult = state.projectOriginalCheck = undefined;
      state.preparationFailed = false;
      const holder = state.holder;state.holder = undefined;
      checked(state.effectBorrowMethods === undefined
        ? state.context.runtime.clientProgramPreparationBorrowReturn(holder)
        : state.effectBorrowMethods.clientProgramEffectPreparationInputReturn(holder));
    },
    retireSeveredPreparation(original) {
      let run;
      for (const candidate of liveRuns) if (candidate.original === original) {run=candidate;break;}
      if (run === undefined || run.prepared !== undefined || run.request !== undefined ||
          !resourceRuntime.ordinaryManagedRunStatus(original).stopped) fail('InstalledSourceRunCleanupPending');
      const producer=run.producer,state=producer.preparation;
      if (state===undefined || state.holder!==undefined || state.prepared!==undefined || producer.liveRuns<1) {
        fail('ForeignInstalledSourceProducer');
      }
      liveRuns.delete(run);producer.liveRuns--;
      producer.preparation=undefined;
      state.parent=state.admission=state.original=state.context=undefined;
      state.compilationKind=state.preparationFailure=state.originalCheckResult=state.projectOriginalCheck=undefined;state.preparationFailed=false;
      state.compilationFamily=undefined;
      state.policyVerifier=state.policySignal=undefined;state.policyVerifierSelected=false;
      run.value=run.producer=undefined;
      releaseFinishedProducer(producer);
    },
    borrowPreparation(prepared, request) {
      current();
      const producer = producerForRequest(request);
      const state = producer?.preparation;
      if (state === undefined) return undefined;
      if (state.prepared !== prepared || state.holder === undefined || state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      return checked(state.effectBorrowMethods === undefined
        ? state.context.runtime.clientProgramPreparationBorrowSibling(state.holder)
        : state.effectBorrowMethods.clientProgramEffectPreparationInputSibling(state.holder));
    },
    intentCid(receipt, body) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== body || producer.finished) fail('ForeignInstalledSourceProducer');
      const state = producer.preparation;
      if (state?.parent !== undefined) {
        // Fixed shallow DATA projection of the SAME detached snapshot. No
        // second serializer, native hash operation or no-owner fallback.
        const value = {kind: body.kind, input: body.input, parameters: body.parameters,
          ...(Object.hasOwn(body, 'stopBefore') ? {stopBefore: body.stopBefore} : {}),
          ...(Object.hasOwn(body, 'readOnly') ? {readOnly: body.readOnly} : {})};
        const moon = state.context.runtime;
        const cid = checked(moon.clientProgramPrepareRequestSubmittedIntent(state.parent, receipt, value));
        // The original native/canonical/writer stack has returned. Only now
        // may the same owner reduce its temporary constructor peak.
        checked(moon.clientProgramFinishRequestSubmittedIntent(state.parent, receipt));
        return cid;
      }
      return callbacks.intent(originals, view, body);
    },
    finishSourceProducer(receipt, terminal) {
      const producer = producerFor(receipt);
      if (terminal !== 'failed' && terminal !== 'returned') fail('ForeignInstalledSourceProducer');
      producer.finished = true; producer.body = undefined;
      if (producer.liveRuns === 0 && producer.preparation !== undefined) {
        if (producer.preparation.recovery?.childrenPending() === true) fail('InstalledSourceRunCleanupPending');
        producer.request = producer.snapshotPublication = undefined;
        cleanupRequestInput(producer.preparation, retireInitialPreparation);
        producer.preparation = undefined;
      }
      producers.delete(producer);
      releaseFinishedProducer(producer);
    },
    beforeResultRead() {current();}, assertResultReadCurrent: current,
    // Existing original cleanup only; neither a caller terminal flag nor
    // request completion can acknowledge this Run or its physical children.
    retireRun(prepared, original) {
      if (retiredRuns.has(prepared)) {
        if (retiredRuns.get(prepared) !== original) fail('ForeignInstalledSourceProducer');
        return;
      }
      const run = runs.get(prepared);
      if (run === undefined || original === undefined || run.original !== original) {
        fail('ForeignInstalledSourceProducer');
      }
      const observed = resourceRuntime.ordinaryManagedRunStatus(original);
      if (!observed.stopped || run.children.some(child => child.flight !== undefined || !child.closed)) {
        fail('InstalledSourceRunCleanupPending');
      }
      const producer = run.producer;
      if (producer.liveRuns < 1) fail('ForeignInstalledSourceProducer');
      runs.delete(prepared);
      liveRuns.delete(run);
      retiredRuns.set(prepared, original);
      producer.liveRuns--;
      run.prepared = run.request = run.producer = undefined;
      run.model = run.content = run.operationPlan = run.required = run.fileIdentity = undefined;
      run.children = [];
      releaseFinishedProducer(producer);
    },
    // Project ordinary Sources adopt their existing Request. Their view no
    // longer exports the detached Source-compute Root preparation entrance.
    ...(project ? {} : {prepareRun(prepared) {
      return prepareRun(prepared, 'source-compute', undefined);
    }}),
    prepareRead(prepared, declaration, originalRun, occurrence) {
      const run = runFor(prepared);
      const declared = bundle?.sources.findIndex(source => source.declaration === declaration);
      const index = project ? occurrence?.task : declared;
      const expectedRun = run.producer.preparation === undefined ? run.original : run.value;
      if (declared === undefined || declared < 0 || run.prepared !== prepared ||
          expectedRun === undefined || expectedRun !== originalRun ||
          project && (!Number.isSafeInteger(index) || index < 0 || index >= 32 ||
            occurrence.stage !== index || occurrence.input !== 0) ||
          run.children.some(child => child.index === index)) fail('InstalledSourcePreparationMismatch');
      const child = {index, attempted: false, closed: false, bytes: undefined, flight: undefined,
        closing: false, cleanup: undefined, cleanupStatus: undefined, cleanupRetry: undefined,
        reader: undefined, readerClose: undefined, readerStatus: undefined,
        readerCloseSeen: false, readerStatusSeen: false, readerCloseAcknowledged: false};
      run.children.push(child);
      return Object.freeze({originalSource: Object.freeze({}),
        ...(project ? {retainChild(actual) {
          if (child.closed || child.closing || actual === null ||
              typeof actual !== 'object' && typeof actual !== 'function' ||
              child.reader !== undefined && child.reader !== actual) fail('InstalledSourcePreparationMismatch');
          // The installing Connector transfers its same acquired reader here,
          // before a callback/current check can reject the physical result.
          // This retains cleanup responsibility, never permission or capacity.
          child.reader = actual;
          captureReader(child);
          runFor(prepared);
        }} : {readOriginalBytes: () => readBytes(run, child)}),
        close: () => closeChild(child),
        status: () => Object.freeze({pending: !child.closed || child.flight !== undefined})});
    },
    prepareKeyedRead(prepared, declaration, originalRun, request) {
      const run = runFor(prepared);
      if (!project || run.purpose !== 'local-content' || run.original !== originalRun ||
          !bundle.sources.some(source => source.declaration === declaration) ||
          request === null || typeof request !== 'object' ||
          run.children.length >= run.required.attempts ||
          run.children.some(child => child.request === request)) fail('InstalledSourcePreparationMismatch');
      const child = {request, attempted: false, closed: false, bytes: undefined, flight: undefined,
        closing: false, cleanup: undefined, cleanupStatus: undefined, cleanupRetry: undefined,
        reader: undefined, readerClose: undefined, readerStatus: undefined,
        readerCloseSeen: false, readerStatusSeen: false, readerCloseAcknowledged: false};
      run.children.push(child);
      return Object.freeze({originalSource: Object.freeze({}), retainChild(actual) {
        if (child.closed || child.closing || actual === null ||
            typeof actual !== 'object' && typeof actual !== 'function' ||
            child.reader !== undefined && child.reader !== actual) fail('InstalledSourcePreparationMismatch');
        child.reader = actual;
        captureReader(child);
        runFor(prepared);
      }, close: () => closeChild(child),
      status: () => Object.freeze({pending: !child.closed || child.flight !== undefined})});
    },
    async close() {
      if (closed) return status();
      if (flight !== undefined) return flight;
      closing = true;
      const work = Promise.resolve().then(async () => {
        // A failed before-snapshot call may not have returned its receipt to
        // the SDK. This installed owner still retains and retries that exact
        // initial child, rather than stranding it behind the producer gate.
        for (const producer of producers) if (producer.finished && producer.liveRuns === 0) {
          if (producer.preparation !== undefined) {
            if (producer.preparation.recovery?.childrenPending() === true) return status();
            cleanupRequestInput(producer.preparation, retireInitialPreparation);
            producer.preparation = undefined;
          }
          releaseFinishedProducer(producer);
        }
        if (producers.size !== 0) return status();
        let childPending = false, failure;
        for (const run of liveRuns) {
          for (const child of run.children) {
            try {if (pending(await closeChild(child))) childPending = true;}
            catch (cause) {childPending = true; failure ??= cause;}
          }
          if (run.original === undefined) continue;
          const observed = resourceRuntime.ordinaryManagedRunStatus(run.original);
          if (observed.admitted && !observed.stopped) childPending = true;
        }
        if (failure !== undefined) throw failure;
        if (childPending) return status();
        // The same successful installation cleanup also owns unfinished
        // preparation records which never obtained an original Run.
        for (const run of liveRuns) {
          const producer = run.producer;
          if (producer.liveRuns < 1) fail('ForeignInstalledSourceProducer');
          producer.liveRuns--;
          liveRuns.delete(run);
          run.prepared = run.request = run.producer = undefined;
          run.model = run.content = run.required = run.fileIdentity = undefined;
          run.children = [];
          releaseFinishedProducer(producer);
        }
        if (producers.size !== 0) return status();
        bundle = undefined; liveRuns.clear(); closed = true; return status();
      });
      flight = work;
      try {return await work;} finally {if (flight === work) flight = undefined;}
    },
  });
  installations.set(view, {originals, source, current});
  current();
  try {
    if (source) {
      await callbacks.prepare(originals, view);
      bundle = callbacks.read(originals);
      if (!Array.isArray(bundle.sources) || bundle.sources.length < 1 ||
          bundle.sources.length > 128) fail('InstalledSourcePreparationMismatch');
    }
    current(); return view;
  } catch (cause) {
    const error = Object.assign(new Error('InstalledSourcePreparationCleanupPending', {cause}),
      {code: 'InstalledSourcePreparationCleanupPending', cleanupPending: true});
    error.cleanupHandle = Object.freeze({status, retry: view.close});
    throw error;
  }
}
