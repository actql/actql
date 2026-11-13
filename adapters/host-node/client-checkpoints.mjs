// Checkpoint connection of the installed Remote Host. Run acceptance on the
// Host's protected Site is a protected operation: the account decides allow,
// deny or delegate for the Host-resolved tuple (Site key, realization key,
// write). A delegated request the Host defers is held as a durable
// `prepare_attempt` Checkpoint before any Run definition, Run or Site
// dispatch exists. Answers are admitted per Checkpoint by the common
// Checkpoint journal; an approved request is resumed by this Host (on start
// and after answers), never by an in-memory callback alone and never by the
// Client. No second approval state machine lives here.
import {recordCheckpointApproval} from
  '../host-common/checkpoint-approval.mjs';
import {createHash, createPublicKey, createPrivateKey, randomUUID, sign,
  verify} from 'node:crypto';
import {mkdir, open as openFile, readFile, rename} from
  'node:fs/promises';
import {join} from 'node:path';
import {ExecutionAuthorizationError, createAuthorizationDecisionBudget,
  admitResumedDispatch} from
  '../host-common/authorization-gate.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {canonicalJson, contentCid, createLocalAuthorizationGate} from
  './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {BOUND_SOURCE_SUBMISSION, validBoundSourceOccurrence} from './ordinary-source-binding.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey,
  openContinuationEvidence} from './local-continuation-evidence.mjs';
import {loadCheckpointRuntime, openSqliteCheckpointJournal} from
  './sqlite-checkpoint-journal.mjs';
import {retainInstalledHostInitializationFailure} from
  './installed-host-cleanup.mjs';
import {modelCheckpointMetadata} from './model-checkpoint-metadata.mjs';
import {INSTALLED_EFFECT_CHECKPOINT_LIMITS} from
  '../host-common/installed-checkpoint-codec-limits.mjs';
import {EFFECT_TARGET_CONTINUATION, effectTargetReadScope} from
  './effect-target-read-inventory.mjs';
import {MAX_INSTALLED_SOURCE_AUTHORITIES} from './installed-source-limits.mjs';
import {MAX_INSTALLED_EFFECT_PROFILES} from './installed-effect-limits.mjs';
import {validCheckpointLookup} from '../../packages/client-wire/index.mjs';
import {selectOriginalInferMetadataAcquisition,
  selectOriginalInferStoreBootstrapAcquisition,
  selectOriginalInferResourceCodecAcquisition} from './infer-operation.mjs';

const IDENTIFIER = /^[A-Za-z0-9._:-]{1,128}$/u;
const MAX_REVIEW_BYTES = INSTALLED_EFFECT_CHECKPOINT_LIMITS.maxWireBytes;
const MAX_PAGE = 100;
const PAGE = 100;
const LOOKUP_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
const MULTI_SOURCE_SUBMISSION = 'actql-remote-multi-source-submission/0.1';
const KEYED_SOURCE_SUBMISSION = 'actql-remote-keyed-source-submission/0.1';
const pluralCapture = captured => [MULTI_SOURCE_SUBMISSION, KEYED_SOURCE_SUBMISSION, BOUND_SOURCE_SUBMISSION]
  .includes(captured.version);
// The existing read-scope CID binds the full checked occurrence. Include the
// original Run separately and keep the identifier bounded even for a maximal
// Run ID; neither a Source slot nor a Unit index is a global Checkpoint ID.
function computationSourceCheckpointId(runId, scopeCid) {
  return `source-${contentCid({run_id: runId, read_scope_cid: scopeCid}).slice(7)}`;
}

const MODEL_CHECKPOINT_STORAGE = 'actql-installed-model-checkpoint-storage/0.1';
export const MAX_MODEL_INPUT_BYTES = 3 * 1024 * 1024;

function coded(code, detail) {
  return Object.assign(new Error(code, detail === undefined ? undefined
    : {cause: detail}), {code});
}
const fail = (code, detail) => { throw coded(code, detail); };
const without = (value, ...keys) => Object.fromEntries(
  Object.entries(value).filter(([key]) => !keys.includes(key)));
const hex = value => createHash('sha256').update(value).digest('hex');
// Captured caller input is opaque data, not an installation identity.
const capturedValueWire = value => canonicalValueJson(value, {dataKeys: true});
const capturedValueCid = value => `sha256:${hex(capturedValueWire(value))}`;
const freezeSavedData = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freezeSavedData(child);
    Object.freeze(value);
  }
  return value;
};

// This is an installed Host-private bounded capture, not a new Run schema.
// A plural capture is never inferred by reinterpreting the singular field.
function acquisitionsOf(captured) {
  if (!pluralCapture(captured)) {
    if (captured.acquisitions !== undefined) fail('HeldAcquisitionChanged');
    return captured.acquisition === undefined ? [] : [captured.acquisition];
  }
  // A keyed Source can share task 0 with its Direct prefix (Content) or
  // occupy task 1. Retain that checked coordinate, never derive it from the
  // acquisition's position in this two-Source inventory.
  if (captured.acquisition !== undefined ||
      !Array.isArray(captured.acquisitions) ||
      captured.acquisitions.length !== 2 ||
      captured.acquisitions.some((item, index) =>
        !(captured.version === BOUND_SOURCE_SUBMISSION ? validBoundSourceOccurrence(item, index)
          : captured.version === KEYED_SOURCE_SUBMISSION
          ? Number.isSafeInteger(item?.stage) && item.stage >= 0 &&
            Number.isSafeInteger(item.input) && item.input >= 0 &&
            (index === 0 ? item.task === 0 : item.task === 0 || item.task === 1) &&
            (index === 0 ? typeof item.checkedSource?.requirementCid === 'string' &&
              item.checkedSource.selectionCid === undefined
              : typeof item.checkedSource?.selectionCid === 'string' &&
                item.checkedSource.requirementCid === undefined &&
                typeof item.checkedSource.programCid === 'string' &&
                typeof item.checkedSource.parametersCid === 'string' &&
                Number.isSafeInteger(item.checkedSource.step) && item.checkedSource.step >= 0)
          : item?.stage === index && item.input === 0 && item.task === index &&
            typeof item.checkedSource?.requirementCid === 'string') ||
        typeof item.checkedSource?.sourceRef !== 'string' ||
        item.readTuple?.operation !== 'read' ||
        item.physicalBinding === undefined)) {
    fail('HeldAcquisitionChanged');
  }
  if (captured.version === KEYED_SOURCE_SUBMISSION &&
      (captured.acquisitions[0].stage !== captured.acquisitions[1].stage ||
       captured.acquisitions[0].input === captured.acquisitions[1].input)) {
    fail('HeldAcquisitionChanged');
  }
  return captured.acquisitions;
}
const occurrenceIdentity = occurrence => ({stage: occurrence.stage,
  input: occurrence.input, task: occurrence.task,
  ...(occurrence.checkedSource.selectionCid === undefined
    ? {requirement_cid: occurrence.checkedSource.requirementCid}
    : {selection_cid: occurrence.checkedSource.selectionCid})});
const occurrenceKey = occurrence => occurrence.stage === undefined
  ? 'singular' : canonicalJson(occurrenceIdentity(occurrence));

function trustedReviewers(reviewers) {
  if (!Array.isArray(reviewers) || reviewers.length === 0) {
    fail('InvalidCheckpointReviewers');
  }
  const byKey = new Map();
  for (const reviewer of reviewers) {
    if (!IDENTIFIER.test(reviewer?.keyId ?? '') ||
        !IDENTIFIER.test(reviewer?.reviewerId ?? '') ||
        typeof reviewer.principalId !== 'string' || !reviewer.principalId ||
        byKey.has(reviewer.keyId)) {
      fail('InvalidCheckpointReviewers');
    }
    byKey.set(reviewer.keyId, Object.freeze({
      keyId: reviewer.keyId,
      reviewerId: reviewer.reviewerId,
      principalId: reviewer.principalId,
      publicKey: createPublicKey(reviewer.publicKey),
    }));
  }
  return byKey;
}

function principals(values, code) {
  if (values === undefined) return new Set();
  if (!Array.isArray(values) || values.some(value =>
    typeof value !== 'string' || !value)) fail(code);
  return new Set(values);
}

// The installed adapter's authorization object is an opaque in-process
// selector. Retained identity uses only the checked Mapping and account
// bindings; caller-created lookalikes cannot select an authority.
function captureEffectTargets(effectTargets) {
  const invalid = () => fail('InvalidRemoteHostEffectTargets');
  const text = value => typeof value === 'string' && value.length > 0;
  if (!Array.isArray(effectTargets) ||
      effectTargets.length > MAX_INSTALLED_EFFECT_PROFILES) invalid();
  const authorities = new Set();
  const byRef = new Map();
  const byCid = new Map();
  return Array.from(effectTargets, item => {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) invalid();
    const {selectors, authorization} = item;
    if (authorization === null || typeof authorization !== 'object' ||
        Array.isArray(authorization) || authorities.has(authorization) ||
        !Array.isArray(selectors) || selectors.length === 0) invalid();
    authorities.add(authorization);
    const mappings = new Map();
    for (const selector of selectors) {
      if (!text(selector?.kind) || !text(selector.target) ||
          !text(selector.mappingRef) ||
          !/^sha256:[0-9a-f]{64}$/u.test(selector.mappingCid ?? '') ||
          selector.effectId !== undefined && !text(selector.effectId)) invalid();
      const {mappingRef, mappingCid, target} = selector;
      const previous = byRef.get(mappingRef) ?? byCid.get(mappingCid);
      if (previous !== undefined && (previous.authorization !== authorization ||
          previous.mappingRef !== mappingRef || previous.mappingCid !== mappingCid ||
          previous.target !== target)) invalid();
      const mapping = {authorization, mappingRef, mappingCid, target};
      byRef.set(mappingRef, mapping);
      byCid.set(mappingCid, mapping);
      mappings.set(mappingRef, Object.freeze({mappingRef, mappingCid}));
    }
    // A profile has at least one uniquely owned Mapping, so the common
    // CheckEnvironment member bound also bounds this authority inventory.
    if (byRef.size > MAX_INSTALLED_EFFECT_PROFILES) invalid();
    const context = authorization.context;
    return {authority: authorization,
      mappings: Object.freeze([...mappings.values()]),
      configuration: Object.freeze({
        accountConfiguration: authorization.accountConfiguration,
        context: Object.freeze({...context}),
      })};
  });
}

// Account admission and signed Checkpoint continuation are distinct Host
// capabilities. An omitted signer configuration does not make an admitted
// Account invalid; any explicitly selected Checkpoint option still takes the
// existing complete validation/installation path below.
export async function installHostRunAcceptance(options) {
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
  const {accountConfig, accountConfiguration, decisionTimeoutMs = 30_000,
    maxInFlightDecisions = 16, maxRetainedDecisions = 1024} = authorization;
  const decisionBudget = createAuthorizationDecisionBudget({
    maxInFlightDecisions, maxRetainedDecisions});
  let gate;
  try {
    gate = await createLocalAuthorizationGate({accountConfig,
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
    async acceptRun({requested, captured, signal}) {
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
  effectTargets,
  modelResumeVerifier,
  now = () => Date.now()}) {
  if (authorization === undefined) return undefined;
  if (authorization === null || typeof authorization !== 'object') {
    fail('InvalidRemoteHostAuthorization');
  }
  // Inventory admission and Checkpoints share one aggregate authority bound.
  if (sources !== undefined && (source !== undefined ||
      !Array.isArray(sources) || sources.length < 1 ||
      sources.length > MAX_INSTALLED_SOURCE_AUTHORITIES ||
      sources.some(item => typeof item?.sourceRef !== 'string' ||
        item.sourceRef.length === 0) ||
      new Set(sources.map(item => item.sourceRef)).size !== sources.length)) {
    fail('InvalidRemoteHostSources');
  }
  if (effectTargets !== undefined && effectTarget !== undefined) {
    fail('InvalidRemoteHostEffectTargets');
  }
  // Snapshot every plural account and context before installation awaits.
  const installedEffectTargets = effectTargets === undefined ? []
    : captureEffectTargets(effectTargets);
  const {accountConfig, accountConfiguration, reviewers, reviewReaders,
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
  const hostPrivateKey = createPrivateKey(hostKey.privateKey);
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
  let journal;
  let evidence;
  try {
  const state = join(root, 'checkpoints');
  let privateKey;
  try { privateKey = await loadPrivateEvidenceKey(state); }
  catch (error) {
    if (error?.code !== 'PrivateEvidenceKeyUnavailable') throw error;
    await createPrivateEvidenceKey(state);
    privateKey = await loadPrivateEvidenceKey(state);
  }

  // The current trusted authorization context: principal, account and the
  // admitted configuration identity. A resume under another one fails
  // revalidation before any protected work.
  const gate = await createLocalAuthorizationGate({accountConfig,
    accountConfiguration, principal: ownerPrincipal, ...decisionOptions});
  const configured = gate.configurationCid !== undefined;
  // The source's read decision uses the source installation's own account
  // configuration and context (the same one its adapter rechecks before
  // provider I/O). Without a decision function or deferral a delegated read
  // is unsupported here, so this gate is also the current-authority check.
  const installedSources = [];
  for (const installed of sources ?? (source === undefined ? [] : [source])) {
    // Preserve the singular installation owner's original validation and
    // journal-custody ordering. The new plural inventory is copied once.
    const context = sources === undefined ? undefined : installed.context;
    const configuration = sources === undefined ? installed : Object.freeze({
      sourceRef: installed.sourceRef,
      accountConfiguration: installed.accountConfiguration,
      ...(context === undefined ? {} : {context: Object.freeze({...context})}),
    });
    installedSources.push({configuration,
      gate: await createLocalAuthorizationGate({
        accountConfiguration: configuration.accountConfiguration,
        context: configuration.context, ...decisionOptions})});
  }
  const sourceGate = sources === undefined ? installedSources[0]?.gate
    : undefined;
  if (effectTarget !== undefined) effectTarget = Object.freeze({
    accountConfiguration: effectTarget.accountConfiguration,
    context: Object.freeze({...effectTarget.context}),
  });
  const effectTargetGate = effectTarget === undefined ? undefined :
    await createLocalAuthorizationGate({
      accountConfiguration: effectTarget.accountConfiguration,
      context: effectTarget.context, ...decisionOptions});
  for (const installed of installedEffectTargets) {
    installed.gate = await createLocalAuthorizationGate({
      accountConfiguration: installed.configuration.accountConfiguration,
      context: installed.configuration.context, ...decisionOptions});
  }
  const effectTargetAuthorities = new Map(installedEffectTargets.map(installed =>
    [installed.authority, installed]));
  function installedSource(occurrence) {
    const installed = sources === undefined ? installedSources[0]
      : installedSources.find(item => item.configuration.sourceRef ===
        occurrence.checkedSource.sourceRef);
    if (installed === undefined ||
        (installed.configuration.sourceRef !== undefined &&
          installed.configuration.sourceRef !== occurrence.checkedSource.sourceRef)) {
      fail('HeldAcquisitionChanged');
    }
    return installed;
  }
  function captureInventory(captured) {
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
            configuration_cid: read.configurationCid ?? null,
            context_cid: read.contextCid})))
          .sort((left, right) => left.mapping_ref < right.mapping_ref ? -1
            : left.mapping_ref > right.mapping_ref ? 1 : 0)}),
      ...(sources === undefined ? {} : {source_authorization_bindings:
        installedSources.map(({configuration, gate: read}) => ({
          source_ref: configuration.sourceRef,
          configuration_cid: read.configurationCid ?? null,
          context_cid: read.contextCid,
        })).sort((left, right) => left.source_ref < right.source_ref ? -1 : 1)}),
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
  const indexPath = id => join(heldIndex, `${id}.json`);
  // The request ID of a held prepare attempt (not private: lookups are keyed
  // by it), written durably (file and directory) before its Checkpoint is
  // persisted. It is only an index: a missing or unreadable entry is
  // rebuilt from the attempt's captured submission.
  const syncDirectory = async path => {
    const handle = await openFile(path, 'r');
    try { await handle.sync(); } finally { await handle.close(); }
  };
  async function recordHeld(prepareAttemptId, requestId) {
    const temporary = `${indexPath(prepareAttemptId)}.${process.pid}.tmp`;
    const handle = await openFile(temporary, 'w', 0o600);
    try {
      await handle.writeFile(JSON.stringify({version:
        'actql-remote-held-request/0.1', prepare_attempt_id: prepareAttemptId,
      request_id: requestId}));
      await handle.sync();
    } finally { await handle.close(); }
    await rename(temporary, indexPath(prepareAttemptId));
    await syncDirectory(heldIndex);
  }
  async function indexedRequestId(prepareAttemptId) {
    try {
      const record = JSON.parse(await readFile(indexPath(prepareAttemptId),
        'utf8'));
      return record.prepare_attempt_id === prepareAttemptId &&
        typeof record.request_id === 'string' ? record.request_id : undefined;
    } catch { return undefined; }
  }

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
      return {hostKeyId: hostKey.keyId,
        signature: sign(null, Buffer.from(preimage, 'utf8'),
          hostPrivateKey).toString('base64')};
    },
  });

  // Retention of held private evidence follows the journal: a waiting or
  // resuming request keeps it; an ended preparation or a terminal Run
  // releases it.
  evidence = openContinuationEvidence({
    stateDirectory: state, ...privateKey, contractControl,
    isTerminalRunOutcome: journal.isTerminalRunOutcome,
    preparation(prepareAttemptId) {
      if (prepareAttemptId.startsWith('effect-') ||
          prepareAttemptId.startsWith('model-')) {
        const model = prepareAttemptId.startsWith('model-');
        const run = journal.getRunState(prepareAttemptId.slice(
          model ? 6 : 7));
        // Cancellation/expiry can stop unsent work while entered calls still
        // need historical observation and cleanup. Missing discovery is not
        // proof that those immutable Model originals may be retired.
        if (run !== undefined && journal.isTerminalRunOutcome(run.status)) {
          const unresolved = journal.hasUnresolvedModelCalls?.(
            prepareAttemptId.slice(model ? 6 : 7));
          if (model ? unresolved !== false : unresolved === true) return undefined;
        }
        return run === undefined ? undefined :
          {status: 'run_created', runStatus: run.status};
      }
      const current = journal.getPreparation(prepareAttemptId);
      if (current === undefined) return undefined;
      return {status: current.status, runStatus: current.runId === null
        ? undefined : journal.getRunState(current.runId)?.status};
    },
  });

  const tuple = Object.freeze({connection: siteKey, resource: realizationKey,
    operation: 'write'});
  // The gate that continues approved requests: the same configuration and
  // durable journal; a resume never defers again.
  const resumeGate = await createLocalAuthorizationGate({accountConfig,
    accountConfiguration, principal: ownerPrincipal, ...decisionOptions,
    deferral: {journal,
      authorities, binding,
      describe() { fail('ResumeDoesNotDefer'); }}});
  for (const installed of installedSources) {
    installed.resumeGate = await createLocalAuthorizationGate({
      accountConfiguration: installed.configuration.accountConfiguration,
      context: installed.configuration.context, ...decisionOptions,
      deferral: {journal, authorities, binding,
        describe() { fail('ResumeDoesNotDefer'); }}});
  }
  // The read approval admitted immediately before a held request's physical
  // start, for the source adapter's current-authority check that follows in
  // the same process (after a restart a started acquisition is only
  // reconciled, never started again).
  const admittedReads = new Map();
  // The Host-resolved request: this installation scope, the caller's request
  // identity and intent, and the Site and realization it would run on. The
  // caller supplies none of these values directly.
  const requestSubject = requested => Object.freeze({
    version: 'actql-remote-run-acceptance-request/0.1',
    authority_scope_cid: authorityScopeCid,
    namespace_id: namespaceId,
    logical_request_scope_cid: requested.logicalRequestScopeCid,
    intent_fingerprint_cid: requested.intentFingerprintCid,
    site_key: siteKey,
    realization_key: realizationKey,
  });
  // One prepare attempt per request of this installation scope, found again
  // from the request ID alone (a lookup has no Program).
  const prepareAttemptIdOf = requestId => `prepare-${hex(canonicalJson({
    authority_scope_cid: authorityScopeCid, namespace_id: namespaceId,
    request_id: requestId})).slice(0, 40)}`;

  function deferralFor({prepareAttemptId, request, requestCid, captured,
    answering}) {
    return {
      journal,
      authorities,
      binding,
      async describe(view) {
        const capturedWire = capturedValueWire(captured);
        const invocation = {
          version: 'actql-remote-prepared-invocation/0.1',
          request_cid: requestCid,
          captured_submission_cid: capturedValueCid(captured),
          site_key: siteKey,
          realization_key: realizationKey,
        };
        const invocationCid = contentCid(invocation);
        const created = now();
        const expiresAt = new Date(created + checkpointTtlMs).toISOString();
        const displayed = {
          request_id: captured.requestId,
          kind: captured.kind,
          format: captured.kind === 'aql' ? captured.input.format : 'json',
          document: captured.kind === 'aql' ? captured.input.text
            : captured.input,
          parameters: captured.parameters,
          site_key: siteKey,
          realization_key: realizationKey,
          operation: 'write',
        };
        const projection = {
          version: 'actql-run-review-projection/0.1',
          prepared_invocation_cid: invocationCid,
          execution_context_cid: gate.contextCid,
          host_policy_cid: gate.configurationCid,
          approval_claims: ['invocation_scope_approved'],
          authoring_context_cid: contentCid({principal: captured.principalId,
            request_id: captured.requestId}),
          redaction_policy_cid: contentCid({version:
            'actql-remote-review-redaction/0.1', redacted: []}),
          sensitivity: 'restricted',
          retention_class: 'approval-evidence',
          encryption_required: true,
          expires_at: expiresAt,
          displayed_scope: displayed,
          displayed_authoring_context: [{principal: captured.principalId}],
        };
        projection.review_projection_cid = capturedValueCid(projection);
        const reviewWire = capturedValueWire(projection);
        if (Buffer.byteLength(reviewWire, 'utf8') > maxReviewBytes) {
          fail('CheckpointReviewTooLarge');
        }
        const reviewCid = capturedValueCid(JSON.parse(reviewWire));
        const items = [
          {name: 'captured_input', wire: capturedWire},
          {name: 'invocation_request', wire: canonicalJson(request)},
          {name: 'prepared_invocation', wire: canonicalJson(invocation)},
          {name: 'review_projection', wire: reviewWire},
        ];
        const continuation = {
          version: 'actql-remote-continuation/0.1',
          prepare_attempt_id: prepareAttemptId,
          boundary: view.boundary,
          invocation_cid: invocationCid,
          request_subject_cid: request.subject_cid,
          request_id: captured.requestId,
          delegated_subject: JSON.parse(JSON.stringify(view.subject)),
          answering_authorities: [...answering],
          evidence: items.map(({name, wire}) =>
            evidence.reference(prepareAttemptId, name, wire)),
        };
        const continuationCid = contentCid(continuation);
        await evidence.hold(prepareAttemptId, requestCid, [...items,
          {name: 'continuation_record', wire: canonicalJson(continuation)}]);
        return {
          priorStatus: undefined,
          declaredResults: [...captured.resultNames],
          binding,
          body: {
            checkpoint_id: `${prepareAttemptId}-preparation`,
            continuation_state_cid: continuationCid,
            subject: {kind: 'prepare_attempt',
              prepare_attempt_id: prepareAttemptId, continuation: 'start_run'},
            kind: 'run_scope',
            required_artifact: {artifact_type: 'prepared_invocation',
              artifact_cid: invocationCid},
            review_projection_cid: reviewCid,
            human_summary: `Run request ${captured.requestId} on ${siteKey}`,
            created_at: new Date(created).toISOString(),
            expires_at: expiresAt,
          },
        };
      },
    };
  }

  // The pre-acquisition binding of a held read: the request, the exact
  // captured submission, the Host-checked source and the Host-resolved read
  // tuple. It is not a Prepared Invocation: the formal invocation depends on
  // the later source observation and is issued by its owner after it.
  const acquisitionIntent = (requestCid, captured, occurrence) => ({
    version: pluralCapture(captured)
      ? 'actql-remote-multi-source-acquisition-intent/0.1'
      : 'actql-remote-acquisition-intent/0.1',
    request_cid: requestCid,
    captured_submission_cid: capturedValueCid(captured),
    ...(pluralCapture(captured)
      ? {occurrence: occurrenceIdentity(occurrence)} : {}),
    checked_source: occurrence.checkedSource,
    read_tuple: occurrence.readTuple,
    physical_binding: occurrence.physicalBinding,
    ...(captured.version === BOUND_SOURCE_SUBMISSION
      ? {installation_binding: occurrence.installationBinding} : {}),
  });

  // The durable deferral of a request's source read (`read_access`,
  // `prepare_attempt`). `port` persists the Checkpoint: the journal for a new
  // held request, or the current resume claim for one already resuming.
  // `earlier` names the approvals this attempt already holds (checked again
  // on their own before the start).
  function readDeferralFor({prepareAttemptId, request, requestCid, captured,
    occurrence, answering, port, earlier = []}) {
    const {gate: readGate} = installedSource(occurrence);
    return {
      journal: port,
      authorities,
      binding,
      async describe(view) {
        const intent = acquisitionIntent(requestCid, captured, occurrence);
        const intentCid = capturedValueCid(intent);
        const created = now();
        const expiresAt = new Date(created + checkpointTtlMs).toISOString();
        const projection = {
          version: 'actql-run-review-projection/0.1',
          prepared_invocation_cid: intentCid,
          execution_context_cid: readGate.contextCid,
          host_policy_cid: readGate.configurationCid,
          approval_claims: ['invocation_scope_approved'],
          authoring_context_cid: contentCid({principal: captured.principalId,
            request_id: captured.requestId}),
          redaction_policy_cid: contentCid({version:
            'actql-remote-review-redaction/0.1', redacted: []}),
          sensitivity: 'restricted',
          retention_class: 'approval-evidence',
          encryption_required: true,
          expires_at: expiresAt,
          displayed_scope: {
            request_id: captured.requestId,
            kind: captured.kind,
            format: captured.kind === 'aql' ? captured.input.format : 'json',
            document: captured.kind === 'aql' ? captured.input.text
              : captured.input,
            parameters: captured.parameters,
            source: occurrence.checkedSource,
            read_tuple: occurrence.readTuple,
            physical_binding: occurrence.physicalBinding,
            ...(pluralCapture(captured)
              ? {occurrence: occurrenceIdentity(occurrence)} : {}),
          },
          displayed_authoring_context: [{principal: captured.principalId}],
        };
        projection.review_projection_cid = capturedValueCid(projection);
        const reviewWire = capturedValueWire(projection);
        if (Buffer.byteLength(reviewWire, 'utf8') > maxReviewBytes) {
          fail('CheckpointReviewTooLarge');
        }
        const reviewCid = capturedValueCid(JSON.parse(reviewWire));
        const items = [
          {name: 'captured_input', wire: capturedValueWire(captured)},
          {name: 'invocation_request', wire: canonicalJson(request)},
          // The Store's prepared-invocation slot holds the acquisition
          // intent (a distinct version), never a fabricated invocation.
          {name: 'prepared_invocation', wire: capturedValueWire(intent)},
          {name: 'review_projection', wire: reviewWire},
        ];
        const continuation = {
          version: 'actql-remote-continuation/0.1',
          prepare_attempt_id: prepareAttemptId,
          boundary: view.boundary,
          invocation_cid: intentCid,
          request_subject_cid: request.subject_cid,
          request_id: captured.requestId,
          delegated_subject: JSON.parse(JSON.stringify(view.subject)),
          answering_authorities: [...answering],
          earlier_approvals: [...earlier],
          ...(pluralCapture(captured)
            ? {acquisition_occurrence: occurrenceIdentity(occurrence)} : {}),
          evidence: items.map(({name, wire}) =>
            evidence.reference(prepareAttemptId, name, wire)),
        };
        const continuationCid = contentCid(continuation);
        await recordHeld(prepareAttemptId, captured.requestId);
        await evidence.hold(prepareAttemptId, requestCid, [...items,
          {name: 'continuation_record', wire: canonicalJson(continuation)}]);
        return {
          priorStatus: undefined,
          declaredResults: [...captured.resultNames],
          binding,
          body: {
            checkpoint_id: `${prepareAttemptId}-acquisition` +
              (pluralCapture(captured)
                ? `-${hex(occurrenceKey(occurrence)).slice(0, 20)}` : ''),
            continuation_state_cid: continuationCid,
            subject: {kind: 'prepare_attempt',
              prepare_attempt_id: prepareAttemptId, continuation: 'start_run'},
            kind: 'read_access',
            required_artifact: {artifact_type: 'read_scope',
              artifact_cid: intentCid},
            review_projection_cid: reviewCid,
            human_summary: `Read ${occurrence.checkedSource.sourceRef}` +
              ` for request ${captured.requestId}`,
            created_at: new Date(created).toISOString(),
            expires_at: expiresAt,
          },
        };
      },
    };
  }

  // Decide a request's source read for the Host-resolved read tuple. The
  // account allows, denies or delegates; a delegated read is answered by the
  // Host's decision function or held through `port`.
  async function decideRead({prepareAttemptId, request, requestCid,
    captured, occurrence, port, earlier, signal}) {
    const {configuration} = installedSource(occurrence);
    const answering = answeringAuthorities ??
      authorities.map(item => item.reviewerId);
    const intentCid = capturedValueCid(acquisitionIntent(requestCid, captured,
      occurrence));
    const deferring = await createLocalAuthorizationGate({
      accountConfiguration: configuration.accountConfiguration,
      context: configuration.context, ...decisionOptions, decide,
      answeringAuthorities: decide === undefined ? undefined : answering,
      // Epoch-bound submission does not yet expose the complete pre-Run
      // response/cancel/recovery contract. Use the existing gate's unsupported
      // decision before it seals evidence or creates a Checkpoint.
      deferral: captured.submission === undefined
        ? readDeferralFor({prepareAttemptId, request, requestCid,
          captured, occurrence, answering, port, earlier}) : undefined});
    try {
      return await deferring.authorize('acquisition',
        occurrence.readTuple, {subjectCid: intentCid, signal});
    } finally { deferring.close(); }
  }

  function continuedOccurrence(captured, continuation) {
    const inventory = captureInventory(captured);
    if (!pluralCapture(captured)) return inventory[0];
    const identity = continuation.acquisition_occurrence;
    const occurrence = identity === undefined ? undefined : inventory.find(
      item => canonicalJson(occurrenceIdentity(item)) === canonicalJson(identity));
    if (occurrence === undefined) fail('HeldAcquisitionChanged');
    return occurrence;
  }

  function admittedRead(captured, occurrence, {checkpointCid,
    earlier = [], prepareAttemptId} = {}) {
    return Object.freeze({checkpointCid,
      readTuple: occurrence.readTuple, acquisition: occurrence,
      principalId: captured.principalId, earlier: [...earlier],
      prepareAttemptId});
  }

  // The exact held evidence of one prepare attempt, from its ledger: the
  // continuation record, the captured submission and the request, checked
  // against each other.
  async function continuationOf(prepareAttemptId, continuationStateCid) {
    const opened = await evidence.open(prepareAttemptId);
    // Every continuation of one attempt (a Run-acceptance hold and a
    // later read hold) binds the same captured submission; any held one
    // anchors it when no exact one is named.
    const [anchor] = continuationStateCid === undefined
      ? opened.held('continuation_record') : [continuationStateCid];
    if (anchor === undefined) fail('ContinuationEvidenceNotHeld');
    const continuation = await opened.record('continuation_record', anchor);
    const references = new Map(continuation.evidence.map(item =>
      [item.name, item.semantic_cid]));
    const captured = await opened.record('captured_input',
      references.get('captured_input'));
    const request = await opened.record('invocation_request',
      references.get('invocation_request'));
    const invocation = await opened.record('prepared_invocation',
      references.get('prepared_invocation'));
    if ((continuation.boundary === 'acquisition' ? capturedValueCid(invocation)
      : contentCid(invocation)) !== continuation.invocation_cid ||
        invocation.captured_submission_cid !== capturedValueCid(captured) ||
        invocation.request_cid !== opened.requestCid ||
        contentCid(request) !== opened.requestCid ||
        continuation.prepare_attempt_id !== prepareAttemptId) {
      fail('ArtifactIntegrityFailed');
    }
    captureInventory(captured);
    if (continuation.boundary === 'acquisition') {
      const occurrence = continuedOccurrence(captured, continuation);
      if (occurrence === undefined || capturedValueCid(acquisitionIntent(
        opened.requestCid, captured, occurrence)) !== capturedValueCid(invocation)) {
        fail('HeldAcquisitionChanged');
      }
    }
    return {continuation, captured, request};
  }

  // A later read Checkpoint retains the whole earlier approval chain in the
  // same continuation evidence. Reconstruct occurrence grants from exact
  // held records, never from a sourceRef cache or from the last answer alone.
  async function earlierReadApprovals(prepareAttemptId, captured, earlier) {
    const approved = new Map();
    for (const checkpointCid of earlier) {
      const view = journal.inspect(checkpointCid);
      if (view?.prepareAttemptId !== prepareAttemptId) {
        fail('HeldAcquisitionChanged');
      }
      if (view.kind !== 'read_access') continue;
      const prior = await continuationOf(prepareAttemptId,
        view.continuationStateCid);
      if (capturedValueCid(prior.captured) !== capturedValueCid(captured)) {
        fail('HeldAcquisitionChanged');
      }
      const occurrence = continuedOccurrence(captured, prior.continuation);
      const key = occurrenceKey(occurrence);
      if (approved.has(key)) fail('HeldAcquisitionChanged');
      approved.set(key, admittedRead(captured, occurrence, {checkpointCid,
        earlier, prepareAttemptId}));
    }
    return approved;
  }
  async function heldRequestId(prepareAttemptId) {
    const indexed = await indexedRequestId(prepareAttemptId);
    if (indexed !== undefined) return indexed;
    const {captured} = await continuationOf(prepareAttemptId);
    await recordHeld(prepareAttemptId, captured.requestId);
    return captured.requestId;
  }
  const diagnostic = diagnosticObserver(observe);
  const step = async (name, detail) => {
    diagnostic(name, detail);
    await faultInjection?.(name, detail);
  };

  const heldCheckpoint = checkpointCid => {
    const view = checkpointCid === null ? undefined
      : journal.inspect(checkpointCid);
    return view === undefined ? undefined : Object.freeze({
      checkpointId: view.checkpointId, checkpointCid: view.checkpointCid,
      kind: view.kind, expiresAt: view.expiresAt});
  };

  // The held projection of one prepare attempt, or undefined when the
  // attempt has created its Run (then the request journal answers) or does
  // not exist.
  function held(prepareAttemptId, requestId) {
    journal.expire();
    const preparation = journal.getPreparation(prepareAttemptId);
    if (preparation === undefined || preparation.status === 'run_created') {
      return undefined;
    }
    const checkpoint = heldCheckpoint(preparation.checkpointCid);
    const lookupExpiresAt = new Date((checkpoint === undefined ? now()
      : Date.parse(journal.inspect(checkpoint.checkpointCid).createdAt)) +
      LOOKUP_RETENTION_MS).toISOString();
    const base = {kind: 'held', requestId, prepareAttemptId,
      durability: 'durable', lookupExpiresAt};
    if (preparation.status === 'waiting_checkpoint') {
      return Object.freeze({...base, state: 'waiting_checkpoint',
        checkpoint});
    }
    if (preparation.status === 'resuming') {
      return Object.freeze({...base, state: 'resuming',
        ...(checkpoint === undefined ? {} : {checkpoint})});
    }
    return Object.freeze({...base, state: 'ended',
      endReason: preparation.endReason ?? 'ended',
      ...(preparation.terminalErrorCode === null ? {} :
        {terminalErrorCode: preparation.terminalErrorCode})});
  }

  const refusal = decision => {
    const error = new ExecutionAuthorizationError(decision);
    return coded(error.runtimeCode ?? 'ACTQL_E_DELEGATION_UNAVAILABLE',
      error);
  };

  // Resume sweep. Approved preparations are continued by whichever Host
  // claims their intent; a busy intent (a live or recently dead claimant) is
  // retried after its lease.
  let sweeping;
  let retry;
  let closed = false;
  let host;
  const originalStateSavedObservations = new WeakMap();
  const originalStateSavedByBinding = new WeakMap();
  async function originalModelStorageEvidence(handle, acquisition, ownerId, requestCid) {
    if (closed) fail('OriginalModelStateHostStopped');
    if (acquisition !== undefined) {
      selectOriginalInferMetadataAcquisition(acquisition, ownerId, requestCid);
      if (typeof evidence.originalModelStorageBindingEvidenceSelected !== 'function') {
        fail('InferOriginalMetadataAcquisitionUnavailable');
      }
    }
    const selected = await (acquisition === undefined
      ? evidence.originalModelStorageBindingEvidence(handle)
      : evidence.originalModelStorageBindingEvidenceSelected(handle, ownerId, requestCid, acquisition));
    if (closed) fail('OriginalModelStateHostStopped');
    if (acquisition !== undefined) selectOriginalInferMetadataAcquisition(acquisition, ownerId, requestCid);
    return selected;
  }
  async function originalModelBootstrapEvidence(handle, acquisition, ownerId, requestCid) {
    if (closed) fail('OriginalModelStateHostStopped');
    selectOriginalInferStoreBootstrapAcquisition(acquisition, ownerId, requestCid);
    if (typeof evidence.originalModelStorageBindingEvidenceSelected !== 'function') {
      fail('InferOriginalMetadataAcquisitionUnavailable');
    }
    const selected = await evidence.originalModelStorageBindingEvidenceSelected(
      handle, ownerId, requestCid, acquisition);
    if (closed) fail('OriginalModelStateHostStopped');
    selectOriginalInferStoreBootstrapAcquisition(acquisition, ownerId, requestCid);
    return selected;
  }
  function originalModelDocumentLimits(acquisition, ownerId, requestCid) {
    if (acquisition === undefined) {
      return {maxWireBytes: MAX_MODEL_INPUT_BYTES, maxNodes: 10000, maxDepth: 64};
    }
    const codec = selectOriginalInferResourceCodecAcquisition(acquisition, ownerId, requestCid);
    const parse = codec.decode.parse;
    // This is the original Writer/decoder ceiling, not new funding, a Store
    // grant or a replacement for the complete simultaneous read envelope.
    if (parse.max_input_bytes < 1 || parse.max_nodes < 1 || parse.max_depth < 1) {
      fail('InferOriginalStateCodecUnavailable');
    }
    return {maxWireBytes: Math.min(MAX_MODEL_INPUT_BYTES, parse.max_input_bytes),
      maxNodes: parse.max_nodes, maxDepth: parse.max_depth};
  }
  async function retainOriginalModelStateBytes({runDefinition, storageBinding, bodyWire}, acquisition) {
    const runId = contractControl.runDefinitionRunId(runDefinition);
    if (!IDENTIFIER.test(runId)) fail('InvalidOriginalModelStateCustody');
    const ownerId = `model-${runId}`;
    const runDefinitionCid = runDefinition.identity;
    const current = () => {
      if (closed) fail('OriginalModelStateHostStopped');
      if (acquisition !== undefined) {
        selectOriginalInferMetadataAcquisition(acquisition, ownerId, runDefinitionCid);
      }
    };
    current();
    const documentLimits = originalModelDocumentLimits(acquisition, ownerId, runDefinitionCid);
    if (acquisition !== undefined &&
        (typeof evidence.holdOriginalModelState !== 'function' ||
          typeof evidence.openOriginalModelState !== 'function')) {
      fail('InferOriginalMetadataAcquisitionUnavailable');
    }
    const selected = await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinitionCid);
    current();
    const document = contractControl.readModelOriginalResourceDocument(bodyWire, documentLimits);
    if (contractControl.modelOriginalResourceOriginField(document, 'run_id') !== runId ||
        contractControl.modelOriginalResourceOriginField(document, 'run_definition_cid') !== runDefinitionCid ||
        contractControl.modelOriginalResourceOriginField(document, 'storage_binding_cid') !== selected.identity) {
      fail('OriginalModelStateBindingMismatch');
    }
    const cid = acquisition === undefined
      ? (await evidence.hold(ownerId, runDefinitionCid,
        [{name: 'original_model_state', wire: document.wire}]))[0]
      : await evidence.holdOriginalModelState(ownerId, runDefinitionCid, document.wire, acquisition);
    // An unavailable original after write never rewrites that write as unsaved.
    // The same continuation keeps its park, Store and cleanup responsibilities.
    current();
    await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinitionCid);
    current();
    const held = await (acquisition === undefined ? evidence.open(ownerId)
      : evidence.openOriginalModelState(ownerId, acquisition));
    current();
    if (held.requestCid !== runDefinitionCid) fail('ModelContinuationRunMismatch');
    const saved = await held.bytes('original_model_state', cid,
      {maxBytes: Math.min(documentLimits.maxWireBytes, Buffer.byteLength(document.wire, 'utf8'))});
    current();
    if (!saved.equals(Buffer.from(document.wire, 'utf8'))) fail('OriginalModelStateBindingMismatch');
    await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinitionCid);
    current();
    return Object.freeze({ownerId, cid, runId, runDefinitionCid,
      storageBindingCid: selected.identity});
  }
  async function readOriginalModelStateBytes({runDefinition, storageBinding, receipt}, acquisition) {
    const runId = contractControl.runDefinitionRunId(runDefinition);
    const ownerId = `model-${runId}`;
    const current = () => {
      if (closed) fail('OriginalModelStateHostStopped');
      if (acquisition !== undefined) {
        selectOriginalInferMetadataAcquisition(acquisition, ownerId, runDefinition.identity);
      }
    };
    current();
    const documentLimits = originalModelDocumentLimits(acquisition, ownerId, runDefinition.identity);
    // The selected path never silently delegates to the ordinary Evidence
    // reader. Its physical metadata/FD lifetime belongs to that same Owner.
    if (acquisition !== undefined && typeof evidence.openOriginalModelState !== 'function') {
      fail('InferOriginalMetadataAcquisitionUnavailable');
    }
    const selected = await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinition.identity);
    current();
    if (receipt === null || typeof receipt !== 'object' || Array.isArray(receipt) ||
        Object.keys(receipt).sort().join(',') !== 'cid,ownerId,runDefinitionCid,runId,storageBindingCid' ||
        !IDENTIFIER.test(runId) || receipt.ownerId !== ownerId ||
        receipt.runId !== runId || receipt.runDefinitionCid !== runDefinition.identity ||
        receipt.storageBindingCid !== selected.identity ||
        !/^sha256:[0-9a-f]{64}$/u.test(receipt.cid ?? '')) fail('InvalidOriginalModelStateCustody');
    const held = await (acquisition === undefined ? evidence.open(ownerId)
      : evidence.openOriginalModelState(ownerId, acquisition));
    current();
    if (held.requestCid !== runDefinition.identity) fail('ModelContinuationRunMismatch');
    const bytes = await held.bytes('original_model_state', receipt.cid, {maxBytes: documentLimits.maxWireBytes});
    current();
    const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
    const document = contractControl.readModelOriginalResourceDocument(wire, documentLimits);
    if (contractControl.modelOriginalResourceOriginField(document, 'run_id') !== runId ||
        contractControl.modelOriginalResourceOriginField(document, 'run_definition_cid') !== runDefinition.identity ||
        contractControl.modelOriginalResourceOriginField(document, 'storage_binding_cid') !== selected.identity) {
      fail('OriginalModelStateBindingMismatch');
    }
    await originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinition.identity);
    current();
    return {document, storage: selected};
  }
  async function confirmOriginalModelStateSavedBytes(args, acquisition) {
    const {runDefinition, storageBinding, receipt, identity} = args;
    const runId = contractControl.runDefinitionRunId(runDefinition);
    if (identity === null || typeof identity !== 'object' || Array.isArray(identity) ||
        Object.keys(identity).sort().join(',') !== 'inputArtifactCid,preparedInvocationCid,providerBindingCid,runDefinitionCid,runId,scopeCid,strategyRevision,taskIndex' ||
        identity.runId !== runId || identity.runDefinitionCid !== runDefinition.identity) {
      fail('InvalidOriginalModelStateCustody');
    }
    const {document, storage} = await readOriginalModelStateBytes(args, acquisition);
    if (acquisition !== undefined) {
      selectOriginalInferMetadataAcquisition(acquisition, `model-${runId}`, runDefinition.identity);
    }
    if (closed) fail('OriginalModelStateHostStopped');
    if (contractControl.modelOriginalResourceOriginField(document, 'prepared_invocation_cid') !== identity.preparedInvocationCid) {
      fail('OriginalModelStateBindingMismatch');
    }
    const documentWire = document.wire;
    // Projection of the Common-admitted data only, not a Resource phase or
    // current journal decision. Preserve the original saved evidence issuer.
    const data = JSON.parse(documentWire);
    if (data.cut?.scope_cid !== identity.scopeCid || data.cut.input_artifact_cid !== identity.inputArtifactCid) {
      fail('OriginalModelStateBindingMismatch');
    }
    const reference = evidence.reference(receipt.ownerId, 'original_model_state', documentWire);
    if (reference.semantic_cid !== receipt.cid) fail('OriginalModelStateBindingMismatch');
    let originals = originalStateSavedByBinding.get(storageBinding);
    if (originals === undefined) {
      originals = new Map(); originalStateSavedByBinding.set(storageBinding, originals);
    }
    const prior = originals.get(reference.holding_cid);
    if (prior !== undefined) {
      if (prior.facts.documentWire !== documentWire ||
          capturedValueWire(prior.facts.identity) !== capturedValueWire(identity)) fail('OriginalModelStateBindingMismatch');
      return prior.observation;
    }
    const observation = Object.freeze({kind: 'saved-original-model-state'});
    const facts = freezeSavedData({identity: {...identity}, documentCid: receipt.cid,
      holdingCid: reference.holding_cid, storageBindingCid: storage.identity,
      resourceStateCid: data.resource_state_cid, phase: data.resource_phase, cut: data.cut, documentWire});
    const original = {observation, facts, storageBinding, runDefinition};
    originalStateSavedObservations.set(observation, original);
    originals.set(reference.holding_cid, original);
    return observation;
  }
  function originalModelStateSavedRecord(observation) {
    const original = originalStateSavedObservations.get(observation);
    if (original === undefined) fail('ForeignOriginalModelStateSavedObservation');
    if (original.facts === undefined) fail('OriginalModelStateSavedObservationRetired');
    return original;
  }
  function retireOriginalModelStateSavedObservation(observation) {
    const original = originalStateSavedObservations.get(observation);
    if (original === undefined) fail('ForeignOriginalModelStateSavedObservation');
    if (original.facts === undefined) return;
    const originals = originalStateSavedByBinding.get(original.storageBinding);
    if (originals?.get(original.facts.holdingCid) !== original) {
      fail('ForeignOriginalModelStateSavedObservation');
    }
    originals.delete(original.facts.holdingCid);
    if (originals.size === 0) originalStateSavedByBinding.delete(original.storageBinding);
    // Keep only the original nominal shell for idempotent retirement. Neither
    // an escaped token nor the Store-wide binding may retain the Run graph.
    original.facts = undefined;
    original.storageBinding = undefined;
    original.runDefinition = undefined;
  }
  // Errors that a later attempt may clear (a busy Store, a transient read);
  // anything else is permanent for this item and only observed.
  const PERMANENT = new Set(['ArtifactIntegrityFailed',
    'ContinuationEvidenceNotHeld', 'ContinuationEvidenceRetired',
    'PrivateEvidenceKeyMismatch', 'HeldRunDefinitionMissing',
    'HeldRequestChanged', 'HeldAcquisitionChanged',
    'InvalidContinuationLedger']);
  const retryable = error => !PERMANENT.has(error?.code ?? error?.message);
  // Observe Runs created from approved preparations. The intent completes
  // only after the physical start is reserved, so these Runs are started
  // (or unknown); they are never started or sent again here. A terminal Run
  // ends its journal Run. Returns true when an item should be retried.
  async function recoverRuns() {
    let busy = false;
    let after = '';
    for (;;) {
      const page = journal.listPreparationRuns({after, limit: sweepPage});
      for (const {prepareAttemptId, runId} of page) {
        if (closed) return busy;
        try {
          const {captured} = await continuationOf(prepareAttemptId);
          await step('run_observed', {prepareAttemptId, runId});
          const status = await host.observe({captured, runId});
          if (journal.isTerminalRunOutcome(status)) {
            journal.finishRun(runId, {status});
          }
        } catch (error) {
          const code = error?.code ?? error?.message;
          await step('recovery_failed', {prepareAttemptId, runId, code,
            retry: retryable(error)});
          if (retryable(error)) busy = true;
        }
      }
      if (page.length < sweepPage) return busy;
      after = page.at(-1).prepareAttemptId;
    }
  }
  async function resumeOne(prepareAttemptId) {
    const claimant = `remote-host-${process.pid}-${randomUUID()}`;
    let claimed;
    try {
      claimed = journal.claimPreparationResume(prepareAttemptId,
        {claimant, leaseMs, binding});
    } catch (error) {
      if (error?.code === 'ResumeIntentNotFound') return 'done';
      throw error;
    }
    if (claimed.action === 'busy') return 'busy';
    if (claimed.action === 'invalidated') {
      // Revalidation failed (for example the configuration changed): the
      // preparation ended without a Run. A Run already defined but not
      // started fails before dispatch, so nothing starts later.
      try {
        const {captured} = await continuationOf(prepareAttemptId);
        await host.abandon(captured);
      } catch (error) {
        await step('abandon_failed', {prepareAttemptId,
          code: error?.code ?? error?.message});
      }
      return 'done';
    }
    if (claimed.action !== 'claimed') return 'done';
    const claim = claimed.claim;
    await step('resume_claimed', {prepareAttemptId,
      generation: claim.generation});
    const end = status => {
      // A stale fence did not settle the preparation. Let the owned drain
      // retain retry responsibility and re-observe it under a fresh claim.
      // In particular, a cancelled Run must not strand its held evidence.
      journal.completeResume(claim, {status});
    };
    let continuation;
    let captured;
    let request;
    try {
      ({continuation, captured, request} = await continuationOf(
        prepareAttemptId, claimed.continuationStateCid));
    } catch (error) {
      if (retryable(error)) return 'busy';
      end('failed');
      return 'done';
    }
    const probe = await host.inspect(captured);
    // A durable request cancellation: nothing new starts. A Run already
    // defined but not started is cancelled through its own cancellation;
    // one whose start is reserved keeps the existing stop and cleanup
    // owners (the cancellation was applied to the Run by cancel-request).
    const cancelRequested = () =>
      journal.getPreparation(prepareAttemptId)?.cancelRequested === true;
    if (cancelRequested() && probe.state !== 'started' &&
        probe.state !== 'terminal') {
      if (probe.state === 'unstarted') await host.cancelRun(captured);
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
      journal.completeResume(claim, {run: {runId: probe.runId,
        status: 'running'}});
      if (probe.state === 'terminal') {
        journal.finishRun(probe.runId, {status: probe.status});
      }
      return 'done';
    }
    // Otherwise the physical start is still ahead: the common resumed
    // authorization holds now (current configuration, approval validity at
    // trusted time, live claim), whether or not the Run Definition exists.
    // The resumed Checkpoint is Run acceptance (`run_scope`) or a held
    // source read (`read_access`), each decided for its own tuple.
    const resumedKind = journal.inspect(claimed.checkpointCid)?.kind;
    const readHeld = resumedKind === 'read_access';
    const inventory = captureInventory(captured);
    const resumedOccurrence = readHeld
      ? continuedOccurrence(captured, continuation) : undefined;
    if (readHeld && (installedSources.length === 0 ||
        resumedOccurrence === undefined)) {
      await host.abandon(captured);
      end('failed');
      return 'done';
    }
    // Every earlier approval is still required, including Run acceptance and
    // the other source occurrence, at this Host's trusted time.
    const earlier = [...(continuation.earlier_approvals ?? [])];
    const earlierCurrent = () => {
      for (const checkpointCid of earlier) {
        if (journal.committedApprovalAt(checkpointCid).current !== true) {
          throw Object.assign(new Error('ApprovalExpired'),
            {code: 'ApprovalExpired'});
        }
      }
    };
    const decision = readHeld
      ? await installedSource(resumedOccurrence).resumeGate.resume('acquisition',
        resumedOccurrence.readTuple, {
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
      await host.abandon(captured);
      end('failed');
      return 'done';
    }
    const readApprovals = await earlierReadApprovals(prepareAttemptId,
      captured, earlier);
    const allApprovals = [...earlier, claimed.checkpointCid];
    if (readHeld) {
      readApprovals.set(occurrenceKey(resumedOccurrence), admittedRead(
        captured, resumedOccurrence, {checkpointCid: claimed.checkpointCid,
          earlier, prepareAttemptId}));
    }
    // Decide the complete ordered inventory before any provider I/O. A new
    // delegated occurrence replaces this resume intent with its own durable
    // Checkpoint in the existing journal. Ephemeral Host permits are decided
    // again after restart; only actual held approvals are reconstructed.
    if (installedSources.length > 0) for (const occurrence of inventory) {
      if (readApprovals.has(occurrenceKey(occurrence))) continue;
      try { journal.renewResume(claim, leaseMs); }
      catch (error) {
        if (error?.code === 'ResumeClaimStale') return 'busy';
        throw error;
      }
      const read = await decideRead({prepareAttemptId, request,
        requestCid: contentCid(request), captured, occurrence,
        earlier: allApprovals,
        port: {
          persistCheckpoint: ({body, authorities: reviewers, binding: bound,
            decisionSubjectCid, requestedClaims, configurationCid}) =>
            journal.completeResume(claim, {checkpoint: {body,
              authorities: reviewers, binding: bound, decisionSubjectCid,
              requestedClaims, configurationCid}}),
          submitResolution: item => journal.submitResolution(item),
        }});
      if (read.action === 'waiting') return 'done';
      if (read.error?.code === 'ResumeClaimStale' ||
          read.detail === 'ResumeClaimStale') return 'busy';
      if (read.action !== 'dispatch') {
        await host.abandon(captured);
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
    const outcome = await host.resume({
      captured, step,
      renew() { journal.renewResume(claim, leaseMs); },
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
        journal.renewResume(claim, leaseMs);
        earlierCurrent();
        try { admission.enter(identity); }
        catch (error) {
          if (error?.code !== 'PriorAdmissionUnresolved') throw error;
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
        journal.completeResume(claim, {run: {runId, status: 'running'}});
      },
    });
    if (outcome === 'started') return 'done';
    const refusal = outcome?.refused;
    // A start that did not happen may be a cancellation that arrived during
    // the resume: settle it now rather than retrying.
    if (outcome === 'not_started') {
      const after = await host.inspect(captured);
      if (after.state === 'cancelled') {
        end('cancelled');
        return 'done';
      }
      return 'busy';
    }
    if (refusal?.code === 'ResumeClaimStale') return 'busy';
    if (refusal?.code === 'PreparationCancelled') {
      await host.cancelRun(captured);
      end('cancelled');
      return 'done';
    }
    if (refusal !== undefined) {
      await host.abandon(captured);
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
  }

  // One drain: every resumable preparation, page by page (a busy page never
  // starves later ones), then the Run-side duties and evidence retention.
  async function drain() {
    journal.expire();
    let busy = false;
    let after = '';
    for (;;) {
      const page = journal.listResumablePreparations({after,
        limit: sweepPage});
      for (const id of page) {
        if (closed) return busy;
        let outcome;
        try { outcome = await resumeOne(id); }
        catch (error) {
          outcome = 'busy';
          await step('resume_failed', {prepareAttemptId: id,
            code: error?.code ?? error?.message});
        }
        if (outcome === 'busy') busy = true;
      }
      if (page.length < sweepPage) break;
      after = page.at(-1);
    }
    if (await recoverRuns()) busy = true;
    if (await host?.models?.sweep()) busy = true;
    if (await host?.effects?.sweep()) busy = true;
    await evidence.settle();
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
            await step('sweep_failed', {code: error?.code ?? error?.message});
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

  const summaryOf = async view => {
    let subject;
    if (view.prepareAttemptId !== null) {
      const requestId = await heldRequestId(view.prepareAttemptId);
      if (requestId === undefined) fail('HeldRequestIndexMissing');
      subject = {kind: 'prepare_attempt',
        prepareAttemptId: view.prepareAttemptId, requestId};
    } else {
      subject = {kind: 'run_unit', runId: view.runId,
        runDefinitionCid: view.runDefinitionCid};
    }
    return Object.freeze({checkpointId: view.checkpointId,
      checkpointCid: view.checkpointCid, kind: view.kind, phase: view.phase,
      subject, requiredArtifact: {type: view.requiredArtifact.type,
        cid: view.requiredArtifact.cid},
      reviewProjectionCid: view.reviewProjectionCid,
      requirements: [...view.requirements], createdAt: view.createdAt,
      expiresAt: view.expiresAt, humanSummary: view.humanSummary,
      ...modelCheckpointMetadata(journal, view)});
  };

  async function modelStoredContinuation(view) {
    if (view?.kind !== 'model_invocation' || view.prepareAttemptId !== null) {
      fail('InvalidInstalledModelContinuation');
    }
    const held = await evidence.open(`model-${view.runId}`);
    if (held.requestCid !== view.runDefinitionCid) fail('ModelContinuationRunMismatch');
    const record = await held.record('continuation_record', view.continuationStateCid);
    if (record?.version !== MODEL_CHECKPOINT_STORAGE ||
        record.run_definition_cid !== view.runDefinitionCid ||
        record.model_invocation_scope_cid !== view.requiredArtifact.cid ||
        record.review_projection_cid !== view.reviewProjectionCid ||
        !/^sha256:[0-9a-f]{64}$/u.test(record.review_storage_cid ?? '') ||
        typeof record.continuation_wire !== 'string') {
      fail('InvalidInstalledModelContinuation');
    }
    return {held, record};
  }

  return Object.freeze({
    configured,
    journal,
    binding,
    modelContext: Object.freeze({accountId: gate.accountId,
      configurationCid: gate.configurationCid, principal: gate.principal,
      contextCid: gate.contextCid}),

    // Installation-only custody from this exact private Evidence port, not a
    // caller's CID or matching configuration. Reopening requires fresh nominal
    // custody even when the selected Store's canonical identity is unchanged.
    async observeModelOriginalStorageBinding() {
      if (closed) fail('OriginalModelStateHostStopped');
      const handle = await evidence.observeOriginalModelStorageBinding();
      if (closed) fail('OriginalModelStateHostStopped');
      return handle;
    },
    async observeModelOriginalStorageBindingSelected(args, acquisition) {
      // Require the operation's original bootstrap role BEFORE reading DATA;
      // omission never falls back to the ordinary unselected Store path.
      selectOriginalInferStoreBootstrapAcquisition(acquisition);
      const {runDefinition} = args;
      const ownerId = `model-${contractControl.runDefinitionRunId(runDefinition)}`;
      const requestCid = runDefinition.identity;
      if (closed) fail('OriginalModelStateHostStopped');
      selectOriginalInferStoreBootstrapAcquisition(acquisition, ownerId, requestCid);
      if (typeof evidence.observeOriginalModelStorageBindingSelected !== 'function') {
        fail('InferOriginalMetadataAcquisitionUnavailable');
      }
      const handle = await evidence.observeOriginalModelStorageBindingSelected(ownerId, requestCid, acquisition);
      if (closed) fail('OriginalModelStateHostStopped');
      selectOriginalInferStoreBootstrapAcquisition(acquisition, ownerId, requestCid);
      return handle;
    },
    async modelOriginalStorageBindingBootstrapSelected(args, acquisition) {
      selectOriginalInferStoreBootstrapAcquisition(acquisition);
      const {storageBinding, runDefinition} = args;
      const ownerId = `model-${contractControl.runDefinitionRunId(runDefinition)}`;
      return originalModelBootstrapEvidence(storageBinding, acquisition, ownerId, runDefinition.identity);
    },
    modelOriginalStorageBindingEvidence(handle) {
      return originalModelStorageEvidence(handle);
    },
    async modelOriginalStorageBindingEvidenceSelected(args, acquisition) {
      selectOriginalInferMetadataAcquisition(acquisition);
      const {storageBinding, runDefinition} = args;
      const ownerId = `model-${contractControl.runDefinitionRunId(runDefinition)}`;
      return originalModelStorageEvidence(storageBinding, acquisition, ownerId, runDefinition.identity);
    },
    // A data-only Common document is saved under its dedicated private role.
    // This does not authenticate the other Origin fields, restore a current
    // resource cut, acknowledge a Model Entry or grant startup/send authority.
    retainOriginalModelState: args => retainOriginalModelStateBytes(args, undefined),
    async retainOriginalModelStateSelected(args, acquisition) {
      // Check nominal membership before even inspecting caller DATA. Missing
      // selected physical support must never fall back to the ordinary path.
      selectOriginalInferMetadataAcquisition(acquisition);
      return retainOriginalModelStateBytes(args, acquisition);
    },
    readOriginalModelState: async args => (await readOriginalModelStateBytes(args, undefined)).document,
    async readOriginalModelStateSelected(args, acquisition) {
      // Required nominal original; an omitted/forged handle cannot opt out to
      // a legacy read. This is current-cut only, not a prime/general restriction.
      selectOriginalInferMetadataAcquisition(acquisition);
      return (await readOriginalModelStateBytes(args, acquisition)).document;
    },
    // A same-installation saved-byte observation, not a restore/read/send
    // grant. The existing Store is actually reopened and verified first;
    // an imported receipt or matching configuration alone cannot issue it.
    confirmOriginalModelStateSaved: args => confirmOriginalModelStateSavedBytes(args, undefined),
    async confirmOriginalModelStateSavedSelected(args, acquisition) {
      selectOriginalInferMetadataAcquisition(acquisition);
      return confirmOriginalModelStateSavedBytes(args, acquisition);
    },
    // The original private caller must first finish all users and unresolved
    // cut/cleanup duties, then retire this view BEFORE returning its READ
    // reservation. This drops references only: no Store deletion, physical ACK,
    // Journal mutation, Resource settlement or send grant. Stop does not block
    // this cleanup-only path, and durable bytes still require a fresh read.
    retireOriginalModelStateSavedObservation,
    originalModelStateSavedFacts(observation) {
      if (closed) fail('OriginalModelStateHostStopped');
      return originalModelStateSavedRecord(observation).facts;
    },
    originalModelStateSavedObservationCurrent(observation) {
      if (closed) fail('OriginalModelStateHostStopped');
      originalModelStateSavedRecord(observation);
      // Currentness is nominal installation lifetime only. The saved fact is
      // historical; callers reconfirm bytes asynchronously before using it,
      // and separately validate current Resource/authorization/retention.
      return observation;
    },

    // Exact private pre-INFER completion bytes, held before either immediate
    // inventory registration or a deferred Checkpoint. This receipt names
    // custody; callers must reopen it and validate the original owner binding.
    async retainModelInput({runId, runDefinitionCid, bodyWire}) {
      if (!IDENTIFIER.test(runId ?? '') ||
          !/^sha256:[0-9a-f]{64}$/u.test(runDefinitionCid ?? '') ||
          typeof bodyWire !== 'string' || bodyWire.length === 0 ||
          Buffer.byteLength(bodyWire) > MAX_MODEL_INPUT_BYTES) {
        fail('InvalidModelInputCustody');
      }
      const ownerId = `model-${runId}`;
      const [cid] = await evidence.hold(ownerId, runDefinitionCid,
        [{name: 'captured_input', wire: bodyWire}]);
      return Object.freeze({ownerId, cid, runId, runDefinitionCid});
    },
    async readModelInput(receipt) {
      if (receipt === null || typeof receipt !== 'object' || Array.isArray(receipt) ||
          Object.keys(receipt).sort().join(',') !== 'cid,ownerId,runDefinitionCid,runId' ||
          !IDENTIFIER.test(receipt.runId ?? '') || receipt.ownerId !== `model-${receipt.runId}` ||
          !/^sha256:[0-9a-f]{64}$/u.test(receipt.cid ?? '') ||
          !/^sha256:[0-9a-f]{64}$/u.test(receipt.runDefinitionCid ?? '')) {
        fail('InvalidModelInputCustody');
      }
      const held = await evidence.open(receipt.ownerId);
      if (held.requestCid !== receipt.runDefinitionCid) fail('ModelContinuationRunMismatch');
      return held.bytes('captured_input', receipt.cid, {maxBytes: MAX_MODEL_INPUT_BYTES});
    },

    // A fixed Model inventory has its own activation decision. Neither a
    // Source answer nor the later Effect Set answer is a Model send permit.
    async modelAuthorization({runId, runDefinitionCid, unitId, scopeCid, tuple,
      declaredResults, modelCallSet, reviewWire, continuationWire, beforeDefer,
      journalPort = journal, attachImmediate = false}) {
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
           journalPort.attachModelCallSetCheckpoint === journal.attachModelCallSetCheckpoint)) {
        fail('ModelImmediateCheckpointChainingUnsupported');
      }
      const port = !attachImmediate ? journalPort : {...journalPort,
        persistCheckpoint: checkpoint => journalPort.attachModelCallSetCheckpoint(checkpoint)};
      const model = await createLocalAuthorizationGate({accountConfig,
        accountConfiguration, principal: ownerPrincipal, ...decisionOptions,
        decide, requiredClaims: ['invocation_scope_approved'],
        answeringAuthorities: answeringAuthorities ?? authorities.map(item => item.reviewerId),
        deferral: {journal: port, authorities, binding,
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
            const storedReview = evidence.reference(`model-${runId}`,
              'review_projection', reviewWire).semantic_cid;
            const storedContinuation = canonicalValueJson({version: MODEL_CHECKPOINT_STORAGE,
              run_definition_cid: runDefinitionCid,
              model_invocation_scope_cid: scopeCid,
              review_projection_cid: review.identity, review_storage_cid: storedReview,
              continuation_wire: continuationWire});
            const refs = await evidence.hold(`model-${runId}`, runDefinitionCid, [
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
        authorize: options => model.authorize('activation', tuple,
          {...options, subjectCid: scopeCid}),
        resume: options => model.resume('activation', tuple,
          {...options, subjectCid: scopeCid}),
        close: () => model.close(),
        cleanup: () => model.cleanup(),
        cleanupPending: () => model.cleanupPending(),
      });
    },
    async modelContinuation(view) {
      const {record} = await modelStoredContinuation(view);
      return JSON.parse(record.continuation_wire);
    },

    // Every target tuple has its own read-scope artifact and answer. These
    // pre-computation approvals never reuse a Source or Effect-commit grant.
    async effectTargetAuthorization({runId, runDefinitionCid, unitId,
      inventoryCid, target, declaredResults, continuation, beforeDefer,
      effectTargetAuthority, journalPort = journal}) {
      const installed = effectTargets === undefined
        ? effectTargetAuthority === undefined && effectTargetGate !== undefined
          ? {configuration: effectTarget, gate: effectTargetGate} : undefined
        : effectTargetAuthorities.get(effectTargetAuthority);
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
      const read = await createLocalAuthorizationGate({
        accountConfiguration: installed.configuration.accountConfiguration,
        context: installed.configuration.context, ...decisionOptions, decide,
        answeringAuthorities: answeringAuthorities ?? authorities.map(item => item.reviewerId),
        deferral: {journal: journalPort, authorities, binding,
          async describe(view) {
            if (view.boundary !== 'acquisition' || view.subject.subject_cid !== scopeCid) {
              fail('InvalidEffectTargetCheckpointBoundary');
            }
            await beforeDefer();
            const wire = await continuation();
            if (typeof wire !== 'string') fail('InvalidEffectTargetContinuation');
            const reviewWire = canonicalValueJson({scope,
              configuration_cid: installed.gate.configurationCid,
              context_cid: installed.gate.contextCid}, {dataKeys: true});
            if (Buffer.byteLength(reviewWire) > maxReviewBytes) fail('CheckpointReviewTooLarge');
            const refs = await evidence.hold(`effect-${runId}`, runDefinitionCid, [
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
      if (read.configurationCid !== installed.gate.configurationCid ||
          read.contextCid !== installed.gate.contextCid) {
        read.close();
        fail('EffectTargetCheckpointConfigurationChanged');
      }
      return Object.freeze({scopeCid, configurationCid: read.configurationCid,
        contextCid: read.contextCid,
        assertCurrent: () => read.assertConfigurationCurrent(),
        authorize: options => read.authorize('acquisition', target.readTuple,
          {...options, subjectCid: scopeCid}),
        resume: options => read.resume('acquisition', target.readTuple,
          {...options, subjectCid: scopeCid}),
        current: options => installed.gate.authorize('acquisition', target.readTuple,
          {...options, subjectCid: scopeCid}),
        close: () => read.close(),
        cleanup: () => read.cleanup(),
        cleanupPending: () => read.cleanupPending(),
      });
    },
    async effectTargetContinuation(view) {
      if (view?.kind !== 'read_access' || view.prepareAttemptId !== null) {
        fail('InvalidEffectTargetContinuation');
      }
      const held = await evidence.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      const saved = await held.record('continuation_record', view.continuationStateCid);
      if (saved?.version !== EFFECT_TARGET_CONTINUATION ||
          saved.run_definition_cid !== view.runDefinitionCid ||
          saved.unit_id !== view.subject?.unit_id) fail('InvalidEffectTargetContinuation');
      return saved;
    },
    async runUnitReadContinuation(view) {
      if (view?.kind !== 'read_access' || view.prepareAttemptId !== null) {
        fail('InvalidRunUnitReadContinuation');
      }
      const held = await evidence.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      return held.record('continuation_record', view.continuationStateCid);
    },
    async inspectEffectTargetApprovals(runId, runDefinitionCid) {
      if (!IDENTIFIER.test(runId ?? '') || typeof runDefinitionCid !== 'string') {
        fail('InvalidEffectTargetContinuation');
      }
      const records = [];
      let after = '';
      for (;;) {
        const page = journal.listRunCheckpoints({after, limit: PAGE});
        for (const view of page) {
          if (view.runId !== runId || view.kind !== 'read_access' ||
              !view.checkpointId.startsWith(`${runId}-target-`)) continue;
          if (view.runDefinitionCid !== runDefinitionCid || view.prepareAttemptId !== null) {
            fail('EffectContinuationRunMismatch');
          }
          const held = await evidence.open(`effect-${runId}`);
          if (held.requestCid !== runDefinitionCid) fail('EffectContinuationRunMismatch');
          const continuation = await held.record('continuation_record', view.continuationStateCid);
          if (continuation?.version !== EFFECT_TARGET_CONTINUATION ||
              continuation.run_definition_cid !== runDefinitionCid) {
            fail('InvalidEffectTargetContinuation');
          }
          records.push(Object.freeze({view, continuation}));
        }
        if (page.length < PAGE) break;
        after = page.at(-1).checkpointCid;
      }
      return Object.freeze(records);
    },

    // Host-installed Effect execution uses this same journal and reviewer
    // authority. The read boundary has no deferral port in this profile:
    // a deferred target read is unsupported before any provider I/O.
    async effectAuthorization({runId, runDefinitionCid, runDefinition, unitId,
      declaredResults, reviewWire, continuationWire, beforeDefer, targetReads,
      requestedStop, assertRequestedStopCurrent, projectReview,
      journalPort = journal}) {
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
      const checkpointEnd = (created, stopLifetime) => {
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
      const originalReview = (subjectCid, claims) => {
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
      const common = {accountConfig, accountConfiguration,
        principal: ownerPrincipal, ...decisionOptions, decide,
        answeringAuthorities: answeringAuthorities === undefined
          ? authorities.map(item => item.reviewerId)
          : [...answeringAuthorities]};
      const read = await createLocalAuthorizationGate(common);
      let commit;
      try {
        commit = await createLocalAuthorizationGate({...common,
          requiredClaims: effectClaims,
          deferral: {journal: journalPort, authorities, binding,
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
              const refs = await evidence.hold(id, runDefinitionCid, [
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
            commit.configurationCid !== gate.configurationCid) {
          fail('EffectCheckpointConfigurationChanged');
        }
        const stopLimits = Object.freeze({...INSTALLED_EFFECT_CHECKPOINT_LIMITS,
          maxWireBytes: maxReviewBytes});
        const stopCurrent = () => {
          if (requestedStop === undefined) fail('RequestedEffectStopUnavailable');
          assertRequestedStopCurrent();
          read.assertConfigurationCurrent();
          commit.assertConfigurationCurrent();
        };
        // Project the existing journal's admitted body, not caller-supplied
        // approval DATA. Common rechecks its original Run/Preview/intent and
        // canonical checkpoint CID before an ownership admission is returned.
        const checkedStopView = (resumption, subjectCid) => {
          const held = resumption?.claim;
          const claim = held?.claim ?? held;
          const admitted = journalPort.admitResume(claim,
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
        const requestStop = async (decision, options) => {
          stopCurrent();
          options.signal?.throwIfAborted();
          await beforeDefer();
          stopCurrent();
          const review = originalReview(decision.subjectCid, ['effect_scope_approved']);
          const refs = await evidence.hold(`effect-${runId}`, runDefinitionCid, [
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
            requestedClaims: [], configurationCid: commit.configurationCid});
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
          async authorize(boundary, scope, options = {}) {
            if (boundary === 'acquisition' && targetReads !== undefined) {
              return targetReads.authorize(scope, options);
            }
            const decision = await (boundary === 'effect_commit' ? commit : read)
              .authorize(boundary, scope, options);
            // A genuine delegated Checkpoint already stops this exact Preview.
            // Neither an Account Allow nor an immediate Host permit discharges
            // the independent user-requested restriction.
            return boundary === 'effect_commit' && requestedStop !== undefined &&
              decision.action === 'dispatch' ? requestStop(decision, options) : decision;
          },
          async resume(boundary, scope, options = {}) {
            const view = checkedStopView(options.resumption, options.subjectCid);
            if (view === undefined) return commit.resume(boundary, scope, options);
            if (boundary !== 'effect_commit') fail('RequestedEffectStopBindingChanged');
            // This approval releases only the continuation restriction. Current
            // Delegate still needs a genuine current Host answer; these review
            // claims must never be supplied to executionAuthorizationAnswer.
            const decision = await commit.authorize(boundary, scope,
              {...options, allowDeferral: false});
            checkedStopView(options.resumption, options.subjectCid);
            return decision;
          },
          continuationAdmission(resumption, subjectCid) {
            if (checkedStopView(resumption, subjectCid) === undefined) return undefined;
            const owned = admitResumedDispatch(journalPort, resumption,
              {configurationCid: commit.configurationCid, approvalClaims: false});
            if (owned.detail !== undefined) fail(owned.detail, owned.error);
            stopCurrent();
            return owned.admission;
          },
          assertCurrent() {
            read.assertConfigurationCurrent();
            commit.assertConfigurationCurrent();
          },
          close, cleanup: close, cleanupPending,
        });
      } catch (error) {
        read.close();
        commit?.close();
        throw error;
      }
    },
    // A Source read inside an admitted Effect Run uses the same durable
    // Run-unit owner as Effect commit, but its own Source account and exact
    // acquisition occurrence. An Effect answer is never a read permit.
    async computationSourceAuthorization({runId, runDefinitionCid, unitId,
      occurrence, declaredResults, continuation, beforeDefer, journalPort = journal}) {
      // The checked Program/Plan owns Source cardinality. This original port's
      // ordinal is not a second Host limit on the number of acquired Sources.
      if (!IDENTIFIER.test(runId ?? '') || !IDENTIFIER.test(unitId ?? '') ||
          typeof runDefinitionCid !== 'string' ||
          typeof continuation !== 'function' || typeof beforeDefer !== 'function' ||
          !Array.isArray(declaredResults) ||
          ![occurrence?.stage, occurrence?.input, occurrence?.task]
            .every(value => Number.isSafeInteger(value) && value >= 0)) {
        fail('InvalidComputationSourceContinuation');
      }
      occurrence = JSON.parse(JSON.stringify(occurrence));
      const freeze = value => {
        if (value !== null && typeof value === 'object') {
          for (const item of Object.values(value)) freeze(item);
          Object.freeze(value);
        }
        return value;
      };
      freeze(occurrence);
      declaredResults = Object.freeze([...declaredResults]);
      const {configuration, gate: current} = installedSource(occurrence);
      const scope = Object.freeze({version: 'actql-effect-source-read-scope/0.1',
        run_definition_cid: runDefinitionCid, unit_id: unitId,
        authority_scope_cid: authorityScopeCid,
        principal_id: ownerPrincipal, occurrence});
      const scopeCid = contentCid(scope);
      const read = await createLocalAuthorizationGate({
        accountConfiguration: configuration.accountConfiguration,
        context: configuration.context, ...decisionOptions, decide,
        answeringAuthorities: answeringAuthorities ?? authorities.map(item => item.reviewerId),
        deferral: {journal: journalPort, authorities, binding,
          async describe(view) {
            if (view.boundary !== 'acquisition' ||
                view.subject.subject_cid !== scopeCid) {
              fail('InvalidComputationSourceCheckpointBoundary');
            }
            // The acquisition owner confirms durable custody before the
            // continuation may refer to any earlier completed Source.
            await beforeDefer();
            const wire = await continuation();
            if (typeof wire !== 'string') fail('InvalidComputationSourceContinuation');
            const reviewWire = JSON.stringify({scope,
              configuration_cid: current.configurationCid,
              context_cid: current.contextCid});
            if (Buffer.byteLength(reviewWire) > maxReviewBytes) fail('CheckpointReviewTooLarge');
            const refs = await evidence.hold(`effect-${runId}`, runDefinitionCid, [
              {name: 'review_projection', wire: reviewWire},
              {name: 'continuation_record', wire},
            ]);
            const created = now();
            return {priorStatus: 'running', declaredResults, body: {
              checkpoint_id: computationSourceCheckpointId(runId, scopeCid),
              run_id: runId, run_definition_cid: runDefinitionCid,
              continuation_state_cid: refs[1],
              subject: {kind: 'run_unit', run_id: runId, unit_id: unitId,
                continuation: 'resume_unit'},
              kind: 'read_access',
              required_artifact: {artifact_type: 'read_scope', artifact_cid: scopeCid},
              review_projection_cid: refs[0],
              human_summary: `Read ${occurrence.checkedSource.sourceRef} for Run ${runId}`,
              created_at: new Date(created).toISOString(),
              expires_at: new Date(created + checkpointTtlMs).toISOString(),
            }};
          },
        }});
      if (read.configurationCid !== current.configurationCid ||
          read.contextCid !== current.contextCid) {
        read.close();
        fail('SourceCheckpointConfigurationChanged');
      }
      return Object.freeze({scopeCid,
        assertCurrent: () => read.assertConfigurationCurrent(),
        authorize: options => read.authorize('acquisition', occurrence.readTuple,
          {...options, subjectCid: scopeCid}),
        resume: options => read.resume('acquisition', occurrence.readTuple,
          {...options, subjectCid: scopeCid}),
        close: () => read.close(),
      });
    },
    async retainComputationSource(runId, runDefinitionCid, wire) {
      if (!IDENTIFIER.test(runId ?? '') || typeof runDefinitionCid !== 'string') {
        fail('InvalidComputationSourceContinuation');
      }
      const [semanticCid] = await evidence.hold(`effect-${runId}`, runDefinitionCid,
        [{name: 'source_capture', wire}]);
      return semanticCid;
    },
    // Called only by the acquisition custody owner after confirmed physical
    // close. A durable waiting/resuming Run still owns its evidence; a failed
    // pre-Checkpoint persistence has no Run row and can now retire safely.
    async retireComputationSources(runId) {
      if (!IDENTIFIER.test(runId ?? '')) fail('InvalidComputationSourceContinuation');
      await evidence.abandon(`effect-${runId}`);
      return evidence.settle();
    },
    async readComputationSource(view, semanticCid, maxBytes) {
      if (view?.prepareAttemptId !== null ||
          !['read_access', 'model_invocation'].includes(view.kind)) {
        fail('InvalidComputationSourceContinuation');
      }
      const held = await evidence.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      return held.bytes('source_capture', semanticCid, {maxBytes});
    },
    async computationSourceReferences(view) {
      if (view?.prepareAttemptId !== null ||
          !['read_access', 'model_invocation'].includes(view.kind)) {
        fail('InvalidComputationSourceContinuation');
      }
      const held = await evidence.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      return held.held('source_capture');
    },
    async computationContinuation(view) {
      if (view?.kind !== 'read_access' || view.prepareAttemptId !== null) {
        fail('InvalidComputationSourceContinuation');
      }
      const held = await evidence.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
      return held.record('continuation_record', view.continuationStateCid);
    },
    async effectContinuation(view) {
      if (view?.kind !== 'effect_set' || view.prepareAttemptId !== null) {
        fail('InvalidEffectContinuation');
      }
      const held = await evidence.open(`effect-${view.runId}`);
      if (held.requestCid !== view.runDefinitionCid) {
        fail('EffectContinuationRunMismatch');
      }
      return held.record('continuation_record', view.continuationStateCid);
    },
    effectRunState(runId, runDefinitionCid) {
      if (!IDENTIFIER.test(runId ?? '') ||
          typeof runDefinitionCid !== 'string') {
        fail('InvalidEffectContinuation');
      }
      let view = journal.activeRunCheckpoint(runId);
      if (view === undefined) {
        let after = '';
        for (;;) {
          const page = journal.listRunCheckpoints({after, limit: PAGE});
          view = page.find(item => item.runId === runId);
          if (view !== undefined || page.length < PAGE) break;
          after = page.at(-1).checkpointCid;
        }
      }
      if (view === undefined) return undefined;
      if (!['effect_set', 'read_access', 'model_invocation'].includes(view.kind) || view.runId !== runId ||
          view.runDefinitionCid !== runDefinitionCid ||
          view.prepareAttemptId !== null) {
        fail('EffectContinuationRunMismatch');
      }
      return journal.getRunState(runId);
    },
    // Route only through the journal's exact current continuation. The
    // transition owner fences physical entry; this lookup grants no authority.
    cancelEffectContinuation(runId, runDefinitionCid) {
      const view = journal.activeRunCheckpoint(runId);
      if (!['effect_set', 'read_access', 'model_invocation'].includes(view?.kind) ||
          view.runId !== runId || view.runDefinitionCid !== runDefinitionCid ||
          view.prepareAttemptId !== null) return false;
      const state = journal.getRunState(runId);
      if (state?.status === 'waiting_checkpoint') {
        return journal.cancelCheckpoint(view.checkpointCid).outcome === 'cancelled';
      }
      if (state?.status === 'resuming') {
        return journal.cancelUnsentResume(view.checkpointCid).outcome === 'cancelled';
      }
      return false;
    },
    hasUnresolvedSourceStart(runId, runDefinitionCid) {
      const view = journal.activeRunCheckpoint(runId);
      return view?.kind === 'read_access' && view.runId === runId &&
        view.runDefinitionCid === runDefinitionCid &&
        view.requiredArtifact.type === 'read_scope' &&
        (view.checkpointId === computationSourceCheckpointId(runId,
          view.requiredArtifact.cid) ||
          // Already sealed legacy Checkpoints retain their original identity.
          view.checkpointId.startsWith(`${runId}-source-`)) &&
        journal.hasStartedResume(view.checkpointCid);
    },
    hasUnresolvedEffectTargetStart(runId, runDefinitionCid) {
      const view = journal.activeRunCheckpoint(runId);
      return view?.kind === 'read_access' && view.runDefinitionCid === runDefinitionCid &&
        view.checkpointId.startsWith(`${runId}-target-`) &&
        journal.hasStartedResume(view.checkpointCid);
    },
    hasUnresolvedModelStart(runId, runDefinitionCid) {
      const view = journal.activeRunCheckpoint(runId);
      return view?.kind === 'model_invocation' && view.runId === runId &&
        view.runDefinitionCid === runDefinitionCid &&
        journal.hasUnresolvedModelCalls(runId);
    },
    // Principals admitted to the Checkpoint operations at all. Each
    // operation still applies its own authorization.
    admitsCheckpointPrincipal: principal => principal === ownerPrincipal ||
      readers.has(principal) || answerers.has(principal),

    // Decide Run acceptance for one Host-resolved request before any Run
    // definition exists. `dispatch`: continue; `held`: the durable held
    // reply; refusals throw with their ACTQL runtime code and record nothing.
    async acceptRun({requested, captured, signal}) {
      captureInventory(captured);
      const prepareAttemptId = prepareAttemptIdOf(captured.requestId);
      const subject = requestSubject(requested);
      const request = {version: 'actql-remote-invocation-request/0.1',
        subject, subject_cid: contentCid(subject)};
      const requestCid = contentCid(request);
      const existing = journal.getPreparation(prepareAttemptId);
      if (existing !== undefined) {
        // The held request's durable fingerprint is its evidence ledger's
        // request CID. Unavailable evidence is never a reason to skip the
        // comparison.
        let ledger;
        try { ledger = await evidence.open(prepareAttemptId); }
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
          const original = await ledger.record('captured_input', captures[0]);
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
      const deferring = await createLocalAuthorizationGate({accountConfig,
        accountConfiguration, principal: ownerPrincipal, ...decisionOptions,
        decide,
        answeringAuthorities: decide === undefined ? undefined : answering,
        // Run-scoped Model and Effect approvals remain owned by their existing
        // continuation paths. Unsupported pre-Run waits must not be admitted.
        deferral: captured.submission === undefined
          ? deferralFor({prepareAttemptId, request, requestCid,
            captured, answering}) : undefined});
      let sealed;
      let decision;
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
      if (sealed !== undefined) await evidence.abandon(prepareAttemptId);
      throw refusal(decision);
    },

    // Decide the source read of a new request whose Run acceptance was just
    // allowed or permitted, before any Run Definition or provider I/O. A
    // delegated read is held as a `read_access` `prepare_attempt`
    // Checkpoint (the held reply); refusals throw and record nothing.
    async acceptAcquisition({requested, captured, signal}) {
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
      const permits = new Map();
      admittedReads.delete(captured.requestId);
      for (const occurrence of inventory) {
        const decision = await decideRead({prepareAttemptId, request,
          requestCid, captured, occurrence, port: journal, signal});
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
        await evidence.abandon(prepareAttemptId);
        throw refusal(decision);
      }
      if (permits.size > 0) admittedReads.set(captured.requestId, permits);
      return {kind: 'dispatch'};
    },

    // The source access a request's acquisition uses. For a request whose
    // read was held and approved, the adapter's current-authority check just
    // before provider I/O (and before Source Evidence) accepts that exact
    // admitted approval while it is still current and the request is not
    // cancelled; deny and allow are the source account's own. Every other
    // request uses the installed access unchanged.
    acquisitionAccess(requestId, base, occurrence) {
      const key = occurrence === undefined ? 'singular' : occurrenceKey(occurrence);
      const admitted = admittedReads.get(requestId)?.get(key);
      if (admitted === undefined || occurrence !== undefined &&
          capturedValueCid(occurrence) !== capturedValueCid(admitted.acquisition)) return base;
      const same = scope => ['connection', 'resource', 'operation'].every(
        key => scope?.[key] === admitted.readTuple[key]);
      let originalApproval;
      const approvalCurrent = () => {
        if (admittedReads.get(requestId)?.get(key) !== admitted) return false;
        const preparation = admitted.prepareAttemptId === undefined
          ? undefined : journal.getPreparation(admitted.prepareAttemptId);
        const approvedNow = cid => {
          try {return journal.committedApprovalAt(cid).current === true;}
          catch {return false;}
        };
        return preparation?.cancelRequested !== true &&
          [admitted.checkpointCid,...admitted.earlier].filter(cid=>cid!==undefined).every(approvedNow);
      };
      const assertApprovedReadCurrent = () => {
        if (!approvalCurrent()) fail('ApprovalExpired');
      };
      const authorization = Object.freeze({
        ...base.authorization,
        async authorize(boundary, scope, options) {
          if (boundary === 'acquisition') originalApproval = undefined;
          const current = await base.authorization.authorize(boundary, scope,
            options);
          if (current.action === 'dispatch' || current.action === 'deny' ||
              boundary !== 'acquisition' || !same(scope)) return current;
          // The returned approval carries the exact approved read, which a
          // source adapter verifies against its own installation.
          if (!approvalCurrent()) return current;
          originalApproval = recordCheckpointApproval(Object.freeze({boundary,
            action: 'dispatch', basis: 'resumed_approval',
            tuple: Object.freeze({...scope}),
            checkpointCid: admitted.checkpointCid}), {
            checkpointCid: admitted.checkpointCid,
            earlierCheckpointCids: Object.freeze(admitted.earlier.filter(cid=>cid!==undefined)),
            // The original resume entered before this admitted read was
            // published. Both Site fences retain that same live occurrence;
            // they issue no new grant or physical request.
            assertCurrent: assertApprovedReadCurrent,
            enter: assertApprovedReadCurrent,
            readTuple: admitted.readTuple,
            physicalBinding: admitted.acquisition?.physicalBinding,
            checkedSource: admitted.acquisition?.checkedSource,
            ...(admitted.acquisition?.installationBinding === undefined ? {} :
              {installationBinding: admitted.acquisition.installationBinding}),
            ...(admitted.acquisition?.stage === undefined ? {} :
              {occurrence: occurrenceIdentity(admitted.acquisition)}),
            principalId: admitted.principalId});
          return originalApproval;
        },
      });
      // The same read's nominal decision is metadata custody, never another
      // authorization. Its consumer must validate the original facts/current.
      return Object.freeze({...base, authorization,
        originalCheckpointApproval() {
          if (originalApproval === undefined || admitted.checkpointCid === undefined) return undefined;
          if (!approvalCurrent()) fail('ApprovalExpired');
          return originalApproval;
        }});
    },

    // The dispatch of a held read ended; its admitted approval is no longer
    // used for provider I/O in this process.
    releaseAcquisition(requestId) { admittedReads.delete(requestId); },

    // Durable request cancellation of a held request (before or after its
    // Run exists); the caller applies it to an existing Run.
    cancelHeld(requestId) {
      const cancelled = journal.requestPreparationCancellation(
        prepareAttemptIdOf(requestId));
      return Object.freeze({outcome: cancelled.outcome});
    },

    // Whether this Host held the request (a prepare attempt exists): its Run
    // may start only through the resumed authorization.
    heldOrigin(requestId) {
      return journal.getPreparation(prepareAttemptIdOf(requestId)) !==
        undefined;
    },

    heldLookup(requestId) {
      return held(prepareAttemptIdOf(requestId), requestId);
    },

    prepareAttemptIdOf,

    async listCheckpoints(input) {
      const {principalId, after, limit, checkpointId} = input;
      if (!(principalId === ownerPrincipal || readers.has(principalId) ||
          answerers.has(principalId))) {
        fail('CheckpointListDenied');
      }
      const lookup = Object.hasOwn(input, 'checkpointId');
      // This empty shape probes only the public Owner's identifier class. It
      // is not a Journal observation or a fabricated lookup return value.
      if (lookup && (after !== '' || limit !== 1 ||
          !validCheckpointLookup({items: []}, checkpointId))) {
        fail('InvalidCheckpointLookup');
      }
      journal.expire();
      if (lookup) {
        // Inspect uses this same Journal's exact ID/CID index and refuses
        // ambiguous IDs. A CID fallback is not an ID match or a new grant.
        const view = journal.inspect(checkpointId);
        if (view === undefined || view.checkpointId !== checkpointId || view.closure !== 'open') {
          return Object.freeze({items: []});
        }
        const summary = await summaryOf(view);
        const current = journal.inspect(view.checkpointCid);
        if (current?.checkpointId !== checkpointId || current.closure !== 'open') {
          return Object.freeze({items: []});
        }
        return Object.freeze({items: [summary]});
      }
      const bounded = Math.min(limit, MAX_PAGE);
      const rows = journal.listPending({after: after === '' ? undefined
        : after, limit: bounded + 1});
      const page = rows.slice(0, bounded);
      return Object.freeze({items: await Promise.all(page.map(summaryOf)),
        ...(rows.length > bounded ? {next: page.at(-1).cursor} : {})});
    },

    // The ordinary Local default signs only an explicitly selected original
    // Checkpoint, never arbitrary caller DATA. These current decisions are
    // distinct from the Effect Delegate/approval and the actual key/use claim.
    async localSigningContext({principalId, summary, signingResource, signal}) {
      if (principalId !== ownerPrincipal || !answerers.has(principalId) ||
          !readers.has(principalId) || typeof signingResource !== 'string') {
        fail('CheckpointAnswerDenied');
      }
      const original = journal.originalCheckpointForSigning(summary?.checkpointCid);
      if (original.view.kind !== 'effect_set' || original.view.prepareAttemptId !== null ||
          original.view.closure !== 'open' ||
          canonicalValueJson(await summaryOf(original.view)) !== canonicalValueJson(summary)) {
        fail('LocalSigningOriginalConflict');
      }
      const decisions = [];
      for (const [resource, operation] of [['run', 'read'], ['run', 'resolve'], [signingResource, 'sign']]) {
        signal?.throwIfAborted();
        const decision = await gate.authorize('preparation',
          {connection: siteKey, resource, operation},
          {subjectCid: original.view.checkpointCid, signal});
        if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
        decisions.push(decision);
      }
      const assertCurrent = () => {
        signal?.throwIfAborted();
        if (closed) fail('ClientHostClosing');
        gate.assertConfigurationCurrent();
        for (const decision of decisions) gate.assertAccountCurrent(decision);
        const current = journal.originalCheckpointForSigning(original.view.checkpointCid);
        if (current.wire !== original.wire || current.view.closure !== 'open') {
          fail('LocalSigningOriginalConflict');
        }
        const state = journal.getRunState(original.view.runId);
        if (state?.status !== 'waiting_checkpoint' || state.cancelRequested === true) {
          fail('LocalSigningOriginalConflict');
        }
      };
      assertCurrent();
      return Object.freeze({...original, configurationCid: gate.configurationCid,
        assertCurrent});
    },

    async reviewCheckpoint({principalId, checkpointCid, maxBytes, signal}) {
      if (!readers.has(principalId)) fail('CheckpointReviewDenied');
      const view = journal.inspect(checkpointCid);
      // Only a Checkpoint of this Host scope, named by its exact CID, and
      // only its own review projection; never an arbitrary Store CID.
      if (view === undefined || view.checkpointCid !== checkpointCid ||
          view.prepareAttemptId === null &&
            !['effect_set', 'read_access', 'model_invocation'].includes(view.kind)) {
        fail('CheckpointReviewDenied');
      }
      if (view.closure === 'expired' || view.closure === 'cancelled') {
        fail('CheckpointReviewUnavailable');
      }
      signal?.throwIfAborted();
      const bound = Math.min(maxBytes, maxReviewBytes);
      let bytes;
      try {
        if (view.kind === 'model_invocation') {
          const {held, record} = await modelStoredContinuation(view);
          bytes = await held.bytes('review_projection', record.review_storage_cid,
            {maxBytes: bound});
          const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
          const review = contractControl.admitRunEvidence('run_review_projection', wire,
            {maxWireBytes: bound, maxNodes: 10000, maxDepth: 64});
          if (review.wire !== wire || review.identity !== view.reviewProjectionCid) {
            fail('ModelReviewProjectionMismatch');
          }
        } else if (view.kind === 'effect_set' && view.prepareAttemptId === null) {
          const opened = await evidence.open(`effect-${view.runId}`);
          if (opened.requestCid !== view.runDefinitionCid) fail('EffectContinuationRunMismatch');
          // Old pending checkpoints retain their original full-byte identity;
          // this read never upgrades their evidence or reissues a checkpoint.
          if (opened.held('review_projection').includes(view.reviewProjectionCid)) {
            bytes = await opened.bytes('review_projection', view.reviewProjectionCid,
              {maxBytes: bound});
          } else {
            bytes = await opened.artifactBytes('review_projection', view.reviewProjectionCid,
              {maxBytes: bound});
            const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
            const review = contractControl.admitRunEvidence('review_projection', wire,
              {...INSTALLED_EFFECT_CHECKPOINT_LIMITS, maxWireBytes: bound});
            if (review.wire !== wire || review.identity !== view.reviewProjectionCid) {
              fail('EffectReviewProjectionMismatch');
            }
            const body = JSON.parse(wire);
            if (body.effect_preview_cid !== view.requiredArtifact.cid ||
                body.authority_scope_cid !== authorityScopeCid ||
                JSON.stringify(body.approval_claims) !== JSON.stringify(view.requirements)) {
              fail('EffectReviewProjectionMismatch');
            }
          }
        } else {
          const opened = await evidence.open(view.prepareAttemptId ?? `effect-${view.runId}`);
          bytes = await opened.bytes('review_projection',
            view.reviewProjectionCid, {maxBytes: bound});
        }
      } catch (error) {
        if (error?.code === 'EvidenceReadLimitExceeded') {
          fail('CheckpointReviewTooLarge');
        }
        fail('CheckpointReviewUnavailable', error);
      }
      signal?.throwIfAborted();
      return Object.freeze({kind: 'review', checkpointCid,
        artifactCid: view.reviewProjectionCid, byteLength: bytes.byteLength,
        contentBase64: bytes.toString('base64')});
    },

    // Admit each signed answer on its own. The authenticated principal must
    // be the principal of the trusted reviewer whose key signed it; the
    // caller's claims about itself are never used.
    async resolve({principalId, items}) {
      if (!answerers.has(principalId)) fail('CheckpointAnswerDenied');
      const results = new Array(items.length);
      const admitted = [];
      const positions = [];
      items.forEach((item, index) => {
        let reviewer;
        try {
          const resolution = JSON.parse(item.resolutionWire);
          reviewer = trusted.get(resolution?.proof?.key_id);
          if (resolution?.checkpoint_cid !== item.checkpointCid) {
            throw coded('ResolutionCheckpointMismatch');
          }
        } catch (error) {
          results[index] = {checkpointCid: item.checkpointCid,
            status: 'invalid', reason: error?.code ?? 'InvalidResolution'};
          return;
        }
        if (reviewer === undefined || reviewer.principalId !== principalId) {
          results[index] = {checkpointCid: item.checkpointCid,
            status: 'invalid', reason: 'AnswerPrincipalMismatch'};
          return;
        }
        admitted.push({checkpointCid: item.checkpointCid,
          resolutionWire: item.resolutionWire,
          approvalEvidenceWire: item.approvalEvidenceWire});
        positions.push(index);
      });
      if (admitted.length > 0) {
        const answered = await journal.submitResolutions(admitted);
        answered.forEach((result, position) => {
          results[positions[position]] = Object.fromEntries(
            ['checkpointCid', 'status', 'decision', 'resolutionCid', 'reason']
              .filter(key => result[key] !== undefined && result[key] !== null)
              .map(key => [key, result[key]]));
        });
      }
      // The answer is stored; resuming is this Host's separate work. A Host
      // that only records answers leaves the durable intent to the next
      // Host start (for example a separate executing Host process).
      if (resumeAfterAnswer && results.some(result =>
        result.status === 'committed' && result.decision === 'approved')) {
        void sweep();
      }
      return Object.freeze({results: results.map(item =>
        Object.freeze(item))});
    },

    // Install the Host's physical port for held requests ({inspect, resume,
    // abandon, observe}), then sweep once (Host start).
    start(port) {
      host = port;
      return sweep();
    },
    sweep,

    // The checkpoint-journal Run created by a resumed request ended.
    runFinished(runId, status) {
      const run = journal.getRunState(runId);
      if (run === undefined || journal.isTerminalRunOutcome(run.status) ||
          run.status !== 'running') return;
      journal.finishRun(runId, {status});
      // Retention settles in the owned sweep (which stop() waits for), or in
      // close(); never as a detached write.
      void sweep();
    },

    // Stop starting new resumes; running work may still end its Runs.
    stop,
    // After the Host's running dispatches settled: settle retention, then
    // release the evidence owner and the journal. Returns what is left for
    // the next owner (retention that could not complete yet).
    async close() {
      await stop();
      admittedReads.clear();
      gate.close();
      effectTargetGate?.close();
      for (const installed of installedEffectTargets) installed.gate.close();
      resumeGate.close();
      for (const installed of installedSources) {
        installed.gate.close();
        installed.resumeGate.close();
      }
      decisionBudget.close();
      let retention;
      try { retention = await evidence.settle(); }
      finally {
        await evidence.close();
        journal.close();
      }
      return Object.freeze({pendingRetention: retention.pending,
        pendingAuthorization: decisionBudget.cleanupPending()});
    },
  });
  } catch (cause) {
    decisionBudget.close();
    // Before journal custody exists, preserve the original admission error.
    if (journal === undefined) throw cause;
    throw await retainInstalledHostInitializationFailure(cause,
      {journal, store: evidence});
  }
}
