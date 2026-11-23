import {installedSourceFor} from './installed-source.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {bindClientSourceOperation} from './client-source-operation.mjs';

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
