// One installed Local Host for the current OS user. The Client talks to the
// Host in process; the journal and publication Store own durable physical I/O.
import {createHash} from 'node:crypto';
import {mkdir, readFile} from 'node:fs/promises';
import {homedir, userInfo} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {prepareCapturedDuckDBSource} from
  './captured-duckdb-source.mjs';
import {loadInstalledDuckDBSource} from './installed-duckdb-source.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {retainInstalledHostInitializationFailure} from
  './installed-host-cleanup.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from './result-access.mjs';
import {installRunStateAuthority, installRunStateService,
  inspectAuthorizedRunState} from '../host-common/run-state-access.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {localContractLimits, localOutputLimits,
  sourceFreeValuesPlan, acquiredTaskRunAdmission} from
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

async function openInstalledHost(root, mode = 'local', beforeDispatch,
  authorization, sourceProfilePath) {
  await mkdir(root, {recursive: true, mode: 0o700});
  const moon = await import(runtimeUrl.href);
  const control = runtimeCore(moon).publicationControl;
  const principalId = userInfo().username;
  const sourceProfile = await loadInstalledDuckDBSource(
    sourceProfilePath ?? process.env.ACTQL_LOCAL_SOURCE_PROFILE,
    {root, principalId});
  const environmentWire = sourceProfile?.environmentWire ??
    (await readFile(join(packageRoot,
      'spec/local-check-environment.json'), 'utf8')).trimEnd();
  const evidenceCid = JSON.parse(environmentWire).evidence_bundle_cid;
  const environment = moon.clientProgramCheckEnvironment(environmentWire,
    evidenceCid, false, false, true, false, false, false, false);
  if (environment === undefined) {
    throw new Error('InvalidInstalledLocalEnvironment');
  }
  const registry = await readFile(join(packageRoot,
    'spec/dependencies/aoa-pipeline-registry.json'), 'utf8');
  const aoa = JSON.parse(await readFile(join(packageRoot,
    'spec/contracts/actql-aoa.json'), 'utf8'));
  const values = JSON.stringify(aoa.execution_contracts['REL.values']);
  const fragment = JSON.stringify(
    aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
  const ordered = JSON.stringify(
    aoa.execution_contracts['REL.derive.ordered']);
  const tenantId = 'local';
  const authorityScopeCid = cid({version: 'actql-local-owner-scope/0.1',
    root, principalId});
  const storeAuthorityCid = cid({version: 'actql-local-store-owner/0.1',
    root, principalId});
  const journalDirectory = join(root, 'requests');
  await mkdir(journalDirectory, {recursive: true, mode: 0o700});
  const journal = openClientRequestJournal(journalDirectory);
  let store;
  let checkpoints;
  let dispatchOwner;
  try {
    store = await openLocalPublicationStore({
      directory: join(root, 'publication'), storeAuthorityCid,
      capacityBytes: 512 * 1024 * 1024,
      maxObjectBytes: localOutputLimits.maxWireBytes,
      maxObjects: 10000, maxContractNodes: 10000,
      maxContractDepth: 64,
    }, control);
  const hostConnection = ({principalId: actual, connection, ref}) =>
    actual === principalId &&
    connection.mode === mode && connection.owner === mode &&
    (ref === undefined || ref.tenantId === tenantId &&
      ref.authorityScopeCid === authorityScopeCid);
  const authorizedScope = ({principalId: actual}) =>
    actual === principalId ? {tenantId, authorityScopeCid} : undefined;
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
      actual === principalId && ref.tenantId === tenantId &&
      ref.authorityScopeCid === authorityScopeCid});
  const prepareSubmit = installNodeClientProgramPreparation({moon,
    environment});
    checkpoints = await installRemoteCheckpoints({root, tenantId,
      authorityScopeCid, ownerPrincipal: principalId,
      siteKey: authorization?.siteKey ?? 'actql-remote-host',
      realizationKey: sourceProfile === undefined ? REALIZATION_KEY
        : 'duckdb-acquired', environmentCid: evidenceCid,
      contractControl: control, authorization,
      source: sourceProfile?.readAuthorization});
  const observeRun = async ({ref, principalId: actual}) => {
    if (actual !== principalId || ref.tenantId !== tenantId ||
        ref.authorityScopeCid !== authorityScopeCid) {
      throw new Error('RunStateAccessDenied');
    }
    // Recheck the journal revision after asynchronous Store observation so
    // control facts never combine observations from two journal revisions.
    for (let attempt = 0; attempt < 8; attempt++) {
      const retained = journal.lookupRunDefinition(ref, moon, control);
      if (retained === undefined) throw new Error('RunStateAccessDenied');
      let state;
      if (await store.confirmCommittedIndex(ref) !== undefined) {
        state = await inspectAuthorizedRunState(stateService, {
          indexKey: ref, principalId: actual, purpose: 'inspect',
        });
      } else {
        if (!Array.isArray(retained.resultNames)) {
          throw new Error('RunStateInventoryUnknown');
        }
        const liveExecution = dispatchOwner.live(ref);
        const executionUnknown = retained.dispatchReserved &&
          !retained.preDispatchFailureConfirmed &&
          retained.physicalStartReserved !== false &&
          retained.observedTerminalOutcome === null && !liveExecution;
        const wire = checked(moon.clientProgramIssueControlledUnpublishedRunState(
          control.runDefinitionRunId(retained.runDefinition), now(),
          retained.resultNames, retained.dispatchReserved,
          retained.preDispatchFailureConfirmed,
          retained.cancellationRequested &&
            retained.physicalStartReserved === false,
          retained.observedTerminalOutcome ?? 'none', executionUnknown));
        state = JSON.parse(wire);
      }
      const after = journal.lookupRunDefinition(ref, moon, control);
      if (after?.revision !== retained.revision) continue;
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
    const existing = journal.lookupDefinition({tenantId, authorityScopeCid,
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
    const acquisition = moon.clientProgramPrepareQueryAcquisition(
      preparedProgram, 0, 0);
    const acquired = acquisition?.$tag === 1;
    if (acquired) {
      if (sourceProfile === undefined) {
        throw new Error('ClientProgramNeedsInputs');
      }
      const requirement = checked(
        moon.clientProgramPrepareLocalQueryRequirement(preparedProgram,
          0, 0, registry, values, fragment, ordered));
      if (moon.clientProgramQueryRequirementSourceRef(requirement) !==
          sourceProfile.sourceRef) {
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
    return {requested, resultNames, acquired};
  };
  const prepareAcquisition = (preparedProgram,
    sourceAccess = sourceProfile.sourceAccess) =>
    prepareCapturedDuckDBSource({moon, preparedProgram, registry, values,
      fragment, ordered, database: sourceProfile.database,
      schema: sourceProfile.schema, table: sourceProfile.table,
      sourceAccess});
  const planFor = ({preparedProgram, kind, input, parameters, requestId},
    retainedDefinitionWire) => {
    const common = {moon, control, preparedProgram,
      document: kind === 'aql' ? input.text : JSON.stringify(input),
      format: kind === 'aql' ? input.format : 'json', parameters,
      environmentWire, environmentCid: evidenceCid,
      authorityScopeCid, tenantId, requestId, storeAuthorityCid, now,
      ...(retainedDefinitionWire === undefined ? {} :
        {retainedDefinitionWire})};
    return sourceProfile !== undefined &&
      moon.clientProgramPrepareQueryAcquisition(preparedProgram, 0, 0)?.$tag ===
        1
      ? acquiredTaskRunAdmission(common)
      : sourceFreeValuesPlan(common);
  };
  // Admit (or look up) the request's Run Definition: the durable Run.
  const admitDefinition = async (submission, requested, resultNames,
    held) => {
    const accepted = await journal.admitOrLookupDefinition(requested, {
      tenantId, lookupExpiresAt: plus(now(), 7 * 24 * 60 * 60 * 1000),
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
  const observed = (name, detail) => authorization?.observe?.(name, detail);
  dispatchOwner = installNodeClientDispatchOwner({moon, control,
    journal, store, checkpoints, startRun, hostConnection, beforeDispatch,
    observed, prepareAcquisition, planFor, sourceProfile, registry, values,
    fragment, ordered, tenantId, authorityScopeCid, storeAuthorityCid, now});
  const startDispatch = dispatchOwner.start;
  const runIdOf = accepted => control.runDefinitionRunId(
    accepted.runDefinition?.wire === undefined
      ? journal.lookupRunDefinition(accepted.ref, moon, control).runDefinition
      : accepted.runDefinition);
  const submit = async submission => {
    const {requestId, principalId: actual, connection, kind, input,
      parameters} = submission;
    if (!hostConnection({principalId: actual, connection})) {
      throw new Error('ClientConnectionDenied');
    }
    const {requested, resultNames, acquired} = requestOf(submission);
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
      const existing = journal.resolveDefinition(requested, {tenantId}, moon,
        control);
      if (existing !== undefined) {
        void checkpoints.sweep();
        return {ref: existing.ref, durability: existing.durability,
          revision: existing.revision};
      }
    }
    if (checkpoints !== undefined &&
        (checkpoints.heldOrigin(requestId) ||
         journal.lookup({tenantId, authorityScopeCid, requestId}, moon) ===
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
        const existing = journal.lookupDefinition({tenantId,
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
    const {requested, resultNames, acquired} = requestOf(submission);
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
    return {submission, requested, resultNames, preparedSource};
  };
  const definitionOf = captured => journal.lookupDefinition({tenantId,
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
    const accepted = journal.lookupDefinition({tenantId,
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
    const {submission, requested, resultNames, preparedSource} = resolved;
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
        captured)).requested, tenantId, principalId: captured.principalId,
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
  const hostOperations = {
    observe: observed,
    authorizeConnection: value => checkpointOperation.has(value.operation)
      ? checkpointConnection(value)
      : hostConnection(value) || value.operation === 'connect' &&
        checkpointConnection(value),
    negotiate, prepareSubmit, submit, attach, lookupRequest: lookupHeld,
    stateService, resultService, observeRun, wait, cancel, cancelRequest,
    ...checkpointOperations,
  };
  if (checkpoints !== undefined) {
    await checkpoints.start({inspect: inspectHeld, resume: resumeHeld,
      abandon: abandonHeld, observe: observeHeldRun,
      cancelRun: cancelHeldRun});
  }
  const port = createNodeInProcessClientHost({
    authenticate: () => principalId,
    ...hostOperations, maxRowBytes: 1024 * 1024,
  });
  return {port, store, journal, hostOperations, checkpoints,
    dispatchOwner, inspectAcquisition};
  } catch (cause) {
    throw await retainInstalledHostInitializationFailure(cause,
      {journal, store, checkpoints, dispatchOwner});
  }
}

// This HTTP ingress uses the installed Host's common owner and physical
// services. Embedded Local continues to use the in-process port above.
//
// `authorization` installs Run-acceptance protection for the Host's Site:
// {accountConfig | accountConfiguration, reviewers: [{keyId, reviewerId,
// principalId, publicKey}], reviewReaders: [principal], hostKey: {keyId,
// privateKey}, siteKey?, decide?, answeringAuthorities?, checkpointTtlMs?,
// leaseMs?, maxReviewBytes?, resumeAfterAnswer?, sweepPage?, observe?}.
// Approved requests are resumed at Host start and, unless
// `resumeAfterAnswer` is false, after an answer is stored; each sweep step
// handles at most `sweepPage` items and continues until none remain.
// `observe(step, detail)` is Host instrumentation of the protected steps. Without a configuration the Missing account
// denies every request; nothing defaults to allow.
export async function openInstalledRemoteHttpHost({directory,
  authenticate, beforeDispatch, authorization, sourceProfilePath}) {
  if (typeof directory !== 'string' || !directory ||
      typeof authenticate !== 'function' ||
      beforeDispatch !== undefined && typeof beforeDispatch !== 'function') {
    throw new TypeError('InvalidInstalledRemoteHost');
  }
  const host = await openInstalledHost(resolve(directory), 'remote',
    beforeDispatch, authorization, sourceProfilePath);
  const handle = createClientHttpHandler({
    ...host.hostOperations, authenticate, maxRequestBytes: 65536,
  });
  // A request's handling can outlive its response: a Result read records
  // its delivery attempt after the last bytes are sent. Close waits for
  // every request still being handled; once closing, new requests are
  // refused before they touch the Store.
  const handling = new Set();
  let closing = false;
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
      await host.checkpoints?.stop();
      await host.dispatchOwner.drain();
      const checkpoints = await host.checkpoints?.close();
      host.journal.close();
      // A Store with a pending deletion keeps its durable deletion record;
      // the next owner recovers it.
      let storeCleanupPending = false;
      try { await host.store.close(); }
      catch (error) {
        if (error?.code !== 'PublicationStoreCleanupPending') throw error;
        storeCleanupPending = true;
      }
      return Object.freeze({storeCleanupPending,
        pendingRetention: checkpoints?.pendingRetention ?? []});
    },
  });
}

export async function connectEmbeddedLocal(options) {
  const root = localStateRoot();
  let opened = profiles.get(root);
  if (opened === undefined) {
    opened = openInstalledHost(root);
    profiles.set(root, opened);
    opened.catch(() => profiles.delete(root));
  }
  const host = await opened;
  return connectInProcess(options, host.port);
}
