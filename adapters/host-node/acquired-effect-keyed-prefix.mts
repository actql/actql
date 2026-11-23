// Compose the existing original prefix, keyed Row receiver and Content
// custody. The caller retains this duty before any asynchronous Source work.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {performance} from 'node:perf_hooks';
import {bytesCid, originalLocalContentStoragePolicy} from './local-account-config.mjs';
import {preparePrivatePublicationHolding} from '../host-common/private-publication-holding.mjs';
import {localOutputLimits, localContractLimits} from './local-publication-limits.mjs';
import {keyedInputRetentionSelection} from './local-values-plan.mjs';

import type {createJournalKeyedLookupStorage} from './client-request-journal-records.mjs';
import type {createInstalledRowSourceKeyedLookup} from './installed-row-source-keyed-lookup.mjs';
import type {createInstalledRowSourceKeyedPreparation} from './installed-row-source-keyed-preparation.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';

type Preparation = ReturnType<typeof createInstalledRowSourceKeyedPreparation>;
type OpenLookup = ReturnType<typeof createInstalledRowSourceKeyedLookup>;
type LookupOptions = Parameters<OpenLookup>[0];
type KeyedCapacity = Readonly<{maxBytes: number; maxWork: number; maxNodes: number}>;
type KeyedAdapter = Pick<Preparation, 'prepareKeyed' | 'keyedRecoveryBinding'> & Readonly<{
  admitsSource(sourceRef: string): boolean;
  sourceAccess: NonNullable<LookupOptions['sourceAccess']>;
  requiresRunContentCapture?: boolean;
  keyedLedgerCapacity(acquisition: unknown, options?: Readonly<{originalWork: number}>): KeyedCapacity;
  openKeyedLookup: OpenLookup;
}>;
type SourceProfile = NonNullable<Parameters<typeof installedSourceFor<KeyedAdapter>>[0]> &
  Readonly<{fileReadDeclarations?: readonly unknown[]}>;
type Journal = ReturnType<typeof createJournalKeyedLookupStorage>;
type Activation = Parameters<Journal['persistOriginalKeyedLookupActivation']>;
type Page = Parameters<Journal['persistOriginalKeyedLookupPage']>;
type RawRequest = Extract<Parameters<typeof preparePrivatePublicationHolding>[1], {contentCid: string}>;
type HoldingStore = Parameters<typeof preparePrivatePublicationHolding>[0];
type Store = Awaited<ReturnType<typeof openLocalPublicationStore>>;
type ReadCleanup = Readonly<{status(): Readonly<{pending: boolean}>; retry(): unknown}>;
type Custody = Readonly<{
  close(): unknown;
  cleanup(): boolean | PromiseLike<boolean>;
  cleanupPending(): boolean;
}>;
type Limits = typeof localContractLimits;
type OutputLimits = typeof localOutputLimits;
type Retention = Readonly<{
  expiresAt: string;
  retentionContractCid: string;
  availableUntil: string;
  deleteBy: string;
  metadataDeleteBy: string;
  metadataRetentionPolicyCid: string;
  clockContractCid: string;
}>;
type Storage = ReturnType<typeof originalLocalContentStoragePolicy> &
  Readonly<{namespaceId: string; storeAuthorityCid: string}>;
type Definition = Activation[1]['runDefinition'];
type KeyedPlan = Readonly<{compiled: unknown; runDefinition: Definition; graph: unknown}>;
type Capture = Readonly<{capture: NonNullable<LookupOptions['originalCapture']>}>;
type CapturedSource = Readonly<{captured: Capture; sourceEvidence: unknown}>;
type Captures = readonly Capture[];
type Sources = readonly CapturedSource[];
type Control = Activation[3] & Page[3] & Readonly<{
  startInstalledEffectKeyedCaptureInput(run: unknown, prepared: unknown, request: unknown,
    compiled: unknown, definition: Definition, graph: unknown, acquisition: unknown,
    captures: Captures, limits: Readonly<{maxEntries: number; maxNameBytes: number; maxBytes: number; maxWork: number}>): unknown;
  prepareInstalledOriginalComposedKeyedHostInput(run: unknown, compiled: unknown, definition: Definition,
    graph: unknown, scope: unknown, acquisition: unknown, captures: Captures, host: unknown): Readonly<{left?: unknown; prefix?: unknown}>;
  startInstalledOriginalComposedKeyedPrefix(run: unknown, compiled: unknown, definition: Definition,
    graph: unknown, scope: unknown, acquisition: unknown, captures: Captures): unknown;
  keyedLookupPublicationEvidence(observation: unknown): unknown;
  prepareKeyedLookupSourceMetadata(lookup: unknown, request: unknown, captures: Captures, sources: Sources,
    selection: Retention, output: OutputLimits, maxWork: number, limits: Limits, files?: readonly unknown[]): unknown;
  prepareKeyedLookupRawCapture(request: unknown, compiled: unknown, definition: Definition, retention: unknown,
    storage: Storage, cid: string, bytes: number, at: string, nowMs: bigint,
    limits: Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxTextUnits: number}>): Readonly<{
      binding: RawRequest; original: unknown;
    }>;
  prepareKeyedLookupCapturedPage(request: unknown, capture: unknown, raw: unknown, at: string,
    output: OutputLimits, maxWork: number, limits: Limits): unknown;
  prepareGenericEffectKeyedLookupSourceMetadata(parent: unknown, lookup: unknown, captures: Captures,
    sources: Sources, selection: Retention, limits: Limits): unknown;
  finishGenericEffectKeyedLookupPublicationInput(parent: unknown, lookup: unknown, at: string, limits: Limits): unknown;
}>;
type Runtime = Activation[2] & Readonly<{
  clientProgramEffectComposedModelKeyedAcquisition(prepared: unknown, graph: unknown): unknown;
  clientProgramEffectAcquisitionCount?(prepared: unknown): number;
  clientProgramKeyedLookupStop(lookup: unknown): void;
  clientProgramKeyedLookupCleanup(lookup: unknown, quantum: number): unknown;
  clientProgramSerializationPrefixCancel(execution: unknown): boolean;
  clientProgramSerializationPrefixCleanup(execution: unknown): unknown;
  clientProgramKeyedAcquisitionSourceEvidenceFacts(acquisition: unknown): unknown;
  clientProgramInstalledEffectKeyedInputWorkLimit(run: unknown, prepared: unknown, request: unknown): unknown;
  clientProgramInstalledEffectKeyedOriginal(run: unknown, prepared: unknown, request: unknown): unknown;
  clientProgramKeyedLookupLeft(lookup: unknown): unknown;
  clientProgramOriginalComposedKeyedPrefixExecution(prefix: unknown): unknown;
  clientProgramOriginalComposedKeyedPrefixAdvance(prefix: unknown, quantum: number): unknown;
  clientProgramCompleteOriginalComposedKeyedPrefix(prefix: unknown): unknown;
  clientProgramEffectKeyedPlanGraphIsGeneric(graph: unknown): boolean;
  clientProgramKeyedLookupStartDeclaredFileRequestPlan(lookup: unknown, at: string, nowMs: bigint, scope: string): unknown;
  clientProgramKeyedLookupDeclaredFilePublicationInputDeferredCatalog(lookup: unknown, at: string,
    nowMs: bigint, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramKeyedLookupPrepareActivation(lookup: unknown, request: unknown, identity: unknown,
    scope: string, at: string, nowMs: bigint, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
}>;
type Acquired = Readonly<{
  prepared: unknown; compilation: unknown; requestIdentity: unknown; authorityScopeCid: string;
  runDefinition: Definition; control: Control; selectRetention(): Retention;
}>;
type ContentFrame = NonNullable<LookupOptions['keyedContent']> & Readonly<{
  recoveryInventory(): unknown;
  sourceBinding: ReturnType<Preparation['keyedRecoveryBinding']>;
}>;
type ContentRun = Readonly<{
  captureKeyed(options: Readonly<{
    preparedEffect: unknown; compilation: unknown; plan: KeyedPlan; acquisition: unknown; ledger: unknown;
    maxBytes: number; maxWork: number; sourceBinding: ContentFrame['sourceBinding']; store?: Store;
    principalId?: string; signal?: AbortSignal; inputAvailable(): boolean;
    retainExecution(child: Custody): void;
  }>): ContentFrame;
}>;
type PublicationContext = Readonly<{
  acquired: Acquired; captures: Captures; sources: Sources; signal?: AbortSignal;
  now(): string; current(): void;
}>;
type Inference = Readonly<{graph: unknown}>;
type KeyedOptions = PublicationContext & Readonly<{
  moon: Runtime; managedRun: unknown; infer?: Inference; selected?: unknown;
  originalPreparation?: Readonly<{scope?: unknown}>;
  plan?: KeyedPlan; sourceProfile: SourceProfile; ledger: unknown; contentRun?: ContentRun;
  store?: Store; principalId?: string; retain(owner: Custody): void; requestJournal?: Journal;
  runRef?: Activation[0]; originalHost?: unknown;
  sourcePreparation?: KeyedPlan & Readonly<{acquisition: unknown}>;
}>;
type NativePublication = PublicationContext & Pick<KeyedOptions, 'moon' | 'infer' | 'requestJournal' | 'runRef' | 'store'> &
  Readonly<{plan: KeyedPlan; sourceOriginal: unknown; capacity: KeyedCapacity; fileReadDeclarations?: readonly unknown[]}>;


export async function prepareAcquiredEffectKeyedPrefix(options: KeyedOptions) {
  return prepareOriginalEffectKeyedInput(options);
}

// The selected Source plan is a real no-Model compiler original. Both callers
// keep the same Row/Content/Journal/cleanup loop below; no second IO engine.
export async function prepareAcquiredEffectKeyedCapture(options: KeyedOptions) {
  if (options.sourcePreparation === undefined || options.infer !== undefined) {
    throw new TypeError('InstalledEffectKeyedOriginalUnavailable');
  }
  return prepareOriginalEffectKeyedInput(options);
}

async function prepareOriginalEffectKeyedInput({moon, acquired, managedRun,
  infer, selected, originalPreparation, plan, captures, sources, sourceProfile, ledger,
  contentRun, store, principalId, signal, now, current, retain, requestJournal, runRef, originalHost,
  sourcePreparation}: KeyedOptions) {
  plan ??= sourcePreparation;
  const acquisition = sourcePreparation === undefined
    ? checked(moon.clientProgramEffectComposedModelKeyedAcquisition(acquired.prepared, infer!.graph))
    : sourcePreparation.acquisition;
  if (acquisition === undefined) return undefined;
  const sourceCount = moon.clientProgramEffectAcquisitionCount?.(acquired.prepared);
  if (!Number.isSafeInteger(sourceCount) || sourceCount! < 1 || captures.length !== sourceCount ||
      sourcePreparation === undefined && (selected === undefined || originalPreparation?.scope === undefined) ||
      plan?.compiled === undefined || typeof retain !== 'function') {
    throw new TypeError('InstalledComposedKeyedOriginalUnavailable');
  }
  let prefix: unknown, execution: unknown, lookup: Awaited<ReturnType<OpenLookup>> | undefined,
    sourceLookup: unknown, sourceOriginal: unknown, keyedContent: (Custody & Readonly<{frame?: ContentFrame}>) | undefined,
    publication: (NonNullable<LookupOptions['publication']> & Readonly<{cleanup(): Promise<boolean>}>) | undefined,
    failureRecovery: Custody | undefined,
    uncertain = false, closed = false;
  const cleanup = async () => {
    if (closed) return true;
    // Raw response backing is still funded by its SAME RowRun. Return that
    // actual byte-holder borrow before retiring the RowRun/lookup credit.
    if (publication !== undefined && await publication.cleanup() !== true) return false;
    if (uncertain) return false;
    if (failureRecovery !== undefined) {
      await failureRecovery.close();
      if (await failureRecovery.cleanup() === false || failureRecovery.cleanupPending() !== false) return false;
      failureRecovery = undefined;
    }
    if (lookup !== undefined) {
      await lookup.close();
      if (await lookup.cleanup() === false || lookup.cleanupPending() !== false) return false;
      lookup = undefined;
    }
    if (sourceLookup !== undefined) {
      // Before the adapter returns, this same custody still owns a partially
      // constructed assembly. Its actual Row children/recovery settle above.
      moon.clientProgramKeyedLookupStop(sourceLookup);
      while (!checked(moon.clientProgramKeyedLookupCleanup(sourceLookup, 64))) {
        await yieldEventLoop();
      }
      sourceLookup = undefined;
    }
    if (keyedContent !== undefined) {
      if (await keyedContent.cleanup() === false || keyedContent.cleanupPending() !== false) return false;
      keyedContent = undefined;
    }
    if (execution !== undefined) {
      moon.clientProgramSerializationPrefixCancel(execution);
      if (checked(moon.clientProgramSerializationPrefixCleanup(execution)) !== true) return false;
      execution = undefined; prefix = undefined;
    }
    closed = true;
    return true;
  };
  retain(Object.freeze({close: cleanup, cleanup, cleanupPending: () => !closed}));
  current();
  const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(acquisition)) as readonly string[];
  const adapter = installedSourceFor<KeyedAdapter>(sourceProfile, facts[0]);
  const access = adapter.sourceAccess;
  // Resolve the same installed Plan's ValueBudget policy before the first
  // capacity quote. Model/prefix and standalone adapters keep their own limits.
  const originalWork = sourcePreparation === undefined ? undefined
    : checked(moon.clientProgramInstalledEffectKeyedInputWorkLimit(
      managedRun, acquired.prepared, acquired.requestIdentity)) as number;
  current();
  const capacity = adapter.keyedLedgerCapacity(acquisition,
    originalWork === undefined ? undefined : {originalWork});
  let left: unknown;
  if (sourcePreparation !== undefined) {
    sourceOriginal = checked(moon.clientProgramInstalledEffectKeyedOriginal(
      managedRun, acquired.prepared, acquired.requestIdentity));
    current();
    sourceLookup = acquired.control.startInstalledEffectKeyedCaptureInput(
      managedRun, acquired.prepared, acquired.requestIdentity, plan.compiled,
      plan.runDefinition, plan.graph, acquisition, captures,
      {maxEntries: localContractLimits.maxNodes, maxNameBytes: localContractLimits.maxWireBytes,
        maxBytes: capacity.maxBytes, maxWork: capacity.maxWork});
    left = moon.clientProgramKeyedLookupLeft(sourceLookup);
  } else if (originalHost !== undefined) {
    const original = acquired.control.prepareInstalledOriginalComposedKeyedHostInput(managedRun,
      plan.compiled, plan.runDefinition, infer!.graph, originalPreparation!.scope, acquisition, captures, originalHost);
    left = original.left; prefix = original.prefix;
  } else {
    prefix = acquired.control.startInstalledOriginalComposedKeyedPrefix(managedRun,
      plan.compiled, plan.runDefinition, infer!.graph, originalPreparation!.scope, acquisition, captures);
  }
  if (prefix !== undefined) {
    execution = moon.clientProgramOriginalComposedKeyedPrefixExecution(prefix);
    current();
    for (;;) {
      signal?.throwIfAborted();
      const poll = checked(moon.clientProgramOriginalComposedKeyedPrefixAdvance(prefix, 64));
      current();
      if (runtimeField(poll, 0)) break;
      if (runtimeField(poll, 2) !== undefined) {
        throw Object.assign(new Error('InstalledComposedKeyedPrefixFailed'),
          {code: 'MoonBitHostFailure', cause: runtimeField(poll, 2)});
      }
      if (runtimeField(poll, 1)) throw new Error('InstalledComposedKeyedPrefixStopped');
      await yieldEventLoop();
    }
    left = checked(moon.clientProgramCompleteOriginalComposedKeyedPrefix(prefix));
  }
  current();
  if (left === undefined) throw new Error('OriginalKeyedHostLeftUnavailable');
  const prepared = await adapter.prepareKeyed({preparedEffect: acquired.prepared,
    keyedAcquisition: acquisition, requestIdentity: acquired.requestIdentity, sourceAccess: access});
  current();
  if (adapter.requiresRunContentCapture === true) {
    if (typeof contentRun?.captureKeyed !== 'function') throw new Error('InstalledContentCaptureUnavailable');
    const frame = contentRun.captureKeyed({preparedEffect: acquired.prepared, compilation: acquired.compilation,
      plan, acquisition, ledger, maxBytes: capacity.maxBytes, maxWork: capacity.maxWork,
      sourceBinding: adapter.keyedRecoveryBinding(prepared.prepared), store, principalId, signal,
      inputAvailable: () => {current(); return true;},
      retainExecution: child => {keyedContent = child;}});
    // The actual frame owns its operational methods, while its separately
    // retained child above owns cleanup even if construction fails.
    const child = keyedContent as Custody;
    keyedContent = Object.freeze({...child, frame});
  }
  const generic = sourceOriginal !== undefined &&
    moon.clientProgramEffectKeyedPlanGraphIsGeneric(plan.graph) === true;
  publication = generic
    ? originalGenericKeyedLookupPublication({acquired, sourceOriginal, captures, sources, signal, now, current})
    : originalKeyedLookupPublication({moon, acquired, plan, infer, sourceOriginal,
      captures, sources, requestJournal, runRef, capacity, signal, now, current, store,
      fileReadDeclarations: sourceProfile.fileReadDeclarations});
  try {
    lookup = await adapter.openKeyedLookup({preparedEffect: acquired.prepared,
      publication,
      managedRun, keyedAcquisition: acquisition, left, ledger, signal,
      ...(sourceLookup === undefined ? {} : {sourceLookup}),
      preparedKeyed: prepared.prepared, sourceAccess: access,
      ...(sourcePreparation === undefined
        ? {originalCaptures: captures.map(value => value.capture)}
        : {originalCapture: captures[0].capture}),
      keyedContent: keyedContent?.frame, maxWork: capacity.maxWork, maxNodes: capacity.maxNodes});
  } catch (cause) {
    const end = acquisitionEndHandoff().outcome(cause);
    if (end.outcome === 'unknown') {
      failureRecovery = end.recovery as Custody | undefined;
      uncertain = failureRecovery === undefined;
    }
    throw cause;
  }
  current();
  const observation = await lookup.issueObservation({authorityScopeCid: acquired.authorityScopeCid,
    observedAt: now()});
  current();
  const original = await lookup.borrowSerializationInput();
  current();
  const evidence = acquired.control.keyedLookupPublicationEvidence(observation.observation);
  const result: {lookup: typeof original; observation: typeof observation.observation; evidence: unknown;
    sourceOriginal?: unknown; capturedInput?: Readonly<{recovery: unknown; binding: ContentFrame['sourceBinding']}>;
    contentOwner?: ContentFrame} = {lookup: original, observation: observation.observation, evidence,
    ...(sourceOriginal === undefined ? {} : {sourceOriginal}),
    ...(keyedContent === undefined ? {} : {capturedInput: Object.freeze({
      recovery: keyedContent.frame!.recoveryInventory(),
      binding: keyedContent.frame!.sourceBinding})})};
  // Borrow the operational frame already retained by this same cleanup owner.
  // Recovery metadata cannot reconstruct its original Store/Reference custody.
  if (keyedContent !== undefined) result.contentOwner = keyedContent.frame!;
  return Object.freeze(result);
}

// Same lookup/Source/Journal originals, not a second acquisition owner. The
// installing Source calls initialize before planning and activate before send.
function originalKeyedLookupPublication({moon, acquired, plan, infer, sourceOriginal, captures, sources,
  requestJournal, runRef, capacity, signal, now, current, store, fileReadDeclarations}: NativePublication) {
  if (typeof requestJournal?.persistOriginalKeyedLookupActivation !== 'function' ||
      typeof requestJournal?.persistOriginalKeyedLookupPage !== 'function' ||
      typeof store?.prepareLookupRawEvidence !== 'function' ||
      typeof store?.confirmLookupRawEvidence !== 'function' ||
      typeof store?.commitPhysicalHolding !== 'function' ||
      runRef?.runDefinitionCid !== acquired.runDefinition.identity ||
      typeof acquired.control.prepareKeyedLookupSourceMetadata !== 'function' ||
      typeof acquired.control.prepareKeyedLookupRawCapture !== 'function' ||
      typeof acquired.control.prepareKeyedLookupCapturedPage !== 'function' ||
      !Array.isArray(sources) || sources.length !== captures.length) {
    throw new TypeError('OriginalKeyedLookupJournalUnavailable');
  }
  let lookup: unknown, retention: unknown, storage: Storage;
  const holdings: ReturnType<typeof preparePrivatePublicationHolding>[] = [];
  let storeReadCleanup: ReadCleanup | undefined, storeReadFlight: Promise<boolean> | undefined;
  // Only THIS trusted Store confirmation can retain its actual failed reader.
  // Cleanup retries that same close handle; it does not reopen/read as cleanup.
  const confirmRaw: NonNullable<HoldingStore['confirmLookupRawEvidence']> = async binding => {
    if (storeReadFlight !== undefined || storeReadCleanup !== undefined) throw new TypeError('LookupRawReaderCleanupPending');
    try { return await store.confirmLookupRawEvidence(binding); }
    catch (error) {
      if ((error as {cleanupHandle?: ReadCleanup} | null | undefined)?.cleanupHandle !== undefined) storeReadCleanup = (error as {cleanupHandle: ReadCleanup}).cleanupHandle;
      throw error;
    }
  };
  const cleanupStoreReads = async () => {
    if (storeReadFlight !== undefined) return storeReadFlight;
    if (storeReadCleanup === undefined) return true;
    const original = storeReadCleanup;
    if (original.status().pending === false) {storeReadCleanup = undefined;return true;}
    let flight: Promise<boolean>;
    flight = Promise.resolve().then(() => original.retry()).catch(() => {})
      .then(() => {
        if (original.status().pending !== false) return false;
        if (storeReadCleanup === original) storeReadCleanup = undefined;
        return true;
      }).finally(() => {if (storeReadFlight === flight) storeReadFlight = undefined;});
    storeReadFlight = flight;
    return flight;
  };
  const originalCurrent = () => {signal?.throwIfAborted(); current();};
  return Object.freeze({
    initialize(original: unknown) {
      originalCurrent();
      if (lookup !== undefined) throw new TypeError('OriginalKeyedLookupAlreadyInitialized');
      lookup = original;
      const selection = keyedInputRetentionSelection(acquired);
      storage = Object.freeze({namespaceId:runRef.namespaceId, storeAuthorityCid:store?.storeAuthorityCid,
        ...originalLocalContentStoragePolicy({storeAuthorityCid:store?.storeAuthorityCid,
          authorityScopeCid:acquired.authorityScopeCid, runDefinitionCid:acquired.runDefinition.identity,
          expiresAt:selection.expiresAt})});
      retention = acquired.control.prepareKeyedLookupSourceMetadata(lookup,
        acquired.requestIdentity, captures, sources, selection,
        localOutputLimits, capacity.maxWork, localContractLimits, fileReadDeclarations);
      originalCurrent();
      checked(moon.clientProgramKeyedLookupStartDeclaredFileRequestPlan(lookup, now(),
        BigInt(Math.floor(performance.now())), acquired.authorityScopeCid));
      originalCurrent();
    },
    responseBackingReleased() {
      if (storeReadCleanup !== undefined || storeReadFlight !== undefined) return false;
      return holdings.every(holding => {
        const state = holding.status();
        return (state.committed || state.abandoned) && !state.operationPending && !state.preparedPending;
      });
    },
    async cleanup() {
      if (!await cleanupStoreReads()) return false;
      for (const holding of holdings) {
        await holding.abort();
        const state = holding.status();
        if (state.operationPending || state.preparedPending || (!state.committed && !state.abandoned)) return false;
      }
      holdings.length = 0;
      return true;
    },
    async retainRawResponse(original: unknown, request: unknown, attempt: unknown, bytes: Uint8Array) {
      originalCurrent();
      if (lookup !== original || retention === undefined || !(bytes instanceof Uint8Array) ||
          typeof store?.prepareLookupRawEvidence !== 'function') {
        throw new TypeError('ForeignOriginalKeyedRawResponse');
      }
      const captured = acquired.control.prepareKeyedLookupRawCapture(request, plan.compiled,
        plan.runDefinition, retention, storage, bytesCid(bytes), bytes.byteLength, now(),
        BigInt(Math.floor(performance.now())), {maxBytes:capacity.maxBytes,
          maxNodes:256, maxDepth:32, maxTextUnits:capacity.maxBytes});
      originalCurrent();
      const holding = preparePrivatePublicationHolding({
        confirmLookupRawEvidence: confirmRaw,
        prepareLookupRawEvidence: (...args) => store.prepareLookupRawEvidence(...args),
        commitPhysicalHolding: (...args) => store.commitPhysicalHolding(...args),
      }, captured.binding, bytes);
      // Retain the original partial writer/commit owner BEFORE its first await.
      holdings.push(holding);
      await holding.commit();
      originalCurrent();
      return captured.original;
    },
    adopt(original: unknown, request: unknown, attempt: unknown, capture: unknown, raw: unknown) {
      originalCurrent();
      if (lookup !== original || raw === undefined) throw new TypeError('ForeignOriginalKeyedPage');
      const page = acquired.control.prepareKeyedLookupCapturedPage(request, capture, raw,
        now(), localOutputLimits, capacity.maxWork, localContractLimits);
      originalCurrent();
      requestJournal.persistOriginalKeyedLookupPage(runRef, {page, keyedRequest:request,
        activationRecord:(attempt as {record: Page[1]['activationRecord']}).record, identity:acquired.requestIdentity,
        preparedEffect:acquired.prepared, compilation:acquired.compilation,
        compiled:plan.compiled, runDefinition:plan.runDefinition, graph:infer?.graph,
        ...(sourceOriginal === undefined ? {} : {sourceOriginal}),
        limits:localContractLimits}, moon, acquired.control);
      originalCurrent();
    },
    finishInput(original: unknown) {
      originalCurrent();
      if (lookup !== original || holdings.some(owner => owner.status().committed !== true)) {
        throw new TypeError('OriginalKeyedRawHoldingUnavailable');
      }
      const read = checked(moon.clientProgramKeyedLookupDeclaredFilePublicationInputDeferredCatalog(
        lookup, now(), BigInt(Math.floor(performance.now())),
        localContractLimits.maxWireBytes, localContractLimits.maxNodes, localContractLimits.maxDepth));
      originalCurrent();
      return read;
    },
    activate(original: unknown, request: unknown) {
      originalCurrent();
      if (lookup !== original || retention === undefined) throw new TypeError('ForeignOriginalKeyedLookup');
      const activation = checked(moon.clientProgramKeyedLookupPrepareActivation(lookup,
        request, acquired.requestIdentity, acquired.authorityScopeCid, now(),
        BigInt(Math.floor(performance.now())), localContractLimits.maxWireBytes,
        localContractLimits.maxNodes, localContractLimits.maxDepth));
      const record = requestJournal.persistOriginalKeyedLookupActivation(runRef, {
        activation, identity: acquired.requestIdentity, preparedEffect: acquired.prepared,
        compilation: acquired.compilation, compiled: plan.compiled,
        runDefinition: plan.runDefinition, graph: infer?.graph, limits: localContractLimits,
        ...(sourceOriginal === undefined ? {} : {sourceOriginal}),
      }, moon, acquired.control);
      originalCurrent();
      return Object.freeze({activation, record});
    },
  });
}


// The actual generic content_ref protocol uses the same funded lookup and
// captured Source bodies. Content bytes/holding stay with the original Store;
// no Native activation, raw-response archive or cleanup ACK is manufactured.
function originalGenericKeyedLookupPublication({acquired, sourceOriginal, captures, sources, signal, now, current}:
  PublicationContext & Readonly<{sourceOriginal: unknown}>) {
  if (typeof acquired.control.prepareGenericEffectKeyedLookupSourceMetadata !== 'function' ||
      typeof acquired.control.finishGenericEffectKeyedLookupPublicationInput !== 'function') {
    throw new TypeError('OriginalGenericKeyedLookupPublicationUnavailable');
  }
  let lookup: unknown, retention: unknown;
  const originalCurrent = () => {signal?.throwIfAborted(); current();};
  return Object.freeze({protocol: 'generic-source',
    initialize(original: unknown) {
      originalCurrent();
      if (lookup !== undefined) throw new TypeError('OriginalKeyedLookupAlreadyInitialized');
      lookup = original;
      retention = acquired.control.prepareGenericEffectKeyedLookupSourceMetadata(sourceOriginal, lookup,
        captures, sources, keyedInputRetentionSelection(acquired), localContractLimits);
      originalCurrent();
    },
    finishInput(original: unknown) {
      originalCurrent();
      if (lookup !== original || retention === undefined) throw new TypeError('ForeignOriginalGenericKeyedLookup');
      const read = acquired.control.finishGenericEffectKeyedLookupPublicationInput(sourceOriginal, lookup,
        now(), localContractLimits);
      originalCurrent();
      return read;
    },
    async cleanup() {return true;},
  });
}
