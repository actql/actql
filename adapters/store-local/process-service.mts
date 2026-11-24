// Control-side physical Store owner. Requests arrive only through an installed
// process channel after execution admission. Files and sealed bodies outlive
// that process; neither a storage key nor a seal report admits an ActQL result.
import {createLocalRetainedStore, validateLocalStoreConfiguration, RetainedFileError} from './files.mjs';
import type {DelegatedWriteLease, LocalRetainedStore} from './files.mjs';
import type {processStoreContext} from './process-binding.mjs';

type Writer = ReturnType<LocalRetainedStore['reserve']>;
type Body = Awaited<ReturnType<Writer['finishDelegated']>>;
type Borrow = ReturnType<Body['delegateRead']>;
type Output = {writer: Writer; descriptor?: DelegatedWriteLease; body?: Body; reads: Map<string, Borrow>};
type Session = Pick<ReturnType<typeof processStoreContext>, 'session' | 'run'>;
type ProcessChannel = {identity: () => Session; cleanupHandle: {whenStopped: () => Promise<unknown>}};
type UncheckedStoreRequest = {
  command?: unknown;
  output?: unknown;
  bytes?: unknown;
  report?: NonNullable<Parameters<Writer['finishDelegated']>[0]> | null;
};

export function createProcessRetainedStore(options: Parameters<typeof validateLocalStoreConfiguration>[0]) {
  const limits = validateLocalStoreConfiguration(options);
  const outputs = new Map<string, Output>();
  let identity: Session | undefined, store: LocalRetainedStore | undefined, opening: Promise<LocalRetainedStore> | undefined,
    stopped = false, closed = false, observed: Promise<unknown> | undefined;
  const fail: (code: string) => never = code => { throw new RetainedFileError(code); };
  const cleanupHandle = Object.freeze({
    status: () => ({pending: !!opening || !!store?.status().cleanupPending}),
    retry: async () => { if (opening) await opening; if (store) await store.cleanup(); return cleanupHandle.status(); },
  });
  const exact = (owner: Session) => {
    if (!identity || owner.session !== identity.session || owner.run !== identity.run || stopped || closed) {
      fail('ForeignStoreSession');
    }
  };
  const invoke = async (request: UncheckedStoreRequest | null | undefined, signal: AbortSignal, owner: Session) => {
    exact(owner);
    signal.throwIfAborted();
    if (!request || typeof request !== 'object' || Array.isArray(request)) fail('InvalidStoreRequest');
    if (request.command === 'reserve' && Object.keys(request).sort().join(',') === 'bytes,command,output') {
      const {output, bytes} = request;
      if (typeof output !== 'string' || !output.length || output.length > 256 || outputs.has(output) ||
          outputs.size >= limits.maxEntries ||
          !Number.isSafeInteger(bytes) || (bytes as number) < 0 || (bytes as number) > limits.capacityBytes) fail('InvalidStoreRequest');
      if (!store) {
        opening ??= createLocalRetainedStore(limits);
        try { store = await opening; } finally { opening = undefined; }
      }
      exact(owner); signal.throwIfAborted();
      const writer = store.reserve(bytes as number);
      const entry: Output = {writer, descriptor: undefined, body: undefined, reads: new Map()};
      outputs.set(output, entry);
      try {
        await writer.start();
        exact(owner); signal.throwIfAborted();
        entry.descriptor = writer.delegate(identity!.session);
        return entry.descriptor;
      } catch (error) {
        writer.cancel();
        await writer.cleanupHandle.retry();
        if (!writer.cleanupHandle.status().pending) outputs.delete(output);
        throw error;
      }
    }
    if (request.command === 'seal' && Object.keys(request).sort().join(',') === 'command,output,report') {
      const entry = outputs.get(request.output as string);
      if (!entry?.descriptor || entry.body) fail('ForeignStoreReport');
      entry.body = await entry.writer.finishDelegated(request.report);
      return {output: request.output, bytes: request.report!.bytes, cid: request.report!.cid};
    }
    if (request.command === 'read' && Object.keys(request).sort().join(',') === 'command,output') {
      const entry = outputs.get(request.output as string);
      if (!entry?.body || entry.reads.size >= limits.maxReadersPerBody) fail('RetainedUnavailable');
      const read = entry.body.delegateRead(identity!.session);
      entry.reads.set(read.descriptor.token, read);
      return read.descriptor;
    }
    if (request.command === 'read-finish' && Object.keys(request).sort().join(',') === 'command,output,report') {
      const entry = outputs.get(request.output as string);
      const read = entry?.reads.get(request.report?.token as string);
      if (!read) fail('ForeignStoreReadReport');
      const result = read.finish(request.report);
      entry!.reads.delete(request.report!.token as string);
      return result;
    }
    if (request.command === 'release-sealed' && Object.keys(request).sort().join(',') === 'command,output,report') {
      const entry = outputs.get(request.output as string);
      const report = request.report;
      if (!entry?.body || !report || typeof report !== 'object' || Array.isArray(report) ||
          Object.keys(report).sort().join(',') !== 'bytes,cid' ||
          report.cid !== entry.body.cid || report.bytes !== entry.body.bytes) fail('ForeignStoreReport');
      // Only the exact independently sealed generation is revocable here.
      // Existing read owners prevent unlink/capacity release until confirmed.
      entry.body.close();
      await entry.body.cleanupHandle.retry();
      const state = entry.body.cleanupHandle.status();
      // Keep the bounded entry as a tombstone: a lost reply can be answered
      // again and the same output name can never acquire another generation.
      return {version: 'actql-local-file-release/0.1', output: request.output,
        bytes: report.bytes, cid: report.cid, reclaimed: !state.pending};
    }
    fail('InvalidStoreRequest');
  };
  return Object.freeze({
    service: Object.freeze({invoke, cleanupHandle}),
    observe(channel: ProcessChannel) {
      if (identity) fail('StoreAlreadyBound');
      identity = Object.freeze({...channel.identity()});
      observed = channel.cleanupHandle.whenStopped().then(() => {
        stopped = true;
        for (const entry of outputs.values()) {
          // Actual exit is the only fallback for a missing writer-close report.
          // Independently sealed outputs are not revoked by this event.
          if (!entry.body) entry.writer.confirmDelegatedStopped();
          for (const read of entry.reads.values()) read.confirmStopped();
          entry.reads.clear();
        }
      });
      observed.catch(() => {});
    },
    body(output: string) { return outputs.get(output)?.body; },
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
