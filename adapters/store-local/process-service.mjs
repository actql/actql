// Control-side physical Store owner. Requests arrive only through an installed
// process channel after execution admission. Files and sealed bodies outlive
// that process; neither a storage key nor a seal report admits an ActQL result.
import {createLocalRetainedStore, validateLocalStoreConfiguration, RetainedFileError} from './files.mjs';

export function createProcessRetainedStore(options) {
  const limits = validateLocalStoreConfiguration(options);
  const outputs = new Map();
  let identity, store, opening, stopped = false, closed = false, observed;
  const fail = code => { throw new RetainedFileError(code); };
  const cleanupHandle = Object.freeze({
    status: () => ({pending: !!opening || !!store?.status().cleanupPending}),
    retry: async () => { if (opening) await opening; if (store) await store.cleanup(); return cleanupHandle.status(); },
  });
  const exact = owner => {
    if (!identity || owner.session !== identity.session || owner.run !== identity.run || stopped || closed) {
      fail('ForeignStoreSession');
    }
  };
  const invoke = async (request, signal, owner) => {
    exact(owner);
    signal.throwIfAborted();
    if (!request || typeof request !== 'object' || Array.isArray(request)) fail('InvalidStoreRequest');
    if (request.command === 'reserve' && Object.keys(request).sort().join(',') === 'bytes,command,output') {
      const {output, bytes} = request;
      if (typeof output !== 'string' || !output.length || output.length > 256 || outputs.has(output) ||
          !Number.isSafeInteger(bytes) || bytes < 0 || bytes > limits.capacityBytes) fail('InvalidStoreRequest');
      if (!store) {
        opening ??= createLocalRetainedStore(limits);
        try { store = await opening; } finally { opening = undefined; }
      }
      exact(owner); signal.throwIfAborted();
      const writer = store.reserve(bytes);
      const entry = {writer, descriptor: undefined, body: undefined, read: undefined};
      outputs.set(output, entry);
      try {
        await writer.start();
        exact(owner); signal.throwIfAborted();
        entry.descriptor = writer.delegate(identity.session);
        return entry.descriptor;
      } catch (error) {
        writer.cancel();
        await writer.cleanupHandle.retry();
        if (!writer.cleanupHandle.status().pending) outputs.delete(output);
        throw error;
      }
    }
    if (request.command === 'seal' && Object.keys(request).sort().join(',') === 'command,output,report') {
      const entry = outputs.get(request.output);
      if (!entry?.descriptor || entry.body) fail('ForeignStoreReport');
      entry.body = await entry.writer.finishDelegated(request.report);
      return {output: request.output, bytes: request.report.bytes, cid: request.report.cid};
    }
    if (request.command === 'read' && Object.keys(request).sort().join(',') === 'command,output') {
      const entry = outputs.get(request.output);
      if (!entry?.body || entry.read) fail('RetainedUnavailable');
      entry.read = entry.body.delegateRead(identity.session);
      return entry.read.descriptor;
    }
    if (request.command === 'read-finish' && Object.keys(request).sort().join(',') === 'command,output,report') {
      const entry = outputs.get(request.output);
      if (!entry?.read) fail('ForeignStoreReadReport');
      const result = entry.read.finish(request.report);
      entry.read = undefined;
      return result;
    }
    fail('InvalidStoreRequest');
  };
  return Object.freeze({
    service: Object.freeze({invoke, cleanupHandle}),
    observe(channel) {
      if (identity) fail('StoreAlreadyBound');
      identity = Object.freeze({...channel.identity()});
      observed = channel.cleanupHandle.whenStopped().then(() => {
        stopped = true;
        for (const entry of outputs.values()) {
          // Actual exit is the only fallback for a missing writer-close report.
          // Independently sealed outputs are not revoked by this event.
          if (!entry.body) entry.writer.confirmDelegatedStopped();
          if (entry.read) { entry.read.confirmStopped(); entry.read = undefined; }
        }
      });
      observed.catch(() => {});
    },
    body(output) { return outputs.get(output)?.body; },
    status() { return store?.status(); },
    cleanupHandle,
    async close() {
      closed = true;
      if (opening) { try { store = await opening; } finally { opening = undefined; } }
      store?.close();
      if (store) await store.cleanup();
    },
  });
}
