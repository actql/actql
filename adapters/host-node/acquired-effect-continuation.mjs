// Host connection of Source acquisition to the existing Run-unit Checkpoint
// and encrypted continuation custody. This owns no scheduler or retry loop.
import {runtimeField, runtimeTriple} from '../host-common/compiler-binding.generated.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {recordCheckpointApproval, checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {validInstallationBinding} from './ordinary-source-binding.mjs';

const VERSION = 'actql-acquired-effect-continuation/0.1';
const BOUND_VERSION = 'actql-acquired-effect-bound-continuation/0.1';
const CAPTURE = 'actql-host-source-capture/0.1';
const ORIGINAL_INPUT = 'actql-host-source-original-input/0.1';
const fail = code => { throw Object.assign(new Error(code), {code}); };
const same = (left, right) => canonicalJson(left) === canonicalJson(right);
const sourceScope = source => {
  const {preparedSource: prepared, adapter} = source;
  const scope = {...prepared.occurrence, checkedSource: prepared.checkedSource,
    readTuple: prepared.readTuple, physicalBinding: prepared.physicalBinding,
    physicalPolicy: prepared.physicalPolicy};
  if (typeof adapter.ordinaryRecoveryBinding === 'function') {
    const binding = adapter.ordinaryRecoveryBinding(prepared);
    if (!validInstallationBinding(binding)) fail('HeldAcquisitionChanged');
    scope.installationBinding = binding;
  }
  return scope;
};
const bindingFor = (runDefinitionCid, scope, acquisition, sourceEvidenceWire) => canonicalJson({
  version: CAPTURE, run_definition_cid: runDefinitionCid, scope,
  acquisition: acquisition ?? null, source_evidence_wire: sourceEvidenceWire});

export function acquiredEffectContinuation({checkpoints, moon, acquired,
  submission, declaredResults, principalId, unitId, resume, restore,
  signal, currentRun = () => true, assertUpdateSelectionCurrent, assertContinuationCurrent}) {
  if (checkpoints === undefined) return undefined;
  if (resume !== undefined && restore !== undefined) fail('ConflictingSourceContinuation');
  const runDefinitionCid = acquired.runDefinition.identity;
  const runId = acquired.control.runDefinitionRunId(acquired.runDefinition);
  const states = new Map();
  const restorations = new Set();
  let pendingTask;
  let continuationVersion = VERSION;
  let captureStartedAt;
  let captureCompletedAt;
  let live = true;
  const originalCurrent = () => {
    signal?.throwIfAborted();
    if (!live || !currentRun()) fail('ClientRunCancellationRequested');
    if (assertUpdateSelectionCurrent === undefined) return;
    const changed = () => { throw refusedEffectPreparation(Object.assign(
      new Error('InstalledEffectOriginalSelectionChanged'),
      {code: 'InstalledEffectOriginalSelectionChanged'})); };
    if (typeof assertUpdateSelectionCurrent !== 'function') changed();
    const result = assertUpdateSelectionCurrent();
    // The existing installed owner must still be current synchronously. An
    // asynchronous assertion cannot admit a Source read or Model closure.
    if (typeof result?.then === 'function') {
      void Promise.resolve(result).catch(() => {});
      changed();
    }
  };
  const current = () => {
    originalCurrent();
    resume?.assertCurrent();
    assertContinuationCurrent?.();
  };
  const currentApproval = checkpointCid => {
    if (checkpointCid === undefined) return true;
    try { return checkpoints.journal.committedApprovalAt(checkpointCid).current === true; }
    catch { return false; }
  };
  const sourceOriginalCurrent = state => {
    originalCurrent();
    if (assertUpdateSelectionCurrent !== undefined && state.gate !== undefined) {
      if (typeof state.gate.assertCurrent !== 'function') fail('SourceCurrentAuthorityUnavailable');
      state.gate.assertCurrent();
    }
    if (!currentApproval(state.checkpointCid) ||
        state.earlierCheckpointCids?.some(cid=>!currentApproval(cid))) fail('ApprovalExpired');
    originalCurrent();
  };
  const sourceCurrent = state => {
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
    persistCheckpoint: checkpoint => resume.active
      ? checkpoints.journal.completeResume(resume.claim, {checkpoint})
      : checkpoints.journal.persistCheckpoint(checkpoint),
    submitResolution: item => checkpoints.journal.submitResolution(item),
  };
  const ensureGate = async state => {
    current();
    if (state.gate !== undefined) return state.gate;
    state.gate = await checkpoints.computationSourceAuthorization({runId,
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
  const approvedAccess = state => {
    const original = state.base;
    return Object.freeze({...original, assertCurrent() { sourceCurrent(state); },
      authorization: Object.freeze({
      ...original.authorization,
      async authorize(boundary, scope, options) {
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
          readTuple: state.scope.readTuple, checkedSource: state.scope.checkedSource,
          physicalBinding: state.scope.physicalBinding,
          occurrence: {stage: state.scope.stage, input: state.scope.input, task: state.scope.task},
          principalId,
          assertCurrent() { sourceCurrent(state); },
          enter,
        });
      },
    })});
  };
  async function persistSource(state) {
    sourceCurrent(state);
    const {captured, sourceEvidenceWire, startedAt, completedAt} = state.material;
    const acquisition = captured.acquisition;
    // Provider-specific acquisition diagnostics are not the Source evidence
    // owner. Every installed capture has the original issued evidence wire;
    // bind that exact observation even when no selector diagnostic exists.
    if (typeof sourceEvidenceWire !== 'string' || sourceEvidenceWire.length === 0) {
      fail('SourceCaptureObservationUnavailable');
    }
    const binding = bindingFor(runDefinitionCid, state.scope, acquisition, sourceEvidenceWire);
    const exported = checked(moon.clientProgramExportSourceCapture(captured.capture.source(),
      captured.requirement, binding));
    const originalRead = captured.capture.originalRead?.();
    const originalFacts = originalRead === undefined ? undefined :
      checked(moon.clientProgramExportSourceOriginalRead(originalRead));
    const record = {version: CAPTURE, run_definition_cid: runDefinitionCid,
      scope: state.scope, acquisition: acquisition ?? null, binding,
      requirement_cid: moon.clientProgramSourceCaptureExportRequirement(exported),
      descriptor: moon.clientProgramSourceCaptureExportDescriptor(exported),
      rows: moon.clientProgramSourceCaptureExportRows(exported),
      ...(originalFacts === undefined ? {} : {original_input: {version: ORIGINAL_INPUT,
        schema_cid: runtimeField(originalFacts, 0), rows_cid: runtimeField(originalFacts, 1), rows: runtimeField(originalFacts, 2)}}),
      source_evidence_wire: sourceEvidenceWire,
      ...(state.checkpointCid === undefined ? {} : {checkpoint_cid: state.checkpointCid}),
      ...(state.earlierCheckpointCids === undefined ? {} : {earlier_checkpoint_cids: state.earlierCheckpointCids}),
      capture_started_at: startedAt, capture_completed_at: completedAt};
    const wire = canonicalJson(record);
    if (Buffer.byteLength(wire) > 2_000_000) fail('SourceCaptureRetentionLimitExceeded');
    state.captureCid = await checkpoints.retainComputationSource(runId, runDefinitionCid, wire);
    sourceCurrent(state);
    state.record = record;
  }
  return Object.freeze({
    restoringModel: restore !== undefined,
    nextJournal,
    accessFor(base, occurrence) {
      current();
      if (states.has(occurrence.task)) fail('DuplicateSourceContinuationOccurrence');
      const state = {base};
      state.access = approvedAccess(state);
      states.set(occurrence.task, state);
      return state.access;
    },
    async prepared(sources) {
      current();
      for (const source of sources) {
        const state = states.get(source.occurrence.task);
        state.scope = JSON.parse(canonicalJson(sourceScope(source)));
        state.source = source;
      }
      // A newly retained installed binding has a distinct closed form. Never
      // promote an old binding-free scope using the current installation.
      continuationVersion = [...states.values()].some(state =>
        state.scope.installationBinding !== undefined) ? BOUND_VERSION : VERSION;
      const restoring = resume ?? restore;
      if (restoring === undefined) return;
      const saved = restoring.continuation;
      if (saved?.version !== continuationVersion || saved.run_definition_cid !== runDefinitionCid ||
          saved.unit_id !== unitId || !same(saved.submission, submission) ||
          !Array.isArray(saved.sources) || saved.sources.length !== states.size ||
          (restore === undefined ? !Number.isSafeInteger(saved.pending_task)
            : saved.pending_task !== null)) fail('HeldAcquisitionChanged');
      for (const item of saved.sources) {
        const state = states.get(item.scope?.task);
        if (state === undefined || !same(state.scope, item.scope)) fail('HeldAcquisitionChanged');
        state.captureCid = item.capture_cid;
      }
      captureStartedAt = saved.capture_started_at ?? undefined;
      captureCompletedAt = saved.capture_completed_at ?? undefined;
      const references = await checkpoints.computationSourceReferences(restoring.view);
      current();
      if (references.length > states.size) fail('DuplicateRetainedSourceCapture');
      for (const captureCid of references) {
        const bytes = await checkpoints.readComputationSource(restoring.view, captureCid, 2_000_000);
        current();
        const record = JSON.parse(bytes.toString('utf8'));
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
    async beforeRead(source) {
      current();
      const state = states.get(source.occurrence.task);
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
    restore(source, record, ledger) {
      const state = states.get(source.occurrence.task);
      sourceCurrent(state);
      const {requirement, capacity, referenceIssuer} = source.adapter.retainedCapture(source.preparedSource);
      const binding = bindingFor(runDefinitionCid, state.scope, record.acquisition,
        record.source_evidence_wire);
      const input = record.original_input;
      if (input !== undefined && (input === null || Array.isArray(input) ||
          Object.keys(input).sort().join(',') !== 'rows,rows_cid,schema_cid,version' ||
          input.version !== ORIGINAL_INPUT || typeof input.schema_cid !== 'string' ||
          typeof input.rows_cid !== 'string' || !Array.isArray(input.rows) ||
          !input.rows.every(row => typeof row === 'string'))) fail('HeldAcquisitionChanged');
      const owner = checked(moon.clientProgramRestoreSourceCapture(requirement,
        record.requirement_cid, binding, record.binding, record.descriptor,
        record.rows, ledger, capacity,
        () => {
          try { sourceCurrent(state); return true; }
          catch { return false; }
        }, referenceIssuer,
        input === undefined ? undefined : runtimeTriple(input.schema_cid, input.rows_cid, input.rows)));
      restorations.add(owner);
      const capturedSource = moon.clientProgramSourceCaptureSource(owner);
      if (capturedSource === undefined) fail('SourceCaptureCustodyUnavailable');
      const pure = acquired.kind === 'infer';
      if (pure && moon.clientProgramCapturedTaskSourceMatches(acquired.prepared,
          capturedSource, source.occurrence.task) !== true) fail('HeldAcquisitionChanged');
      const identity = checked((pure ? moon.clientProgramIdentifyCapturedSourceRelation
        : moon.clientProgramIdentifyCapturedEffectSourceRelation)(capturedSource));
      const logicalInput = checked((pure ? moon.clientProgramIssueCapturedTaskSourceLogical
        : moon.clientProgramEffectIssueCapturedSourceLogicalAt)(
        acquired.prepared, capturedSource, identity, requirement, source.occurrence.task));
      const close = async () => {
        if (!moon.clientProgramCloseSourceCapture(owner)) fail('SourceCaptureCleanupPending');
        restorations.delete(owner);
      };
      const captured = Object.freeze({identity, logicalInput, requirement, capturedSource,
        checkedSource: state.scope.checkedSource, occurrence: source.occurrence,
        acquisition: record.acquisition,
        capture: Object.freeze({source: () => moon.clientProgramSourceCaptureSource(owner),
          originalRead: () => moon.clientProgramSourceCaptureOriginalRead(owner),
          retainTask: (dag, task) => checked(moon.clientProgramSourceCaptureRetainTask(owner, dag, task)),
          close}), close,
      });
      state.captured = captured;
      return {captured, sourceEvidenceWire: record.source_evidence_wire};
    },
    async captured(source, captured, sourceEvidenceWire, startedAt, completedAt, originalApproval) {
      const state = states.get(source.occurrence.task);
      sourceCurrent(state);
      if (originalApproval !== undefined) {
        const facts = checkpointApprovalFacts(originalApproval);
        const matches = (left, right) => left === undefined || right === undefined
          ? left === right : same(left, right);
        if (originalApproval.action !== 'dispatch' || originalApproval.boundary !== 'acquisition' ||
            facts === undefined || typeof facts.checkpointCid !== 'string' ||
            facts.principalId !== principalId || !matches(facts.readTuple, state.scope.readTuple) ||
            !matches(facts.checkedSource, state.scope.checkedSource) ||
            !matches(facts.physicalBinding, state.scope.physicalBinding) ||
            !matches(facts.installationBinding, state.scope.installationBinding) ||
            facts.occurrence !== undefined && ['stage','input','task'].some(name=>facts.occurrence[name]!==source.occurrence[name]) ||
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
      return JSON.parse(continuationWire());
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
