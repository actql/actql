import {open} from 'node:fs/promises';
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
  let closing = false, closed = false, bundle, flight, count = 0, checkingBundle = false;
  const receipts = new WeakMap(), producers = new Set(), runs = new Map();
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
  async function closeChild(child) {
    if (child.closed) return Object.freeze({pending: false});
    if (child.flight !== undefined) return Object.freeze({pending: true});
    if (child.cleanup !== undefined) {
      if (pending(Reflect.apply(child.cleanupStatus, child.cleanup, []))) {
        await Reflect.apply(child.cleanupRetry, child.cleanup, []);
      }
      if (pending(Reflect.apply(child.cleanupStatus, child.cleanup, []))) return Object.freeze({pending: true});
      child.cleanup = child.cleanupStatus = child.cleanupRetry = undefined;
    }
    child.bytes = undefined; child.closed = true;
    return Object.freeze({pending: false});
  }
  function runFor(prepared) {
    current();
    const run = runs.get(prepared);
    if (run === undefined) fail('NodeManagedRunAdmissionUnavailable');
    resourceRuntime.assertOrdinaryManagedRunCurrent(run.original, prepared);
    return run;
  }
  function prepareRun(prepared, purpose, model) {
    current();
    const old = runs.get(prepared);
    if (old !== undefined) {
      if (old.purpose !== purpose || old.model !== model) fail('ForeignInstalledModelPreparation');
      return runFor(prepared).original;
    }
    const request = callbacks.request(originals, prepared);
    const producer = [...producers].find(value => value.request === request && !value.finished);
    if (producer === undefined || runs.size === 4096) fail('ForeignInstalledSourceProducer');
    const run = {prepared, request, producer, purpose, model, original: undefined,
      children: [], fileIdentity: undefined};
    runs.set(prepared, run);
    // A failed quote remains attached to this one preparation. It cannot be
    // retried under a different purpose or replaced by another original.
    const required = purpose === 'local-mock-model'
      ? callbacks.mockRequirements(originals, prepared, model)
      : callbacks.requirements(originals, prepared);
    run.original = resourceRuntime.retainOrdinaryManagedRun(prepared, required,
      () => {current(); if (run.producer.request !== request) fail('ForeignInstalledSourceProducer');},
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
    beforeSourceSnapshot(kind, input, options) {
      current();
      if (count === 4096 || producers.size === 32) fail('InstalledSourceProducerLimit');
      count++;
      const receipt = Object.freeze({});
      const producer = {receipt, kind, body: undefined, request: undefined, finished: false};
      receipts.set(receipt, producer); producers.add(producer);
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
    },
    bindSourceRequest(receipt, body, request) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== body || producer.request !== undefined || producer.finished) fail('ForeignInstalledSourceProducer');
      producer.request = request;
    },
    intentCid(receipt, body) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== body || producer.finished) fail('ForeignInstalledSourceProducer');
      return callbacks.intent(originals, view, body);
    },
    finishSourceProducer(receipt, terminal) {
      const producer = producerFor(receipt);
      if (terminal !== 'failed' && terminal !== 'returned') fail('ForeignInstalledSourceProducer');
      producer.finished = true; producer.body = undefined; producers.delete(producer);
    },
    beforeResultRead() {current();}, assertResultReadCurrent: current,
    prepareRun(prepared) {
      return prepareRun(prepared, 'source-compute', undefined);
    },
    prepareLocalMockModelRun(prepared, model) {
      return prepareRun(prepared, 'local-mock-model', model);
    },
    prepareRead(prepared, declaration, originalRun) {
      const run = runFor(prepared);
      const index = bundle?.sources.findIndex(source => source.declaration === declaration);
      if (index === undefined || index < 0 || run.original !== originalRun ||
          run.children.some(child => child.index === index)) fail('InstalledSourcePreparationMismatch');
      const child = {index, attempted: false, closed: false, bytes: undefined, flight: undefined,
        cleanup: undefined, cleanupStatus: undefined, cleanupRetry: undefined};
      run.children.push(child);
      return Object.freeze({originalSource: Object.freeze({}),
        readOriginalBytes: () => readBytes(run, child), close: () => closeChild(child),
        status: () => Object.freeze({pending: !child.closed || child.flight !== undefined})});
    },
    async close() {
      if (closed) return status();
      if (flight !== undefined) return flight;
      closing = true;
      const work = Promise.resolve().then(async () => {
        if (producers.size !== 0) return status();
        for (const run of runs.values()) {
          for (const child of run.children) if (pending(await closeChild(child))) return status();
          if (run.original === undefined) continue;
          const observed = resourceRuntime.ordinaryManagedRunStatus(run.original);
          if (observed.admitted && !observed.stopped) return status();
        }
        bundle = undefined; runs.clear(); closed = true; return status();
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
      if (!Array.isArray(bundle.sources) || bundle.sources.length !== 2) fail('InstalledMockCatalogueUnavailable');
    }
    current(); return view;
  } catch (cause) {
    const error = Object.assign(new Error('InstalledSourcePreparationCleanupPending', {cause}),
      {code: 'InstalledSourcePreparationCleanupPending', cleanupPending: true});
    error.cleanupHandle = Object.freeze({status, retry: view.close});
    throw error;
  }
}
