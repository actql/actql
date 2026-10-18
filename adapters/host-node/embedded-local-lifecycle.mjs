// The existing installed Host owns execution and durable data. This registry
// only leases its in-process connection and retains its physical close retry.
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createInstalledHostShutdown, retainInstalledHostRuntimeFailure}
  from './installed-host-cleanup.mjs';

export function installedHostShutdown(host) {
  const retireRuntime = host.retireModelRuntime;
  const initialControl = host.initialControl;
  const shutdown = createInstalledHostShutdown({
    stop: () => {
      host.stopModelRuntime?.();
      return host.checkpoints?.stop();
    },
    drain: () => host.dispatchOwner.drain(),
    retire: () => host.retireTerminalEffects(),
    checkpoint: () => host.checkpoints?.close(),
    journal: () => host.journal.close(),
    source: () => host.sourceProfile?.close(),
    effect: () => host.installedEffect?.close(),
    store: () => host.store.close(),
    ...(host.diagnostic === undefined ? {} :
      {diagnostic: () => host.diagnostic.close()}),
    ...(host.observation === undefined ? {} :
      {observation: () => host.observation.close()}),
    ...(host.ownerViews === undefined ? {} : {ownerViews: () => host.ownerViews.close()}),
    ...(initialControl === undefined ? {} : {initialControl}),
    ...(retireRuntime === undefined ? {} : {finalize: async () => {
      await Reflect.apply(retireRuntime, host, []);
      // The same shutdown marks this duty complete only after success.
      // A failed/partial retirement still owns the original callback.
      delete host.retireModelRuntime;
    }}),
  });
  return Object.freeze({status: shutdown.status, close: shutdown.close});
}

const closing = () => Object.assign(new Error('ClientHostClosing'),
  {code: 'ClientHostClosing'});

export function createEmbeddedHostRegistry(sameInstallation) {
  const profiles = new Map();
  const preparationChanged = () => {
    throw Object.assign(new Error('InstalledHostPreparationChanged'),
      {code: 'InstalledHostPreparationChanged'});
  };
  function preparationFor(host, installation, generation) {
    const entry = profiles.get(host);
    if (entry === undefined || entry.originalHost !== host ||
        entry.originalInstallation !== installation ||
        entry.generation !== generation || entry.finalized ||
        entry.preparationRetired) preparationChanged();
    return entry;
  }
  const forget = (root, entry) => {
    if (profiles.get(root) === entry) profiles.delete(root);
    if (entry.originalHost !== undefined && profiles.get(entry.originalHost) === entry) {
      profiles.delete(entry.originalHost);
    }
    entry.preparationRetired = true;
    entry.originalHost = entry.originalInstallation = entry.generation = undefined;
  };
  return Object.freeze({
  // A candidate belongs to this SAME registry, before Project discovery. It
  // has no root lease or physical Host yet and issues no capacity/permission.
  // The selected startup must independently admit its prior control envelope.
  registerPreparation(host, installation, generation) {
    if (host === null || typeof host !== 'object' || Array.isArray(host) ||
        installation === null || typeof installation !== 'object' ||
        Array.isArray(installation) || generation !== host || profiles.has(host)) {
      preparationChanged();
    }
    profiles.set(host, {originalHost: host, originalInstallation: installation,
      generation, preparing: true, leases: 0, accepting: 0, closing: false,
      handling: new Set()});
  },
  assertPreparation(host, installation, generation) {
    const entry = preparationFor(host, installation, generation);
    if (entry.closing || entry.failure !== undefined) preparationChanged();
  },
  retirePreparation(host, installation, generation) {
    const entry = preparationFor(host, installation, generation);
    // An adopted candidate belongs to its Host's existing shutdown. An
    // unadopted candidate may cut only its own managed registry references.
    if (!entry.preparing) preparationChanged();
    forget(undefined, entry);
  },
  async connect(root, identity, open, options, preparedHost, releaseUnadopted) {
    const prepared = preparedHost === undefined ? undefined : profiles.get(preparedHost);
    if (preparedHost !== undefined && (typeof root !== 'string' || !root ||
        prepared === undefined || prepared.originalHost !== preparedHost ||
        !prepared.preparing || prepared.preparationRetired || prepared.closing)) {
      preparationChanged();
    }
    let entry = profiles.get(root);
    if (entry?.preparing) preparationChanged();
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
      entry = prepared ?? {leases: 0, accepting: 0, closing: false, handling: new Set()};
      entry.identity = identity;
      entry.preparing = false;
      const opened = entry;
      entry.host = Promise.resolve().then(open).then(async host => {
        // Take the acquired child's existing shutdown custody before refusing
        // a foreign return. A failed pair check must not lose that child.
        opened.shutdown = installedHostShutdown(host);
        if (preparedHost !== undefined && host !== preparedHost) {
          const failure = Object.assign(new Error('InstalledHostPreparationChanged'),
            {code: 'InstalledHostPreparationChanged'});
          try { await opened.shutdown.close(); }
          catch (cause) {
            failure.cause = cause;
            failure.cleanupPending = true;
            failure.cleanupHandle = Object.freeze({
              status: () => Object.freeze({pending: opened.shutdown.status().pending.length !== 0}),
              retry: opened.shutdown.close,
            });
          }
          throw failure;
        }
        return host;
      }).catch(cause => {
        // A prepared generation also owns its original registry references.
        // Keep their retirement behind the SAME initializer's captured child
        // status/retry, rather than waiting for an unrelated later connect.
        const error = prepared === undefined ? cause :
          retainInstalledHostRuntimeFailure(cause, () => forget(root, opened));
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
      if (prepared !== undefined) {
        if (typeof releaseUnadopted !== 'function') {
          throw Object.assign(new Error('InstalledHostPreparationCleanupUnavailable'),
            {code: 'InstalledHostPreparationCleanupUnavailable'});
        }
        // Close the unused preparation before reserving/exposing another
        // lease. Cleanup success does not prove this original Host stayed
        // current while the callback awaited its own children.
        await releaseUnadopted();
        if (profiles.get(root) !== entry || entry.closing || entry.failure !== undefined) {
          throw closing();
        }
        if (profiles.get(preparedHost) === prepared) preparationChanged();
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
            // The existing shutdown owner also retains observation close.
            // Retire this generation only after every child has settled.
            forget(root, opened);
            opened.finalized = true;
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
    try {
    const originalPort = host.port, answer = originalPort.answerCheckpoint;
    if (answer !== undefined && typeof answer !== 'function') {
      throw new TypeError('InvalidLocalCheckpointAnswerPort');
    }
    const port = Object.freeze({
      ...(answer === undefined ? {} : {
        answerCheckpoint: (summary, decision, signal) => {
            if (sealed || opened.closing) return Promise.reject(closing());
            const pending = Promise.resolve().then(() => {
              if (sealed || opened.closing) throw closing();
              return Reflect.apply(answer, originalPort, [summary, decision, signal]);
            });
            // The same lease/Host handling sets own signing as well as reads.
            // Close must not forget a pending original key/use operation.
            handling.add(pending);
            opened.handling.add(pending);
            pending.finally(() => {
              handling.delete(pending);
              opened.handling.delete(pending);
            }).catch(() => {});
            return pending;
        },
      }),
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
    return await connectInProcess(options, port);
    } catch (cause) {
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
