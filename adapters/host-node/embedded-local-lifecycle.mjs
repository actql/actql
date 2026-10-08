// The existing installed Host owns execution and durable data. This registry
// only leases its in-process connection and retains its physical close retry.
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createInstalledHostShutdown} from './installed-host-cleanup.mjs';

export function installedHostShutdown(host) {
  return createInstalledHostShutdown({
    stop: () => host.checkpoints?.stop(),
    drain: () => host.dispatchOwner.drain(),
    retire: () => host.retireTerminalEffects(),
    checkpoint: () => host.checkpoints?.close(),
    journal: () => host.journal.close(),
    source: () => host.sourceProfile?.close(),
    effect: () => host.installedEffect?.close(),
    store: () => host.store.close(),
  });
}

const closing = () => Object.assign(new Error('ClientHostClosing'),
  {code: 'ClientHostClosing'});

export function createEmbeddedHostRegistry(sameInstallation) {
  const profiles = new Map();
  const forget = (root, entry) => {
    if (profiles.get(root) === entry) profiles.delete(root);
  };
  return Object.freeze({async connect(root, identity, open, options) {
    let entry = profiles.get(root);
    if (entry?.failure !== undefined) {
      // A failed opening can retain physical cleanup after rejecting. Do not
      // replace its owner until the exact retained handle confirms release.
      if (!entry.initializationPending ||
          entry.initializationStatus?.().pending === false) {
        forget(root, entry);
        entry = undefined;
      } else throw entry.failure;
    }
    if (entry === undefined) {
      entry = {identity, leases: 0, accepting: 0, closing: false, handling: new Set()};
      const opened = entry;
      entry.host = Promise.resolve().then(open).then(host => {
        opened.shutdown = installedHostShutdown(host);
        return host;
      }, error => {
        opened.failure = error;
        opened.initializationPending = error?.cleanupPending === true;
        const handle = error?.cleanupHandle;
        opened.initializationStatus = typeof handle?.status === 'function'
          ? handle.status.bind(handle) : undefined;
        if (!opened.initializationPending) forget(root, opened);
        throw error;
      });
      profiles.set(root, entry);
    } else {
      if (entry.closing) throw closing();
      if (!sameInstallation(entry.identity, identity)) {
        throw new TypeError('InstalledHostConfigurationMismatch');
      }
    }
    entry.leases++;
    entry.accepting++;
    const opened = entry;
    let sealed = false, released = false, finished = false, flight;
    const handling = new Set();
    function seal() {
      if (sealed) return;
      sealed = true;
      opened.accepting--;
      if (opened.accepting === 0) opened.closing = true;
    }
    function close() {
      if (flight !== undefined) return flight;
      seal();
      if (!released) {
        released = true;
        opened.leases--;
      }
      flight = Promise.resolve().then(async () => {
        if (finished) return;
        await Promise.allSettled([...handling]);
        if (opened.leases !== 0) { finished = true; return; }
        const host = await opened.host;
        await Promise.allSettled([...opened.handling]);
        try {
          await opened.shutdown.close();
          if (!opened.finalized) {
            // All leases share optional observation finalization as well as
            // physical shutdown. Awaiting export must not duplicate close.
            opened.finalization ??= Promise.resolve().then(async () => {
              host.diagnostic.close();
              if (host.observation !== undefined) await host.observation.close();
              forget(root, opened);
              opened.finalized = true;
            });
            await opened.finalization;
          }
          finished = true;
        } catch (cause) {
          // Retry through this lease, so final release also retires exactly
          // this registry generation. Never reopen adapters to clean them up.
          const error = Object.assign(new Error(cause?.code ?? 'InstalledHostCleanupPending',
            {cause}), {code: cause?.code ?? 'InstalledHostCleanupPending',
            primaryFailure: cause?.primaryFailure ?? cause,
            cleanupPending: true,
            cleanupHandle: Object.freeze({status: opened.shutdown.status, retry: close})});
          throw error;
        }
      }).finally(() => { flight = undefined; });
      return flight;
    }
    let host;
    try { host = await opened.host; }
    catch (error) {
      // Initialization itself retains cleanup; there is no returned Host.
      released = true;
      opened.leases--;
      seal();
      throw error;
    }
    const port = Object.freeze({
      perform(operation, request, signal) {
        if (sealed || opened.closing) return Promise.reject(closing());
        const pending = Promise.resolve().then(() => host.port.perform(operation, request, signal));
        handling.add(pending);
        opened.handling.add(pending);
        pending.finally(() => {
          handling.delete(pending);
          opened.handling.delete(pending);
        }).catch(() => {});
        return pending;
      }, close, seal,
    });
    try { return await connectInProcess(options, port); }
    catch (cause) {
      try { await close(); }
      catch {
        // No Client was returned to own retry. Expose only this connection's
        // recovery operation; provider causes and internal handles stay here.
        const failure = Object.assign(new Error('InstalledLocalConnectionCleanupPending'),
          {code: 'InstalledLocalConnectionCleanupPending', cleanupPending: true});
        const status = () => Object.freeze({pending: !finished});
        failure.cleanupHandle = Object.freeze({status, async retry() {
          try { await close(); }
          catch { throw failure; }
          failure.cleanupPending = false;
          return status();
        }});
        throw failure;
      }
      throw cause;
    }
  }});
}
