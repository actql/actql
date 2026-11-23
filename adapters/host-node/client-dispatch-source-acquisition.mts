import {installedSourceFor} from './installed-source.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {bindClientSourceOperation} from './client-source-operation.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {acquiredKeyedTaskPublicationPlan} from './local-values-plan.mjs';

import type {createInstalledRowSourceKeyedLookup} from './installed-row-source-keyed-lookup.mjs';
import type {createInstalledRowSourceKeyedPreparation} from './installed-row-source-keyed-preparation.mjs';

type PreparedSource = Readonly<{
  checkedSource: Readonly<{sourceRef: string}>;
  selection?: unknown;
}>;
type EvidenceInputs = Readonly<{
  authorityScopeCid: string;
  effectiveDataPolicyCid: string;
}>;
type SourceCapture = Readonly<{
  capture: unknown;
  acquisition?: unknown;
  checkedSource: Readonly<{sourceDataPolicyCid: string}>;
  close(): unknown;
  prepareSourceEvidenceOriginal(options: EvidenceInputs): unknown;
  issueSourceEvidence(options: EvidenceInputs): string | Promise<string>;
}>;
type RecoveryOwner = Readonly<{
  close(): unknown;
  cleanup(): unknown;
  cleanupPending(): unknown;
}>;
type AcquisitionEntry<Ref> = {
  ref: Ref;
  sourceOperationScope?: object;
  sourceCapture?: SourceCapture;
  cleanupOwner?: RecoveryOwner;
  physicalStarted?: boolean;
  physicalWorkMayHaveStarted?: boolean;
  stopObservationPending?: boolean;
  unresolvedCleanup?: boolean;
  abort: AbortController;
};
type AcquisitionOptions = Readonly<{
  captureOnly?: boolean;
  originalEvidence?: boolean;
  ledger?: unknown;
  occurrence?: unknown;
}>;
type SourceOpenInputs = Readonly<{
  preparedProgram: unknown;
  preparedSource: PreparedSource;
  registry: unknown;
  values: unknown;
  fragment: unknown;
  ordered: unknown;
  sourceAccess: unknown;
  signal: AbortSignal;
  retainedRelationOutput: boolean;
  ledger: unknown;
  reportAcquisitionFailure: ReturnType<typeof acquisitionEndHandoff>['retain'];
  originalOperationScope?: ReturnType<typeof bindClientSourceOperation>;
}>;
type SourceOpen = (options: SourceOpenInputs) => SourceCapture | Promise<SourceCapture>;
type SourceMember = Readonly<{
  admitsSource(sourceRef: string): boolean;
  open: SourceOpen;
  openCapture?: SourceOpen;
}>;
type AcquisitionPorts<Ref> = Readonly<{
  sourceProfile: Parameters<typeof installedSourceFor<SourceMember>>[0];
  now(): string;
  step(name: 'acquisition_started' | 'acquisition_completed', fields: Readonly<{
    ref: Ref; selection?: unknown; acquisition?: unknown;
  }>): unknown;
  observation?: Readonly<{
    canMeasure(phase: 'source'): boolean;
    emit(phase: 'source', kind: 'acquisition_interval', detail: Readonly<{
      ref: Ref; outcome: 'confirmed' | 'failed';
    }>, measurement: Readonly<{segment: 'source-acquisition'; durationMs: number}>): void;
  }>;
  registry: unknown;
  values: unknown;
  fragment: unknown;
  ordered: unknown;
  store: object;
  journal: object;
  retainedRelationOutput: boolean;
  authorityScopeCid: string;
  control: Readonly<{takeSourceEvidenceOriginal(capture: unknown): unknown}>;
}>;

export function createClientDispatchSourceAcquisition<Ref>({sourceProfile, now, step, observation,
  registry, values, fragment, ordered, store, journal, retainedRelationOutput,
  authorityScopeCid, control}: AcquisitionPorts<Ref>) {
  async function acquireSource(entry: AcquisitionEntry<Ref>, preparedProgram: unknown,
    preparedSource: PreparedSource, sourceAccess: unknown,
    {captureOnly = false, originalEvidence = false, ledger, occurrence}: AcquisitionOptions = {}) {
    if (entry.sourceCapture !== undefined) {
      throw new TypeError('ClientSourceCaptureAlreadyRetained');
    }
    const installedSource = installedSourceFor(sourceProfile,
      preparedSource.checkedSource.sourceRef);
    const captureStartedAt = now();
    await step('acquisition_started', {ref: entry.ref,
      ...(preparedSource.selection === undefined ? {} :
        {selection: preparedSource.selection})});
    entry.physicalStarted = true;
    entry.physicalWorkMayHaveStarted = true;
    const acquisition = acquisitionEndHandoff();
    const measured = observation?.canMeasure('source') ? performance.now() : undefined;
    let returned = false;
    try {
      const open = captureOnly ? installedSource.openCapture : installedSource.open;
      if (typeof open !== 'function') throw new TypeError('InstalledSourceCaptureUnavailable');
      entry.sourceCapture = await open({preparedProgram,
        registry, values, fragment, ordered, sourceAccess,
        signal: entry.abort.signal, preparedSource,
        retainedRelationOutput, ledger,
        reportAcquisitionFailure: acquisition.retain,
        ...(entry.sourceOperationScope === undefined ? {} : {
          originalOperationScope: bindClientSourceOperation(entry.sourceOperationScope,
            journal, store, preparedProgram, preparedSource, occurrence ?? {stage: 0, input: 0, task: 0}),
        })});
      returned = true;
    } catch (error) {
      const ended = acquisition.outcome(error);
      if (ended.outcome === 'not_started' || ended.outcome === 'stopped') {
        entry.stopObservationPending = true;
      } else if (ended.recovery !== undefined) {
        entry.cleanupOwner = ended.recovery as RecoveryOwner;
      } else {
        entry.unresolvedCleanup = true;
      }
      throw error;
    } finally {
      if (measured !== undefined) observation!.emit('source', 'acquisition_interval',
        {ref: entry.ref, outcome: returned ? 'confirmed' : 'failed'},
        {segment: 'source-acquisition', durationMs: performance.now() - measured});
    }
    const captureCompletedAt = now();
    await step('acquisition_completed', {ref: entry.ref,
      ...(entry.sourceCapture.acquisition === undefined ? {} :
        {acquisition: entry.sourceCapture.acquisition})});
    const evidenceOptions = {authorityScopeCid,
      effectiveDataPolicyCid: entry.sourceCapture.checkedSource.sourceDataPolicyCid};
    let sourceEvidence, sourceEvidenceWire;
    if (originalEvidence) {
      await entry.sourceCapture.prepareSourceEvidenceOriginal(evidenceOptions);
      sourceEvidence = control.takeSourceEvidenceOriginal(entry.sourceCapture.capture);
    } else sourceEvidenceWire = await entry.sourceCapture.issueSourceEvidence(evidenceOptions);
    return {captured: entry.sourceCapture, captureStartedAt, captureCompletedAt,
      sourceEvidence, sourceEvidenceWire};
  }

  return acquireSource;
}

type KeyedPublication = Parameters<typeof acquiredKeyedTaskPublicationPlan<unknown>>[0];
type AcquiredTaskPlan = KeyedPublication['acquired'];
type OpenLookup = ReturnType<typeof createInstalledRowSourceKeyedLookup>;
type LookupInput = Parameters<OpenLookup>[0];
type Lookup = Awaited<ReturnType<OpenLookup>>;
type LookupHostInputs = Parameters<Lookup['openHost']>[0];
type RecoveryBinding = ReturnType<typeof createInstalledRowSourceKeyedPreparation>['keyedRecoveryBinding'];
type KeyedChild = Readonly<{close(): unknown; cleanup?: undefined}> | RecoveryOwner;
type KeyedEntry<Ref> = Pick<AcquisitionEntry<Ref>, 'ref' | 'abort' | 'physicalWorkMayHaveStarted' | 'unresolvedCleanup'> & {
  borrowedSources?: boolean;
  sourceCapture?: Pick<KeyedChild, 'close'>;
  pendingSetup?: Awaited<ReturnType<Lookup['openHost']>>;
};
type KeyedCapture = SourceCapture & KeyedPublication['captured'];
type KeyedOccurrence = Readonly<{stage: number; input: number; task: number}>;
type KeyedSelection = Readonly<{
  directAdapter: Readonly<{
    openCapture(input: Pick<SourceOpenInputs, 'preparedProgram' | 'preparedSource' | 'sourceAccess' | 'signal' | 'ledger'> &
      Pick<LookupHostInputs, 'registry' | 'values' | 'fragment' | 'ordered'> &
      Readonly<{occurrence: KeyedOccurrence}>): KeyedCapture | PromiseLike<KeyedCapture>;
  }>;
  keyedAdapter: Readonly<{openKeyedLookup: OpenLookup; keyedRecoveryBinding?: RecoveryBinding}>;
  preparedSource: PreparedSource;
  directOccurrence: KeyedOccurrence;
  directAccess: unknown;
  keyedAccess: LookupInput['sourceAccess'];
  preparedKeyed: LookupInput['preparedKeyed'];
  acquisition: unknown;
  capacity: Readonly<{maxBytes: number; maxWork: number}>;
  ledger: unknown;
  capturedContent: boolean;
  managedRun?: unknown;
  requestIdentity?: unknown;
}>;
type KeyedPorts<Ref> = Pick<LookupHostInputs, 'registry' | 'values' | 'fragment' | 'ordered'> & Readonly<{
  moon: KeyedPublication['moon'] & Readonly<{
    clientProgramKeyedCaptureLeftRead(acquisition: unknown, captured: unknown): unknown;
  }>;
  control: KeyedPublication['control'] & AcquisitionPorts<Ref>['control'] & Readonly<{
    admitRunEvidence(kind: 'source_evidence', wire: string,
      bounds: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>): unknown;
  }>;
  runContent?: Readonly<{
    captureKeyed(options: Readonly<{
      preparedProgram: unknown;
      plan: AcquiredTaskPlan;
      acquisition: unknown;
      ledger: unknown;
      maxBytes: number;
      maxWork: number;
      sourceBinding: ReturnType<RecoveryBinding>;
      store: object;
      principalId: string;
      signal: AbortSignal;
      retainExecution(child: KeyedChild): void;
    }>): LookupInput['keyedContent'];
  }>;
  store: object;
  step(name: 'acquisition_started' | 'acquisition_completed',
    fields: Readonly<{ref: Ref; kind: 'direct' | 'keyed'; resourceUsage: unknown}>): unknown;
  resourceUsage(ledger: unknown): unknown;
  now(): string;
  authorityScopeCid: string;
  namespaceId: string;
  storeAuthorityCid: string;
  retainedRelationOutput: boolean;
}>;

export function createClientDispatchKeyedAcquisition<Ref>({moon, control, runContent, store,
  registry, values, fragment, ordered, step, resourceUsage, now, authorityScopeCid,
  namespaceId, storeAuthorityCid, retainedRelationOutput}: KeyedPorts<Ref>) {
  async function acquireKeyedSources(entry: KeyedEntry<Ref>, preparedProgram: unknown,
    selected: KeyedSelection, acquired: AcquiredTaskPlan, principalId: string) {
    const {directAdapter, keyedAdapter, preparedSource, directOccurrence,
      directAccess, keyedAccess, preparedKeyed, acquisition, capacity, ledger, capturedContent,
      managedRun, requestIdentity} = selected;
    // Retain the aggregate before the first await. Compute borrows these
    // inputs; its confirmed close must precede reclamation of either source.
    entry.borrowedSources = true;
    const children: KeyedChild[] = [];
    const closed = new Set<KeyedChild>();
    entry.sourceCapture = Object.freeze({async close() {
      const failures = [];
      for (const child of [...children].reverse()) {
        if (closed.has(child)) continue;
        try {
          await child.close();
          if (typeof child.cleanup === 'function' &&
              (await child.cleanup() === false || child.cleanupPending() !== false)) {
            throw new Error('ClientSourceCleanupPending');
          }
          closed.add(child);
        } catch (error) {
          failures.push(error);
          // The lookup can still borrow its left capture while stopping.
          // Keep earlier children until that dependent custody is reclaimed.
          break;
        }
      }
      if (failures.length) throw new AggregateError(failures, 'ClientSourceCleanupPending');
    }});
    const open = async <Child extends KeyedChild>(kind: 'direct' | 'keyed',
      operation: () => Child | PromiseLike<Child>) => {
      let returned = false;
      entry.abort.signal.throwIfAborted();
      await step('acquisition_started', {ref: entry.ref, kind,
        resourceUsage: resourceUsage(ledger)});
      entry.physicalWorkMayHaveStarted = true;
      try {
        const child = await operation();
        children.push(child);
        returned = true;
        await step('acquisition_completed', {ref: entry.ref, kind,
          resourceUsage: resourceUsage(ledger)});
        return child;
      } catch (error) {
        if (returned) throw error;
        const ended = acquisitionEndHandoff().outcome(error);
        if (ended.outcome === 'unknown') {
          // A lookup's failed child is source custody, not an execution owner.
          // Keep it alongside the already acquired Direct input for retry.
          if (ended.recovery !== undefined) children.push(ended.recovery as RecoveryOwner);
          else entry.unresolvedCleanup = true;
        }
        throw error;
      }
    };
    const captureStartedAt = now();
    const captured = await open('direct', () => directAdapter.openCapture({preparedProgram,
      registry, values, fragment, ordered, preparedSource,
      occurrence: directOccurrence, sourceAccess: directAccess,
      signal: entry.abort.signal, ledger}));
    const left = checked(moon.clientProgramKeyedCaptureLeftRead(acquisition,
      captured.capture.source()));
    const keyedContent = !capturedContent ? undefined : runContent!.captureKeyed({
      preparedProgram, plan: acquired, acquisition, ledger, maxBytes: capacity.maxBytes, maxWork: capacity.maxWork,
      sourceBinding: keyedAdapter.keyedRecoveryBinding!(preparedKeyed!),
      store, principalId, signal: entry.abort.signal, retainExecution: child => children.push(child)});
    const lookup = await open('keyed', () => keyedAdapter.openKeyedLookup({preparedProgram,
      keyedAcquisition: acquisition, left, ledger, signal: entry.abort.signal,
      originalCapture: captured.capture, keyedContent,
      sourceAccess: keyedAccess, preparedKeyed, maxWork: capacity.maxWork}));
    const evidenceOptions = {authorityScopeCid,
      effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid};
    const contentOrInfer = acquired.serializationGraph !== undefined || acquired.kind === 'infer';
    let sourceEvidence, sourceEvidenceWire;
    if (contentOrInfer) sourceEvidenceWire = await captured.issueSourceEvidence(evidenceOptions);
    else {
      await captured.prepareSourceEvidenceOriginal(evidenceOptions);
      sourceEvidence = control.takeSourceEvidenceOriginal(captured.capture);
    }
    const keyedObservation = await lookup.issueObservation({authorityScopeCid, observedAt: now()});
    const effectiveDataPolicyCid = moon.clientProgramPublicationDataPolicyCid(preparedProgram);
    if (effectiveDataPolicyCid === undefined) throw new Error('InstalledKeyedSourcePolicyUnavailable');
    if (contentOrInfer) {
      // Both acquisition children remain in this supervisor's custody. The
      // Content provider borrows their exact sealed inputs; cleanup stops that
      // dependent before closing lookup and its left capture in reverse order.
      return {plan: acquired, acquiredContent: {captured, ledger, sourceEvidenceWire,
        authorityScopeCid, captureStartedAt, captureCompletedAt: now(), keyedObservation,
        keyedLookup: await lookup.borrowSerializationInput(), keyedContent,
        sourceEvidence: control.admitRunEvidence('source_evidence', sourceEvidenceWire!,
          {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
        keyedSourceEvidence: control.admitRunEvidence('source_evidence', keyedObservation.sourceEvidenceWire,
          {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})}};
    }
    const plan = acquiredKeyedTaskPublicationPlan({moon, control, acquired,
      publicationOriginal: managedRun === undefined ? undefined
        : {kind: 'installed_run', value: managedRun},
      preparedProgram, captured, sourceEvidence, keyedObservation,
      authorityScopeCid, effectiveDataPolicyCid, captureStartedAt, captureCompletedAt: now(),
      namespaceId, storeAuthorityCid, now});
    const setup = await lookup.openHost({registry, values, fragment, ordered, retainedRelationOutput,
      managedRun, requestIdentity});
    entry.pendingSetup = setup;
    return {plan, setup};
  }

  return acquireKeyedSources;
}
