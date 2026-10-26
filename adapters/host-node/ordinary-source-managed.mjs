import {closedValuesPreparationAvailable,beginClosedValuesInput,bindClosedValuesSnapshot,cleanupClosedValuesInput,checkedPreparation} from '../local-node/closed-values-preparation-adapter.mjs';
import {matchesPublishedSubmissionSnapshot} from '../../packages/sdk/internal/private-source-preparation.mjs';
import {open} from 'node:fs/promises';
import {checked} from '../host-common/runtime-result.mjs';
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
  let closing = false, closed = false, bundle, flight, checkingBundle = false;
  const receipts = new WeakMap(), producers = new Set(), runs = new WeakMap();
  // Exact Prepared lookup is provenance, not a second strong payload root.
  // The live inventory owns each record until its actual retirement.
  const liveRuns = new Set();
  const retiredRuns = new WeakMap();
  const retireInitialPreparation = prepared => callbacks.retireInitialPreparation(originals, prepared);
  const releaseFinishedProducer = producer => {
    if (producer.finished && producer.liveRuns === 0) {
      producer.request = undefined;
      producer.snapshotPublication = undefined;
    }
  };
  const producerForRequest = request => {
    for (const producer of producers) if (producer.request === request && !producer.finished) return producer;
    return undefined;
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
  function runFor(prepared) {
    current();
    const run = runs.get(prepared);
    if (run === undefined) fail('NodeManagedRunAdmissionUnavailable');
    resourceRuntime.assertOrdinaryManagedRunCurrent(run.original, run.operationPlan ?? (run.producer.preparation === undefined ? prepared : run.producer.receipt));
    return run;
  }
  function prepareRun(prepared, purpose, model, effectful = false, content, operationPlan) {
    current();
    if (retiredRuns.has(prepared)) fail('ForeignInstalledModelPreparation');
    const old = runs.get(prepared);
    if (old !== undefined) {
      if (old.purpose !== purpose || old.model !== model || old.effectful !== effectful || old.content !== content || old.operationPlan !== operationPlan) {
        fail('ForeignInstalledModelPreparation');
      }
      return runFor(prepared).original;
    }
    const request = callbacks.request(originals, prepared);
    const producer = producerForRequest(request);
    if (producer === undefined || liveRuns.size === 4096) fail('ForeignInstalledSourceProducer');
    const run = {prepared, request, producer, purpose, model, effectful, content, operationPlan, original: undefined,
      children: [], fileIdentity: undefined};
    if (producer.liveRuns === Number.MAX_SAFE_INTEGER) fail('InstalledSourceProducerLimit');
    producer.liveRuns++;
    runs.set(prepared, run);
    liveRuns.add(run);
    // A failed quote remains attached to this one preparation. It cannot be
    // retried under a different purpose or replaced by another original.
    const required = operationPlan !== undefined
      ? callbacks.effectRequirements(originals, prepared, operationPlan)
      : purpose === 'local-content'
      ? callbacks.contentRequirements(originals, prepared, content)
      : purpose === 'local-mock-model'
      ? callbacks.mockRequirements(originals, prepared, model)
      : effectful ? callbacks.effectRequirements(originals, prepared)
      : callbacks.requirements(originals, prepared);
    run.required = required;
    const producerReceipt = producer.receipt;
    const requestOriginals = new WeakSet();
    requestOriginals.add(request);
    run.original = resourceRuntime.retainOrdinaryManagedRun(operationPlan ?? prepared, required,
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
  const view = Object.freeze({
    assertCurrent: current,
    beforeSourceSnapshot(kind, input, options, originalConnection) {
      current();
      if (producers.size === 32) fail('InstalledSourceProducerLimit');
      const receipt = Object.freeze({});
      const producer = {receipt, kind, body: undefined, request: undefined, finished: false, liveRuns: 0, snapshotPublication: undefined, preparation: undefined};
      receipts.set(receipt, producer); producers.add(producer);
      // One preparation protocol; the narrow shape adapter is staged until
      // every supported frontend has a construction proof for this owner.
      if (kind === 'program' && options === undefined && callbacks.preparationContext !== undefined) {
        const context = callbacks.preparationContext(originals);
        if (closedValuesPreparationAvailable(context)) {
          const state = {context, original: undefined, admission: undefined,
            phase: undefined, prepared: undefined, holder: undefined, adopting: false};
          producer.preparation = state;
          try {
            const required = callbacks.preparationRequirements(originals);
            const accepted = beginClosedValuesInput(state, input, receipt, originalConnection, required, () => {
              // Cleanup may continue while the manager is closing. Exact
              // membership/current installation, not raw Prepared, is retained.
              if (closed || receipts.get(receipt) !== producer || producer.preparation !== state) {
                fail('ForeignInstalledSourceProducer');
              }
              callbacks.validator(originals);
            });
            if (!accepted) producer.preparation = undefined;
          } catch (cause) {
            producer.finished = true;
            try {
              cleanupClosedValuesInput(state);
              producer.preparation = undefined; producers.delete(producer);
            } catch (cleanupCause) {
              throw Object.assign(new Error('NodeLocalPreparationCleanupPending', {cause}),
                {code: 'NodeLocalPreparationCleanupPending', cleanupPending: true,
                  cleanupCause});
            }
            throw cause;
          }
        }
      }
      return receipt;
    },
    beforeSourceQuery(format, text, parameters, options) {
      // SDK owns documented option and input validation/snapshot semantics.
      // No data-only restriction on the trusted embedding caller is added.
      return view.beforeSourceSnapshot('aql', text, options);
    },
    bindSourceSnapshot(receipt, body) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== undefined || producer.finished) fail('ForeignInstalledSourceProducer');
      producer.body = body;
      if (producer.preparation !== undefined) bindClosedValuesSnapshot(producer.preparation, body);
    },
    publishSourceSnapshot(receipt, body, publication) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== body || producer.finished || producer.snapshotPublication !== undefined ||
          !matchesPublishedSubmissionSnapshot(publication, body)) fail('ForeignInstalledSourceProducer');
      producer.snapshotPublication = publication;
    },
    bindSourceRequest(receipt, body, request) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== body || producer.request !== undefined || producer.finished) fail('ForeignInstalledSourceProducer');
      producer.request = request;
    },
    submittedIntentOriginal(request) {
      current();
      const producer = producerForRequest(request);
      const state = producer?.preparation;
      if (state === undefined) return undefined;
      if (producer.finished || state.phase === undefined || state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      const intent = state.context.runtime.clientProgramClosedValuesSubmittedIntentOriginal(state.phase);
      if (intent === undefined) fail('ForeignInstalledSourceProducer');
      return intent;
    },
    fundedPreparation(request, environment) {
      current();
      const producer = producerForRequest(request);
      const state = producer?.preparation;
      if (state === undefined) return undefined;
      if (state.context.environment !== environment || state.phase === undefined || state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      if (state.holder === undefined) {
        const contracts = originals.installation.sequenceContractOriginal;
        if (contracts === undefined || contracts.moon !== moon) fail('ForeignInstalledSourceProducer');
        checkedPreparation(moon,moon.clientProgramPrepareClosedValuesBody(state.phase, environment,
          state.context.preparedEnvironment, contracts.admission));
        // Separate fixed call: semantic/plan constructor stacks have unwound
        // before the same reservation may drop their temporary peak.
        state.holder = checkedPreparation(moon,moon.clientProgramCompleteClosedValuesBody(state.phase));
      }
      const prepared = moon.clientProgramPreparationBorrowRead(state.holder);
      if (prepared === undefined) fail('ForeignInstalledSourceProducer');
      if (state.prepared !== undefined && state.prepared !== prepared) fail('ForeignInstalledSourceProducer');
      state.prepared = prepared;
      return prepared;
    },
    publicationPreparation(prepared) {
      const run = runFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared ||
          state.holder === undefined || !state.adopting || state.phase === undefined) {
        fail('ForeignInstalledSourceProducer');
      }
      return state.phase;
    },
    reservePublication(prepared) {
      const run = runFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared ||
          state.holder === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      return checkedPreparation(state.context.runtime,
        state.context.runtime.clientProgramReservePublication(
          state.phase, prepared, state.holder));
    },
    compilationOriginal(prepared) {
      const run = runFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared || state.holder === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      const original = state.context.runtime.clientProgramClosedValuesCompilationOriginal(state.phase, prepared);
      if (original === undefined) fail('NodeManagedRunCompilationUnavailable');
      return original;
    },
    adoptPreparation(prepared, request, identity) {
      current();
      const producer = producerForRequest(request);
      const state = producer?.preparation;
      if (state === undefined) return undefined;
      if (state.prepared !== prepared || state.holder === undefined || state.adopting) fail('ForeignInstalledSourceProducer');
      state.adopting = true;
      const outcome = state.context.runtime.clientProgramAdoptClosedValuesPreparation(state.phase,prepared,identity);
      if (runtimeIsError(outcome)) state.adopting = false;
      const value = checked(outcome);
      const run = {prepared,request,producer,purpose:'source-compute',model:undefined,
        effectful:false,content:undefined,original:state.original,children:[],fileIdentity:undefined,value};
      producer.liveRuns++;
      runs.set(prepared,run);liveRuns.add(run);
      return run;
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
      if (state.prepared !== prepared ||
          !state.context.runtime.clientProgramSeverClosedValuesBody(state.phase,state.holder)) {
        fail('ForeignInstalledSourceProducer');
      }
      // Original membership/currentness depends only on this receipt/state,
      // not the heavy request after retirement has fenced new operations.
      producer.body = producer.request = producer.snapshotPublication = undefined;
      run.prepared = run.request = undefined;
      state.prepared = undefined;
      const holder = state.holder;state.holder = undefined;
      checked(state.context.runtime.clientProgramPreparationBorrowReturn(holder));
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
      state.phase=state.admission=state.original=state.context=undefined;
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
      return checked(state.context.runtime.clientProgramPreparationBorrowSibling(state.holder));
    },
    intentCid(receipt, body) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== body || producer.finished) fail('ForeignInstalledSourceProducer');
      return callbacks.intent(originals, view, body, producer.preparation?.phase);
    },
    finishSourceProducer(receipt, terminal) {
      const producer = producerFor(receipt);
      if (terminal !== 'failed' && terminal !== 'returned') fail('ForeignInstalledSourceProducer');
      producer.finished = true; producer.body = undefined;
      if (producer.liveRuns === 0 && producer.preparation !== undefined) {
        producer.request = producer.snapshotPublication = undefined;
        cleanupClosedValuesInput(producer.preparation, retireInitialPreparation);
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
    prepareRun(prepared) {
      return prepareRun(prepared, 'source-compute', undefined);
    },
    prepareContentRun(prepared, selected) {
      if (!project || typeof callbacks.contentRequirements !== 'function') fail('InstalledContentRunPreparationUnavailable');
      return prepareRun(prepared, 'local-content', undefined, false, selected);
    },
    prepareEffectRun() {fail('InstalledEffectPlanUnavailable');},
    prepareEffectPlanRun(prepared, operationPlan) {
      if (operationPlan === null || typeof operationPlan !== 'object') fail('InstalledEffectPlanUnavailable');
      return prepareRun(prepared, 'source-compute', undefined, true, undefined, operationPlan);
    },
    prepareLocalMockModelRun(prepared, model) {
      return prepareRun(prepared, 'local-mock-model', model);
    },
    prepareEffectLocalMockModelRun(prepared, model) {
      return prepareRun(prepared, 'local-mock-model', model, true);
    },
    prepareRead(prepared, declaration, originalRun, occurrence) {
      const run = runFor(prepared);
      const declared = bundle?.sources.findIndex(source => source.declaration === declaration);
      const index = project ? occurrence?.task : declared;
      if (declared === undefined || declared < 0 || run.original !== originalRun ||
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
        for (const producer of producers) if (producer.finished && producer.liveRuns === 0 &&
            producer.preparation !== undefined) {
          cleanupClosedValuesInput(producer.preparation, retireInitialPreparation);
          producer.preparation = undefined;
          producers.delete(producer);
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
          run.prepared = run.request = run.producer = undefined;
          run.model = run.content = run.required = run.fileIdentity = undefined;
          run.children = [];
          releaseFinishedProducer(producer);
        }
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
      if (!Array.isArray(bundle.sources) || (project
        ? bundle.sources.length < 1 || bundle.sources.length > 128
        : bundle.sources.length !== 2)) fail('InstalledSourcePreparationMismatch');
    }
    current(); return view;
  } catch (cause) {
    const error = Object.assign(new Error('InstalledSourcePreparationCleanupPending', {cause}),
      {code: 'InstalledSourcePreparationCleanupPending', cleanupPending: true});
    error.cleanupHandle = Object.freeze({status, retry: view.close});
    throw error;
  }
}
