// The existing installed Host owns execution and durable data. This registry
// only leases its in-process connection and retains its physical close retry.
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {ledgerLimitsFields, ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';
import {captureSourcePreparation, sourcePreparationPort} from
  '../../packages/sdk/internal/private-source-preparation.mjs';
import {createInstalledHostShutdown, retainInstalledHostRuntimeFailure,
  retainInstalledHostInitializationFailure, originalInitialControlClose}
  from './installed-host-cleanup.mjs';
import type {SynchronousAction} from './installed-host-cleanup.mjs';
import type {RunReference} from '../../packages/sdk/index.d.ts';

type HostPort = Parameters<typeof connectInProcess>[1];
type PortPerform = Parameters<HostPort['perform']>;
type PortAnswer = Parameters<NonNullable<HostPort['answerCheckpoint']>>;
type SourcePreparation = NonNullable<ReturnType<typeof captureSourcePreparation>>;
type ShutdownInput = Parameters<typeof createInstalledHostShutdown>[0];
type InitialControl = NonNullable<ShutdownInput['initialControl']>;
type Shutdown = ReturnType<typeof createInstalledHostShutdown>;
type InitializationFailure = Awaited<ReturnType<typeof retainInstalledHostInitializationFailure>>;
type CloseOwner = {close: () => unknown};
type CheckpointOwner = {close: ShutdownInput['checkpoint']; stop: ShutdownInput['stop']};
type ShutdownHost = {
  initialControl?: InitialControl; retireModelRuntime?: ShutdownInput['retire'];
  prepareShutdown?: ShutdownInput['stop']; stopModelRuntime?: SynchronousAction;
  runAcceptance?: CheckpointOwner; checkpoints?: CheckpointOwner;
  dispatchOwner?: {drain: ShutdownInput['drain']}; retireTerminalEffects?: ShutdownInput['retire'];
  sourceProfile?: CloseOwner; installedEffect?: CloseOwner;
  closePublicationOwnership?: ShutdownInput['publicationOwnership']; diagnostic?: CloseOwner;
  observation?: CloseOwner; ownerViews?: CloseOwner;
} & (Readonly<{journal: CloseOwner; closeRequestJournal?: ShutdownInput['journal']}> |
  Readonly<{journal?: CloseOwner; closeRequestJournal: ShutdownInput['journal']}>) &
  (Readonly<{store: CloseOwner; closePublicationStore?: ShutdownInput['store']}> |
  Readonly<{store?: CloseOwner; closePublicationStore: ShutdownInput['store']}>);
type EmbeddedHost = ShutdownHost & {port: HostPort};
type RequestRecord = {
  request?: object; pending?: Promise<unknown>; owner?: RegistryEntry; generation?: object;
};
type RegistryEntry = {
  originalHost?: object; originalInstallation?: object; generation?: object;
  preparing?: boolean; preparationRetired?: boolean; closing: boolean; finalized?: boolean;
  leases: number; accepting: number; handling: Map<Promise<unknown>, RequestRecord | undefined>;
  requestIndex?: WeakMap<object, RequestRecord>; hostJournalPreparation?: object; mockPreparation?: object;
  identity?: unknown; host?: Promise<EmbeddedHost>; shutdown?: Shutdown; failure?: unknown;
  initializationPending?: boolean; initializationStatus?: () => {pending: unknown};
  sourceProducerPending?: number;
};
type ObservedFailure = {
  code?: string; primaryFailure?: unknown; cleanupPending?: unknown;
  cleanupHandle?: {status?: () => {pending: unknown}};
};
type ManagedRun = {
  value?: unknown; runtime?: {clientProgramInstalledManagedRunAccounting?: unknown};
  usage?: unknown; retire?: (value: unknown) => unknown; original?: unknown;
  manager?: {retireSeveredPreparation?(original: object): ReturnType<SynchronousAction>};
  closed?: boolean; finalAccounting?: readonly bigint[];
};
type ComputeRegistry = {
  computeRuns?: Pick<WeakMap<object, ManagedRun>, 'get'>;
  computeRunObservations?: Map<string, ManagedRun>;
};


type EffectReference = Readonly<{ref: unknown; durability: unknown; revision: unknown}>;
type EffectDiagnostic = (event: string, detail: Readonly<Record<string, unknown>>) => unknown;
type EffectStart<Accepted extends EffectReference> = Readonly<{
  effectRun: Readonly<{start(accepted: Accepted): Promise<unknown>}>;
  settle(): void;
  diagnostic: EffectDiagnostic;
}>;
type EffectObservation = Readonly<{retainOperation?(operation: Promise<unknown>): unknown}>;
type SettlementFailure = {code?: unknown; message?: unknown; cause?: unknown} | null | undefined;

export function installedEffectSettlements(observation?: EffectObservation) {
  const starts = new Set<Promise<unknown>>();
  const retain = (settlement: Promise<unknown>) => {
    // Run-state observation can open Store readers after dispatch retires.
    // Keep this original continuation through Host stop as well.
    starts.add(settlement);
    const retire = () => { starts.delete(settlement); };
    settlement.then(retire, retire);
    try {observation?.retainOperation?.(settlement);} catch { /* Optional metadata. */ }
  };
  return Object.freeze({
    start<Accepted extends EffectReference>(accepted: Accepted,
      {effectRun, settle, diagnostic}: EffectStart<Accepted>) {
      // Return the durable original Ref before physical work settles.
      const settlement = effectRun.start(accepted).catch((error: SettlementFailure) => {
        diagnostic('effect_start_failed', {ref: accepted.ref,
          code: error?.code ?? error?.message, cause: error?.cause});
      }).finally(settle).catch((error: SettlementFailure) => diagnostic('effect_settlement_failed', {
        ref: accepted.ref, code: error?.code ?? error?.message}));
      retain(settlement);
      return {ref: accepted.ref, durability: accepted.durability, revision: accepted.revision};
    },
    retain,
    async drain(resumes: ReadonlyMap<unknown, unknown>, retirements: ReadonlyMap<unknown, unknown>) {
      // Host stop has joined the last sweep. Only its admitted work remains.
      await Promise.allSettled([...starts, ...resumes.values()]);
      await Promise.allSettled([...retirements.values()]);
    },
  });
}

export function installedHostShutdown(host: ShutdownHost) {
  const retireRuntime = host.retireModelRuntime;
  const initialControl = host.initialControl;
  const prepareShutdown = host.prepareShutdown;
  const closePublicationStore = host.closePublicationStore;
  const closeRequestJournal = host.closeRequestJournal;
  const closePublicationOwnership = host.closePublicationOwnership;
  const shutdown = createInstalledHostShutdown({
    stop: prepareShutdown === undefined ? () => {
      host.stopModelRuntime?.();
      return (host.runAcceptance ?? host.checkpoints)?.stop();
    } : async () => {
      host.stopModelRuntime?.();
      // The same Host's deferred constructor may already hold a physical
      // child. Observe that original to terminal before enumerating shutdown
      // duties; never replace it or turn its Promise into an ACK.
      await Reflect.apply(prepareShutdown,host,[]);
      return (host.runAcceptance ?? host.checkpoints)?.stop();
    },
    drain: () => prepareShutdown === undefined
      ? host.dispatchOwner!.drain() : host.dispatchOwner?.drain(),
    retire: () => prepareShutdown === undefined
      ? host.retireTerminalEffects!() : host.retireTerminalEffects?.(),
    checkpoint: () => (host.runAcceptance ?? host.checkpoints)?.close(),
    journal: closeRequestJournal === undefined ? () => host.journal!.close() :
      () => Reflect.apply(closeRequestJournal, host, []),
    source: () => host.sourceProfile?.close(),
    effect: () => host.installedEffect?.close(),
    store: closePublicationStore === undefined ? () => host.store!.close() :
      () => Reflect.apply(closePublicationStore,host,[]),
    ...(closePublicationOwnership === undefined ? {} : {publicationOwnership:
      () => Reflect.apply(closePublicationOwnership, host, [])}),
    ...(host.diagnostic === undefined ? {} :
      {diagnostic: () => host.diagnostic!.close()}),
    ...(host.observation === undefined ? {} :
      {observation: () => host.observation!.close()}),
    ...(host.ownerViews === undefined ? {} : {ownerViews: () => host.ownerViews!.close()}),
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

export function createEmbeddedHostRegistry(sameInstallation: (original: unknown, selected: unknown) => boolean) {
  const profiles = new Map<unknown, RegistryEntry>();
  const preparationChanged: () => never = () => {
    throw Object.assign(new Error('InstalledHostPreparationChanged'),
      {code: 'InstalledHostPreparationChanged'});
  };
  function preparationFor(host: unknown, installation: unknown, generation: unknown) {
    const entry = profiles.get(host);
    if (entry === undefined || entry.originalHost !== host ||
        entry.originalInstallation !== installation ||
        entry.generation !== generation || entry.finalized ||
        entry.preparationRetired) preparationChanged();
    return entry;
  }
  const forget = (root: unknown, entry: RegistryEntry) => {
    if (profiles.get(root) === entry) profiles.delete(root);
    if (entry.originalHost !== undefined && profiles.get(entry.originalHost) === entry) {
      profiles.delete(entry.originalHost);
    }
    entry.preparationRetired = true;
    entry.mockPreparation = undefined;
    entry.requestIndex = undefined;
    entry.hostJournalPreparation = undefined;
    entry.originalHost = entry.originalInstallation = entry.generation = undefined;
  };
  function originalRequestRecord(entry: RegistryEntry, request: object) {
    const original = entry.requestIndex!.get(request);
    if (original === undefined || original.owner !== entry ||
        original.generation !== entry.generation || original.request === undefined ||
        entry.handling.get(original.pending!) !== original) preparationChanged();
    return original;
  }
  function assertUnboundRequest(entry: RegistryEntry, request: unknown): asserts request is object {
    if (request === null || typeof request !== 'object' ||
        entry.requestIndex!.has(request)) preparationChanged();
  }
  function retainRequestRecord(entry: RegistryEntry, request: object, pending: Promise<unknown>) {
    const original: RequestRecord = {request, pending, owner: entry, generation: entry.generation};
    entry.requestIndex!.set(request, original);
    entry.handling.set(pending, original);
    return original;
  }
  function retireRequestRecord(entry: RegistryEntry, pending: Promise<unknown>, original: RequestRecord) {
    if (entry.handling.get(pending) === original) entry.handling.delete(pending);
    // Weak aliases may outlive this call. Their tombstone retains no request,
    // Promise, Host or generation, and cannot bind to a different original.
    original.request = original.pending = original.owner = original.generation = undefined;
  }
  function originalSourceRequest(host: unknown, installation: unknown, generation: unknown, request: unknown) {
    const entry = preparationFor(host, installation, generation);
    if (entry.closing || entry.failure !== undefined ||
        request === null || typeof request !== 'object') preparationChanged();
    return originalRequestRecord(entry, request).request!;
  }
  return Object.freeze({
  // A candidate belongs to this SAME registry, before Project discovery. It
  // has no root lease or physical Host yet and issues no capacity/permission.
  // The selected startup must independently admit its prior control envelope.
  registerPreparation(host: unknown, installation: unknown, generation: unknown) {
    if (host === null || typeof host !== 'object' || Array.isArray(host) ||
        installation === null || typeof installation !== 'object' ||
        Array.isArray(installation) || generation !== host || profiles.has(host)) {
      preparationChanged();
    }
    profiles.set(host, {originalHost: host, originalInstallation: installation,
      generation, preparing: true, leases: 0, accepting: 0, closing: false,
      handling: new Map(), requestIndex: new WeakMap()});
  },
  assertPreparation(host: unknown, installation: unknown, generation: unknown) {
    const entry = preparationFor(host, installation, generation);
    if (entry.closing || entry.failure !== undefined) preparationChanged();
  },
  // An already admitted Run retains this same Host through graceful drain.
  // This identity-only check cannot admit a new Request or preparation.
  assertRetainedPreparation(host: unknown, installation: unknown, generation: unknown) {
    const entry = preparationFor(host, installation, generation);
    if (entry.failure !== undefined) preparationChanged();
  },
  // The actual Host retains this one original before its first root/Journal
  // operation. This association is not a native facility, issuer or grant.
  retainHostJournalPreparation(host: unknown, installation: unknown, generation: unknown, view: unknown) {
    const entry = preparationFor(host, installation, generation);
    if (entry.closing || entry.failure !== undefined ||
        entry.hostJournalPreparation !== undefined || view === null ||
        typeof view !== 'object' || !Object.isFrozen(view)) preparationChanged();
    entry.hostJournalPreparation = view;
  },
  hostJournalPreparation(host: unknown, installation: unknown, generation: unknown) {
    const entry = preparationFor(host, installation, generation);
    if (entry.closing || entry.failure !== undefined ||
        entry.hostJournalPreparation === undefined) preparationChanged();
    return entry.hostJournalPreparation;
  },
  // Retain only this original Host's prepared mock view. This existing
  // registry association is not the Source supplier or a DATA admission.
  retainMockPreparation(host: unknown, installation: unknown, generation: unknown, view: unknown) {
    const entry = preparationFor(host, installation, generation);
    if (entry.closing || entry.failure !== undefined || entry.mockPreparation !== undefined ||
        view === null || typeof view !== 'object') preparationChanged();
    entry.mockPreparation = view;
  },
  mockPreparation(host: unknown, installation: unknown, generation: unknown, allowMissing = false) {
    const entry = preparationFor(host, installation, generation);
    if (entry.closing || entry.failure !== undefined ||
        entry.mockPreparation === undefined && !allowMissing) preparationChanged();
    return entry.mockPreparation;
  },
  retainedMockPreparation(host: unknown, installation: unknown, generation: unknown) {
    // Cleanup may outlive new-operation currentness. Keep the exact registry
    // pair while closing; this projection cannot admit another preparation.
    return preparationFor(host, installation, generation).mockPreparation;
  },
  // Identity-only projection from this registry's actual pending calls. The
  // Source operational supplier covers the additional request reference and
  // Map backing before installing its consumer. This is not an issuer, grant,
  // request parser or evidence that the call's physical work has stopped.
  originalSourceRequest,
  // Both ingresses retain their actual pending operation in this SAME Host
  // registry. This association neither prepares a Program nor admits capacity.
  retainRequest(host: unknown, installation: unknown, generation: unknown, request: unknown, pending: unknown) {
    const entry = preparationFor(host, installation, generation);
    if (entry.closing || entry.failure !== undefined || request === null ||
        typeof request !== 'object' || !(pending instanceof Promise) || entry.handling.has(pending)) {
      preparationChanged();
    }
    assertUnboundRequest(entry, request);
    const original = retainRequestRecord(entry, request, pending);
    pending.finally(() => retireRequestRecord(entry, pending, original)).catch(() => {});
  },
  assertSourceRequest(host: unknown, installation: unknown, generation: unknown, request: unknown) {
    originalSourceRequest(host, installation, generation, request);
  },
  bindSourceRequest(host: unknown, installation: unknown, generation: unknown, parent: unknown, derived: unknown) {
    const entry = preparationFor(host, installation, generation);
    if (entry.closing || entry.failure !== undefined || parent === null ||
        typeof parent !== 'object' || derived === null || typeof derived !== 'object') preparationChanged();
    const selected = originalRequestRecord(entry, parent);
    const bound = entry.requestIndex!.get(derived);
    if (bound !== undefined) {
      if (bound !== selected) preparationChanged();
      return;
    }
    // Alias identity is weak: the active operation/dispatch owns its payload.
    // The same strong handling inventory remains the physical drain owner.
    // This index grants no capacity or authority and never changes a packet.
    entry.requestIndex!.set(derived, selected);
  },
  retirePreparation(host: unknown, installation: unknown, generation: unknown) {
    const entry = preparationFor(host, installation, generation);
    // An adopted candidate belongs to its Host's existing shutdown. An
    // unadopted candidate may cut only its own managed registry references.
    if (!entry.preparing) preparationChanged();
    forget(undefined, entry);
  },
  async connect(root: unknown, identity: unknown, open: () => EmbeddedHost | PromiseLike<EmbeddedHost>,
    options: Parameters<typeof connectInProcess>[0], preparedHost?: object,
    releaseUnadopted?: () => unknown, initialControl?: InitialControl) {
    const retainedControl = initialControl === undefined ? undefined :
      Object.freeze({close: originalInitialControlClose(initialControl)});
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
      entry = prepared ?? {leases: 0, accepting: 0, closing: false, handling: new Map(), requestIndex: new WeakMap()};
      entry.identity = identity;
      entry.preparing = false;
      const opened = entry;
      entry.host = Promise.resolve().then(open).then(async host => {
        // Take the acquired child's existing shutdown custody before refusing
        // a foreign return. A failed pair check must not lose that child.
        opened.shutdown = installedHostShutdown(host);
        if (preparedHost !== undefined && host !== preparedHost) {
          const failure = Object.assign(new Error('InstalledHostPreparationChanged'),
            {code: 'InstalledHostPreparationChanged'}) as Error & ObservedFailure;
          try { await opened.shutdown!.close(); }
          catch (cause) {
            failure.cause = cause;
            failure.cleanupPending = true;
            failure.cleanupHandle = Object.freeze({
              status: () => Object.freeze({pending: opened.shutdown!.status().pending.length !== 0}),
              retry: opened.shutdown!.close,
            });
          }
          throw failure;
        }
        return host;
      }).catch(async cause => {
        // A prepared generation also owns its original registry references.
        // Keep their retirement behind the SAME initializer's captured child
        // status/retry, rather than waiting for an unrelated later connect.
        const owned = retainedControl === undefined ? cause :
          await retainInstalledHostInitializationFailure(cause, {initialControl: retainedControl});
        const error = prepared === undefined ? owned :
          retainInstalledHostRuntimeFailure(owned, () => forget(root, opened));
        if (retainedControl !== undefined && prepared !== undefined &&
            error === owned && (owned as InitializationFailure).cleanupHandle.status().pending === false) {
          // Both original cleanup and registry retirement completed. Preserve
          // the refusal itself without re-reading an arbitrary thrown value.
          opened.failure = cause;
          opened.initializationPending = false;
          throw cause;
        }
        opened.failure = error;
        opened.initializationPending = (error as ObservedFailure | null | undefined)?.cleanupPending === true;
        const handle = (error as ObservedFailure | null | undefined)?.cleanupHandle;
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
    let sealed = false, released = false, finished = false, flight: Promise<void> | undefined;
    const handling = new Set<Promise<unknown>>();
    const sourceProducers = new Map<unknown, {pending: Promise<void>; settled: () => void}>();
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
        // A producer can finish after the SDK's cleanup iteration started.
        // Await that original attempt, but never treat its rejection as alias
        // retirement. The SDK retains its same retry; the next close can drain
        // it without resnapshotting, dispatching or replacing the receipt.
        if (sourceProducers.size !== 0) {
          throw Object.assign(new Error('InstalledSourceProducerCleanupPending'),
            {code: 'InstalledSourceProducerCleanupPending'});
        }
        if (opened.leases !== 0) { finished = true; return; }
        const host = await opened.host!;
        await Promise.allSettled([...opened.handling.keys()]);
        if ((opened.sourceProducerPending ?? 0) !== 0) {
          throw Object.assign(new Error('InstalledSourceProducerCleanupPending'),
            {code: 'InstalledSourceProducerCleanupPending'});
        }
        try {
          await opened.shutdown!.close();
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
          const error = Object.assign(new Error((cause as ObservedFailure | null | undefined)?.code ?? 'InstalledHostCleanupPending',
            {cause}), {code: (cause as ObservedFailure | null | undefined)?.code ?? 'InstalledHostCleanupPending',
            primaryFailure: (cause as ObservedFailure | null | undefined)?.primaryFailure ?? cause,
            cleanupPending: true,
            cleanupHandle: Object.freeze({status: opened.shutdown!.status, retry: close})});
          throw error;
        }
      }).finally(() => { flight = undefined; });
      return flight;
    }
    let host: EmbeddedHost;
    try { host = await opened.host!; }
    catch (error) {
      // Initialization itself retains cleanup; there is no returned Host.
      released = true;
      opened.leases--;
      seal();
      throw error;
    }
    try {
    const originalPort = host.port;
    // Builtin Local supplies its already captured initial-control owner on
    // every lease. Identity-only registry entries do not select that provider.
    const sourcePreparation = retainedControl !== undefined ||
      (originalPort !== undefined && sourcePreparationPort in originalPort)
      ? captureSourcePreparation(originalPort) : undefined;
    if (retainedControl !== undefined && sourcePreparation === undefined) {
      throw Object.assign(new Error('NodeSourceManagedAdmissionUnavailable'),
        {code: 'NodeSourceManagedAdmissionUnavailable'});
    }
    const answer = originalPort.answerCheckpoint;
    if (answer !== undefined && typeof answer !== 'function') {
      throw new TypeError('InvalidLocalCheckpointAnswerPort');
    }
    const retainSourceProducer = (receipt: unknown) => {
      if (sourceProducers.has(receipt)) {
        throw Object.assign(new Error('InstalledSourceProducerAlreadyPending'),
          {code: 'InstalledSourceProducerAlreadyPending'});
      }
      let settled!: () => void;
      const pending = new Promise<void>(resolve => {settled = resolve;});
      sourceProducers.set(receipt, {pending, settled});
      opened.sourceProducerPending = (opened.sourceProducerPending ?? 0) + 1;
      handling.add(pending);
      opened.handling.set(pending, undefined);
      return receipt;
    };
    const port: HostPort = Object.freeze({
      ...(sourcePreparation === undefined ? {} : {[sourcePreparationPort]: Object.freeze<SourcePreparation>({
        beforeSourceSnapshot(kind, input, options, originalConnection) {
          if (sealed || opened.closing) throw closing();
          return retainSourceProducer(sourcePreparation.beforeSourceSnapshot(kind, input, options, originalConnection));
        },
        beforeSourceQuery(format, text, parameters, options, originalConnection) {
          if (sealed || opened.closing) throw closing();
          // Query admission enters the SAME producer/lease lifetime. No
          // second snapshot, receipt, pending owner or physical ACK is made.
          return retainSourceProducer(sourcePreparation.beforeSourceQuery(format, text, parameters, options, originalConnection));
        },
        beforeResultRead(schemaOrOptions, options) {
          if (sealed || opened.closing) throw closing();
          return sourcePreparation.beforeResultRead(schemaOrOptions, options);
        },
        assertResultReadCurrent() {
          if (sealed || opened.closing) throw closing();
          return sourcePreparation.assertResultReadCurrent();
        },
        assertSourceSnapshotCurrent(receipt) {
          if (sealed || opened.closing || !sourceProducers.has(receipt)) throw closing();
          return sourcePreparation.assertSourceSnapshotCurrent(receipt);
        },
        captureSourceSnapshot(receipt, value, snapshot) {
          if (sealed || opened.closing || !sourceProducers.has(receipt)) throw closing();
          return sourcePreparation.captureSourceSnapshot(receipt, value, snapshot);
        },
        bindSourceSnapshot(receipt, body) {
          if (sealed || opened.closing) throw closing();
          return sourcePreparation.bindSourceSnapshot(receipt, body);
        },
        publishSourceSnapshot(receipt, body, publication) {
          if (sealed || opened.closing || !sourceProducers.has(receipt)) throw closing();
          return sourcePreparation.publishSourceSnapshot(receipt, body, publication);
        },
        bindSourceRequest(receipt, body, request) {
          if (sealed || opened.closing) throw closing();
          return sourcePreparation.bindSourceRequest(receipt, body, request);
        },
        intentCid(receipt, body) {
          if (sealed || opened.closing) throw closing();
          if (!sourceProducers.has(receipt)) {
            throw Object.assign(new Error('ForeignInstalledSourceProducer'),
              {code: 'ForeignInstalledSourceProducer'});
          }
          return sourcePreparation.intentCid(receipt, body);
        },
        finishSourceProducer(receipt, terminal) {
          const producer = sourceProducers.get(receipt);
          if (producer === undefined) {
            throw Object.assign(new Error('ForeignInstalledSourceProducer'),
              {code: 'ForeignInstalledSourceProducer'});
          }
          try {
            // Retirement stays legal after sealing. This same original Owner
            // cuts only producer aliases; it grants no physical cleanup ACK.
            const result = sourcePreparation.finishSourceProducer(receipt, terminal);
            sourceProducers.delete(receipt);
            opened.sourceProducerPending!--;
            return result;
          } finally {
            producer.settled();
            handling.delete(producer.pending);
            opened.handling.delete(producer.pending);
          }
        },
      })}),
      ...(answer === undefined ? {} : {
        answerCheckpoint: (summary: PortAnswer[0], decision: PortAnswer[1], signal?: PortAnswer[2]) => {
            if (sealed || opened.closing) return Promise.reject(closing());
            const pending = Promise.resolve().then(() => {
              if (sealed || opened.closing) throw closing();
              return Reflect.apply(answer, originalPort, [summary, decision, signal]);
            });
            // The same lease/Host handling sets own signing as well as reads.
            // Close must not forget a pending original key/use operation.
            handling.add(pending);
            opened.handling.set(pending, undefined);
            pending.finally(() => {
              handling.delete(pending);
              opened.handling.delete(pending);
            }).catch(() => {});
            return pending;
        },
      }),
      perform(operation: PortPerform[0], request: PortPerform[1], signal?: PortPerform[2]) {
        if (sealed || opened.closing) return Promise.reject(closing());
        // Refuse rebinding before scheduling any physical operation.
        try { assertUnboundRequest(opened, request); }
        catch (cause) { return Promise.reject(cause); }
        const pending = Promise.resolve().then(() => host.port.perform(operation, request, signal));
        handling.add(pending);
        // Same pending operation and drain record; the weak index supplies
        // identity lookup only, never a holding or physical acknowledgement.
        const original = retainRequestRecord(opened, request, pending);
        pending.finally(() => {
          handling.delete(pending);
          retireRequestRecord(opened, pending, original);
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
          {code: 'InstalledLocalConnectionCleanupPending', cleanupPending: true}) as Error & ObservedFailure;
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

// The same Host bag owns these observations. They retain no authority or new
// Resource owner, and retirement publishes only inert final Ledger scalars.
// Separate lexical scope: this continuation retains only the same run, record
// and two scalar-state slots; it cannot capture a retiring method's Request.
export function managedPreparationRetirementContinuation(run: ManagedRun,
    record: Readonly<{computeLiveRuns?: Pick<Set<ManagedRun>, 'delete'>}>) {
  let retired = false, finalAccounting: readonly bigint[] | undefined;
  return () => {
    if (!retired) {
      let observed: readonly bigint[] | undefined;
      // The original input/control children have returned before this final
      // cut. Core drops its Ledger on success; late Result observation keeps
      // only these exact immutable scalars, never a live/current witness.
      if (typeof run.usage === 'function') {
        try {
          const values = checked(Reflect.apply(run.usage, run.runtime, [run.value]));
          const length = ledgerLimitsFields.length + ledgerUsageFields.length;
          if (Array.isArray(values) && values.length === length &&
              Reflect.ownKeys(values).length === length + 1) {
            let numeric = true;
            for (let index = 0; index < length; index++) {
              const field = Object.getOwnPropertyDescriptor(values, String(index));
              if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'bigint') {
                numeric = false; break;
              }
            }
            if (numeric) observed = Object.freeze(values as bigint[]);
          }
        } catch { /* Optional metadata cannot replace original cleanup. */ }
      }
      checked(Reflect.apply(run.retire!,run.runtime,[run.value]));
      finalAccounting = observed;
      retired = true;
    }
    run.manager!.retireSeveredPreparation!(run.original as object);
    record.computeLiveRuns!.delete(run);
    for(const key of Object.keys(run)) (run as Record<string, unknown>)[key]=undefined;
    run.closed=true;
    if (finalAccounting !== undefined) run.finalAccounting = finalAccounting;
  };
}

export function bindManagedComputeRunObservation(record: ComputeRegistry, prepared: object, ref: RunReference, clientOperationError: (code: string) => unknown) {
  const run = record.computeRuns?.get(prepared);
  if (run === undefined || run.value === undefined || run.closed) return;
  // Index only an actually admitted Run's existing holding. This does
  // not cache authority, reconstruct a preparation or scan other Runs.
  const key = JSON.stringify([ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid]);
  const index = record.computeRunObservations ??= new Map();
  const prior = index.get(key);
  if (prior !== undefined && prior !== run) throw clientOperationError('ForeignInstalledComputeRun');
  index.set(key, run);
  // Capture the same native method without sampling or extending the
  // Core Run lifetime. Final retirement supplies its last live DATA.
  if (!Object.hasOwn(run, 'usage')) run.usage = run.runtime!.clientProgramInstalledManagedRunAccounting;
    }

export function managedComputeUsageReader(record: ComputeRegistry, ref: RunReference) {
  const key = JSON.stringify([ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid]);
  if (record.computeRunObservations?.get(key) === undefined) return undefined;
  // Capture only the public key and existing installation bag. Final
  // retirement clears that bag, including this index, so a held response
  // cannot keep a prepared Program, Core Run or Ledger alive afterward.
  return () => {
    const run = record.computeRunObservations?.get(key);
    if (run === undefined) return undefined;
    if (run.closed) return run.finalAccounting;
    if (run.value === undefined) return undefined;
    if (!Object.hasOwn(run, 'usage')) run.usage = run.runtime!.clientProgramInstalledManagedRunAccounting;
    if (typeof run.usage !== 'function') return undefined;
    // The original JS Core export returns Result[Array[Int64], Issue].
    return checked(Reflect.apply(run.usage, run.runtime, [run.value])) as readonly bigint[];
  };
    }
