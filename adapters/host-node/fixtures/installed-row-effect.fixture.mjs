// Provider-neutral test assembly over the existing production Run, capture,
// publication Store and request Journal. A driver or caller still owns its
// original Site, current checks, Provider I/O and cleanup. This helper grants
// no production authority and retains the original fixture's exact limits.
import assert from 'node:assert/strict';
import {mkdir, readFile} from 'node:fs/promises';
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
  wrapStage, wrapRecoveredStage, stopBeforeApply = false, unitOf = installedRowEffectUnit} = {}) {
  const installed = effect ?? await installation.load();
  const environmentWire = installed.environmentWire;
  const environment = moon.clientProgramCheckEnvironment(environmentWire,
    JSON.parse(environmentWire).evidence_bundle_cid,
    false, false, true, false, false, false, false);
  assert.ok(environment);
  // This explicit low-level fixture checks its authored input directly. It
  // installs no ordinary Request or funded preparation callback; its Journal
  // and provider ports below keep their separate component qualification.
  const prepareProgram = request => {
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
  const now = () => new Date().toISOString();
  const outcomes = [];
  const executions = [];
  const runs = installNodeClientEffectRun({moon, publicationControl: control,
    journal, now,
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
      const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
        facts.owner, installedContracts, values, 1n, 0n, 0n, 0n);
      assert.ok(owned);
      const execution = await runCapturedEffectComputation(owned);
      executions.push(execution);
      const compiledPlan = checked(moon.strategyPublicationAdmit(
        'compiled_plan', moon.clientProgramEffectCompilationCompiledPlanWire(
          facts.compilation), limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth));
      const stage = await installed.prepareCaptured({moon, control, store,
        execution, checkedHost: owned, prepared: facts.prepared,
        compilation: facts.compilation,
        identity: facts.identity, plan,
        previewContext: {runDefinition: facts.definition,
          runInvocation: plan.invocationOwner, compiledPlan},
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
  let closed = false;
  const close = async () => {
    if (closed) return;
    closed = true;
    for (const {stage, result} of outcomes) {
      await stage.dispose();
      await endCustody(stage, result);
    }
    for (const execution of executions) {
      await execution.close();
    }
    await store.close();
    journal.close();
    if (effect === undefined) installed.close();
  };
  installation.onClose(close);
  return {installed, journal, store, control, outcomes, close,
    async run(document, requestId, {kind = 'program', format = 'json'} = {}) {
      const prepared = prepareProgram({kind,
        input: kind === 'program' ? document : {text: document, format},
        parameters: null});
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
      const recovery = await recoverAdmittedEffectRun({requests: journal,
        store, key: {namespaceId: 'namespace-a', authorityScopeCid: cid('e'),
          requestId, runDefinitionCid},
        principalId: 'principal-a', contractLimits: limits,
        authorizeEvidenceRead: async () => true});
      let stage;
      try {
        stage = installed.prepareRecovered({moon, control, store,
          recovered: {requestIdentity: recovery.requestIdentity,
            requestScope: recovery.requestScope,
            computation: recovery.computation},
          continuation, contractLimits: limits, retainRecoveryOwner});
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
