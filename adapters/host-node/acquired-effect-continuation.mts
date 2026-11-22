// Host connection of Source acquisition to the existing Run-unit Checkpoint
// and encrypted continuation custody. This owns no scheduler or retry loop.
import {runtimeField, runtimeTriple} from '../host-common/compiler-binding.generated.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {recordCheckpointApproval, checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {validInstallationBinding} from './ordinary-source-binding.mjs';

import type {createAuthorizationGate} from '../host-common/authorization-gate.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type Authorization = ReturnType<typeof createAuthorizationGate>;
type Scope = Parameters<Authorization['authorize']>[1];
type Decision = Awaited<ReturnType<Authorization['authorize']>>;
type AuthorizationOptions = Parameters<Authorization['authorize']>[2];
type ResumeOptions = Parameters<Authorization['resume']>[2];
type Journal = NonNullable<NonNullable<Parameters<typeof createAuthorizationGate>[0]>['deferral']>['journal'];
type Admission = NonNullable<Decision['admission']>;
type Claim = Readonly<Pick<Admission, 'intentId' | 'claimant' | 'generation'> & {
  runId: string; prepareAttemptId?: string | null;
}>;
type Checkpoint = Parameters<Journal['persistCheckpoint']>[0];
type ResolutionSubmission = Readonly<{
  checkpointCid: string; resolutionWire: string; approvalEvidenceWire?: string; unknownEffects?: readonly string[];
}>;
type SourceJournal = Omit<Journal, 'submitResolution'> & Readonly<{
  submitResolution(item: ResolutionSubmission): Awaitable<unknown>;
  committedApprovalAt(checkpointCid: string): Readonly<{current: boolean}>;
  completeResume(claim: Claim, outcome: Readonly<{checkpoint: Checkpoint}>): Awaited<ReturnType<Journal['persistCheckpoint']>>;
}>;
type Occurrence = Readonly<{stage: number; input: number; task: number; computeTask?: number}>;
type InstallationBinding = typeof validInstallationBinding extends (value: unknown) => value is infer Binding ? Binding : never;
type SourceScope = Occurrence & Readonly<{
  checkedSource: unknown; readTuple: Scope; physicalBinding: unknown; physicalPolicy?: unknown;
  installationBinding?: InstallationBinding;
}>;
type PreparedSource = Readonly<{
  occurrence: Occurrence; checkedSource: unknown; readTuple: Scope; physicalBinding: unknown; physicalPolicy?: unknown;
}>;
type Preparation = Readonly<{checkedOwner: unknown; requestIdentity: unknown}>;
type Retention = Readonly<{requirement?: unknown; capacity: unknown; referenceIssuer?: unknown; wholeInput?: boolean}>;
type SourceAdapter = Readonly<{
  ordinaryRecoveryBinding?(prepared: PreparedSource, original: Preparation & Readonly<{occurrence: Occurrence}>): unknown;
  retainedCapture(prepared: PreparedSource): Retention;
}>;
type Source = Readonly<{occurrence: Occurrence; preparedSource: PreparedSource; adapter: SourceAdapter}>;
// The resumed Source decision projects the exact read scope. The Checkpoint
// still carries the principal separately in the original decision's facts.
type SourceDecision = Omit<Decision, 'tuple'> & Readonly<{tuple: Scope}>;
type ReadAddress = Readonly<{sourceRef?: string; connection?: string; resource?: string}>;
type SourceAccess = ReadAddress & Readonly<{authorization: Readonly<{
  authorize(...args: Parameters<Authorization['authorize']>): Promise<SourceDecision>;
}>}>;
type CurrentSourceAccess<Access extends SourceAccess> = Readonly<Pick<Access, Extract<keyof Access, keyof ReadAddress>> & {
  authorization: SourceAccess['authorization'];
  assertCurrent(): void;
}>;
type View = Readonly<{
  kind: string; prepareAttemptId: string | null; runId: string; runDefinitionCid: string; checkpointCid?: string;
}>;
type SavedContinuation = Readonly<{
  version: string; run_definition_cid: string; unit_id: string; submission: unknown; pending_task: number | null;
  capture_started_at: string | null; capture_completed_at: string | null;
  sources: readonly Readonly<{scope: SourceScope; capture_cid?: string}>[];
}>;
type Restoration = Readonly<{view: View; continuation: SavedContinuation}>;
type Resume = Restoration & Readonly<{
  view: View & Readonly<{checkpointCid: string}>;
  active: boolean; claim: Claim; assertCurrent(): void;
}>;
type Gate = Readonly<{
  authorize(options?: AuthorizationOptions): Awaitable<Decision>;
  resume(options?: ResumeOptions): Awaitable<Decision>;
  assertCurrent(): SynchronousRuntimeData;
  close(): boolean;
}>;
type Checkpoints = Readonly<{
  journal: SourceJournal;
  computationSourceAuthorization(options: Readonly<{
    runId: string; runDefinitionCid: string; unitId: string; occurrence: SourceScope; declaredResults: readonly string[];
    beforeDefer(): Promise<void>; continuation(): Promise<string>; journalPort?: SourceJournal;
  }>): Awaitable<Gate>;
  retainComputationSource(runId: string, runDefinitionCid: string, wire: string): Awaitable<string>;
  computationSourceReferences(view: View): Awaitable<readonly string[]>;
  readComputationSource(view: View, captureCid: string, maxBytes: number): Awaitable<Buffer>;
  retireComputationSources(runId: string): Awaitable<unknown>;
}>;
type OriginalInput = Readonly<{version: string; schema_cid: string; rows_cid: string; rows: readonly string[]}>;
type RecordBase = Readonly<{
  version: string; run_definition_cid: string; scope: SourceScope; acquisition: unknown; binding: string;
  source_evidence_wire: string; checkpoint_cid?: string; earlier_checkpoint_cids?: readonly string[];
  capture_started_at: string; capture_completed_at: string;
}>;
type CaptureRecord = RecordBase & Readonly<{
  input_kind?: string; source_identity?: unknown; schema_cid?: unknown; rows_cid?: unknown; rows: unknown;
  requirement_cid?: string; descriptor?: string; original_input?: OriginalInput | null;
}>;
type Capture = Readonly<{
  inputKind?: string; requirement?: unknown; acquisition?: unknown;
  capture: Readonly<{source(): unknown; originalRead?(): unknown}>;
}>;
type RestoredCapture = Capture & Readonly<{
  identity: unknown; logicalInput: unknown; wholeCapacity?: unknown; capturedSource: unknown;
  checkedSource: unknown; occurrence: Occurrence;
  capture: Readonly<{
    originalRead(): unknown; originalCapturedInput?(): unknown; retainTask(dag: unknown, task: number): unknown;
    close(): Promise<void>;
  }>;
  close(): Promise<void>;
}>;
type CaptureMaterial = Readonly<{
  captured: Capture; sourceEvidenceWire: string; startedAt: string; completedAt: string;
}>;
type State<Access extends SourceAccess = SourceAccess> = {
  base: Access; occurrence: Occurrence; access?: CurrentSourceAccess<Access>;
  scope?: SourceScope; source?: Source; adapter?: SourceAdapter; preparedSource?: PreparedSource;
  gate?: Gate; checkpointCid?: string; earlierCheckpointCids?: readonly string[]; decision?: Decision;
  enter?: () => void; captured?: Capture; material?: CaptureMaterial; captureCid?: string; record?: CaptureRecord;
};
type PreparedState = State & {scope: SourceScope; source: Source};
type ApprovalFacts = Readonly<{
  checkpointCid?: string; principalId?: string; readTuple?: unknown; checkedSource?: unknown;
  physicalBinding?: unknown; installationBinding?: unknown; occurrence?: Occurrence;
  earlierCheckpointCids?: readonly string[]; assertCurrent?(): unknown;
}>;
type OriginalInputTuple = ReturnType<typeof runtimeTriple<string, string, readonly string[]>>;
type Runtime = Readonly<{
  clientProgramExportWholeSourceCapture(source: unknown, capacity: unknown, binding: string): unknown;
  clientProgramExportSourceCapture(source: unknown, requirement: unknown, binding: string): unknown;
  clientProgramExportQuerySourceOriginalRead(read: unknown, requirement: unknown): unknown;
  clientProgramSourceCaptureExportRequirement(exported: unknown): string;
  clientProgramSourceCaptureExportDescriptor(exported: unknown): string;
  clientProgramSourceCaptureExportRows(exported: unknown): readonly string[];
  clientProgramEffectAcquisitionCount(prepared: unknown): number;
  clientProgramRestoreWholeSourceCapture(capacity: unknown, binding: string, savedBinding: string,
    savedIdentity: readonly string[], schemaCid: string, rowsCid: string, rows: readonly string[],
    ledger: unknown, custodyAvailable: () => boolean, referenceIssuer: unknown): unknown;
  clientProgramRestoreSourceCapture(requirement: unknown, requirementCid: string, binding: string, savedBinding: string,
    descriptor: string, rows: readonly string[], ledger: unknown, capacity: unknown, custodyAvailable: () => boolean,
    referenceIssuer: unknown, original: OriginalInputTuple | undefined): unknown;
  clientProgramSourceCaptureSource(owner: unknown): unknown;
  clientProgramCapturedTaskSourceMatches(prepared: unknown, capturedSource: unknown, task: number): boolean;
  clientProgramIdentifyWholeCapturedSourceRelation(source: unknown, capacity: unknown): unknown;
  clientProgramIdentifyWholeCapturedEffectSourceRelation(source: unknown, capacity: unknown): unknown;
  clientProgramIdentifyQueryCapturedSourceRelation(source: unknown, requirement: unknown): unknown;
  clientProgramIdentifyQueryCapturedEffectSourceRelation(source: unknown, requirement: unknown): unknown;
  clientProgramIssueWholeSourceInputLogical(prepared: unknown, source: unknown, identity: unknown, capacity: unknown): unknown;
  clientProgramIssueEffectWholeSourceInputLogical(prepared: unknown, source: unknown, identity: unknown, capacity: unknown): unknown;
  clientProgramIssueCapturedTaskSourceLogical(prepared: unknown, source: unknown, identity: unknown, requirement: unknown, task: number): unknown;
  clientProgramEffectIssueCapturedSourceLogicalAt(prepared: unknown, source: unknown, identity: unknown, requirement: unknown, task: number): unknown;
  clientProgramCloseSourceCapture(owner: unknown, quantum?: number): boolean;
  clientProgramSourceCaptureOriginalRead(owner: unknown): unknown;
  clientProgramRestoredWholeSourceCaptureInput(owner: unknown): unknown;
  clientProgramSourceCaptureRetainInput(owner: unknown, dag: unknown, task: number): unknown;
  clientProgramSourceCaptureRetainTask(owner: unknown, dag: unknown, task: number): unknown;
}>;
type Definition = Readonly<{identity: string; wire: string}>;
type Options = Readonly<{
  checkpoints?: Checkpoints; moon: Runtime;
  acquired: Readonly<{
    kind?: string; prepared: unknown; requestIdentity: unknown; runDefinition: Definition;
    control: Readonly<{runDefinitionRunId(definition: Definition): string}>;
  }>;
  submission: unknown; declaredResults: readonly string[]; principalId: string; unitId: string;
  resume?: Resume; restore?: Restoration; signal?: AbortSignal; currentRun?(): boolean;
  assertUpdateSelectionCurrent?(): SynchronousRuntimeData;
  assertContinuationCurrent?(): SynchronousRuntimeData;
}>;


const VERSION = 'actql-acquired-effect-continuation/0.1';
const BOUND_VERSION = 'actql-acquired-effect-bound-continuation/0.1';
const CAPTURE = 'actql-host-source-capture/0.1';
const ORIGINAL_INPUT = 'actql-host-source-original-input/0.1';
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const same = (left: unknown, right: unknown) => canonicalJson(left) === canonicalJson(right);
const sourceScope = (source: Source, original: Preparation) => {
  const {preparedSource: prepared, adapter} = source;
  const scope: Omit<SourceScope, 'installationBinding'> & {installationBinding?: InstallationBinding} = {...prepared.occurrence, checkedSource: prepared.checkedSource,
    readTuple: prepared.readTuple, physicalBinding: prepared.physicalBinding,
    physicalPolicy: prepared.physicalPolicy};
  if (typeof adapter.ordinaryRecoveryBinding === 'function') {
    const binding = adapter.ordinaryRecoveryBinding(prepared, {...original, occurrence: prepared.occurrence});
    if (!validInstallationBinding(binding)) fail('HeldAcquisitionChanged');
    scope.installationBinding = binding;
  }
  return scope;
};
const bindingFor = (runDefinitionCid: string, scope: SourceScope, acquisition: unknown, sourceEvidenceWire: string) => canonicalJson({
  version: CAPTURE, run_definition_cid: runDefinitionCid, scope,
  acquisition: acquisition ?? null, source_evidence_wire: sourceEvidenceWire});

export function acquiredEffectContinuation({checkpoints, moon, acquired,
  submission, declaredResults, principalId, unitId, resume, restore,
  signal, currentRun = () => true, assertUpdateSelectionCurrent, assertContinuationCurrent}: Options) {
  if (checkpoints === undefined) return undefined;
  if (resume !== undefined && restore !== undefined) fail('ConflictingSourceContinuation');
  const runDefinitionCid = acquired.runDefinition.identity;
  const runId = acquired.control.runDefinitionRunId(acquired.runDefinition);
  // These remain the original nominal constructor inputs, not restored DATA.
  const originalPreparation = Object.freeze({checkedOwner: acquired.prepared,
    requestIdentity: acquired.requestIdentity});
  const states = new Map<number, State>();
  const restorations = new Set<unknown>();
  let pendingTask: number | undefined;
  let continuationVersion: typeof VERSION | typeof BOUND_VERSION = VERSION;
  let captureStartedAt: string | undefined;
  let captureCompletedAt: string | undefined;
  let live = true;
  const originalCurrent = () => {
    signal?.throwIfAborted();
    if (!live || !currentRun()) fail('ClientRunCancellationRequested');
    if (assertUpdateSelectionCurrent === undefined) return;
    const changed: () => never = () => { throw refusedEffectPreparation(Object.assign(
      new Error('InstalledEffectOriginalSelectionChanged'),
      {code: 'InstalledEffectOriginalSelectionChanged'})); };
    if (typeof assertUpdateSelectionCurrent !== 'function') changed();
    const result = assertUpdateSelectionCurrent();
    // The existing installed owner must still be current synchronously. An
    // asynchronous assertion cannot admit a Source read or Model closure.
    if (typeof (result as {then?: unknown} | null | undefined)?.then === 'function') {
      void Promise.resolve(result).catch(() => {});
      changed();
    }
  };
  const current = () => {
    originalCurrent();
    resume?.assertCurrent();
    assertContinuationCurrent?.();
  };
  const currentApproval = (checkpointCid: string | undefined) => {
    if (checkpointCid === undefined) return true;
    try { return checkpoints!.journal.committedApprovalAt(checkpointCid).current === true; }
    catch { return false; }
  };
  const sourceOriginalCurrent = (state: State) => {
    originalCurrent();
    if (assertUpdateSelectionCurrent !== undefined && state.gate !== undefined) {
      if (typeof state.gate.assertCurrent !== 'function') fail('SourceCurrentAuthorityUnavailable');
      state.gate.assertCurrent();
    }
    if (!currentApproval(state.checkpointCid) ||
        state.earlierCheckpointCids?.some(cid=>!currentApproval(cid))) fail('ApprovalExpired');
    originalCurrent();
  };
  const sourceCurrent = (state: State) => {
    current();
    sourceOriginalCurrent(state);
    current();
  };
  const continuationWire = () => {
    current();
    return canonicalJson({version: continuationVersion,
      run_definition_cid: runDefinitionCid, unit_id: unitId,
      submission, pending_task: pendingTask ?? null,
      capture_started_at: captureStartedAt ?? null,
      capture_completed_at: captureCompletedAt ?? null,
      sources: [...states.values()].map(state => ({scope: state.scope,
        ...(state.captureCid === undefined ? {} : {capture_cid: state.captureCid})})),
    });
  };
  const nextJournal = resume === undefined ? undefined : {
    ...checkpoints.journal,
    persistCheckpoint: (checkpoint: Checkpoint) => resume.active
      ? checkpoints.journal.completeResume(resume.claim, {checkpoint})
      : checkpoints.journal.persistCheckpoint(checkpoint),
    submitResolution: (item: ResolutionSubmission) => checkpoints.journal.submitResolution(item),
  };
  const sourceState = (source: Source): PreparedState => {
    const state = states.get(source?.occurrence?.task);
    if (state === undefined || state.source !== source ||
        state.adapter !== source.adapter || state.preparedSource !== source.preparedSource ||
        !same(state.occurrence, source.occurrence) ||
        !same(state.occurrence, source.preparedSource?.occurrence)) fail('HeldAcquisitionChanged');
    return state as PreparedState;
  };
  const ensureGate = async (state: PreparedState) => {
    current();
    if (state.gate !== undefined) return state.gate;
    state.gate = await checkpoints!.computationSourceAuthorization({runId,
      runDefinitionCid, unitId: `${unitId}-source-${state.scope.task}`,
      occurrence: state.scope, declaredResults,
      beforeDefer: async () => {
        sourceCurrent(state);
        pendingTask = state.scope.task;
        for (const prior of states.values()) {
          if (prior.captured !== undefined && prior.captureCid === undefined) {
            await persistSource(prior);
            current();
          }
        }
      },
      continuation: async () => continuationWire(),
      ...(nextJournal === undefined ? {} : {journalPort: nextJournal}),
    });
    sourceCurrent(state);
    return state.gate;
  };
  const approvedAccess = <Access extends SourceAccess>(state: State<Access>): CurrentSourceAccess<Access> => {
    const original = state.base;
    return Object.freeze({...original, assertCurrent() { sourceCurrent(state); },
      authorization: Object.freeze({
      ...original.authorization,
      async authorize(boundary: Parameters<Authorization['authorize']>[0], scope: Scope, options?: AuthorizationOptions): Promise<SourceDecision> {
        const assertCurrent = boundary === 'acquisition'
          ? () => sourceCurrent(state) : () => sourceOriginalCurrent(state);
        assertCurrent();
        const decision = await original.authorization.authorize(boundary, scope, options);
        assertCurrent();
        if (decision.action === 'dispatch' || decision.action === 'deny' ||
            boundary !== 'acquisition' || state.decision?.action !== 'dispatch' ||
            !live || !same(scope, state.scope?.readTuple) ||
            !currentApproval(state.checkpointCid)) return decision;
        const approved = state.decision;
        const enter = state.enter;
        return recordCheckpointApproval(Object.freeze({...approved,
          boundary, tuple: Object.freeze({...scope})}), {
          checkpointCid: state.checkpointCid,
          readTuple: state.scope!.readTuple, checkedSource: state.scope!.checkedSource,
          physicalBinding: state.scope!.physicalBinding,
          occurrence: {stage: state.scope!.stage, input: state.scope!.input, task: state.scope!.task},
          principalId,
          assertCurrent() { sourceCurrent(state); },
          enter,
        });
      },
    })}) as CurrentSourceAccess<Access>;
  };
  async function persistSource(state: State) {
    sourceCurrent(state);
    const {captured, sourceEvidenceWire, startedAt, completedAt} = state.material!;
    const acquisition = captured.acquisition;
    // Provider-specific acquisition diagnostics are not the Source evidence
    // owner. Every installed capture has the original issued evidence wire;
    // bind that exact observation even when no selector diagnostic exists.
    if (typeof sourceEvidenceWire !== 'string' || sourceEvidenceWire.length === 0) {
      fail('SourceCaptureObservationUnavailable');
    }
    const binding = bindingFor(runDefinitionCid, state.scope!, acquisition, sourceEvidenceWire);
    const wholeInput = captured.inputKind === 'whole-input';
    if (captured.inputKind !== undefined && !wholeInput) fail('HeldAcquisitionChanged');
    // Whole custody retains the actual Source/input snapshot. Its kind only
    // selects the typed owner; it cannot manufacture a Query requirement.
    const retained = wholeInput ? state.source!.adapter.retainedCapture(state.source!.preparedSource) : undefined;
    if (wholeInput && retained!.wholeInput !== true) fail('HeldAcquisitionChanged');
    const exported = checked(wholeInput
      ? moon.clientProgramExportWholeSourceCapture(captured.capture.source(), retained!.capacity, binding)
      : moon.clientProgramExportSourceCapture(captured.capture.source(), captured.requirement, binding));
    const originalRead = wholeInput ? undefined : captured.capture.originalRead?.();
    const originalFacts = originalRead === undefined ? undefined :
      checked(moon.clientProgramExportQuerySourceOriginalRead(originalRead, captured.requirement));
    const record = {version: CAPTURE, run_definition_cid: runDefinitionCid,
      scope: state.scope!, acquisition: acquisition ?? null, binding,
      ...(wholeInput ? {input_kind: 'whole-input', source_identity: runtimeField(exported, 0),
        schema_cid: runtimeField(exported, 1), rows_cid: runtimeField(exported, 2), rows: runtimeField(exported, 3)}
        : {requirement_cid: moon.clientProgramSourceCaptureExportRequirement(exported),
          descriptor: moon.clientProgramSourceCaptureExportDescriptor(exported),
          rows: moon.clientProgramSourceCaptureExportRows(exported)}),
      ...(originalFacts === undefined ? {} : {original_input: {version: ORIGINAL_INPUT,
        schema_cid: runtimeField(originalFacts, 0), rows_cid: runtimeField(originalFacts, 1),
        rows: runtimeField(originalFacts, 2)} as OriginalInput}),
      source_evidence_wire: sourceEvidenceWire,
      ...(state.checkpointCid === undefined ? {} : {checkpoint_cid: state.checkpointCid}),
      ...(state.earlierCheckpointCids === undefined ? {} : {earlier_checkpoint_cids: state.earlierCheckpointCids}),
      capture_started_at: startedAt, capture_completed_at: completedAt};
    const wire = canonicalJson(record);
    if (Buffer.byteLength(wire) > 2_000_000) fail('SourceCaptureRetentionLimitExceeded');
    state.captureCid = await checkpoints!.retainComputationSource(runId, runDefinitionCid, wire);
    sourceCurrent(state);
    state.record = record;
  }
  return Object.freeze({
    restoringModel: restore !== undefined,
    nextJournal,
    accessFor<Access extends SourceAccess>(base: Access, occurrence: Occurrence) {
      current();
      if (states.has(occurrence.task)) fail('DuplicateSourceContinuationOccurrence');
      const state: State<Access> = {base, occurrence: JSON.parse(canonicalJson(occurrence))};
      state.access = approvedAccess(state);
      states.set(occurrence.task, state);
      return state.access;
    },
    async prepared(sources: readonly Source[]) {
      current();
      if (!Array.isArray(sources) || sources.length !== states.size) fail('HeldAcquisitionChanged');
      const seen = new Set<State>();
      for (const source of sources as readonly Source[]) {
        const state = states.get(source?.occurrence?.task);
        if (state === undefined || seen.has(state) ||
            !same(state.occurrence, source.occurrence) ||
            !same(state.occurrence, source.preparedSource?.occurrence)) fail('HeldAcquisitionChanged');
        seen.add(state);
        state.scope = JSON.parse(canonicalJson(sourceScope(source, originalPreparation)));
        state.source = source;
        state.adapter = source.adapter;
        state.preparedSource = source.preparedSource;
      }
      // A newly retained installed binding has a distinct closed form. Never
      // promote an old binding-free scope using the current installation.
      continuationVersion = [...states.values()].some(state =>
        state.scope!.installationBinding !== undefined) ? BOUND_VERSION : VERSION;
      const restoring = resume ?? restore;
      if (restoring === undefined) return;
      const saved = restoring.continuation;
      if (saved?.version !== continuationVersion || saved.run_definition_cid !== runDefinitionCid ||
          saved.unit_id !== unitId || !same(saved.submission, submission) ||
          !Array.isArray(saved.sources) || saved.sources.length !== states.size ||
          (restore === undefined ? !Number.isSafeInteger(saved.pending_task)
            : saved.pending_task !== null)) fail('HeldAcquisitionChanged');
      const savedSources = new Set<State>();
      for (const item of saved.sources as SavedContinuation['sources']) {
        const state = states.get(item.scope?.task);
        if (state === undefined || savedSources.has(state) ||
            !same(state.scope, item.scope)) fail('HeldAcquisitionChanged');
        savedSources.add(state);
        state.captureCid = item.capture_cid;
      }
      captureStartedAt = saved.capture_started_at ?? undefined;
      captureCompletedAt = saved.capture_completed_at ?? undefined;
      // The actual checked source-free Program never issued a Source capture
      // ledger. Its validated empty closure is not a missing acquired Source.
      // Model/Effect evidence and their original cleanup remain independent.
      if (restore !== undefined && states.size === 0 &&
          moon.clientProgramEffectAcquisitionCount(acquired.prepared) === 0) return;
      const references = await checkpoints.computationSourceReferences(restoring.view);
      current();
      if (references.length > states.size) fail('DuplicateRetainedSourceCapture');
      for (const captureCid of references) {
        const bytes = await checkpoints.readComputationSource(restoring.view, captureCid, 2_000_000);
        current();
        const record = JSON.parse(bytes.toString('utf8')) as CaptureRecord;
        const state = states.get(record.scope?.task);
        if (record.version !== CAPTURE || record.run_definition_cid !== runDefinitionCid ||
            state === undefined || !same(record.scope, state.scope) ||
            state.record !== undefined ||
            state.captureCid !== undefined && state.captureCid !== captureCid ||
            !currentApproval(record.checkpoint_cid) ||
            record.earlier_checkpoint_cids !== undefined && (!Array.isArray(record.earlier_checkpoint_cids) ||
              record.earlier_checkpoint_cids.some(cid=>typeof cid!=='string'||!currentApproval(cid)))) fail('HeldAcquisitionChanged');
        state.earlierCheckpointCids = record.earlier_checkpoint_cids;
        state.captureCid = captureCid;
        state.record = record;
        state.checkpointCid = record.checkpoint_cid;
        if (captureStartedAt === undefined || record.capture_started_at < captureStartedAt) {
          captureStartedAt = record.capture_started_at;
        }
        if (captureCompletedAt === undefined || record.capture_completed_at > captureCompletedAt) {
          captureCompletedAt = record.capture_completed_at;
        }
      }
      for (const state of states.values()) {
        if ((restore !== undefined || state.captureCid !== undefined) && state.record === undefined) {
          fail('SourceCaptureCustodyUnavailable');
        }
      }
    },
    async beforeRead(source: Source) {
      current();
      const state = sourceState(source);
      const gate = await ensureGate(state);
      sourceCurrent(state);
      if (state.record !== undefined) {
        // Source authority is revalidated before consuming retained data,
        // without opening the upstream provider or reissuing its evidence.
        const decision = await state.base.authorization.authorize('acquisition', state.scope.readTuple);
        sourceCurrent(state);
        if (decision.action !== 'dispatch' &&
            (decision.action === 'deny' || state.checkpointCid === undefined ||
              !currentApproval(state.checkpointCid))) throw new ExecutionAuthorizationError(decision);
        return {retained: state.record};
      }
      if (restore !== undefined) fail('SourceCaptureCustodyUnavailable');
      const resumed = resume !== undefined &&
        source.occurrence.task === resume.continuation.pending_task;
      const decision = resumed ? await gate.resume({resumption: {claim: {
        checkpointCid: resume.view.checkpointCid, claim: resume.claim}}})
        : await gate.authorize();
      // A committed successor Checkpoint has consumed the predecessor claim.
      // It transfers no Source dispatch permission, but originals must still
      // be current before returning that journal-owned waiting observation.
      if (decision.action === 'waiting') {
        sourceOriginalCurrent(state);
        return {waiting: decision.checkpoint};
      }
      sourceCurrent(state);
      if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
      state.decision = decision;
      state.checkpointCid = resumed ? resume.view.checkpointCid : undefined;
      // Every borrower uses this same entry closure. A successful original
      // admission is consumed once; later uses still recheck its owners.
      let entered = false;
      state.enter = () => {
        sourceCurrent(state);
        if (!entered) {
          decision.admission?.enter();
          entered = true;
        }
      };
      return {enter: state.enter};
    },
    restore(source: Source, record: CaptureRecord, ledger: unknown) {
      const state = sourceState(source);
      sourceCurrent(state);
      const {requirement, capacity, referenceIssuer, wholeInput = false} = source.adapter.retainedCapture(source.preparedSource);
      const binding = bindingFor(runDefinitionCid, state.scope, record.acquisition,
        record.source_evidence_wire);
      // The current installed owner selects the variant, before any saved
      // DATA reaches Core. Core then checks its exact Source and row identity.
      if (wholeInput !== (record.input_kind === 'whole-input') ||
          record.input_kind !== undefined && record.input_kind !== 'whole-input' ||
          wholeInput && (['requirement_cid', 'descriptor', 'original_input'].some(key => Object.hasOwn(record, key)) ||
            !Array.isArray(record.source_identity) || !record.source_identity.every(value => typeof value === 'string') ||
            typeof record.schema_cid !== 'string' || typeof record.rows_cid !== 'string' ||
            !Array.isArray(record.rows) || !record.rows.every(value => typeof value === 'string'))) fail('HeldAcquisitionChanged');
      const input = record.original_input;
      if (input !== undefined && (input === null || Array.isArray(input) ||
          Object.keys(input).sort().join(',') !== 'rows,rows_cid,schema_cid,version' ||
          input.version !== ORIGINAL_INPUT || typeof input.schema_cid !== 'string' ||
          typeof input.rows_cid !== 'string' || !Array.isArray(input.rows) ||
          !input.rows.every(row => typeof row === 'string'))) fail('HeldAcquisitionChanged');
      const custodyAvailable = () => {
        try { sourceCurrent(state); return true; }
        catch { return false; }
      };
      const owner = checked(wholeInput
        ? moon.clientProgramRestoreWholeSourceCapture(capacity, binding, record.binding,
          record.source_identity as readonly string[], record.schema_cid as string, record.rows_cid as string, record.rows as readonly string[],
          ledger, custodyAvailable, referenceIssuer)
        : moon.clientProgramRestoreSourceCapture(requirement,
        record.requirement_cid!, binding, record.binding, record.descriptor!,
        record.rows as readonly string[], ledger, capacity, custodyAvailable, referenceIssuer,
        input === undefined ? undefined : runtimeTriple(input!.schema_cid, input!.rows_cid, input!.rows)));
      restorations.add(owner);
      const capturedSource = moon.clientProgramSourceCaptureSource(owner);
      if (capturedSource === undefined) fail('SourceCaptureCustodyUnavailable');
      const pure = acquired.kind === 'infer';
      if (pure && !wholeInput && moon.clientProgramCapturedTaskSourceMatches(acquired.prepared,
          capturedSource, source.occurrence.task) !== true) fail('HeldAcquisitionChanged');
      const identity = checked(wholeInput
        ? (pure ? moon.clientProgramIdentifyWholeCapturedSourceRelation
          : moon.clientProgramIdentifyWholeCapturedEffectSourceRelation)(capturedSource, capacity)
        : (pure ? moon.clientProgramIdentifyQueryCapturedSourceRelation
          : moon.clientProgramIdentifyQueryCapturedEffectSourceRelation)(capturedSource, requirement));
      const logicalInput = checked(wholeInput
        ? (pure ? moon.clientProgramIssueWholeSourceInputLogical
          : moon.clientProgramIssueEffectWholeSourceInputLogical)(
          acquired.prepared, capturedSource, identity, capacity)
        : (pure ? moon.clientProgramIssueCapturedTaskSourceLogical
          : moon.clientProgramEffectIssueCapturedSourceLogicalAt)(
          acquired.prepared, capturedSource, identity, requirement, source.occurrence.task));
      const close = async () => {
        if (!moon.clientProgramCloseSourceCapture(owner)) fail('SourceCaptureCleanupPending');
        restorations.delete(owner);
      };
      const captured: RestoredCapture = Object.freeze({identity, logicalInput,
        ...(wholeInput ? {inputKind: 'whole-input', wholeCapacity: capacity} : {requirement}), capturedSource,
        checkedSource: state.scope.checkedSource, occurrence: source.occurrence,
        acquisition: record.acquisition,
        capture: Object.freeze({source: () => moon.clientProgramSourceCaptureSource(owner),
          originalRead: () => moon.clientProgramSourceCaptureOriginalRead(owner),
          ...(wholeInput ? {originalCapturedInput() {
            if (this !== captured.capture) fail('SourceCaptureCustodyUnavailable');
            return checked(moon.clientProgramRestoredWholeSourceCaptureInput(owner));
          }} : {}),
          retainTask: (dag: unknown, task: number) => checked(wholeInput
            ? moon.clientProgramSourceCaptureRetainInput(owner, dag, task)
            : moon.clientProgramSourceCaptureRetainTask(owner, dag, task)),
          close}), close,
      });
      state.captured = captured;
      return {captured, sourceEvidenceWire: record.source_evidence_wire};
    },
    async captured(source: Source, captured: Capture, sourceEvidenceWire: string, startedAt: string,
      completedAt: string, originalApproval?: SourceDecision) {
      const state = sourceState(source);
      sourceCurrent(state);
      if (originalApproval !== undefined) {
        const facts = checkpointApprovalFacts(originalApproval) as ApprovalFacts | undefined;
        const matches = (left: unknown, right: unknown) => left === undefined || right === undefined
          ? left === right : same(left, right);
        // Singular read approvals may omit an installation fact. Keep the
        // actual Source scope binding; a supplied approval fact must match it.
        if (originalApproval.action !== 'dispatch' || originalApproval.boundary !== 'acquisition' ||
            facts === undefined || typeof facts.checkpointCid !== 'string' ||
            facts.principalId !== principalId || !matches(facts.readTuple, state.scope.readTuple) ||
            !matches(facts.checkedSource, state.scope.checkedSource) ||
            !matches(facts.physicalBinding, state.scope.physicalBinding) ||
            facts.installationBinding !== undefined && !matches(facts.installationBinding, state.scope.installationBinding) ||
            facts.occurrence !== undefined && ['stage','input','task'].some(name=>facts.occurrence![name as keyof Occurrence]!==source.occurrence[name as keyof Occurrence]) ||
            facts.earlierCheckpointCids !== undefined && (!Array.isArray(facts.earlierCheckpointCids) ||
              facts.earlierCheckpointCids.some(cid=>typeof cid!=='string'))) fail('HeldAcquisitionChanged');
        // Preserve the original Checkpoint issuer's exact read approval. A
        // copied decision or an arbitrary approved CID cannot enter this path.
        state.checkpointCid = facts.checkpointCid;
        state.earlierCheckpointCids = facts.earlierCheckpointCids;
        facts.assertCurrent?.();
        sourceCurrent(state);
      }
      state.captured = captured;
      state.material = {captured, sourceEvidenceWire, startedAt, completedAt};
      captureStartedAt ??= startedAt;
      captureCompletedAt = completedAt;
      if (resume?.active) {
        await persistSource(state);
        current();
      }
    },
    async retainAll() {
      current();
      for (const state of states.values()) {
        if (state.captured === undefined) fail('SourceCaptureCustodyUnavailable');
        if (state.captureCid === undefined) await persistSource(state);
        sourceCurrent(state);
        if (state.record === undefined) fail('SourceCaptureCustodyUnavailable');
      }
      // A Model boundary is after every source capture, not a pending Source
      // read. Its complete closure can only restore those exact originals.
      pendingTask = undefined;
      return JSON.parse(continuationWire()) as SavedContinuation;
    },
    times: () => ({captureStartedAt, captureCompletedAt}),
    async close() {
      for (const owner of restorations) {
        if (!moon.clientProgramCloseSourceCapture(owner)) fail('SourceCaptureCleanupPending');
        restorations.delete(owner);
      }
      live = false;
      for (const state of states.values()) state.gate?.close();
      await checkpoints.retireComputationSources(runId);
    },
  });
}
