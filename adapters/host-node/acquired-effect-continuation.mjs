// Host connection of Source acquisition to the existing Run-unit Checkpoint
// and encrypted continuation custody. This owns no scheduler or retry loop.
import {canonicalJson} from '../../packages/sdk/checkpoints.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {recordCheckpointApproval} from '../host-common/checkpoint-approval.mjs';
import {ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {capturedDuckDBPendingCapacity, capturedDuckDBRequirement} from './captured-duckdb-source.mjs';

const VERSION = 'actql-acquired-effect-continuation/0.1';
const CAPTURE = 'actql-host-source-capture/0.1';
const fail = code => { throw Object.assign(new Error(code), {code}); };
const same = (left, right) => canonicalJson(left) === canonicalJson(right);
const sourceScope = prepared => ({...prepared.occurrence,
  checkedSource: prepared.checkedSource, readTuple: prepared.readTuple,
  physicalBinding: prepared.physicalBinding, physicalPolicy: prepared.physicalPolicy});
const bindingFor = (runDefinitionCid, scope, acquisition) => canonicalJson({
  version: CAPTURE, run_definition_cid: runDefinitionCid, scope, acquisition});

export function acquiredEffectContinuation({checkpoints, moon, acquired,
  submission, declaredResults, principalId, unitId, resume,
  signal, currentRun = () => true}) {
  if (checkpoints === undefined) return undefined;
  const runDefinitionCid = acquired.runDefinition.identity;
  const runId = acquired.control.runDefinitionRunId(acquired.runDefinition);
  const states = new Map();
  const restorations = new Set();
  let pendingTask;
  let captureStartedAt;
  let captureCompletedAt;
  let live = true;
  const currentClaim = () => {
    try { resume?.assertCurrent(); return true; }
    catch { return false; }
  };
  const currentApproval = checkpointCid => {
    if (checkpointCid === undefined) return true;
    try { return checkpoints.journal.committedApprovalAt(checkpointCid).current === true; }
    catch { return false; }
  };
  const continuationWire = () => canonicalJson({version: VERSION,
    run_definition_cid: runDefinitionCid, unit_id: unitId,
    submission, pending_task: pendingTask,
    capture_started_at: captureStartedAt ?? null,
    capture_completed_at: captureCompletedAt ?? null,
    sources: [...states.values()].map(state => ({scope: state.scope,
      ...(state.captureCid === undefined ? {} : {capture_cid: state.captureCid})})),
  });
  const nextJournal = resume === undefined ? undefined : {
    ...checkpoints.journal,
    persistCheckpoint: checkpoint => resume.active
      ? checkpoints.journal.completeResume(resume.claim, {checkpoint})
      : checkpoints.journal.persistCheckpoint(checkpoint),
    submitResolution: item => checkpoints.journal.submitResolution(item),
  };
  const ensureGate = async state => {
    if (state.gate !== undefined) return state.gate;
    state.gate = await checkpoints.computationSourceAuthorization({runId,
      runDefinitionCid, unitId: `${unitId}-source-${state.scope.task}`,
      occurrence: state.scope, declaredResults,
      beforeDefer: async () => {
        pendingTask = state.scope.task;
        for (const prior of states.values()) {
          if (prior.captured !== undefined && prior.captureCid === undefined) {
            await persistSource(prior);
          }
        }
      },
      continuation: async () => continuationWire(),
      ...(nextJournal === undefined ? {} : {journalPort: nextJournal}),
    });
    return state.gate;
  };
  const approvedAccess = state => {
    const original = state.base;
    return Object.freeze({...original, authorization: Object.freeze({
      ...original.authorization,
      async authorize(boundary, scope, options) {
        const current = await original.authorization.authorize(boundary, scope, options);
        signal?.throwIfAborted();
        if (!currentRun()) fail('ClientRunCancellationRequested');
        if (boundary === 'acquisition') resume?.assertCurrent();
        if (current.action === 'dispatch' || current.action === 'deny' ||
            boundary !== 'acquisition' || state.decision?.action !== 'dispatch' ||
            !live || !same(scope, state.scope?.readTuple) ||
            !currentApproval(state.checkpointCid)) return current;
        return recordCheckpointApproval(Object.freeze({...state.decision,
          boundary, tuple: Object.freeze({...scope})}), {
          checkpointCid: state.checkpointCid,
          readTuple: state.scope.readTuple, checkedSource: state.scope.checkedSource,
          physicalBinding: state.scope.physicalBinding,
          occurrence: {stage: state.scope.stage, input: state.scope.input, task: state.scope.task},
          principalId,
        });
      },
    })});
  };
  async function persistSource(state) {
    const {captured, sourceEvidenceWire, startedAt, completedAt} = state.material;
    const acquisition = captured.acquisition;
    if (acquisition?.observation === undefined) fail('SourceCaptureObservationUnavailable');
    const binding = bindingFor(runDefinitionCid, state.scope, acquisition);
    const exported = checked(moon.clientProgramExportSourceCapture(captured.capture.source(),
      captured.requirement, binding));
    const record = {version: CAPTURE, run_definition_cid: runDefinitionCid,
      scope: state.scope, acquisition, binding,
      requirement_cid: moon.clientProgramSourceCaptureExportRequirement(exported),
      descriptor: moon.clientProgramSourceCaptureExportDescriptor(exported),
      rows: moon.clientProgramSourceCaptureExportRows(exported),
      source_evidence_wire: sourceEvidenceWire,
      ...(state.checkpointCid === undefined ? {} : {checkpoint_cid: state.checkpointCid}),
      capture_started_at: startedAt, capture_completed_at: completedAt};
    const wire = canonicalJson(record);
    if (Buffer.byteLength(wire) > 2_000_000) fail('SourceCaptureRetentionLimitExceeded');
    state.captureCid = await checkpoints.retainComputationSource(runId, runDefinitionCid, wire);
    state.record = record;
  }
  return Object.freeze({
    nextJournal,
    accessFor(base, occurrence) {
      if (states.has(occurrence.task)) fail('DuplicateSourceContinuationOccurrence');
      const state = {base};
      state.access = approvedAccess(state);
      states.set(occurrence.task, state);
      return state.access;
    },
    async prepared(sources) {
      for (const source of sources) {
        const state = states.get(source.occurrence.task);
        state.scope = JSON.parse(canonicalJson(sourceScope(source.preparedSource)));
        state.source = source;
      }
      if (resume === undefined) return;
      const saved = resume.continuation;
      if (saved?.version !== VERSION || saved.run_definition_cid !== runDefinitionCid ||
          saved.unit_id !== unitId || !same(saved.submission, submission) ||
          !Array.isArray(saved.sources) || saved.sources.length !== states.size ||
          !Number.isSafeInteger(saved.pending_task)) fail('HeldAcquisitionChanged');
      for (const item of saved.sources) {
        const state = states.get(item.scope?.task);
        if (state === undefined || !same(state.scope, item.scope)) fail('HeldAcquisitionChanged');
        state.captureCid = item.capture_cid;
      }
      captureStartedAt = saved.capture_started_at ?? undefined;
      captureCompletedAt = saved.capture_completed_at ?? undefined;
      const references = await checkpoints.computationSourceReferences(resume.view);
      if (references.length > states.size) fail('DuplicateRetainedSourceCapture');
      for (const captureCid of references) {
        const bytes = await checkpoints.readComputationSource(resume.view, captureCid, 2_000_000);
        const record = JSON.parse(bytes.toString('utf8'));
        const state = states.get(record.scope?.task);
        if (record.version !== CAPTURE || record.run_definition_cid !== runDefinitionCid ||
            state === undefined || !same(record.scope, state.scope) ||
            state.record !== undefined ||
            state.captureCid !== undefined && state.captureCid !== captureCid ||
            !currentApproval(record.checkpoint_cid)) fail('HeldAcquisitionChanged');
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
        if (state.captureCid !== undefined && state.record === undefined) {
          fail('SourceCaptureCustodyUnavailable');
        }
      }
    },
    async beforeRead(source) {
      signal?.throwIfAborted();
      if (!currentRun()) fail('ClientRunCancellationRequested');
      resume?.assertCurrent();
      const state = states.get(source.occurrence.task);
      const gate = await ensureGate(state);
      if (state.record !== undefined) {
        // Source authority is revalidated before consuming retained data,
        // without opening the upstream provider or reissuing its evidence.
        const current = await state.base.authorization.authorize('acquisition', state.scope.readTuple);
        signal?.throwIfAborted();
        if (!currentRun()) fail('ClientRunCancellationRequested');
        resume?.assertCurrent();
        if (current.action !== 'dispatch' &&
            (current.action === 'deny' || state.checkpointCid === undefined ||
              !currentApproval(state.checkpointCid))) throw new ExecutionAuthorizationError(current);
        return {retained: state.record};
      }
      const resumed = resume !== undefined &&
        source.occurrence.task === resume.continuation.pending_task;
      const decision = resumed ? await gate.resume({resumption: {claim: {
        checkpointCid: resume.view.checkpointCid, claim: resume.claim}}})
        : await gate.authorize();
      if (decision.action === 'waiting') return {waiting: decision.checkpoint};
      if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
      state.decision = decision;
      state.checkpointCid = resumed ? resume.view.checkpointCid : undefined;
      return {enter: () => {
        signal?.throwIfAborted();
        if (!currentRun()) fail('ClientRunCancellationRequested');
        resume?.assertCurrent();
        decision.admission?.enter();
      }};
    },
    restore(source, record, ledger) {
      const state = states.get(source.occurrence.task);
      const requirement = capturedDuckDBRequirement(source.preparedSource);
      const binding = bindingFor(runDefinitionCid, state.scope, record.acquisition);
      const owner = checked(moon.clientProgramRestoreSourceCapture(requirement,
        record.requirement_cid, binding, record.binding, record.descriptor,
        record.rows, ledger, capturedDuckDBPendingCapacity(source.preparedSource),
        () => live && !signal?.aborted && currentRun() && currentClaim() &&
          currentApproval(state.checkpointCid)));
      restorations.add(owner);
      const capturedSource = moon.clientProgramSourceCaptureSource(owner);
      if (capturedSource === undefined) fail('SourceCaptureCustodyUnavailable');
      const identity = checked(moon.clientProgramIdentifyCapturedEffectSourceRelation(capturedSource));
      const logicalInput = checked(moon.clientProgramEffectIssueCapturedSourceLogicalAt(
        acquired.prepared, capturedSource, identity, requirement, source.occurrence.task));
      const close = async () => {
        if (!moon.clientProgramCloseSourceCapture(owner)) fail('SourceCaptureCleanupPending');
        restorations.delete(owner);
      };
      const captured = Object.freeze({identity, logicalInput, requirement, capturedSource,
        checkedSource: state.scope.checkedSource, occurrence: source.occurrence,
        acquisition: record.acquisition,
        capture: Object.freeze({source: () => moon.clientProgramSourceCaptureSource(owner),
          retainTask: (dag, task) => checked(moon.clientProgramSourceCaptureRetainTask(owner, dag, task)),
          close}), close,
      });
      state.captured = captured;
      return {captured, sourceEvidenceWire: record.source_evidence_wire};
    },
    async captured(source, captured, sourceEvidenceWire, startedAt, completedAt) {
      const state = states.get(source.occurrence.task);
      state.captured = captured;
      state.material = {captured, sourceEvidenceWire, startedAt, completedAt};
      captureStartedAt ??= startedAt;
      captureCompletedAt = completedAt;
      if (resume?.active) {
        await persistSource(state);
      }
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
