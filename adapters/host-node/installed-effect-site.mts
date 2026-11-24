// Composition of one installed Effect Site with the common captured Run owner.
// Provider hooks supply only Preview/current-use and physical dispatch facts;
// the common Effect application, receipt, publication and recovery order stays
// here. The Host's durable Run-start and Checkpoint owners remain external.
import {completeCapturedEffectRun, completeRecoveredEffectRun,
  completeInterruptedEffectRun, settleRefusedEffectRun} from
  './entry.mjs';
import {releaseCompletedRunPreparedPayloads,
  suspendCompletedEffectfulComputation, isCompletedEffectfulPublicationCleanupFailure} from
  '../host-common/completed-run-publication.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {ExecutionAuthorizationError} from
  '../host-common/authorization-gate.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {projectEffectApplication, projectEffectPreflightFailure} from '../host-common/observation.mjs';
import {isEffectApplyPreflightRejection, effectApplyPreflightFailureObservation} from './effect-run-apply.mjs';
import {isEffectPreparationRefusal} from '../host-common/effect-preparation-result.mjs';
import {isEffectCaptureRecoveryRefusal} from './effect-run-recovery.mjs';
import {assertEffectTargetReadBinding, isEffectTargetReadRefusal} from
  './effect-target-read-continuation.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {retainFirstAndLatestCleanupError} from '../host-common/managed-failure.mjs';
import {runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {INSTALLED_EFFECT_CHECKPOINT_LIMITS} from
  '../host-common/installed-checkpoint-codec-limits.mjs';

import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {createEffectPreviewControls} from '../host-common/runtime-effect-preview-control.mjs';
import type {applyCapturedEffectSet, applyRecoveredEffectSet} from './effect-run-apply.mjs';
import type {recoverAdmittedEffectRun} from './effect-run-recovery.mjs';
import type {effectTargetReadContinuation} from './effect-target-read-continuation.mjs';
import type {EffectTarget} from './client-checkpoint-admission-inputs.mjs';
import type {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';
import type {ControlWork} from './installed-effect-plan.mjs';
import type {createInstalledRowEffect} from './installed-row-effect.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type Current = () => SynchronousRuntimeData;
type Completion = Parameters<typeof completeCapturedEffectRun>[0];
type Result = Awaited<ReturnType<typeof completeCapturedEffectRun | typeof settleRefusedEffectRun>>;
type Authorization = NonNullable<Completion['apply']['authorization']>;
type Publication = Completion['publication'];
type PreviewControl = ReturnType<typeof createEffectPreviewControls>['effectPreviewControls'];
type Control = Publication['control'] & Pick<PreviewControl, 'projectEffectComputationReview'> &
  Readonly<{// The Common constructor returns a synchronous optional ExecutionCapacity.
    effectComputationReviewConstructionCapacity(...args: Parameters<
      PreviewControl['effectComputationReviewConstructionCapacity']>): SynchronousRuntimeData;
    runDefinitionRunId(definition: unknown): string;
    effectComputationPreviewWire(preview: Publication['preview']): string}>;
type Runtime = Completion['apply']['moon'] & Readonly<{
  clientProgramEffectCompilationUnitId(compilation: unknown): string;
  clientProgramEffectCompilationResultNames(compilation: unknown): readonly string[];
  clientProgramRequestedEffectStop(intent: unknown, referenceWire: string, identity: unknown,
    allowed: unknown, definition: unknown, capturedInputs: unknown): unknown;
  clientProgramRequestedEffectStopContinuation(original: unknown, providerWire: string,
    targetBindingWire: string | undefined, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
}>;
type TargetReads = Awaited<ReturnType<typeof effectTargetReadContinuation>>;
type Ref = Parameters<typeof projectEffectApplication>[1];
type Recovered = Awaited<ReturnType<typeof recoverAdmittedEffectRun>>;
type RecoveryResources = NonNullable<Recovered['recoveryResources']> &
  Readonly<{status(): Readonly<{pending: boolean}>}>;
type FailureStatus = Readonly<{pending: boolean; errors: readonly unknown[]}>;
type CleanupHandle = Readonly<{status(): FailureStatus; retry(): Promise<FailureStatus>}>;
type CompletionFailure = Error & {outcome?: 'unknown'; uncertain?: true;
  cleanupPending?: boolean; cleanupErrors?: readonly unknown[]; cleanupHandle?: CleanupHandle};
type Cleanup = Readonly<{close(): unknown; cleanup?(): unknown; cleanupPending?(): boolean}>;
type Physical = Required<Cleanup>;
type Construction = Readonly<{close(): unknown; status(): Readonly<{pending: boolean}>;
  releaseInputs?(): unknown}>;
type Stage = Readonly<{
  preview: Publication['preview']; computation: Publication['computation'];
  storedResults: Publication['storedResults']; publication: Publication;
  receipt: Completion['receipt']; scopes: Authorization['scopes'];
  continuationWire: string; dispose?(): unknown; releaseInputs?(): unknown;
  requestedStop?: unknown; assertRequestedStopCurrent?: Current; cleanupOwner?: Physical;
}>;
type CapturedStage = Stage & Readonly<{apply: Completion['apply'] & Parameters<typeof applyCapturedEffectSet>[0]}>;
type RecoveredStage = Stage & Readonly<{apply: Completion['apply'] & Parameters<typeof applyRecoveredEffectSet>[0]}>;
type OwnedStage = CapturedStage | RecoveredStage;
type ReviewArgs = Parameters<PreviewControl['projectEffectComputationReview']>;
type Gate = Authorization['gate'] & Cleanup;
type AuthorizeFacts = Readonly<{
  runId: string; runDefinitionCid: string; runDefinition: unknown; unitId: string;
  declaredResults: readonly string[]; reviewWire: string; continuationWire: string;
  projectReview(policy: ReviewArgs[1], limits: ReviewArgs[2]): SynchronousRuntimeData;
  requestedStop?: unknown; assertRequestedStopCurrent?: Current;
  beforeDefer(): void | Promise<void>; targetReads?: TargetReads;
}>;
type Checkpoint = Readonly<{runId: string; checkpointCid: string;
  subject?: Readonly<{kind?: string; unit_id?: string}>}>;
type Claim = Readonly<{intentId: string; runId: string; claimant: string; generation: number}>;
type Resume = NonNullable<Authorization['resume']>;
type Claimed = Extract<NonNullable<Resume['claim']>, {action: 'claimed'}> &
  Readonly<{claim: Claim}>;
type Attempt = Claimed | Readonly<{action: 'settlement'; claim: Claim}> |
  Readonly<{action: 'invalidated' | 'admitted' | 'busy' | 'completed' | 'changed'}>;
type ResumeBinding = Parameters<ReturnType<typeof openSqliteCheckpointJournal>['claimResume']>[1]['binding'];
type CheckpointJournal = Readonly<{
  claimResume(runId: string, options: Readonly<{claimant: string; leaseMs: number; binding: ResumeBinding;
    expectedCheckpointCid: string; settleEffectRevalidation: true}>): Attempt;
  admitResume(claim: Claim, options: Readonly<{checkpointCid: string}>): unknown;
  completeResume(claim: Claim, result: Readonly<{status?: 'failed'; runStateWire?: string}>): unknown;
  refuseUnsentEffectResume(checkpointCid: string, runDefinitionCid: string): Readonly<{outcome: string}>;
  finishRun(runId: string, result: Readonly<{from: 'needs_reconciliation'; status: string;
    runStateWire?: string}>): unknown;
}>;
type Continuation = Readonly<{version: string; run_definition_cid: string; unit_id: string;
  preview_cid: string; target_read_binding?: unknown; requested_stop?: unknown}>;
type ObservedRun = Readonly<{status: string; control?: unknown}>;
type Reconciliation = Extract<Result, {status: 'needs_reconciliation'}>;
type Facts = Readonly<{
  ref: Ref; moon: Runtime; control: Control; store: Publication['store'];
  compilation?: unknown; continuation?: Continuation; view?: Checkpoint;
  retained?: Readonly<{resultNames?: readonly string[]; runDefinition: unknown}>;
  runDefinition?: unknown; identity?: unknown; allowed?: unknown; definition?: unknown;
  originalSubmittedIntent?: Readonly<{intent: unknown; referenceWire: string; assertCurrent: Current}>;
  signal?: AbortSignal; targetReads?: TargetReads; observation?: unknown;
  managedEffect?: Readonly<{controlConstruction?: ControlWork}>;
  effectAuthorization?(input: AuthorizeFacts): Awaitable<Gate>;
  recordReconciliation(ref: Ref, selected: Readonly<{issuedSet: Reconciliation['issuedSet'];
    ledger: OwnedStage['apply']['ledger']; preview: Stage['preview']}>): ObservedRun;
  observeRun(input: Readonly<{ref: Ref}>): Awaitable<ObservedRun>;
  retainExecution(owner: ReturnType<typeof cleanupCustody>): void;
  beginPhysicalWork?(): void; assertContinuationCurrent?: Current;
}>;
type Execution = NonNullable<Publication['execution']> & Physical;
type Opened = Readonly<{execution?: Physical; checkedHost?: unknown; cleanupOwner?: Physical;
  contentOwner?: object; publicationPlan?: unknown; status?: string; checkpoint?: unknown;
  modelUnknown?: boolean}>;
type CapturedFacts = Facts & Readonly<{
  assertUpdateSelectionCurrent?: Current; observePreEffectFailure?(): void;
  publicationPlan?: unknown; contentOwner?: object;
  openComputation(ports: Readonly<{retainComputationOwner(owner: Physical): void}>):
    Awaitable<Opened | null | undefined>;
}>;
type RecoveredFacts = Facts & Readonly<{
  view: Checkpoint; reconciliationOnly?: boolean; checkpointJournal: CheckpointJournal;
  checkpointBinding: ResumeBinding;
  recoverCapture(ports: Readonly<{signal: AbortSignal | undefined;
    retainRecoveryResources(owner: RecoveryResources): void}>): Awaitable<AdmittedRecovery>;
  prepareTargetReads?(claim: Claimed): Awaitable<TargetReads | undefined>;
}>;
type AdmittedRecovery = Omit<Recovered, 'recoveryResources'> & Readonly<{recoveryResources?: RecoveryResources}>;
type RecoverySelection = RecoveredFacts & Readonly<{recovered: AdmittedRecovery}>;
type SiteOptions = Readonly<{
  environmentWire: string; privateEvidenceKey?: Uint8Array;
  prepareCaptured(facts: CapturedFacts & Readonly<{execution: Execution; checkedHost: object;
    retainConstructionOwner(owner: Construction): void}>): Awaitable<CapturedStage>;
  prepareRecovered(facts: RecoverySelection & Readonly<{retainRecoveryOwner(owner: Physical): void;
    retainConstructionOwner(owner: Construction): void}>): Awaitable<RecoveredStage>;
  prepareManagedPlan?: Awaited<ReturnType<typeof createInstalledRowEffect>>['prepareManagedPlan'];
  validateRecoveredInstallation?(facts: RecoverySelection): unknown;
  queryTableBindings?: unknown; queryTableWriteAccesses?: unknown;
  targetReadInventory?(facts: Facts & Readonly<{assertUpdateSelectionCurrent?: Current}>): unknown;
  targetReadAuthorization?: EffectTarget['authorization'];
  claimant?: string; leaseMs?: number;
}>;

const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};

// Only interrupted completion composes these two failures. Keep both exact
// originals, including immutable objects and primitive rejection reasons.
const failureData = (value: unknown, key: PropertyKey): unknown => {
  try {
    const field = Object.getOwnPropertyDescriptor(value as object, key);
    return field && Object.hasOwn(field, 'value') ? field.value : undefined;
  } catch { return undefined; }
};
function interruptedCompletionFailure(primary: unknown, completion: unknown) {
  const code = failureData(primary, 'code');
  const failure: CompletionFailure = Object.assign(new AggregateError([primary, completion],
    'InstalledEffectCompletionFailed', {cause: primary}), {
    code: typeof code === 'string' ? code : 'InstalledEffectCompletionFailed',
    primaryFailure: primary, completionFailure: completion,
  });
  const reasons = [primary, completion];
  if (reasons.some(value => failureData(value, 'outcome') === 'unknown')) failure.outcome = 'unknown';
  if (reasons.some(value => failureData(value, 'uncertain') === true)) failure.uncertain = true;
  const owners: {handle: unknown; status: unknown; retry: unknown; released: boolean}[] = [];
  const seen = new Set<unknown>();
  const errors: unknown[] = [];
  const record = (error: unknown) => retainFirstAndLatestCleanupError(errors, error);
  for (const reason of reasons) {
    if (failureData(reason, 'cleanupPending') !== true) continue;
    const handle = failureData(reason, 'cleanupHandle');
    if (handle !== undefined && seen.has(handle)) continue;
    seen.add(handle);
    let status: unknown, retry: unknown;
    try {
      status = (handle as Partial<CleanupHandle> | null | undefined)?.status;
      retry = (handle as Partial<CleanupHandle> | null | undefined)?.retry;
    }
    catch (error) { record(error); }
    owners.push({handle, status, retry, released: false});
  }
  if (owners.length === 0) return failure;
  const status = () => {
    for (const owner of owners) {
      if (owner.released) continue;
      try {
        if (typeof owner.status !== 'function' || typeof owner.retry !== 'function') {
          throw new Error('InstalledEffectCompletionCleanupOwnerMissing');
        }
        const state = Reflect.apply(owner.status, owner.handle, []);
        if (Array.isArray(state?.errors)) {
          for (const error of state.errors) record(error);
        }
        owner.released = state?.pending === false;
      } catch (error) { record(error); }
    }
    return Object.freeze({pending: owners.some(owner => !owner.released),
      errors: Object.freeze([...errors])});
  };
  failure.cleanupPending = true;
  let flight: Promise<FailureStatus> | undefined;
  failure.cleanupHandle = Object.freeze({status, retry() {
    if (flight !== undefined) return flight;
    flight = Promise.resolve().then(async () => {
      status();
      for (const owner of owners) {
        if (owner.released || typeof owner.retry !== 'function') continue;
        try { await Reflect.apply(owner.retry, owner.handle, []); }
        catch (error) { record(error); }
      }
      const result = status();
      failure.cleanupPending = result.pending;
      failure.cleanupErrors = result.errors;
      return result;
    }).finally(() => {flight = undefined;});
    return flight;
  }});
  return failure;
}

function ownedStage(stage: OwnedStage, code: string) {
  if (stage === null || typeof stage !== 'object' ||
      !stage.preview || !stage.computation || !stage.storedResults ||
      !stage.apply || !stage.receipt || !stage.publication ||
      !Array.isArray(stage.scopes) || stage.scopes.length === 0 ||
      typeof stage.continuationWire !== 'string' ||
      stage.dispose !== undefined && typeof stage.dispose !== 'function' ||
      stage.releaseInputs !== undefined && typeof stage.releaseInputs !== 'function') {
    fail(code);
  }
  return stage;
}

function effectUnitId(facts: Facts) {
  const unit = facts.compilation === undefined
    ? facts.continuation?.unit_id
    : facts.moon.clientProgramEffectCompilationUnitId(facts.compilation);
  if (typeof unit !== 'string' || !unit ||
      facts.compilation === undefined &&
        (facts.view?.subject?.kind !== 'run_unit' ||
          facts.view.subject.unit_id !== unit)) {
    fail('InstalledEffectContinuationMismatch');
  }
  return unit;
}

function requestedStopOriginal(facts: Facts, stage: OwnedStage) {
  if (stage.requestedStop !== undefined) {
    stage.assertRequestedStopCurrent!();
    return stage.requestedStop;
  }
  const original = facts.originalSubmittedIntent;
  if (original === undefined) return undefined;
  original.assertCurrent();
  return runtimeUnboxedReferenceOption(checked(
    facts.moon.clientProgramRequestedEffectStop(original.intent,
      original.referenceWire, facts.identity, facts.allowed, facts.definition,
      stage.apply.capturedInputs)));
}

function continuation(facts: Facts, stage: OwnedStage, settlementOnly = false, requestedStop?: unknown) {
  let provider: unknown;
  try { provider = JSON.parse(stage.continuationWire); }
  catch { fail('InvalidInstalledEffectContinuation'); }
  let targetBinding: unknown = facts.targetReads?.captureBinding();
  if (settlementOnly && facts.continuation?.target_read_binding !== undefined) {
    // This authenticated historical binding identifies the original capture.
    // Observing that capture does not reopen its target-read authorization.
    targetBinding = facts.continuation.target_read_binding;
    assertEffectTargetReadBinding(targetBinding);
  }
  if (requestedStop !== undefined) {
    return checked(facts.moon.clientProgramRequestedEffectStopContinuation(
      requestedStop, stage.continuationWire,
      targetBinding === undefined ? undefined : canonicalValueJson(targetBinding, {dataKeys:true}),
      INSTALLED_EFFECT_CHECKPOINT_LIMITS.maxWireBytes,
      INSTALLED_EFFECT_CHECKPOINT_LIMITS.maxNodes,
      INSTALLED_EFFECT_CHECKPOINT_LIMITS.maxDepth)) as string;
  }
  return canonicalValueJson({version: 'actql-installed-effect-continuation/0.1',
    run_definition_cid: facts.ref.runDefinitionCid,
    unit_id: effectUnitId(facts),
    preview_cid: facts.control.effectComputationPreviewSemanticCid(
      stage.preview),
    ...(targetBinding === undefined ? {} : {target_read_binding: targetBinding}),
    provider}, {dataKeys: true});
}

function checkContinuation(facts: Facts, stage: OwnedStage, settlementOnly = false) {
  const original = facts.continuation?.requested_stop === undefined ? undefined
    : requestedStopOriginal(facts, stage);
  if (facts.continuation?.requested_stop !== undefined && original === undefined) {
    fail('RequestedEffectStopUnavailable');
  }
  const expected = continuation(facts, stage, settlementOnly, original);
  if (canonicalValueJson(facts.continuation, {dataKeys: true}) !== expected) {
    fail('InstalledEffectContinuationMismatch');
  }
}

function checkContinuationBinding(facts: Facts, recovered: Recovered['computation']) {
  effectUnitId(facts);
  const saved = facts.continuation;
  if (saved?.version !== 'actql-installed-effect-continuation/0.1' ||
      saved.run_definition_cid !== facts.ref.runDefinitionCid ||
      saved.preview_cid !== facts.control.effectComputationPreviewSemanticCid(
        recovered.preview)) {
    fail('InstalledEffectContinuationMismatch');
  }
}

function authorization(facts: Facts, stage: OwnedStage, beforeDefer: AuthorizeFacts['beforeDefer']) {
  const declaredResults = facts.compilation === undefined
    ? facts.retained?.resultNames
    : facts.moon.clientProgramEffectCompilationResultNames(
      facts.compilation);
  if (!Array.isArray(declaredResults) ||
      declaredResults.some(name => typeof name !== 'string' || !name) ||
      new Set(declaredResults).size !== declaredResults.length) {
    fail('InvalidInstalledEffectResultInventory');
  }
  const requestedStop = requestedStopOriginal(facts, stage);
  if (requestedStop !== undefined && typeof facts.effectAuthorization !== 'function') {
    fail('RequestedEffectStopUnavailable');
  }
  return facts.effectAuthorization!({
    runId: facts.control.runDefinitionRunId(facts.retained?.runDefinition ??
      facts.runDefinition),
    runDefinitionCid: facts.ref.runDefinitionCid,
    runDefinition: facts.retained?.runDefinition ?? facts.runDefinition,
    unitId: effectUnitId(facts),
    declaredResults,
    reviewWire: facts.control.effectComputationPreviewWire(stage.preview),
    // Capture the same actual Preview, not its public CID or a restored DATA
    // substitute. The Checkpoint Owner supplies its original policy/claims.
    projectReview: (policy, limits) => {
      const input = stage.publication.contractLimits;
      const args: ReviewArgs = [stage.preview, policy, limits, input];
      const construction = facts.managedEffect?.controlConstruction;
      if (construction === undefined) {
        return facts.control.projectEffectComputationReview(...args);
      }
      // Reuse the SAME Run's fixed control frame for bounded preflight, then
      // prepay the native parser/encoder peak before entering projection.
      const capacity = construction(facts.control,
        facts.control.effectComputationReviewConstructionCapacity,
        [stage.preview, limits, input]);
      if (capacity === undefined) fail('EffectReviewConstructionUnavailable');
      return construction(facts.control,
        facts.control.projectEffectComputationReview, args, capacity);
    },
    continuationWire: continuation(facts, stage, false, requestedStop),
    ...(requestedStop === undefined ? {} : {requestedStop,
      assertRequestedStopCurrent: stage.assertRequestedStopCurrent ??
        (() => facts.originalSubmittedIntent!.assertCurrent())}),
    beforeDefer,
    targetReads: facts.targetReads,
  });
}

function completionOptions(stage: OwnedStage, gate: Gate | undefined, signal: AbortSignal | undefined,
  resume?: Resume, beforeDispatch?: Current): Completion {
  // Observation and refused settlement never call the authorization gate.
  const apply = {...stage.apply, authorization: Object.freeze({gate: gate!,
    scopes: stage.scopes,
    ...(resume === undefined ? {} : {resume})})};
  return Object.freeze({apply, receipt: stage.receipt,
    publication: stage.publication, signal, beforeDispatch});
}

function noEffectRowWasSent(options: Completion) {
  const {apply, receipt} = options;
  const control = runtimeCore(apply.moon).effectApplicationControl;
  return receipt.members.every(member => member.rowOwners.every(owner => {
    const entry = apply.ledger.currentAdmitted(
      control.logicalItemLocatorCid(owner.claim.locator));
    // The physical owner records a dispatch claim before invoking a provider.
    // An absent head and a Prepared intent are both unattempted states.
    return entry === undefined || control.ledgerEntryStateCode(entry) === 0;
  }));
}

function terminalPreSendRefusal(error: unknown, options: Completion) {
  return (error instanceof ExecutionAuthorizationError &&
      error.authorization?.action === 'deny' ||
    isEffectApplyPreflightRejection(error) || isEffectPreparationRefusal(error) ||
      isEffectTargetReadRefusal(error)) &&
      noEffectRowWasSent(options);
}

function finishStatus(result: Result) {
  if (result.status === 'waiting') {
    if ((result.progress as Readonly<{checkpoint?: unknown}> | undefined)?.checkpoint === undefined) {
      fail('InstalledEffectReadDeferralUnsupported');
    }
    return Object.freeze({status: 'waiting_checkpoint', result});
  }
  return Object.freeze({status: result.status === 'failed'
    ? 'failed_effect_set' : result.status, result});
}

function cleanupCustody(physical: Physical | undefined, requirePhysical = false) {
  let stage: OwnedStage | undefined;
  const authorizations: {owner: Cleanup; closeAttempted: boolean; released: boolean}[] = [];
  let physicalCloseAttempted = false;
  let physicalReleased = false;
  let disposed = false;
  let release: (() => unknown) | undefined;
  let released = false;
  let inputsReleased = false;
  let recoveryResources: RecoveryResources | undefined;
  let constructionOwner: Construction | undefined;
  const releaseAuthorizations = async () => {
    let failure;
    for (const state of authorizations) {
      if (state.released) continue;
      try {
        // A full child owns recovery through cleanup. A close-only child has a
        // synchronous, retryable close: false or an exception retains custody.
        const recover = state.closeAttempted &&
          typeof state.owner.cleanup === 'function';
        state.closeAttempted = true;
        const result = await (recover ? state.owner.cleanup!() : state.owner.close());
        state.released = result !== false &&
          (typeof state.owner.cleanupPending !== 'function' ||
            state.owner.cleanupPending() === false);
      } catch (error) { failure ??= error; }
    }
    if (failure !== undefined) throw failure;
    return authorizations.every(state => state.released);
  };
  const releaseInputs = async () => {
    if (typeof constructionOwner?.releaseInputs === 'function' &&
        await constructionOwner.releaseInputs() !== true) {
      fail('InstalledEffectConstructionCleanupPending');
    }
    if (!inputsReleased && typeof stage?.releaseInputs === 'function') {
      await stage.releaseInputs();
      inputsReleased = true;
    }
  };
  return Object.freeze({
    expectPhysical() { requirePhysical = true; },
    retainAuthorization(owner: Cleanup) {
      if (authorizations.some(state => state.owner === owner) ||
          typeof owner?.close !== 'function') {
        fail('InstalledEffectCleanupOwnerAlreadySet');
      }
      authorizations.push({owner, closeAttempted: false, released: false});
    },
    attachPhysical(value: Physical) {
      if (physical !== undefined && physical !== value ||
          typeof value?.close !== 'function' ||
          typeof value?.cleanup !== 'function' ||
          typeof value?.cleanupPending !== 'function') {
        fail('InstalledEffectCleanupOwnerAlreadySet');
      }
      physical = value;
    },
    attach(value: OwnedStage) {
      if (stage !== undefined) fail('InstalledEffectCleanupOwnerAlreadySet');
      stage = value;
    },
    requireRelease(operation: () => unknown) {
      if (release !== undefined || typeof operation !== 'function') {
        fail('InstalledEffectCleanupOwnerAlreadySet');
      }
      release = operation;
    },
    retainConstruction(original: Construction) {
      if (constructionOwner !== undefined || typeof original?.close !== 'function' ||
          typeof original?.status !== 'function' || original.releaseInputs !== undefined &&
          typeof original.releaseInputs !== 'function') fail('InstalledEffectCleanupOwnerAlreadySet');
      constructionOwner = original;
    },
    retainRecoveryResources(original: RecoveryResources) {
      if (recoveryResources === original) return;
      if (recoveryResources !== undefined || typeof original?.close !== 'function' ||
          typeof original?.status !== 'function') fail('InstalledEffectCleanupOwnerAlreadySet');
      recoveryResources = original;
    },
    closeAuthorizations: releaseAuthorizations,
    async close() {
      // Effect execution has stopped before dispatch custody closes. Its
      // consumer pins must go before the borrowed Compute output can reclaim.
      let failure;
      try { await releaseAuthorizations(); } catch (error) { failure = error; }
      try { await releaseInputs(); } catch (error) { failure ??= error; }
      if (physical !== undefined && !physicalCloseAttempted && !physicalReleased) {
        physicalCloseAttempted = true;
        try { await physical.close(); } catch (error) { failure ??= error; }
      }
      if (failure !== undefined) throw failure;
    },
    async cleanup() {
      // Opening may have begun physical work before returning an owner.
      // Missing custody is not evidence that the operation stopped.
      if (!await releaseAuthorizations()) return false;
      if (requirePhysical && !physicalReleased && physical === undefined) return false;
      await releaseInputs();
      if (physical !== undefined && !physicalReleased) {
        const cleaned = await physical.cleanup();
        if (cleaned === false || physical.cleanupPending() !== false) return false;
        physicalReleased = true;
      }
      if (release !== undefined && !released) {
        await release();
        released = true;
      }
      if (!disposed && typeof stage?.dispose === 'function') {
        await stage.dispose();
      }
      disposed = true;
      // Actual inputs/authorizations/physical children and completed payloads
      // are gone before their capture decode allowance can be returned. Cut
      // this custody's strong aliases before that consuming return callback.
      stage = release = physical = undefined;
      authorizations.length = 0;
      if (constructionOwner !== undefined) {
        if (await constructionOwner.close() !== true || constructionOwner.status().pending !== false) return false;
        constructionOwner = undefined;
      }
      if (recoveryResources !== undefined) {
        if (await recoveryResources.close() !== true) return false;
        recoveryResources = undefined;
      }
      return true;
    },
    cleanupPending() {
      return authorizations.some(state => !state.released) ||
        !inputsReleased && typeof stage?.releaseInputs === 'function' ||
        requirePhysical && !physicalReleased && physical === undefined ||
        physical !== undefined && !physicalReleased ||
        release !== undefined && !released ||
        !disposed && stage?.dispose !== undefined || recoveryResources !== undefined || constructionOwner !== undefined;
    },
  });
}

function recordUnknown(facts: Facts, result: Result, stage: OwnedStage) {
  if (result.status !== 'needs_reconciliation') return undefined;
  return facts.recordReconciliation(facts.ref, {issuedSet: result.issuedSet,
    ledger: stage.apply.ledger, preview: stage.preview});
}

async function currentRunState(facts: Facts, result: Result, stage: OwnedStage) {
  const unknown = recordUnknown(facts, result, stage);
  if (unknown !== undefined) return unknown;
  const observed = await facts.observeRun({ref: facts.ref});
  const {control: _control, ...state} = observed;
  return state;
}

// The installed Host owns this factory. `prepareCaptured` and
// `prepareRecovered` are connector-supplied projections over the same common
// owners; neither hook may decide that an unknown send succeeded or restart
// Compute. The recovered hook receives the exact durable capture only.
export function createInstalledEffectSite({environmentWire,
  prepareCaptured, prepareRecovered, prepareManagedPlan, validateRecoveredInstallation, privateEvidenceKey,
  queryTableBindings,
  queryTableWriteAccesses,
  targetReadInventory, targetReadAuthorization,
  claimant = 'installed-effect-host', leaseMs = 60_000}: SiteOptions) {
  if (typeof environmentWire !== 'string' || !environmentWire ||
      typeof prepareCaptured !== 'function' ||
      typeof prepareRecovered !== 'function' ||
      (prepareManagedPlan !== undefined && typeof prepareManagedPlan !== 'function') ||
      (validateRecoveredInstallation !== undefined && typeof validateRecoveredInstallation !== 'function') ||
      targetReadInventory !== undefined && typeof targetReadInventory !== 'function' ||
      (targetReadInventory === undefined) !== (targetReadAuthorization === undefined) ||
      privateEvidenceKey !== undefined &&
        (!(privateEvidenceKey instanceof Uint8Array) ||
          privateEvidenceKey.byteLength !== 32) ||
      typeof claimant !== 'string' || !claimant ||
      !Number.isSafeInteger(leaseMs) || leaseMs < 1) {
    fail('InvalidInstalledEffectSiteFactory');
  }
  return Object.freeze({
    environmentWire,
    // Retain the SAME installed implementation callback. Selection and its
    // nominal Plan/current/capacity checks stay with the original Run owner.
    prepareManagedPlan,
    queryTableBindings,
    queryTableWriteAccesses,
    targetReadInventory, targetReadAuthorization,
    privateEvidenceKey: privateEvidenceKey === undefined ? undefined :
      Uint8Array.from(privateEvidenceKey),
    async execute(facts: CapturedFacts) {
      const {moon, retainExecution, signal} = facts;
      signal?.throwIfAborted();
      facts.assertUpdateSelectionCurrent?.();
      if (typeof facts.openComputation !== 'function') {
        fail('InvalidInstalledEffectComputationPort');
      }
      const custody = cleanupCustody(undefined);
      retainExecution(custody);
      if (facts.targetReads !== undefined) {
        custody.retainAuthorization(facts.targetReads);
        let readiness;
        try { readiness = await facts.targetReads.prepare(); }
        catch (error) { facts.observePreEffectFailure?.(); throw error; }
        if (readiness.status === 'waiting_checkpoint') return readiness;
        facts.assertUpdateSelectionCurrent?.();
      }
      custody.expectPhysical();
      facts.beginPhysicalWork?.();
      let opened: Opened | null | undefined;
      try {
        facts.assertUpdateSelectionCurrent?.();
        facts.targetReads?.enterComputation();
        opened = await facts.openComputation(Object.freeze({
          retainComputationOwner: (owner: Physical) => custody.attachPhysical(owner),
        }));
      } catch (failure) {
        // No Effect provider callback has run. The same failure remains the
        // primary cause; the dispatch owner publishes this terminal outcome
        // only after the physical owner confirms stop and cleanup.
        facts.observePreEffectFailure?.();
        throw failure;
      }
      if (opened?.status === 'waiting_checkpoint' && opened.checkpoint !== undefined) {
        // The Source owner has persisted its exact continuation and retained
        // inputs. Waiting is neither a failed computation nor Effect approval.
        return Object.freeze({status: 'waiting_checkpoint', checkpoint: opened.checkpoint});
      }
      if (opened?.status === 'needs_reconciliation' && opened.modelUnknown === true) {
        // An entered Model attempt is neither an Effect failure nor a
        // fabricated Effect ledger. Keep its original physical custody and
        // stop before Preview/Effect authorization or any Effect write.
        let originalFailure;
        try {
          const primary = Object.getOwnPropertyDescriptor(opened, 'primaryFailure');
          if (primary !== undefined && Object.hasOwn(primary, 'value')) {
            originalFailure = {primaryFailure: primary.value};
          }
        } catch { /* Failure inspection cannot change the existing Unknown. */ }
        return Object.freeze({status: 'needs_reconciliation', modelUnknown: true,
          ...originalFailure});
      }
      const {execution, checkedHost} = (opened ?? {}) as Opened & {execution?: Execution; checkedHost?: object};
      if (execution === undefined || checkedHost === undefined) {
        fail('InvalidInstalledEffectComputationPort');
      }
      // A failed Preview or Store operation still belongs to the dispatch
      // cleanup owner. Retain before any provider callback can fail.
      custody.attachPhysical(opened!.cleanupOwner ?? execution);
      // This original belongs to the completed computation's retained cleanup
      // owner. It is not a holding-CID resolver supplied by the caller.
      const contentOwner = opened!.contentOwner;
      // Acquired Runs can issue their Observation Set only after acquisition.
      // The installed Host supplies this plan from the same checked owner.
      if (opened!.publicationPlan !== undefined) {
        facts = Object.freeze({...facts,
          publicationPlan: opened!.publicationPlan});
      }
      let stage: CapturedStage;
      try {
        facts.assertUpdateSelectionCurrent?.();
        const capturedFacts = {...facts, execution, checkedHost,
          retainConstructionOwner: (owner: Construction) => custody.retainConstruction(owner)};
        delete capturedFacts.contentOwner;
        if (contentOwner !== undefined) capturedFacts.contentOwner = contentOwner;
        stage = await prepareCaptured(Object.freeze(capturedFacts));
      } catch (error) {
        // Preparation has no Effect dispatch permit. A checked refusal is
        // definitive here, but observation/transport failures are not. The
        // dispatch owner still waits for physical stop and cleanup before
        // recording the outcome; this does not release that responsibility.
        if (isEffectPreparationRefusal(error) || isEffectTargetReadRefusal(error) ||
            error instanceof ExecutionAuthorizationError &&
              error.authorization?.action === 'deny') {
          facts.observePreEffectFailure?.();
        }
        throw error;
      }
      custody.attach(stage);
      // Capture has transferred the prepared Result handles to this owner.
      // Register their cleanup before validation or any fallible apply work.
      // Until a terminal outcome selects retirement, release local handles
      // only. Existing Host owners still decide durable retention/retirement
      // and transfer; cleanup does not reclassify the application failure.
      let releaseMode = 'retain';
      const storedResults = stage?.storedResults;
      if (storedResults !== undefined) {
        custody.requireRelease(() => releaseMode === 'retire'
          ? releaseCompletedRunPreparedPayloads(storedResults, facts.control)
          : suspendCompletedEffectfulComputation({execution,
            store: facts.store, storedResults, control: facts.control,
            computation: stage.computation, preview: stage.preview}));
      }
      ownedStage(stage, 'InvalidInstalledEffectCapture');
      if (stage.publication.execution !== execution ||
          stage.publication.store !== facts.store ||
          stage.publication.control !== facts.control ||
          stage.publication.storedResults !== stage.storedResults ||
          stage.publication.computation !== stage.computation ||
          stage.publication.preview !== stage.preview ||
          stage.apply.moon !== moon ||
          stage.receipt.commonMoon !== moon) {
        fail('InvalidInstalledEffectCapture');
      }
      let failed = false;
      try {
        facts.assertUpdateSelectionCurrent?.();
        const gate = await authorization(facts, stage, async () => {
          facts.assertUpdateSelectionCurrent?.();
          // The approved continuation must be able to reconstruct exact
          // claims after process loss. These are durable intents, not send
          // claims; the resumed path still repeats current admission.
          stage.apply.ledger.prepareCapturedSetIntents(
            stage.apply.capturedInputs, stage.apply.members,
            stage.apply.maxFrontierWork);
          await suspendCompletedEffectfulComputation({execution,
            store: facts.store, storedResults: stage.storedResults,
            control: facts.control, computation: stage.computation,
            preview: stage.preview});
          facts.assertUpdateSelectionCurrent?.();
        });
        custody.retainAuthorization(gate);
        facts.assertUpdateSelectionCurrent?.();
        const options = completionOptions(stage, gate, signal, undefined,
          facts.assertContinuationCurrent);
        let result;
        try { result = await completeCapturedEffectRun(options); }
        catch (error) {
          // Preserve only the completed owner's exact terminal cleanup
          // failure. Provider/apply cleanup still needs interrupted completion.
          if (isCompletedEffectfulPublicationCleanupFailure(options.publication, error)) throw error;
          try { result = await completeInterruptedEffectRun(options, false); }
          catch (completionError) {
            if (failureData(completionError, 'code') === 'EffectRunNoAttemptedSend') {
              projectEffectPreflightFailure(facts.observation, facts.ref, effectApplyPreflightFailureObservation(error));
              if (terminalPreSendRefusal(error, options)) {
                releaseMode = 'retire';
                return Object.freeze({status: 'failed_without_effect_dispatch'});
              }
              throw error;
            }
            throw interruptedCompletionFailure(error, completionError);
          }
        }
        projectEffectApplication(facts.observation, facts.ref, result);
        if (result.status === 'needs_reconciliation') {
          await suspendCompletedEffectfulComputation({execution,
            store: facts.store, storedResults: stage.storedResults,
            control: facts.control, computation: stage.computation,
            preview: stage.preview});
        } else if (result.status === 'failed' || result.status === 'published') {
          // An idempotent publication may already have released this owner.
          // Retry with the same terminal mode, never switch back to retain.
          releaseMode = 'retire';
        }
        recordUnknown(facts, result, stage);
        return finishStatus(result);
      } catch (error) {
        failed = true;
        throw error;
      } finally {
        try { await custody.closeAuthorizations(); }
        catch (error) {
          // Cleanup remains with the retained owner. Never replace the
          // application failure or detach any cleanup handle it carries.
          if (!failed) throw error;
        }
      }
    },
    async resume(facts: RecoveredFacts) {
      const {signal, ref, view, checkpointJournal, checkpointBinding} = facts;
      const observing = facts.reconciliationOnly === true;
      signal?.throwIfAborted();
      // The Host resolves this Ref through its original request and current
      // evidence-read authority. No new physical-start claim exists here.
      // Retain custody before a fallible Store read. A failed read or busy
      // claim has not begun a new physical continuation and may be retried.
      const custody = cleanupCustody(undefined);
      facts.retainExecution(custody);
      let recovered: AdmittedRecovery | undefined;
      try { recovered = await facts.recoverCapture({signal,
        retainRecoveryResources: custody.retainRecoveryResources}); }
      catch (error) {
        if (!observing && isEffectCaptureRecoveryRefusal(error)) {
          checkpointJournal.refuseUnsentEffectResume(view.checkpointCid,
            ref.runDefinitionCid);
        }
        throw error;
      }
      let releaseMode = 'retain';
      if (recovered.recoveryResources !== undefined) {
        custody.retainRecoveryResources(recovered.recoveryResources);
      }
      custody.requireRelease(async () => {
        if (releaseMode === 'retire') {
          await releaseCompletedRunPreparedPayloads(recovered!.computation.storedResults, facts.control);
        } else {
          await suspendCompletedEffectfulComputation({execution: null,
            store: facts.store, storedResults: recovered!.computation.storedResults,
            control: facts.control, computation: recovered!.computation.computation,
            preview: recovered!.computation.preview});
        }
        recovered = undefined;
      });
      checkContinuationBinding(facts, recovered.computation);
      // Installation fencing must precede resumed target-read preparation.
      // prepareRecovered alone is too late: reads may already have occurred.
      validateRecoveredInstallation?.(Object.freeze({...facts, recovered}));
      recovered.assertUpdateSelectionCurrent?.();
      // Observing an unknown Effect is not a new approved continuation. Keep
      // the completed resume intent and physical start identity unchanged.
      const claimed = observing ? undefined : checkpointJournal.claimResume(view.runId, {
        claimant, leaseMs, binding: checkpointBinding,
        expectedCheckpointCid: view.checkpointCid,
        settleEffectRevalidation: true});
      if (claimed?.action === 'invalidated') {
        // The journal has durably failed this Run before any Effect send.
        // Transfer the recovered capture's cleanup before reporting that
        // stopped outcome to the common dispatch owner.
        releaseMode = 'retire';
        // The original Compute stop was already observed as nonterminal
        // while waiting. Its earlier observation must not be rewritten to
        // failed; the Checkpoint journal already owns the failed Run state.
        return Object.freeze({status: 'failed'});
      }
      const settling = claimed?.action === 'settlement';
      if (!observing && claimed!.action !== 'claimed' && !settling) return claimed!;
      const originalContinuationFacts = facts;
      const originalContinuationCurrent = facts.assertContinuationCurrent;
      const assertResumeCurrent = () => {
        signal?.throwIfAborted();
        if (!observing && !settling) {
          if (originalContinuationCurrent !== undefined) {
            Reflect.apply(originalContinuationCurrent, originalContinuationFacts, []);
          }
          checkpointJournal.admitResume((claimed as Claimed).claim, {checkpointCid: view.checkpointCid});
        }
      };
      facts = Object.freeze({...facts, assertContinuationCurrent: assertResumeCurrent});
      if (recovered.updateTargetSelections !== undefined) {
        const original = recovered.assertUpdateSelectionCurrent;
        recovered = Object.freeze({...recovered, assertUpdateSelectionCurrent() {
          original!();
          assertResumeCurrent();
        }});
      }
      let stage: RecoveredStage;
      try {
        recovered.assertUpdateSelectionCurrent?.();
        if (!observing && !settling && facts.prepareTargetReads !== undefined) {
          const targetReads = await facts.prepareTargetReads(claimed as Claimed);
          recovered.assertUpdateSelectionCurrent?.();
          if (targetReads !== undefined) {
            custody.retainAuthorization(targetReads);
            const readiness = await targetReads.prepare();
            recovered.assertUpdateSelectionCurrent?.();
            if (readiness.status !== 'ready') fail('InstalledEffectRepeatDeferralUnsupported');
            facts = Object.freeze({...facts, targetReads});
          }
        }
        stage = await prepareRecovered(Object.freeze({...facts,
          recovered,
          retainRecoveryOwner: (owner: Physical) => custody.attachPhysical(owner),
          retainConstructionOwner: (owner: Construction) => custody.retainConstruction(owner)}));
        recovered.assertUpdateSelectionCurrent?.();
      } catch (error) {
        if (!observing && !settling && (isEffectPreparationRefusal(error) || isEffectTargetReadRefusal(error) ||
            error instanceof ExecutionAuthorizationError &&
              error.authorization?.action === 'deny')) {
          const refused = checkpointJournal.refuseUnsentEffectResume(
            view.checkpointCid, ref.runDefinitionCid);
          if (refused.outcome === 'failed') releaseMode = 'retire';
        }
        throw error;
      }
      if (stage?.cleanupOwner !== undefined) {
        custody.attachPhysical(stage.cleanupOwner);
      }
      custody.attach(stage);
      ownedStage(stage, 'InvalidInstalledEffectRecovery');
      if (stage.publication.execution !== null ||
          stage.publication.store !== facts.store ||
          stage.publication.control !== facts.control ||
          stage.storedResults !== recovered.computation.storedResults ||
          stage.computation !== recovered.computation.computation ||
          stage.preview !== recovered.computation.preview ||
          stage.publication.storedResults !== stage.storedResults ||
          stage.publication.computation !==
            recovered.computation.computation ||
          stage.publication.preview !== stage.preview ||
          stage.apply.computation !== recovered.computation.computation ||
          stage.apply.preview !== stage.preview ||
          stage.apply.requestScope !== recovered.requestScope ||
          stage.apply.moon !== facts.moon ||
          stage.receipt.commonMoon !== facts.moon) {
        fail('InvalidInstalledEffectRecovery');
      }
      checkContinuation(facts, stage, settling || observing);
      const cleanupOwner = stage.cleanupOwner;
      if (typeof facts.retainExecution !== 'function' ||
          typeof cleanupOwner?.close !== 'function' ||
          typeof cleanupOwner.cleanup !== 'function' ||
          typeof cleanupOwner.cleanupPending !== 'function') {
        fail('InvalidInstalledEffectRecoveryOwner');
      }
      // The resumed operation has no Compute owner. Its provider must still
      // hand over physical stop and cleanup custody before any send.
      custody.attachPhysical(cleanupOwner);
      if (settling) {
        const result = await settleRefusedEffectRun(
          completionOptions(stage, undefined, signal));
        projectEffectApplication(facts.observation, facts.ref, result);
        if (result.status === 'needs_reconciliation') {
          const state = recordUnknown(facts, result, stage);
          checkpointJournal.completeResume((claimed as Claimed | Extract<Attempt, {action: 'settlement'}>).claim,
            {runStateWire: JSON.stringify(state)});
        } else {
          checkpointJournal.completeResume((claimed as Claimed | Extract<Attempt, {action: 'settlement'}>).claim, {status: 'failed'});
          releaseMode = 'retire';
        }
        return finishStatus(result);
      }
      let failed = false;
      try {
        recovered.assertUpdateSelectionCurrent?.();
        const gate = observing ? undefined : await authorization(facts, stage, () => {
          fail('InstalledEffectRepeatDeferralUnsupported');
        });
        if (gate !== undefined) custody.retainAuthorization(gate);
        recovered.assertUpdateSelectionCurrent?.();
        const completion = completionOptions(stage, gate, signal,
          observing ? undefined : Object.freeze({claim: claimed as Claimed}));
        const options = observing ? Object.freeze({...completion,
          apply: Object.freeze({...completion.apply, observationOnly: true})}) : completion;
        facts.beginPhysicalWork?.();
        let result;
        try { result = await completeRecoveredEffectRun(options); }
        catch (error) {
          // A rejected observation must not publish an old receipt as a new
          // reconciliation result. Keep uncertainty and custody for retry.
          if (observing || isCompletedEffectfulPublicationCleanupFailure(options.publication, error)) throw error;
          try { result = await completeInterruptedEffectRun(options, true); }
          catch (completionError) {
            if (failureData(completionError, 'code') === 'EffectRunNoAttemptedSend') {
              projectEffectPreflightFailure(facts.observation, facts.ref, effectApplyPreflightFailureObservation(error));
              if (terminalPreSendRefusal(error, options)) {
                checkpointJournal.completeResume((claimed as Claimed | Extract<Attempt, {action: 'settlement'}>).claim,
                  {status: 'failed'});
                releaseMode = 'retire';
                return Object.freeze({status: 'failed'});
              }
              throw error;
            }
            throw interruptedCompletionFailure(error, completionError);
          }
        }
        projectEffectApplication(facts.observation, facts.ref, result);
        if (result.status === 'waiting') {
          fail('InstalledEffectRepeatDeferralUnsupported');
        }
        if (result.status === 'published') {
          // Publication may already have released an idempotent result owner.
          // Keep later cleanup on that same terminal release mode.
          releaseMode = 'retire';
        }
        if (result.status === 'needs_reconciliation') {
          await suspendCompletedEffectfulComputation({execution: null,
            store: facts.store, storedResults: stage.storedResults,
            control: facts.control, computation: stage.computation,
            preview: stage.preview});
        }
        if (result.status === 'failed') {
          if (observing) checkpointJournal.finishRun(view.runId,
            {from: 'needs_reconciliation', status: 'failed'});
          else checkpointJournal.completeResume((claimed as Claimed | Extract<Attempt, {action: 'settlement'}>).claim, {status: 'failed'});
          releaseMode = 'retire';
        } else {
          const state = await currentRunState(facts, result, stage);
          if (observing) checkpointJournal.finishRun(view.runId,
            {from: 'needs_reconciliation', status: state.status,
              runStateWire: JSON.stringify(state)});
          else checkpointJournal.completeResume((claimed as Claimed | Extract<Attempt, {action: 'settlement'}>).claim, {
            runStateWire: JSON.stringify(state),
          });
          if (result.status !== 'needs_reconciliation') {
            releaseMode = 'retire';
          }
        }
        return finishStatus(result);
      } catch (error) {
        failed = true;
        throw error;
      } finally {
        try { await custody.closeAuthorizations(); }
        catch (error) {
          // Cleanup remains with the retained owner. Never replace the
          // application failure or detach any cleanup handle it carries.
          if (!failed) throw error;
        }
      }
    },
  });
}
