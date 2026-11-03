// Provider-neutral test assembly over the existing production Run, capture,
// publication Store and request Journal. A driver or caller still owns its
// original Site, current checks, Provider I/O and cleanup. This helper grants
// no production authority and retains the original fixture's exact limits.
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../host-common/runtime-result.mjs';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {installNodeClientEffectRun, openClientRequestJournal} from '../client-effect-run.mjs';
import {completeCapturedEffectRun, completeRecoveredEffectRun,
  recoverAdmittedEffectRun, runCapturedEffectComputation} from '../entry.mjs';
import {localContractLimits, localOutputLimits, sourceFreeEffectPublicationPlan} from '../local-values-plan.mjs';
import {openLocalPublicationStore} from '../../store-local/publication-store.mjs';
import {releaseCompletedRunPreparedPayloads,
  suspendCompletedEffectfulComputation} from '../../host-common/completed-run-publication.mjs';
import {ExecutionAuthorizationError} from '../../host-common/authorization-gate.mjs';
import {installedRowEffectUnit} from '../installed-row-effect.mjs';
import {openFundedClientPreparation} from '../funded-client-preparation.fixture.mjs';
import {prepareInstalledEffectManagedPlanRun, readInstalledEffectManagedPlanRun}
  from '../installed-effect-managed-run.mjs';
import {installUpdateTargetOriginals} from '../installed-update-originals.mjs';
import {prepareEffectCaptureResources} from '../effect-capture-resources.mjs';
const repository = new URL('../../../', import.meta.url);
const limits = localContractLimits;
const cid = digit => `sha256:${digit.repeat(64)}`;

const storeConfiguration = directory => ({directory,
  storeAuthorityCid: cid('7'), capacityBytes: 64 * 1024 * 1024,
  maxObjectBytes: localOutputLimits.maxWireBytes, maxObjects: 1000,
  maxContractNodes: limits.maxNodes, maxContractDepth: limits.maxDepth,
  privateEvidenceKey: Buffer.alloc(32, 4)});

// One Host process over `state`: a request journal, the publication Store
// and the installed Effect. `run` accepts and starts one Program request; the
// installed factory captures and the common owner completes it.
// `stopBeforeApply` ends the process's part after the capture, as a Host
// stopped while the Set waits for approval would.
export async function effectHost(t, installation, state, {effect,
  wrapStage, wrapRecoveredStage, stopBeforeApply = false, unitOf = installedRowEffectUnit,
  managed = false} = {}) {
  const installed = effect ?? await installation.load();
  const environmentWire = installed.environmentWire;
  const environment = moon.clientProgramCheckEnvironment(environmentWire,
    JSON.parse(environmentWire).evidence_bundle_cid,
    false, false, true, false, false, false, false);
  assert.ok(environment);
  // Real installed recipes retain the ordinary funded Request; explicit-port
  // component drivers without that recipe keep their direct authored checker.
  const prepareProgram = async request => {
    if (funded !== undefined) {
      const prepared = await funded.prepare(request);
      requests.set(prepared, request);
      return prepared;
    }
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      request.kind === 'program' ? JSON.stringify(request.input) : request.input.text,
      request.kind === 'program' ? 'json' : request.input.format,
      environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared, moon.clientProgramEffectPreparationIssueCode(outcome));
    return prepared;
  };
  await mkdir(state, {recursive: true});
  const journal = openClientRequestJournal(join(state, 'requests'));
  const control = runtimeCore(moon).publicationControl;
  const store = await openLocalPublicationStore(storeConfiguration(
    join(state, 'store')), control);
  const [registry, contract] = await Promise.all([
    readFile(new URL('spec/dependencies/aoa-pipeline-registry.json',
      repository), 'utf8'),
    readFile(new URL('spec/contracts/actql-aoa.json', repository), 'utf8'),
  ]);
  const values = JSON.stringify(
    JSON.parse(contract).execution_contracts['REL.values']);
  // Retain this fixture Host's exact admitted Values-only contract closure.
  // Sequence consumers require the Core original, not its registry wire.
  const installedContracts = checked(moon.clientPrepareInstalledSequenceContracts(
    registry, values, undefined, undefined));
  // Real installed recipes use the existing ordinary Request owner. The
  // explicit-port row tests without a recipe keep their separate low-level
  // component scope; neither path supplies a shaped managed Run.
  const funded = managed ? await openFundedClientPreparation({moon, environment,
    allowEffects: true, sequenceContracts: {values}}) : undefined;
  const requests = new WeakMap(), identities = new WeakMap();
  const managedRuns = new WeakMap(), liveManagedRuns = new Set(), recoveryFrames = [], recoveryOwners = [];
  const originals = managed ? installUpdateTargetOriginals({moon, control,
    installedEffect: installed, limits}) : undefined;
  let closing = false, closed = false, storeClosed = false, journalClosed = false;
  const assertCurrent = () => {assert.equal(closing || closed, false);};
  const readManaged = (prepared, request) => readInstalledEffectManagedPlanRun({
    runs: managedRuns, liveRuns: liveManagedRuns, runtime: moon,
    prepared, request, assertCurrent, checked});
  const prepareDefinition = funded === undefined ? undefined : facts =>
    prepareInstalledEffectManagedPlanRun({runs: managedRuns, liveRuns: liveManagedRuns,
      runtime: moon, manager: funded.manager, prepared: facts.prepared,
      request: facts.identity, requestInput: requests.get(facts.prepared),
      selection: installed, facts, inputs: Object.freeze({registry, values, installedContracts}),
      assertCurrent, checked});
  const requestPath = requestId => join(state, `fixture-input-${
    createHash('sha256').update(requestId).digest('hex')}.json`);
  const now = () => new Date().toISOString();
  const outcomes = [];
  const executions = [];
  const runs = installNodeClientEffectRun({moon, publicationControl: control,
    journal, now, prepareDefinition, updateTargetOriginals: originals,
    ...(managed ? {requestIdentityFor({prepared, authorityScopeCid, requestId}) {
      let identity = identities.get(prepared);
      if (identity === undefined) {
        identity = moon.clientProgramEffectRequestIdentity(prepared,
          authorityScopeCid, requestId, moon.clientProgramSourceFreeInputIntentCid());
        assert.ok(identity); identities.set(prepared, identity);
      }
      return identity;
    }} : {}),
    authorizeRequest: async () => ({executionContextCid: cid('a'),
      hostPolicyCid: cid('b'), createdAt: now(),
      expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()}),
    authorizeRunStart: async () => true,
    async execute(facts) {
      const plan = sourceFreeEffectPublicationPlan({moon, control,
        prepared: facts.prepared,
        compilation: facts.compilation, allowed: facts.allowed,
        definition: facts.definition, authorityScopeCid: cid('e'),
        namespaceId: 'namespace-a', storeAuthorityCid: store.storeAuthorityCid,
        now});
      const managedEffect = funded === undefined ? undefined : readManaged(facts.prepared, facts.identity);
      const owned = managedEffect === undefined
        ? moon.clientProgramOpenSourceFreeLocalEffectHost(
          facts.owner, installedContracts, values, 1n, 0n, 0n, 0n)
        : checked(moon.clientProgramInstalledEffectManagedHostOpen(managedEffect.value, facts.owner, []));
      assert.ok(owned);
      const execution = await runCapturedEffectComputation(owned);
      executions.push({execution, closed: false});
      const compiledPlan = checked(moon.strategyPublicationAdmit(
        'compiled_plan', moon.clientProgramEffectCompilationCompiledPlanWire(
          facts.compilation), limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
      const stage = await installed.prepareCaptured({moon, control, store,
        managedEffect,
        execution, checkedHost: owned, prepared: facts.prepared,
        compilation: facts.compilation,
        identity: facts.identity, plan,
        previewContext: {runDefinition: facts.definition,
          runInvocation: plan.invocationOwner, compiledPlan},
        assertContinuationCurrent: assertCurrent,
        updateTargetSelections: facts.updateTargetSelections,
        assertUpdateSelectionCurrent: facts.assertUpdateSelectionCurrent,
        unit: unitOf(moon, facts.compilation)});
      const owned2 = wrapStage === undefined ? stage : wrapStage(stage);
      if (stopBeforeApply) {
        // As the installed Host does before the Set waits: the durable
        // intents let a later process rebuild the exact claims.
        stage.apply.ledger.prepareCapturedSetIntents(
          stage.apply.capturedInputs, stage.apply.members,
          stage.apply.maxFrontierWork);
        await suspendCompletedEffectfulComputation({execution, store,
          storedResults: stage.storedResults, control,
          computation: stage.computation, preview: stage.preview});
        outcomes.push({stage, result: {status: 'suspended'}});
        return Object.freeze({status: 'captured',
          continuation: JSON.parse(stage.continuationWire)});
      }
      try {
        const result = await completeCapturedEffectRun({apply: owned2.apply,
          receipt: owned2.receipt, publication: owned2.publication});
        outcomes.push({stage, result});
        return result;
      } catch (error) {
        outcomes.push({stage, error});
        // As the installed Host does: a commit refused before any send
        // releases the unpublished Results.
        if (error instanceof ExecutionAuthorizationError &&
            error.authorization?.action === 'deny') {
          await releaseCompletedRunPreparedPayloads(stage.storedResults,
            control);
        }
        throw error;
      }
    }});
  // What this process still holds when it ends: a failed Set's unpublished
  // Results are released; otherwise the process stops and only its local
  // payload custody ends, while the durable capture stays for a restart.
  const endCustody = async (stage, result) => {
    if (result?.status === 'suspended') return;
    if (result?.status === 'failed') {
      await releaseCompletedRunPreparedPayloads(stage.storedResults, control);
      return;
    }
    // Release the SAME completed Result owner's process-local children,
    // including restored private dependency schemas. Releasing only public
    // Result handles leaves the recovered capture's original Store custody.
    // Suspension retains durable evidence and any already-selected terminal
    // release mode; it does not acknowledge an unknown physical operation.
    await suspendCompletedEffectfulComputation(stage.publication);
  };
  const close = async () => {
    if (closed) return;
    closing = true;
    for (const outcome of outcomes) {
      if (!outcome.disposed) {
        assert.notEqual(await outcome.stage.dispose(), false,
          'The original recovered child is still pending');
        outcome.disposed = true;
      }
      if (!outcome.custodyEnded) {
        await endCustody(outcome.stage, outcome.result);
        outcome.custodyEnded = true;
      }
    }
    for (const record of executions) {
      if (!record.closed) {
        if (!record.closeAttempted) {
          record.closeAttempted = true;
          await record.execution.close();
        }
        if (record.execution.cleanupPending()) await record.execution.cleanup();
        assert.equal(record.execution.cleanupPending(), false);
        record.closed = true;
      }
    }
    for (const owner of recoveryOwners) {
      if (owner.cleanupPending()) await owner.close();
      assert.equal(owner.cleanupPending(), false);
    }
    for (const frame of recoveryFrames) assert.equal(await frame.close(), true);
    for (const run of liveManagedRuns) {
      // A failed selection never adopted its Request. The existing funded
      // fixture's close below owns that original partial input and borrower.
      if (run.value === undefined && run.fixtureRetirement === undefined) {
        assert.notEqual(run.selecting, true, 'Original selection is still pending');
        for (const name of Object.keys(run)) run[name] = undefined;
        run.closed = true;
        continue;
      }
      const retirement = run.fixtureRetirement ??= {prepared: run.prepared,
        original: run.original, value: run.value, request: run.request, retire: run.retire};
      if (!retirement.payloadSevered) {
        run.retireControlConstruction?.();
        try {checked(Reflect.apply(retirement.retire, moon, [retirement.value]));}
        catch (cause) {
          if (moon.clientProgramInstalledPreparationPayloadSevered(retirement.value, retirement.request) !== true) throw cause;
        }
        retirement.payloadSevered = true;
        // Match the normal caller: cut compiler/Plan/provider aliases BEFORE
        // returning its same Request borrower. Keep only original retirement
        // controls for a consumed-return failure or pending parent settlement.
        for (const name of Object.keys(run)) {
          if (name !== 'fixtureRetirement') run[name] = undefined;
        }
      }
      if (!retirement.borrowReturned) {
        funded.manager.severPreparation(retirement.prepared, retirement.original);
        retirement.borrowReturned = true;
      }
      if (!retirement.callerRetired) {
        funded.retireOriginal(retirement.prepared);
        retirement.callerRetired = true;
        retirement.prepared = retirement.request = undefined;
      }
      // Returning the SAME preparation borrower can finish the original
      // parent. Observe that actual retirement before removing its live slot.
      checked(Reflect.apply(retirement.retire, moon, [retirement.value]));
      funded.manager.retireSeveredPreparation(retirement.original);
      run.fixtureRetirement = undefined;
      run.closed = true;
      liveManagedRuns.delete(run);
    }
    await funded?.close();
    liveManagedRuns.clear();
    recoveryFrames.length = recoveryOwners.length = 0;
    if (!storeClosed) {assert.equal(await store.close(), true);storeClosed = true;}
    if (!journalClosed) {journal.close();journalClosed = true;}
    if (effect === undefined) assert.notEqual(await installed.close(), false);
    closed = true;
  };
  installation.onClose(close);
  return {installed, journal, store, control, outcomes, close,
    async run(document, requestId, {kind = 'program', format = 'json'} = {}) {
      assertCurrent();
      const request = {kind,
        input: kind === 'program' ? document : {text: document, format},
        parameters: null};
      const prepared = await prepareProgram(request);
      if (managed) await writeFile(requestPath(requestId), JSON.stringify(request));
      const accepted = await runs.accept({prepared,
        authorityScopeCid: cid('e'), requestId, namespaceId: 'namespace-a',
        principalId: 'principal-a',
        connection: {mode: 'local', owner: 'local'},
        lookupExpiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000)
          .toISOString()});
      try {
        return {accepted, started: await runs.start(accepted)};
      } catch (error) {
        // The accepted request stays the Run's handle for a restart.
        if (error !== null && typeof error === 'object') {
          error.accepted = accepted;
        }
        throw error;
      }
    },
    // Recover the admitted Run of `requestId` in this process and continue
    // it through the installed factory's recovery projection.
    // `retainRecoveryOwner` receives the recovered Ledger handle's owner, as
    // the Host's recovery custody does.
    async resume(requestId, runDefinitionCid, continuation,
      {retainRecoveryOwner} = {}) {
      assertCurrent();
      let prepared, compilation, managedEffect;
      if (managed) {
        prepared = await prepareProgram(JSON.parse(await readFile(requestPath(requestId), 'utf8')));
        compilation = checked(moon.clientProgramCompileLocalEffects(prepared));
      }
      const recovery = await recoverAdmittedEffectRun({requests: journal,
        store, key: {namespaceId: 'namespace-a', authorityScopeCid: cid('e'),
          requestId, runDefinitionCid},
        principalId: 'principal-a', contractLimits: limits,
        authorizeEvidenceRead: async () => true,
        ...(managed ? {restoreOriginal(retained, identity) {
          const evidence = retained.runAdmissionEvidence;
          const restored = evidence.updateTargetRunOriginal === undefined
            ? originals.restoreEffectMaterials(evidence.effectOriginalRunWire,
              retained.runDefinition, identity, compilation)
            : originals.restoreRun(evidence.updateTargetRunOriginal,
              retained.runDefinition, identity, compilation);
          assert.strictEqual(restored.prepared, prepared);
          prepareDefinition(Object.freeze({...restored, identity,
            modelCompiled: undefined, queryTimePreparation: undefined}));
          managedEffect = readManaged(prepared, identity);
          return restored;
        }, prepareRecoveryResources({requestIdentity, runDefinition, contractLimits,
          assertOriginalCurrent, retain}) {
          return prepareEffectCaptureResources({moon, control, request: requestIdentity,
            runDefinition, contractLimits, managed: managedEffect,
            assertCurrent: assertOriginalCurrent,
            retain(frame) {recoveryFrames.push(frame);retain(frame);}});
        }} : {})});
      let stage;
      try {
        stage = installed.prepareRecovered({moon, control, store,
          managedEffect,
          prepared: recovery.prepared,
          recovered: recovery,
          updateTargetSelections: recovery.updateTargetSelections,
          assertUpdateSelectionCurrent: recovery.assertUpdateSelectionCurrent,
          continuation, contractLimits: limits,
          retainRecoveryOwner: managed ? owner => {
            recoveryOwners.push(owner);
            retainRecoveryOwner?.(owner);
          } : retainRecoveryOwner});
      } catch (error) {
        outcomes.push({stage: {dispose() {},
          storedResults: recovery.computation.storedResults,
          publication: {store, control, ...recovery.computation}}});
        throw error;
      }
      try {
        const owned = wrapRecoveredStage === undefined ? stage : wrapRecoveredStage(stage);
        const result = await completeRecoveredEffectRun({
          apply: owned.apply, receipt: owned.receipt,
          publication: owned.publication});
        outcomes.push({stage, result});
        return {stage, result};
      } catch (error) {
        outcomes.push({stage});
        throw error;
      }
    }};
}
