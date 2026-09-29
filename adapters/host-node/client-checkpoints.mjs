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
import {ExecutionAuthorizationError, createAuthorizationDecisionBudget} from
  '../host-common/authorization-gate.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {canonicalJson, contentCid, createLocalAuthorizationGate} from
  './local-account-config.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey,
  openContinuationEvidence} from './local-continuation-evidence.mjs';
import {loadCheckpointRuntime, openSqliteCheckpointJournal} from
  './sqlite-checkpoint-journal.mjs';
import {retainInstalledHostInitializationFailure} from
  './installed-host-cleanup.mjs';

const IDENTIFIER = /^[A-Za-z0-9._:-]{1,128}$/u;
const MAX_REVIEW_BYTES = 256 * 1024;
const MAX_PAGE = 100;
const PAGE = 100;
const LOOKUP_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
const TERMINAL_RUNS = new Set(['succeeded', 'failed', 'cancelled']);

function coded(code, detail) {
  return Object.assign(new Error(code, detail === undefined ? undefined
    : {cause: detail}), {code});
}
const fail = (code, detail) => { throw coded(code, detail); };
const without = (value, ...keys) => Object.fromEntries(
  Object.entries(value).filter(([key]) => !keys.includes(key)));
const hex = value => createHash('sha256').update(value).digest('hex');

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

// Install the Checkpoint connection for one installed Host scope. Returns
// undefined when the Host installs no Run-acceptance protection (then its
// in-process Site is unprotected and pure compute is covered, as before).
// `source` (optional): the installed source's own read authorization,
// {accountConfiguration, context}. With it, a request whose Program acquires
// that source is decided for the Host-resolved read tuple before any Run or
// provider I/O exists, and a delegated read is held like Run acceptance.
export async function installRemoteCheckpoints({root, namespaceId,
  authorityScopeCid, ownerPrincipal, siteKey, realizationKey,
  environmentCid, contractControl, authorization, source,
  now = () => Date.now()}) {
  if (authorization === undefined) return undefined;
  if (authorization === null || typeof authorization !== 'object') {
    fail('InvalidRemoteHostAuthorization');
  }
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
  const sourceGate = source === undefined ? undefined :
    await createLocalAuthorizationGate({
      accountConfiguration: source.accountConfiguration,
      context: source.context, ...decisionOptions});
  const binding = Object.freeze({
    authorizationContextCid: contentCid({principal: ownerPrincipal,
      account_id: gate.accountId ?? null,
      configuration_cid: gate.configurationCid ?? 'missing',
      // A changed source configuration also revalidates held requests.
      source_configuration_cid: sourceGate?.configurationCid ?? null}),
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

  const journal = openSqliteCheckpointJournal(join(state, 'journal'), {
    runtime: await loadCheckpointRuntime(),
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
  let evidence;
  try {
  evidence = openContinuationEvidence({
    stateDirectory: state, ...privateKey, contractControl,
    preparation(prepareAttemptId) {
      if (prepareAttemptId.startsWith('effect-')) {
        const run = journal.getRunState(prepareAttemptId.slice(7));
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
  const readResumeGate = source === undefined ? undefined :
    await createLocalAuthorizationGate({
      accountConfiguration: source.accountConfiguration,
      context: source.context, ...decisionOptions,
      deferral: {journal, authorities, binding,
        describe() { fail('ResumeDoesNotDefer'); }}});
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
        const capturedWire = canonicalJson(captured);
        const invocation = {
          version: 'actql-remote-prepared-invocation/0.1',
          request_cid: requestCid,
          captured_submission_cid: contentCid(captured),
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
        projection.review_projection_cid = contentCid(projection);
        const reviewWire = canonicalJson(projection);
        if (Buffer.byteLength(reviewWire, 'utf8') > maxReviewBytes) {
          fail('CheckpointReviewTooLarge');
        }
        const reviewCid = contentCid(JSON.parse(reviewWire));
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
  const acquisitionIntent = (requestCid, captured) => ({
    version: 'actql-remote-acquisition-intent/0.1',
    request_cid: requestCid,
    captured_submission_cid: contentCid(captured),
    checked_source: captured.acquisition.checkedSource,
    read_tuple: captured.acquisition.readTuple,
    physical_binding: captured.acquisition.physicalBinding,
  });

  // The durable deferral of a request's source read (`read_access`,
  // `prepare_attempt`). `port` persists the Checkpoint: the journal for a new
  // held request, or the current resume claim for one already resuming.
  // `earlier` names the approvals this attempt already holds (checked again
  // on their own before the start).
  function readDeferralFor({prepareAttemptId, request, requestCid, captured,
    answering, port, earlier = []}) {
    return {
      journal: port,
      authorities,
      binding,
      async describe(view) {
        const intent = acquisitionIntent(requestCid, captured);
        const intentCid = contentCid(intent);
        const created = now();
        const expiresAt = new Date(created + checkpointTtlMs).toISOString();
        const projection = {
          version: 'actql-run-review-projection/0.1',
          prepared_invocation_cid: intentCid,
          execution_context_cid: sourceGate.contextCid,
          host_policy_cid: sourceGate.configurationCid,
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
            source: captured.acquisition.checkedSource,
            read_tuple: captured.acquisition.readTuple,
            physical_binding: captured.acquisition.physicalBinding,
          },
          displayed_authoring_context: [{principal: captured.principalId}],
        };
        projection.review_projection_cid = contentCid(projection);
        const reviewWire = canonicalJson(projection);
        if (Buffer.byteLength(reviewWire, 'utf8') > maxReviewBytes) {
          fail('CheckpointReviewTooLarge');
        }
        const reviewCid = contentCid(JSON.parse(reviewWire));
        const items = [
          {name: 'captured_input', wire: canonicalJson(captured)},
          {name: 'invocation_request', wire: canonicalJson(request)},
          // The Store's prepared-invocation slot holds the acquisition
          // intent (a distinct version), never a fabricated invocation.
          {name: 'prepared_invocation', wire: canonicalJson(intent)},
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
            checkpoint_id: `${prepareAttemptId}-acquisition`,
            continuation_state_cid: continuationCid,
            subject: {kind: 'prepare_attempt',
              prepare_attempt_id: prepareAttemptId, continuation: 'start_run'},
            kind: 'read_access',
            required_artifact: {artifact_type: 'read_scope',
              artifact_cid: intentCid},
            review_projection_cid: reviewCid,
            human_summary: `Read ${captured.acquisition.checkedSource.sourceRef}` +
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
    captured, port, earlier, signal}) {
    const answering = answeringAuthorities ??
      authorities.map(item => item.reviewerId);
    const intentCid = contentCid(acquisitionIntent(requestCid, captured));
    const deferring = await createLocalAuthorizationGate({
      accountConfiguration: source.accountConfiguration,
      context: source.context, ...decisionOptions, decide,
      answeringAuthorities: decide === undefined ? undefined : answering,
      deferral: readDeferralFor({prepareAttemptId, request, requestCid,
        captured, answering, port, earlier})});
    try {
      return await deferring.authorize('acquisition',
        captured.acquisition.readTuple, {subjectCid: intentCid, signal});
    } finally { deferring.close(); }
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
    if (contentCid(invocation) !== continuation.invocation_cid ||
        invocation.captured_submission_cid !== contentCid(captured) ||
        invocation.request_cid !== opened.requestCid ||
        contentCid(request) !== opened.requestCid ||
        continuation.prepare_attempt_id !== prepareAttemptId) {
      fail('ArtifactIntegrityFailed');
    }
    return {continuation, captured, request};
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
          if (TERMINAL_RUNS.has(status)) {
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
    if (readHeld && (readResumeGate === undefined ||
        captured.acquisition === undefined)) {
      await host.abandon(captured);
      end('failed');
      return 'done';
    }
    // Approvals this attempt answered earlier (Run acceptance before a read)
    // are each checked on their own at the Host trusted time.
    const earlierCurrent = () => {
      for (const checkpointCid of continuation.earlier_approvals ?? []) {
        if (journal.committedApprovalAt(checkpointCid).current !== true) {
          throw Object.assign(new Error('ApprovalExpired'),
            {code: 'ApprovalExpired'});
        }
      }
    };
    const decision = readHeld
      ? await readResumeGate.resume('acquisition',
        captured.acquisition.readTuple, {
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
    // Run acceptance approved for a Program that reads the installed
    // source: its read is decided now, before any Run or provider I/O. A
    // delegated read is held as this attempt's next Checkpoint (under the
    // current claim) and resumes later on its own approval. An immediate
    // Host permit is kept for this attempt's start, as for a new request.
    let readPermit = false;
    if (!readHeld && captured.acquisition !== undefined &&
        sourceGate !== undefined) {
      // The read decision gets a full lease; a claim that lapses meanwhile
      // persists nothing and the next claim decides the read again.
      try { journal.renewResume(claim, leaseMs); }
      catch (error) {
        if (error?.code === 'ResumeClaimStale') return 'busy';
        throw error;
      }
      const read = await decideRead({prepareAttemptId, request,
        requestCid: contentCid(request), captured,
        earlier: [claimed.checkpointCid],
        port: {
          persistCheckpoint: ({body, authorities: reviewers, binding: bound,
            decisionSubjectCid, requestedClaims, configurationCid}) =>
            journal.completeResume(claim, {checkpoint: {body,
              authorities: reviewers, binding: bound, decisionSubjectCid,
              requestedClaims, configurationCid}}),
          submitResolution: item => journal.submitResolution(item),
        }});
      if (read.action === 'waiting') return 'done';
      // A lapsed or superseded claim sends nothing and ends nothing: the
      // read Checkpoint was not persisted, and the intent is retried.
      if (read.error?.code === 'ResumeClaimStale' ||
          read.detail === 'ResumeClaimStale') return 'busy';
      if (read.action !== 'dispatch') {
        await host.abandon(captured);
        end('failed');
        return 'done';
      }
      readPermit = read.basis === 'host_permit';
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
        // The source adapter's current-authority check right after the
        // start reservation accepts this exact admitted read approval.
        if (readHeld) {
          admittedReads.set(captured.requestId, Object.freeze({
            checkpointCid: claimed.checkpointCid,
            readTuple: captured.acquisition.readTuple,
            acquisition: captured.acquisition,
            principalId: captured.principalId,
            earlier: [...(continuation.earlier_approvals ?? [])],
            prepareAttemptId}));
        } else if (readPermit) {
          // The Host's immediate read permit for this attempt: it holds
          // only while the Run acceptance approval is current and the
          // request is not cancelled, and ends with the dispatch.
          admittedReads.set(captured.requestId, Object.freeze({
            readTuple: captured.acquisition.readTuple,
            acquisition: captured.acquisition,
            principalId: captured.principalId,
            earlier: [claimed.checkpointCid,
              ...(continuation.earlier_approvals ?? [])],
            prepareAttemptId}));
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
      expiresAt: view.expiresAt, humanSummary: view.humanSummary});
  };

  return Object.freeze({
    configured,
    journal,
    binding,

    // Host-installed Effect execution uses this same journal and reviewer
    // authority. The read boundary has no deferral port in this profile:
    // a deferred target read is unsupported before any provider I/O.
    async effectAuthorization({runId, runDefinitionCid, unitId,
      declaredResults, reviewWire, continuationWire, beforeDefer}) {
      if (!IDENTIFIER.test(runId ?? '') || !IDENTIFIER.test(unitId ?? '') ||
          typeof beforeDefer !== 'function' ||
          typeof reviewWire !== 'string' ||
          typeof continuationWire !== 'string' ||
          !Array.isArray(declaredResults)) {
        fail('InvalidInstalledEffectContinuation');
      }
      declaredResults = Object.freeze([...declaredResults]);
      const common = {accountConfig, accountConfiguration,
        principal: ownerPrincipal, decide,
        answeringAuthorities: answeringAuthorities === undefined
          ? authorities.map(item => item.reviewerId)
          : [...answeringAuthorities]};
      const read = await createLocalAuthorizationGate(common);
      let commit;
      try {
        commit = await createLocalAuthorizationGate({...common,
          requiredClaims: effectClaims,
          deferral: {journal, authorities, binding,
            async describe(view) {
              if (view.boundary !== 'effect_commit' &&
                  view.subject.boundary !== 'effect_commit') {
                fail('InvalidEffectCheckpointBoundary');
              }
              await beforeDefer();
              const id = `effect-${runId}`;
              const refs = await evidence.hold(id, runDefinitionCid, [
                {name: 'review_projection', wire: reviewWire},
                {name: 'continuation_record', wire: continuationWire},
              ]);
              const created = now();
              return {priorStatus: 'running', declaredResults, body: {
                checkpoint_id: `${runId}-effect-commit`, run_id: runId,
                run_definition_cid: runDefinitionCid,
                continuation_state_cid: refs[1],
                subject: {kind: 'run_unit', run_id: runId, unit_id: unitId,
                  continuation: 'resume_unit'},
                required_artifact: {artifact_cid: view.subject.subject_cid},
                review_projection_cid: refs[0],
                human_summary: 'Approve the complete Effect Set',
                created_at: new Date(created).toISOString(),
                expires_at: new Date(created + checkpointTtlMs).toISOString(),
              }};
            },
          }});
        if (read.configurationCid !== gate.configurationCid ||
            commit.configurationCid !== gate.configurationCid) {
          fail('EffectCheckpointConfigurationChanged');
        }
        return Object.freeze({
          authorize: (boundary, ...args) =>
            (boundary === 'effect_commit' ? commit : read)
              .authorize(boundary, ...args),
          resume: (...args) => commit.resume(...args),
          close() { read.close(); commit.close(); },
        });
      } catch (error) {
        read.close();
        commit?.close();
        throw error;
      }
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
      const view = journal.inspect(`${runId}-effect-commit`);
      if (view === undefined) return undefined;
      if (view.kind !== 'effect_set' || view.runId !== runId ||
          view.runDefinitionCid !== runDefinitionCid ||
          view.prepareAttemptId !== null) {
        fail('EffectContinuationRunMismatch');
      }
      return journal.getRunState(runId);
    },
    // Principals admitted to the Checkpoint operations at all. Each
    // operation still applies its own authorization.
    admitsCheckpointPrincipal: principal => principal === ownerPrincipal ||
      readers.has(principal) || answerers.has(principal),

    // Decide Run acceptance for one Host-resolved request before any Run
    // definition exists. `dispatch`: continue; `held`: the durable held
    // reply; refusals throw with their ACTQL runtime code and record nothing.
    async acceptRun({requested, captured, signal}) {
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
        deferral: deferralFor({prepareAttemptId, request, requestCid,
          captured, answering})});
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
            captured_submission_cid: contentCid(captured),
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
      if (captured.acquisition === undefined || sourceGate === undefined) {
        return {kind: 'dispatch'};
      }
      const prepareAttemptId = prepareAttemptIdOf(captured.requestId);
      const subject = requestSubject(requested);
      const request = {version: 'actql-remote-invocation-request/0.1',
        subject, subject_cid: contentCid(subject)};
      const requestCid = contentCid(request);
      const decision = await decideRead({prepareAttemptId, request,
        requestCid, captured, port: journal, signal});
      if (decision.action === 'dispatch') {
        // An immediate Host permit (not an account allow) is this request's
        // one-time read grant for the adapter's current-authority check in
        // this process; it is never persisted or reused elsewhere.
        if (decision.basis === 'host_permit') {
          admittedReads.set(captured.requestId, Object.freeze({
            readTuple: captured.acquisition.readTuple,
            acquisition: captured.acquisition,
            principalId: captured.principalId, earlier: []}));
        }
        return {kind: 'dispatch'};
      }
      if (decision.action === 'waiting') {
        return {kind: 'held', held: held(prepareAttemptId,
          captured.requestId)};
      }
      await evidence.abandon(prepareAttemptId);
      throw refusal(decision);
    },

    // The source access a request's acquisition uses. For a request whose
    // read was held and approved, the adapter's current-authority check just
    // before provider I/O (and before Source Evidence) accepts that exact
    // admitted approval while it is still current and the request is not
    // cancelled; deny and allow are the source account's own. Every other
    // request uses the installed access unchanged.
    acquisitionAccess(requestId, base) {
      const admitted = admittedReads.get(requestId);
      if (admitted === undefined || sourceGate === undefined) return base;
      const same = scope => ['connection', 'resource', 'operation'].every(
        key => scope?.[key] === admitted.readTuple[key]);
      const authorization = Object.freeze({
        ...base.authorization,
        async authorize(boundary, scope, options) {
          const current = await base.authorization.authorize(boundary, scope,
            options);
          if (current.action === 'dispatch' || current.action === 'deny' ||
              boundary !== 'acquisition' || !same(scope)) return current;
          const preparation = admitted.prepareAttemptId === undefined
            ? undefined : journal.getPreparation(admitted.prepareAttemptId);
          const approvedNow = cid => {
            try { return journal.committedApprovalAt(cid).current === true; }
            catch { return false; }
          };
          const valid = preparation?.cancelRequested !== true &&
            [admitted.checkpointCid, ...admitted.earlier]
              .filter(cid => cid !== undefined).every(approvedNow);
          // The returned approval carries the exact approved read, which a
          // source adapter verifies against its own installation.
          return valid ? recordCheckpointApproval(Object.freeze({boundary,
            action: 'dispatch', basis: 'resumed_approval',
            tuple: Object.freeze({...scope}),
            checkpointCid: admitted.checkpointCid}), {
            checkpointCid: admitted.checkpointCid,
            readTuple: admitted.readTuple,
            physicalBinding: admitted.acquisition?.physicalBinding,
            checkedSource: admitted.acquisition?.checkedSource,
            principalId: admitted.principalId}) : current;
        },
      });
      return Object.freeze({...base, authorization});
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

    async listCheckpoints({principalId, after, limit}) {
      if (!(principalId === ownerPrincipal || readers.has(principalId) ||
          answerers.has(principalId))) {
        fail('CheckpointListDenied');
      }
      journal.expire();
      const bounded = Math.min(limit, MAX_PAGE);
      const rows = journal.listPending({after: after === '' ? undefined
        : after, limit: bounded + 1});
      const page = rows.slice(0, bounded);
      return Object.freeze({items: await Promise.all(page.map(summaryOf)),
        ...(rows.length > bounded ? {next: page.at(-1).cursor} : {})});
    },

    async reviewCheckpoint({principalId, checkpointCid, maxBytes, signal}) {
      if (!readers.has(principalId)) fail('CheckpointReviewDenied');
      const view = journal.inspect(checkpointCid);
      // Only a Checkpoint of this Host scope, named by its exact CID, and
      // only its own review projection; never an arbitrary Store CID.
      if (view === undefined || view.checkpointCid !== checkpointCid ||
          view.prepareAttemptId === null && view.kind !== 'effect_set') {
        fail('CheckpointReviewDenied');
      }
      if (view.closure === 'expired' || view.closure === 'cancelled') {
        fail('CheckpointReviewUnavailable');
      }
      signal?.throwIfAborted();
      const bound = Math.min(maxBytes, maxReviewBytes);
      let bytes;
      try {
        const opened = await evidence.open(view.prepareAttemptId ??
          `effect-${view.runId}`);
        bytes = await opened.bytes('review_projection',
          view.reviewProjectionCid, {maxBytes: bound});
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
      if (run === undefined || TERMINAL_RUNS.has(run.status) ||
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
    throw await retainInstalledHostInitializationFailure(cause,
      {journal, store: evidence});
  }
}
