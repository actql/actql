// Durable Checkpoint lifecycle journal for a Node Host.
//
// Semantics (artifact shape and identity, Resolution admission, signature
// preimages, transition table, commit decisions, resume fencing and Run-state
// projections) are owned by the portable MoonBit core in src/checkpoint_runtime
// and reached through src/checkpoint_runtime_node. This adapter owns only
// storage, the clock, and the Host authorization and attestation ports, which
// verify and produce Ed25519 signatures over the core-computed preimages.
//
// A Run-unit Checkpoint belongs to a Run row. A preparation Checkpoint
// precedes its Run: it belongs to a preparation row, and a Run row exists only
// once the resumed preparation continuation creates it.
import {DatabaseSync} from 'node:sqlite';
import {mkdirSync, realpathSync} from 'node:fs';
import {join} from 'node:path';
import {createSqliteTransaction, throwSqliteInitializationFailure} from
  '../host-common/sqlite-transaction.mjs';
import {initializeCheckpointJournal, prepareCheckpointJournalStatements} from './sqlite-checkpoint-journal-storage.mjs';
import {createModelResumeState} from './model-resume-state.mjs';
import {checkpointJournalClose} from './sqlite-checkpoint-journal-close.mjs';

import {admissionIdentity, authoritiesJson, bindingJson, checkpointView, cid, configurationBinding,
  core, declaredJson, effectsJson, fail, iso, preparationView, priorAdmissionView, requestedClaimsJson,
  subjectBinding, text} from './sqlite-checkpoint-journal-wire.mjs';

import type {StatementResultingChanges} from 'node:sqlite';
import type {WireRunState} from '../../packages/client-wire/index.d.ts';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {CheckpointRuntime} from './checkpoint-runtime.mjs';
import type {AttemptRow, ScopeRow, SlotRow} from './model-resume-sqlite.mjs';
import type {CheckpointRow, IntentRow, RunRow} from './sqlite-checkpoint-journal-storage.mjs';
import type {CheckpointArtifact, ResumeBinding} from './sqlite-checkpoint-journal-wire.mjs';

type ModelCalls = ReturnType<typeof createModelResumeState>;
type ModelOptions = Parameters<typeof createModelResumeState>[1];
type ModelOriginals = Parameters<ModelCalls['prepare']>[1];
type ModelInventory = NonNullable<Parameters<ModelCalls['immediateOriginals']>[0]>;
type RunStatus = WireRunState['status'];

type ResolutionAuthenticationInput = Readonly<{
  checkpointWire: string; resolutionWire: string;
  approvalEvidenceWire: string; proofPreimage: string;
}>;
type ResolutionAuthentication = Readonly<{
  keyId: string; reviewerId: string; authorityContextCid: string;
  policyCid: string; verifiedPreimage: string;
}>;
type ResolutionAttestation = Readonly<{hostKeyId: string; signature: string}>;

type JournalOptions = Readonly<{
  runtime: CheckpointRuntime;
  expectedAuthorityScopeCid: string;
  authorizeResolution(input: ResolutionAuthenticationInput):
    ResolutionAuthentication | PromiseLike<ResolutionAuthentication>;
  attestResolution(preimage: string): ResolutionAttestation | PromiseLike<ResolutionAttestation>;
  modelResumeVerifier?: ModelOptions['verifier'];
  now?(): number;
  faults?: Readonly<{beforeCommit?(step: string): void}>;
}>;

type SealedCheckpoint = Readonly<{
  checkpoint_id: string; checkpoint_cid: string; checkpoint_wire: string;
  kind: CheckpointArtifact['kind']; unit_id: string | null; created_at: string; expires_at: string;
}> & (Readonly<{subject_kind: 'prepare_attempt'; run_id: null; prepare_attempt_id: string}> |
  Readonly<{subject_kind: 'run_unit'; run_id: string; prepare_attempt_id: null}>);
type RunStateResult = Readonly<{
  run_id: string; status: RunStatus; checkpoint_cid: string | null; run_state_wire: string;
}>;
type RunExit = Readonly<{
  run_status: 'cancelled' | 'needs_reconciliation'; run_state_wire: string;
}>;
type RevalidationExit = Readonly<{
  run_status: 'failed' | 'needs_reconciliation'; run_state_wire: string; terminal_error_code: string;
}>;
type Approval = Readonly<{
  checkpoint_cid: string; resolution_cid: string; verified_resolution_cid: string;
  reviewer_id: string; claims: readonly string[]; expires_at: string | null; current: boolean;
}>;
type Fence = Readonly<{action: 'current' | 'stale'}>;
type ClaimDecision = Readonly<{action: 'busy'}> | Readonly<{action: 'completed'}> |
  Readonly<{action: 'invalidated'; generation: number}> |
  Readonly<{action: 'claim' | 'settlement'; generation: number; lease_expires_ms: number}>;

type ResolutionSeal = Readonly<{
  checkpoint_cid: string; decision: 'approved' | 'rejected'; resolution_cid: string;
  verified_resolution_cid: string; verified_resolution_wire: string;
}>;
type ResolutionCommit = Omit<ResolutionSeal, 'checkpoint_cid'> & Readonly<{
  action: 'commit' | 'duplicate' | 'conflict' | 'expired';
  resume_intent_id: string | null;
}> & (Readonly<{effect: 'move_run'; run_status: RunStatus}> |
  Readonly<{effect: 'continue_preparation' | 'end_preparation'; run_status: null}>);
type ResolutionMethod = 'resolutionAdmit' | 'resolutionDecide' |
  'resolutionAdmitImmediate' | 'resolutionSealImmediate';
type ModelResolutionMethod = `model${Capitalize<ResolutionMethod>}`;
type GrantKey = 'checkpointCid' | 'resolutionCid' | 'verifiedResolutionCid' | 'scopeCid' |
  'runId' | 'runDefinitionCid' | 'preparedInvocationCid';
type GrantIdentity = Readonly<Partial<Record<GrantKey, string>>>;
type ModelGrant = GrantIdentity & Readonly<{current: boolean; expiresAt?: string}>;

type CheckpointInput = Readonly<{
  body: string | Readonly<{kind?: unknown}>;
  authorities: unknown; binding: ResumeBinding;
  decisionSubjectCid?: unknown; requestedClaims?: unknown; configurationCid?: unknown;
  modelCallSet?: ModelOriginals;
}>;
type PersistInput = CheckpointInput & Readonly<{priorStatus?: string; declaredResults: unknown}>;
type ClaimIdentity = Readonly<{intentId: string; claimant: string; generation: number}>;
type RunClaim = ClaimIdentity & Readonly<{runId: string; prepareAttemptId?: never}>;
type PreparationClaim = ClaimIdentity & Readonly<{runId?: never; prepareAttemptId: string}>;
type Claim = RunClaim | PreparationClaim;
type ClaimRequest = Readonly<{claimant: string; leaseMs: number; binding: ResumeBinding}>;
type EffectIndex = Readonly<Record<string, readonly string[]>>;
type UnknownEffects = readonly string[] | EffectIndex |
  ((runId: string) => readonly string[] | undefined);
type RunClaimRequest = ClaimRequest & Readonly<{
  unknownEffects?: readonly string[]; preserveStarted?: boolean;
  expectedCheckpointCid?: string; settleEffectRevalidation?: boolean;
}>;
type ResumeOutcome = Readonly<{
  checkpoint?: CheckpointInput; runStateWire?: string; status?: 'failed' | 'cancelled';
  run?: Readonly<{runId: string; status: 'preparing' | 'running'}>; attachImmediateModelCallSet?: boolean;
}>;
type EntryOptions = Readonly<{checkpointCid?: string; resolutionCid?: string; dispatchIdentity?: string}>;
type ResolutionFailure = Readonly<{code?: string; cause?: Readonly<{message?: unknown}>}>;
type ResolutionSubmission = Readonly<{
  checkpointCid: string; resolutionWire: string; approvalEvidenceWire?: string; unknownEffects?: readonly string[];
}>;
type Page = Readonly<{after?: string; limit?: number}>;

export function openSqliteCheckpointJournal(root: string, {
  runtime,
  expectedAuthorityScopeCid,
  authorizeResolution,
  attestResolution,
  modelResumeVerifier,
  now = () => Date.now(),
  faults = {},
}: JournalOptions = {} as JournalOptions) {
  let modelCalls: ModelCalls;
  if (!text(root) || !cid(expectedAuthorityScopeCid) ||
      runtime === null || typeof runtime !== 'object' ||
      typeof runtime.checkpointSealBody !== 'function' ||
      typeof authorizeResolution !== 'function' ||
      typeof attestResolution !== 'function' || typeof now !== 'function') {
    fail('InvalidCheckpointJournalConfiguration');
  }
  const fault = (step: string) => {
    if (typeof faults.beforeCommit === 'function') faults.beforeCommit(step);
  };
  mkdirSync(root, {recursive: true, mode: 0o700});
  const path = join(realpathSync(root), 'checkpoint-journal.sqlite3');
  const database = new DatabaseSync(path, {
    open: true,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
  const originalTransaction = createSqliteTransaction(database, 'CheckpointJournal');
  const transaction = Object.freeze({
    run<Result extends SynchronousRuntimeData>(body: () => Result): Result {
      return originalTransaction.run(() => {
        const value = body();
        // Fixed existing-Owner guard, not a user callback. Cover every
        // transaction (including lease updates without a diagnostic hook),
        // after all body/fault work and immediately before the real COMMIT.
        modelCalls?.assertOriginalCurrentCutsUnchangedLocked();
        return value;
      });
    },
    assertUsable: originalTransaction.assertUsable,
    get connectionUsable() {return originalTransaction.connectionUsable;},
  });
  const closeControl = checkpointJournalClose(database);
  try {
    initializeCheckpointJournal(database, transaction, fail);
  } catch (error) {
    throwSqliteInitializationFailure(database, error, 'checkpoint-journal');
  }

  try {
  const statements = prepareCheckpointJournalStatements(database);

  const alive = () => {
    if (closeControl.closed) fail('CheckpointJournalClosed');
    transaction.assertUsable();
  };
  const changed = (result: StatementResultingChanges, code: string) => {
    if (result.changes !== 1) fail(code);
  };
  const transitionAllowed = (from: string, to: string) => {
    if (!runtime.runTransitionAllowed(from, to)) fail('RunTransitionRejected');
  };
  modelCalls = createModelResumeState(database, {
    verifier: modelResumeVerifier, transaction, alive, now, iso, fault,
    admissionLocked, confirmEntryGrant, fenced,
    checkpoint: reference => statements.checkpoint.get(reference),
    run: runId => statements.run.get(runId),
  });
  const intentView = (row: IntentRow) => JSON.stringify({
    state: row.state,
    generation: Number(row.generation),
    claimant: row.claimant,
    lease_expires_ms: Number(row.lease_expires_ms),
  });

  // Run-state projection issued by the core from committed rows only.
  function projectRunState(runId: string) {
    const run = statements.run.get(runId);
    if (run === undefined) return undefined;
    let wire;
    if (run.status === 'waiting_checkpoint') {
      const row = statements.checkpoint.get(run.checkpoint_cid);
      if (row === undefined) fail('CheckpointJournalCorrupt');
      wire = core<Pick<RunStateResult, 'run_state_wire'>>(runtime.checkpointWaitingState(
        row.checkpoint_wire, row.checkpoint_wire, run.updated_at,
        run.declared_results_json,
      ), 'CheckpointJournalCorrupt').run_state_wire;
    } else if (run.run_state_wire !== '') {
      wire = core<RunStateResult>(runtime.runStateAdmit(run.run_state_wire),
        'CheckpointJournalCorrupt').run_state_wire;
    } else {
      wire = core<Pick<RunStateResult, 'run_state_wire'>>(runtime.checkpointLifecycleState(
        run.run_id, run.status, run.updated_at, run.declared_results_json,
      ), 'CheckpointJournalCorrupt').run_state_wire;
    }
    return Object.freeze({
      runId: run.run_id,
      status: run.status,
      version: Number(run.version),
      runStateWire: wire,
      runState: JSON.parse(wire) as WireRunState,
    });
  }

  function projectPreparation(prepareAttemptId: string) {
    const row = statements.preparation.get(prepareAttemptId);
    return row === undefined ? undefined : preparationView(row);
  }

  function sealBody(body: CheckpointInput['body']) {
    const bodyWire = typeof body === 'string' ? body : JSON.stringify(body);
    return core<SealedCheckpoint>(runtime.checkpointSealBody(bodyWire), 'InvalidCheckpoint');
  }

  const isPreparation = (sealed: SealedCheckpoint): sealed is Extract<SealedCheckpoint, {subject_kind: 'prepare_attempt'}> => sealed.subject_kind === 'prepare_attempt';

  function insertCheckpoint(sealed: SealedCheckpoint, authorities: string, binding: string, subject: string, claims: string,
    configuration: string, at: string) {
    statements.insertCheckpoint.run(
      sealed.checkpoint_cid, sealed.checkpoint_id, sealed.run_id,
      sealed.prepare_attempt_id, sealed.checkpoint_wire, sealed.expires_at,
      authorities, binding, subject, claims, configuration, at,
    );
  }

  // The next Checkpoint named by a resumed continuation's exit.
  function nextCheckpoint(checkpoint: CheckpointInput) {
    const sealed = sealBody(checkpoint.body);
    return {
      sealed,
      modelCallSet: modelCalls.prepare(sealed, checkpoint.modelCallSet),
      reviewers: authoritiesJson(checkpoint.authorities),
      bound: bindingJson(checkpoint.binding),
      subject: subjectBinding(checkpoint.decisionSubjectCid),
      claims: requestedClaimsJson(checkpoint.requestedClaims),
      configuration: configurationBinding(checkpoint.configurationCid),
    };
  }

  // Exit of a waiting Run whose Checkpoint was rejected, expired or
  // cancelled without dispatching its continuation: `cancelled`, or
  // `needs_reconciliation` with a `reconcile` action over the earlier Effect
  // outcomes the Run owner still records as unknown.
  function waitingExit(run: RunRow, unknown: string, at: string) {
    const exit = core<RunExit>(runtime.waitingExitState(run.run_id, at,
      run.declared_results_json, unknown), 'InvalidRunState');
    transitionAllowed('waiting_checkpoint', exit.run_status);
    changed(statements.moveRun.run(exit.run_status, at, '',
      exit.run_status === 'cancelled' ? '' : exit.run_state_wire, run.run_id,
      run.version, 'waiting_checkpoint'), 'RunStateConflict');
    return exit.run_status;
  }

  // Unknown Effects of one Run as the Host reports them: an array, or a
  // function or object keyed by Run id (for a sweep over several Runs).
  function unknownOf(unknownEffects: UnknownEffects | undefined, runId: string) {
    const value = typeof unknownEffects === 'function'
      ? unknownEffects(runId)
      : Array.isArray(unknownEffects) ? unknownEffects
        : (unknownEffects as EffectIndex | undefined)?.[runId];
    return effectsJson(value ?? []);
  }

  // After commit: the waiting projection is issued only from the exact wire
  // read back from the committed row. A preparation Checkpoint has no Run
  // state; its waiting state is the committed preparation row.
  function waitingAfterCommit(sealed: SealedCheckpoint) {
    const row = statements.checkpoint.get(sealed.checkpoint_cid);
    if (row === undefined) fail('CheckpointNotPersisted');
    const identity = {
      checkpointCid: sealed.checkpoint_cid,
      checkpointId: sealed.checkpoint_id,
      runId: sealed.run_id,
      prepareAttemptId: sealed.prepare_attempt_id,
    };
    if (isPreparation(sealed)) {
      core<SealedCheckpoint>(runtime.checkpointAdmit(row.checkpoint_wire),
        'CheckpointNotPersisted');
      return Object.freeze({...identity,
        preparation: projectPreparation(sealed.prepare_attempt_id)});
    }
    const run = statements.run.get(sealed.run_id);
    if (run === undefined) fail('CheckpointNotPersisted');
    if (run.status !== 'waiting_checkpoint' ||
        run.checkpoint_cid !== sealed.checkpoint_cid) {
      // Idempotent retry of an already answered Checkpoint: report the
      // current committed state, never a stale waiting claim.
      const current = projectRunState(sealed.run_id);
      return Object.freeze({...identity,
        runStateWire: current!.runStateWire, runState: current!.runState});
    }
    const wire = core<Pick<RunStateResult, 'run_state_wire'>>(runtime.checkpointWaitingState(
      sealed.checkpoint_wire, row.checkpoint_wire, run.updated_at,
      run.declared_results_json,
    ), 'CheckpointNotPersisted').run_state_wire;
    return Object.freeze({...identity,
      runStateWire: wire, runState: JSON.parse(wire) as WireRunState});
  }

  function expireLocked(row: CheckpointRow, at: string, unknown = '[]') {
    changed(statements.closeCheckpoint.run('expired', '', at,
      row.checkpoint_cid), 'CheckpointAlreadyClosed');
    if (row.prepare_attempt_id !== null) {
      const preparation = statements.preparation.get(row.prepare_attempt_id);
      if (preparation?.status === 'waiting_checkpoint' &&
          preparation.checkpoint_cid === row.checkpoint_cid) {
        changed(statements.movePreparation.run('ended', at, '', '', 'expired',
          '', preparation.prepare_attempt_id, preparation.version,
          'waiting_checkpoint'), 'PreparationStateConflict');
      }
      return;
    }
    const run = statements.run.get(row.run_id);
    if (run?.status === 'waiting_checkpoint' &&
        run.checkpoint_cid === row.checkpoint_cid) {
      waitingExit(run, unknown, at);
    }
  }

  // Host authorization port: it verifies proof.signature (Ed25519) over the
  // core-computed unsigned Resolution CID text with Host-trusted keys and
  // reports the exact text it verified.
  async function authenticate(checkpointWire: string, resolutionWire: string,
    approvalEvidenceWire: string) {
    const {preimage} = core<Readonly<{preimage: string}>>(runtime.resolutionProofPreimage(resolutionWire),
      'InvalidResolution');
    let authentication;
    try {
      authentication = await authorizeResolution(Object.freeze({
        checkpointWire,
        resolutionWire,
        approvalEvidenceWire,
        proofPreimage: preimage,
      }));
    } catch (error) {
      fail('ResolutionAuthenticationFailed', error);
    }
    if (!text(authentication?.keyId) || !text(authentication?.reviewerId) ||
        !text(authentication?.authorityContextCid) ||
        !text(authentication?.policyCid) ||
        !text(authentication?.verifiedPreimage)) {
      fail('ResolutionAuthenticationFailed');
    }
    return JSON.stringify({
      key_id: authentication.keyId,
      reviewer_id: authentication.reviewerId,
      expected_authority_scope_cid: expectedAuthorityScopeCid,
      authority_context_cid: authentication.authorityContextCid,
      policy_cid: authentication.policyCid,
      proof_preimage: authentication.verifiedPreimage,
    });
  }

  // Host attestation port: Ed25519 over the unsigned verified-wrapper CID.
  async function attest(preimage: string) {
    const attestation = await attestResolution(preimage);
    if (!text(attestation?.hostKeyId) || !text(attestation?.signature)) {
      fail('InvalidHostAttestation');
    }
    return attestation;
  }

  function claimLocked(intent: IntentRow, claimant: string, at: number, current: string, leaseMs: number,
    effectSettlement = false, settlementOnly = false) {
    // The admitted layout binds an intent to its original Checkpoint by foreign key.
    const checkpoint = statements.checkpoint.get(intent.checkpoint_cid)!;
    const args = [intentView(intent), claimant, at, leaseMs,
      checkpoint.binding_json, current] as const;
    const decided = core<ClaimDecision>(effectSettlement
      ? runtime.effectResumeClaimDecide(...args, settlementOnly)
      : runtime.resumeClaimDecide(...args), 'InvalidResumeClaim');
    return {checkpoint, decided};
  }

  function modelHasEnteredLocked(checkpoint: CheckpointRow | undefined, intent: IntentRow) {
    if (checkpoint === undefined) fail('CheckpointJournalCorrupt');
    const kind = JSON.parse(checkpoint.checkpoint_wire).kind;
    if (kind === 'read_access') return modelCalls.hasEnteredUnderParentLocked({
      checkpointCid: checkpoint.checkpoint_cid, intentId: intent.intent_id, runId: intent.run_id});
    if (kind !== 'model_invocation') return false;
    return modelCalls.hasEnteredLocked({checkpointCid: checkpoint.checkpoint_cid,
      intentId: intent.intent_id, runId: intent.run_id,
      resolutionCid: intent.resolution_cid});
  }

  function hasStartedLocked(intent: IntentRow) {
    const checkpoint = statements.checkpoint.get(intent.checkpoint_cid);
    return modelHasEnteredLocked(checkpoint, intent) ||
      statements.startedAdmission.get(intent.intent_id) !== undefined;
  }

  function refuseUnsentRunResume(reference: string, runDefinitionCid: string, expectedKind: CheckpointArtifact['kind'], expectedClaim?: ClaimIdentity) {
      alive();
      const at = iso(now());
      return transaction.run(() => {
        const claimedIntent = expectedClaim === undefined ? undefined :
          fenced(expectedClaim, now());
        const checkpoint = rowFor(reference);
        if (checkpoint === undefined) fail('CheckpointNotFound');
        const artifact = JSON.parse(checkpoint.checkpoint_wire) as CheckpointArtifact;
        if (artifact.run_definition_cid !== runDefinitionCid ||
            artifact.kind !== expectedKind || checkpoint.run_id === null) {
          fail('CheckpointRunMismatch');
        }
        const intent = statements.intentByCheckpoint.get(
          checkpoint.checkpoint_cid);
        if (claimedIntent !== undefined && claimedIntent.intent_id !== intent?.intent_id) {
          fail('ResumeClaimStale');
        }
        const run = statements.run.get(checkpoint.run_id);
        if (checkpoint.closure !== 'resolved' || intent === undefined ||
            run?.status !== 'resuming' || intent.state === 'completed') {
          return Object.freeze({outcome: 'not_resuming'});
        }
        if (hasStartedLocked(intent)) {
          return Object.freeze({outcome: 'admitted'});
        }
        transitionAllowed('resuming', 'failed');
        changed(statements.completeIntent.run(Number(intent.generation) + 1,
          'preparation-refusal', 'failed', at, intent.intent_id,
          intent.generation), 'ResumeClaimStale');
        changed(statements.moveRun.run('failed', at, '', '', run.run_id,
          run.version, 'resuming'), 'RunStateConflict');
        fault('refuseUnsentEffectResume');
        return Object.freeze({outcome: 'failed', runId: run.run_id});
      });
    }

  // The portable Model grant checker owns the minimum of approval, review
  // and original Run validity. A generic current approval alone is insufficient.
  function confirmModelGrant(originals: NonNullable<ModelOriginals>, checkpointWire: string, verifiedWire: string,
    expected: GrantIdentity, at: number, immediate = false) {
    const method = immediate ? 'modelImmediateInvocationGrantAt' : 'modelInvocationGrantAt';
    if (typeof runtime[method] !== 'function') {
      fail('ModelInvocationGrantRuntimeUnavailable');
    }
    const grant = core<ModelGrant>(runtime[method](JSON.stringify(originals),
      checkpointWire, verifiedWire, iso(at)), 'ModelInvocationGrantRejected');
    if (grant.current !== true || !text(grant.expiresAt) ||
        (['checkpointCid', 'resolutionCid', 'verifiedResolutionCid', 'scopeCid',
          'runId', 'runDefinitionCid', 'preparedInvocationCid'] as const).some(
          key => grant[key] !== expected[key])) {
      fail('ModelInvocationGrantMismatch');
    }
    return grant.expiresAt;
  }

  // Called only after admissionLocked, inside the same per-call transaction.
  // Read the exact private-journal wrapper produced by authenticated atomic
  // submitResolution, never caller/imported bytes. Its original authentication
  // and Host sealing ports establish provenance; canonical shape alone does not.
  function confirmEntryGrant(originals: NonNullable<ModelOriginals>, inventory: ModelInventory['inventory'],
    admission: Readonly<{checkpointCid: string; resolutionCid: string; verifiedResolutionCid: string}>, at: number) {
    const row = statements.checkpoint.get(admission.checkpointCid);
    const stored = statements.resolution.get(admission.checkpointCid);
    if (row === undefined || stored?.resolution_cid !== admission.resolutionCid ||
        stored.verified_resolution_cid !== admission.verifiedResolutionCid) {
      fail('ResolutionNotCommitted');
    }
    return confirmModelGrant(originals, row.checkpoint_wire, stored.verified_resolution_wire,
      {...inventory, resolutionCid: admission.resolutionCid,
        verifiedResolutionCid: admission.verifiedResolutionCid}, at);
  }

  // Generic Core Resolution admission cannot establish the original Run,
  // PreparedInvocation and fixed Model scope binding. Select its dedicated
  // entry point only from checked retained originals, re-read at commit.
  // Source/Effect calls keep the original export and argument list.
  function resolutionCall<Method extends ResolutionMethod>(method: Method,
    row: Readonly<{checkpoint_wire: string; checkpoint_cid: string}>,
    args: Parameters<CheckpointRuntime[Method]>,
    {locked = false, inventory}: Readonly<{locked?: boolean; inventory?: ModelInventory}> = {}) {
    if (JSON.parse(row.checkpoint_wire).kind !== 'model_invocation') {
      return (runtime[method] as (...wires: typeof args) => string)(...args);
    }
    const modelMethod = `model${method[0].toUpperCase()}${method.slice(1)}` as ModelResolutionMethod;
    if (typeof runtime[modelMethod] !== 'function') {
      fail('ModelResolutionRuntimeUnavailable');
    }
    const call = () => {
      const originals = inventory === undefined
        ? modelCalls.resolutionOriginals(row.checkpoint_cid)
        : modelCalls.immediateOriginals(inventory);
      return (runtime[modelMethod] as (original: string, ...wires: typeof args) => string)(JSON.stringify(originals), ...args);
    };
    return locked ? call() : transaction.run(call);
  }

  function persistCheckpoint({
    body, priorStatus, declaredResults, authorities, binding,
    decisionSubjectCid, requestedClaims, configurationCid, modelCallSet,
  }: PersistInput, attachImmediate = false) {
    alive();
    const sealed = sealBody(body);
    const inventory = modelCalls.prepare(sealed, modelCallSet);
    if (isPreparation(sealed)) {
      if (priorStatus !== undefined) fail('RunTransitionRejected');
    } else {
      if (priorStatus !== 'preparing' && priorStatus !== 'running') {
        fail('RunTransitionRejected');
      }
      transitionAllowed(priorStatus, 'waiting_checkpoint');
    }
    const reviewers = authoritiesJson(authorities);
    const bound = bindingJson(binding);
    const subject = subjectBinding(decisionSubjectCid);
    const claims = requestedClaimsJson(requestedClaims);
    const configuration = configurationBinding(configurationCid);
    const declared = declaredJson(declaredResults);
    const at = iso(now());
    transaction.run(() => {
      const existing = statements.checkpoint.get(sealed.checkpoint_cid);
      if (existing !== undefined) {
        if (existing.checkpoint_wire !== sealed.checkpoint_wire ||
            existing.authorities_json !== reviewers ||
            existing.binding_json !== bound ||
            existing.decision_subject_cid !== subject ||
            existing.requested_claims_json !== claims ||
            existing.configuration_cid !== configuration) {
          fail('CheckpointConflict');
        }
        modelCalls.registerLocked(sealed, inventory, at, true, attachImmediate);
        return;
      }
      if (isPreparation(sealed)) {
        if (statements.preparation.get(sealed.prepare_attempt_id) !==
            undefined) {
          fail('PreparationAlreadyTracked');
        }
        statements.insertPreparation.run(sealed.prepare_attempt_id, at,
          declared, sealed.checkpoint_cid);
      } else {
        const run = statements.run.get(sealed.run_id);
        if (run === undefined) {
          statements.insertRun.run(sealed.run_id, 'waiting_checkpoint', at,
            declared, sealed.checkpoint_cid);
        } else {
          if (run.status !== priorStatus) fail('RunStateConflict');
          changed(statements.moveRun.run('waiting_checkpoint', at,
            sealed.checkpoint_cid, '', run.run_id, run.version,
            priorStatus), 'RunStateConflict');
        }
      }
      insertCheckpoint(sealed, reviewers, bound, subject, claims,
        configuration, at);
      modelCalls.registerLocked(sealed, inventory, at, false, attachImmediate);
      fault('persistCheckpoint');
    });
    return waitingAfterCommit(sealed);
  }

  return Object.freeze({
    path,

    get connectionFenced() { return !transaction.connectionUsable; },

    // Private Local Reviewer custody in THIS original Journal, not another
    // signing store or a public grant API. The caller retains the authenticated
    // operation, policy, key and current authority. A successful transition is
    // observed only after the original FULL transaction confirms its COMMIT.
    localSigningRecord(operationCid: string) {
      if (closeControl.closed) fail('CheckpointJournalClosed');
      if (!cid(operationCid)) fail('InvalidLocalSigningOperation');
      return statements.localSigning.get('local-signing/' + operationCid)?.value;
    },
    transitionLocalSigningRecord(operationCid: string, previous: string | undefined, next: string) {
      if (closeControl.closed) fail('CheckpointJournalClosed');
      if (!cid(operationCid) || typeof next !== 'string' ||
          Buffer.byteLength(next, 'utf8') > 32768 ||
          previous !== undefined && typeof previous !== 'string') {
        fail('InvalidLocalSigningOperation');
      }
      const key = 'local-signing/' + operationCid;
      return transaction.run(() => {
        const observed = statements.localSigning.get(key)?.value;
        if (observed !== previous) fail('LocalSigningOriginalConflict');
        if (previous === undefined) statements.insertLocalSigning.run(key, next);
        else changed(statements.updateLocalSigning.run(next, key, previous),
          'LocalSigningOriginalConflict');
        fault('localSigningRecord');
        return next;
      });
    },

    // The Core lifecycle owns outcome classification. Unknown host values
    // cannot authorize retirement; cleanup and Result custody are separate.
    isTerminalRunOutcome(status: unknown) {
      return typeof status === 'string' && runtime.runOutcomeTerminal(status);
    },

    // Seal and durably persist a deferred decision. The caller may report
    // a waiting Checkpoint only from the returned projection, which exists
    // only after the transaction committed. A Run-unit Checkpoint either
    // creates its Run or moves the tracked Run from `priorStatus`; a
    // preparation Checkpoint creates no Run.
    persistCheckpoint: (input: PersistInput) => persistCheckpoint(input),

    // Registration includes the complete checked inventory in the Checkpoint
    // transaction. There is no API for adding an inventory or slot afterward.
    registerResumeCallSet(input: PersistInput) {
      if (input?.modelCallSet === undefined) fail('ModelCallInventoryRequired');
      return persistCheckpoint(input);
    },

    // Attach a real deferred approval to the same immediate inventory. This
    // never replaces the inventory or reinitializes any existing slot/attempt.
    attachModelCallSetCheckpoint(input: PersistInput & Readonly<{body: Readonly<{kind: unknown}>}>) {
      if (input?.body?.kind !== 'model_invocation' || input.modelCallSet === undefined) {
        fail('ModelCallInventoryRequired');
      }
      return persistCheckpoint(input, true);
    },

    // Track the already-issued original Run and its full call inventory in one
    // transaction. Registration grants no permission and creates no Checkpoint.
    registerImmediateModelCallSet({modelCallSet, declaredResults, parentResume}: Readonly<{
      modelCallSet: ModelOriginals; declaredResults: unknown;
      parentResume?: Readonly<{claim: RunClaim; checkpointCid: string}>;
    }>) {
      alive();
      const prepared = modelCalls.prepareImmediate(modelCallSet);
      const declared = declaredJson(declaredResults);
      const at = iso(now());
      transaction.run(() => {
        const runId = prepared.inventory.runId;
        const existing = statements.run.get(runId);
        if (existing === undefined) {
          if (parentResume !== undefined) fail('ModelImmediateParentResumeMismatch');
          statements.insertRun.run(runId, 'running', at, declared, '');
        } else if (existing.status === 'resuming' && parentResume !== undefined) {
          const parent = admissionLocked(parentResume.claim, parentResume.checkpointCid, now());
          if (parent.runId !== runId || parent.kind !== 'read_access' || existing.declared_results_json !== declared) {
            fail('ModelImmediateParentResumeMismatch');
          }
        } else if (existing.status !== 'running' || existing.declared_results_json !== declared || parentResume !== undefined) {
          fail('RunStateConflict');
        }
        modelCalls.registerImmediateLocked(prepared, at);
        fault('registerImmediateModelCallSet');
      });
      return modelCalls.public.readModelCalls(prepared.inventory);
    },

    // Bounded recovery discovery only. These retained originals are untrusted
    // until the installed owner reopens their Store custody and the ordinary
    // Model read path re-admits them. Discovery cannot grant send permission.
    discoverModelCallSets({runId, after = '', limit = 100}: Page & Readonly<{runId?: string}> = {}) {
      alive();
      if ((runId !== undefined && !text(runId)) || typeof after !== 'string' ||
          !Number.isSafeInteger(limit) || limit < 1 || limit > 1000) {
        fail('InvalidModelInventoryPage');
      }
      const rows = database.prepare(`SELECT scope_cid, checkpoint_cid,
        inventory_json, originals_json, checkpoint_originals_json FROM resume_model_scopes
        WHERE (? IS NULL OR run_id = ?) AND scope_cid > ?
        ORDER BY scope_cid LIMIT ?`).all(runId ?? null, runId ?? null, after, limit) as
        Pick<ScopeRow, 'scope_cid' | 'checkpoint_cid' | 'inventory_json' | 'originals_json' | 'checkpoint_originals_json'>[];
      return rows.map(row => Object.freeze({scopeCid: row.scope_cid,
        checkpointCid: row.checkpoint_cid,
        inventory: JSON.parse(row.inventory_json),
        originals: JSON.parse(row.checkpoint_originals_json || row.originals_json)}));
    },
    hasUnresolvedModelCalls(runId: string) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      return transaction.run(() => {
        let unresolved = false;
        const scopes = database.prepare('SELECT * FROM resume_model_scopes WHERE run_id = ?').all(runId) as ScopeRow[];
        for (const scope of scopes) {
          const inventory = JSON.parse(scope.inventory_json);
          const slots = database.prepare('SELECT * FROM resume_model_slots WHERE scope_cid = ? ORDER BY ordinal').all(scope.scope_cid) as SlotRow[];
          const attempts = database.prepare('SELECT * FROM resume_model_attempts WHERE scope_cid = ? ORDER BY ordinal, attempt_index').all(scope.scope_cid) as AttemptRow[];
          if (!Array.isArray(inventory.slots) || inventory.slots.length !== scope.slot_count ||
              slots.length !== scope.slot_count) fail('ModelResumeInventoryCorrupt');
          for (const [ordinal, slot] of slots.entries()) {
            if (slot.ordinal !== ordinal || inventory.slots[ordinal]?.slotCid !== slot.slot_cid ||
                inventory.slots[ordinal]?.ordinal !== ordinal) fail('ModelResumeInventoryCorrupt');
            const entered = attempts.filter(attempt => attempt.ordinal === ordinal);
            if (slot.state === 'Unsent') {
              if (slot.attempt_index !== 0 || entered.length !== 0) fail('ModelResumeInventoryCorrupt');
            } else {
              const last = entered.at(-1);
              if (entered.length !== slot.attempt_index || last?.attempt_index !== slot.attempt_index ||
                  last?.state !== slot.state || entered.some((attempt, index) => attempt.attempt_index !== index + 1 ||
                    JSON.parse(attempt.entry_json).slotCid !== slot.slot_cid ||
                    JSON.parse(attempt.entry_json).attemptCid !== attempt.attempt_cid)) {
                fail('ModelResumeInventoryCorrupt');
              }
            }
            if (slot.state === 'EnteredUnknown') unresolved = true;
          }
          if (attempts.some(attempt => slots[attempt.ordinal] === undefined)) fail('ModelResumeInventoryCorrupt');
        }
        return unresolved;
      });
    },

    ...modelCalls.public,

    // Record a Run the Host created directly (for example an allowed
    // invocation). A Run created by a resumed preparation continuation uses
    // completeResume instead.
    createRun({runId, status = 'running', declaredResults}: Readonly<{runId: string; status?: string; declaredResults: unknown}>) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      if (status !== 'preparing' && status !== 'running') {
        fail('RunTransitionRejected');
      }
      const declared = declaredJson(declaredResults);
      const at = iso(now());
      transaction.run(() => {
        if (statements.run.get(runId) !== undefined) fail('RunAlreadyTracked');
        statements.insertRun.run(runId, status, at, declared, '');
        fault('createRun');
      });
      return projectRunState(runId);
    },

    // Exit of a Run that is not resuming (a resumed continuation exits
    // through completeResume). Compare-and-swap on the current status. A
    // `succeeded` exit without a continuation-issued state records that no
    // declared Result was published; any issued state is admitted by the core.
    finishRun(runId: string, {status, from = 'running', runStateWire}: Readonly<{status: string; from?: string; runStateWire?: string}>) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      if (!['succeeded', 'failed', 'needs_reconciliation', 'cancelled']
        .includes(status) || from === 'resuming') {
        fail('RunTransitionRejected');
      }
      transitionAllowed(from, status);
      const at = iso(now());
      transaction.run(() => {
        const run = statements.run.get(runId);
        if (run === undefined) fail('RunNotFound');
        if (run.status !== from) fail('RunStateConflict');
        let wire = '';
        if (text(runStateWire) || status === 'succeeded' ||
            status === 'needs_reconciliation') {
          let issued = runStateWire;
          if (!text(issued)) {
            if (status !== 'succeeded') fail('InvalidRunState');
            const running = JSON.parse(core<Pick<RunStateResult, 'run_state_wire'>>(runtime.checkpointLifecycleState(
              runId, 'running', at, run.declared_results_json,
            ), 'InvalidRunState').run_state_wire);
            issued = JSON.stringify({...running, status});
          }
          const view = core<RunStateResult>(runtime.runStateAdmit(issued), 'InvalidRunState');
          if (view.run_id !== runId || view.status !== status ||
              view.checkpoint_cid !== null) {
            fail('InvalidRunState');
          }
          wire = view.run_state_wire;
        }
        changed(statements.moveRun.run(status, at, '', wire, runId,
          run.version, from), 'RunStateConflict');
        fault('finishRun');
      });
      return projectRunState(runId);
    },

    // Cancel a waiting Checkpoint without dispatching its continuation: the
    // Checkpoint closes as cancelled, a waiting preparation ends without a
    // Run and a waiting Run moves to `cancelled`, or to
    // `needs_reconciliation` over `unknownEffects` (earlier Effect outcomes
    // of the Run the Host still records as unknown). No resume intent exists
    // or is created. Repeating the cancel is idempotent; an answered or
    // expired Checkpoint is not cancelled.
    cancelCheckpoint(reference: string, {unknownEffects = []}: Readonly<{unknownEffects?: readonly string[]}> = {}) {
      alive();
      const unknown = effectsJson(unknownEffects);
      const at = iso(now());
      return transaction.run(() => {
        const row = rowFor(reference);
        if (row === undefined) fail('CheckpointNotFound');
        if (row.closure === 'cancelled') {
          return Object.freeze({outcome: 'duplicate', checkpointCid:
            row.checkpoint_cid});
        }
        if (row.closure !== 'open') {
          return Object.freeze({outcome: 'not_open', closure: row.closure,
            checkpointCid: row.checkpoint_cid});
        }
        changed(statements.closeCheckpoint.run('cancelled', '', at,
          row.checkpoint_cid), 'CheckpointAlreadyClosed');
        let runStatus;
        if (row.prepare_attempt_id !== null) {
          // A preparation precedes its Run and has no Effect outcomes.
          if (unknown !== '[]') fail('InvalidUnknownEffects');
          const preparation = statements.preparation.get(row.prepare_attempt_id);
          if (preparation?.status !== 'waiting_checkpoint' ||
              preparation.checkpoint_cid !== row.checkpoint_cid) {
            fail('PreparationStateConflict');
          }
          changed(statements.movePreparation.run('ended', at, '', '',
            'cancelled', '', preparation.prepare_attempt_id,
            preparation.version, 'waiting_checkpoint'),
          'PreparationStateConflict');
        } else {
          const run = statements.run.get(row.run_id);
          if (run?.status !== 'waiting_checkpoint' ||
              run.checkpoint_cid !== row.checkpoint_cid) {
            fail('RunStateConflict');
          }
          runStatus = waitingExit(run, unknown, at);
        }
        fault('cancelCheckpoint');
        return Object.freeze({outcome: 'cancelled',
          checkpointCid: row.checkpoint_cid,
          ...(row.run_id !== null ? {runId: row.run_id, runStatus} :
            {prepareAttemptId: row.prepare_attempt_id})});
      });
    },

    // A cancelled request may fence an answered continuation only before
    // any protected dispatch was admitted. The admission and this transition
    // use the same SQLite write transaction, so neither can overtake the
    // other. An admitted send remains the resume owner's reconciliation duty.
    cancelUnsentResume(reference: string) {
      alive();
      const at = iso(now());
      return transaction.run(() => {
        const checkpoint = rowFor(reference);
        if (checkpoint === undefined) fail('CheckpointNotFound');
        if (checkpoint.run_id === null || checkpoint.closure !== 'resolved') {
          return Object.freeze({outcome: 'not_resuming'});
        }
        const intent = statements.intentByCheckpoint.get(
          checkpoint.checkpoint_cid);
        const run = statements.run.get(checkpoint.run_id);
        if (intent === undefined || run?.status !== 'resuming' ||
            intent.state === 'completed') {
          return Object.freeze({outcome: 'not_resuming'});
        }
        if (hasStartedLocked(intent)) {
          return Object.freeze({outcome: 'admitted'});
        }
        transitionAllowed('resuming', 'cancelled');
        const generation = Number(intent.generation) + 1;
        changed(statements.completeIntent.run(generation, 'cancellation',
          'cancelled', at, intent.intent_id, intent.generation),
        'ResumeClaimStale');
        changed(statements.moveRun.run('cancelled', at, '', '', run.run_id,
          run.version, 'resuming'), 'RunStateConflict');
        fault('cancelUnsentResume');
        return Object.freeze({outcome: 'cancelled', runId: run.run_id});
      });
    },

    // Refusal is exact-kind and only applies before any protected start.
    refuseUnsentEffectResume: (reference: string, runDefinitionCid: string) =>
      refuseUnsentRunResume(reference, runDefinitionCid, 'effect_set'),
    refuseUnsentSourceResume(reference: string, runDefinitionCid: string, claim: ClaimIdentity) {
      if (claim === undefined) fail('InvalidResumeClaim');
      return refuseUnsentRunResume(reference, runDefinitionCid, 'read_access', claim);
    },

    // Exact Run read-access refusal for continuations whose physical owner is
    // not a Source acquisition. Preserve the same live claim and started guard.
    refuseUnsentReadResume(reference: string, runDefinitionCid: string, claim: ClaimIdentity) {
      if (claim === undefined) fail('InvalidResumeClaim');
      return refuseUnsentRunResume(reference, runDefinitionCid, 'read_access', claim);
    },
    // A definitive Model policy refusal may end only an exact live resume
    // whose complete inventory still proves that no call ever entered.
    refuseUnsentModelResume(reference: string, runDefinitionCid: string, claim: ClaimIdentity) {
      if (claim === undefined) fail('InvalidResumeClaim');
      return refuseUnsentRunResume(reference, runDefinitionCid, 'model_invocation', claim);
    },

    // Durable request cancellation of one prepare attempt, committed before
    // it is acknowledged. A waiting preparation is ended as cancelled with
    // its Checkpoint closed (a later answer is then `cancelled`). A resuming
    // or Run-created preparation keeps the durable request for its resume
    // owner, which must not start it and forwards it to the Run's own
    // cancellation. Outcomes: `accepted`, `already_requested` (this request
    // was already recorded, or the preparation already ended cancelled) or
    // `already_terminal` (ended otherwise). Repeating it changes nothing.
    requestPreparationCancellation(prepareAttemptId: string) {
      alive();
      if (!text(prepareAttemptId)) fail('InvalidPrepareAttemptId');
      const at = iso(now());
      return transaction.run(() => {
        const preparation = statements.preparation.get(prepareAttemptId);
        if (preparation === undefined) fail('PreparationNotFound');
        const view = () => projectPreparation(prepareAttemptId);
        if (preparation.cancel_requested === 1 ||
            preparation.status === 'ended' &&
              preparation.end_reason === 'cancelled') {
          return Object.freeze({outcome: 'already_requested',
            preparation: view()});
        }
        if (preparation.status === 'ended') {
          return Object.freeze({outcome: 'already_terminal',
            preparation: view()});
        }
        if (preparation.status === 'waiting_checkpoint') {
          changed(statements.closeCheckpoint.run('cancelled', '', at,
            preparation.checkpoint_cid), 'CheckpointAlreadyClosed');
          changed(statements.movePreparation.run('ended', at, '', '',
            'cancelled', '', prepareAttemptId, preparation.version,
            'waiting_checkpoint'), 'PreparationStateConflict');
          const ended = statements.preparation.get(prepareAttemptId);
          changed(statements.requestPreparationCancel.run(at,
            prepareAttemptId, ended!.version), 'PreparationStateConflict');
        } else {
          changed(statements.requestPreparationCancel.run(at,
            prepareAttemptId, preparation.version),
          'PreparationStateConflict');
        }
        fault('requestPreparationCancellation');
        return Object.freeze({outcome: 'accepted', preparation: view()});
      });
    },

    // Safe metadata of the waiting Checkpoints, oldest first. With `limit`
    // one bounded page is returned after the opaque `after` cursor (the
    // `cursor` of the page's last item); without it, every waiting one.
    listPending({after, limit}: Page = {}) {
      alive();
      let rows;
      if (limit === undefined) {
        if (after !== undefined) fail('InvalidCheckpointPage');
        rows = statements.pending.all();
      } else {
        if (!Number.isSafeInteger(limit) || limit < 1 || limit > 1000) {
          fail('InvalidCheckpointPage');
        }
        let cursor = ['', ''];
        if (after !== undefined) {
          const parsed = typeof after === 'string' ? after.split('|') : [];
          if (parsed.length !== 2 || !text(parsed[0]) || !text(parsed[1])) {
            fail('InvalidCheckpointPage');
          }
          cursor = parsed;
        }
        rows = statements.pendingPage.all(cursor[0], cursor[0], cursor[1],
          limit);
      }
      return rows.map(row => {
        core<SealedCheckpoint>(runtime.checkpointAdmit(row.checkpoint_wire),
          'CheckpointJournalCorrupt');
        const view = checkpointView(row.checkpoint_wire, row);
        return limit === undefined ? view : Object.freeze({...view,
          cursor: `${row.persisted_at}|${row.checkpoint_cid}`});
      });
    },

    // Discover retained Run continuations, including closed Checkpoints whose
    // Run still needs reconciliation or cleanup. Discovery grants no execution.
    listRunCheckpoints({after = '', limit = 100}: Page = {}) {
      alive();
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 1000 ||
          typeof after !== 'string') fail('InvalidCheckpointPage');
      return (database.prepare(`SELECT * FROM checkpoints
        WHERE run_id IS NOT NULL AND checkpoint_cid > ?
        ORDER BY checkpoint_cid LIMIT ?`).all(after, limit) as CheckpointRow[]).map(row => {
        core<SealedCheckpoint>(runtime.checkpointAdmit(row.checkpoint_wire),
          'CheckpointJournalCorrupt');
        return checkpointView(row.checkpoint_wire, row);
      });
    },

    // Prepare attempts with an approved, not yet completed resume intent.
    // Claims decide who continues; pages use the last prepare attempt ID.
    listResumablePreparations({after = '', limit = 100}: Page = {}) {
      alive();
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 1000 ||
          typeof after !== 'string') {
        fail('InvalidResumableLimit');
      }
      return statements.resumablePreparations.all(after, limit)
        .map(row => row.prepare_attempt_id);
    },

    // Runs created by approved preparations and still `running`, as
    // {prepareAttemptId, runId}, one page after `after`. The Host that owns
    // the Run's execution resumes or reconciles each on start; completing
    // the preparation intent never drops this duty.
    listPreparationRuns({after = '', limit = 100}: Page = {}) {
      alive();
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 1000 ||
          typeof after !== 'string') {
        fail('InvalidPreparationRunPage');
      }
      return statements.preparationRuns.all(after, limit).map(row =>
        Object.freeze({prepareAttemptId: row.prepare_attempt_id,
          runId: row.run_id}));
    },

    inspect(reference: string) {
      alive();
      const row = rowFor(reference);
      if (row === undefined) return undefined;
      core<SealedCheckpoint>(runtime.checkpointAdmit(row.checkpoint_wire),
        'CheckpointJournalCorrupt');
      return checkpointView(row.checkpoint_wire, row);
    },

    // Original bytes for this journal's private signing connection, not an
    // incoming summary or a newly reconstructed Checkpoint. Its caller must
    // retain the same read/current/closure checks before and after callbacks.
    originalCheckpointForSigning(reference: string) {
      alive();
      const row = rowFor(reference);
      if (row === undefined) fail('CheckpointUnavailable');
      core<SealedCheckpoint>(runtime.checkpointAdmit(row.checkpoint_wire), 'CheckpointJournalCorrupt');
      return Object.freeze({wire: row.checkpoint_wire,
        view: checkpointView(row.checkpoint_wire, row)});
    },

    getRunState(runId: string) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      return projectRunState(runId);
    },

    // The exact durable continuation currently linked to this Run. This is
    // routing metadata only: no current claim, approval or authority is inferred.
    activeRunCheckpoint(runId: string) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      return transaction.run(() => {
        const run = statements.run.get(runId);
        if (run === undefined) return undefined;
        const active = statements.activeRunIntents.all(runId);
        if (active.length > 1) fail('CheckpointJournalCorrupt');
        let reference;
        let intent;
        if (run.status === 'waiting_checkpoint') {
          if (active.length !== 0 || run.checkpoint_cid === '') {
            fail('CheckpointJournalCorrupt');
          }
          reference = run.checkpoint_cid;
        } else if (run.status === 'resuming') {
          intent = active[0];
          if (intent === undefined ||
              statements.intent.get(runId)?.intent_id !== intent.intent_id) {
            fail('CheckpointJournalCorrupt');
          }
          reference = intent.checkpoint_cid;
        } else {
          if (active.length !== 0) fail('CheckpointJournalCorrupt');
          return undefined;
        }
        const row = statements.checkpoint.get(reference);
        if (row === undefined || row.run_id !== runId ||
            row.prepare_attempt_id !== null) fail('CheckpointJournalCorrupt');
        const admitted = core<SealedCheckpoint>(runtime.checkpointAdmit(row.checkpoint_wire),
          'CheckpointJournalCorrupt');
        if (admitted.checkpoint_cid !== reference || admitted.run_id !== runId ||
            admitted.subject_kind !== 'run_unit') fail('CheckpointJournalCorrupt');
        if (intent === undefined) {
          if (row.closure !== 'open') fail('CheckpointJournalCorrupt');
        } else {
          const resolution = statements.resolution.get(reference);
          if (row.closure !== 'resolved' ||
              row.resolution_cid !== intent.resolution_cid ||
              resolution?.resolution_cid !== intent.resolution_cid ||
              resolution.decision !== 'approved') fail('CheckpointJournalCorrupt');
        }
        return checkpointView(row.checkpoint_wire, row);
      });
    },

    // The committed answer of one Checkpoint: decision, actor and the
    // Resolution identities. Evidence and review contents are not returned.
    resolutionOf(reference: string) {
      alive();
      const row = rowFor(reference);
      if (row === undefined) return undefined;
      const stored = statements.resolution.get(row.checkpoint_cid);
      if (stored === undefined) return undefined;
      const verified = JSON.parse(stored.verified_resolution_wire);
      return Object.freeze({
        checkpointCid: row.checkpoint_cid,
        decision: stored.decision,
        actor: verified.resolution.actor,
        resolutionCid: stored.resolution_cid,
        verifiedResolutionCid: stored.verified_resolution_cid,
      });
    },

    getPreparation(prepareAttemptId: string) {
      alive();
      if (!text(prepareAttemptId)) fail('InvalidPrepareAttemptId');
      return projectPreparation(prepareAttemptId);
    },

    // Admit, attest, and commit one Resolution. Resolution storage,
    // Checkpoint closure, the Run or preparation transition and the unique
    // resume intent commit in one transaction. `unknownEffects` are the
    // earlier Effect outcomes of the Run the Host still records as unknown:
    // a rejection (or an expiry found here) then moves the waiting Run to
    // `needs_reconciliation` instead of `cancelled`, without a resume intent.
    async submitResolution({
      checkpointCid, resolutionWire, approvalEvidenceWire = '',
      unknownEffects = [],
    }: ResolutionSubmission) {
      alive();
      if (!text(checkpointCid) || !text(resolutionWire) ||
          typeof approvalEvidenceWire !== 'string') {
        fail('InvalidResolutionSubmission');
      }
      const unknown = effectsJson(unknownEffects);
      const row = statements.checkpoint.get(checkpointCid);
      if (row === undefined) fail('CheckpointNotFound');
      if (row.prepare_attempt_id !== null && unknown !== '[]') {
        fail('InvalidUnknownEffects');
      }
      const verifiedAt = iso(now());
      const authJson = await authenticate(row.checkpoint_wire, resolutionWire,
        approvalEvidenceWire);
      const admitted = core<Readonly<{attestation_preimage: string}>>(resolutionCall('resolutionAdmit', row, [
        row.checkpoint_wire, resolutionWire, approvalEvidenceWire, authJson,
        row.authorities_json, verifiedAt,
      ]), 'InvalidResolution');
      const attestation = await attest(admitted.attestation_preimage);
      alive();
      const outcome = transaction.run(() => {
        const current = statements.checkpoint.get(checkpointCid)!;
        // A cancelled Checkpoint admits no Resolution and no resume intent.
        if (current.closure === 'cancelled') return {kind: 'cancelled'} as const;
        // Authentication and attestation are asynchronous Host work: the
        // expiration decision uses the trusted time read again here, at the
        // commit boundary, never the time captured before that work.
        const committedAt = iso(now());
        if (current.closure === 'open' && core<Readonly<{expired: boolean}>>(runtime.checkpointExpiredAt(
          current.checkpoint_wire, committedAt), 'CheckpointJournalCorrupt')
          .expired) {
          expireLocked(current, committedAt, unknown);
          return {kind: 'expired'} as const;
        }
        const decided = core<ResolutionCommit>(resolutionCall('resolutionDecide', current, [
          current.checkpoint_wire, resolutionWire, approvalEvidenceWire,
          authJson, current.authorities_json, verifiedAt,
          attestation.hostKeyId, attestation.signature, current.closure,
          current.resolution_cid, unknown,
        ], {locked: true}), 'InvalidResolution');
        if (decided.action === 'duplicate') {
          return {kind: 'duplicate', decided} as const;
        }
        if (decided.action === 'conflict') {
          return {kind: 'conflict'} as const;
        }
        // An approval whose own permission already lapsed at the commit
        // boundary authorizes nothing: it is not committed, and the open
        // Checkpoint keeps waiting for an answer within its deadline.
        if (decided.action !== 'expired' && decided.decision === 'approved' &&
            !core<Approval>(runtime.resumedApprovalAt(decided.verified_resolution_wire,
              committedAt), 'InvalidResolution').current) {
          return {kind: 'approval_expired'} as const;
        }
        if (decided.action === 'expired') {
          if (current.closure === 'open') {
            expireLocked(current, verifiedAt, unknown);
          }
          return {kind: 'expired'} as const;
        }
        if (decided.effect === 'move_run') {
          const run = statements.run.get(current.run_id);
          if (run?.status !== 'waiting_checkpoint' ||
              run.checkpoint_cid !== checkpointCid) {
            fail('RunStateConflict');
          }
          if (decided.decision === 'approved') {
            transitionAllowed('waiting_checkpoint', decided.run_status);
            changed(statements.moveRun.run(decided.run_status, verifiedAt, '',
              '', run.run_id, run.version, 'waiting_checkpoint'),
            'RunStateConflict');
          } else if (waitingExit(run, unknown, verifiedAt) !==
              decided.run_status) {
            fail('RunTransitionRejected');
          }
        } else {
          const preparation = statements.preparation.get(
            current.prepare_attempt_id);
          if (preparation?.status !== 'waiting_checkpoint' ||
              preparation.checkpoint_cid !== checkpointCid) {
            fail('PreparationStateConflict');
          }
          // Approval continues the same attempt; rejection ends it and no
          // Run is ever created for it.
          const [status, reason] = decided.effect === 'continue_preparation' ?
            ['resuming', ''] : ['ended', 'rejected'];
          changed(statements.movePreparation.run(status, verifiedAt, '', '',
            reason, '', preparation.prepare_attempt_id, preparation.version,
            'waiting_checkpoint'), 'PreparationStateConflict');
        }
        statements.insertResolution.run(
          decided.resolution_cid, checkpointCid, decided.decision,
          decided.verified_resolution_cid, decided.verified_resolution_wire,
          verifiedAt,
        );
        changed(statements.closeCheckpoint.run('resolved',
          decided.resolution_cid, verifiedAt, checkpointCid),
        'CheckpointAlreadyClosed');
        if (decided.decision === 'approved') {
          statements.insertIntent.run(decided.resume_intent_id,
            checkpointCid, decided.resolution_cid, current.run_id,
            current.prepare_attempt_id);
        }
        fault('submitResolution');
        return {kind: 'committed', decided} as const;
      });
      if (outcome.kind === 'conflict') fail('CheckpointResolutionConflict');
      if (outcome.kind === 'cancelled') fail('CheckpointCancelled');
      if (outcome.kind === 'expired') fail('CheckpointExpired');
      if (outcome.kind === 'approval_expired') fail('ApprovalExpired');
      // Both a committed and a duplicate decision have a durable Resolution.
      const stored = statements.resolution.get(checkpointCid)!;
      const intent = statements.intentByCheckpoint.get(checkpointCid);
      return Object.freeze({
        outcome: outcome.kind,
        decision: stored.decision,
        resolutionCid: stored.resolution_cid,
        verifiedResolutionCid: stored.verified_resolution_cid,
        verifiedResolutionWire: stored.verified_resolution_wire,
        resumeIntentId: intent?.intent_id ?? null,
        ...(row.run_id !== null ?
          {runState: projectRunState(row.run_id)} :
          {preparation: projectPreparation(row.prepare_attempt_id)}),
      });
    },

    // Answer several pending Checkpoints in one Host operation. Each item is
    // admitted independently as the answer to its own exact Checkpoint: its
    // own Resolution, authentication, attestation and one atomic commit of
    // Resolution, closure, transition and resume intent. An item never
    // covers another Checkpoint, and an invalid item neither blocks nor alters
    // the others. Results are per item, in input order.
    async submitResolutions(items: readonly ResolutionSubmission[]) {
      alive();
      if (!Array.isArray(items) || items.length === 0) {
        fail('InvalidResolutionSubmission');
      }
      const results = [];
      for (const item of items) {
        const checkpointCid = item?.checkpointCid;
        try {
          const committed = await this.submitResolution(item);
          results.push(Object.freeze({
            checkpointCid,
            status: committed.outcome === 'duplicate' ? 'duplicate' : 'committed',
            decision: committed.decision,
            resolutionCid: committed.resolutionCid,
            resumeIntentId: committed.resumeIntentId,
          }));
        } catch (error) {
          const failure = error as ResolutionFailure | null | undefined;
          if (failure?.code === 'CheckpointJournalClosed') throw error;
          const status = ({
            CheckpointResolutionConflict: 'conflicting',
            CheckpointExpired: 'expired',
            CheckpointCancelled: 'cancelled',
            ModelRunCancelled: 'cancelled',
          } as Readonly<Record<string, string>>)[failure?.code as string] ?? 'invalid';
          results.push(Object.freeze({
            checkpointCid,
            status,
            reason: String(failure?.code ?? 'InvalidResolutionSubmission'),
            ...(failure?.cause !== undefined ?
              {detail: String(failure.cause?.message ?? failure.cause)} : {}),
          }));
        }
      }
      return Object.freeze(results);
    },

    // Admit an immediate delegated permit or reject against the exact
    // Checkpoint body the Host would persist if it deferred. Nothing is
    // persisted: no Checkpoint, no waiting state and no resume intent. The
    // returned verified Resolution is the decision evidence the Host retains
    // with the permitted or rejected unit.
    async admitImmediateResolution({
      body, resolutionWire, approvalEvidenceWire = '', authorities, modelCallSet,
    }: Pick<CheckpointInput, 'body' | 'authorities' | 'modelCallSet'> &
      Pick<ResolutionSubmission, 'resolutionWire' | 'approvalEvidenceWire'>) {
      alive();
      if (!text(resolutionWire) || typeof approvalEvidenceWire !== 'string') {
        fail('InvalidResolutionSubmission');
      }
      const bodyWire = typeof body === 'string' ? body : JSON.stringify(body);
      const subject = sealBody(bodyWire);
      const inventory = modelCalls.prepare(subject, modelCallSet);
      const reviewers = authoritiesJson(authorities);
      const verifiedAt = iso(now());
      const authJson = await authenticate(subject.checkpoint_wire,
        resolutionWire, approvalEvidenceWire);
      const admitted = core<Readonly<{attestation_preimage: string}>>(resolutionCall('resolutionAdmitImmediate', subject, [
        bodyWire, resolutionWire, approvalEvidenceWire, authJson, reviewers,
        verifiedAt,
      ], {inventory}), 'InvalidResolution');
      const attestation = await attest(admitted.attestation_preimage);
      const sealed = core<ResolutionSeal>(resolutionCall('resolutionSealImmediate', subject, [
        bodyWire, resolutionWire, approvalEvidenceWire, authJson, reviewers,
        verifiedAt, attestation.hostKeyId, attestation.signature,
      ], {inventory}), 'InvalidResolution');
      let modelGrantExpiresAt;
      if (inventory !== undefined && sealed.decision === 'approved') {
        modelGrantExpiresAt = transaction.run(() => {
          const originals = modelCalls.immediateOriginals(inventory);
          return confirmModelGrant(originals, subject.checkpoint_wire,
            sealed.verified_resolution_wire, {...inventory.inventory,
              resolutionCid: sealed.resolution_cid,
              verifiedResolutionCid: sealed.verified_resolution_cid}, now(), true);
        });
      }
      return Object.freeze({
        checkpointCid: sealed.checkpoint_cid,
        decision: sealed.decision,
        resolutionCid: sealed.resolution_cid,
        verifiedResolutionCid: sealed.verified_resolution_cid,
        verifiedResolutionWire: sealed.verified_resolution_wire,
        ...(modelGrantExpiresAt === undefined ? {} : {modelGrantExpiresAt}),
      });
    },

    // Claim the unique resume intent of a Run with a strictly higher fencing
    // generation. Bound authorization-context and environment-binding CIDs
    // are revalidated here, before any continuation dispatch. If they no
    // longer revalidate, nothing is dispatched and the Run exits `resuming`
    // to `failed`, or to `needs_reconciliation` over `unknownEffects`, with
    // terminal_error.code ACTQL_E_RESUME_REVALIDATION_FAILED.
    claimResume(runId: string, {claimant, leaseMs, binding, unknownEffects = [],
      preserveStarted = false, expectedCheckpointCid,
      settleEffectRevalidation = false}: RunClaimRequest) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      if (typeof preserveStarted !== 'boolean') fail('InvalidResumeClaim');
      if (typeof settleEffectRevalidation !== 'boolean') fail('InvalidResumeClaim');
      if (expectedCheckpointCid !== undefined && !text(expectedCheckpointCid)) fail('InvalidResumeClaim');
      const current = bindingJson(binding);
      const unknown = effectsJson(unknownEffects);
      const at = now();
      return transaction.run(() => {
        const intent = statements.intent.get(runId);
        if (intent === undefined) fail('ResumeIntentNotFound');
        if (expectedCheckpointCid !== undefined &&
            intent.checkpoint_cid !== expectedCheckpointCid) {
          return Object.freeze({action: 'changed'});
        }
        // Keep an earlier protected start unresolved when the caller requests
        // preservation, before changed-binding invalidation can end it.
        if (preserveStarted && intent.state !== 'completed' &&
            hasStartedLocked(intent)) {
          return Object.freeze({action: 'admitted'});
        }
        const settlement = statements.effectSettlement.get(intent.intent_id);
        const {checkpoint, decided} = claimLocked(intent, claimant, at,
          current, leaseMs, settleEffectRevalidation || settlement !== undefined,
          settlement !== undefined);
        if (decided.action === 'busy' || decided.action === 'completed') {
          return Object.freeze({action: decided.action});
        }
        const run = statements.run.get(runId);
        if (run?.status !== 'resuming') fail('RunStateConflict');
        const artifact = JSON.parse(checkpoint.checkpoint_wire) as CheckpointArtifact;
        if (settlement !== undefined && Number(settlement.generation) !== Number(intent.generation)) {
          fail('EffectSettlementJournalCorrupt');
        }
        if (decided.action === 'settlement') {
          if (artifact.kind !== 'effect_set') fail('InvalidEffectSettlementClaim');
          // Core has checked the lease/clock bounds and selected the next
          // generation. Retain that fence for observation only. This durable
          // marker is sticky across lease takeover and configuration changes.
          changed(statements.claimIntent.run(decided.generation, claimant,
            decided.lease_expires_ms, intent.intent_id, intent.generation), 'ResumeClaimStale');
          statements.recordEffectSettlement.run(intent.intent_id, decided.generation);
          fault('claimEffectSettlement');
          return Object.freeze({action: 'settlement',
            claim: Object.freeze({intentId: intent.intent_id, runId, claimant,
              generation: decided.generation, leaseExpiresMs: decided.lease_expires_ms}),
            checkpointCid: checkpoint.checkpoint_cid,
            continuationStateCid: artifact.continuation_state_cid,
            runDefinitionCid: artifact.run_definition_cid,
            subject: Object.freeze({...artifact.subject}),
            terminalErrorCode: 'ACTQL_E_RESUME_REVALIDATION_FAILED'});
        }
        if (decided.action === 'invalidated') {
          // Entered Model calls cannot be reduced to an unsent failed Run.
          // Valid replacement claims still recover later proven-unsent slots;
          // aggregate completion remains the Model continuation owner's job.
          if (modelHasEnteredLocked(checkpoint, intent)) {
            return Object.freeze({action: 'admitted'});
          }
          const failed = core<RevalidationExit>(runtime.revalidationFailedState(runId, iso(at),
            run.declared_results_json, unknown), 'InvalidResumeClaim');
          transitionAllowed('resuming', failed.run_status);
          changed(statements.completeIntent.run(decided.generation, claimant,
            failed.run_status, iso(at), intent.intent_id, intent.generation),
          'ResumeClaimStale');
          changed(statements.moveRun.run(failed.run_status, iso(at), '',
            failed.run_state_wire, runId, run.version, 'resuming'),
          'RunStateConflict');
          fault('claimResume');
          return Object.freeze({
            action: 'invalidated',
            runStatus: failed.run_status,
            terminalErrorCode: failed.terminal_error_code,
          });
        }
        changed(statements.claimIntent.run(decided.generation, claimant,
          decided.lease_expires_ms, intent.intent_id, intent.generation),
        'ResumeClaimStale');
        fault('claimResume');
        return Object.freeze({
          action: 'claimed',
          claim: Object.freeze({
            intentId: intent.intent_id,
            runId,
            claimant,
            generation: decided.generation,
            leaseExpiresMs: decided.lease_expires_ms,
          }),
          checkpointCid: checkpoint.checkpoint_cid,
          continuationStateCid: artifact.continuation_state_cid,
          runDefinitionCid: artifact.run_definition_cid,
          subject: Object.freeze({...artifact.subject}),
        });
      });
    },

    // Claim the resume intent of an approved preparation Checkpoint. A failed
    // revalidation dispatches nothing and ends the preparation without
    // creating a Run.
    claimPreparationResume(prepareAttemptId: string, {claimant, leaseMs, binding}: ClaimRequest) {
      alive();
      if (!text(prepareAttemptId)) fail('InvalidPrepareAttemptId');
      const current = bindingJson(binding);
      const at = now();
      return transaction.run(() => {
        const intent = statements.preparationIntent.get(prepareAttemptId);
        if (intent === undefined) fail('ResumeIntentNotFound');
        const {checkpoint, decided} = claimLocked(intent, claimant, at,
          current, leaseMs);
        if (decided.action === 'busy' || decided.action === 'completed') {
          return Object.freeze({action: decided.action});
        }
        const preparation = statements.preparation.get(prepareAttemptId);
        if (preparation?.status !== 'resuming') {
          fail('PreparationStateConflict');
        }
        if (decided.action === 'invalidated') {
          const code = runtime.resumeRevalidationFailedCode();
          changed(statements.completeIntent.run(decided.generation, claimant,
            'revalidation_failed', iso(at), intent.intent_id,
            intent.generation), 'ResumeClaimStale');
          changed(statements.movePreparation.run('ended', iso(at), '', '',
            'revalidation_failed', code, prepareAttemptId, preparation.version,
            'resuming'), 'PreparationStateConflict');
          fault('claimResume');
          return Object.freeze({
            action: 'invalidated',
            runCreated: false,
            terminalErrorCode: code,
          });
        }
        changed(statements.claimIntent.run(decided.generation, claimant,
          decided.lease_expires_ms, intent.intent_id, intent.generation),
        'ResumeClaimStale');
        fault('claimResume');
        const artifact = JSON.parse(checkpoint.checkpoint_wire) as CheckpointArtifact;
        return Object.freeze({
          action: 'claimed',
          claim: Object.freeze({
            intentId: intent.intent_id,
            prepareAttemptId,
            claimant,
            generation: decided.generation,
            leaseExpiresMs: decided.lease_expires_ms,
          }),
          checkpointCid: checkpoint.checkpoint_cid,
          continuationStateCid: artifact.continuation_state_cid,
          subject: Object.freeze({...artifact.subject}),
        });
      });
    },

    renewResume<Selected extends Claim>(claim: Selected, leaseMs: number) {
      alive();
      if (!Number.isSafeInteger(leaseMs) || leaseMs <= 0) fail('InvalidLease');
      const at = now();
      return transaction.run(() => {
        const intent = fenced(claim, at);
        changed(statements.renewIntent.run(at + leaseMs, intent.intent_id,
          claim.generation, claim.claimant), 'ResumeClaimStale');
        return Object.freeze({...claim, leaseExpiresMs: at + leaseMs});
      });
    },

    // The same original lease fence, observed without updating its row.
    assertResumeClaimCurrent(claim: ClaimIdentity) {
      alive();
      transaction.run(() => { fenced(claim, now()); });
    },

    // Committed resume state of one Checkpoint, read from journal rows only:
    // its current resume intent (state, claimant, generation, lease), the
    // committed Resolution and the requested claims bound when it deferred.
    // Undefined when the Checkpoint has no resume intent.
    currentResume(checkpointCid: string) {
      alive();
      if (!text(checkpointCid)) fail('InvalidCheckpointReference');
      const intent = statements.intentByCheckpoint.get(checkpointCid);
      if (intent === undefined) return undefined;
      const checkpoint = statements.checkpoint.get(checkpointCid)!;
      const stored = statements.resolution.get(checkpointCid);
      return Object.freeze({
        checkpointCid,
        intentId: intent.intent_id,
        runId: intent.run_id,
        prepareAttemptId: intent.prepare_attempt_id,
        state: intent.state,
        claimant: intent.claimant,
        generation: Number(intent.generation),
        leaseExpiresMs: Number(intent.lease_expires_ms),
        resolutionCid: intent.resolution_cid,
        decision: stored?.decision ?? null,
        verifiedResolutionCid: stored?.verified_resolution_cid ?? null,
        closure: checkpoint.closure,
        decisionSubjectCid: checkpoint.decision_subject_cid === '' ? null :
          checkpoint.decision_subject_cid,
        requestedClaims: Object.freeze(
          JSON.parse(checkpoint.requested_claims_json) as string[]),
      });
    },

    // Read the original intent's durable physical-start fact without
    // claiming or invalidating it under a possibly changed installation.
    // A later Host may reconcile that work, never infer a fresh start from
    // the absence of an in-process operation or from retained input rows.
    hasStartedResume(checkpointCid: string) {
      alive();
      if (!text(checkpointCid)) fail('InvalidCheckpointReference');
      return transaction.run(() => {
        const intent = statements.intentByCheckpoint.get(checkpointCid);
        return intent !== undefined && intent.state !== 'completed' &&
          hasStartedLocked(intent);
      });
    },

    // Trusted Host observation of this exact Run's committed publication or
    // durable Effect reconciliation receipt state from its original owner.
    // This settles a lost completion response, not execution authorization:
    // no callback, claim or dispatch is returned. Atomically fencing any old
    // claimant prevents further work after the already-observed outcome.
    settleObservedEffectResume(reference: string, runDefinitionCid: string, runStateWire: string) {
      alive();
      const admitted = core<RunStateResult>(runtime.runStateAdmit(runStateWire), 'InvalidRunState');
      if (!['succeeded', 'needs_reconciliation'].includes(admitted.status) ||
          admitted.checkpoint_cid !== null) {
        fail('InvalidRunState');
      }
      const at = iso(now());
      return transaction.run(() => {
        const checkpoint = rowFor(reference);
        if (checkpoint === undefined) fail('CheckpointNotFound');
        const artifact = JSON.parse(checkpoint.checkpoint_wire) as CheckpointArtifact;
        if (artifact.run_definition_cid !== runDefinitionCid ||
            artifact.kind !== 'read_access' || checkpoint.run_id !== admitted.run_id) {
          fail('CheckpointRunMismatch');
        }
        const intent = statements.intentByCheckpoint.get(checkpoint.checkpoint_cid);
        const run = statements.run.get(checkpoint.run_id);
        if (intent === undefined || intent.state === 'completed' || run?.status !== 'resuming') {
          return Object.freeze({outcome: 'not_resuming'});
        }
        transitionAllowed('resuming', admitted.status);
        changed(statements.completeIntent.run(Number(intent.generation) + 1,
          'effect-outcome-observer', admitted.status, at, intent.intent_id,
          intent.generation), 'ResumeClaimStale');
        changed(statements.moveRun.run(admitted.status, at, '', admitted.run_state_wire,
          run.run_id, run.version, 'resuming'), 'RunStateConflict');
        fault('settleObservedEffectResume');
        return Object.freeze({outcome: admitted.status, runId: run.run_id});
      });
    },

    // The committed approval of one resolved Checkpoint and whether its own
    // permission is still current at the Host trusted time. Read from
    // committed rows only; used for approvals an attempt answered earlier
    // than the Checkpoint its current claim resumes (each approval is
    // checked on its own, never through a later one).
    committedApprovalAt(checkpointCid: string) {
      alive();
      if (!text(checkpointCid)) fail('InvalidCheckpointReference');
      const atIso = iso(now());
      const checkpoint = statements.checkpoint.get(checkpointCid);
      const stored = statements.resolution.get(checkpointCid);
      if (checkpoint?.closure !== 'resolved' || stored?.decision !== 'approved' ||
          checkpoint.resolution_cid !== stored.resolution_cid) {
        fail('ResolutionNotCommitted');
      }
      const approval = core<Approval>(runtime.resumedApprovalAt(
        stored.verified_resolution_wire, atIso), 'ResolutionNotCommitted');
      if (approval.checkpoint_cid !== checkpointCid ||
          approval.resolution_cid !== stored.resolution_cid) {
        fail('ResolutionNotCommitted');
      }
      return Object.freeze({
        checkpointCid,
        resolutionCid: stored.resolution_cid,
        authority: approval.reviewer_id,
        expiresAt: approval.expires_at,
        current: approval.current === true,
        checkedAt: atIso,
      });
    },

    // Admission of one resumed protected dispatch at the Host trusted time.
    // `claim` names the claim the caller holds ({intentId, claimant,
    // generation}); it is an identity to check, never an authority record.
    // Everything else comes from committed rows: the intent must be the
    // current intent of its Checkpoint (and of its Run or preparation) and
    // the claim must pass the MoonBit fence (current claimant, generation
    // and unexpired lease); the Checkpoint must be resolved by the intent's
    // committed approved Resolution, the Run or preparation `resuming`, and
    // the approval's own permission current. Returns the bound admission;
    // throws a coded error otherwise. Nothing is recorded.
    admitResume(claim: ClaimIdentity, {checkpointCid}: Pick<EntryOptions, 'checkpointCid'> = {}) {
      alive();
      const at = now();
      return transaction.run(() => {
        const admission = admissionLocked(claim, checkpointCid, at);
        if (admission.kind !== 'model_invocation') return admission;
        const {inventory, originals} = modelCalls.grantContext(admission.checkpointCid);
        const modelGrantExpiresAt = confirmEntryGrant(originals, inventory, admission, at);
        return Object.freeze({...admission, modelGrantExpiresAt});
      });
    },

    // The same admission, taken immediately before the protected send and
    // recorded durably: at most one protected dispatch start per claim
    // generation of an intent. A second entry with the same generation, by
    // this or any other process, is `ResumeAdmissionConsumed`.
    //
    // A lease handoff cannot admit two starts: once an earlier claim
    // generation of this (still uncompleted) intent entered a protected
    // dispatch, its physical outcome is unknown to a later claimant, so a
    // fresh start is refused with `PriorAdmissionUnresolved` (the error
    // carries `priorAdmission`). The later claimant may only take the
    // physical reconciliation path (`enterResumedReconciliation`) or leave
    // the intent to a later completion. `dispatchIdentity` is the durable
    // identity of the protected send when it has one (a remote dispatch the
    // Site deduplicates); it is recorded for reconciliation.
    enterResumedDispatch(claim: ClaimIdentity, {checkpointCid, resolutionCid,
      dispatchIdentity}: EntryOptions = {}) {
      alive();
      const identity = admissionIdentity(dispatchIdentity);
      const at = now();
      return transaction.run(() => {
        const admission = enteredLocked(claim, checkpointCid, resolutionCid,
          at);
        const prior = statements.priorAdmission.get(admission.intentId,
          admission.generation);
        if (prior !== undefined) {
          throw Object.assign(new Error('PriorAdmissionUnresolved'), {
            code: 'PriorAdmissionUnresolved',
            priorAdmission: priorAdmissionView(prior),
          });
        }
        changed(statements.enterAdmission.run(admission.intentId,
          admission.generation, admission.claimant, admission.admittedAt,
          'start', identity), 'ResumeAdmissionConsumed');
        fault('enterResumedDispatch');
        return Object.freeze({...admission, mode: 'start',
          dispatchIdentity: identity === '' ? null : identity});
      });
    },

    // Physical reconciliation of an earlier generation's protected dispatch
    // by the current live claim (same fence, approval validity and single
    // entry per generation as `enterResumedDispatch`). Admitted only when an
    // earlier generation started a dispatch with a recorded durable identity
    // and `dispatchIdentity` is exactly that identity: the caller re-sends
    // the same durable dispatch (which the receiver deduplicates), never a
    // second distinct one. A prior start with no durable identity (a Local
    // provider session) cannot be reconciled here: `PriorAdmissionUnresolved`.
    enterResumedReconciliation(claim: ClaimIdentity, {checkpointCid, resolutionCid,
      dispatchIdentity}: EntryOptions = {}) {
      alive();
      const identity = admissionIdentity(dispatchIdentity);
      if (identity === '') fail('ReconciliationIdentityRequired');
      const at = now();
      return transaction.run(() => {
        const admission = enteredLocked(claim, checkpointCid, resolutionCid,
          at);
        const prior = statements.priorAdmission.get(admission.intentId,
          admission.generation);
        if (prior === undefined) fail('NoPriorAdmission');
        if (prior.dispatch_identity === '') {
          throw Object.assign(new Error('PriorAdmissionUnresolved'), {
            code: 'PriorAdmissionUnresolved',
            priorAdmission: priorAdmissionView(prior),
          });
        }
        if (prior.dispatch_identity !== identity) {
          fail('ReconciliationIdentityMismatch');
        }
        changed(statements.enterAdmission.run(admission.intentId,
          admission.generation, admission.claimant, admission.admittedAt,
          'reconcile', identity), 'ResumeAdmissionConsumed');
        fault('enterResumedReconciliation');
        return Object.freeze({...admission, mode: 'reconcile',
          dispatchIdentity: identity,
          priorAdmission: priorAdmissionView(prior)});
      });
    },

    // Complete the resume intent together with the resumed continuation's
    // exit. For a Run the outcome is one of: {runStateWire} for a
    // continuation-issued state, {status: 'failed' | 'cancelled'}, or
    // {checkpoint: {...}} for the next Checkpoint of the same Run. For a
    // preparation it is one of: {run: {runId, status}} to create the Run
    // (status 'preparing' or 'running'), {status: 'failed' | 'cancelled'} to
    // end without a Run, or {checkpoint: {...}} for the next preparation
    // Checkpoint of the same attempt.
    completeResume(claim: Claim, outcome: ResumeOutcome) {
      alive();
      if (!text(claim?.intentId) || !text(claim?.claimant) ||
          !Number.isSafeInteger(claim?.generation)) {
        fail('ResumeClaimStale');
      }
      if (text(claim.prepareAttemptId)) {
        return completePreparation(claim as PreparationClaim, outcome);
      }
      let target;
      let runStateWire = '';
      let next: ReturnType<typeof nextCheckpoint> | undefined;
      if (outcome?.checkpoint !== undefined) {
        next = nextCheckpoint(outcome.checkpoint);
        if (next.sealed.run_id !== claim.runId) fail('CheckpointRunMismatch');
        target = 'waiting_checkpoint';
      } else if (text(outcome?.runStateWire)) {
        const view = core<RunStateResult>(runtime.runStateAdmit(outcome.runStateWire),
          'InvalidRunState');
        if (view.run_id !== claim.runId || view.checkpoint_cid !== null) {
          fail('InvalidRunState');
        }
        target = view.status;
        runStateWire = view.run_state_wire;
      } else if (outcome?.status === 'failed' ||
          outcome?.status === 'cancelled') {
        target = outcome.status;
      } else {
        fail('InvalidResumeOutcome');
      }
      if (!runtime.resumeCompletionAllowed(target)) {
        fail('RunTransitionRejected');
      }
      const at = now();
      const atIso = iso(at);
      transaction.run(() => {
        const intent = fenced(claim, at);
        const settlement = statements.effectSettlement.get(intent.intent_id);
        if (settlement !== undefined && !runtime.effectSettlementCompletionAllowed(target)) {
          fail('InvalidEffectSettlementOutcome');
        }
        const run = statements.run.get(intent.run_id);
        if (run?.status !== 'resuming') fail('RunStateConflict');
        if (settlement !== undefined) {
          // Preserve the refusal that restricted this claim. Unknown members
          // come from the already admitted common Run state, never a new
          // dispatch or an adapter's reinterpretation of historical rows.
          const unknown = target === 'needs_reconciliation'
            ? JSON.parse(runStateWire).next_action.effects : [];
          const refused = core<RevalidationExit>(runtime.revalidationFailedState(run.run_id,
            atIso, run.declared_results_json, effectsJson(unknown)),
          'InvalidEffectSettlementOutcome');
          if (refused.run_status !== target) fail('InvalidEffectSettlementOutcome');
          runStateWire = refused.run_state_wire;
        }
        transitionAllowed('resuming', target);
        changed(statements.completeIntent.run(claim.generation,
          claim.claimant, target, atIso, intent.intent_id, claim.generation),
        'ResumeClaimStale');
        let checkpointCid = '';
        if (next !== undefined) {
          if (statements.checkpoint.get(next.sealed.checkpoint_cid) !==
              undefined) {
            fail('CheckpointConflict');
          }
          insertCheckpoint(next.sealed, next.reviewers, next.bound,
            next.subject, next.claims, next.configuration, atIso);
          if (outcome.attachImmediateModelCallSet === true && next.modelCallSet === undefined) {
            fail('ModelImmediateInventoryRequired');
          }
          modelCalls.registerLocked(next.sealed, next.modelCallSet, atIso,
            false, outcome.attachImmediateModelCallSet === true);
          checkpointCid = next.sealed.checkpoint_cid;
        }
        changed(statements.moveRun.run(target, atIso, checkpointCid,
          runStateWire, run.run_id, run.version, 'resuming'),
        'RunStateConflict');
        fault('completeResume');
      });
      if (next !== undefined) return waitingAfterCommit(next.sealed);
      return projectRunState(claim.runId!);
    },

    // Close every open Checkpoint whose expiration has been reached: a
    // waiting preparation ends and a waiting Run is cancelled, without
    // dispatch, or moves to `needs_reconciliation` when the Host reports
    // unknown earlier Effect outcomes for it. `unknownEffects` is a function
    // of the Run id or an object keyed by Run id.
    expire({unknownEffects}: Readonly<{unknownEffects?: UnknownEffects}> = {}) {
      alive();
      const at = iso(now());
      return transaction.run(() => {
        const expired = [];
        for (const row of statements.pending.all()) {
          const result = core<Readonly<{expired: boolean}>>(runtime.checkpointExpiredAt(row.checkpoint_wire,
            at), 'CheckpointJournalCorrupt');
          if (result.expired) {
            expireLocked(row, at, row.run_id === null ? '[]'
              : unknownOf(unknownEffects, row.run_id));
            expired.push(row.checkpoint_cid);
          }
        }
        fault('expire');
        return expired;
      });
    },

    close() {
      closeControl.close();
    },
  });

  function rowFor(reference: string) {
    if (!text(reference)) fail('InvalidCheckpointReference');
    let row = statements.checkpoint.get(reference);
    if (row === undefined) {
      const rows = statements.checkpointById.all(reference);
      if (rows.length > 1) fail('AmbiguousCheckpointReference');
      row = rows[0];
    }
    return row;
  }

  function enteredLocked(claim: ClaimIdentity, checkpointCid: string | undefined, resolutionCid: string | undefined, at: number) {
    const admission = admissionLocked(claim, checkpointCid, at);
    if (resolutionCid !== undefined &&
        resolutionCid !== admission.resolutionCid) {
      fail('ResolutionNotCommitted');
    }
    return admission;
  }

  function admissionLocked(claim: ClaimIdentity, checkpointCid: string | undefined, at: number) {
    if (!text(claim?.intentId) || !text(claim?.claimant) ||
        !Number.isSafeInteger(claim?.generation)) {
      fail('ResumeNotClaimed');
    }
    const intent = statements.intentById.get(claim.intentId);
    if (intent === undefined) fail('ResumeIntentNotFound');
    if (checkpointCid !== undefined && intent.checkpoint_cid !== checkpointCid) {
      fail('ResumeIntentMismatch');
    }
    const latest = intent.run_id !== null
      ? statements.intent.get(intent.run_id)
      : statements.preparationIntent.get(intent.prepare_attempt_id);
    if (latest?.intent_id !== intent.intent_id) fail('ResumeIntentMismatch');
    const fence = core<Fence>(runtime.resumeFenceDecide(intentView(intent),
      claim.claimant, claim.generation, at), 'ResumeClaimStale');
    if (fence.action !== 'current') fail('ResumeClaimStale');
    if (statements.effectSettlement.get(intent.intent_id) !== undefined) {
      fail('ResumeSettlementOnly');
    }
    const checkpoint = statements.checkpoint.get(intent.checkpoint_cid);
    const stored = statements.resolution.get(intent.checkpoint_cid);
    if (checkpoint?.closure !== 'resolved' || stored?.decision !== 'approved' ||
        checkpoint.resolution_cid !== intent.resolution_cid ||
        stored.resolution_cid !== intent.resolution_cid) {
      fail('ResolutionNotCommitted');
    }
    const owner = intent.run_id !== null
      ? statements.run.get(intent.run_id)
      : statements.preparation.get(intent.prepare_attempt_id);
    if (owner?.status !== 'resuming') fail('RunNotResuming');
    const atIso = iso(at);
    const approval = core<Approval>(runtime.resumedApprovalAt(
      stored.verified_resolution_wire, atIso), 'ResolutionNotCommitted');
    if (approval.checkpoint_cid !== intent.checkpoint_cid ||
        approval.resolution_cid !== intent.resolution_cid ||
        approval.verified_resolution_cid !== stored.verified_resolution_cid) {
      fail('ResolutionNotCommitted');
    }
    if (approval.current !== true) fail('ApprovalExpired');
    const artifact = JSON.parse(checkpoint.checkpoint_wire) as CheckpointArtifact;
    return Object.freeze({
      intentId: intent.intent_id,
      checkpointCid: intent.checkpoint_cid,
      runId: intent.run_id,
      prepareAttemptId: intent.prepare_attempt_id,
      resolutionCid: intent.resolution_cid,
      verifiedResolutionCid: stored.verified_resolution_cid,
      claimant: intent.claimant,
      generation: Number(intent.generation),
      leaseExpiresMs: Number(intent.lease_expires_ms),
      kind: artifact.kind,
      requiredArtifactCid: artifact.required_artifact.artifact_cid,
      decisionSubjectCid: checkpoint.decision_subject_cid === '' ? null :
        checkpoint.decision_subject_cid,
      requestedClaims: Object.freeze(
        JSON.parse(checkpoint.requested_claims_json) as string[]),
      configurationCid: checkpoint.configuration_cid === '' ? null :
        checkpoint.configuration_cid,
      observedClaims: Object.freeze([...approval.claims]),
      authority: approval.reviewer_id,
      approvalExpiresAt: approval.expires_at,
      admittedAt: atIso,
    });
  }

  // Only the current, unexpired claimant may complete an intent.
  function fenced(claim: ClaimIdentity, at: number) {
    const intent = statements.intentById.get(claim?.intentId ?? '');
    if (intent === undefined) fail('ResumeClaimStale');
    const fence = core<Fence>(runtime.resumeFenceDecide(intentView(intent),
      claim.claimant, claim.generation, at), 'ResumeClaimStale');
    if (fence.action !== 'current') fail('ResumeClaimStale');
    return intent;
  }

  function completePreparation(claim: PreparationClaim, outcome: ResumeOutcome) {
    let next: ReturnType<typeof nextCheckpoint> | undefined;
    let run: ResumeOutcome['run'];
    let ended: ResumeOutcome['status'];
    if (outcome?.checkpoint !== undefined) {
      next = nextCheckpoint(outcome.checkpoint);
      if (next.sealed.prepare_attempt_id !== claim.prepareAttemptId) {
        fail('CheckpointPreparationMismatch');
      }
    } else if (outcome?.run !== undefined) {
      if (!text(outcome.run.runId) ||
          !['preparing', 'running'].includes(outcome.run.status)) {
        fail('InvalidResumeOutcome');
      }
      run = outcome.run;
    } else if (outcome?.status === 'failed' ||
        outcome?.status === 'cancelled') {
      ended = outcome.status;
    } else {
      fail('InvalidResumeOutcome');
    }
    const at = now();
    const atIso = iso(at);
    transaction.run(() => {
      const intent = fenced(claim, at);
      const preparation = statements.preparation.get(intent.prepare_attempt_id);
      if (preparation?.status !== 'resuming') fail('PreparationStateConflict');
      const exit = next !== undefined ? 'waiting_checkpoint' :
        run !== undefined ? 'run_created' : ended!;
      changed(statements.completeIntent.run(claim.generation, claim.claimant,
        exit, atIso, intent.intent_id, claim.generation), 'ResumeClaimStale');
      const move = (status: string, checkpointCid: string, runId: string, reason: string) => changed(
        statements.movePreparation.run(status, atIso, checkpointCid, runId,
          reason, '', preparation.prepare_attempt_id, preparation.version,
          'resuming'), 'PreparationStateConflict');
      if (next !== undefined) {
        if (statements.checkpoint.get(next.sealed.checkpoint_cid) !==
            undefined) {
          fail('CheckpointConflict');
        }
        move('waiting_checkpoint', next.sealed.checkpoint_cid, '', '');
        insertCheckpoint(next.sealed, next.reviewers, next.bound, next.subject,
          next.claims, next.configuration, atIso);
        modelCalls.registerLocked(next.sealed, next.modelCallSet, atIso);
      } else if (run !== undefined) {
        // The approved preparation continuation creates the Run.
        if (statements.run.get(run.runId) !== undefined) {
          fail('RunAlreadyTracked');
        }
        statements.insertRun.run(run.runId, run.status, atIso,
          preparation.declared_results_json, '');
        move('run_created', '', run.runId, '');
      } else {
        move('ended', '', '', ended!);
      }
      fault('completeResume');
    });
    if (next !== undefined) return waitingAfterCommit(next.sealed);
    return Object.freeze({
      preparation: projectPreparation(claim.prepareAttemptId),
      ...(run !== undefined ? {runState: projectRunState(run.runId)} : {}),
    });
  }
  } catch (error) {
    throwSqliteInitializationFailure(database, error, 'checkpoint-journal');
  }
}
