// One installed Local Host for the current OS user. The Client talks to the
// Host in process; the journal and publication Store own durable physical I/O.
import {createHash, createPublicKey} from 'node:crypto';
import {mkdir, readFile, stat} from 'node:fs/promises';
import {homedir, userInfo} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {admitHostRootFormat} from './host-root-format.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {installNodeClientEffectRun} from './client-effect-run.mjs';
import {runCapturedEffectComputation} from './entry.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
import {recoverAdmittedEffectRun} from './effect-run-recovery.mjs';
import {retireCompletedEffectfulCapture} from
  '../host-common/completed-run-publication.mjs';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installedEffectIdentity, loadInstalledEffect,
  publishInstalledEffectProfile} from
  './installed-effect.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey} from
  './local-continuation-evidence.mjs';
import {installedSourceIdentity, loadInstalledSource,
  publishInstalledSourceProfile} from
  './installed-source.mjs';
import {createDiagnosticObserver} from
  '../host-common/diagnostic-observer.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {createInstalledHostShutdown,
  retainInstalledHostInitializationFailure} from
  './installed-host-cleanup.mjs';
import {composeInstalledCheckEnvironment,
  verifyInstalledConnectorBindings} from
  './installed-check-environment.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from './result-access.mjs';
import {installRunStateAuthority, installRunStateService,
  inspectAuthorizedRunState} from '../host-common/run-state-access.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {localContractLimits, localOutputLimits,
  sourceFreeValuesPlan, sourceFreeTaskPlan,
  sourceFreeEffectPublicationPlan, acquiredEffectPublicationAdmission,
  acquiredTaskRunAdmission} from
  './local-values-plan.mjs';

const packageRoot = fileURLToPath(new URL('../../', import.meta.url));
const runtimeUrl = new URL('../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const now = () => new Date().toISOString();
const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const plus = (date, milliseconds) => new Date(Date.parse(date) +
  milliseconds).toISOString();
const profiles = new Map();

const bytesCid = bytes => `sha256:${createHash('sha256')
  .update(bytes).digest('hex')}`;
const publicKeyCid = value => bytesCid(createPublicKey(value).export({
  type: 'spki', format: 'der'}));

async function embeddedInstallationIdentity(root, installation) {
  const sourcePath = installation?.sourceProfilePath ??
    process.env.ACTQL_LOCAL_SOURCE_PROFILE;
  const effectPath = installation?.effectProfilePath ??
    process.env.ACTQL_LOCAL_EFFECT_PROFILE;
  const source = sourcePath === undefined ? null :
    await installedSourceIdentity(sourcePath);
  const effect = effectPath === undefined ? null :
    await installedEffectIdentity(effectPath);
  const authorization = installation?.authorization;
  const accountIdentity = authorization?.accountConfiguration !== undefined
    ? bytesCid(canonicalJson(JSON.parse(
      authorization.accountConfiguration)))
    : authorization?.accountConfig === undefined ? null :
      bytesCid(canonicalJson(JSON.parse(await readFile(
        authorization.accountConfig, 'utf8'))));
  const ordinary = Object.fromEntries(Object.entries(authorization ?? {})
    .filter(([key, value]) => !['accountConfiguration', 'accountConfig',
      'hostKey', 'reviewers'].includes(key) &&
      typeof value !== 'function'));
  const identity = bytesCid(canonicalJson({
    version: 'actql-embedded-installation/0.1', root,
    source, effect, accountIdentity, ordinary,
    hostKey: authorization?.hostKey === undefined ? null : {
      keyId: authorization.hostKey.keyId,
      publicKeyCid: publicKeyCid(authorization.hostKey.privateKey)},
    reviewers: authorization?.reviewers?.map(reviewer => ({
      keyId: reviewer.keyId, reviewerId: reviewer.reviewerId,
      principalId: reviewer.principalId,
      publicKeyCid: publicKeyCid(reviewer.publicKey)})) ?? null}));
  return Object.freeze({identity, callbacks: Object.freeze({
    resolveSourceSecret: installation?.resolveSourceSecret,
    resolveEffectSecret: installation?.resolveEffectSecret,
    decide: authorization?.decide, observe: authorization?.observe,
    faultInjection: authorization?.faultInjection})});
}

function sameEmbeddedInstallation(left, right) {
  return left.identity === right.identity &&
    Object.keys(left.callbacks).every(key =>
      left.callbacks[key] === right.callbacks[key]);
}

function localStateRoot() {
  const supplied = process.env.ACTQL_LOCAL_STATE_DIR;
  if (supplied !== undefined && !supplied) {
    throw new TypeError('InvalidLocalStateDirectory');
  }
  return resolve(supplied ?? join(homedir(), '.local', 'share', 'actql'));
}

// The realization this installed Host runs: source-free values Programs on
// its in-process Site. With Run-acceptance protection installed, the account
// decides the tuple (Site key, this realization, write) for each request.
const REALIZATION_KEY = 'source-free-values';

async function openInstalledHost({root, mode = 'local', beforeDispatch,
  authorization, sourceProfilePath, resolveSourceSecret,
  effectProfilePath, resolveEffectSecret, effectInstallation}) {
  const selectedSourcePath = sourceProfilePath ??
    process.env.ACTQL_LOCAL_SOURCE_PROFILE;
  const selectedEffectPath = effectProfilePath ??
    process.env.ACTQL_LOCAL_EFFECT_PROFILE;
  if (effectInstallation !== undefined && selectedEffectPath !== undefined) {
    throw new TypeError('InvalidInstalledEffectSite');
  }
  await admitHostRootFormat(root);
  const moon = await import(runtimeUrl.href);
  const control = runtimeCore(moon).publicationControl;
  const principalId = userInfo().username;
  const baseEnvironmentWire = (await readFile(join(packageRoot,
    'spec/local-check-environment.json'), 'utf8')).trimEnd();
  // Both adapters restore published declarations without provider I/O. The
  // combined environment is admitted before either can dispatch work.
  let sourceProfile;
  let installedEffect;
  let environmentWire;
  try {
    sourceProfile = await loadInstalledSource(selectedSourcePath,
      {root, principalId, moon, runtimeUrl, baseEnvironmentWire,
        resolveSecret: resolveSourceSecret});
    installedEffect = selectedEffectPath === undefined ? undefined :
      await loadInstalledEffect(selectedEffectPath, {root, principalId, moon,
        runtimeUrl, baseEnvironmentWire, resolveSecret: resolveEffectSecret});
    if (installedEffect !== undefined) {
      if (authorization === undefined) {
        throw new TypeError('InstalledEffectAuthorizationRequired');
      }
      effectInstallation = createInstalledEffectSite(installedEffect);
    }
    if (effectInstallation !== undefined &&
        (typeof effectInstallation.environmentWire !== 'string' ||
          typeof effectInstallation.execute !== 'function' ||
          typeof effectInstallation.resume !== 'function' ||
          effectInstallation.privateEvidenceKey !== undefined &&
            (!(effectInstallation.privateEvidenceKey instanceof Uint8Array) ||
              effectInstallation.privateEvidenceKey.byteLength !== 32))) {
      throw new TypeError('InvalidInstalledEffectSite');
    }
    environmentWire = composeInstalledCheckEnvironment(moon,
      baseEnvironmentWire, sourceProfile?.environmentWire,
      effectInstallation?.environmentWire);
    const {evidence_bundle_cid: ignored, ...body} = JSON.parse(environmentWire);
    void ignored;
    body.host_policy_profile = {...body.host_policy_profile,
      capacity: {...body.host_policy_profile.capacity,
        max_graph_construction_edges: 1000,
        max_graph_construction_input_rows: 1000,
        max_graph_construction_nodes: 1000}};
    environmentWire = canonicalJson({...body,
      evidence_bundle_cid: contentCid(body)});
    verifyInstalledConnectorBindings(sourceProfile,
      installedEffect ?? effectInstallation);
  } catch (cause) {
    // An adapter that failed before returning its owner must clean up its
    // own partial acquisition. Preserve its original public failure when the
    // Host has acquired nothing else.
    if (sourceProfile === undefined && installedEffect === undefined) {
      throw cause;
    }
    throw await retainInstalledHostInitializationFailure(cause,
      {sourceProfile, installedEffect});
  }
  let environment;
  let evidenceCid;
  try {
    evidenceCid = JSON.parse(environmentWire).evidence_bundle_cid;
    const numericProfile = JSON.parse(await readFile(join(packageRoot,
      'spec/contracts/actql-numeric-reduction.json'), 'utf8'));
    const numericProfileCid = `sha256:${createHash('sha256')
      .update(canonicalJson(numericProfile)).digest('hex')}`;
    environment = moon.clientProgramCheckEnvironmentWithNumericProfile(
      environmentWire, evidenceCid, false, false, true, true, false, false,
      false, numericProfileCid);
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause,
      {sourceProfile, installedEffect});
  }
  if (environment === undefined) {
    throw await retainInstalledHostInitializationFailure(
      new Error('InvalidInstalledLocalEnvironment'),
      {sourceProfile, installedEffect});
  }
  let registry;
  let values;
  let fragment;
  let ordered;
  const namespaceId = 'local';
  const authorityScopeCid = cid({version: 'actql-local-owner-scope/0.1',
    root, principalId});
  const storeAuthorityCid = cid({version: 'actql-local-store-owner/0.1',
    root, principalId});
  const journalDirectory = join(root, 'requests');
  let journal;
  let effectEvidenceKey;
  let store;
  let checkpoints;
  let dispatchOwner;
  let diagnostic;
  try {
    diagnostic = createDiagnosticObserver(authorization?.observe);
    registry = await readFile(join(packageRoot,
      'spec/dependencies/aoa-pipeline-registry.json'), 'utf8');
    const aoa = JSON.parse(await readFile(join(packageRoot,
      'spec/contracts/actql-aoa.json'), 'utf8'));
    values = JSON.stringify(aoa.execution_contracts['REL.values']);
    fragment = JSON.stringify(
      aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
    ordered = JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
    await mkdir(journalDirectory, {recursive: true, mode: 0o700});
    journal = openClientRequestJournal(journalDirectory);
    if (effectInstallation !== undefined &&
        effectInstallation.privateEvidenceKey === undefined) {
      const keyDirectory = join(root, 'checkpoints');
      try {
        effectEvidenceKey = await loadPrivateEvidenceKey(keyDirectory);
      } catch (error) {
        if (error?.code !== 'PrivateEvidenceKeyUnavailable') throw error;
        let existing = false;
        try { existing = (await stat(keyDirectory)).isDirectory(); }
        catch (missing) { if (missing?.code !== 'ENOENT') throw missing; }
        if (existing) throw error;
        await createPrivateEvidenceKey(keyDirectory);
        effectEvidenceKey = await loadPrivateEvidenceKey(keyDirectory);
      }
    }
    store = await openLocalPublicationStore({
      directory: join(root, 'publication'), storeAuthorityCid,
      capacityBytes: 512 * 1024 * 1024,
      maxObjectBytes: localOutputLimits.maxWireBytes,
      maxObjects: 10000, maxContractNodes: 10000,
      maxContractDepth: 64,
      ...(effectInstallation === undefined ? {} : {
        privateEvidenceKey: effectInstallation.privateEvidenceKey ??
          effectEvidenceKey?.key}),
    }, control);
    effectEvidenceKey?.key.fill(0);
  const hostConnection = ({principalId: actual, connection, ref}) =>
    actual === principalId &&
    connection.mode === mode && connection.owner === mode &&
    (ref === undefined || ref.namespaceId === namespaceId &&
      ref.authorityScopeCid === authorityScopeCid);
  const authorizedScope = ({principalId: actual}) =>
    actual === principalId ? {namespaceId, authorityScopeCid} : undefined;
  const lookupRequest = installNodeClientRequestLookup({journal,
    control: moon, authorizedScope});
  const startRun = installNodeClientRunStart({journal,
    requestControl: moon, publicationControl: control,
    authorizeRunStart: ({principalId: actual, connection, ref}) =>
      hostConnection({principalId: actual, connection, ref})});
  const resultAuthority = installResultAccessAuthority({
    authorizeResultReadRequest: ({principalId: actual}) =>
      actual === principalId,
    admitResultRead: ({attemptId}) => ({
      authorizationContextCid: cid({version: 'actql-local-read/0.1',
        attemptId}),
      dataCeilingCid: cid({version: 'actql-local-read-ceiling/0.1'}),
      egressAdmissionCid: cid({version: 'actql-local-egress/0.1'}),
      expiresAt: plus(now(), 60 * 60 * 1000),
      maxBytes: localOutputLimits.maxWireBytes, maxUses: 1,
    }),
    authorizeResultRead: ({principalId: actual}) =>
      actual === principalId,
    authorizeDeliveryAttemptLookup: ({principalId: actual}) =>
      actual === principalId,
  });
  const resultService = installNodeResultAccessService({store, control,
    authority: resultAuthority, now, limits: localContractLimits,
    frameLimits: {maxRowBytes: 1024 * 1024, maxDepth: 64,
      maxFrameBytes: 1024 * 1024}});
  const stateService = installRunStateService({store, control,
    authority: installRunStateAuthority({
      authorizeRunState: ({principalId: actual}) => actual === principalId,
      resultPolicyAvailable: () => true,
    }), now, limits: localContractLimits});
  const attach = installNodeClientRunAttach({journal,
    requestControl: moon, publicationControl: control, authorizedScope,
    authorizeRun: ({ref, principalId: actual}) =>
      actual === principalId && ref.namespaceId === namespaceId &&
      ref.authorityScopeCid === authorityScopeCid});
  const prepareSubmit = installNodeClientProgramPreparation({moon,
    environment, allowEffects: effectInstallation !== undefined});
    checkpoints = await installRemoteCheckpoints({root, namespaceId,
      authorityScopeCid, ownerPrincipal: principalId,
      siteKey: authorization?.siteKey ?? 'actql-remote-host',
      realizationKey: sourceProfile?.realizationKey ?? REALIZATION_KEY,
      environmentCid: evidenceCid,
      contractControl: control,
      authorization: authorization == null ? authorization :
        {...authorization, observe: diagnostic},
      source: sourceProfile?.readAuthorization});
  const observeRun = async ({ref, principalId: actual}) => {
    if (actual !== principalId || ref.namespaceId !== namespaceId ||
        ref.authorityScopeCid !== authorityScopeCid) {
      throw new Error('RunStateAccessDenied');
    }
    // Recheck the journal revision after asynchronous Store observation so
    // control facts never combine observations from two journal revisions.
    for (let attempt = 0; attempt < 8; attempt++) {
      const retained = journal.lookupRunDefinition(ref, moon, control);
      if (retained === undefined) throw new Error('RunStateAccessDenied');
      const runId = control.runDefinitionRunId(retained.runDefinition);
      let state;
      let continuation;
      if (await store.confirmCommittedIndex(ref) !== undefined) {
        state = await inspectAuthorizedRunState(stateService, {
          indexKey: ref, principalId: actual, purpose: 'inspect',
        });
      } else {
        if (!Array.isArray(retained.resultNames)) {
          throw new Error('RunStateInventoryUnknown');
        }
        continuation = checkpoints?.effectRunState(runId,
          ref.runDefinitionCid);
        if (continuation?.status === 'succeeded') {
          // A second journal cannot establish Publication Store success.
          // Reobserve the committed index instead of issuing success from
          // the Checkpoint lifecycle alone.
          continue;
        }
        if (continuation !== undefined &&
            continuation.status !== 'running') {
          state = continuation.runState;
        } else {
          const liveExecution = dispatchOwner.live(ref);
          const executionUnknown = retained.dispatchReserved &&
            !retained.preDispatchFailureConfirmed &&
            retained.physicalStartReserved !== false &&
            retained.observedTerminalOutcome === null && !liveExecution;
          const wire = checked(
            moon.clientProgramIssueControlledUnpublishedRunState(
              runId, now(), retained.resultNames, retained.dispatchReserved,
              retained.preDispatchFailureConfirmed,
              retained.cancellationRequested &&
                retained.physicalStartReserved === false,
              retained.observedTerminalOutcome ?? 'none', executionUnknown));
          state = JSON.parse(wire);
        }
      }
      const after = journal.lookupRunDefinition(ref, moon, control);
      if (after?.revision !== retained.revision) continue;
      if (continuation !== undefined) {
        const afterContinuation = checkpoints.effectRunState(runId,
          ref.runDefinitionCid);
        if (afterContinuation?.version !== continuation.version) continue;
      }
      if (state.status === 'running' && !dispatchOwner.live(ref) &&
          retained.physicalStartReserved === true) {
        continue;
      }
      const observation = moon.clientRunControlObservation(retained.revision,
        retained.cancellationRequested,
        retained.physicalStartReserved === false,
        retained.preDispatchFailureConfirmed, retained.physicalCloseConfirmed);
      if (observation === undefined) throw new Error('InvalidRunControl');
      return {...state, control: JSON.parse(observation)};
    }
    throw new Error('RunStateObservationUnstable');
  };
  const cancelEffectContinuation = ref => {
    if (checkpoints === undefined) return false;
    const retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined || !retained.cancellationRequested) {
      return false;
    }
    const runId = control.runDefinitionRunId(retained.runDefinition);
    const view = checkpoints.journal.inspect(`${runId}-effect-commit`);
    if (view?.kind !== 'effect_set' || view.runId !== runId ||
        view.runDefinitionCid !== ref.runDefinitionCid ||
        view.prepareAttemptId !== null) return false;
    const state = checkpoints.journal.getRunState(runId)?.status;
    if (state === 'waiting_checkpoint') {
      return checkpoints.journal.cancelCheckpoint(view.checkpointCid)
        .outcome === 'cancelled';
    }
    if (state === 'resuming') {
      return checkpoints.journal.cancelUnsentResume(view.checkpointCid)
        .outcome === 'cancelled';
    }
    return false;
  };
  const cancel = async ({ref, principalId: actual, connection}) => {
    if (!hostConnection({principalId: actual, connection, ref})) {
      throw new Error('ClientRunCancellationDenied');
    }
    // Authorization precedes existence queries. A late publication remains a
    // successful Run even if cancellation was accepted while it committed.
    const publicationCommitted =
      await store.confirmCommittedIndex(ref) !== undefined;
    const accepted = journal.requestCancellation(ref, {
      currentAuthorization: true, publicationCommitted,
    }, moon, control);
    if (accepted.kind !== 'already_terminal') {
      dispatchOwner.cancel(ref);
      cancelEffectContinuation(ref);
      void checkpoints?.sweep();
    }
    return accepted;
  };
  // Cancel a request by its ID. For a request this Host held, the
  // cancellation is first made durable on its prepare attempt, so a resume
  // (on this or a later start) cannot start it and hands it to the Run.
  // When the request has a Run (created before or concurrently), the same
  // cancellation is then applied to that Run through its own cancellation,
  // which the physical start reservation observes atomically.
  const cancelRequest = async ({principalId: actual, connection,
    requestId}) => {
    if (!hostConnection({principalId: actual, connection})) {
      throw Object.assign(new Error('ClientRequestCancellationDenied'),
        {code: 'ClientRequestCancellationDenied'});
    }
    const held = checkpoints?.heldOrigin(requestId)
      ? checkpoints.cancelHeld(requestId) : undefined;
    const existing = journal.lookupDefinition({namespaceId, authorityScopeCid,
      requestId}, moon, control);
    if (existing !== undefined) {
      const run = await cancel({ref: existing.ref, principalId: actual,
        connection});
      void checkpoints?.sweep();
      return {requestId, ref: run.ref, revision: run.revision,
        kind: held?.outcome === 'accepted' && run.kind === 'already_requested'
          ? 'accepted' : run.kind};
    }
    if (held === undefined) {
      throw Object.assign(new Error('ClientRequestNotFound'),
        {code: 'ClientRequestNotFound'});
    }
    void checkpoints.sweep();
    return {requestId, kind: held.outcome};
  };
  const wait = async ({ref, principalId: actual, until, signal}) => {
    if (until !== null && until !== 'terminal') {
      throw new Error('InvalidWaitCondition');
    }
    const current = await observeRun({ref, principalId: actual});
    if (['succeeded', 'failed', 'cancelled'].includes(current.status)) {
      return current;
    }
    const operation = dispatchOwner.operation(ref);
    if (operation === undefined) return current;
    if (signal?.aborted) throw new Error('WaitAborted');
    let abort;
    const interrupted = new Promise((_, reject) => {
      abort = () => reject(new Error('WaitAborted'));
      signal?.addEventListener('abort', abort, {once: true});
    });
    try {
      await Promise.race([operation, interrupted]);
    } finally {
      signal?.removeEventListener('abort', abort);
    }
    return observeRun({ref, principalId: actual});
  };
  const requestOf = ({preparedProgram, requestId}) => {
    prepareSubmit.assertOwned(preparedProgram);
    if (prepareSubmit.kindOf(preparedProgram) === 'effectful') {
      const acquired = moon.clientProgramEffectPrepareQueryAcquisition(
        preparedProgram, 0, 0)?.$tag === 1;
      if (acquired) {
        if (sourceProfile === undefined) {
          throw new Error('ClientProgramNeedsInputs');
        }
        let requirement;
        try {
          requirement = checked(
            moon.clientProgramEffectPrepareLocalQueryRequirement(
              preparedProgram, 0, 0, registry, values, fragment, ordered));
        } catch (cause) {
          throw Object.assign(new Error('ClientProgramUnsupported', {cause}),
            {code: 'ClientProgramUnsupported'});
        }
        if (!sourceProfile.admitsSource(
          moon.clientProgramQueryRequirementSourceRef(requirement))) {
          throw new Error('InstalledSourceProgramMismatch');
        }
      }
      const requested = moon.clientProgramEffectRequestIdentity(
        preparedProgram, authorityScopeCid, requestId,
        moon.clientProgramSourceFreeInputIntentCid());
      if (requested === undefined) {
        throw new Error('ClientProgramNeedsInputs');
      }
      const resultNames = [];
      for (let index = 0;
        index < moon.clientProgramEffectResultCount(preparedProgram);
        index++) {
        const name = moon.clientProgramEffectResultName(preparedProgram,
          index);
        if (name === undefined) {
          throw new Error('ClientProgramResultMissing');
        }
        resultNames.push(name);
      }
      return {requested, resultNames, acquired, effectful: true};
    }
    const acquisition = moon.clientProgramPrepareQueryAcquisition(
      preparedProgram, 0, 0);
    const acquired = acquisition?.$tag === 1;
    if (acquired) {
      if (sourceProfile === undefined) {
        throw new Error('ClientProgramNeedsInputs');
      }
      // A checked acquisition the local planner cannot generate is an
      // unsupported Program: refused before any Run exists.
      let requirement;
      try {
        requirement = checked(
          moon.clientProgramPrepareLocalQueryRequirement(preparedProgram,
            0, 0, registry, values, fragment, ordered));
      } catch (cause) {
        throw Object.assign(new Error('ClientProgramUnsupported', {cause}),
          {code: 'ClientProgramUnsupported'});
      }
      if (!sourceProfile.admitsSource(
        moon.clientProgramQueryRequirementSourceRef(requirement))) {
        throw new Error('InstalledSourceProgramMismatch');
      }
    }
    const requested = moon.clientProgramRequestIdentity(preparedProgram,
      authorityScopeCid, requestId,
      moon.clientProgramSourceFreeInputIntentCid());
    if (requested === undefined) {
      throw new Error('ClientProgramNeedsInputs');
    }
    const resultNames = [];
    for (let index = 0;
      index < moon.clientProgramResultCount(preparedProgram); index++) {
      const name = moon.clientProgramResultName(preparedProgram, index);
      if (name === undefined) throw new Error('ClientProgramResultMissing');
      resultNames.push(name);
    }
    return {requested, resultNames, acquired, effectful: false};
  };
  const prepareAcquisition = (preparedProgram,
    sourceAccess = sourceProfile.sourceAccess) =>
    sourceProfile.prepare({preparedProgram, registry, values, fragment,
      ordered, sourceAccess});
  const planFor = ({preparedProgram, requestId},
    retainedDefinitionWire) => {
    prepareSubmit.assertOwned(preparedProgram);
    const common = {moon, control, preparedProgram,
      authorityScopeCid, namespaceId, requestId, storeAuthorityCid, now,
      ...(retainedDefinitionWire === undefined ? {} :
        {retainedDefinitionWire})};
    return sourceProfile !== undefined &&
      moon.clientProgramPrepareQueryAcquisition(preparedProgram, 0, 0)?.$tag ===
        1
      ? acquiredTaskRunAdmission(common)
      : moon.clientProgramTaskCount(preparedProgram) > 1 ||
          moon.clientProgramUsesGraphCarrier(preparedProgram)
        ? sourceFreeTaskPlan(common)
        : sourceFreeValuesPlan(common);
  };
  // Admit (or look up) the request's Run Definition: the durable Run.
  const admitDefinition = async (submission, requested, resultNames,
    held) => {
    const accepted = await journal.admitOrLookupDefinition(requested, {
      namespaceId, lookupExpiresAt: plus(now(), 7 * 24 * 60 * 60 * 1000),
      resultNames,
      issueDefinition: () => {
        held.plan = planFor(submission);
        return held.plan.runDefinition;
      },
    }, moon, control);
    return accepted;
  };
  // Composition installs one owner for dispatch, cancellation, stop, and
  // cleanup. Checkpoint and HTTP paths share this owner.
  const observed = diagnostic;
  dispatchOwner = installNodeClientDispatchOwner({moon, control,
    journal, store, checkpoints, startRun, hostConnection, beforeDispatch,
    observed, prepareAcquisition, planFor, sourceProfile, registry, values,
    faultInjection: authorization?.faultInjection,
    fragment, ordered, namespaceId, authorityScopeCid, storeAuthorityCid, now});
  const startDispatch = dispatchOwner.start;
  const recoverEffectCapture = (ref, signal) => {
    const retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined || typeof retained.requestId !== 'string') {
      throw new Error('EffectRecoveryRequestMismatch');
    }
    const requestId = retained.requestId;
    return recoverAdmittedEffectRun({requests: journal, store,
      key: {namespaceId, authorityScopeCid, requestId,
        runDefinitionCid: ref.runDefinitionCid}, principalId,
      contractLimits: localContractLimits, signal,
      authorizeEvidenceRead: binding => hostConnection({principalId,
        connection: {mode, owner: mode}, ref}) &&
        binding.namespaceId === namespaceId &&
        binding.authorityScopeCid === authorityScopeCid &&
        binding.requestId === requestId &&
        binding.runDefinitionCid === ref.runDefinitionCid &&
        binding.storeAuthorityCid === storeAuthorityCid},
    async () => moon);
  };
  const effectRun = effectInstallation === undefined ? undefined :
    installNodeClientEffectRun({moon, publicationControl: control, journal,
      now,
      authorizeRequest: async ({principalId: actual, connection}) => {
        if (!hostConnection({principalId: actual, connection})) return null;
        const createdAt = now();
        return Object.freeze({
          executionContextCid: cid({version:
            'actql-installed-effect-execution-context/0.1',
          authorityScopeCid, evidenceCid, principalId: actual}),
          hostPolicyCid: checkpoints?.binding.authorizationContextCid ??
            cid({version: 'actql-installed-effect-missing-policy/0.1',
              authorityScopeCid}),
          createdAt, expiresAt: plus(createdAt, 24 * 60 * 60 * 1000),
        });
      },
      authorizeRunStart: ({principalId: actual, connection, ref}) =>
        hostConnection({principalId: actual, connection, ref}),
      prepareExecution: ({prepared, compilation, allowed, definition}) => {
        const options = {moon, control, prepared,
          compilation, allowed, definition, authorityScopeCid, namespaceId,
          storeAuthorityCid, now};
        return moon.clientProgramEffectPrepareQueryAcquisition(prepared,
          0, 0)?.$tag === 1
          ? acquiredEffectPublicationAdmission(options)
          : sourceFreeEffectPublicationPlan(options);
      },
      execute: facts => dispatchOwner.track(facts.ref, {
        run: ({signal, retainExecution, beginPhysicalWork,
          observePreEffectFailure}) =>
          effectInstallation.execute(
          Object.freeze({...facts, signal, retainExecution,
            beginPhysicalWork, observePreEffectFailure, moon, control,
            publicationPlan: facts.preparedExecution,
            store, storeAuthorityCid, authorityScopeCid,
            observeRun: ({ref}) => observeRun({ref, principalId}),
            openComputation: ({retainComputationOwner} = {}) => {
              if (moon.clientProgramEffectPrepareQueryAcquisition(
                facts.prepared, 0, 0)?.$tag === 1) {
                // Read admission is the installed source's immediate gate.
                // Do not borrow an Effect commit permit or create a read
                // Checkpoint that this Effect profile cannot resume.
                return openAcquiredEffectComputation({moon,
                  owner: facts.owner, acquired: facts.preparedExecution,
                  sourceProfile, registry, values, fragment, ordered,
                  sourceAccess: sourceProfile.sourceAccess, signal, now,
                  retainComputationOwner});
              }
              const setup = moon.clientProgramOpenSourceFreeLocalEffectHost(
                facts.owner, registry, values, 1n, 0n, 0n, 0n);
              if (setup === undefined) {
                throw new Error('InstalledEffectProgramUnsupported');
              }
              return runCapturedEffectComputation(setup, {}, signal).then(
                execution => Object.freeze({execution, checkedHost: setup}));
            },
            recoverCapture: ({signal: recoverySignal} = {}) =>
              recoverEffectCapture(facts.ref, recoverySignal),
            effectAuthorization: checkpoints?.effectAuthorization,
            recordReconciliation: (...args) =>
              effectRun.recordReconciliation(...args)})),
        observeStopped: terminalOutcome => journal.markPhysicalClose(
          facts.ref, terminalOutcome),
        barrierFailureOutcome: 'failed',
      }),
    });
  const runIdOf = accepted => control.runDefinitionRunId(
    accepted.runDefinition?.wire === undefined
      ? journal.lookupRunDefinition(accepted.ref, moon, control).runDefinition
      : accepted.runDefinition);
  const admitEffectDefinition = submission => effectRun.accept({
    prepared: submission.preparedProgram, authorityScopeCid,
    requestId: submission.requestId, namespaceId,
    principalId: submission.principalId, connection: submission.connection,
    lookupExpiresAt: plus(now(), 7 * 24 * 60 * 60 * 1000),
  });
  const submitEffect = async (submission, requested, resultNames) => {
    const {requestId, principalId: actual, connection, kind, input,
      parameters, preparedProgram} = submission;
    // A deferred approval must be answerable by this installed profile.
    // Reject unsupported checked shapes before retaining a Checkpoint.
    effectRun.checkSupported(preparedProgram);
    if (checkpoints?.heldOrigin(requestId)) {
      const existing = journal.resolveDefinition(requested, {namespaceId}, moon,
        control);
      if (existing !== undefined) {
        void checkpoints.sweep();
        return {ref: existing.ref, durability: existing.durability,
          revision: existing.revision};
      }
    }
    if (checkpoints !== undefined &&
        (checkpoints.heldOrigin(requestId) ||
         journal.lookup({namespaceId, authorityScopeCid, requestId}, moon) ===
           undefined)) {
      const requestedFacts = {
        logicalRequestScopeCid: moon.clientRequestScopeCid(requested),
        intentFingerprintCid: moon.clientRequestIntentCid(requested),
      };
      const captured = {version: 'actql-remote-captured-submission/0.1',
        requestId, principalId: actual, connection, kind, input,
        parameters, resultNames};
      const decided = await checkpoints.acceptRun({requested: requestedFacts,
        captured});
      if (decided.kind !== 'dispatch') {
        const existing = journal.lookupDefinition({namespaceId,
          authorityScopeCid, requestId}, moon, control);
        void checkpoints.sweep();
        if (existing !== undefined) {
          return {ref: existing.ref, durability: existing.durability,
            revision: existing.revision};
        }
        if (decided.held === undefined) {
          throw new Error('HeldRunDefinitionMissing');
        }
        return decided.held;
      }
    }
    const accepted = await admitEffectDefinition(submission);
    // The durable accepted Ref is returned before physical work settles.
    // Its start claim cannot be reset by a lost response or a second submit.
    void effectRun.start(accepted).catch(error => {
      diagnostic('effect_start_failed', {ref: accepted.ref,
        code: error?.code ?? error?.message});
    }).finally(() => settleHeldRun(accepted, runIdOf(accepted)))
      .catch(error => diagnostic('effect_settlement_failed', {
        ref: accepted.ref, code: error?.code ?? error?.message}));
    return {ref: accepted.ref, durability: accepted.durability,
      revision: accepted.revision};
  };
  const submit = async submission => {
    const {requestId, principalId: actual, connection, kind, input,
      parameters} = submission;
    if (!hostConnection({principalId: actual, connection})) {
      throw new Error('ClientConnectionDenied');
    }
    const {requested, resultNames, acquired, effectful} =
      requestOf(submission);
    if (effectful) {
      return submitEffect(submission, requested, resultNames);
    }
    const preparedSource = acquired
      ? await prepareAcquisition(submission.preparedProgram) : undefined;
    // Run acceptance on the protected Site is decided before any Run
    // Definition exists. A request that was held is never started from here:
    // submitting it again returns its held state, or its existing Run, and
    // only wakes the durable resume owner, which starts it under the resumed
    // authorization. Other admitted requests are looked up, not decided
    // again.
    // A held request whose Run exists is compared with the request
    // journal's own identity (no side effect): another intent conflicts,
    // whatever the state of the held evidence.
    if (checkpoints?.heldOrigin(requestId)) {
      const existing = journal.resolveDefinition(requested, {namespaceId}, moon,
        control);
      if (existing !== undefined) {
        void checkpoints.sweep();
        return {ref: existing.ref, durability: existing.durability,
          revision: existing.revision};
      }
    }
    if (checkpoints !== undefined &&
        (checkpoints.heldOrigin(requestId) ||
         journal.lookup({namespaceId, authorityScopeCid, requestId}, moon) ===
           undefined)) {
      const requestedFacts = {
        logicalRequestScopeCid: moon.clientRequestScopeCid(requested),
        intentFingerprintCid: moon.clientRequestIntentCid(requested),
      };
      const captured = {version: 'actql-remote-captured-submission/0.1',
        requestId, principalId: actual, connection, kind, input,
        parameters, resultNames,
        ...(preparedSource === undefined ? {} : {acquisition: {
          checkedSource: preparedSource.checkedSource,
          readTuple: preparedSource.readTuple,
          physicalBinding: preparedSource.physicalBinding}})};
      let decided = await checkpoints.acceptRun({requested: requestedFacts,
        captured});
      // Run acceptance allowed or permitted: a Program that reads the
      // installed source has its read decided before any Run exists.
      if (decided.kind === 'dispatch') {
        decided = await checkpoints.acceptAcquisition({
          requested: requestedFacts, captured});
      }
      if (decided.kind !== 'dispatch') {
        const existing = journal.lookupDefinition({namespaceId,
          authorityScopeCid, requestId}, moon, control);
        void checkpoints.sweep();
        if (existing === undefined) {
          if (decided.held === undefined) {
            throw new Error('HeldRunDefinitionMissing');
          }
          return decided.held;
        }
        return {ref: existing.ref, durability: existing.durability,
          revision: existing.revision};
      }
    }
    const held = {preparedSource,
      preparedSourceAccess: sourceProfile?.sourceAccess};
    const accepted = await admitDefinition(submission, requested,
      resultNames, held);
    // A resumed request's journal Run (if any) ends with its dispatch.
    startDispatch(submission, requested, accepted, held,
      checkpoints === undefined ? undefined : status =>
        settleHeldRun(accepted, runIdOf(accepted)));
    return {ref: accepted.ref, durability: accepted.durability,
      revision: accepted.revision};
  };
  // Continue one approved held request (called by the Checkpoint sweep with
  // the captured submission and the claim's admission). The admission is
  // entered synchronously immediately before the Run Definition is
  // admitted; the resume intent completes with the created Run.
  const heldSubmission = async captured => {
    const submission = {principalId: captured.principalId,
      connection: captured.connection, requestId: captured.requestId,
      kind: captured.kind, input: captured.input,
      parameters: captured.parameters};
    submission.preparedProgram = await prepareSubmit(submission);
    const {requested, resultNames, acquired, effectful} =
      requestOf(submission);
    const preparedSource = acquired
      ? await prepareAcquisition(submission.preparedProgram) : undefined;
    const acquisition = preparedSource === undefined ? undefined : {
      checkedSource: preparedSource.checkedSource,
      readTuple: preparedSource.readTuple,
      physicalBinding: preparedSource.physicalBinding};
    // Compared as canonical JSON: the held submission is stored in its
    // canonical form, so key order carries no meaning here.
    if (canonicalJson(acquisition ?? null) !==
        canonicalJson(captured.acquisition ?? null)) {
      throw new Error('HeldAcquisitionChanged');
    }
    if (JSON.stringify(resultNames) !==
        JSON.stringify(captured.resultNames)) {
      throw new Error('HeldRequestChanged');
    }
    return {submission, requested, resultNames, preparedSource, effectful};
  };
  const definitionOf = captured => journal.lookupDefinition({namespaceId,
    authorityScopeCid, requestId: captured.requestId}, moon, control);
  const terminal = status => ['succeeded', 'failed', 'cancelled']
    .includes(status);
  // Recover only from the accepted Run and the committed publication owner.
  // A reserved start without an available publication cannot be treated as
  // an unstarted read or reconstructed by fetching the source again.
  const inspectAcquisition = async ({requestId, principalId: actual,
    connection}) => {
    if (sourceProfile === undefined ||
        !hostConnection({principalId: actual, connection})) {
      throw new Error('AcquisitionInspectionDenied');
    }
    const accepted = journal.lookupDefinition({namespaceId,
      authorityScopeCid, requestId}, moon, control);
    if (accepted === undefined || accepted.physicalStartReserved !== true) {
      return {state: 'not_started'};
    }
    const current = await observeRun({ref: accepted.ref,
      principalId: actual});
    const availability = Object.values(current.result_availability);
    if (current.status === 'succeeded' && availability.length > 0 &&
        availability.every(result => result.state === 'available')) {
      return {state: 'completed_retained', ref: accepted.ref,
        resultNames: Object.keys(current.result_availability)};
    }
    return {state: 'started_unknown', ref: accepted.ref};
  };
  // The physical state of a held request's Run: `absent` (no Run
  // Definition yet), `unstarted` (no physical start reserved), `cancelled`
  // (cancelled before any physical start), `abandoned` (failed before
  // dispatch), `started` (reserved: running, or unknown after a crash) or
  // `terminal`.
  const inspectHeld = async captured => {
    const acquisition = captured.acquisition === undefined ? undefined :
      await inspectAcquisition({requestId: captured.requestId,
        principalId: captured.principalId, connection: captured.connection});
    const accepted = definitionOf(captured);
    if (accepted === undefined) return {state: 'absent', acquisition};
    const runId = runIdOf(accepted);
    if (accepted.preDispatchFailureConfirmed) {
      return {state: 'abandoned', runId, acquisition};
    }
    if (accepted.physicalStartReserved !== true) {
      // A Run cancelled before any physical start is terminal, not
      // resumable: its public state is the Run's own projection.
      if (accepted.cancellationRequested) {
        const current = await observeRun({ref: accepted.ref, principalId});
        if (current.status === 'cancelled') {
          return {state: 'cancelled', runId, acquisition};
        }
      }
      return {state: 'unstarted', runId, acquisition};
    }
    const current = await observeRun({ref: accepted.ref, principalId});
    return terminal(current.status)
      ? {state: 'terminal', runId, status: current.status, acquisition}
      : {state: 'started', runId, status: current.status, acquisition};
  };
  // After a held request's dispatch ends, its journal Run ends only with the
  // Run's observed terminal state; a Run whose physical stop is unknown (for
  // example after a cancel) stays with its owners and is observed again by
  // the sweep. Nothing is inferred from how the dispatch returned.
  const settleHeldRun = async (accepted, runId) => {
    let status;
    try {
      status = (await observeRun({ref: accepted.ref, principalId})).status;
    } catch {}
    if (terminal(status)) checkpoints.runFinished(runId, status);
    else void checkpoints.sweep();
  };
  // Continue one approved held request whose physical start is not
  // reserved. The Run Definition is admitted (or looked up); the common
  // resumed admission is entered synchronously immediately before the
  // physical start reservation, and the resume intent completes with the
  // Run right after it. Resolves with 'started', {refused} or 'not_started'.
  // The Run cancellation of a held request's defined Run (the Host itself
  // applies a durable request cancellation to its Run).
  const cancelHeldRun = async captured => {
    const accepted = definitionOf(captured);
    if (accepted === undefined) return;
    const publicationCommitted =
      await store.confirmCommittedIndex(accepted.ref) !== undefined;
    const result = journal.requestCancellation(accepted.ref, {
      currentAuthorization: true, publicationCommitted}, moon, control);
    if (result.kind !== 'already_terminal') {
      dispatchOwner.cancel(accepted.ref);
    }
  };
  const resumeHeld = async ({captured, beforePhysicalStart, started,
    step, renew, preparationCancelled}) => {
    // A request whose physical target or result inventory differs from the
    // one held is refused before anything is admitted or read: the earlier
    // approval does not cover it.
    let resolved;
    try { resolved = await heldSubmission(captured); }
    catch (error) {
      if (['HeldAcquisitionChanged', 'HeldRequestChanged']
        .includes(error?.message)) {
        return {refused: Object.assign(error, {code: error.message})};
      }
      throw error;
    }
    const {submission, requested, resultNames, preparedSource,
      effectful} = resolved;
    if (effectful) {
      effectRun.checkSupported(submission.preparedProgram);
      const accepted = await admitEffectDefinition(submission);
      await step('definition_admitted', {ref: accepted.ref});
      try { renew(); }
      catch (error) { return {refused: error}; }
      if (preparationCancelled()) {
        await cancelHeldRun(captured);
        return 'not_started';
      }
      if (definitionOf(captured)?.cancellationRequested) {
        return 'not_started';
      }
      const runId = runIdOf(accepted);
      let settle;
      const observedStart = new Promise(resolve => { settle = resolve; });
      let startObserved = false;
      const flight = effectRun.start(accepted, {
        beforePhysicalStart,
        started() {
          startObserved = true;
          try { started(runId); }
          finally { settle('started'); }
        },
      });
      void flight.then(result => {
        if (!startObserved) {
          settle(result.kind === 'started' ? 'started' : 'not_started');
        }
      }, error => {
        if (!startObserved) settle({refused: error});
        diagnostic('effect_start_failed', {ref: accepted.ref,
          code: error?.code ?? error?.message});
      }).finally(() => settleHeldRun(accepted, runId))
        .catch(error => diagnostic('effect_settlement_failed', {
          ref: accepted.ref, code: error?.code ?? error?.message}));
      return observedStart;
    }
    const held = {preparedSource,
      preparedSourceAccess: sourceProfile?.sourceAccess};
    const accepted = await admitDefinition(submission, requested,
      resultNames, held);
    await step('definition_admitted', {ref: accepted.ref});
    try { renew(); }
    catch (error) { return {refused: error}; }
    // A request cancellation recorded meanwhile (even before this Run
    // existed) is applied to the Run now; a Run cancellation is read from
    // the journal, not from the admitted snapshot. Either way the Run is not
    // dispatched.
    if (preparationCancelled()) {
      await cancelHeldRun(captured);
      return 'not_started';
    }
    if (definitionOf(captured)?.cancellationRequested) return 'not_started';
    const runId = runIdOf(accepted);
    return startDispatch(submission, requested, accepted, held,
      () => settleHeldRun(accepted, runId),
      {beforePhysicalStart, started: () => started(runId)});
  };
  // A held request whose authorization no longer holds before any physical
  // start: its Run (if already defined) fails before dispatch; nothing runs.
  const abandonHeld = async captured => {
    const accepted = definitionOf(captured);
    if (accepted === undefined || accepted.physicalStartReserved === true ||
        accepted.preDispatchFailureConfirmed) return;
    if (accepted.dispatchReserved !== true) {
      const start = await startRun({identity: (await heldSubmission(
        captured)).requested, namespaceId, principalId: captured.principalId,
      connection: captured.connection});
      if (start.kind !== 'reserved' && start.kind !== 'reconcile') return;
    }
    journal.markPreDispatchFailure(accepted.ref);
  };
  // A Run whose physical start is reserved is only observed: a terminal Run
  // ends its journal Run; an unknown one is never sent again.
  const observeHeldRun = async ({captured}) => {
    const accepted = definitionOf(captured);
    if (accepted === undefined) throw new Error('HeldRunDefinitionMissing');
    return (await observeRun({ref: accepted.ref, principalId})).status;
  };
  const negotiate = () => ({version: 'actql-client-host/0.1',
    mode, owner: mode, durability: 'durable', scopeRef: principalId,
    capabilities: ['result-jsonl'], limits: {
      maxReadWireBytes: 10 * 1024 * 1024,
      maxRowWireBytes: 1024 * 1024,
      maxRowRetainedValueBytes: 1024 * 1024,
      maxRetainedValueBytes: 10 * 1024 * 1024,
      maxRows: 10000, maxBatchRows: 1000,
      maxBatchRetainedValueBytes: 10 * 1024 * 1024,
    }});
  // A held request is looked up through the Checkpoint journal until its Run
  // exists; then the request journal answers with its RunRef.
  const lookupHeld = async value => {
    const found = await lookupRequest(value);
    if (checkpoints === undefined || found.kind !== 'not_found') return found;
    if (authorizedScope(value) === undefined) return found;
    return checkpoints.heldLookup(value.requestId) ?? found;
  };
  const checkpointOperations = checkpoints === undefined ? {} : {
    checkpoints: ({principalId: actual, after, limit}) =>
      checkpoints.listCheckpoints({principalId: actual, after, limit}),
    checkpointReview: ({principalId: actual, checkpointCid, maxBytes,
      signal}) => checkpoints.reviewCheckpoint({principalId: actual,
      checkpointCid, maxBytes, signal}),
    resolve: ({principalId: actual, items}) =>
      checkpoints.resolve({principalId: actual, items}),
  };
  const checkpointOperation = new Set(['checkpoints', 'checkpoint-review',
    'resolve']);
  // Reviewers and review readers may connect and use only the Checkpoint
  // operations; every Run operation still requires the owner.
  const checkpointConnection = value => checkpoints !== undefined &&
    value.ref === undefined && value.connection.mode === mode &&
    value.connection.owner === mode &&
    checkpoints.admitsCheckpointPrincipal(value.principalId);
  const effectResumeFlights = new Map();
  const effectRetirementFlights = new Map();
  const retiredEffectCaptures = new Set();
  const retireEffectCapture = ref => {
    const key = ref.runDefinitionCid;
    if (retiredEffectCaptures.has(key)) return Promise.resolve(false);
    const existing = effectRetirementFlights.get(key);
    if (existing !== undefined) return existing;
    const flight = (async () => {
      if (dispatchOwner.operation(ref) !== undefined) {
        throw new Error('EffectCaptureExecutionStillOwned');
      }
      if (await store.confirmCommittedIndex(ref) !== undefined) {
        retiredEffectCaptures.add(key);
        return false;
      }
      const retained = journal.lookupRunDefinition(ref, moon, control);
      if (retained?.runDefinition?.identity !== key) {
        throw new Error('EffectRetirementRunDefinitionMissing');
      }
      const result = await retireCompletedEffectfulCapture({store, control,
        runDefinition: retained.runDefinition,
        contractLimits: localContractLimits});
      retiredEffectCaptures.add(key);
      return result;
    })().finally(() => {
      if (effectRetirementFlights.get(key) === flight) {
        effectRetirementFlights.delete(key);
      }
    });
    effectRetirementFlights.set(key, flight);
    return flight;
  };
  const retireIncompleteEffects = async () => {
    const failures = [];
    let after = '';
    for (;;) {
      const page = await store.listEffectCaptureCustodies({after, limit: 100});
      for (const run of page) {
        const ref = Object.freeze({namespaceId, authorityScopeCid,
          runDefinitionCid: run.identity});
        try {
          // Cleanup discovery is not a new start claim. A live invocation
          // still owns its preparation; only absent local owners are eligible.
          if (dispatchOwner.operation(ref) !== undefined ||
              effectResumeFlights.has(run.identity)) continue;
          const retained = journal.lookupRunDefinition(ref, moon, control);
          if (retained === undefined) continue; // Another authority scope.
          if (retained.runDefinition.wire !== run.wire) {
            throw new Error('EffectCaptureCustodyRunMismatch');
          }
          const runId = control.runDefinitionRunId(run);
          // Durable custody still exists only before transfer to a Checkpoint
          // or physical dispatch. A complete private record is not sufficient
          // to establish that transfer. The original unknown Run stays intact.
          if (checkpoints.journal.inspect(`${runId}-effect-commit`) !== undefined) continue;
          await retireEffectCapture(ref);
        } catch (error) { failures.push(error); }
      }
      if (page.length < 100) break;
      after = page.at(-1).identity;
    }
    if (failures.length > 0) {
      throw new AggregateError(failures, 'EffectCaptureCleanupPending');
    }
  };
  const retireTerminalEffects = async () => {
    if (effectRun === undefined || checkpoints === undefined) return;
    let after = '';
    const failures = [];
    try { await retireIncompleteEffects(); }
    catch (error) { failures.push(error); }
    for (;;) {
      const page = checkpoints.journal.listRunCheckpoints({after, limit: 100});
      for (const view of page) {
        if (view.kind !== 'effect_set' || view.prepareAttemptId !== null ||
            !['failed', 'cancelled'].includes(
              checkpoints.journal.getRunState(view.runId)?.status)) continue;
        const ref = Object.freeze({namespaceId, authorityScopeCid,
          runDefinitionCid: view.runDefinitionCid});
        try { await retireEffectCapture(ref); }
        catch (error) { failures.push(error); }
      }
      if (page.length < 100) break;
      after = page.at(-1).checkpointCid;
    }
    if (failures.length > 0) {
      throw new AggregateError(failures, 'EffectCaptureCleanupPending');
    }
  };
  const sweepEffectRuns = async () => {
    if (effectRun === undefined || checkpoints === undefined) return false;
    let busy = false;
    try { await retireIncompleteEffects(); }
    catch (error) {
      busy = true;
      diagnostic('effect_capture_retirement_failed', {
        code: error?.code ?? error?.message});
    }
    let after = '';
    for (;;) {
      const page = checkpoints.journal.listRunCheckpoints({after, limit: 100});
      for (const view of page) {
        if (view.kind !== 'effect_set' || view.prepareAttemptId !== null) {
          continue;
        }
        const key = view.runDefinitionCid;
        const ref = Object.freeze({namespaceId, authorityScopeCid,
          runDefinitionCid: key});
        if (cancelEffectContinuation(ref)) {
          busy = true;
        }
        const runStatus = checkpoints.journal.getRunState(view.runId)?.status;
        if (runStatus === 'failed' || runStatus === 'cancelled') {
          try { await retireEffectCapture(ref); }
          catch (error) {
            busy = true;
            diagnostic('effect_capture_retirement_failed', {ref,
              code: error?.code ?? error?.message});
          }
          continue;
        }
        if (runStatus !== 'resuming') continue;
        if (effectResumeFlights.has(key) ||
            dispatchOwner.operation(ref) !== undefined) {
          busy = true;
          continue;
        }
        try {
          const retained = journal.lookupRunDefinition(ref, moon, control);
          if (retained === undefined ||
              retained.runDefinition.identity !== key) {
            throw new Error('EffectResumeRunDefinitionMissing');
          }
          const continuation = await checkpoints.effectContinuation(view);
          const flight = dispatchOwner.track(ref, {
            run: ({signal, retainExecution, beginPhysicalWork}) =>
              effectInstallation.resume(Object.freeze({ref, view,
                continuation, retained, moon, control, store,
                storeAuthorityCid, authorityScopeCid, signal,
                retainExecution, beginPhysicalWork,
                observeRun: ({ref}) => observeRun({ref, principalId}),
                recoverCapture: ({signal: recoverySignal} = {}) =>
                  recoverEffectCapture(ref, recoverySignal),
                checkpointJournal: checkpoints.journal,
                checkpointBinding: checkpoints.binding,
                effectAuthorization: checkpoints.effectAuthorization,
                recordReconciliation: (...args) =>
                  effectRun.recordReconciliation(...args)})),
            // The original Compute stopped before the Effect Checkpoint.
            // Its nonterminal stop observation is immutable. Effect failure
            // and reconciliation belong to the Checkpoint and Effect owners.
            observeStopped: () => journal.markPhysicalClose(ref, null),
          });
          effectResumeFlights.set(key, flight);
          void flight.catch(error => {
            diagnostic('effect_resume_failed', {ref,
              code: error?.code ?? error?.message});
          }).finally(() => {
            effectResumeFlights.delete(key);
            if (checkpoints.journal.getRunState(view.runId)?.status !==
                'resuming') {
              void checkpoints.sweep();
            }
          });
        } catch (error) {
          diagnostic('effect_resume_failed', {ref,
            code: error?.code ?? error?.message});
        }
        busy = true;
      }
      if (page.length < 100) break;
      after = page.at(-1).checkpointCid;
    }
    return busy;
  };
  const hostOperations = {
    observe: observed,
    authorizeConnection: value => checkpointOperation.has(value.operation)
      ? checkpointConnection(value)
      : hostConnection(value) || value.operation === 'connect' &&
        checkpointConnection(value),
    negotiate, prepareSubmit, submit, attach, lookupRequest: lookupHeld,
    stateService, resultService, observeRun, wait, cancel, cancelRequest,
    ...checkpointOperations,
    // Discovery of the installed source, when its adapter serves it.
    ...(sourceProfile?.discovery ?? {}),
  };
  if (checkpoints !== undefined) {
    await checkpoints.start({inspect: inspectHeld, resume: resumeHeld,
      abandon: abandonHeld, observe: observeHeldRun,
      cancelRun: cancelHeldRun,
      effects: effectRun === undefined ? undefined :
        {sweep: sweepEffectRuns}});
  }
  const port = createNodeInProcessClientHost({
    authenticate: () => principalId,
    ...hostOperations, maxRowBytes: 1024 * 1024,
  });
  return {port, store, journal, hostOperations, checkpoints, diagnostic,
    dispatchOwner, inspectAcquisition, sourceProfile, installedEffect,
    retireTerminalEffects};
  } catch (cause) {
    diagnostic?.close();
    effectEvidenceKey?.key.fill(0);
    throw await retainInstalledHostInitializationFailure(cause,
      {journal, store, checkpoints, dispatchOwner,
        sourceProfile, installedEffect});
  }
}

// This HTTP ingress uses the installed Host's common owner and physical
// services. Embedded Local continues to use the in-process port above.
//
// `authorization` installs Run-acceptance protection for the Host's Site:
// {accountConfig | accountConfiguration, reviewers: [{keyId, reviewerId,
// principalId, publicKey}], reviewReaders: [principal], hostKey: {keyId,
// privateKey}, siteKey?, decide?, answeringAuthorities?, checkpointTtlMs?,
// leaseMs?, maxReviewBytes?, resumeAfterAnswer?, sweepPage?, observe?,
// faultInjection?}.
// Approved requests are resumed at Host start and, unless
// `resumeAfterAnswer` is false, after an answer is stored; each sweep step
// handles at most `sweepPage` items and continues until none remain.
// `observe(step, detail)` is bounded best-effort diagnostics and cannot stop
// execution. `faultInjection(step, detail)` is an explicit awaited test hook;
// `beforeDispatch` remains a required execution barrier. Without a
// configuration the Missing account denies every request; nothing allows it.
export async function openInstalledRemoteHttpHost({directory,
  authenticate, beforeDispatch, authorization, sourceProfilePath,
  resolveSourceSecret, effectProfilePath, resolveEffectSecret,
  effectInstallation}) {
  if (typeof directory !== 'string' || !directory ||
      typeof authenticate !== 'function' ||
      beforeDispatch !== undefined && typeof beforeDispatch !== 'function') {
    throw new TypeError('InvalidInstalledRemoteHost');
  }
  const host = await openInstalledHost({root: resolve(directory), mode: 'remote',
    beforeDispatch, authorization, sourceProfilePath, resolveSourceSecret,
    effectProfilePath, resolveEffectSecret, effectInstallation});
  const handle = createClientHttpHandler({
    ...host.hostOperations, authenticate, maxRequestBytes: 65536,
  });
  // A request's handling can outlive its response: a Result read records
  // its delivery attempt after the last bytes are sent. Close waits for
  // every request still being handled; once closing, new requests are
  // refused before they touch the Store.
  const handling = new Set();
  let closing = false;
  const shutdown = createInstalledHostShutdown({
    stop: () => host.checkpoints?.stop(),
    drain: () => host.dispatchOwner.drain(),
    retire: () => host.retireTerminalEffects(),
    checkpoint: () => host.checkpoints?.close(),
    journal: () => host.journal.close(),
    source: () => host.sourceProfile?.close(),
    effect: () => host.installedEffect?.close(),
    store: () => host.store.close(),
  });
  return Object.freeze({
    handler(request, response) {
      if (closing) {
        response.writeHead(503, {'content-type': 'application/json'});
        response.end(JSON.stringify({code: 'ClientHostClosing'}));
        return Promise.resolve();
      }
      const handled = Promise.resolve(handle(request, response));
      handling.add(handled);
      handled.finally(() => handling.delete(handled)).catch(() => {});
      return handled;
    },
    inspectAcquisition: host.inspectAcquisition,
    // Stop accepting requests and wait for those being handled, stop
    // starting resumes, let running dispatches finish and record their
    // ends, settle retention, then release the journals and the Store
    // owner. Returns what remains for the next owner instead of hiding it.
    async close() {
      closing = true;
      host.diagnostic.close();
      while (handling.size > 0) {
        await Promise.allSettled([...handling]);
      }
      const result = await shutdown.close();
      return Object.freeze({...result,
        diagnosticDeliveryPending: host.diagnostic.status().active !== 0});
    },
  });
}

// Publish the installed source's declaration for a Host state directory
// (the embedded Local Host's by default) from its source profile
// (`ACTQL_LOCAL_SOURCE_PROFILE` by default). This is the explicit step a Host
// start restores without provider I/O.
export async function publishInstalledSource({sourceProfilePath, directory,
  resolveSourceSecret, signal} = {}) {
  const root = directory === undefined ? localStateRoot() : resolve(directory);
  await admitHostRootFormat(root);
  const moon = await import(runtimeUrl.href);
  return publishInstalledSourceProfile(
    sourceProfilePath ?? process.env.ACTQL_LOCAL_SOURCE_PROFILE, {root,
      principalId: userInfo().username, moon, runtimeUrl,
      resolveSecret: resolveSourceSecret, signal});
}

// Publish the installed Effect's generation (its declaration, execution
// Mappings and Check Environment) for a Host state directory (the embedded
// Local Host's by default) from its Effect profile
// (`ACTQL_LOCAL_EFFECT_PROFILE` by default). This is the explicit step a Host
// start restores without provider I/O.
export async function publishInstalledEffect({effectProfilePath, directory,
  resolveEffectSecret, signal} = {}) {
  const root = directory === undefined ? localStateRoot() : resolve(directory);
  await admitHostRootFormat(root);
  const moon = await import(runtimeUrl.href);
  const baseEnvironmentWire = (await readFile(join(packageRoot,
    'spec/local-check-environment.json'), 'utf8')).trimEnd();
  return publishInstalledEffectProfile(
    effectProfilePath ?? process.env.ACTQL_LOCAL_EFFECT_PROFILE, {root,
      principalId: userInfo().username, moon, runtimeUrl,
      baseEnvironmentWire, resolveSecret: resolveEffectSecret, signal});
}

export async function connectEmbeddedLocal(options) {
  const installation = options?.installation;
  if (installation !== undefined && (installation === null ||
      typeof installation !== 'object' || Array.isArray(installation))) {
    throw new TypeError('InvalidInstalledHostOptions');
  }
  const root = installation?.directory === undefined ? localStateRoot() :
    resolve(installation.directory);
  const identity = await embeddedInstallationIdentity(root, installation);
  let opened = profiles.get(root);
  if (opened === undefined) {
    opened = Object.freeze({identity,
      host: openInstalledHost({root, authorization: installation?.authorization,
        sourceProfilePath: installation?.sourceProfilePath,
        resolveSourceSecret: installation?.resolveSourceSecret,
        effectProfilePath: installation?.effectProfilePath,
        resolveEffectSecret: installation?.resolveEffectSecret})});
    profiles.set(root, opened);
    opened.host.catch(() => {
      if (profiles.get(root) === opened) profiles.delete(root);
    });
  } else if (!sameEmbeddedInstallation(opened.identity, identity)) {
    throw new TypeError('InstalledHostConfigurationMismatch');
  }
  const host = await opened.host;
  const {installation: _installation, ...clientOptions} = options;
  return connectInProcess(clientOptions, host.port);
}
