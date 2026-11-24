// Checkpoint connection of the installed Remote Host. Run acceptance on the
// Host's protected Site is a protected operation: the account decides allow,
// deny or delegate for the Host-resolved tuple (Site key, realization key,
// write). A delegated request the Host defers is held as a durable
// `prepare_attempt` Checkpoint before any Run definition, Run or Site
// dispatch exists. Answers are admitted per Checkpoint by the common
// Checkpoint journal; an approved request is resumed by this Host (on start
// and after answers), never by an in-memory callback alone and never by the
// Client. No second approval state machine lives here.
import {createPrivateKey, randomUUID, sign,
  verify} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
import {join} from 'node:path';
import {ExecutionAuthorizationError, createAuthorizationDecisionBudget,
  admitResumedDispatch} from
  '../host-common/authorization-gate.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {canonicalJson, contentCid, createLocalAuthorizationGate} from
  './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey,
  openContinuationEvidence} from './local-continuation-evidence.mjs';
import {openSqliteCheckpointJournal} from
  './sqlite-checkpoint-journal.mjs';
import {loadCheckpointRuntime} from './checkpoint-runtime.mjs';
import {createCheckpointModelCustody} from './client-checkpoint-model-custody.mjs';
import {createHeldCheckpointDeferrals} from './client-checkpoint-held-deferral.mjs';
import {createCheckpointHeldIndex, createCheckpointHeldRecovery} from './client-checkpoint-held-recovery.mjs';
import {retainInstalledHostInitializationFailure} from
  './installed-host-cleanup.mjs';
import {INSTALLED_EFFECT_CHECKPOINT_LIMITS} from
  '../host-common/installed-checkpoint-codec-limits.mjs';
import {EFFECT_TARGET_CONTINUATION, effectTargetReadScope} from
  './effect-target-read-inventory.mjs';
import {acquisitionsOf, captureEffectTargets, capturedValueCid, capturedValueWire, coded,
  computationSourceCheckpointId, fail, hex, IDENTIFIER, occurrenceIdentity, occurrenceKey,
  pluralCapture, principals, trustedReviewers, without} from './client-checkpoint-admission-inputs.mjs';
import {createCheckpointReview, MODEL_CHECKPOINT_STORAGE} from './client-checkpoint-review.mjs';
import {createCheckpointComputationSource, createCheckpointSourceSelection, createCheckpointAcquisitionAccess}
  from './client-checkpoint-computation-source.mjs';

import type {runtimeCore} from '../host-common/runtime-core.mjs';
import type {CapturedOccurrence, EffectTarget, ReviewerInput, SourceCapture} from './client-checkpoint-admission-inputs.mjs';
import type {CapturedRequest} from './client-checkpoint-held-deferral.mjs';
import type {prepareInstalledSourceCheckpointInventory} from './installed-source-inventory.mjs';

type GateOptions = NonNullable<Parameters<typeof createLocalAuthorizationGate>[0]>;
type Gate = Awaited<ReturnType<typeof createLocalAuthorizationGate>>;
type Deferral = NonNullable<GateOptions['deferral']>;
type Decision = Awaited<ReturnType<Gate['authorize']>>;
type Journal = ReturnType<typeof openSqliteCheckpointJournal>;
type JournalOptions = NonNullable<Parameters<typeof openSqliteCheckpointJournal>[1]>;
type Evidence = ReturnType<typeof openContinuationEvidence>;
type CleanupHandle = Awaited<ReturnType<typeof retainInstalledHostInitializationFailure>>['cleanupHandle'];
type EvidenceControl = Parameters<typeof openContinuationEvidence>[0]['contractControl'];
type ContractControl = ReturnType<typeof runtimeCore>['publicationControl'] & EvidenceControl;
type SourceConfiguration = Readonly<{sourceRef?: string}> &
  Pick<GateOptions, 'accountConfiguration' | 'context'>;
type SourceBinding = {source_ref?: string; configuration_cid?: string | null; context_cid?: string};
type SourceSlot = {configuration: SourceConfiguration; gate?: Gate; resumeGate?: Gate};
type OriginalSourceInventory = NonNullable<ReturnType<typeof prepareInstalledSourceCheckpointInventory>>;
type SourceInventory = Omit<OriginalSourceInventory, 'installedSources' | 'sources' | 'custody'> &
  Readonly<{installedSources: SourceSlot[]; sources: readonly SourceConfiguration[];
    custody: OriginalSourceInventory['custody'] & {cleanupIssue?: unknown}}>;
type Authorization = Pick<GateOptions, 'accountConfig' | 'accountConfiguration' | 'accountConstruction' |
  'decisionTimeoutMs' | 'maxInFlightDecisions' | 'maxRetainedDecisions' | 'decide' | 'answeringAuthorities'> & Readonly<{
  reviewers?: readonly ReviewerInput[]; hostKey?: Readonly<{
    keyId: string; privateKey: Parameters<typeof createPrivateKey>[0];
  }>;
  reviewReaders?: readonly string[]; effectRequiredClaims?: readonly string[];
  checkpointTtlMs?: number; leaseMs?: number; maxReviewBytes?: number;
  resumeAfterAnswer?: boolean; sweepPage?: number;
  observe?(name: string, detail: unknown): unknown; faultInjection?(name: string, detail: unknown): unknown;
}>;
type Installation = Readonly<{
  root: string; namespaceId: string; authorityScopeCid: string; ownerPrincipal: string;
  siteKey: string; realizationKey: string; environmentCid: string; contractControl: ContractControl;
  authorization?: Authorization | null; source?: SourceConfiguration;
  sources?: readonly SourceConfiguration[]; sourceInventory?: SourceInventory;
  effectTarget?: SourceConfiguration; effectTargets?: readonly EffectTarget[];
  modelResumeVerifier?: JournalOptions['modelResumeVerifier']; now?(): number;
}>;
type AcceptanceInput = Readonly<{
  requested: Readonly<{logicalRequestScopeCid: string; intentFingerprintCid: string}>;
  captured: CapturedRequest; signal?: AbortSignal;
}>;
type Fault = Readonly<{code?: string; message?: string}> | null | undefined;
type HeldSourceRequest = Parameters<ReturnType<typeof createHeldCheckpointDeferrals>['readDeferralFor']>[0];
type ReadDecisionInput = Omit<HeldSourceRequest, 'answering'> & Readonly<{signal?: AbortSignal}>;
type HostProbe = Readonly<{state: 'absent'} |
  {state: 'abandoned' | 'cancelled' | 'unstarted'; runId?: string} |
  {state: 'started' | 'terminal'; runId: string; status: string}>;
type ResumeInput = Readonly<{captured: CapturedRequest;
  step(name: string, detail: unknown): Promise<void>;
  renew(): void; preparationCancelled(): boolean; beforePhysicalStart(): void; started(runId: string): void;
}>;
type HostSweep = Readonly<{drain?(): unknown; sweep(): boolean | PromiseLike<boolean>}>;
type HostPort = Readonly<{
  inspect(captured: CapturedRequest): PromiseLike<HostProbe>;
  cancelRun(captured: CapturedRequest): unknown; abandon(captured: CapturedRequest): unknown;
  observe(input: Readonly<{captured: CapturedRequest; runId: string}>): string | PromiseLike<string>;
  resume(input: ResumeInput): PromiseLike<'started' | 'not_started' | Readonly<{refused: unknown}>>;
  models?: HostSweep; effects?: HostSweep;
}>;
type ReadApproval = ReturnType<ReturnType<typeof createCheckpointHeldRecovery>['admittedRead']>;
type CheckpointView = NonNullable<ReturnType<Journal['inspect']>>;
type RunUnit = Readonly<{runId: string; runDefinitionCid: string; unitId: string}>;
type JournalPort = Pick<Journal, 'persistCheckpoint' | 'submitResolution'>;
type ModelCheckpointPort = JournalPort & Readonly<{
  modelParentResume?: Readonly<{claim: Readonly<{runId: string}>; checkpointCid: string}>;
  attachModelCallSetCheckpoint?: Journal['attachModelCallSetCheckpoint'];
}>;
type ModelAuthorization = RunUnit & Readonly<{
  scopeCid: string; tuple: Parameters<Gate['authorize']>[1];
  declaredResults: readonly string[];
  modelCallSet: NonNullable<Parameters<Journal['persistCheckpoint']>[0]['modelCallSet']>;
  reviewWire: string; continuationWire: string; beforeDefer(): unknown;
  journalPort?: ModelCheckpointPort; attachImmediate?: boolean;
}>;
type EffectJournalPort = JournalPort & Pick<Journal, 'admitResume' | 'inspect' |
  'enterResumedDispatch' | 'enterResumedReconciliation'>;
type ResumeArguments = Parameters<Gate['resume']>;
type Resumption = NonNullable<ResumeArguments[2]>['resumption'];
type EffectAuthorization = RunUnit & Readonly<{
  runDefinition?: unknown; declaredResults: readonly string[];
  reviewWire: string; continuationWire: string; beforeDefer(): unknown;
  targetReads?: Readonly<{authorize(scope: AuthorizationArguments[1], options?: AuthorizationArguments[2]): Decision | PromiseLike<Decision>}>;
  requestedStop?: unknown; assertRequestedStopCurrent?(): unknown;
  projectReview?: (policy: Readonly<{authorityScopeCid: string; approvalClaims: readonly string[]; redactionPolicyCid: string}>,
    limits: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>) => Readonly<{wire: string; identity: string}>;
  journalPort?: EffectJournalPort;
}>;
type TargetAuthorization = RunUnit & Readonly<{
  inventoryCid: string; target: Parameters<typeof effectTargetReadScope>[0]['target'];
  declaredResults: readonly string[]; continuation(): string | PromiseLike<string>; beforeDefer(): unknown;
  effectTargetAuthority?: EffectTarget['authorization']; journalPort?: JournalPort;
}>;
type AuthorizationArguments = Parameters<Gate['authorize']>;
type SavedTarget = Readonly<Record<string, unknown> & {
  version?: string; run_definition_cid: string; unit_id?: string;
}>;



const MAX_REVIEW_BYTES = INSTALLED_EFFECT_CHECKPOINT_LIMITS.maxWireBytes;
const PAGE = 100;

// Account admission and signed Checkpoint continuation are distinct Host
// capabilities. An omitted signer configuration does not make an admitted
// Account invalid; any explicitly selected Checkpoint option still takes the
// existing complete validation/installation path below.
export async function installHostRunAcceptance(options: Installation) {
  const {authorization, ownerPrincipal, authorityScopeCid, namespaceId,
    siteKey, realizationKey} = options;
  const checkpointFields = ['reviewers', 'hostKey', 'reviewReaders',
    'answeringAuthorities', 'effectRequiredClaims', 'checkpointTtlMs',
    'leaseMs', 'maxReviewBytes', 'resumeAfterAnswer', 'faultInjection',
    'sweepPage', 'decide'];
  if (authorization === undefined) return Object.freeze({});
  if (authorization === null || typeof authorization !== 'object' ||
      Array.isArray(authorization) ||
      checkpointFields.some(name => name in authorization)) {
    const checkpoints = await installRemoteCheckpoints(options);
    return Object.freeze({checkpoints, runAcceptance: checkpoints});
  }
  // Diagnostics are shared with ordinary Host dispatch. A valid observer is
  // not selection of a signer, but its existing type rule still applies.
  if (authorization.observe !== undefined &&
      typeof authorization.observe !== 'function') {
    fail('InvalidRemoteHostAuthorization');
  }
  const {accountConfig, accountConfiguration, accountConstruction, decisionTimeoutMs = 30_000,
    maxInFlightDecisions = 16, maxRetainedDecisions = 1024} = authorization;
  const decisionBudget = createAuthorizationDecisionBudget({
    maxInFlightDecisions, maxRetainedDecisions});
  let gate: Gate;
  try {
    gate = await createLocalAuthorizationGate({accountConfig, accountConstruction,
      accountConfiguration, principal: ownerPrincipal, decisionTimeoutMs,
      decisionBudget});
  } catch (cause) {
    decisionBudget.close();
    throw cause;
  }
  const tuple = Object.freeze({connection: siteKey, resource: realizationKey,
    operation: 'write'});
  let stopped = false;
  const stop = () => {
    stopped = true;
    gate.close();
    decisionBudget.close();
  };
  const runAcceptance = Object.freeze({
    async acceptRun({requested, captured, signal}: AcceptanceInput) {
      if (stopped) fail('ExecutionAuthorizationStopped');
      if (captured.principalId !== ownerPrincipal) fail('ClientConnectionDenied');
      const subject = Object.freeze({
        version: 'actql-remote-run-acceptance-request/0.1',
        authority_scope_cid: authorityScopeCid, namespace_id: namespaceId,
        logical_request_scope_cid: requested.logicalRequestScopeCid,
        intent_fingerprint_cid: requested.intentFingerprintCid,
        site_key: siteKey, realization_key: realizationKey,
      });
      // No decision callback, deferral journal or signer exists here. The
      // same Account evaluator refuses Delegate; it is never an Allow or a
      // synthetic approval. Source/Effect gates keep their own exact tuples.
      const scope = gate.withContext({principal: gate.principal,
        contextCid: gate.contextCid});
      try {
        const decision = await scope.authorize('preparation', tuple,
          {subjectCid: contentCid(subject), signal, allowDeferral: false});
        if (stopped) fail('ExecutionAuthorizationStopped');
        if (decision.action !== 'dispatch') {
          const error = new ExecutionAuthorizationError(decision);
          throw coded(error.runtimeCode ?? 'ACTQL_E_DELEGATION_UNAVAILABLE', error);
        }
        scope.assertAccountCurrent(decision);
        return {kind: 'dispatch'};
      } finally {
        // Share the installation's real budget, not an installation-long
        // cache of completed request decisions or a fresh capacity credit.
        scope.close();
      }
    },
    stop,
    close() {
      stop();
      if (gate.cleanupPending() || decisionBudget.cleanupPending()) {
        fail('ExecutionAuthorizationCleanupPending');
      }
    },
  });
  return Object.freeze({runAcceptance});
}

// Install the Checkpoint connection for one installed Host scope. Returns
// undefined when the Host installs no Run-acceptance protection (then its
// in-process Site is unprotected and pure compute is covered, as before).
// `source` (optional): the installed source's own read authorization,
// {accountConfiguration, context, sourceRef?}. A sourceRef also binds two
// distinct occurrences of that same installed source. A request that acquires
// that source is decided for the Host-resolved read tuple before any Run or
// provider I/O exists, and a delegated read is held like Run acceptance.
// `sources` is the plural installation alternative: sourceRef selects only
// authorization configuration; captured reads remain occurrence/task-bound.
// `effectTargets` is the plural Effect alternative: each trusted adapter's
// checked Mapping selectors bind its own opaque target-read authorization.
export async function installRemoteCheckpoints({root, namespaceId,
  authorityScopeCid, ownerPrincipal, siteKey, realizationKey,
  environmentCid, contractControl, authorization, source, sources, effectTarget,
  effectTargets, sourceInventory,
  modelResumeVerifier,
  now = () => Date.now()}: Installation) {
  if (authorization === undefined) return undefined;
  if (authorization === null || typeof authorization !== 'object') {
    fail('InvalidRemoteHostAuthorization');
  }
  // Admit the whole original range. The normal caller prepared its native
  // inventory on the SAME initial Source material before Source completion.
  if (sources !== undefined && (source !== undefined ||
      !Array.isArray(sources) || sources.length < 1 ||
      sources.some(item => typeof item?.sourceRef !== 'string' ||
        item.sourceRef.length === 0) ||
      new Set(sources.map(item => item.sourceRef)).size !== sources.length)) {
    fail('InvalidRemoteHostSources');
  }
  if (sourceInventory !== undefined && (sources !== sourceInventory.sources ||
      sourceInventory.installedSources.length !== sources.length ||
      sourceInventory.bindings.length !== sources.length ||
      sourceInventory.installedSources.some((item, index) => item.configuration !== sources[index]))) {
    fail('InvalidRemoteHostSources');
  }
  if (effectTargets !== undefined && effectTarget !== undefined) {
    fail('InvalidRemoteHostEffectTargets');
  }
  // Snapshot every plural account and context before installation awaits.
  const installedEffectTargets = effectTargets === undefined ? []
    : captureEffectTargets(effectTargets);
  const {accountConfig, accountConfiguration, accountConstruction, reviewers, reviewReaders,
    hostKey, decide, answeringAuthorities, effectRequiredClaims = [],
    checkpointTtlMs = 24 * 60 * 60 * 1000,
    leaseMs = 60_000, maxReviewBytes = MAX_REVIEW_BYTES,
    decisionTimeoutMs = 30_000, maxInFlightDecisions = 16,
    maxRetainedDecisions = 1024,
    resumeAfterAnswer = true, observe, faultInjection,
    sweepPage = PAGE} = authorization;
  const trusted = trustedReviewers(reviewers);
  if (!Array.isArray(effectRequiredClaims) ||
      effectRequiredClaims.some(claim =>
        !['effect_scope_approved', 'partial_application_accepted']
          .includes(claim))) {
    fail('InvalidEffectApprovalClaims');
  }
  const effectClaims = Object.freeze([...effectRequiredClaims]);
  const readers = principals(reviewReaders, 'InvalidReviewReaders');
  const answerers = new Set([...trusted.values()].map(item => item.principalId));
  if (!IDENTIFIER.test(hostKey?.keyId ?? '')) fail('InvalidRemoteHostKey');
  const hostPrivateKey = createPrivateKey(hostKey!.privateKey);
  if (!Number.isSafeInteger(checkpointTtlMs) || checkpointTtlMs < 1000 ||
      !Number.isSafeInteger(leaseMs) || leaseMs < 1000 ||
      !Number.isSafeInteger(maxReviewBytes) || maxReviewBytes < 1 ||
      maxReviewBytes > 1024 * 1024 ||
      !Number.isSafeInteger(decisionTimeoutMs) || decisionTimeoutMs < 1 ||
      typeof resumeAfterAnswer !== 'boolean' ||
      observe !== undefined && typeof observe !== 'function' ||
      faultInjection !== undefined && typeof faultInjection !== 'function' ||
      !Number.isSafeInteger(sweepPage) || sweepPage < 1 || sweepPage > 1000) {
    fail('InvalidRemoteHostAuthorization');
  }
  const decisionBudget = createAuthorizationDecisionBudget({
    maxInFlightDecisions, maxRetainedDecisions});
  const decisionOptions = {decisionBudget, decisionTimeoutMs};
  const installedSources: SourceSlot[] = sourceInventory?.installedSources ?? [];
  let sourceConsumerClosed = false;
  let originalSetupCleanup: CleanupHandle | undefined;
  if (sourceInventory !== undefined) {
    // This is the existing Source body borrow, not authority or a stop ACK.
    sourceInventory.custody.holder!.environment();
    sourceInventory.custody.retire = () => {
      decisionBudget.close();
      for (const installed of installedSources) {
        installed.gate?.close();
        installed.resumeGate?.close();
      }
      if (decisionBudget.cleanupPending()) return false;
      if (!sourceConsumerClosed && originalSetupCleanup?.status().pending !== false) return false;
      if (sourceInventory.custody.holder !== undefined) {
        sourceInventory.custody.holder.release();
        sourceInventory.custody.holder = undefined;
      }
      return true;
    };
  }
  let journal: Journal | undefined;
  let evidence: Evidence | undefined;
  try {
  const state = join(root, 'checkpoints');
  let privateKey;
  try { privateKey = await loadPrivateEvidenceKey(state); }
  catch (error) {
    if ((error as Fault)?.code !== 'PrivateEvidenceKeyUnavailable') throw error;
    await createPrivateEvidenceKey(state);
    privateKey = await loadPrivateEvidenceKey(state);
  }

  // The current trusted authorization context: principal, account and the
  // admitted configuration identity. A resume under another one fails
  // revalidation before any protected work.
  const gate = await createLocalAuthorizationGate({accountConfig, accountConstruction,
    accountConfiguration, principal: ownerPrincipal, ...decisionOptions});
  const configured = gate.configurationCid !== undefined;
  // The source's read decision uses the source installation's own account
  // configuration and context (the same one its adapter rechecks before
  // provider I/O). Without a decision function or deferral a delegated read
  // is unsupported here, so this gate is also the current-authority check.
  let sourceIndex = 0;
  for (const installed of sources ?? (source === undefined ? [] : [source])) {
    // Preserve the singular installation owner's original validation and
    // journal-custody ordering. The new plural inventory is copied once.
    const context = sources === undefined ? undefined : installed.context;
    const configuration = sourceInventory !== undefined || sources === undefined ? installed : Object.freeze({
      sourceRef: installed.sourceRef,
      accountConfiguration: installed.accountConfiguration,
      ...(context === undefined ? {} : {context: Object.freeze({...context})}),
    });
    const entry: SourceSlot = sourceInventory === undefined ? {configuration}
      : installedSources[sourceIndex++];
    if (sourceInventory === undefined) installedSources.push(entry);
    entry.gate = await createLocalAuthorizationGate({accountConstruction,
        accountConfiguration: configuration.accountConfiguration,
        context: configuration.context, ...decisionOptions});
  }
  const sourceGate = sources === undefined ? installedSources[0]?.gate
    : undefined;
  if (effectTarget !== undefined) effectTarget = Object.freeze({
    accountConfiguration: effectTarget.accountConfiguration,
    context: Object.freeze({...effectTarget.context}) as GateOptions['context'],
  });
  const effectTargetGate = effectTarget === undefined ? undefined :
    await createLocalAuthorizationGate({accountConstruction,
      accountConfiguration: effectTarget.accountConfiguration,
      context: effectTarget.context, ...decisionOptions});
  for (const installed of installedEffectTargets) {
    installed.gate = await createLocalAuthorizationGate({accountConstruction,
      accountConfiguration: installed.configuration.accountConfiguration,
      context: installed.configuration.context, ...decisionOptions});
  }
  const effectTargetAuthorities = new Map(installedEffectTargets.map(installed =>
    [installed.authority, installed]));
  const installedSource = createCheckpointSourceSelection({sources,
    installedSources: installedSources as (SourceSlot & {gate: Gate})[]});
  function captureInventory(captured: SourceCapture) {
    const inventory = acquisitionsOf(captured);
    if (pluralCapture(captured) && sources === undefined &&
        source?.sourceRef === undefined) {
      fail('HeldAcquisitionChanged');
    }
    if (installedSources.length > 0) {
      for (const occurrence of inventory) installedSource(occurrence);
    }
    return inventory;
  }
  const sourceBindings: SourceBinding[] = sourceInventory?.bindings ?? [];
  if (sources !== undefined) {
    for (let index = 0; index < installedSources.length; index++) {
      const {configuration, gate: read} = installedSources[index] as SourceSlot & {gate: Gate};
      const row = sourceInventory === undefined ? {source_ref: configuration.sourceRef} : sourceBindings[index];
      // Actual admitted Account identities fit their existing CID codec.
      // Refuse an incompatible producer; never truncate or invent a binding.
      if (sourceInventory !== undefined &&
          ((read.configurationCid !== undefined && !/^sha256:[0-9a-f]{64}$/u.test(read.configurationCid)) ||
          !/^sha256:[0-9a-f]{64}$/u.test(read.contextCid))) fail('InvalidRemoteHostSources');
      row.configuration_cid = read.configurationCid ?? null;
      row.context_cid = read.contextCid;
      if (sourceInventory === undefined) sourceBindings.push(row);
    }
    sourceBindings.sort((left, right) => left.source_ref! < right.source_ref! ? -1 : 1);
  }
  const binding = Object.freeze({
    authorizationContextCid: contentCid({principal: ownerPrincipal,
      account_id: gate.accountId ?? null,
      configuration_cid: gate.configurationCid ?? 'missing',
      // A changed source configuration also revalidates held requests.
      source_configuration_cid: sourceGate?.configurationCid ?? null,
      ...(effectTargetGate === undefined ? {} : {effect_target_authorization_binding: {
        configuration_cid: effectTargetGate.configurationCid ?? null,
        context_cid: effectTargetGate.contextCid,
      }}),
      ...(effectTargets === undefined ? {} : {effect_target_authorization_bindings:
        installedEffectTargets.flatMap(({mappings, gate: read}) =>
          mappings.map(({mappingRef, mappingCid}) => ({mapping_ref: mappingRef,
            mapping_cid: mappingCid,
            configuration_cid: read!.configurationCid ?? null,
            context_cid: read!.contextCid})))
          .sort((left, right) => left.mapping_ref < right.mapping_ref ? -1
            : left.mapping_ref > right.mapping_ref ? 1 : 0)}),
      ...(sources === undefined ? {} : {source_authorization_bindings: sourceBindings}),
    }),
    environmentBindingCid: contentCid({version:
      'actql-remote-run-acceptance-environment/0.1', site_key: siteKey,
    realization_key: realizationKey, environment_cid: environmentCid,
    authority_scope_cid: authorityScopeCid}),
  });
  const authorities = [...trusted.values()].map(({keyId, reviewerId}) =>
    ({keyId, reviewerId}));
  const heldIndex = join(state, 'held');
  await mkdir(heldIndex, {recursive: true, mode: 0o700});
  const {recordHeld, indexedRequestId} = createCheckpointHeldIndex(heldIndex);

  journal = openSqliteCheckpointJournal(join(state, 'journal'), {
    runtime: await loadCheckpointRuntime(),
    expectedAuthorityScopeCid: authorityScopeCid,
    modelResumeVerifier,
    now,
    // Host authorization port: Host-trusted reviewer keys only; the
    // Resolution and its run-scope approval must be signed by the same key.
    authorizeResolution({resolutionWire, approvalEvidenceWire,
      proofPreimage}) {
      const resolution = JSON.parse(resolutionWire);
      const reviewer = trusted.get(resolution.proof?.key_id);
      if (reviewer === undefined || resolution.actor !== reviewer.reviewerId) {
        fail('UntrustedReviewerKey');
      }
      if (!verify(null, Buffer.from(proofPreimage, 'utf8'),
        reviewer.publicKey,
        Buffer.from(resolution.proof.signature ?? '', 'base64'))) {
        fail('InvalidResolutionSignature');
      }
      if (approvalEvidenceWire !== '') {
        const evidence = JSON.parse(approvalEvidenceWire);
        const approval = evidence.compatibility_approval;
        const effect = evidence.kind === 'effect_set';
        const unsigned = contentCid(without(approval,
          effect ? 'attestation_cid' : 'run_scope_approval_cid', 'proof'));
        if (approval?.proof?.key_id !== reviewer.keyId ||
            approval.approver !== reviewer.reviewerId ||
            effect && approval.authority_scope_cid !== authorityScopeCid ||
            !verify(null, Buffer.from(unsigned, 'utf8'), reviewer.publicKey,
              Buffer.from(approval.proof.signature ?? '', 'base64'))) {
          fail('InvalidApprovalSignature');
        }
      }
      return {
        keyId: reviewer.keyId,
        reviewerId: reviewer.reviewerId,
        authorityContextCid: binding.authorizationContextCid,
        policyCid: gate.configurationCid ?? contentCid({configuration:
          'missing'}),
        verifiedPreimage: proofPreimage,
      };
    },
    attestResolution(preimage) {
      return {hostKeyId: hostKey!.keyId,
        signature: sign(null, Buffer.from(preimage, 'utf8'),
          hostPrivateKey).toString('base64')};
    },
  });

  // Retention of held private evidence follows the journal: a waiting or
  // resuming request keeps it; an ended preparation or a terminal Run
  // releases it.
  evidence = openContinuationEvidence({
    stateDirectory: state, ...privateKey, contractControl,
    isTerminalRunOutcome: journal!.isTerminalRunOutcome,
    preparation(prepareAttemptId) {
      if (prepareAttemptId.startsWith('effect-') ||
          prepareAttemptId.startsWith('model-')) {
        const model = prepareAttemptId.startsWith('model-');
        const run = journal!.getRunState(prepareAttemptId.slice(
          model ? 6 : 7));
        // Cancellation/expiry can stop unsent work while entered calls still
        // need historical observation and cleanup. Missing discovery is not
        // proof that those immutable Model originals may be retired.
        if (run !== undefined && journal!.isTerminalRunOutcome(run.status)) {
          const unresolved = journal!.hasUnresolvedModelCalls?.(
            prepareAttemptId.slice(model ? 6 : 7));
          if (model ? unresolved !== false : unresolved === true) return undefined;
        }
        return run === undefined ? undefined :
          {status: 'run_created', runStatus: run.status};
      }
      const current = journal!.getPreparation(prepareAttemptId);
      if (current === undefined) return undefined;
      return {status: current.status, runStatus: current.runId === null
        ? undefined : journal!.getRunState(current.runId)?.status};
    },
  });

  const tuple = Object.freeze({connection: siteKey, resource: realizationKey,
    operation: 'write'});
  // The gate that continues approved requests: the same configuration and
  // durable journal; a resume never defers again. The gate's general
  // describe type permits broader Model data, which the Journal admits or
  // refuses using its original checked Model inventory.
  const resumeGate = await createLocalAuthorizationGate({accountConfig, accountConstruction,
    accountConfiguration, principal: ownerPrincipal, ...decisionOptions,
    deferral: {journal: journal as Journal & Deferral['journal'],
      authorities, binding,
      describe() { fail('ResumeDoesNotDefer'); }}});
  for (const installed of installedSources) {
    installed.resumeGate = await createLocalAuthorizationGate({accountConstruction,
      accountConfiguration: installed.configuration.accountConfiguration,
      context: installed.configuration.context, ...decisionOptions,
      deferral: {journal: journal as Journal & Deferral['journal'], authorities, binding,
        describe() { fail('ResumeDoesNotDefer'); }}});
  }
  // The read approval admitted immediately before a held request's physical
  // start, for the source adapter's current-authority check that follows in
  // the same process (after a restart a started acquisition is only
  // reconciled, never started again).
  const admittedReads = new Map<string, Map<string, ReadApproval>>();
  const {requestSubject, prepareAttemptIdOf, deferralFor, acquisitionIntent,
    readDeferralFor} = createHeldCheckpointDeferrals({authorityScopeCid, namespaceId, siteKey,
    realizationKey, journal, authorities, binding, evidence, gate, now,
    checkpointTtlMs, maxReviewBytes, installedSource, recordHeld});

  // Decide a request's source read for the Host-resolved read tuple. The
  // account allows, denies or delegates; a delegated read is answered by the
  // Host's decision function or held through `port`.
  async function decideRead({prepareAttemptId, request, requestCid,
    captured, occurrence, port, earlier, signal}: ReadDecisionInput) {
    const {configuration} = installedSource(occurrence);
    const answering = answeringAuthorities ??
      authorities.map(item => item.reviewerId);
    const intentCid = capturedValueCid(acquisitionIntent(requestCid, captured,
      occurrence));
    const deferring = await createLocalAuthorizationGate({accountConstruction,
      accountConfiguration: configuration.accountConfiguration,
      context: configuration.context, ...decisionOptions, decide,
      answeringAuthorities: decide === undefined ? undefined : answering,
      // Epoch-bound submission does not yet expose the complete pre-Run
      // response/cancel/recovery contract. Use the existing gate's unsupported
      // decision before it seals evidence or creates a Checkpoint.
      deferral: captured.submission === undefined
        ? readDeferralFor({prepareAttemptId, request, requestCid,
          captured, occurrence, answering, port, earlier}) as ReturnType<typeof readDeferralFor> & Deferral : undefined});
    try {
      return await deferring.authorize('acquisition',
        occurrence.readTuple, {subjectCid: intentCid, signal});
    } finally { deferring.close(); }
  }

  const {continuedOccurrence, admittedRead, continuationOf, earlierReadApprovals,
    heldRequestId, held} = createCheckpointHeldRecovery({captureInventory,
    evidence, acquisitionIntent, journal, indexedRequestId, recordHeld, now});
  const diagnostic = diagnosticObserver(observe);
  const step = async (name: string, detail: unknown) => {
    diagnostic(name, detail);
    await faultInjection?.(name, detail);
  };

  const refusal = (decision: Decision) => {
    const error = new ExecutionAuthorizationError(decision);
    return coded(error.runtimeCode ?? 'ACTQL_E_DELEGATION_UNAVAILABLE',
      error);
  };

  // Resume sweep. Approved preparations are continued by whichever Host
  // claims their intent; a busy intent (a live or recently dead claimant) is
  // retried after its lease.
  let sweeping: Promise<void> | undefined;
  let retry: ReturnType<typeof setTimeout> | undefined;
  let closed = false;
  let host: HostPort | undefined;
  const modelCustody = createCheckpointModelCustody({contractControl, evidence, IDENTIFIER,
    capturedValueWire, fail, get closed() { return closed; }});
  // Errors that a later attempt may clear (a busy Store, a transient read);
  // anything else is permanent for this item and only observed.
  const PERMANENT = new Set(['ArtifactIntegrityFailed',
    'ContinuationEvidenceNotHeld', 'ContinuationEvidenceRetired',
    'PrivateEvidenceKeyMismatch', 'HeldRunDefinitionMissing',
    'HeldRequestChanged', 'HeldAcquisitionChanged',
    'InvalidContinuationLedger']);
  const retryable = (error: Fault) => !PERMANENT.has((error?.code ?? error?.message)!);
  // Observe Runs created from approved preparations. The intent completes
  // only after the physical start is reserved, so these Runs are started
  // (or unknown); they are never started or sent again here. A terminal Run
  // ends its journal Run. Returns true when an item should be retried.
  async function recoverRuns() {
    let busy = false;
    let after = '';
    for (;;) {
      const page = journal!.listPreparationRuns({after, limit: sweepPage});
      for (const {prepareAttemptId, runId} of page) {
        if (closed) return busy;
        try {
          const {captured} = await continuationOf(prepareAttemptId);
          await step('run_observed', {prepareAttemptId, runId});
          const status = await host!.observe({captured, runId});
          if (journal!.isTerminalRunOutcome(status)) {
            journal!.finishRun(runId, {status});
          }
        } catch (error) {
          const code = (error as Fault)?.code ?? (error as Fault)?.message;
          await step('recovery_failed', {prepareAttemptId, runId, code,
            retry: retryable(error as Fault)});
          if (retryable(error as Fault)) busy = true;
        }
      }
      if (page.length < sweepPage) return busy;
      after = page.at(-1)!.prepareAttemptId;
    }
  }
  async function resumeOne(prepareAttemptId: string) {
    const claimant = `remote-host-${process.pid}-${randomUUID()}`;
    let claimed;
    try {
      claimed = journal!.claimPreparationResume(prepareAttemptId,
        {claimant, leaseMs, binding});
    } catch (error) {
      if ((error as Fault)?.code === 'ResumeIntentNotFound') return 'done';
      throw error;
    }
    if (claimed.action === 'busy') return 'busy';
    if (claimed.action === 'invalidated') {
      // Revalidation failed (for example the configuration changed): the
      // preparation ended without a Run. A Run already defined but not
      // started fails before dispatch, so nothing starts later.
      try {
        const {captured} = await continuationOf(prepareAttemptId);
        await host!.abandon(captured);
      } catch (error) {
        await step('abandon_failed', {prepareAttemptId,
          code: (error as Fault)?.code ?? (error as Fault)?.message});
      }
      return 'done';
    }
    if (claimed.action !== 'claimed') return 'done';
    const claim = claimed.claim;
    await step('resume_claimed', {prepareAttemptId,
      generation: claim.generation});
    const end = (status: 'failed' | 'cancelled') => {
      // A stale fence did not settle the preparation. Let the owned drain
      // retain retry responsibility and re-observe it under a fresh claim.
      // In particular, a cancelled Run must not strand its held evidence.
      journal!.completeResume(claim, {status});
    };
    let continuation;
    let captured;
    let request;
    try {
      ({continuation, captured, request} = await continuationOf(
        prepareAttemptId, claimed.continuationStateCid));
    } catch (error) {
      if (retryable(error as Fault)) return 'busy';
      end('failed');
      return 'done';
    }
    const probe = await host!.inspect(captured);
    // A durable request cancellation: nothing new starts. A Run already
    // defined but not started is cancelled through its own cancellation;
    // one whose start is reserved keeps the existing stop and cleanup
    // owners (the cancellation was applied to the Run by cancel-request).
    const cancelRequested = () =>
      journal!.getPreparation(prepareAttemptId)?.cancelRequested === true;
    if (cancelRequested() && probe.state !== 'started' &&
        probe.state !== 'terminal') {
      if (probe.state === 'unstarted') await host!.cancelRun(captured);
      end(probe.state === 'abandoned' ? 'failed' : 'cancelled');
      return 'done';
    }
    // A Run whose physical start an earlier claim already reserved (running,
    // unknown or ended) is only reconciled: the intent completes with it and
    // nothing is authorized or sent again.
    // A Run an earlier claim failed before dispatch (authorization no
    // longer held) ends the request without a journal Run.
    if (probe.state === 'abandoned') {
      end('failed');
      return 'done';
    }
    // A Run cancelled before its physical start ends the request the same
    // way; nothing is retried or started.
    if (probe.state === 'cancelled') {
      end('cancelled');
      return 'done';
    }
    if (probe.state === 'started' || probe.state === 'terminal') {
      journal!.completeResume(claim, {run: {runId: probe.runId,
        status: 'running'}});
      if (probe.state === 'terminal') {
        journal!.finishRun(probe.runId, {status: probe.status});
      }
      return 'done';
    }
    // Otherwise the physical start is still ahead: the common resumed
    // authorization holds now (current configuration, approval validity at
    // trusted time, live claim), whether or not the Run Definition exists.
    // The resumed Checkpoint is Run acceptance (`run_scope`) or a held
    // source read (`read_access`), each decided for its own tuple.
    const resumedKind = journal!.inspect(claimed.checkpointCid)?.kind;
    const readHeld = resumedKind === 'read_access';
    const inventory = captureInventory(captured);
    const resumedOccurrence = readHeld
      ? continuedOccurrence(captured, continuation) : undefined;
    if (readHeld && (installedSources.length === 0 ||
        resumedOccurrence === undefined)) {
      await host!.abandon(captured);
      end('failed');
      return 'done';
    }
    // Every earlier approval is still required, including Run acceptance and
    // the other source occurrence, at this Host's trusted time.
    const earlier = [...(continuation.earlier_approvals ?? [])];
    const earlierCurrent = () => {
      for (const checkpointCid of earlier) {
        if (journal!.committedApprovalAt(checkpointCid).current !== true) {
          throw Object.assign(new Error('ApprovalExpired'),
            {code: 'ApprovalExpired'});
        }
      }
    };
    const decision = readHeld
      ? await installedSource(resumedOccurrence!).resumeGate!.resume('acquisition',
        resumedOccurrence!.readTuple, {
          subjectCid: continuation.invocation_cid,
          sealedSubjectCid: continuation.invocation_cid,
          resumption: {claim: {checkpointCid: claimed.checkpointCid, claim}},
        })
      : await resumeGate.resume('preparation', tuple, {
        subjectCid: request.subject_cid,
        sealedSubjectCid: continuation.invocation_cid,
        resumption: {claim: {checkpointCid: claimed.checkpointCid, claim}},
      });
    let earlierValid = true;
    try { earlierCurrent(); } catch { earlierValid = false; }
    if (decision.action !== 'dispatch' || decision.admission === undefined ||
        !earlierValid) {
      // A lapsed or superseded claim sends nothing and ends nothing.
      if (decision.detail === 'ResumeClaimStale') return 'busy';
      await host!.abandon(captured);
      end('failed');
      return 'done';
    }
    const readApprovals = await earlierReadApprovals(prepareAttemptId,
      captured, earlier);
    const allApprovals = [...earlier, claimed.checkpointCid];
    if (readHeld) {
      readApprovals.set(occurrenceKey(resumedOccurrence!), admittedRead(
        captured, resumedOccurrence!, {checkpointCid: claimed.checkpointCid,
          earlier, prepareAttemptId}));
    }
    // Decide the complete ordered inventory before any provider I/O. A new
    // delegated occurrence replaces this resume intent with its own durable
    // Checkpoint in the existing journal!. Ephemeral Host permits are decided
    // again after restart; only actual held approvals are reconstructed.
    if (installedSources.length > 0) for (const occurrence of inventory) {
      if (readApprovals.has(occurrenceKey(occurrence))) continue;
      try { journal!.renewResume(claim, leaseMs); }
      catch (error) {
        if ((error as Fault)?.code === 'ResumeClaimStale') return 'busy';
        throw error;
      }
      const read = await decideRead({prepareAttemptId, request,
        requestCid: contentCid(request), captured, occurrence,
        earlier: allApprovals,
        port: {
          persistCheckpoint: ({body, authorities: reviewers, binding: bound,
            decisionSubjectCid, requestedClaims, configurationCid}) =>
            journal!.completeResume(claim, {checkpoint: {body,
              authorities: reviewers, binding: bound, decisionSubjectCid,
              requestedClaims, configurationCid}}) as ReturnType<Journal['persistCheckpoint']>,
          submitResolution: item => journal!.submitResolution(item),
        }});
      if (read.action === 'waiting') return 'done';
      if ((read.error as Fault)?.code === 'ResumeClaimStale' ||
          read.detail === 'ResumeClaimStale') return 'busy';
      if (read.action !== 'dispatch') {
        await host!.abandon(captured);
        end('failed');
        return 'done';
      }
      if (read.basis === 'host_permit') {
        readApprovals.set(occurrenceKey(occurrence), admittedRead(captured,
          occurrence, {earlier: allApprovals, prepareAttemptId}));
      }
    }
    const admission = decision.admission;
    const identity = request.subject.logical_request_scope_cid;
    const outcome = await host!.resume({
      captured, step,
      renew() { journal!.renewResume(claim, leaseMs); },
      // Entered synchronously immediately before the physical start
      // reservation (fence, approval validity, single start per claim
      // generation). A later generation reconciles the same identity.
      preparationCancelled: cancelRequested,
      beforePhysicalStart() {
        // A request cancellation recorded at any point before now stops the
        // start (checked synchronously with the reservation).
        if (cancelRequested()) {
          throw Object.assign(new Error('PreparationCancelled'),
            {code: 'PreparationCancelled'});
        }
        // The claimant keeps its lease while it works; a lapsed or
        // superseded claim throws here and nothing starts.
        journal!.renewResume(claim, leaseMs);
        earlierCurrent();
        try { admission.enter(identity); }
        catch (error) {
          if ((error as Fault)?.code !== 'PriorAdmissionUnresolved') throw error;
          admission.reconcile(identity);
        }
        // Each adapter receives only its exact occurrence grant, bound to
        // the complete captured pair and every still-current approval.
        if (readApprovals.size > 0) {
          admittedReads.set(captured.requestId, new Map([...readApprovals]
            .map(([key, value]) => [key, Object.freeze({...value,
              earlier: allApprovals.filter(cid => cid !== value.checkpointCid),
            })])));
        }
      },
      // The intent completes with the Run right after its physical start is
      // reserved; the Run is then only observed.
      started(runId) {
        journal!.completeResume(claim, {run: {runId, status: 'running'}});
      },
    });
    if (outcome === 'started') return 'done';
    const refusal = (outcome as Readonly<{refused?: Fault}> | undefined)?.refused;
    // A start that did not happen may be a cancellation that arrived during
    // the resume: settle it now rather than retrying.
    if (outcome === 'not_started') {
      const after = await host!.inspect(captured);
      if (after.state === 'cancelled') {
        end('cancelled');
        return 'done';
      }
      return 'busy';
    }
    if (refusal?.code === 'ResumeClaimStale') return 'busy';
    if (refusal?.code === 'PreparationCancelled') {
      await host!.cancelRun(captured);
      end('cancelled');
      return 'done';
    }
    if (refusal !== undefined) {
      await host!.abandon(captured);
      end('failed');
    }
    return 'done';
  }

  async function stop() {
    closed = true;
    if (retry !== undefined) clearTimeout(retry);
    retry = undefined;
    await sweeping;
    await host?.models?.drain?.();
    await host?.effects?.drain?.();
  }

  // One drain: every resumable preparation, page by page (a busy page never
  // starves later ones), then the Run-side duties and evidence retention.
  async function drain() {
    journal!.expire();
    let busy = false;
    let after = '';
    for (;;) {
      const page = journal!.listResumablePreparations({after,
        limit: sweepPage});
      for (const id of page) {
        if (closed) return busy;
        let outcome;
        try { outcome = await resumeOne(id); }
        catch (error) {
          outcome = 'busy';
          await step('resume_failed', {prepareAttemptId: id,
            code: (error as Fault)?.code ?? (error as Fault)?.message});
        }
        if (outcome === 'busy') busy = true;
      }
      if (page.length < sweepPage) break;
      after = page.at(-1)!;
    }
    if (await recoverRuns()) busy = true;
    if (await host?.models?.sweep()) busy = true;
    if (await host?.effects?.sweep()) busy = true;
    await evidence!.settle();
    return busy;
  }

  // Single-flight, but never lossy: a wake during a drain marks another
  // pass, and busy or failed work is retried after the lease. Failures stay
  // in the durable intents; nothing is dropped with a rejected promise.
  let wake = false;
  function sweep() {
    if (closed || host === undefined) return Promise.resolve();
    wake = true;
    if (sweeping !== undefined) return sweeping;
    sweeping = (async () => {
      let busy = false;
      try {
        while (wake && !closed) {
          wake = false;
          try { busy = await drain() || busy; }
          catch (error) {
            busy = true;
            await step('sweep_failed', {code: (error as Fault)?.code ?? (error as Fault)?.message});
          }
        }
      } finally {
        sweeping = undefined;
      }
      if (busy && !closed && retry === undefined) {
        retry = setTimeout(() => { retry = undefined; void sweep(); },
          leaseMs + 100);
        retry.unref?.();
      }
    })();
    return sweeping;
  }

  const {modelStoredContinuation, review} = createCheckpointReview({journal, evidence,
    contractControl, gate, authorityScopeCid, ownerPrincipal, siteKey, readers, answerers, trusted,
    maxReviewBytes, heldRequestId, resumeAfterAnswer, sweep, get closed() { return closed; }});

  const computationSource = createCheckpointComputationSource({installedSource,
    createLocalAuthorizationGate, journal: journal as Journal & Deferral['journal'], evidence, accountConstruction, decisionOptions,
    decide, answeringAuthorities, authorities, binding, authorityScopeCid, ownerPrincipal,
    now, maxReviewBytes, checkpointTtlMs});

  const acquisitionAccess = createCheckpointAcquisitionAccess({admittedReads, journal});

  return Object.freeze({
    configured,
    journal,
    binding,
    modelContext: Object.freeze({accountId: gate.accountId,
      configurationCid: gate.configurationCid, principal: gate.principal,
      contextCid: gate.contextCid}),

    ...modelCustody,

    // A fixed Model inventory has its own activation decision. Neither a
    // Source answer nor the later Effect Set answer is a Model send permit.
    async modelAuthorization({runId, runDefinitionCid, unitId, scopeCid, tuple,
      declaredResults, modelCallSet, reviewWire, continuationWire, beforeDefer,
      journalPort = journal!, attachImmediate = false}: ModelAuthorization) {
      if (!IDENTIFIER.test(runId ?? '') || typeof unitId !== 'string' || unitId.length === 0 ||
          typeof runDefinitionCid !== 'string' || typeof scopeCid !== 'string' ||
          tuple?.operation !== 'infer' || typeof tuple.connection !== 'string' ||
          typeof tuple.resource !== 'string' || !Array.isArray(declaredResults) ||
          typeof reviewWire !== 'string' || typeof continuationWire !== 'string' ||
          typeof beforeDefer !== 'function' || typeof attachImmediate !== 'boolean' ||
          modelCallSet === null || typeof modelCallSet !== 'object') {
        fail('InvalidInstalledModelContinuation');
      }
      tuple = Object.freeze({connection: tuple.connection,
        resource: tuple.resource, operation: 'infer'});
      declaredResults = Object.freeze([...declaredResults]);
      const review = contractControl.admitRunEvidence('run_review_projection',
        reviewWire, {maxWireBytes: maxReviewBytes, maxNodes: 10000, maxDepth: 64});
      if (review.wire !== reviewWire || modelCallSet.reviewWire !== undefined &&
          modelCallSet.reviewWire !== reviewWire) fail('ModelReviewProjectionMismatch');
      if (attachImmediate && journalPort !== journal &&
          (!Object.hasOwn(journalPort, 'modelParentResume') ||
           journalPort.modelParentResume?.claim?.runId !== runId ||
           typeof journalPort.modelParentResume?.checkpointCid !== 'string' ||
           !Object.hasOwn(journalPort, 'attachModelCallSetCheckpoint') ||
           typeof journalPort.attachModelCallSetCheckpoint !== 'function' ||
           journalPort.attachModelCallSetCheckpoint === journal!.attachModelCallSetCheckpoint)) {
        fail('ModelImmediateCheckpointChainingUnsupported');
      }
      const port = !attachImmediate ? journalPort : {...journalPort,
        persistCheckpoint: (checkpoint: Parameters<Journal['attachModelCallSetCheckpoint']>[0]) => journalPort.attachModelCallSetCheckpoint!(checkpoint)};
      const model = await createLocalAuthorizationGate({accountConfig, accountConstruction,
        accountConfiguration, principal: ownerPrincipal, ...decisionOptions,
        decide, requiredClaims: ['invocation_scope_approved'],
        answeringAuthorities: answeringAuthorities ?? authorities.map(item => item.reviewerId),
        deferral: {journal: port as JournalPort & Deferral['journal'], authorities, binding,
          async describe(view) {
            if (view.boundary !== 'activation' || view.tuple.operation !== 'infer' ||
                view.subject.subject_cid !== scopeCid) {
              fail('InvalidModelCheckpointBoundary');
            }
            await beforeDefer();
            if (Buffer.byteLength(reviewWire) > maxReviewBytes) fail('CheckpointReviewTooLarge');
            // The review's common semantic CID excludes its self field. The
            // existing encrypted continuation store uses a full-byte digest;
            // retain their exact association instead of confusing identities.
            const storedReview = evidence!.reference(`model-${runId}`,
              'review_projection', reviewWire).semantic_cid;
            const storedContinuation = canonicalValueJson({version: MODEL_CHECKPOINT_STORAGE,
              run_definition_cid: runDefinitionCid,
              model_invocation_scope_cid: scopeCid,
              review_projection_cid: review.identity, review_storage_cid: storedReview,
              continuation_wire: continuationWire});
            const refs = await evidence!.hold(`model-${runId}`, runDefinitionCid, [
              {name: 'review_projection', wire: reviewWire},
              {name: 'continuation_record', wire: storedContinuation},
            ]);
            const created = now();
            return {priorStatus: 'running', declaredResults: [...declaredResults],
              modelCallSet: {...modelCallSet, reviewWire}, body: {
                checkpoint_id: `model-${hex(scopeCid)}`,
                run_id: runId, run_definition_cid: runDefinitionCid,
                continuation_state_cid: refs[1],
                subject: {kind: 'run_unit', run_id: runId, unit_id: unitId,
                  continuation: 'resume_unit'},
                kind: 'model_invocation',
                required_artifact: {artifact_type: 'model_invocation_scope',
                  artifact_cid: scopeCid},
                review_projection_cid: review.identity,
                human_summary: `Approve fixed Model calls for Run ${runId}`,
                created_at: new Date(created).toISOString(),
                expires_at: new Date(created + checkpointTtlMs).toISOString(),
              }};
          },
        }});
      if (model.configurationCid !== gate.configurationCid ||
          model.contextCid !== gate.contextCid) {
        model.close();
        fail('ModelCheckpointConfigurationChanged');
      }
      return Object.freeze({scopeCid, configurationCid: model.configurationCid,
        contextCid: model.contextCid,
        authorize: (options?: Parameters<Gate['authorize']>[2]) => model.authorize('activation', tuple,
          {...options, subjectCid: scopeCid}),
        resume: (options?: Parameters<Gate['resume']>[2]) => model.resume('activation', tuple,
          {...options, subjectCid: scopeCid}),
        close: () => model.close(),
        cleanup: () => model.cleanup(),
        cleanupPending: () => model.cleanupPending(),
      });
    },
    async modelContinuation(view: CheckpointView) {
      const {record} = await modelStoredContinuation(view);
      return JSON.parse(record.continuation_wire);
    },

    // Every target tuple has its own read-scope artifact and answer. These
    // pre-computation approvals never reuse a Source or Effect-commit grant.
    async effectTargetAuthorization({runId, runDefinitionCid, unitId,
      inventoryCid, target, declaredResults, continuation, beforeDefer,
      effectTargetAuthority, journalPort = journal!}: TargetAuthorization) {
      const installed = effectTargets === undefined
        ? effectTargetAuthority === undefined && effectTargetGate !== undefined
          ? {configuration: effectTarget!, gate: effectTargetGate} : undefined
        : effectTargetAuthorities.get(effectTargetAuthority!);
      if (installed === undefined || !IDENTIFIER.test(runId ?? '') ||
          !IDENTIFIER.test(unitId ?? '') || typeof runDefinitionCid !== 'string' ||
          typeof inventoryCid !== 'string' || typeof continuation !== 'function' ||
          typeof beforeDefer !== 'function' || !Array.isArray(declaredResults) ||
          !Number.isSafeInteger(target?.index) || target.index < 0 ||
          target.index >= 1000 || target.readTuple?.operation !== 'read' ||
          !Array.isArray(target.physicalBindings) || target.physicalBindings.length === 0) {
        fail('InvalidEffectTargetContinuation');
      }
      target = JSON.parse(canonicalValueJson(target, {dataKeys: true}));
      const scope = effectTargetReadScope({runDefinitionCid, unitId,
        authorityScopeCid, principalId: ownerPrincipal, inventoryCid, target});
      // Bind the exact provider data retained and shown for this approval.
      const scopeCid = `sha256:${hex(canonicalValueJson(scope, {dataKeys: true}))}`;
      const read = await createLocalAuthorizationGate({accountConstruction,
        accountConfiguration: installed.configuration.accountConfiguration,
        context: installed.configuration.context, ...decisionOptions, decide,
        answeringAuthorities: answeringAuthorities ?? authorities.map(item => item.reviewerId),
        deferral: {journal: journalPort as JournalPort & Deferral['journal'], authorities, binding,
          async describe(view) {
            if (view.boundary !== 'acquisition' || view.subject.subject_cid !== scopeCid) {
              fail('InvalidEffectTargetCheckpointBoundary');
            }
            await beforeDefer();
            const wire = await continuation();
            if (typeof wire !== 'string') fail('InvalidEffectTargetContinuation');
            const reviewWire = canonicalValueJson({scope,
              configuration_cid: installed.gate!.configurationCid,
              context_cid: installed.gate!.contextCid}, {dataKeys: true});
            if (Buffer.byteLength(reviewWire) > maxReviewBytes) fail('CheckpointReviewTooLarge');
            const refs = await evidence!.hold(`effect-${runId}`, runDefinitionCid, [
              {name: 'review_projection', wire: reviewWire},
              {name: 'continuation_record', wire},
            ]);
            const created = now();
            return {priorStatus: 'running', declaredResults: [...declaredResults], body: {
              checkpoint_id: `${runId}-target-${target.index}`,
              run_id: runId, run_definition_cid: runDefinitionCid,
              continuation_state_cid: refs[1],
              subject: {kind: 'run_unit', run_id: runId, unit_id: unitId,
                continuation: 'resume_unit'},
              kind: 'read_access',
              required_artifact: {artifact_type: 'read_scope', artifact_cid: scopeCid},
              review_projection_cid: refs[0],
              human_summary: `Read Effect target ${target.readTuple.resource} for Run ${runId}`,
              created_at: new Date(created).toISOString(),
              expires_at: new Date(created + checkpointTtlMs).toISOString(),
            }};
          },
        }});
      if (read.configurationCid !== installed.gate!.configurationCid ||
          read.contextCid !== installed.gate!.contextCid) {
        read.close();
        fail('EffectTargetCheckpointConfigurationChanged');
      }
      return Object.freeze({scopeCid, configurationCid: read.configurationCid,
        contextCid: read.contextCid,
        assertCurrent: () => read.assertConfigurationCurrent(),
        authorize: (options?: Parameters<Gate['authorize']>[2]) => read.authorize('acquisition', target.readTuple,
          {...options, subjectCid: scopeCid}),
        resume: (options?: Parameters<Gate['resume']>[2]) => read.resume('acquisition', target.readTuple,
          {...options, subjectCid: scopeCid}),
        current: (options?: Parameters<Gate['authorize']>[2]) => installed.gate!.authorize('acquisition', target.readTuple,
          {...options, subjectCid: scopeCid}),
        close: () => read.close(),
        cleanup: () => read.cleanup(),
        cleanupPending: () => read.cleanupPending(),
      });
    },
    async effectTargetContinuation(view: CheckpointView) {
      if (view?.kind !== 'read_access' || view.prepareAttemptId !== null) {
        fail('InvalidEffectTargetContinuation');
      }
      const held = await evidence!.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      const saved = await held.record('continuation_record', view.continuationStateCid) as SavedTarget | null;
      if (saved?.version !== EFFECT_TARGET_CONTINUATION ||
          saved.run_definition_cid !== view.runDefinitionCid ||
          saved.unit_id !== (view.subject as Readonly<{unit_id?: string}>)?.unit_id) fail('InvalidEffectTargetContinuation');
      return saved;
    },
    async runUnitReadContinuation(view: CheckpointView) {
      if (view?.kind !== 'read_access' || view.prepareAttemptId !== null) {
        fail('InvalidRunUnitReadContinuation');
      }
      const held = await evidence!.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      return held.record('continuation_record', view.continuationStateCid);
    },
    async inspectEffectTargetApprovals(runId: string, runDefinitionCid: string) {
      if (!IDENTIFIER.test(runId ?? '') || typeof runDefinitionCid !== 'string') {
        fail('InvalidEffectTargetContinuation');
      }
      const records = [];
      let after = '';
      for (;;) {
        const page = journal!.listRunCheckpoints({after, limit: PAGE});
        for (const view of page) {
          if (view.runId !== runId || view.kind !== 'read_access' ||
              !view.checkpointId.startsWith(`${runId}-target-`)) continue;
          if (view.runDefinitionCid !== runDefinitionCid || view.prepareAttemptId !== null) {
            fail('EffectContinuationRunMismatch');
          }
          const held = await evidence!.open(`effect-${runId}`);
          if (held.requestCid !== runDefinitionCid) fail('EffectContinuationRunMismatch');
          const continuation = await held.record('continuation_record', view.continuationStateCid) as SavedTarget | null;
          if (continuation?.version !== EFFECT_TARGET_CONTINUATION ||
              continuation.run_definition_cid !== runDefinitionCid) {
            fail('InvalidEffectTargetContinuation');
          }
          records.push(Object.freeze({view, continuation}));
        }
        if (page.length < PAGE) break;
        after = page.at(-1)!.checkpointCid;
      }
      return Object.freeze(records);
    },

    // Host-installed Effect execution uses this same journal and reviewer
    // authority. The read boundary has no deferral port in this profile:
    // a deferred target read is unsupported before any provider I/O.
    async effectAuthorization({runId, runDefinitionCid, runDefinition, unitId,
      declaredResults, reviewWire, continuationWire, beforeDefer, targetReads,
      requestedStop, assertRequestedStopCurrent, projectReview,
      journalPort = journal!}: EffectAuthorization) {
      if (!IDENTIFIER.test(runId ?? '') || !IDENTIFIER.test(unitId ?? '') ||
          typeof beforeDefer !== 'function' ||
          typeof reviewWire !== 'string' ||
          typeof continuationWire !== 'string' ||
          !Array.isArray(declaredResults)) {
        fail('InvalidInstalledEffectContinuation');
      }
      if (requestedStop !== undefined &&
          (typeof assertRequestedStopCurrent !== 'function' ||
           typeof contractControl.requestedEffectStopLifetime !== 'function' ||
           typeof contractControl.sealRequestedEffectStop !== 'function')) {
        fail('RequestedEffectStopUnavailable');
      }
      const originalLifetime = runDefinition === undefined ? undefined :
        contractControl.runDefinitionLifetime(runDefinition, runDefinitionCid);
      const checkpointEnd = (created: number,
        stopLifetime: ReturnType<ContractControl['requestedEffectStopLifetime']> | undefined) => {
        let expires = created + checkpointTtlMs;
        for (const lifetime of [originalLifetime, stopLifetime]) {
          if (lifetime === undefined) continue;
          const start = Date.parse(lifetime.createdAt);
          const end = Date.parse(lifetime.validUntil);
          if (!Number.isFinite(start) || !Number.isFinite(end) || created < start) {
            fail('RequestedEffectStopLifetimeUnavailable');
          }
          // Common requires the Checkpoint end strictly inside the SAME Run's
          // exclusive deadline, even when a genuine Delegate creates the stop.
          expires = Math.min(expires, end - 1);
        }
        if (!Number.isFinite(expires) || expires <= created) {
          fail('RequestedEffectStopLifetimeUnavailable');
        }
        return expires;
      };
      declaredResults = Object.freeze([...declaredResults]);
      const reviewLimits = Object.freeze({...INSTALLED_EFFECT_CHECKPOINT_LIMITS,
        maxWireBytes: maxReviewBytes});
      const reviewPolicyCid = contentCid({version:
        'actql-remote-review-redaction/0.1', redacted: []});
      const originalReview = (subjectCid: string | undefined, claims: readonly string[]) => {
        if (typeof projectReview !== 'function') fail('OriginalEffectReviewUnavailable');
        const {wire, identity} = projectReview(Object.freeze({authorityScopeCid,
          approvalClaims: Object.freeze([...claims]),
          redactionPolicyCid: reviewPolicyCid}), reviewLimits);
        const review = contractControl.admitRunEvidence('review_projection',
          wire, reviewLimits);
        const body = JSON.parse(review.wire);
        if (review.identity !== identity || review.wire !== wire ||
            body.effect_preview_cid !== subjectCid ||
            body.authority_scope_cid !== authorityScopeCid ||
            body.redaction_policy_cid !== reviewPolicyCid ||
            JSON.stringify(body.approval_claims) !== JSON.stringify(claims)) {
          fail('EffectReviewProjectionMismatch');
        }
        return review;
      };
      const common = {accountConfig, accountConfiguration, accountConstruction,
        principal: ownerPrincipal, ...decisionOptions, decide,
        answeringAuthorities: answeringAuthorities === undefined
          ? authorities.map(item => item.reviewerId)
          : [...answeringAuthorities]};
      const read = await createLocalAuthorizationGate(common);
      let commit: Gate | undefined;
      try {
        commit = await createLocalAuthorizationGate({...common,
          requiredClaims: effectClaims,
          deferral: {journal: journalPort as EffectJournalPort & Deferral['journal'], authorities, binding,
            async describe(view) {
              if (view.boundary !== 'effect_commit' &&
                  view.subject.boundary !== 'effect_commit') {
                fail('InvalidEffectCheckpointBoundary');
              }
              await beforeDefer();
              const review = originalReview(view.subject.subject_cid,
                view.requiredClaims.includes('partial_application_accepted')
                  ? ['effect_scope_approved', 'partial_application_accepted']
                  : ['effect_scope_approved']);
              const id = `effect-${runId}`;
              const refs = await evidence!.hold(id, runDefinitionCid, [
                {name: 'review_projection', wire: review.wire, artifactCid: review.identity},
                {name: 'continuation_record', wire: continuationWire},
              ]);
              const created = now();
              const expires = checkpointEnd(created, requestedStop === undefined
                ? undefined : contractControl.requestedEffectStopLifetime(requestedStop));
              return {priorStatus: 'running', declaredResults, body: {
                checkpoint_id: `${runId}-effect-commit`, run_id: runId,
                run_definition_cid: runDefinitionCid,
                continuation_state_cid: refs[1],
                subject: {kind: 'run_unit', run_id: runId, unit_id: unitId,
                  continuation: 'resume_unit'},
                required_artifact: {artifact_cid: view.subject.subject_cid},
                review_projection_cid: review.identity,
                human_summary: 'Approve the complete Effect Set',
                created_at: new Date(created).toISOString(),
                expires_at: new Date(expires).toISOString(),
              }};
            },
          }});
        if (read.configurationCid !== gate.configurationCid ||
            commit!.configurationCid !== gate.configurationCid) {
          fail('EffectCheckpointConfigurationChanged');
        }
        const stopLimits = Object.freeze({...INSTALLED_EFFECT_CHECKPOINT_LIMITS,
          maxWireBytes: maxReviewBytes});
        const stopCurrent = () => {
          if (requestedStop === undefined) fail('RequestedEffectStopUnavailable');
          assertRequestedStopCurrent!();
          read.assertConfigurationCurrent();
          commit!.assertConfigurationCurrent();
        };
        // Project the existing journal's admitted body, not caller-supplied
        // approval DATA. Common rechecks its original Run/Preview/intent and
        // canonical checkpoint CID before an ownership admission is returned.
        const checkedStopView = (resumption: Resumption, subjectCid: string | undefined) => {
          const held = resumption?.claim as (Parameters<Journal['admitResume']>[0] &
            Readonly<{claim?: Parameters<Journal['admitResume']>[0]; checkpointCid?: string}>) | undefined;
          const claim = held?.claim ?? held;
          const admitted = journalPort.admitResume(claim!,
            {checkpointCid: held?.checkpointCid});
          const view = journalPort.inspect(admitted.checkpointCid);
          if (view?.reasonCode !== 'user_requested_stop') return undefined;
          stopCurrent();
          if (view.runId !== runId || view.runDefinitionCid !== runDefinitionCid ||
              view.subject.kind !== 'run_unit' || view.subject.unit_id !== unitId ||
              view.requiredArtifact.cid !== subjectCid ||
              view.continuationStateCid !== `sha256:${hex(continuationWire)}`) {
            fail('RequestedEffectStopBindingChanged');
          }
          const sealed = JSON.parse(contractControl.sealRequestedEffectStop(
            requestedStop, JSON.stringify({
              version: 'actql-execution-checkpoint/0.1',
              checkpoint_id: view.checkpointId, run_id: view.runId,
              run_definition_cid: view.runDefinitionCid,
              continuation_state_cid: view.continuationStateCid,
              subject: view.subject, phase: view.phase, kind: view.kind,
              required_artifact: {artifact_type: view.requiredArtifact.type,
                artifact_cid: view.requiredArtifact.cid},
              requirements: view.requirements,
              review_projection_cid: view.reviewProjectionCid,
              reason_code: view.reasonCode, human_summary: view.humanSummary,
              created_at: view.createdAt, expires_at: view.expiresAt,
            }), continuationWire, stopLimits));
          if (sealed.checkpoint_cid !== view.checkpointCid) {
            fail('RequestedEffectStopBindingChanged');
          }
          stopCurrent();
          return view;
        };
        const requestStop = async (decision: Decision, options: NonNullable<AuthorizationArguments[2]>) => {
          stopCurrent();
          options.signal?.throwIfAborted();
          await beforeDefer();
          stopCurrent();
          const review = originalReview(decision.subjectCid, ['effect_scope_approved']);
          const refs = await evidence!.hold(`effect-${runId}`, runDefinitionCid, [
            {name: 'review_projection', wire: review.wire, artifactCid: review.identity},
            {name: 'continuation_record', wire: continuationWire},
          ]);
          stopCurrent();
          options.signal?.throwIfAborted();
          const lifetime = contractControl.requestedEffectStopLifetime(requestedStop);
          const created = now();
          const expires = checkpointEnd(created, lifetime);
          const body = {version: 'actql-execution-checkpoint/0.1',
              checkpoint_id: `${runId}-effect-commit`, run_id: runId,
              run_definition_cid: runDefinitionCid,
              continuation_state_cid: refs[1],
              subject: {kind: 'run_unit', run_id: runId, unit_id: unitId,
                continuation: 'resume_unit'}, phase: 'commit', kind: 'effect_set',
              required_artifact: {artifact_type: 'effect_set_preview',
                artifact_cid: decision.subjectCid},
              requirements: ['effect_scope_approved'],
              review_projection_cid: review.identity, reason_code: 'user_requested_stop',
              human_summary: 'Review the requested first Effect Set',
              created_at: new Date(created).toISOString(),
              expires_at: new Date(expires).toISOString(),
            };
          const wire = contractControl.sealRequestedEffectStop(requestedStop,
            JSON.stringify(body), continuationWire, stopLimits);
          stopCurrent();
          // The Journal's existing entry accepts a body, not a sealed artifact.
          // Both existing Common readers must name the same exact artifact;
          // an uncertain/mismatched commit never becomes a returned wait.
          const persisted = await journalPort.persistCheckpoint({body,
            priorStatus: 'running', declaredResults, authorities, binding,
            decisionSubjectCid: contractControl.requestedEffectStopIntentCid(requestedStop),
            requestedClaims: [], configurationCid: commit!.configurationCid});
          if (persisted.checkpointCid !== JSON.parse(wire).checkpoint_cid) {
            fail('RequestedEffectStopCommitMismatch');
          }
          return Object.freeze({boundary: 'effect_commit', action: 'waiting',
            reason: 'user_requested_stop', checkpoint: Object.freeze(persisted)});
        };
        const scopes = [read, commit].map(owner => ({owner, closeAttempted: false,
          released: false}));
        const cleanupPending = () => scopes.some(scope => !scope.released);
        const close = () => {
          let failure;
          for (const scope of scopes) {
            if (scope.released) continue;
            try {
              const recover = scope.closeAttempted;
              scope.closeAttempted = true;
              const result = recover ? scope.owner.cleanup() : scope.owner.close();
              scope.released = result !== false && scope.owner.cleanupPending() === false;
            } catch (error) { failure ??= error; }
          }
          if (failure !== undefined) throw failure;
          return !cleanupPending();
        };
        return Object.freeze({
          async authorize(boundary: AuthorizationArguments[0], scope: AuthorizationArguments[1], options: NonNullable<AuthorizationArguments[2]> = {}) {
            if (boundary === 'acquisition' && targetReads !== undefined) {
              return targetReads.authorize(scope, options);
            }
            const decision = await (boundary === 'effect_commit' ? commit! : read)
              .authorize(boundary, scope, options);
            // A genuine delegated Checkpoint already stops this exact Preview.
            // Neither an Account Allow nor an immediate Host permit discharges
            // the independent user-requested restriction.
            return boundary === 'effect_commit' && requestedStop !== undefined &&
              decision.action === 'dispatch' ? requestStop(decision, options) : decision;
          },
          async resume(boundary: ResumeArguments[0], scope: ResumeArguments[1], options: NonNullable<ResumeArguments[2]> = {}) {
            const view = checkedStopView(options.resumption, options.subjectCid);
            if (view === undefined) return commit!.resume(boundary, scope, options);
            if (boundary !== 'effect_commit') fail('RequestedEffectStopBindingChanged');
            // This approval releases only the continuation restriction. Current
            // Delegate still needs a genuine current Host answer; these review
            // claims must never be supplied to executionAuthorizationAnswer.
            const decision = await commit!.authorize(boundary, scope,
              {...options, allowDeferral: false});
            checkedStopView(options.resumption, options.subjectCid);
            return decision;
          },
          continuationAdmission(resumption: Resumption, subjectCid?: string) {
            if (checkedStopView(resumption, subjectCid) === undefined) return undefined;
            const owned = admitResumedDispatch(journalPort, resumption,
              {configurationCid: commit!.configurationCid, approvalClaims: false});
            if (owned.detail !== undefined) fail(owned.detail, owned.error);
            stopCurrent();
            return owned.admission;
          },
          assertCurrent() {
            read.assertConfigurationCurrent();
            commit!.assertConfigurationCurrent();
          },
          close, cleanup: close, cleanupPending,
        });
      } catch (error) {
        read.close();
        commit?.close();
        throw error;
      }
    },
    ...computationSource,
    async effectContinuation(view: CheckpointView) {
      if (view?.kind !== 'effect_set' || view.prepareAttemptId !== null) {
        fail('InvalidEffectContinuation');
      }
      const held = await evidence!.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) {
        fail('EffectContinuationRunMismatch');
      }
      return held.record('continuation_record', view.continuationStateCid);
    },
    effectRunState(runId: string, runDefinitionCid: string) {
      if (!IDENTIFIER.test(runId ?? '') ||
          typeof runDefinitionCid !== 'string') {
        fail('InvalidEffectContinuation');
      }
      let view = journal!.activeRunCheckpoint(runId);
      if (view === undefined) {
        let after = '';
        for (;;) {
          const page = journal!.listRunCheckpoints({after, limit: PAGE});
          view = page.find(item => item.runId === runId);
          if (view !== undefined || page.length < PAGE) break;
          after = page.at(-1)!.checkpointCid;
        }
      }
      if (view === undefined) return undefined;
      if (!['effect_set', 'read_access', 'model_invocation'].includes(view.kind) || view.runId !== runId ||
          view.runDefinitionCid !== runDefinitionCid ||
          view.prepareAttemptId !== null) {
        fail('EffectContinuationRunMismatch');
      }
      return journal!.getRunState(runId);
    },
    // Route only through the journal's exact current continuation. The
    // transition owner fences physical entry; this lookup grants no authority.
    cancelEffectContinuation(runId: string, runDefinitionCid: string) {
      const view = journal!.activeRunCheckpoint(runId);
      if (!['effect_set', 'read_access', 'model_invocation'].includes(view?.kind!) ||
          view!.runId !== runId || view!.runDefinitionCid !== runDefinitionCid ||
          view!.prepareAttemptId !== null) return false;
      const state = journal!.getRunState(runId);
      if (state?.status === 'waiting_checkpoint') {
        return journal!.cancelCheckpoint(view!.checkpointCid).outcome === 'cancelled';
      }
      if (state?.status === 'resuming') {
        return journal!.cancelUnsentResume(view!.checkpointCid).outcome === 'cancelled';
      }
      return false;
    },
    hasUnresolvedSourceStart(runId: string, runDefinitionCid: string) {
      const view = journal!.activeRunCheckpoint(runId);
      return view?.kind === 'read_access' && view.runId === runId &&
        view.runDefinitionCid === runDefinitionCid &&
        view.requiredArtifact.type === 'read_scope' &&
        (view.checkpointId === computationSourceCheckpointId(runId,
          view.requiredArtifact.cid) ||
          // Already sealed legacy Checkpoints retain their original identity.
          view.checkpointId.startsWith(`${runId}-source-`)) &&
        journal!.hasStartedResume(view.checkpointCid);
    },
    hasUnresolvedEffectTargetStart(runId: string, runDefinitionCid: string) {
      const view = journal!.activeRunCheckpoint(runId);
      return view?.kind === 'read_access' && view.runDefinitionCid === runDefinitionCid &&
        view.checkpointId.startsWith(`${runId}-target-`) &&
        journal!.hasStartedResume(view.checkpointCid);
    },
    hasUnresolvedModelStart(runId: string, runDefinitionCid: string) {
      const view = journal!.activeRunCheckpoint(runId);
      return view?.kind === 'model_invocation' && view.runId === runId &&
        view.runDefinitionCid === runDefinitionCid &&
        journal!.hasUnresolvedModelCalls(runId);
    },
    // Principals admitted to the Checkpoint operations at all. Each
    // operation still applies its own authorization.
    admitsCheckpointPrincipal: (principal: string) => principal === ownerPrincipal ||
      readers.has(principal) || answerers.has(principal),

    // Decide Run acceptance for one Host-resolved request before any Run
    // definition exists. `dispatch`: continue; `held`: the durable held
    // reply; refusals throw with their ACTQL runtime code and record nothing.
    async acceptRun({requested, captured, signal}: AcceptanceInput) {
      captureInventory(captured);
      const prepareAttemptId = prepareAttemptIdOf(captured.requestId);
      const subject = requestSubject(requested);
      const request = {version: 'actql-remote-invocation-request/0.1',
        subject, subject_cid: contentCid(subject)};
      const requestCid = contentCid(request);
      const existing = journal!.getPreparation(prepareAttemptId);
      if (existing !== undefined) {
        // The held request's durable fingerprint is its evidence ledger's
        // request CID. Unavailable evidence is never a reason to skip the
        // comparison.
        let ledger;
        try { ledger = await evidence!.open(prepareAttemptId); }
        catch (error) { fail('HeldRequestEvidenceUnavailable', error); }
        if (ledger.requestCid !== requestCid) {
          fail('ClientRequestIntentConflict');
        }
        // The public request fingerprint does not describe Host-installed
        // physical source bindings. A held plural request also matches its
        // exact private acquisition inventory. Its original full capture
        // remains authoritative; equivalent Program text is not a new intent.
        if (['waiting_checkpoint', 'resuming'].includes(existing.status)) {
          const captures = ledger.held('captured_input');
          if (captures.length !== 1) fail('HeldAcquisitionChanged');
          const original = await ledger.record('captured_input', captures[0]) as CapturedRequest;
          if ((pluralCapture(captured) || pluralCapture(original)) &&
              capturedValueCid(acquisitionsOf(original)) !==
                capturedValueCid(acquisitionsOf(captured))) {
            fail('HeldAcquisitionChanged');
          }
        }
        const reply = held(prepareAttemptId, captured.requestId);
        return reply === undefined ? {kind: 'run_created'}
          : {kind: 'held', held: reply};
      }
      const answering = answeringAuthorities ??
        authorities.map(item => item.reviewerId);
      const deferring = await createLocalAuthorizationGate({accountConfig, accountConstruction,
        accountConfiguration, principal: ownerPrincipal, ...decisionOptions,
        decide,
        answeringAuthorities: decide === undefined ? undefined : answering,
        // Run-scoped Model and Effect approvals remain owned by their existing
        // continuation paths. Unsupported pre-Run waits must not be admitted.
        deferral: captured.submission === undefined
          ? deferralFor({prepareAttemptId, request, requestCid,
            captured, answering}) as ReturnType<typeof deferralFor> & Deferral : undefined});
      let sealed: string | undefined;
      let decision: Decision;
      try { decision = await deferring.authorize('preparation', tuple, {
        subjectCid: request.subject_cid, signal,
        // Two-phase: the account outcome and any immediate Host answer are
        // decided on the request subject; only a deferred decision seals the
        // prepared invocation (bound to the captured submission).
        sealDeferredSubject: async () => {
          await recordHeld(prepareAttemptId, captured.requestId);
          sealed = contentCid({
            version: 'actql-remote-prepared-invocation/0.1',
            request_cid: requestCid,
            captured_submission_cid: capturedValueCid(captured),
            site_key: siteKey,
            realization_key: realizationKey,
          });
          return sealed;
        },
      }); } finally { deferring.close(); }
      if (decision.action === 'dispatch') return {kind: 'dispatch'};
      if (decision.action === 'waiting') {
        return {kind: 'held', held: held(prepareAttemptId,
          captured.requestId)};
      }
      // Evidence held for a Checkpoint that was never committed has no
      // remaining need.
      if (sealed !== undefined) await evidence!.abandon(prepareAttemptId);
      throw refusal(decision);
    },

    // Decide the source read of a new request whose Run acceptance was just
    // allowed or permitted, before any Run Definition or provider I/O. A
    // delegated read is held as a `read_access` `prepare_attempt`
    // Checkpoint (the held reply); refusals throw and record nothing.
    async acceptAcquisition({requested, captured, signal}: AcceptanceInput) {
      const inventory = captureInventory(captured);
      if (inventory.length === 0 || installedSources.length === 0) {
        return {kind: 'dispatch'};
      }
      const prepareAttemptId = prepareAttemptIdOf(captured.requestId);
      const subject = requestSubject(requested);
      const request = {version: 'actql-remote-invocation-request/0.1',
        subject, subject_cid: contentCid(subject)};
      const requestCid = contentCid(request);
      // Resolve every installed authorization before deciding any member.
      // The Host's acquisition owner durably reserves the captured inventory
      // before physical I/O when no Checkpoint is needed.
      for (const occurrence of inventory) installedSource(occurrence);
      const permits = new Map<string, ReadApproval>();
      admittedReads.delete(captured.requestId);
      for (const occurrence of inventory) {
        const decision = await decideRead({prepareAttemptId, request,
          requestCid, captured, occurrence, port: journal!, signal});
        if (decision.action === 'dispatch') {
          // A Host permit is process-local and occurrence-specific. Never
          // retain a partial pair if a later decision holds or refuses.
          if (decision.basis === 'host_permit') {
            permits.set(occurrenceKey(occurrence), admittedRead(captured,
              occurrence));
          }
          continue;
        }
        if (decision.action === 'waiting') {
          return {kind: 'held', held: held(prepareAttemptId,
            captured.requestId)};
        }
        await evidence!.abandon(prepareAttemptId);
        throw refusal(decision);
      }
      if (permits.size > 0) admittedReads.set(captured.requestId, permits);
      return {kind: 'dispatch'};
    },

    ...acquisitionAccess,

    // The dispatch of a held read ended; its admitted approval is no longer
    // used for provider I/O in this process.
    releaseAcquisition(requestId: string) { admittedReads.delete(requestId); },

    // Durable request cancellation of a held request (before or after its
    // Run exists); the caller applies it to an existing Run.
    cancelHeld(requestId: string) {
      const cancelled = journal!.requestPreparationCancellation(
        prepareAttemptIdOf(requestId));
      return Object.freeze({outcome: cancelled.outcome});
    },

    // Whether this Host held the request (a prepare attempt exists): its Run
    // may start only through the resumed authorization.
    heldOrigin(requestId: string) {
      return journal!.getPreparation(prepareAttemptIdOf(requestId)) !==
        undefined;
    },

    heldLookup(requestId: string) {
      return held(prepareAttemptIdOf(requestId), requestId);
    },

    prepareAttemptIdOf,

    ...review,

    // Install the Host's physical port for held requests ({inspect, resume,
    // abandon, observe}), then sweep once (Host start).
    start(port: HostPort) {
      host = port;
      return sweep();
    },
    sweep,

    // The checkpoint-journal Run created by a resumed request ended.
    runFinished(runId: string, status: string) {
      const run = journal!.getRunState(runId);
      if (run === undefined || journal!.isTerminalRunOutcome(run.status) ||
          run.status !== 'running') return;
      journal!.finishRun(runId, {status});
      // Retention settles in the owned sweep (which stop() waits for), or in
      // close(); never as a detached write.
      void sweep();
    },

    // Stop starting new resumes; running work may still end its Runs.
    stop,
    // After the Host's running dispatches settled: settle retention, then
    // release the evidence owner and the journal!. Returns what is left for
    // the next owner (retention that could not complete yet).
    async close() {
      await stop();
      admittedReads.clear();
      gate.close();
      effectTargetGate?.close();
      for (const installed of installedEffectTargets) installed.gate!.close();
      resumeGate.close();
      for (const installed of installedSources) {
        installed.gate!.close();
        installed.resumeGate!.close();
      }
      decisionBudget.close();
      let retention;
      try { retention = await evidence!.settle(); }
      finally {
        await evidence!.close();
        journal!.close();
        sourceConsumerClosed = true;
      }
      sourceInventory?.custody.retire();
      return Object.freeze({pendingRetention: retention.pending,
        pendingAuthorization: decisionBudget.cleanupPending()});
    },
  });
  } catch (cause) {
    decisionBudget.close();
    if (journal === undefined) sourceConsumerClosed = true;
    let retainedFailure = cause;
    if (journal !== undefined) {
      retainedFailure = await retainInstalledHostInitializationFailure(cause,
        {journal, store: evidence});
      originalSetupCleanup = (retainedFailure as Awaited<ReturnType<typeof retainInstalledHostInitializationFailure>>).cleanupHandle;
    }
    try {sourceInventory?.custody.retire();}
    catch (cleanupIssue) {
      // Keep the original admission failure. The actual initial Host retains
      // this same borrow/callback and retries only its cleanup responsibility.
      sourceInventory!.custody.cleanupIssue = cleanupIssue;
    }
    // Before journal custody exists, preserve the original admission error.
    throw retainedFailure;
  }
}
