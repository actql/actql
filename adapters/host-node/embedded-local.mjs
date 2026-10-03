// One installed Local Host for the current OS user. The Client talks to the
// Host in process; the journal and publication Store own durable physical I/O.
import {ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {createHash, createPublicKey, randomBytes} from 'node:crypto';
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
import {capturedDuckDBNativeConfiguration} from './captured-duckdb-source.mjs';
import {recoverAdmittedEffectRun} from './effect-run-recovery.mjs';
import {retireCompletedEffectfulCapture} from
  '../host-common/completed-run-publication.mjs';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';
import {installedModelEnvironment, readInstalledModelExecution,
  readInstalledModelDependencies, installModelProviders,
  admitInstalledModelProvider, observeInstalledModelAccount} from
  './installed-model.mjs';
import {installNodeInferRun} from './installed-infer-run.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {issueInstalledRunControlObservation,
  issueInstalledUnpublishedRunState} from
  '../host-common/run-state-observation.mjs';
import {installedEffectIdentity, loadInstalledEffect,
  publishInstalledEffectProfile} from
  './installed-effect.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey} from
  './local-continuation-evidence.mjs';
import {installedSourceIdentity, installedSourcePaths, loadInstalledSources, installedSourceFor,
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
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {installLocalSnapshotStore} from '../local-node/retained-store.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {localContractLimits, localOutputLimits,
  sourceFreeValuesPlan, sourceFreeTaskPlan,
  sourceFreeEffectPublicationPlan, acquiredEffectPublicationAdmission,
  acquiredTaskRunAdmission, inferTaskRunAdmission} from
  './local-values-plan.mjs';

const packageRoot = fileURLToPath(new URL('../../', import.meta.url));
const runtimeUrl = new URL('../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const now = () => new Date().toISOString();
const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const plus = (date, milliseconds) => new Date(Date.parse(date) +
  milliseconds).toISOString();
const clientOperationError = (code, cause) => Object.assign(
  new Error(code, cause === undefined ? undefined : {cause}), {code});
const profiles = new Map();

const bytesCid = bytes => `sha256:${createHash('sha256')
  .update(bytes).digest('hex')}`;
const publicKeyCid = value => bytesCid(createPublicKey(value).export({
  type: 'spki', format: 'der'}));

async function embeddedInstallationIdentity(root, installation) {
  const sourcePaths = installedSourcePaths(installation);
  const effectPath = installation?.effectProfilePath ??
    process.env.ACTQL_LOCAL_EFFECT_PROFILE;
  const identities = await Promise.all(sourcePaths.map(installedSourceIdentity));
  const source = identities.length === 0 ? null : identities.length === 1
    ? identities[0] : {version: 'actql-installed-source-inventory/0.1', identities};
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
    ...(installation?.modelInstallation === undefined ? {} : {
      modelEnvironment: installation.modelInstallation}),
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
    registerModelProviders: installation?.registerModelProviders,
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
  authorization, sourceProfilePath, sourceProfilePaths, resolveSourceSecret,
  effectProfilePath, resolveEffectSecret, effectInstallation,
  modelInstallation, registerModelProviders}) {
  const selectedSourcePaths = installedSourcePaths({sourceProfilePath, sourceProfilePaths});
  const selectedEffectPath = effectProfilePath ??
    process.env.ACTQL_LOCAL_EFFECT_PROFILE;
  if (effectInstallation !== undefined && selectedEffectPath !== undefined) {
    throw new TypeError('InvalidInstalledEffectSite');
  }
  await admitHostRootFormat(root);
  const moon = await import(runtimeUrl.href);
  const control = runtimeCore(moon).publicationControl;
  const modelProviders = installModelProviders(moon, registerModelProviders);
  const inferSelections = new WeakMap();
  const principalId = userInfo().username;
  const baseEnvironmentWire = (await readFile(join(packageRoot,
    'spec/local-check-environment.json'), 'utf8')).trimEnd();
  // Both adapters restore published declarations without provider I/O. The
  // combined environment is admitted before either can dispatch work.
  let sourceProfile;
  let installedEffect;
  let environmentWire;
  try {
    sourceProfile = await loadInstalledSources(selectedSourcePaths,
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
    environmentWire = installedModelEnvironment(moon, baseEnvironmentWire,
      environmentWire, modelInstallation);
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
  let sourcePublication;
  try {
    evidenceCid = JSON.parse(environmentWire).evidence_bundle_cid;
    const numericProfile = JSON.parse(await readFile(join(packageRoot,
      'spec/contracts/actql-numeric-reduction.json'), 'utf8'));
    const numericProfileCid = `sha256:${createHash('sha256')
      .update(canonicalJson(numericProfile)).digest('hex')}`;
    const propertyGraphLaw = JSON.parse(await readFile(join(packageRoot,
      'spec/dependencies/actql-property-graph-laws.json'), 'utf8'));
    environment = moon.clientProgramCheckEnvironmentWithPropertyGraphProfile(
      environmentWire, evidenceCid, false, false, true, true, false, false,
      false, numericProfileCid, contentCid(propertyGraphLaw));
    if (environment !== undefined) {
      sourcePublication = sourceAliasPublication(moon, environment,
        sourceProfile?.queryAliases ?? []);
    }
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
  let localSnapshotConfiguration;
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
    const snapshotDirectory = join(root, 'carrier-snapshots');
    await mkdir(snapshotDirectory, {recursive:true,mode:0o700});
    // Installed physical wiring, never Program settings. Allocation occurs
    // only after the common driver has reserved work/capacity and captured
    // the snapshot cleanup owner. Relation execution remains memory-backed.
    localSnapshotConfiguration = installLocalSnapshotStore((_key, bytes, frame) =>
      createLocalRetainedStore({parentDirectory:snapshotDirectory,
        capacityBytes:bytes,maxFrameBytes:frame,maxEntries:1}));
    journal = openClientRequestJournal(journalDirectory);
    if ((effectInstallation !== undefined || modelInstallation !== undefined) &&
        effectInstallation?.privateEvidenceKey === undefined) {
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
      ...(effectInstallation === undefined && modelInstallation === undefined ? {} : {
        privateEvidenceKey: effectInstallation?.privateEvidenceKey ??
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
    authorizeResultDescription: ({principalId: actual}) =>
      actual === principalId,
    admitResultDescription: ({attemptId}) => ({
      authorizationContextCid: cid({version: 'actql-local-read/0.1',
        attemptId}),
      dataCeilingCid: cid({version: 'actql-local-read-ceiling/0.1'}),
      egressAdmissionCid: cid({version: 'actql-local-egress/0.1'}),
      expiresAt: plus(now(), 60 * 60 * 1000),
      maxBytes: localOutputLimits.maxWireBytes, maxUses: 1,
    }),
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
    environment, sourcePublication,
    allowEffects: effectInstallation !== undefined});
  const checkSource = installNodeClientCheck({moon, environment,
    publication: sourcePublication,
    sourceAccesses: (sourceProfile?.sources ??
      (sourceProfile === undefined ? [] : [sourceProfile]))
      .map(source => source.sourceAccess)});
  // Checking dispatches nothing and reads no source rows; the audience is
  // the authenticated caller this connection admits.
  const check = async ({principalId: actual, connection, input, parameters,
    signal}) => {
    if (!hostConnection({principalId: actual, connection})) {
      throw clientOperationError('ClientConnectionDenied');
    }
    return checkSource({principalId: actual, input, parameters, signal});
  };
    checkpoints = await installRemoteCheckpoints({root, namespaceId,
      authorityScopeCid, ownerPrincipal: principalId,
      siteKey: authorization?.siteKey ?? 'actql-remote-host',
      realizationKey: sourceProfile?.realizationKey ?? REALIZATION_KEY,
      environmentCid: evidenceCid,
      contractControl: control,
      authorization: authorization == null ? authorization :
        {...authorization, observe: diagnostic},
      ...(sourceProfile?.sources === undefined
        ? {source: sourceProfile?.readAuthorization}
        : {sources: sourceProfile.sources.map(source => ({
          sourceRef: source.sourceAccess.sourceRef, ...source.readAuthorization}))})});
  const observeRun = async ({ref, principalId: actual}) => {
    if (actual !== principalId || ref.namespaceId !== namespaceId ||
        ref.authorityScopeCid !== authorityScopeCid) {
      throw clientOperationError('RunStateAccessDenied');
    }
    // Recheck the journal revision after asynchronous Store observation so
    // control facts never combine observations from two journal revisions.
    for (let attempt = 0; attempt < 8; attempt++) {
      const retained = journal.lookupRunDefinition(ref, moon, control);
      if (retained === undefined) {
        throw clientOperationError('RunStateAccessDenied');
      }
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
          state = issueInstalledUnpublishedRunState(moon, {
            runId, observedAt: now(), resultNames: retained.resultNames,
            dispatchReserved: retained.dispatchReserved,
            preDispatchFailureConfirmed:
              retained.preDispatchFailureConfirmed,
            cancelledBeforeStart: retained.cancellationRequested &&
              retained.physicalStartReserved === false,
            observedTerminalOutcome:
              retained.observedTerminalOutcome ?? 'none',
            executionUnknown,
          });
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
      const observation = issueInstalledRunControlObservation(moon, {
        revision: retained.revision,
        cancellationRequested: retained.cancellationRequested,
        physicallyUnstarted: retained.physicalStartReserved === false,
        preDispatchFailureConfirmed: retained.preDispatchFailureConfirmed,
        physicalCloseConfirmed: retained.physicalCloseConfirmed,
      });
      return {...state, control: observation};
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
      throw clientOperationError('ClientRunCancellationDenied');
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
      throw clientOperationError('ClientRequestCancellationDenied');
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
      throw clientOperationError('ClientRequestNotFound');
    }
    void checkpoints.sweep();
    return {requestId, kind: held.outcome};
  };
  const wait = async ({ref, principalId: actual, until, signal}) => {
    if (until !== null && until !== 'terminal') {
      throw clientOperationError('InvalidWaitCondition');
    }
    const current = await observeRun({ref, principalId: actual});
    if (['succeeded', 'failed', 'cancelled'].includes(current.status)) {
      return current;
    }
    const operation = dispatchOwner.operation(ref);
    if (operation === undefined) return current;
    if (signal?.aborted) throw clientOperationError('WaitAborted');
    let abort;
    const interrupted = new Promise((_, reject) => {
      abort = () => reject(clientOperationError('WaitAborted'));
      signal?.addEventListener('abort', abort, {once: true});
    });
    try {
      await Promise.race([operation, interrupted]);
    } finally {
      signal?.removeEventListener('abort', abort);
    }
    return observeRun({ref, principalId: actual});
  };
  const prepareInferSelection = (preparedProgram, occurrence) => {
    // The Effect compiler retains this exact graph for the saved admission.
    // Current account/egress callbacks are checked again by physical dispatch.
    if (occurrence !== undefined && inferSelections.has(preparedProgram)) return;
    const selectedStep = occurrence === undefined
      ? moon.clientProgramSelectedInferStep(preparedProgram)
      : moon.clientProgramInferOccurrenceCoordinates(occurrence)._2;
    if (selectedStep !== undefined) {
      let execution;
      try {
        ({execution} = readInstalledModelExecution(moon, preparedProgram,
          modelInstallation, occurrence));
      } catch (cause) {
        diagnostic('infer_preparation_rejected', {boundary: 'model_execution',
          code: cause.code, cause: cause.cause ?? cause,
          typedCause: cause.code === 'MoonBitHostFailure' ?
            moon.clientProgramInferModelExecutionIssueKind(cause.cause) :
            undefined});
        throw clientOperationError('ClientProgramUnsupported', cause);
      }
      let dependencies;
      try {
        dependencies = readInstalledModelDependencies(moon, execution,
          modelInstallation);
      } catch (cause) {
        diagnostic('infer_preparation_rejected', {boundary: 'model_dependencies',
          code: cause.code, cause: cause.cause ?? cause,
          typedCause: cause.code === 'MoonBitHostFailure' ?
            moon.clientProgramInferModelDependencyIssueKind(cause.cause) :
            undefined});
        throw clientOperationError('ClientProgramUnsupported', cause);
      }
      let admittedProvider;
      try {
        admittedProvider = admitInstalledModelProvider(moon, execution, dependencies,
          modelProviders);
      } catch (cause) {
        diagnostic('infer_preparation_rejected', {boundary: 'model_provider',
          code: cause.code, cause: cause.cause ?? cause,
          typedCause: cause.code === 'MoonBitHostFailure' ?
            moon.clientProgramModelProviderAdmissionIssueKind(cause.cause) :
            undefined});
        throw clientOperationError('ClientProgramUnsupported', cause);
      }
      const physical = modelProviders.get(moon.clientProgramInferProviderId(execution));
      // Legacy registrations only validate payloads. They cannot implicitly
      // opt into physical preparation or invent an egress observation.
      if (typeof physical?.physicalPreflight !== 'function' ||
          typeof physical?.observeEgress !== 'function' ||
          physical?.quantityCapacity === undefined) {
        diagnostic('infer_preparation_rejected', {boundary: 'model_dispatch',
          code: 'InstalledInferDispatchNotConnected'});
        throw clientOperationError('ClientProgramUnsupported',
          new Error('InstalledInferDispatchNotConnected'));
      }
      try {
        const step = selectedStep;
        const segments = occurrence === undefined ? undefined : checked(
          moon.clientProgramPrepareEffectInferSegments(preparedProgram, occurrence,
            registry, values, fragment, ordered));
        const computeSuffix = occurrence === undefined
          ? checked(moon.clientProgramPrepareInferComputeSuffix(preparedProgram,
            step, registry, values, fragment, ordered)) : segments._1;
        const egressAdmission = checked(occurrence === undefined
          ? moon.clientProgramAdmitInferEgress(preparedProgram, step, execution,
            physical.observeEgress)
          : moon.clientProgramAdmitComposedInferEgress(occurrence, execution,
            physical.observeEgress));
        const observeAccount = () => observeInstalledModelAccount(moon, authorization);
        const account = observeAccount();
        const decision = moon.executionAuthorizationEvaluate(account, principalId,
          moon.clientProgramInferProviderId(execution),
          occurrence === undefined
            ? moon.clientProgramInferModelTaskCid(preparedProgram, step)
            : moon.clientProgramInferOccurrenceModelTaskCid(occurrence), 'infer');
        const outcome = JSON.parse(moon.executionAuthorizationEvaluationJson(decision));
        if (outcome.outcome !== 'allow') {
          throw Object.assign(new Error('InstalledInferAuthorityUnavailable'),
            {code: 'InstalledInferAuthorityUnavailable', cause: outcome});
        }
        const graph = checked(occurrence === undefined
          ? moon.clientProgramInstalledInferPlanGraph(preparedProgram, step, execution)
          : moon.clientProgramInstalledComposedInferPlanGraph(occurrence, execution));
        inferSelections.set(preparedProgram, Object.freeze({step, graph, computeSuffix,
          occurrence, computePrefix: segments?._0,
          provider: moon.clientProgramAdmittedModelProvider(admittedProvider, execution),
          egressAdmission, account, observeAccount,
          physicalPreflight: physical.physicalPreflight,
          quantityCapacity: physical.quantityCapacity}));
      } catch (cause) {
        diagnostic('infer_preparation_rejected', {boundary: 'model_admission',
          code: cause.code, cause: cause.cause ?? cause});
        throw clientOperationError('ClientProgramUnsupported', cause);
      }
    }
  };
  const requestOf = ({preparedProgram, requestId}) => {
    prepareSubmit.assertOwned(preparedProgram);
    if (prepareSubmit.kindOf(preparedProgram) === 'effectful') {
      const count = moon.clientProgramEffectAcquisitionCount(preparedProgram);
      const acquired = count > 0;
      if (count > 0) {
        if (sourceProfile === undefined) throw clientOperationError('ClientProgramNeedsInputs');
        if (count > 2 || count === 2 && sourceProfile.sources?.length !== 2 ||
            count === 1 && sourceProfile.sources !== undefined) {
          throw clientOperationError('ClientProgramUnsupported');
        }
        const selected = new Set();
        for (let task = 0; task < count; task++) {
          try {
            const requirement = checked(moon.clientProgramEffectPrepareLocalQueryRequirement(
              preparedProgram, task, 0, registry, values, fragment, ordered));
            const adapter = installedSourceFor(sourceProfile,
              moon.clientProgramQueryRequirementSourceRef(requirement));
            if (count === 2 && adapter.realizationKey !== 'duckdb-acquired') {
              throw new Error('UnsupportedEffectSourceRealization');
            }
            selected.add(adapter);
          } catch (cause) {
            throw clientOperationError('ClientProgramUnsupported', cause);
          }
        }
        if (selected.size !== count) throw clientOperationError('ClientProgramUnsupported');
      }
      const occurrence = moon.clientProgramEffectInferOccurrence(preparedProgram);
      if (occurrence !== undefined) prepareInferSelection(preparedProgram, occurrence);
      const requested = moon.clientProgramEffectRequestIdentity(
        preparedProgram, authorityScopeCid, requestId,
        moon.clientProgramSourceFreeInputIntentCid());
      if (requested === undefined) {
        throw clientOperationError('ClientProgramNeedsInputs');
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
    const acquisitionCount = moon.clientProgramAcquisitionCount(preparedProgram);
    const acquired = acquisitionCount > 0;
    const selectedAdapters = new Set();
    if (acquired) {
      if (sourceProfile === undefined) throw clientOperationError('ClientProgramNeedsInputs');
      if (acquisitionCount > 2 || acquisitionCount === 2 && sourceProfile.sources?.length !== 2) {
        throw clientOperationError('ClientProgramUnsupported');
      }
      // Every occurrence is selected by its checked requirement before any I/O.
      for (let task = 0; task < acquisitionCount; task++) {
        try {
          const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(
            preparedProgram, task, 0, registry, values, fragment, ordered));
          const adapter = installedSourceFor(sourceProfile,
            moon.clientProgramQueryRequirementSourceRef(requirement));
          selectedAdapters.add(adapter);
        } catch (cause) {
          throw clientOperationError('ClientProgramUnsupported', cause);
        }
      }
    }
    if (selectedAdapters.size !== acquisitionCount) throw clientOperationError('ClientProgramUnsupported');
    // Static ModelTask admission cannot authorize a model call. Until the
    // installed dependency/dispatch route is present, refuse before admitting
    // a Run rather than sending this acquisition into a Values fallback.
    prepareInferSelection(preparedProgram);
    const requested = moon.clientProgramRequestIdentity(preparedProgram,
      authorityScopeCid, requestId,
      moon.clientProgramSourceFreeInputIntentCid());
    if (requested === undefined) {
      throw clientOperationError('ClientProgramNeedsInputs');
    }
    const resultNames = [];
    for (let index = 0;
      index < moon.clientProgramResultCount(preparedProgram); index++) {
      const name = moon.clientProgramResultName(preparedProgram, index);
      if (name === undefined) throw new Error('ClientProgramResultMissing');
      resultNames.push(name);
    }
    return {requested, resultNames, acquired, acquisitionCount, effectful: false};
  };
  const prepareAcquisition = async (preparedProgram, sourceAccess,
    occurrence = {stage: 0, input: 0, task: 0}) => {
    const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(
      preparedProgram, occurrence.stage, occurrence.input, registry, values, fragment, ordered));
    const adapter = installedSourceFor(sourceProfile,
      moon.clientProgramQueryRequirementSourceRef(requirement));
    try {
      const prepared = await adapter.prepare({preparedProgram, registry, values, fragment, ordered,
        sourceAccess: sourceAccess ?? adapter.sourceAccess, occurrence});
      if (prepared.selection !== undefined) diagnostic('acquisition_selection',
        {task: occurrence.task, selection: prepared.selection});
      return prepared;
    } catch (cause) {
      if (cause instanceof ExecutionAuthorizationError) {
        throw clientOperationError(cause.runtimeCode ?? 'ACTQL_E_DELEGATION_UNAVAILABLE', cause);
      }
      if (cause?.selection !== undefined) {
        diagnostic('acquisition_selection', {task: occurrence.task, selection: cause.selection});
        throw clientOperationError(cause.selection.status === 'deferred'
          ? 'ClientProgramRejected' : 'ClientProgramUnsupported', cause);
      }
      throw cause;
    }
  };
  const prepareAcquisitions = async preparedProgram => {
    const result = [];
    for (let task = 0; task < moon.clientProgramAcquisitionCount(preparedProgram); task++) {
      const occurrence = Object.freeze({stage: task, input: 0, task});
      const prepared = await prepareAcquisition(preparedProgram, undefined, occurrence);
      try {
        capturedDuckDBNativeConfiguration(prepared);
      } catch (cause) {
        if (cause?.message === 'InstalledMultiSourceNativeAcquisitionRequired') {
          throw clientOperationError('ClientProgramUnsupported', cause);
        }
        throw cause;
      }
      const adapter = installedSourceFor(sourceProfile, prepared.checkedSource.sourceRef);
      result.push(Object.freeze({occurrence, prepared, adapter, sourceAccess: adapter.sourceAccess}));
    }
    return Object.freeze(result);
  };
  const acquisitionDescriptor = prepared => ({checkedSource: prepared.checkedSource,
    readTuple: prepared.readTuple, physicalBinding: prepared.physicalBinding});
  const sourceDescriptors = sources => sources.map(({occurrence, prepared}) =>
    ({...occurrence, ...acquisitionDescriptor(prepared)}));
  const sourceInventory = sources => sources?.length === 2 ? canonicalJson({
    version: 'actql-client-source-inventory/0.1', environmentCid: evidenceCid,
    acquisitions: sourceDescriptors(sources)}) : undefined;
  const captureSubmission = (submission, resultNames, preparedSource, preparedSources) => ({
    version: preparedSources?.length === 2
      ? 'actql-remote-multi-source-submission/0.1' : 'actql-remote-captured-submission/0.1',
    requestId: submission.requestId, principalId: submission.principalId,
    connection: submission.connection, kind: submission.kind, input: submission.input,
    parameters: submission.parameters, resultNames,
    ...(preparedSources?.length === 2 ? {acquisitions: sourceDescriptors(preparedSources)}
      : preparedSource === undefined ? {} : {acquisition: acquisitionDescriptor(preparedSource)}),
  });
  const planFor = ({preparedProgram, requestId},
    retainedDefinitionWire) => {
    prepareSubmit.assertOwned(preparedProgram);
    const common = {moon, control, preparedProgram,
      authorityScopeCid, namespaceId, requestId, storeAuthorityCid, now,
      ...(retainedDefinitionWire === undefined ? {} :
        {retainedDefinitionWire})};
    const infer = inferSelections.get(preparedProgram);
    if (infer !== undefined) {
      return inferTaskRunAdmission({...common, inferGraph: infer.graph});
    }
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
      resultNames, sourceInventory: sourceInventory(held.preparedSources),
      issueDefinition: () => {
        held.plan = planFor(submission);
        if (held.preparedSources?.length === 2) return {
          runDefinition: held.plan.runDefinition,
          runAdmissionEvidence: {prepared: held.plan.preparedEvidence.wire,
            authorization: held.plan.authorization.wire,
            sourceInventory: sourceInventory(held.preparedSources)}};
        return held.plan.runDefinition;
      },
    }, moon, control).catch(cause => {
      if (cause?.code === 'ClientRequestSourceInventoryMismatch') {
        // Caller input identity is unchanged. This Host cannot start the
        // retained Run against a different physical acquisition inventory.
        throw clientOperationError('ClientRunStartDenied', cause);
      }
      throw cause;
    });
    return accepted;
  };
  // Composition installs one owner for dispatch, cancellation, stop, and
  // cleanup. Checkpoint and HTTP paths share this owner.
  const observed = diagnostic;
  const runInfer = installNodeInferRun({moon, core: runtimeCore(moon), fragment, ordered,
    registry, values, selections: inferSelections, namespaceId, authorityScopeCid,
    storeAuthorityCid, now, faultInjection: authorization?.faultInjection});
  dispatchOwner = installNodeClientDispatchOwner({moon, control,
    journal, store, checkpoints, startRun, hostConnection, beforeDispatch,
    observed, prepareAcquisition, planFor, sourceProfile, registry, values,
    faultInjection: authorization?.faultInjection,
    fragment, ordered, namespaceId, authorityScopeCid, storeAuthorityCid, now,
    runInfer, computeConfigurations: {local:localSnapshotConfiguration}});
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
      now, inferPlanFor: prepared => inferSelections.get(prepared)?.graph,
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
                  retainComputationOwner, infer: inferSelections.get(facts.prepared),
                  store, principalId, faultInjection: authorization?.faultInjection,
                  observe: authorization?.observe});
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
      throw clientOperationError('ClientConnectionDenied');
    }
    const {requested, resultNames, acquired, acquisitionCount, effectful} =
      requestOf(submission);
    if (effectful) {
      return submitEffect(submission, requested, resultNames);
    }
    // A reserved physical start can only be reconciled from its original
    // durable Run. Do this before rebuilding physical source preparations.
    // INFER continues to its existing saved-capture replay owner below.
    const retainedStart = journal.resolveDefinition(requested, {namespaceId}, moon, control);
    if (retainedStart?.physicalStartReserved === true &&
        !inferSelections.has(submission.preparedProgram)) {
      return {ref: retainedStart.ref, durability: retainedStart.durability,
        revision: retainedStart.revision};
    }
    const preparedSources = acquisitionCount === 2
      ? await prepareAcquisitions(submission.preparedProgram) : undefined;
    const preparedSource = acquired && acquisitionCount !== 2
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
        if (existing.physicalStartReserved !== true &&
            existing.runAdmissionEvidence?.sourceInventory !== sourceInventory(preparedSources)) {
          throw clientOperationError('ClientRunStartDenied',
            clientOperationError('ClientRequestSourceInventoryMismatch'));
        }
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
      const captured = captureSubmission(submission, resultNames, preparedSource, preparedSources);
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
    const held = {preparedSource, preparedSources,
      preparedSourceAccess: preparedSource === undefined ? undefined :
        installedSourceFor(sourceProfile, preparedSource.checkedSource.sourceRef).sourceAccess};
    const accepted = await admitDefinition(submission, requested,
      resultNames, held);
    if (inferSelections.has(submission.preparedProgram) &&
        accepted.physicalStartReserved === true &&
        accepted.observedTerminalOutcome === null &&
        !accepted.cancellationRequested &&
        dispatchOwner.operation(accepted.ref) === undefined &&
        await store.confirmCommittedIndex(accepted.ref) === undefined) {
      // Re-submission of the exact accepted request may reopen its saved
      // evidence, never reserve another provider dispatch. Missing evidence
      // leaves the original unknown Run intact.
      const flight = dispatchOwner.track(accepted.ref, {
        run: async ({signal, retainExecution, beginPhysicalWork, acquireSource}) => {
          const current = journal.lookupRunDefinition(accepted.ref, moon, control);
          if (current === undefined || current.cancellationRequested ||
              current.observedTerminalOutcome !== null) return;
          const plan = planFor(submission, current.runDefinition.wire);
          let acquiredInfer;
          if (acquired) {
            // Reacquisition uses the current installed read admission. It
            // grants no permission to dispatch the model again; saved slot
            // replay separately binds the original evidence and actual input.
            const sourceAccess = checkpoints?.acquisitionAccess(
              submission.requestId, sourceProfile.sourceAccess) ?? sourceProfile.sourceAccess;
            const preparedSource = await prepareAcquisition(submission.preparedProgram,
              sourceAccess);
            const {captured, sourceEvidenceWire, captureStartedAt, captureCompletedAt} =
              await acquireSource({preparedProgram: submission.preparedProgram,
                preparedSource, sourceAccess});
            const input = checked(moon.clientProgramAdmitInferCapturedInput(
              submission.preparedProgram, captured.inferStep, captured.capturedSource,
              captured.identity, captured.requirement, captured.logicalInput,
              sourceEvidenceWire, authorityScopeCid,
              captured.checkedSource.sourceDataPolicyCid,
              captureStartedAt, captureCompletedAt));
            acquiredInfer = {input, sourceEvidence: control.admitRunEvidence(
              'source_evidence', sourceEvidenceWire,
              {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})};
          }
          await runInfer({preparedProgram: submission.preparedProgram, plan,
            store, principalId: actual, signal, retainExecution,
            beginPhysicalWork, acquiredInfer, replay: true});
        },
        observeStopped: async () => {
          // Only the existing publication owner can make recovery successful.
          // A reader refusal does not resolve the original physical outcome.
          if (await store.confirmCommittedIndex(accepted.ref) !== undefined) {
            journal.markPhysicalClose(accepted.ref, null);
          }
        },
      });
      void flight.catch(error => diagnostic('infer_replay_failed', {
        ref: accepted.ref, code: error?.code ?? error?.message}));
      return {ref: accepted.ref, durability: accepted.durability,
        revision: accepted.revision};
    }
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
    const {requested, resultNames, acquired, acquisitionCount, effectful} = requestOf(submission);
    const preparedSources = acquisitionCount === 2
      ? await prepareAcquisitions(submission.preparedProgram) : undefined;
    const preparedSource = acquired && acquisitionCount !== 2
      ? await prepareAcquisition(submission.preparedProgram) : undefined;
    const reproduced = captureSubmission(submission, resultNames, preparedSource, preparedSources);
    if (canonicalJson(reproduced) !== canonicalJson(captured)) {
      throw new Error('HeldAcquisitionChanged');
    }
    if (JSON.stringify(resultNames) !==
        JSON.stringify(captured.resultNames)) {
      throw new Error('HeldRequestChanged');
    }
    return {submission, requested, resultNames, preparedSource, preparedSources, effectful};
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
    const acquisition = captured.acquisition === undefined && captured.acquisitions === undefined ? undefined :
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
    const {submission, requested, resultNames, preparedSource, preparedSources,
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
    const held = {preparedSource, preparedSources,
      preparedSourceAccess: preparedSource === undefined ? undefined :
        installedSourceFor(sourceProfile, preparedSource.checkedSource.sourceRef).sourceAccess};
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
    negotiate, prepareSubmit, submit, check, attach,
    lookupRequest: lookupHeld,
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
  authenticate, beforeDispatch, authorization, sourceProfilePath, sourceProfilePaths,
  resolveSourceSecret, effectProfilePath, resolveEffectSecret,
  effectInstallation, modelInstallation, registerModelProviders}) {
  if (typeof directory !== 'string' || !directory ||
      typeof authenticate !== 'function' ||
      beforeDispatch !== undefined && typeof beforeDispatch !== 'function') {
    throw new TypeError('InvalidInstalledRemoteHost');
  }
  const host = await openInstalledHost({root: resolve(directory), mode: 'remote',
    beforeDispatch, authorization, sourceProfilePath, sourceProfilePaths, resolveSourceSecret,
    effectProfilePath, resolveEffectSecret, effectInstallation,
    modelInstallation, registerModelProviders});
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
      while (handling.size > 0) {
        await Promise.allSettled([...handling]);
      }
      const result = await shutdown.close();
      // Failed shutdown still owns retryable physical cleanup. Keep its
      // bounded observation alive until those owners confirm final release.
      host.diagnostic.close();
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
        sourceProfilePaths: installation?.sourceProfilePaths,
        resolveSourceSecret: installation?.resolveSourceSecret,
        effectProfilePath: installation?.effectProfilePath,
        resolveEffectSecret: installation?.resolveEffectSecret,
        modelInstallation: installation?.modelInstallation,
        registerModelProviders: installation?.registerModelProviders})});
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

