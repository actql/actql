import {configureInferEvidence} from './infer-evaluation-evidence.mjs';
// One installed Local Host for the current OS user. The Client talks to the
// Host in process; the journal and publication Store own durable physical I/O.
import {ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {snapshotHostCapacityPolicy, selectInstalledHostEnvironment} from './installed-host-policy.mjs';
import {createHash, createPublicKey, randomBytes, randomUUID} from 'node:crypto';
import {mkdir, readFile, stat} from 'node:fs/promises';
import {homedir, userInfo} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {validClientConnection} from '../../packages/client-wire/index.mjs';
import {createEmbeddedHostRegistry, installedHostShutdown} from './embedded-local-lifecycle.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {admitHostRootFormat} from './host-root-format.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {installNodeClientEffectRun} from './client-effect-run.mjs';
import {runCapturedEffectComputation} from './entry.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
import {selectAcquiredEffectSources} from './acquired-effect-sources.mjs';
import {withLocalExecutionPauseHandler} from '../local-node/retained-store.mjs';
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {capturedDuckDBConfiguration} from './captured-duckdb-source.mjs';
import {recoverAdmittedEffectRun} from './effect-run-recovery.mjs';
import {retireCompletedEffectfulCapture} from
  '../host-common/completed-run-publication.mjs';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';
import {installedModelEnvironment, readInstalledModelExecution,
  readInstalledModelDependencies, installModelProviders,
  admitInstalledModelProvider, admitInstalledModelProviderBinding,
  observeInstalledModelAccount} from
  './installed-model.mjs';
import {installNodeInferRun} from './installed-infer-run.mjs';
import {installNodeModelContinuation} from './installed-model-continuation.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {issueInstalledRunControlObservation, issueInstalledRunObservationKey,
  issueInstalledUnpublishedRunState} from
  '../host-common/run-state-observation.mjs';
import {installedEffectIdentity, installedEffectPaths, loadInstalledEffects,
  publishInstalledEffectProfile} from
  './installed-effect.mjs';
import {installedEffectFor} from './installed-effect-inventory.mjs';
import {installedRowEffectDescriptors} from './installed-row-effect.mjs';
import {assertInstalledConnectorTable} from './installed-connectors.mjs';
import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey} from
  './local-continuation-evidence.mjs';
import {installedSourceIdentity, installedSourcePaths, loadInstalledSources,
  installedSourceFor, installedSourceReadAccesses, installedSourceReadBindings,
  publishInstalledSourceProfile} from
  './installed-source.mjs';
import {createDiagnosticObserver} from
  '../host-common/diagnostic-observer.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {installHostObservation, observationTraceParent} from '../host-common/observation.mjs';
import {installNodeClientDispatchOwner, confirmNodeRunCancellation, cancelNodeRunContinuation,
  observeNodeRestoredModelStop, recordNodeRunPhysicalStop} from './client-dispatch-owner.mjs';
import {retainInstalledHostInitializationFailure} from
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
import {installLocalRetainedStore, installLocalSnapshotStore} from
  '../local-node/retained-store.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {assertEffectTargetReadBinding, effectTargetReadContinuation} from
  './effect-target-read-continuation.mjs';
import {EFFECT_TARGET_CONTINUATION} from './effect-target-read-inventory.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {localContractLimits, localOutputLimits,
  sourceFreeValuesPlan, sourceFreeValuesAdmissionEvidence, sourceFreeTaskPlan,
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
const profiles = createEmbeddedHostRegistry(sameEmbeddedInstallation);

const bytesCid = bytes => `sha256:${createHash('sha256')
  .update(bytes).digest('hex')}`;
const publicKeyCid = value => bytesCid(createPublicKey(value).export({
  type: 'spki', format: 'der'}));

async function embeddedInstallationIdentity(root, installation) {
  const connectorTable = installation?.connectorTable;
  if (connectorTable !== undefined) assertInstalledConnectorTable(connectorTable);
  const sourcePaths = installedSourcePaths(installation);
  const effectPaths = installedEffectPaths(installation);
  const identities = await Promise.all(sourcePaths.map(path =>
    installedSourceIdentity(path, {connectorTable})));
  const source = identities.length === 0 ? null : identities.length === 1
    ? identities[0] : {version: 'actql-installed-source-inventory/0.1', identities};
  const effectIdentities = [];
  for (const path of effectPaths) {
    effectIdentities.push(await installedEffectIdentity(path, {connectorTable}));
  }
  const effect = effectIdentities.length === 0 ? null : effectIdentities.length === 1
    ? effectIdentities[0] : {version: 'actql-installed-effect-inventory/0.1',
      identities: effectIdentities};
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
    ...(installation?.hostCapacityPolicy === undefined ? {} : {
      hostCapacityPolicy: installation.hostCapacityPolicy}),
    ...(installation?.modelInstallation === undefined ? {} : {
      modelEnvironment: installation.modelInstallation}),
    ...(installation?.resultDataPolicy === undefined ? {} : {
      resultDataPolicy: installation.resultDataPolicy}),
    ...(installation?.retainedRelationOutput === true ? {
      retainedRelationOutput: true} : {}),
    ...(installation?.valuesMaxRows === undefined ? {} : {
      valuesMaxRows: installation.valuesMaxRows}),
    hostKey: authorization?.hostKey === undefined ? null : {
      keyId: authorization.hostKey.keyId,
      publicKeyCid: publicKeyCid(authorization.hostKey.privateKey)},
    reviewers: authorization?.reviewers?.map(reviewer => ({
      keyId: reviewer.keyId, reviewerId: reviewer.reviewerId,
      principalId: reviewer.principalId,
      publicKeyCid: publicKeyCid(reviewer.publicKey)})) ?? null}));
  return Object.freeze({identity, connectorTable, callbacks: Object.freeze({
    resolveSourceSecret: installation?.resolveSourceSecret,
    resolveEffectSecret: installation?.resolveEffectSecret,
    registerModelProviders: installation?.registerModelProviders,
    inferEvidence: installation?.inferEvidence,
    observation: installation?.observation,
    decide: authorization?.decide, observe: authorization?.observe,
    faultInjection: authorization?.faultInjection})});
}

function sameEmbeddedInstallation(left, right) {
  return left.identity === right.identity && left.connectorTable === right.connectorTable &&
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

function validateValuesMaxRows(value) {
  if (value !== undefined && (!Number.isSafeInteger(value) || value < 1 || value > 10000)) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
}

async function openInstalledHost({root, mode = 'local', beforeDispatch, workspaceId,
  authorization, connectorTable, sourceProfilePath, sourceProfilePaths, resolveSourceSecret,
  effectProfilePath, effectProfilePaths, resolveEffectSecret, effectInstallation,
  modelInstallation, registerModelProviders, resultDataPolicy, inferEvidence, hostCapacityPolicy,
  retainedRelationOutput = false, valuesMaxRows, observation: observationConnection}) {
  hostCapacityPolicy = snapshotHostCapacityPolicy(hostCapacityPolicy);
  if (connectorTable !== undefined) assertInstalledConnectorTable(connectorTable);
  validateValuesMaxRows(valuesMaxRows);
  if (workspaceId !== undefined && !validClientConnection({mode, owner: mode,
    consentRefs: [], runners: [], workspaceId})) {
    throw new TypeError('InvalidInstalledWorkspaceBinding');
  }
  if (typeof retainedRelationOutput !== 'boolean') {
    throw new TypeError('InvalidLocalRetainedOutputConfiguration');
  }
  const selectedSourcePaths = installedSourcePaths({sourceProfilePath, sourceProfilePaths});
  const selectedEffectPaths = installedEffectPaths({effectProfilePath, effectProfilePaths});
  if (valuesMaxRows !== undefined &&
      (effectInstallation !== undefined || selectedEffectPaths.length > 0)) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
  if (effectInstallation !== undefined && selectedEffectPaths.length > 0) {
    throw new TypeError('InvalidInstalledEffectSite');
  }
  await admitHostRootFormat(root);
  const moon = await import(runtimeUrl.href);
  const control = runtimeCore(moon).publicationControl;
  const installedResultDataPolicy = resultDataPolicy === undefined ? undefined :
    control.admitSourceFreeResultPolicy(resultDataPolicy, localContractLimits);
  const evidenceConfiguration = configureInferEvidence(inferEvidence);
  const modelProviders = installModelProviders(moon, registerModelProviders);
  const inferSelections = new WeakMap();
  const effectSubmissions = new WeakMap();
  const effectSelections = new WeakMap();
  const principalId = userInfo().username;
  const baseEnvironmentWire = selectInstalledHostEnvironment(moon, (await readFile(join(packageRoot,
    'spec/local-check-environment.json'), 'utf8')).trimEnd(), hostCapacityPolicy);
  // Both adapters restore published declarations without provider I/O. The
  // combined environment is admitted before either can dispatch work.
  let sourceProfile;
  let installedEffect;
  let environmentWire, effectiveHostCapacityPolicyCid;
  function selectedInstalledEffect({prepared, compilation}) {
    if (installedEffect?.effects === undefined) return installedEffect;
    let selected = effectSelections.get(prepared);
    if (selected === undefined) {
      selected = installedEffectFor(installedEffect,
        installedRowEffectDescriptors(moon, prepared, compilation));
      effectSelections.set(prepared, selected);
    }
    return selected;
  }
  function recoveredInstalledEffect(facts) {
    if (installedEffect?.effects === undefined) return installedEffect;
    // The capture owner has already authenticated and admitted this Preview.
    // Select its original Mapping inventory; never infer a new Program or Run.
    const preview = facts.recovered.computation.preview;
    const body = JSON.parse(facts.control.effectComputationPreviewWire(preview));
    const descriptors = body.effects.map(member => ({effectId: member.effect_id,
      kind: member.effect_kind, target: member.target, mappingRef: member.mapping,
      mappingCid: member.resolved_mapping_contract_cid,
      ...(member.source_table_input === undefined ? {} : {capabilityCid: member.capability_evidence_cid})}));
    try { return installedEffectFor(installedEffect, descriptors); }
    catch (cause) {
      // This observes only installation metadata before any new provider work.
      // The existing resume owner still preserves attempted unknown outcomes.
      throw refusedEffectPreparation(clientOperationError('InstalledEffectInstallationChanged', cause));
    }
  }
  try {
    sourceProfile = await loadInstalledSources(selectedSourcePaths,
      {root, principalId, moon, runtimeUrl, baseEnvironmentWire,
        resolveSecret: resolveSourceSecret, connectorTable});
    installedEffect = await loadInstalledEffects(selectedEffectPaths, {root, principalId, moon,
        runtimeUrl, baseEnvironmentWire, resolveSecret: resolveEffectSecret, connectorTable});
    if (installedEffect !== undefined) {
      if (authorization === undefined) {
        throw new TypeError('InstalledEffectAuthorizationRequired');
      }
      effectInstallation = createInstalledEffectSite(installedEffect.effects === undefined
        ? installedEffect : {
          environmentWire: installedEffect.environmentWire,
          prepareCaptured: facts => selectedInstalledEffect(facts).prepareCaptured(facts),
          prepareRecovered: facts => recoveredInstalledEffect(facts).prepareRecovered(facts),
        });
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
      capacity: {max_graph_construction_edges: 1000,
        max_graph_construction_input_rows: 1000,
        max_graph_construction_nodes: 1000, ...body.host_policy_profile.capacity}};
    if (hostCapacityPolicy !== undefined) {
      effectiveHostCapacityPolicyCid = contentCid(body.host_policy_profile.capacity);
    }
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
    const graphLaw = JSON.parse(await readFile(join(packageRoot,
      'spec/dependencies/actql-graph-laws.json'), 'utf8'));
    // These declarations admit checking for the installed family providers.
    // The exact task offer and execution obligations still select capability.
    environment = moon.clientProgramCheckEnvironmentWithGraphProfile(
      environmentWire, evidenceCid, false, true, true, true, true, false,
      false, numericProfileCid, contentCid(graphLaw));
    if (environment !== undefined) {
      sourcePublication = sourceAliasPublication(moon, environment,
        sourceProfile?.queryAliases ?? [],
        installedEffect?.queryTableBindings ?? effectInstallation?.queryTableBindings ?? []);
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
    root, principalId, ...(hostCapacityPolicy === undefined ? {} :
      {hostCapacityPolicyCid: effectiveHostCapacityPolicyCid})});
  const storeAuthorityCid = cid({version: 'actql-local-store-owner/0.1',
    root, principalId});
  const journalDirectory = join(root, 'requests');
  let journal;
  let effectEvidenceKey;
  let store;
  let checkpoints;
  let modelController;
  let dispatchOwner;
  let diagnostic;
  let observation;
  let localSnapshotConfiguration;
  try {
    const delivery = createDiagnosticObserver(authorization?.observe);
    diagnostic = Object.assign((event, detail) => {
      observation?.diagnostic(event, detail);
      delivery(event, detail);
    }, {close: delivery.close, status: delivery.status});
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
    // the snapshot cleanup owner. Graph row Relations use the same Store for
    // verified export/reload before their ordinary guaranteed projection.
    const installStore = retainedRelationOutput
      ? installLocalRetainedStore : installLocalSnapshotStore;
    localSnapshotConfiguration = installStore((_key, bytes, frame) =>
      createLocalRetainedStore({parentDirectory:snapshotDirectory,
        capacityBytes:bytes,maxFrameBytes:frame,maxEntries:1}),
    authorization?.faultInjection);
    journal = openClientRequestJournal(journalDirectory, {
      // Private fault hooks exercise the real installed admission clock;
      // Programs and public transport requests cannot select these values.
      submissionEpochTtlMs: authorization?.faultInjection?.submissionEpochTtlMs,
      submissionEpochNow: authorization?.faultInjection?.submissionEpochNow,
    });
    observation = installHostObservation(observationConnection, {journal,
      runId: ref => {
        const retained = journal.lookupRunDefinition(ref, moon, control);
        return retained === undefined ? undefined :
          control.runDefinitionRunId(retained.runDefinition);
      }});
    if (observation !== undefined) journal.installObservationProjection(observation);
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
  const checkSource = installNodeClientCheck({moon, environment,
    publication: sourcePublication,
    tableWriteAccesses: installedEffect?.queryTableWriteAccesses ??
      effectInstallation?.queryTableWriteAccesses ?? [],
    sourceAccesses: (sourceProfile?.sources ??
      (sourceProfile === undefined ? [] : [sourceProfile]))
      .flatMap(installedSourceReadAccesses)});
  // Checking dispatches nothing and reads no source rows; the audience is
  // the authenticated caller this connection admits.
  const check = async ({principalId: actual, connection, ...request}) => {
    if (!hostConnection({principalId: actual, connection})) {
      throw clientOperationError('ClientConnectionDenied');
    }
    // Preserve the selected scope and the absence of template bindings across
    // this installed-Host authorization boundary.
    const result = await checkSource({principalId: actual, ...request});
    // The verdict belongs to the common checker. No diagnostic text, source
    // location, authored name, source bytes or hypothetical Run is projected.
    observation?.emit('check', 'check_completed', {checkVerdict: result.report?.verdict,
      outcome: result.report?.verdict === 'invalid' || result.outcome === 'failed'
        ? 'failed' : result.report?.verdict === 'verified' ? 'succeeded' : 'unknown'});
    return result;
  };
  Object.defineProperty(check, 'unavailable', {value: checkSource.unavailable});
  const prepareSubmit = installNodeClientProgramPreparation({moon,
    environment, sourcePublication, valuesMaxRows, check,
    allowEffects: effectInstallation !== undefined});
  Object.freeze(check);
    if (modelInstallation !== undefined && authorization !== undefined) {
      modelController = await installNodeModelContinuation({moon, control,
        store, storeAuthorityCid, authorityScopeCid, namespaceId, now, observe: diagnostic,
        observation,
        getCheckpoints: () => checkpoints});
    }
    checkpoints = await installRemoteCheckpoints({root, namespaceId,
      authorityScopeCid, ownerPrincipal: principalId,
      siteKey: authorization?.siteKey ?? 'actql-remote-host',
      realizationKey: sourceProfile?.realizationKey ?? REALIZATION_KEY,
      environmentCid: evidenceCid,
      contractControl: control,
      modelResumeVerifier: modelController?.verifier,
      ...(installedEffect?.effects === undefined
        ? {effectTarget: effectInstallation?.targetReadAuthorization}
        : {effectTargets: installedEffect.effects.filter(effect =>
          effect.targetReadAuthorization !== undefined).map(effect => ({
          selectors: effect.effectSelectors, authorization: effect.targetReadAuthorization}))}),
      authorization: authorization == null ? authorization :
        {...authorization, observe: diagnostic},
      ...(sourceProfile?.sources === undefined &&
          (sourceProfile === undefined ||
            installedSourceReadAccesses(sourceProfile).length === 1)
        ? {source: sourceProfile === undefined ? undefined : {
          ...sourceProfile.readAuthorization,
          sourceRef: installedSourceReadAccesses(sourceProfile)[0].sourceRef}}
        : {sources: (sourceProfile?.sources ?? [sourceProfile]).flatMap(source =>
          installedSourceReadAccesses(source).map(access => ({
            sourceRef: access.sourceRef, ...source.readAuthorization})))})});
  const projectRunObservation = (ref, state, retained) => {
    if (observation === undefined) return;
    try {
      // MoonBit fixes the projection equivalence. SQLite only retains this
      // bounded key; it cannot authorize a transition or reinterpret a Run.
      const ownerFactKey = issueInstalledRunObservationKey(moon, {
        outcome: state.status, revision: retained.revision,
        cleanupPending: state.cleanupPending,
        physicalCloseConfirmed: retained.physicalCloseConfirmed,
      });
      if (ownerFactKey === undefined) { observation.noteLoss(); return; }
      observation.emit('run', 'owner_observed', {ref, outcome: state.status,
        revision: retained.revision,
        physicalStop: retained.physicalCloseConfirmed === true ? 'confirmed' : undefined,
        cleanupPending: state.cleanupPending}, {ownerFactKey});
    } catch { observation.noteLoss(); }
  };
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
        if (!dispatchOwner.live(ref) && !modelResumeFlights.has(ref.runDefinitionCid) &&
            (checkpoints?.journal.hasUnresolvedModelCalls(runId) === true ||
            continuation?.status === 'resuming' &&
            (checkpoints.hasUnresolvedSourceStart(runId, ref.runDefinitionCid) ||
             checkpoints.hasUnresolvedEffectTargetStart(runId, ref.runDefinitionCid) ||
             checkpoints.hasUnresolvedModelStart(runId, ref.runDefinitionCid)))) {
          state = issueInstalledUnpublishedRunState(moon, {runId,
            observedAt: now(), resultNames: retained.resultNames,
            dispatchReserved: true, preDispatchFailureConfirmed: false,
            cancelledBeforeStart: false, observedTerminalOutcome: 'none',
            executionUnknown: true});
        } else if (continuation !== undefined &&
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
      // Only this revision-stable common Owner projection supplies status.
      projectRunObservation(ref, state, retained);
      return {...state, control: observation};
    }
    throw new Error('RunStateObservationUnstable');
  };
  const cancelEffectContinuation = async ref => {
    if (checkpoints === undefined) return false;
    const retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined || !retained.cancellationRequested) {
      return false;
    }
    return cancelNodeRunContinuation({ref, journal, store, checkpoints, moon, control,
      currentDispatchIdle: () => dispatchOwner.operation(ref) === undefined &&
        !effectResumeFlights.has(ref.runDefinitionCid) &&
        !modelResumeFlights.has(ref.runDefinitionCid)});
  };
  const continueAcceptedCancellation = async (ref, accepted) => {
    if (accepted.kind === 'already_terminal') return;
    dispatchOwner.cancel(ref);
    try { await cancelEffectContinuation(ref); }
    finally { void checkpoints?.sweep(); }
  };
  // Request-level cancellation already owns its own pre-Run receipt. Its
  // transfer to a defined Run remains separate from a Client cancel operation.
  const cancelRequestRun = async ({ref, principalId: actual, connection}) => {
    if (!hostConnection({principalId: actual, connection, ref})) {
      throw clientOperationError('ClientRunCancellationDenied');
    }
    // Authorization precedes existence queries. A late publication remains a
    // successful Run even if cancellation was accepted while it committed.
    const publicationCommitted =
      await store.confirmCommittedIndex(ref) !== undefined;
    const retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined) throw clientOperationError('ClientRunCancellationDenied');
    const originalRunWire = retained.runAdmissionEvidence?.modelOriginalRunWire;
    if (!publicationCommitted && originalRunWire !== undefined) {
      if (checkpoints === undefined) throw clientOperationError('ModelCancellationJournalUnavailable');
      // The per-call transaction domain wins before the request's independent
      // journal write. A failed second commit is retried without removing the
      // sticky fence; no acknowledgement precedes both durable writes.
      checkpoints.journal.fenceRunCancellation({originalRunWire});
    }
    const accepted = journal.requestCancellation(ref, {
      currentAuthorization: true, publicationCommitted,
    }, moon, control);
    await continueAcceptedCancellation(ref, accepted);
    observation?.emit('run', 'cancellation_requested', {ref,
      revision: accepted.revision, outcome: accepted.outcome});
    return accepted;
  };
  const cancel = async ({ref, cancelId, expectedRevision, principalId: actual, connection}) => {
    if (!hostConnection({principalId: actual, connection, ref})) {
      throw clientOperationError('ClientCancellationDenied');
    }
    const publicationCommitted = await store.confirmCommittedIndex(ref) !== undefined;
    // Recheck current connection authority after the publication observation.
    // The journal then compares the original revision under its write lock.
    if (!hostConnection({principalId: actual, connection, ref})) {
      throw clientOperationError('ClientCancellationDenied');
    }
    let recorded;
    try {
      recorded = journal.recordCancellationOperation(ref, {
        cancelId, expectedRevision, currentAuthorization: true, publicationCommitted,
        modelCancellationOwner: checkpoints?.journal,
      }, moon, control);
    } catch (cause) {
      // A lost COMMIT acknowledgement can leave an accepted original operation.
      // Observe its exact durable identity before waking the existing stop and
      // continuation owners. Pending or unavailable custody grants no authority
      // to advance cancellation, and the lost reply remains unknown to the SDK.
      let retained;
      try {
        retained = journal.lookupCancellationOperation({...ref, cancelId, expectedRevision},
          {currentAuthorization: hostConnection({principalId: actual, connection, ref})},
          moon, control);
      } catch { /* Recovery remains with the durable journal and its existing sweep. */ }
      if (retained?.kind === 'found') {
        try { await continueAcceptedCancellation(ref, retained.cancellation); }
        catch { /* Preserve the original unknown reply; cleanup remains owned. */ }
      }
      throw cause;
    }
    const accepted = recorded.cancellation;
    if (recorded.recorded) await continueAcceptedCancellation(ref, accepted);
    observation?.emit('run', 'cancellation_requested', {ref,
      revision: accepted.revision, outcome: accepted.outcome});
    return accepted;
  };
  const lookupCancellation = ({ref, cancelId, expectedRevision, principalId: actual, connection}) => {
    if (!hostConnection({principalId: actual, connection, ref})) {
      throw clientOperationError('ClientCancellationDenied');
    }
    return journal.lookupCancellationOperation({...ref, cancelId, expectedRevision},
      {currentAuthorization: true}, moon, control);
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
      const run = await cancelRequestRun({ref: existing.ref, principalId: actual,
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
      // The dispatch supervisor records execution failure only after owned
      // stop and cleanup. Its rejected physical Promise is not a failure of
      // this public observation operation. Read the resulting Run state;
      // unresolved custody remains unknown rather than becoming success.
      await Promise.race([operation.then(() => undefined, () => undefined),
        interrupted]);
    } finally {
      signal?.removeEventListener('abort', abort);
    }
    return observeRun({ref, principalId: actual});
  };
  const prepareInferSelection = (preparedProgram, occurrence, retain = true) => {
    // The Effect compiler retains this exact graph for the saved admission.
    // Current account/egress callbacks are checked again by physical dispatch.
    if (retain && occurrence !== undefined && inferSelections.has(preparedProgram)) return;
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
        const durableModel = modelController !== undefined && checkpoints?.configured === true;
        const step = selectedStep;
        const segments = occurrence === undefined ? undefined : checked(
          (prepareSubmit.kindOf(preparedProgram) === 'effectful'
            ? moon.clientProgramPrepareEffectInferSegments : moon.clientProgramPrepareComposedInferSegments)(preparedProgram, occurrence,
            registry, values, fragment, ordered));
        const computeSuffix = occurrence === undefined
          ? checked(moon.clientProgramPrepareInferComputeSuffix(preparedProgram,
            step, registry, values, fragment, ordered)) : segments._1;
        let egressAdmission;
        let egressFailure;
        try {
          egressAdmission = checked(occurrence === undefined
            ? moon.clientProgramAdmitInferEgress(preparedProgram, step, execution,
              physical.observeEgress)
            : moon.clientProgramAdmitComposedInferEgress(occurrence, execution,
              physical.observeEgress));
        } catch (error) {
          if (!durableModel) throw error;
          // Historical fixed inputs and saved responses remain readable.
          // Every fresh send must separately require a current egress owner.
          egressFailure = error;
        }
        const observeAccount = () => observeInstalledModelAccount(moon, authorization);
        const account = observeAccount();
        if (!durableModel) {
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
        }
        const graph = checked(occurrence === undefined
          ? moon.clientProgramInstalledInferPlanGraph(preparedProgram, step, execution)
          : moon.clientProgramInstalledComposedInferPlanGraph(occurrence, execution));
        const providerId = moon.clientProgramInferProviderId(execution);
        const providerBinding = durableModel
          ? admitInstalledModelProviderBinding(moon, providerId, physical) : undefined;
        const selection = Object.freeze({step, graph, computeSuffix,
          occurrence, computePrefix: segments?._0,
          provider: moon.clientProgramAdmittedModelProvider(admittedProvider, execution),
          egressAdmission, egressFailure, account, observeAccount, providerBinding,
          currentProvider: () => modelProviders.get(providerId) === physical,
          physicalPreflight: physical.physicalPreflight,
          quantityCapacity: physical.quantityCapacity});
        if (retain) inferSelections.set(preparedProgram, selection);
        return selection;
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
        try {
          selectAcquiredEffectSources({moon, preparedEffect: preparedProgram,
            sourceProfile, registry, values, fragment, ordered});
        } catch (cause) {
          throw clientOperationError('ClientProgramUnsupported', cause);
        }
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
    if (acquired) {
      if (sourceProfile === undefined) throw clientOperationError('ClientProgramNeedsInputs');
      if (acquisitionCount > 2) {
        throw clientOperationError('ClientProgramUnsupported');
      }
      // Every occurrence is selected by its checked requirement before any I/O.
      for (let task = 0; task < acquisitionCount; task++) {
        try {
          const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(
            preparedProgram, task, 0, registry, values, fragment, ordered));
          const sourceRef = moon.clientProgramQueryRequirementSourceRef(requirement);
          const adapter = installedSourceFor(sourceProfile, sourceRef);
          if (acquisitionCount === 2 &&
              !installedSourceReadBindings(adapter).includes(sourceRef)) {
            throw new Error('InstalledMultiSourceUnsupported');
          }
        } catch (cause) {
          throw clientOperationError('ClientProgramUnsupported', cause);
        }
      }
    }
    // Static ModelTask admission cannot authorize a model call. Until the
    // installed dependency/dispatch route is present, refuse before admitting
    // a Run rather than sending this acquisition into a Values fallback.
    const inventory = moon.clientProgramComposedInferOccurrences(preparedProgram);
    const occurrences = inventory.$tag === 1 ? inventory._0 : [];
    if (occurrences.length > 1) {
      const components = Object.freeze(occurrences.map(occurrence =>
        prepareInferSelection(preparedProgram, occurrence, false)));
      inferSelections.set(preparedProgram, Object.freeze({components,
        graph: Object.freeze(components.map(component => component.graph)),
        egressFailure: components.find(component => component.egressFailure !== undefined)?.egressFailure}));
    } else prepareInferSelection(preparedProgram);
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
      // A held read has no selection before approval. Once authorized, keep
      // either typed acquisition owner; shared ledger admission happens before
      // dispatch and the provider rechecks this exact occurrence's read gate.
      if (prepared.selection !== undefined) {
        try { capturedDuckDBConfiguration(prepared); }
        catch (cause) { throw clientOperationError('ClientProgramUnsupported', cause); }
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
    ...(submission.submission === undefined ? {} : {submission: submission.submission}),
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
      try {return inferTaskRunAdmission({...common, inferGraph: infer.graph});}
      catch (cause) {
        diagnostic('infer_preparation_rejected', {boundary: 'task_compilation',
          code: cause.code, cause: cause.cause ?? cause});
        throw cause;
      }
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
      submission: submission.submission,
      resultNames, sourceInventory: sourceInventory(held.preparedSources),
      issueDefinition: () => {
        held.plan = planFor(submission);
        if (held.plan.kind === 'infer') return {
          runDefinition: held.plan.runDefinition,
          runAdmissionEvidence: {
            prepared: held.plan.preparedEvidence.wire,
            authorization: held.plan.authorization.wire,
            modelOriginalRunWire: originalModelRunWire(held.plan.compiled,
              held.plan.runDefinition),
            ...(held.preparedSources?.length === 2 ? {
              sourceInventory: sourceInventory(held.preparedSources)} : {}),
          }};
        if (held.preparedSources?.length === 2) return {
          runDefinition: held.plan.runDefinition,
          runAdmissionEvidence: {prepared: held.plan.preparedEvidence.wire,
            authorization: held.plan.authorization.wire,
            sourceInventory: sourceInventory(held.preparedSources)}};
        const valuesEvidence = sourceFreeValuesAdmissionEvidence(held.plan);
        if (valuesEvidence !== undefined) return {
          runDefinition: held.plan.runDefinition,
          runAdmissionEvidence: valuesEvidence};
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
    storeAuthorityCid, now, modelController, inferEvidence: evidenceConfiguration,
    faultInjection: authorization?.faultInjection,
    computeConfigurations: {local: localSnapshotConfiguration}});
  dispatchOwner = installNodeClientDispatchOwner({moon, control,
    journal, store, checkpoints, startRun, hostConnection, beforeDispatch,
    observed, prepareAcquisition, planFor, sourceProfile, registry, values,
    faultInjection: authorization?.faultInjection,
    fragment, ordered, namespaceId, authorityScopeCid, storeAuthorityCid, now,
    runInfer, retainedRelationOutput, observation,
    computeConfigurations: {local:localSnapshotConfiguration}});
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
  const openEffectTargetReads = async (facts, {signal, resume, activeResume, journalPort,
    allowDefer = true} = {}) => {
    const selected = installedEffect?.effects === undefined
      ? effectInstallation : selectedInstalledEffect(facts);
    if (typeof selected.targetReadInventory !== 'function') return undefined;
    return effectTargetReadContinuation({checkpoints,
      ...(installedEffect?.effects === undefined ? {} : {
        effectTargetAuthority: selected.targetReadAuthorization}),
      runId: control.runDefinitionRunId(facts.runDefinition),
      runDefinitionCid: facts.ref.runDefinitionCid,
      unitId: moon.clientProgramEffectCompilationUnitId(facts.compilation),
      declaredResults: moon.clientProgramEffectCompilationResultNames(facts.compilation),
      submission: effectSubmissions.get(facts.prepared),
      inventory: selected.targetReadInventory({...facts, moon}), principalId,
      signal, resume, allowDefer, journalPort,
      assertCurrent() {
        if (journal.lookupRunDefinition(facts.ref, moon, control)?.cancellationRequested !== false) {
          throw Object.assign(new Error('ClientRunCancellationRequested'),
            {code: 'ClientRunCancellationRequested'});
        }
        activeResume?.assertCurrent();
      },
    });
  };
  const executeEffectComputation = (facts, sourceResume, targetResume, modelResume) => {
    const activeResume = sourceResume ?? targetResume ?? modelResume;
    const readResume = sourceResume ?? targetResume;
    const parentResume = readResume?.active === true
      ? {claim: readResume.claim, checkpointCid: readResume.view.checkpointCid}
      : modelResume?.parentResume;
    const nextJournal = activeResume?.active !== true ? undefined : {
      ...checkpoints.journal,
      persistCheckpoint: checkpoint => checkpoints.journal.completeResume(
        activeResume.claim, {checkpoint}),
      ...(parentResume === undefined ? {} : {
        modelParentResume: parentResume,
        attachModelCallSetCheckpoint: checkpoint => checkpoints.journal.completeResume(
          parentResume.claim, {checkpoint, attachImmediateModelCallSet: true}),
      }),
    };
    const sourceCheckpoints = targetResume === undefined && modelResume === undefined ? checkpoints : {
      ...checkpoints,
      computationSourceAuthorization: options => checkpoints.computationSourceAuthorization({
        ...options, journalPort: nextJournal}),
    };
    return dispatchOwner.track(facts.ref, {
        run: async ({signal, retainExecution, beginPhysicalWork,
          observePreEffectFailure}) => {
          let targetReads;
          try {
            targetReads = await openEffectTargetReads(facts, {signal,
              resume: targetResume, activeResume, allowDefer: sourceResume === undefined,
              journalPort: modelResume === undefined ? undefined : nextJournal});
          } catch (error) { observePreEffectFailure(); throw error; }
          return effectInstallation.execute(
          Object.freeze({...facts, signal, retainExecution, targetReads, observation,
            beginPhysicalWork, observePreEffectFailure, moon, control,
            assertContinuationCurrent: activeResume?.assertCurrent,
            publicationPlan: facts.preparedExecution,
            store, storeAuthorityCid, authorityScopeCid,
            observeRun: ({ref}) => observeRun({ref, principalId}),
            openComputation: async ({retainComputationOwner} = {}) => {
              if (inferSelections.has(facts.prepared) ||
                  moon.clientProgramEffectPrepareQueryAcquisition(
                facts.prepared, 0, 0)?.$tag === 1) {
                let ownedModelToken;
                try {
                  let retainedModel = modelResume;
                  if (retainedModel === undefined && targetResume !== undefined &&
                      inferSelections.has(facts.prepared) && modelController !== undefined) {
                    activeResume.assertCurrent();
                    const taskIndex = moon.clientProgramInferPlanBoundary(
                      inferSelections.get(facts.prepared).graph)._0;
                    const records = modelController.discover(
                      control.runDefinitionRunId(facts.runDefinition))
                      .filter(record => record.inventory.taskIndex === taskIndex);
                    if (records.length > 1) throw new Error('ModelResumeScopeAmbiguous');
                    if (records.length === 1) {
                      const record = records[0];
                      const token = ownedModelToken = await modelController.prime(record);
                      modelController.state(record.inventory);
                      activeResume.assertCurrent();
                      retainedModel = {record, token, view: targetResume.view};
                    }
                  }
                  const selectedSources = selectAcquiredEffectSources({moon,
                    preparedEffect: facts.prepared, sourceProfile,
                    registry, values, fragment, ordered});
                  const sourceContinuation = acquiredEffectContinuation({
                    checkpoints: (selectedSources.length === 0
                      ? sourceProfile?.realizationKey === 'duckdb-acquired'
                      : selectedSources.every(({adapter}) => adapter.realizationKey === 'duckdb-acquired'))
                      ? sourceCheckpoints : undefined,
                    moon, acquired: facts.preparedExecution,
                    submission: effectSubmissions.get(facts.prepared),
                    declaredResults: moon.clientProgramEffectCompilationResultNames(facts.compilation),
                    unitId: moon.clientProgramEffectCompilationUnitId(facts.compilation),
                    principalId, signal, resume: sourceResume,
                    ...(retainedModel?.token.snapshot.sourceContinuation === undefined ? {} : {
                      restore: {view: retainedModel.view,
                        continuation: retainedModel.token.snapshot.sourceContinuation},
                    }),
                    currentRun: () => journal.lookupRunDefinition(facts.ref, moon, control)
                      ?.cancellationRequested === false});
                  if (retainedModel !== undefined &&
                      moon.clientProgramEffectAcquisitionCount(facts.prepared) > 0 &&
                      retainedModel.token.snapshot.sourceContinuation === undefined) {
                    throw new Error('ModelSourceClosureCustodyUnavailable');
                  }
                  return await openAcquiredEffectComputation({moon,
                    owner: facts.owner, acquired: facts.preparedExecution,
                    sourceProfile, registry, values, fragment, ordered,
                    sourceAccess: sourceProfile?.sourceAccess, signal, now,
                    retainComputationOwner, infer: inferSelections.get(facts.prepared),
                    computeConfigurations: {local: localSnapshotConfiguration},
                    withComputePauseHandler: (configurations, handlePause) => ({
                      ...configurations,
                      local: withLocalExecutionPauseHandler(configurations.local, handlePause),
                    }),
                    store, principalId, faultInjection: authorization?.faultInjection,
                    observe: authorization?.observe, sourceContinuation,
                    modelController, submission: effectSubmissions.get(facts.prepared),
                    existingModel: retainedModel?.record,
                    modelClaim: modelResume?.parentResume === undefined ? modelResume?.claim : undefined,
                    parentResume, modelJournalPort: nextJournal});
                } finally { modelController?.release(ownedModelToken); }
              }
              const setup = moon.clientProgramOpenSourceFreeLocalEffectHost(
                facts.owner, registry, values, 1n, 0n, 0n, 0n,
                fragment, ordered);
              if (setup === undefined) {
                throw new Error('InstalledEffectProgramUnsupported');
              }
              return runCapturedEffectComputation(setup, {}, signal).then(
                execution => Object.freeze({execution, checkedHost: setup}));
            },
            recoverCapture: ({signal: recoverySignal} = {}) =>
              recoverEffectCapture(facts.ref, recoverySignal),
            effectAuthorization: checkpoints === undefined ? undefined : options =>
              checkpoints.effectAuthorization({...options,
                ...(nextJournal === undefined ? {} : {journalPort: nextJournal})}),
            recordReconciliation: (...args) =>
              effectRun.recordReconciliation(...args)}));
        },
        observeStopped: terminalOutcome => {
          recordNodeRunPhysicalStop({ref: facts.ref, journal, moon, control},
            activeResume === undefined ? terminalOutcome : null);
          modelResume?.observeStopped?.();
          if (activeResume !== undefined) activeResume.observedTerminalOutcome = terminalOutcome;
        },
        barrierFailureOutcome: 'failed',
      });
  };
  const effectRun = effectInstallation === undefined ? undefined :
    installNodeClientEffectRun({moon, publicationControl: control, journal,
      now, inferPlanFor: prepared => inferSelections.get(prepared)?.graph,
      ...(installedEffect?.effects === undefined ? {} : {
        validateInstallation(facts) {
          try { selectedInstalledEffect(facts); }
          catch (cause) { throw clientOperationError('ClientProgramUnsupported', cause); }
        },
      }),
      resultPolicyOriginalFor: prepared => {
        if (!inferSelections.has(prepared) ||
            moon.clientProgramEffectAcquisitionCount(prepared) !== 0) {
          return undefined;
        }
        if (installedResultDataPolicy === undefined) {
          throw new TypeError('MissingHostResultDataPolicyOriginal');
        }
        return installedResultDataPolicy;
      },
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
      prepareExecution: ({prepared, compilation, allowed, definition,
        resultPolicyOriginal}) => {
        const sourceFreeInfer = inferSelections.has(prepared) &&
          moon.clientProgramEffectAcquisitionCount(prepared) === 0;
        const retainedResultDataPolicy = sourceFreeInfer
          ? control.admitSourceFreeResultPolicy(
            resultPolicyOriginal, localContractLimits)
          : undefined;
        const options = {moon, control, prepared,
          compilation, allowed, definition, authorityScopeCid, namespaceId,
          storeAuthorityCid, now, resultDataPolicy: retainedResultDataPolicy};
        return inferSelections.has(prepared) ||
          moon.clientProgramEffectPrepareQueryAcquisition(prepared,
          0, 0)?.$tag === 1
          ? acquiredEffectPublicationAdmission(options)
          : sourceFreeEffectPublicationPlan(options);
      },
      execute: executeEffectComputation,
    });
  const runIdOf = accepted => control.runDefinitionRunId(
    accepted.runDefinition?.wire === undefined
      ? journal.lookupRunDefinition(accepted.ref, moon, control).runDefinition
      : accepted.runDefinition);
  const admitEffectDefinition = submission => {
    const {requestId, principalId, connection, kind, input, parameters} = submission;
    effectSubmissions.set(submission.preparedProgram, JSON.parse(canonicalValueJson({
      requestId, principalId, connection, kind, input, parameters,
      ...(submission.submission === undefined ? {} : {submission: submission.submission})}, {dataKeys: true})));
    return effectRun.accept({
    prepared: submission.preparedProgram, authorityScopeCid,
    requestId: submission.requestId, namespaceId,
    principalId: submission.principalId, connection: submission.connection,
    submission: submission.submission,
    lookupExpiresAt: plus(now(), 7 * 24 * 60 * 60 * 1000),
    });
  };
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
        parameters, resultNames,
        ...(submission.submission === undefined ? {} : {submission: submission.submission})};
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
        code: error?.code ?? error?.message, cause: error?.cause});
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
    const selectedModel = inferSelections.get(submission.preparedProgram);
    if (selectedModel?.egressFailure !== undefined &&
        journal.resolveDefinition(requested, {namespaceId}, moon, control) === undefined) {
      diagnostic('infer_preparation_rejected', {boundary: 'model_admission',
        code: selectedModel.egressFailure.code, cause: selectedModel.egressFailure.cause});
      throw clientOperationError('ClientProgramUnsupported', selectedModel.egressFailure);
    }
    if (effectful) {
      return submitEffect(submission, requested, resultNames);
    }
    // A reserved physical start can only be reconciled from its original
    // durable Run. Do this before rebuilding physical source preparations.
    // INFER continues to its existing saved-capture replay owner below.
    const retainedStart = journal.resolveDefinition(requested, {namespaceId}, moon, control);
    if (retainedStart?.physicalStartReserved === true &&
        retainedStart.runAdmissionEvidence?.modelOriginalRunWire !== undefined) {
      // The durable Model owner reopens its original fixed input. Missing
      // inventory after a crash is never permission to reacquire a Source or
      // recompute the prefix through the legacy completed-capture fallback.
      void checkpoints?.sweep();
      return {ref: retainedStart.ref, durability: retainedStart.durability,
        revision: retainedStart.revision};
    }
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
            recordNodeRunPhysicalStop({ref: accepted.ref, journal, moon, control}, null);
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
      parameters: captured.parameters,
      ...(captured.submission === undefined ? {} : {submission: captured.submission})};
    submission.preparedProgram = await prepareSubmit(submission);
    const {requested, resultNames, acquired, acquisitionCount, effectful} = requestOf(submission);
    const preparedSources = acquisitionCount === 2
      ? await prepareAcquisitions(submission.preparedProgram) : undefined;
    const preparedSource = acquired && acquisitionCount !== 2
      ? await prepareAcquisition(submission.preparedProgram) : undefined;
    const reproduced = captureSubmission(submission, resultNames, preparedSource, preparedSources);
    if (canonicalValueJson(reproduced, {dataKeys: true}) !==
        canonicalValueJson(captured, {dataKeys: true})) {
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
          code: error?.code ?? error?.message, cause: error?.cause});
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
  const negotiate = async value => ({version: 'actql-client-host/0.1',
    mode, owner: mode, durability: 'durable',
    ...(value.connection.workspaceId === undefined ? {} : {workspaceId}),
    scopeRef: authorityScopeCid,
    ...(hostConnection(value) ? {submissionEpoch: await submissionService.issueEpoch(value)} : {}),
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
  const submissionService = installNodeClientSubmission({journal, moon,
    authorizedScope: value => hostConnection(value) ? authorizedScope(value) : undefined,
    prepareSubmit, submit, lookupRequest: lookupHeld, checkSubmissionInput: check});
  const checkpointOperations = checkpoints === undefined ? {} : {
    checkpoints: ({principalId: actual, after, limit}) =>
      checkpoints.listCheckpoints({principalId: actual, after, limit}),
    checkpointReview: ({principalId: actual, checkpointCid, maxBytes,
      signal}) => checkpoints.reviewCheckpoint({principalId: actual,
      checkpointCid, maxBytes, signal}),
    async resolve({principalId: actual, items}) {
      const result = await checkpoints.resolve({principalId: actual, items});
      try { if (observation !== undefined) for (const item of result.results) {
        if (item.status !== 'committed') continue;
        const view = checkpoints.journal.inspect(item.checkpointCid);
        if (view?.runDefinitionCid === undefined) continue;
        observation?.emit('approval', 'checkpoint_resolved', {ref: {
          namespaceId, authorityScopeCid, runDefinitionCid: view.runDefinitionCid},
          outcome: 'committed'});
      } } catch { observation?.noteLoss(); }
      return result;
    },
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
          if (checkpoints.effectRunState(runId, ref.runDefinitionCid) !== undefined) {
            continue;
          }
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
        if (!['effect_set', 'read_access'].includes(view.kind) || view.prepareAttemptId !== null ||
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
  const sweepEffectRuns = async ({reconcileRef} = {}) => {
    if (effectRun === undefined || checkpoints === undefined) return false;
    let busy = false;
    // A requested observation owns only its original Run. Global capture
    // retirement belongs to ordinary sweeps and final Host shutdown.
    try { if (reconcileRef === undefined) await retireIncompleteEffects(); }
    catch (error) {
      busy = true;
      diagnostic('effect_capture_retirement_failed', {
        code: error?.code ?? error?.message});
    }
    let after = '';
    for (;;) {
      const page = checkpoints.journal.listRunCheckpoints({after, limit: 100});
      for (const view of page) {
        if (reconcileRef !== undefined &&
            (view.runDefinitionCid !== reconcileRef.runDefinitionCid ||
             view.kind !== 'effect_set')) continue;
        if (!['effect_set', 'read_access'].includes(view.kind) || view.prepareAttemptId !== null) {
          continue;
        }
        const key = view.runDefinitionCid;
        const ref = Object.freeze({namespaceId, authorityScopeCid,
          runDefinitionCid: key});
        if (await cancelEffectContinuation(ref)) {
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
        const observing = reconcileRef !== undefined && runStatus === 'needs_reconciliation';
        if (runStatus !== 'resuming' && !observing) continue;
        if (!observing && checkpoints.journal.currentResume(view.checkpointCid)?.state === 'completed') continue;
        if (effectResumeFlights.has(key) ||
            dispatchOwner.operation(ref) !== undefined) {
          busy = true;
          if (observing && effectResumeFlights.has(key)) {
            await effectResumeFlights.get(key);
          }
          continue;
        }
        try {
          const retained = journal.lookupRunDefinition(ref, moon, control);
          if (retained === undefined ||
              retained.runDefinition.identity !== key) {
            throw new Error('EffectResumeRunDefinitionMissing');
          }
          if (view.kind === 'read_access') {
            // Check before claiming: changed bindings must not turn an
            // earlier entered physical continuation into an unsent failure.
            // Retained inputs cannot prove that later work never started.
            if (checkpoints.journal.hasStartedResume(view.checkpointCid)) {
              // Another owner can publish after this observation. Keep the
              // existing sweep alive without authorizing another execution.
              busy = true;
              const reconciliation = effectRun.reconciliation(ref);
              if (reconciliation !== undefined) {
                checkpoints.journal.settleObservedEffectResume(view.checkpointCid,
                  ref.runDefinitionCid, JSON.stringify(reconciliation));
                continue;
              }
              if (await store.confirmCommittedIndex(ref) !== undefined) {
                const published = await inspectAuthorizedRunState(stateService,
                  {indexKey: ref, principalId, purpose: 'inspect'});
                if (published.status === 'succeeded') {
                  checkpoints.journal.settleObservedEffectResume(view.checkpointCid,
                    ref.runDefinitionCid, JSON.stringify(published));
                  busy = true;
                }
              }
              continue;
            }
            const claimed = checkpoints.journal.claimResume(view.runId, {
              claimant: `source-host-${process.pid}-${randomUUID()}`,
              leaseMs: authorization?.leaseMs ?? 60000,
              binding: checkpoints.binding, preserveStarted: true,
              expectedCheckpointCid: view.checkpointCid});
            if (claimed.action !== 'claimed') {
              if (claimed.action === 'admitted' || claimed.action === 'busy') busy = true;
              continue;
            }
            if (claimed.checkpointCid !== view.checkpointCid) continue;
            const flight = (async () => {
              let sourceResume;
              let targetResumption = false;
              let leaseFailure;
              const leaseMs = authorization?.leaseMs ?? 60000;
              const renewal = setInterval(() => {
                try {
                  if (checkpoints.journal.currentResume(view.checkpointCid)?.state ===
                      'completed') return;
                  checkpoints.journal.renewResume(claimed.claim, leaseMs);
                }
                catch (error) { leaseFailure = error; }
              }, Math.max(1, Math.min(1000, Math.floor(leaseMs / 3))));
              renewal.unref?.();
              try {
                const continuation = await checkpoints.runUnitReadContinuation(view);
                targetResumption = continuation.version === EFFECT_TARGET_CONTINUATION;
                const submission = {...continuation.submission};
                submission.preparedProgram = await prepareSubmit(submission);
                const request = requestOf(submission);
                if (!request.effectful || !targetResumption && inferSelections.has(submission.preparedProgram)) {
                  throw new Error('UnsupportedAcquiredEffectContinuation');
                }
                const accepted = await admitEffectDefinition(submission);
                if (accepted.ref.runDefinitionCid !== ref.runDefinitionCid) {
                  throw new Error('EffectContinuationRunMismatch');
                }
                const facts = await effectRun.restoreComputation(accepted);
                sourceResume = {claim: claimed.claim, view, continuation, active: true,
                  assertCurrent() {
                    if (leaseFailure !== undefined) throw leaseFailure;
                    if (journal.lookupRunDefinition(ref, moon, control)?.cancellationRequested) {
                      throw Object.assign(new Error('ClientRunCancellationRequested'),
                        {code: 'ClientRunCancellationRequested'});
                    }
                    return checkpoints.journal.admitResume(claimed.claim,
                      {checkpointCid: view.checkpointCid});
                  }};
                const result = await executeEffectComputation(facts,
                  targetResumption ? undefined : sourceResume,
                  targetResumption ? sourceResume : undefined);
                // Resume exits only through the existing terminal outcome
                // or atomic next-Checkpoint transition, never a fabricated
                // resuming-to-running intermediate public state.
                if (checkpoints.journal.getRunState(view.runId)?.status === 'resuming') {
                  const ended = effectRun.reconciliation(ref) ?? await observeRun({ref, principalId});
                  if (terminal(ended.status) || ended.status === 'needs_reconciliation') {
                    const {control: _control, ...state} = ended;
                    checkpoints.journal.completeResume(claimed.claim, {
                      runStateWire: JSON.stringify(state)});
                  } else if (['failed_without_effect_dispatch', 'failed_effect_set']
                    .includes(result?.status)) {
                    checkpoints.journal.completeResume(claimed.claim, {status: 'failed'});
                  }
                }
              } catch (error) {
                if (['ResumeClaimStale', 'PriorAdmissionUnresolved'].includes(error?.code) ||
                    error.authorization?.detail === 'ResumeClaimStale') throw error;
                const refusal = (targetResumption
                  ? checkpoints.journal.refuseUnsentReadResume
                  : checkpoints.journal.refuseUnsentSourceResume)(
                  view.checkpointCid, view.runDefinitionCid, claimed.claim);
                // A started source with an unresolved physical owner stays
                // with its original claim and custody. Never reacquire it.
                if (refusal.outcome === 'admitted' &&
                    ['failed', 'cancelled'].includes(sourceResume?.observedTerminalOutcome)) {
                  checkpoints.journal.completeResume(claimed.claim, {
                    status: sourceResume.observedTerminalOutcome});
                }
                throw error;
              } finally {
                clearInterval(renewal);
              }
            })();
            effectResumeFlights.set(key, flight);
            void flight.catch(error => diagnostic('source_resume_failed', {
              ref, code: error?.code ?? error?.message,
              detail: error.authorization?.detail,
              cause: error.authorization?.error?.code,
              missingModule: error?.code === 'ERR_MODULE_NOT_FOUND' ? error.url : undefined})).finally(() => {
              effectResumeFlights.delete(key);
              if (checkpoints.journal.getRunState(view.runId)?.status !== 'resuming') {
                void checkpoints.sweep();
              }
            });
            busy = true;
            continue;
          }
          const continuation = await checkpoints.effectContinuation(view);
          const flight = dispatchOwner.track(ref, {
            run: ({signal, retainExecution, beginPhysicalWork}) =>
              effectInstallation.resume(Object.freeze({ref, view, observation,
                reconciliationOnly: observing,
                continuation, retained, moon, control, store,
                storeAuthorityCid, authorityScopeCid, signal,
                retainExecution, beginPhysicalWork,
                observeRun: ({ref}) => observeRun({ref, principalId}),
                recoverCapture: ({signal: recoverySignal} = {}) =>
                  recoverEffectCapture(ref, recoverySignal),
                checkpointJournal: checkpoints.journal,
                checkpointBinding: checkpoints.binding,
                effectAuthorization: checkpoints.effectAuthorization,
                prepareTargetReads: async claimed => {
                  const records = await checkpoints.inspectEffectTargetApprovals(
                    view.runId, ref.runDefinitionCid);
                  const capturedTarget = continuation.target_read_binding;
                  if (records.length === 0 && capturedTarget === undefined) return undefined;
                  if (capturedTarget !== undefined) assertEffectTargetReadBinding(capturedTarget);
                  const submission = {...(capturedTarget?.submission ?? records[0].continuation.submission)};
                  submission.preparedProgram = await prepareSubmit(submission);
                  if (!requestOf(submission).effectful) throw new Error('EffectContinuationRunMismatch');
                  const accepted = await admitEffectDefinition(submission);
                  if (accepted.ref.runDefinitionCid !== ref.runDefinitionCid) {
                    throw new Error('EffectContinuationRunMismatch');
                  }
                  const facts = await effectRun.restoreComputation(accepted);
                  const reads = await openEffectTargetReads(facts, {signal, allowDefer: false,
                    activeResume: {assertCurrent() {
                      return checkpoints.journal.admitResume(claimed.claim,
                        {checkpointCid: view.checkpointCid});
                    }}});
                  try {
                    if (capturedTarget !== undefined) {
                      assertEffectTargetReadBinding(reads?.captureBinding(), capturedTarget);
                    }
                  } catch (error) { reads?.close(); throw error; }
                  return reads;
                },
                recordReconciliation: (...args) =>
                  effectRun.recordReconciliation(...args)})),
            // The original Compute stopped before the Effect Checkpoint.
            // Its nonterminal stop observation is immutable. Effect failure
            // and reconciliation belong to the Checkpoint and Effect owners.
            observeStopped: () => recordNodeRunPhysicalStop({ref, journal, moon, control}, null),
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
          if (observing) await flight;
        } catch (error) {
          diagnostic('effect_resume_failed', {ref,
            code: error?.code ?? error?.message});
          if (reconcileRef !== undefined) throw error;
        }
        busy = true;
      }
      if (page.length < 100) break;
      after = page.at(-1).checkpointCid;
    }
    return busy;
  };
  const reconcile = async ({ref, principalId: actual, connection, signal}) => {
    if (!hostConnection({principalId: actual, connection, ref})) {
      throw clientOperationError('RunStateAccessDenied');
    }
    signal?.throwIfAborted();
    const state = await observeRun({ref, principalId: actual});
    // An explicit Effect observation never restarts Compute, reopens approval
    // or converts an execution-unknown Run into an invented Effect inventory.
    if (state.status === 'needs_reconciliation' &&
        state.next_action?.kind === 'reconcile') {
      await sweepEffectRuns({reconcileRef: ref});
    }
    return observeRun({ref, principalId: actual});
  };
  const modelResumeFlights = new Map();
  const sweepModelRuns = async () => {
    if (modelController === undefined || checkpoints === undefined) return false;
    let busy = false;
    let after = '';
    for (;;) {
      const page = checkpoints.journal.discoverModelCallSets({after, limit: 100});
      for (const record of page) {
        let token, transferred = false;
        try {
          const originalOwner = modelController.verifier.admitOriginalRun({
            originalRunWire: record.originals.originalRunWire});
          if (originalOwner.runId !== record.inventory.runId ||
              originalOwner.runDefinitionCid !== record.inventory.runDefinitionCid) {
            throw new Error('ModelResumeRunDefinitionMismatch');
          }
          const prior = checkpoints.journal.getRunState(originalOwner.runId);
          if (prior !== undefined && checkpoints.journal.isTerminalRunOutcome(prior.status) &&
              !checkpoints.journal.hasUnresolvedModelCalls(originalOwner.runId)) {
            // Terminal scopes with no unknown attempts may already have had
            // their private input retired. Discovery is not a new read grant.
            modelController.retire(record);
            continue;
          }
          // Discovery is routing only. Authenticate original Store custody,
          // re-admit the entire inventory, then repair saved response markers
          // before inspecting cancellation or current send permission.
          token = await modelController.prime(record);
          let calls = checkpoints.journal.readModelCalls(record.inventory);
          for (const slot of calls.slots) for (const entry of slot.attempts) {
            await modelController.observe(entry);
          }
          calls = checkpoints.journal.readModelCalls(record.inventory);
          const runId = calls.runId;
          const ref = Object.freeze({namespaceId, authorityScopeCid,
            runDefinitionCid: calls.runDefinitionCid});
          const retained = journal.lookupRunDefinition(ref, moon, control);
          if (retained === undefined || retained.runDefinition.identity !== calls.runDefinitionCid ||
              retained.runAdmissionEvidence?.modelOriginalRunWire !== record.originals.originalRunWire) {
            throw new Error('ModelResumeRunDefinitionMissing');
          }
          if (modelResumeFlights.has(ref.runDefinitionCid) || dispatchOwner.operation(ref) !== undefined) {
            busy = true;
            continue;
          }
          const unresolved = checkpoints.journal.hasUnresolvedModelCalls(runId);
          if (retained.cancellationRequested) {
            checkpoints.journal.fenceRunCancellation({originalRunWire: record.originals.originalRunWire});
            await cancelEffectContinuation(ref);
            if (unresolved) busy = true;
            continue;
          }
          const runState = checkpoints.journal.getRunState(runId);
          if (runState === undefined) throw new Error('ModelResumeRunStateMissing');
          if (checkpoints.journal.isTerminalRunOutcome(runState.status)) {
            if (unresolved) busy = true;
            continue;
          }
          const active = checkpoints.journal.activeRunCheckpoint(runId);
          const parentCheckpoint = record.checkpointCid === null && active?.kind === 'read_access'
            ? active : undefined;
          if (active !== undefined && parentCheckpoint === undefined && (active.kind !== 'model_invocation' ||
              active.checkpointCid !== record.checkpointCid)) {
            // A later Source/Effect continuation owns this same Run now.
            if (unresolved) busy = true;
            continue;
          }
          let claim;
          const claimCheckpointCid = record.checkpointCid ?? parentCheckpoint?.checkpointCid;
          if (claimCheckpointCid !== undefined) {
            if (runState.status !== 'resuming' || active === undefined) {
              if (unresolved) busy = true;
              continue;
            }
            const claimed = checkpoints.journal.claimResume(runId, {
              claimant: `model-host-${process.pid}-${randomUUID()}`,
              leaseMs: authorization?.leaseMs ?? 60000, binding: checkpoints.binding,
              expectedCheckpointCid: claimCheckpointCid});
            if (claimed.action !== 'claimed') {
              if (['busy', 'admitted'].includes(claimed.action)) busy = true;
              continue;
            }
            claim = claimed.claim;
          } else if (runState.status !== 'running') {
            if (unresolved) busy = true;
            continue;
          }
          let leaseFailure;
          const leaseMs = authorization?.leaseMs ?? 60000;
          const renewal = claim === undefined ? undefined : setInterval(() => {
            try { checkpoints.journal.renewResume(claim, leaseMs); }
            catch (error) {
              leaseFailure = error;
              dispatchOwner.cancel(ref);
            }
          }, Math.max(1, Math.min(1000, Math.floor(leaseMs / 3))));
          renewal?.unref?.();
          const assertCurrent = () => {
            if (leaseFailure !== undefined) throw leaseFailure;
            if (journal.lookupRunDefinition(ref, moon, control)?.cancellationRequested !== false) {
              throw new Error('ClientRunCancellationRequested');
            }
            // Ownership only here. Model send permission is checked by its
            // own activation and per-call entry; Effect approval is separate.
            if (claim !== undefined) checkpoints.journal.renewResume(claim, leaseMs);
          };
          let restorationDispatchEntered = false;
          let restorationStopConfirmed = false;
          // An older physical-close record cannot acknowledge a new
          // continuation's reclamation. Only its current owner can do that.
          const restorationReclaimed = () => !restorationDispatchEntered || restorationStopConfirmed;
          const retainStoppedModelReconciliation = () => {
            const stopped = journal.lookupRunDefinition(ref, moon, control);
            if (!checkpoints.journal.hasUnresolvedModelCalls(runId) ||
                effectRun?.reconciliation(ref) !== undefined ||
                !restorationReclaimed() || stopped?.physicalCloseConfirmed !== true ||
                dispatchOwner.operation(ref) !== undefined) return false;
            const reconciliation = issueInstalledUnpublishedRunState(moon, {runId,
              observedAt: now(), resultNames: stopped.resultNames,
              dispatchReserved: true, preDispatchFailureConfirmed: false,
              cancelledBeforeStart: false, observedTerminalOutcome: 'none',
              executionUnknown: true});
            if (journal.lookupRunDefinition(ref, moon, control)?.revision !== stopped.revision) return false;
            const lifecycle = checkpoints.journal.getRunState(runId);
            if (claim !== undefined && lifecycle?.status === 'resuming' && leaseFailure === undefined) {
              checkpoints.journal.completeResume(claim, {runStateWire: JSON.stringify(reconciliation)});
            } else if (claim === undefined && lifecycle?.status === 'running') {
              checkpoints.journal.finishRun(runId, {status: 'needs_reconciliation',
                runStateWire: JSON.stringify(reconciliation)});
            }
            return checkpoints.journal.getRunState(runId)?.status === 'needs_reconciliation';
          };
          const runRestoredModel = async () => {
            assertCurrent();
            const current = journal.lookupRunDefinition(ref, moon, control);
            const submission = JSON.parse(canonicalValueJson(token.snapshot.submission));
            if (submission.requestId !== current.requestId ||
                !hostConnection(submission)) throw new Error('ModelResumeSubmissionMismatch');
            submission.preparedProgram = await prepareSubmit(submission);
            const requested = requestOf(submission);
            const admitted = journal.resolveDefinition(requested.requested,
              {namespaceId}, moon, control);
            if (admitted?.ref.runDefinitionCid !== ref.runDefinitionCid) {
              throw new Error('ModelResumeRunDefinitionMismatch');
            }
            assertCurrent();
            if (requested.effectful) {
              if (effectRun === undefined) throw new Error('InstalledEffectContinuationUnavailable');
              const accepted = await admitEffectDefinition(submission);
              if (accepted.ref.runDefinitionCid !== ref.runDefinitionCid) {
                throw new Error('ModelResumeRunDefinitionMismatch');
              }
              const facts = await effectRun.restoreComputation(accepted);
              assertCurrent();
              const modelResume = {record, token, claim, active: claim !== undefined,
                view: record.checkpointCid === null ? Object.freeze({kind: 'model_invocation',
                  prepareAttemptId: null, runId, runDefinitionCid: ref.runDefinitionCid}) : active,
                ...(parentCheckpoint === undefined ? {} : {parentResume: {
                  claim, checkpointCid: parentCheckpoint.checkpointCid}}),
                assertCurrent, observeStopped: () => { restorationStopConfirmed = true; }};
              restorationDispatchEntered = true;
              return executeEffectComputation(facts, undefined, undefined, modelResume);
            }
            if (parentCheckpoint !== undefined) throw new Error('ModelReadParentRunMismatch');
            const plan = planFor(submission, current.runDefinition.wire);
            if (originalModelRunWire(plan.compiled, plan.runDefinition) !== record.originals.originalRunWire) {
              throw new Error('ModelResumeOriginalAdmissionChanged');
            }
            restorationDispatchEntered = true;
            return dispatchOwner.track(ref, {
              run: async ({signal, retainExecution, beginPhysicalWork}) => {
                assertCurrent();
                signal.throwIfAborted();
                return runInfer({preparedProgram: submission.preparedProgram, plan,
                  store, principalId, signal, retainExecution, beginPhysicalWork,
                  submission: token.snapshot.submission, existingModel: record, modelClaim: claim});
              },
              observeStopped: async () => {
                await observeNodeRestoredModelStop({ref,
                  journal, store, checkpoints, moon, control, cleanupConfirmed: true,
                  physicalStopConfirmed: true});
                restorationStopConfirmed = true;
              },
            });
          };
          const flight = runRestoredModel().then(async result => {
            if (leaseFailure !== undefined) throw leaseFailure;
            if (result?.status === 'waiting_checkpoint') return;
            const lifecycle = checkpoints.journal.getRunState(runId);
            if (result?.status === 'needs_reconciliation') {
              const unresolvedModel = checkpoints.journal.hasUnresolvedModelCalls(runId);
              const effectReconciliation = effectRun?.reconciliation(ref);
              // This restoration returned only after its physical Owner's
              // stop and cleanup. Retain its unresolved outcome in the same
              // Run journal, so later sweeps do not reopen a Running frame.
              if (unresolvedModel) {
                retainStoppedModelReconciliation();
                return;
              }
              const reconciliation = effectReconciliation;
              if (reconciliation !== undefined) {
                if (claim !== undefined && lifecycle?.status === 'resuming') {
                  checkpoints.journal.completeResume(claim,
                    {runStateWire: JSON.stringify(reconciliation)});
                } else if (claim === undefined && lifecycle?.status === 'running') {
                  checkpoints.journal.finishRun(runId, {status: 'needs_reconciliation',
                    runStateWire: JSON.stringify(reconciliation)});
                }
              }
              return;
            }
            if (['failed_without_effect_dispatch', 'failed_effect_set'].includes(result?.status)) {
              if (!checkpoints.journal.hasUnresolvedModelCalls(runId) &&
                  dispatchOwner.operation(ref) === undefined) {
                if (claim !== undefined && lifecycle?.status === 'resuming') {
                  checkpoints.journal.completeResume(claim, {status: 'failed'});
                } else if (claim === undefined && lifecycle?.status === 'running') {
                  checkpoints.journal.finishRun(runId, {status: 'failed'});
                }
              }
              return;
            }
            if (await store.confirmCommittedIndex(ref) === undefined) return;
            const published = await inspectAuthorizedRunState(stateService,
              {indexKey: ref, principalId, purpose: 'inspect'});
            if (published.status !== 'succeeded') return;
            const current = checkpoints.journal.getRunState(runId);
            if (claim !== undefined && current?.status === 'resuming') {
              checkpoints.journal.completeResume(claim, {runStateWire: JSON.stringify(published)});
            } else if (claim === undefined && current?.status === 'running') {
              checkpoints.journal.finishRun(runId, {status: 'succeeded',
                runStateWire: JSON.stringify(published)});
            }
          }).catch(async error => {
            const code = error?.code ?? error?.message;
            // Cancellation can win before this restoration physically enters.
            // Its confirmed prior stop still retains unknown Model responsibility;
            // it must not leave a Running journal that only public lookup projects.
            if (retainStoppedModelReconciliation()) return;
            const stopped = journal.lookupRunDefinition(ref, moon, control);
            if (stopped?.physicalCloseConfirmed === true &&
                await confirmNodeRunCancellation({ref, journal, store, checkpoints,
                  moon, control, cleanupConfirmed: restorationReclaimed(),
                  physicalStopConfirmed: stopped.physicalCloseConfirmed}) &&
                restorationReclaimed() &&
                journal.lookupRunDefinition(ref, moon, control)?.revision === stopped.revision) {
              const state = checkpoints.journal.getRunState(runId);
              if (claim !== undefined && state?.status === 'resuming' && leaseFailure === undefined) {
                checkpoints.journal.completeResume(claim, {status: 'cancelled'});
              } else if (claim === undefined && state?.status === 'running') {
                checkpoints.journal.finishRun(runId, {status: 'cancelled'});
              }
              return;
            }
            if (code === 'ModelSavedTerminalFailure' && stopped?.physicalCloseConfirmed === true && restorationReclaimed() &&
                !checkpoints.journal.hasUnresolvedModelCalls(runId)) {
              const state = checkpoints.journal.getRunState(runId);
              if (claim !== undefined && state?.status === 'resuming' && leaseFailure === undefined) {
                checkpoints.journal.completeResume(claim, {status: 'failed'});
              } else if (claim === undefined && state?.status === 'running') {
                checkpoints.journal.finishRun(runId, {status: 'failed'});
              }
              return;
            }
            const detail = error?.authorization?.detail;
            const policyRefusal = error?.authorization?.action === 'deny' ||
              ['ApprovalExpired', 'ModelRunExpired', 'ModelProviderBindingChanged',
                'ModelCheckpointConfigurationChanged', 'InstalledInferAuthorityUnavailable',
                'InstalledModelEgressUnavailable'].includes(code) ||
              ['ApprovalExpired', 'ModelRunExpired'].includes(detail);
            if (claim !== undefined && parentCheckpoint === undefined && policyRefusal && leaseFailure === undefined &&
                dispatchOwner.operation(ref) === undefined) {
              try {
                const current = checkpoints.journal.readModelCalls(record.inventory);
                if (current.slots.every(slot => slot.attempts.length === 0)) {
                  checkpoints.journal.refuseUnsentModelResume(record.checkpointCid,
                    ref.runDefinitionCid, claim);
                }
              } catch (failure) {
                diagnostic('model_refusal_unresolved', {ref,
                  code: failure?.code ?? failure?.message});
              }
            }
            diagnostic('model_resume_failed', {ref, code});
          }).finally(() => {
            if (renewal !== undefined) clearInterval(renewal);
            modelResumeFlights.delete(ref.runDefinitionCid);
            modelController.release(token);
          });
          transferred = true;
          modelResumeFlights.set(ref.runDefinitionCid, flight);
          busy = true;
        } catch (error) {
          busy = true;
          diagnostic('model_recovery_failed', {scopeCid: record.scopeCid,
            code: error?.code ?? error?.message});
        } finally { if (!transferred) modelController.release(token); }
      }
      if (page.length < 100) break;
      after = page.at(-1).scopeCid;
    }
    return busy;
  };
  const hostOperations = {
    observe: observed,
    // A service Workspace is an installed network target label. It does not
    // replace the Local namespace, root-derived authority scope or policy.
    workspaceForPrincipal: () => workspaceId,
    authorizeConnection: value => checkpointOperation.has(value.operation)
      ? checkpointConnection(value)
      : hostConnection(value) || value.operation === 'connect' &&
        checkpointConnection(value),
    negotiate, prepareSubmit, check, attach,
    // New execution requires the authenticated original intent. Historical
    // request/Run observation remains available without relabeling its identity.
    submit: async () => {throw clientOperationError('ClientSubmissionReferenceRequired');},
    submitIntent: submissionService.submitIntent,
    lookupSubmission: submissionService.lookupSubmission,
    lookupRequest: lookupHeld,
    stateService, resultService, observeRun, wait, reconcile, cancel, lookupCancellation, cancelRequest,
    ...checkpointOperations,
    // Discovery of the installed source, when its adapter serves it.
    ...(sourceProfile?.discovery ?? {}),
  };
  if (checkpoints !== undefined) {
    await checkpoints.start({inspect: inspectHeld, resume: resumeHeld,
      abandon: abandonHeld, observe: observeHeldRun,
      cancelRun: cancelHeldRun,
      models: modelController === undefined ? undefined : {
        sweep: sweepModelRuns,
        drain: () => Promise.allSettled([...modelResumeFlights.values()]),
      },
      effects: effectRun === undefined ? undefined :
        {sweep: sweepEffectRuns}});
  }
  const ingress = createNodeInProcessClientHost({
    authenticate: () => principalId,
    ...hostOperations, maxRowBytes: 1024 * 1024,
  });
  const port = observation === undefined ? ingress : Object.freeze({
    perform: (operation, request, signal) => observation.run(operation,
      undefined, () => ingress.perform(operation, request, signal)),
  });
  return {port, store, journal, hostOperations, checkpoints, diagnostic,
    observation,
    dispatchOwner, inspectAcquisition, sourceProfile, installedEffect,
    retireTerminalEffects};
  } catch (cause) {
    diagnostic?.close();
    effectEvidenceKey?.key.fill(0);
    throw await retainInstalledHostInitializationFailure(cause,
      {journal, store, checkpoints, dispatchOwner,
        sourceProfile, installedEffect, observation});
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
  authenticate, beforeDispatch, authorization, workspaceId, connectorTable,
  sourceProfilePath, sourceProfilePaths,
  loopbackHttp = false,
  resolveSourceSecret, effectProfilePath, effectProfilePaths, resolveEffectSecret,
  effectInstallation, modelInstallation, registerModelProviders,
  resultDataPolicy, inferEvidence, retainedRelationOutput, hostCapacityPolicy, valuesMaxRows, observation}) {
  hostCapacityPolicy = snapshotHostCapacityPolicy(hostCapacityPolicy);
  if (typeof directory !== 'string' || !directory ||
      typeof authenticate !== 'function' ||
      typeof loopbackHttp !== 'boolean' ||
      beforeDispatch !== undefined && typeof beforeDispatch !== 'function') {
    throw new TypeError('InvalidInstalledRemoteHost');
  }
  const host = await openInstalledHost({root: resolve(directory), mode: 'remote',
    workspaceId,
    beforeDispatch, authorization, connectorTable, sourceProfilePath, sourceProfilePaths, resolveSourceSecret,
    effectProfilePath, effectProfilePaths, resolveEffectSecret, effectInstallation,
    modelInstallation, registerModelProviders, resultDataPolicy, inferEvidence,
    retainedRelationOutput, hostCapacityPolicy, valuesMaxRows, observation});
  const handle = createClientHttpHandler({
    ...host.hostOperations, authenticate, maxRequestBytes: 65536, loopbackHttp,
  });
  // A request's handling can outlive its response: a Result read records
  // its delivery attempt after the last bytes are sent. Close waits for
  // every request still being handled; once closing, new requests are
  // refused before they touch the Store.
  const handling = new Set();
  let closing = false;
  const shutdown = installedHostShutdown(host);
  return Object.freeze({
    handler(request, response) {
      if (closing) {
        response.writeHead(503, {'content-type': 'application/json'});
        response.end(JSON.stringify({code: 'ClientHostClosing'}));
        return Promise.resolve();
      }
      const handled = Promise.resolve(host.observation === undefined
        ? handle(request, response) : host.observation.run('http',
          observationTraceParent(request.headers), () => handle(request, response),
          {http: {method: request.method, response}}));
      handling.add(handled);
      handled.finally(() => handling.delete(handled)).catch(() => {});
      return handled;
    },
    inspectAcquisition: host.inspectAcquisition,
    observationStatus: () => host.observation?.status(),
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
  resolveSourceSecret, signal, connectorTable} = {}) {
  if (connectorTable !== undefined) assertInstalledConnectorTable(connectorTable);
  const root = directory === undefined ? localStateRoot() : resolve(directory);
  await admitHostRootFormat(root);
  const moon = await import(runtimeUrl.href);
  return publishInstalledSourceProfile(
    sourceProfilePath ?? process.env.ACTQL_LOCAL_SOURCE_PROFILE, {root,
      principalId: userInfo().username, moon, runtimeUrl,
      resolveSecret: resolveSourceSecret, signal, connectorTable});
}

// Publish the installed Effect's generation (its declaration, execution
// Mappings and Check Environment) for a Host state directory (the embedded
// Local Host's by default) from its Effect profile
// (`ACTQL_LOCAL_EFFECT_PROFILE` by default). This is the explicit step a Host
// start restores without provider I/O.
export async function publishInstalledEffect({effectProfilePath, directory,
  resolveEffectSecret, signal, hostCapacityPolicy, connectorTable} = {}) {
  if (connectorTable !== undefined) assertInstalledConnectorTable(connectorTable);
  hostCapacityPolicy = snapshotHostCapacityPolicy(hostCapacityPolicy);
  const root = directory === undefined ? localStateRoot() : resolve(directory);
  await admitHostRootFormat(root);
  const moon = await import(runtimeUrl.href);
  const baseEnvironmentWire = selectInstalledHostEnvironment(moon, (await readFile(join(packageRoot,
    'spec/local-check-environment.json'), 'utf8')).trimEnd(), hostCapacityPolicy);
  return publishInstalledEffectProfile(
    effectProfilePath ?? process.env.ACTQL_LOCAL_EFFECT_PROFILE, {root,
      principalId: userInfo().username, moon, runtimeUrl,
      baseEnvironmentWire, resolveSecret: resolveEffectSecret, signal, connectorTable});
}

export async function connectEmbeddedLocal(options) {
  let installation = options?.installation;
  if (installation !== undefined && (installation === null ||
      typeof installation !== 'object' || Array.isArray(installation))) {
    throw new TypeError('InvalidInstalledHostOptions');
  }
  if (installation?.retainedRelationOutput !== undefined &&
      typeof installation.retainedRelationOutput !== 'boolean') {
    throw new TypeError('InvalidLocalRetainedOutputConfiguration');
  }
  if (installation !== undefined) {
    const {hostCapacityPolicy: selected, valuesMaxRows, ...rest} = installation;
    validateValuesMaxRows(valuesMaxRows);
    const hostCapacityPolicy = snapshotHostCapacityPolicy(selected);
    installation = {...rest, hostCapacityPolicy, valuesMaxRows};
    if (installation.effectProfilePaths !== undefined) {
      installation.effectProfilePaths = installedEffectPaths(installation);
    }
  }
  const root = installation?.directory === undefined ? localStateRoot() :
    resolve(installation.directory);
  const identity = await embeddedInstallationIdentity(root, installation);
  const {installation: _installation, ...clientOptions} = options;
  return profiles.connect(root, identity,
    () => openInstalledHost({root, authorization: installation?.authorization,
        connectorTable: installation?.connectorTable,
        sourceProfilePath: installation?.sourceProfilePath,
        sourceProfilePaths: installation?.sourceProfilePaths,
        resolveSourceSecret: installation?.resolveSourceSecret,
        effectProfilePath: installation?.effectProfilePath,
        effectProfilePaths: installation?.effectProfilePaths,
        resolveEffectSecret: installation?.resolveEffectSecret,
        modelInstallation: installation?.modelInstallation,
        registerModelProviders: installation?.registerModelProviders,
        resultDataPolicy: installation?.resultDataPolicy,
        inferEvidence: installation?.inferEvidence,
        hostCapacityPolicy: installation?.hostCapacityPolicy,
        retainedRelationOutput: installation?.retainedRelationOutput,
        observation: installation?.observation,
        valuesMaxRows: installation?.valuesMaxRows}), clientOptions);
}
