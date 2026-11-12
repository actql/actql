// Installed composition of the actual Model owner, immutable input custody,
// existing Checkpoint journal and Store. This is neither a slot scheduler nor
// a source of dispatch permission from historical bytes.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {authorizationDispatchFacts, ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {bytesCid, contentCid} from './local-account-config.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {loadCheckpointRuntime} from './sqlite-checkpoint-journal.mjs';
import {MAX_MODEL_INPUT_BYTES} from './client-checkpoints.mjs';
import {withPreparedInferEvidence} from './infer-evaluation-evidence.mjs';
import {createNodeInferEntryPersistence} from './infer-entry-persistence.mjs';
import {createInferPhysicalObservation} from './infer-physical-observation.mjs';
import {snapshotModelRawCaptureSelection} from './infer-raw-selection.mjs';
import {createModelRawTransportPersistenceFactory} from './infer-raw-capture.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {selectedInferOriginalCurrentStateCodec,
  snapshotInferOriginalCurrentStateCodec as originalCurrentCodecLimits} from './infer-original-installation.mjs';

const limits = Object.freeze({maxWireBytes: 1048576, maxNodes: 100000, maxDepth: 100});
const fail = code => { throw Object.assign(new Error(code), {code}); };
function requireModelDispatchPreparation(moon, selected) {
  if (selected.localMock === true) {
    // Only the same live Core Mock installation/provider has no external I/O.
    // A Host flag, a matching provider name or absence of egress is not that
    // original. Account, Entry, Run and current-provider gates remain below.
    if (selected.originalMockInstallation === undefined ||
        typeof moon.clientProgramOriginalMockProvider !== 'function' ||
        checked(moon.clientProgramOriginalMockProvider(selected.originalMockInstallation)) !== selected.provider) {
      fail('InstalledMockModelOriginalUnavailable');
    }
    return;
  }
  if (selected.originalMockInstallation !== undefined) fail('InstalledMockModelOriginalUnavailable');
  if (selected.egressAdmission === undefined) {
    throw selected.egressFailure ?? new Error('InstalledModelEgressUnavailable');
  }
}
const parseCore = wire => {
  const value = JSON.parse(wire);
  if (value.ok !== true) fail(value.code ?? 'InstalledModelAdmissionRejected');
  const {ok, ...facts} = value;
  return facts;
};
const same = (a, b) => canonicalJson(a) === canonicalJson(b);
const scopeKeys = ['runId', 'runDefinitionCid', 'preparedInvocationCid', 'scopeCid',
  'providerBindingCid', 'inputArtifactCid', 'taskIndex', 'strategyRevision'];
const select = (value, keys) => Object.fromEntries(keys.map(key => [key, value[key]]));
const entryIdentity = entry => select(entry, entry.provenance === 'deferred'
  ? ['runId', 'runDefinitionCid', 'preparedInvocationCid', 'checkpointCid',
      ...scopeKeys.slice(3), 'ordinal', 'slotCid', 'attemptIndex', 'attemptCid',
      'intentId', 'claimant', 'generation', 'resolutionCid']
  : [...scopeKeys, 'provenance', 'ordinal', 'slotCid', 'attemptIndex', 'attemptCid', 'authorityCid']);
const originalKeys = ['originalRunWire', 'preparedInvocationWire', 'scopeWire',
  'providerBindingWire', 'inputArtifactWire', 'slotWires', 'expectedBoundary'];
// Hash opaque original wires without the configuration canonicalizer's text normalization.
const originalDigest = originals => bytesCid(Buffer.from(canonicalJson(select(originals, originalKeys))));
// This validates only the closed durable transport. Current Source authority,
// typed reference admission and actual Store custody remain receiving duties.
const checkCapturedInventory = (value, runDefinitionCid, binding) => {
  if (value === undefined) return;
  const closed = (item, keys) => item !== null && typeof item === 'object' &&
    !Array.isArray(item) && Object.keys(item).sort().join(',') === keys;
  if (!closed(value, 'entries,runDefinitionCid,version') ||
      value.version !== 'actql-installed-captured-content-inventory/0.1' ||
      value.runDefinitionCid !== runDefinitionCid || !Array.isArray(value.entries)) {
    fail('ModelCapturedInventoryMismatch');
  }
  const seen = new Set();
  if (!closed(binding, 'bindingCid,connection,connectorRegistration,connectorRevision,physicalBindingCid,selectionCid,version') ||
      binding.version !== 'actql-installed-keyed-read-binding/0.1' ||
      ['selectionCid', 'physicalBindingCid', 'bindingCid'].some(key =>
        !/^sha256:[0-9a-f]{64}$/u.test(binding[key] ?? '')) ||
      ['connection', 'connectorRegistration', 'connectorRevision'].some(key =>
        typeof binding[key] !== 'string' || binding[key].length === 0)) {
    fail('ModelCapturedBindingMismatch');
  }
  for (const entry of value.entries) {
    if (!closed(entry, 'captureAuthorityCid,referenceWire') ||
        typeof entry.referenceWire !== 'string' || entry.referenceWire.length === 0 ||
        Buffer.byteLength(entry.referenceWire) > MAX_MODEL_INPUT_BYTES ||
        typeof entry.captureAuthorityCid !== 'string' ||
        !/^sha256:[0-9a-f]{64}$/u.test(entry.captureAuthorityCid) || seen.has(entry.referenceWire)) {
      fail('ModelCapturedInventoryMismatch');
    }
    seen.add(entry.referenceWire);
  }
};
const roles = ['model_call_attempt', 'model_attempt_accounting', 'model_attempt_outcome',
  'model_dispatch_authority', 'model_slot_capture', 'model_capture_bundle', 'model_attachment_admission'];

export async function installNodeModelContinuation({moon, control, store, storeAuthorityCid, namespaceId,
  authorityScopeCid, now, getCheckpoints, observe: observeDiagnostic, observation, inferEvidence}) {
  const runtime = await loadCheckpointRuntime();
  const custody = new Map();
  const live = new WeakMap();
  const leases = new WeakMap();
  // Route only the original bare park to its existing installed operation's
  // completed Common comparison. Escaped park refs retain no new callback or
  // Owner graph through this weak membership; the operation keeps its borrow.
  const originalResourceCuts = new WeakMap();
  function originalResourceCut(park) {
    const original = originalResourceCuts.get(park)?.deref();
    if (original?.facts === undefined || !original.current()) {
      fail('ModelOriginalCurrentCutUnavailable');
    }
    return original;
  }
  // Synchronous journal checks need the previously authenticated receipt and
  // original digest while a Run is waiting or unknown. They do not need input
  // rows, submitted programs or responses, and cannot authorize a fresh send.
  const inventories = new Map();
  const diagnostic = diagnosticObserver(observeDiagnostic);
  let checkpointInstallation;
  let retainedInputs = 0, retainedInputBytes = 0;
  const usage = () => Object.freeze({retainedInputScopes: custody.size,
    retainedInputs, retainedInputBytes, retainedInventoryScopes: inventories.size});
  const changed = () => diagnostic('model_input_custody_changed', usage());
  function retain(receiptWire, receipt, snapshot, bytes) {
    immutableInput(receipt);
    immutableInput(snapshot);
    let tokens = custody.get(receiptWire);
    if (tokens === undefined) custody.set(receiptWire, tokens = new Set());
    const state = {available: true, snapshot};
    const token = Object.freeze({receipt, get snapshot() { return state.snapshot; },
      get available() { return state.available; }});
    leases.set(token, {receiptWire, tokens, state, bytes});
    tokens.add(token);
    retainedInputs++;
    retainedInputBytes += bytes;
    changed();
    return token;
  }
  function ownedInput(token, runDefinitionCid) {
    const lease = leases.get(token);
    if (lease === undefined || !lease.state.available ||
        lease.tokens.has(token) !== true || token.receipt.runDefinitionCid !== runDefinitionCid) {
      fail('ModelFixedInputCustodyUnavailable');
    }
    return token.snapshot;
  }
  // The authenticated receipt covers these exact values. Borrowers may not
  // replace a captured reference or scope after receipt verification. Walk
  // the already byte-bounded decoded tree without another serialized copy.
  function immutableInput(value) {
    const pending = [value];
    while (pending.length > 0) {
      const next = pending.pop();
      if (next !== null && typeof next === 'object') {
        for (const child of Object.values(next)) {
          if (child !== null && typeof child === 'object') pending.push(child);
        }
        Object.freeze(next);
      }
    }
    return value;
  }
  function release(token) {
    const lease = leases.get(token);
    if (lease === undefined) return;
    lease.state.available = false;
    // Retire only this lease's decoded input. Escaped borrows and
    // independently retained consumers keep their own original custody.
    lease.state.snapshot = undefined;
    leases.delete(token);
    lease.tokens.delete(token);
    if (lease.tokens.size === 0 && custody.get(lease.receiptWire) === lease.tokens) {
      custody.delete(lease.receiptWire);
    }
    retainedInputs--;
    retainedInputBytes -= lease.bytes;
    try { retireReceipt(lease.receiptWire); }
    catch (error) {
      // A later sweep can retire small journal metadata. It cannot undo the
      // payload release or replace an earlier execution/admission failure.
      diagnostic('model_input_retirement_pending', {code: error?.code ?? error?.message});
    }
    changed();
  }
  function retireReceipt(receiptWire) {
    const held = inventories.get(receiptWire);
    if (held === undefined || custody.has(receiptWire)) return;
    const journal = checkpoints().journal;
    const state = journal.getRunState(held.receipt.runId);
    const records = journal.discoverModelCallSets({runId: held.receipt.runId, limit: 100});
    const absent = records.length < 100 &&
      !records.some(record => record.originals.fixedInputReceiptWire === receiptWire);
    if (absent || state !== undefined && journal.isTerminalRunOutcome(state.status) &&
        !journal.hasUnresolvedModelCalls(held.receipt.runId)) {
      inventories.delete(receiptWire);
      changed();
    }
  }
  const checkpoints = () => {
    const value = getCheckpoints();
    if (value === undefined) fail('InstalledModelJournalRequired');
    if (checkpointInstallation !== undefined &&
        (checkpointInstallation.checkpoints !== value || checkpointInstallation.journal !== value.journal)) {
      fail('InstalledModelJournalChanged');
    }
    return value;
  };
  function installOriginalJournal() {
    const value = checkpoints();
    if (value.journal === undefined) fail('InstalledModelJournalRequired');
    checkpointInstallation ??= {checkpoints: value, journal: value.journal};
    return value;
  }
  function admittedInventory(originals, immediate, token) {
    const retained = token ?? custody.get(originals.fixedInputReceiptWire)?.values().next().value;
    const prior = inventories.get(originals.fixedInputReceiptWire);
    if (retained === undefined && prior === undefined || retained?.available === false) {
      fail('ModelFixedInputCustodyUnavailable');
    }
    const admitted = retained === undefined ? prior : {
      digest: originalDigest(retained.snapshot.originals), receipt: retained.receipt,
      scopeCid: retained.snapshot.scopeCid, inputArtifactCid: retained.snapshot.inputArtifactCid};
    if (originalDigest(originals) !== admitted.digest) fail('ModelFixedInputOriginalMismatch');
    const facts = parseCore((immediate ? runtime.modelImmediateCallSetAdmit
      : runtime.modelCallSetAdmit)(canonicalJson(originals)));
    if (facts.scopeCid !== admitted.scopeCid ||
        facts.inputArtifactCid !== admitted.inputArtifactCid) fail('ModelFixedInputOriginalMismatch');
    if (retained !== undefined) inventories.set(originals.fixedInputReceiptWire, admitted);
    return JSON.parse(canonicalJson({...facts, fixedInputCustody: {...admitted.receipt, inputArtifactCid: facts.inputArtifactCid},
      retryBinding: {owner: 'single_attempt_model_execution', maxAttempts: 1},
      slots: facts.slots.map(slot => ({...slot, maxAttempts: 1}))}));
  }
  async function readSettled({originals, entry, attemptWire, authorityWire}, retainRecord, beforeRead) {
    const definition = control.admit('run_definition',
      JSON.parse(originals.originalRunWire).runDefinitionWire, limits);
    const bodies = {};
    const evidence = {};
    for (const name of roles) {
      const holdingCid = control.modelScopedPrivateHoldingCid(definition, storeAuthorityCid, entry, name);
      const holding = await store.inspectPhysicalHolding(holdingCid);
      if (holding === undefined) break;
      // Optional Evidence reserves its copy envelope before private decoding.
      // Normal execution restoration keeps its existing Store-owned limits.
      beforeRead?.(holding.objects.reduce((sum, object) => sum + object.byte_count, 0));
      const wire = new TextDecoder('utf-8', {fatal: true}).decode(
        await store.readPrivateEvidence(name, holding.manifest_cid, holdingCid));
      if (await store.confirmPrivateEvidence({name, semanticCid: holding.manifest_cid, holdingCid, wire}) === undefined) {
        fail('ModelSettlementCustodyLost');
      }
      bodies[name] = wire;
      evidence[name] = {cid: holding.manifest_cid, holdingCid};
    }
    if (roles.slice(0, 4).some(role => bodies[role] === undefined)) return null;
    if (bodies.model_call_attempt !== attemptWire || bodies.model_dispatch_authority !== authorityWire) {
      fail('ModelSettlementAttemptMismatch');
    }
    if (bodies.model_slot_capture === undefined || bodies.model_capture_bundle === undefined) {
      if (roles.slice(0, 4).some(role => bodies[role] === undefined)) return null;
      const admitted = JSON.parse(runtime.modelStoppedCallAdmit(canonicalJson(originals), entry.ordinal,
        attemptWire, authorityWire, bodies.model_attempt_accounting, bodies.model_attempt_outcome));
      if (admitted.ok !== true) return null;
      if (admitted.attemptCid !== entry.attemptCid || admitted.slotCid !== entry.slotCid ||
          admitted.accountingCid !== evidence.model_attempt_accounting.cid ||
          admitted.outcomeCid !== evidence.model_attempt_outcome.cid) fail('ModelStoppedProofMismatch');
      const record = Object.freeze({bodies, evidence, state: 'SavedFailure', terminalFailure: true});
      retainRecord?.(record);
      return {entry: entryIdentity(entry), state: 'SavedFailure', durable: true,
        evidence: {...evidence, terminalFailure: true}, retryAllowed: false};
    }
    const capture = control.admitRunEvidence('model_slot_capture', bodies.model_slot_capture, limits);
    // The physical Model owner seals this inventory into its slot capture.
    // Store schema admission alone cannot substitute another Ref or call.
    checked(moon.clientProgramVerifyInferAttachmentAdmission(
      checked(moon.strategyRunEvidenceAdmit('model_slot_capture', capture.wire, 16384, 1024, 20)),
      checked(moon.strategyRunEvidenceAdmit('model_dispatch_authority', authorityWire, 16384, 1024, 20)),
      bodies.model_attachment_admission === undefined ? undefined : checked(
        moon.strategyRunEvidenceAdmit('model_attachment_admission', bodies.model_attachment_admission,
          16384, 1024, 20))));
    const outcome = JSON.parse(capture.wire).outcome;
    const bundle = checked(moon.clientProgramReadInferCaptureBundle(bodies.model_capture_bundle,
      evidence.model_capture_bundle.cid));
    try {
      const document = JSON.parse(bodies.model_capture_bundle);
      if (document.captures.length !== (outcome === 'ok' ? 1 : 0)) fail('ModelSettlementResponseMismatch');
      const observationWire = outcome === 'ok' ? canonicalJson(document.captures[0].evidence) : undefined;
      const facts = parseCore(runtime.modelSavedCallAdmit(canonicalJson(originals), entry.ordinal,
        attemptWire, authorityWire, bodies.model_attempt_accounting,
        bodies.model_attempt_outcome, bodies.model_slot_capture, observationWire));
      if (facts.attemptCid !== entry.attemptCid || facts.slotCid !== entry.slotCid ||
          facts.captureCid !== evidence.model_slot_capture.cid) fail('ModelSettlementProofMismatch');
      const record = Object.freeze({bodies, evidence, state: facts.state});
      retainRecord?.(record);
      return {entry: entryIdentity(entry), state: facts.state, durable: true, evidence, retryAllowed: false};
    } finally { moon.clientProgramReleaseInferCaptureBundle(bundle); }
  }
  const verifier = Object.freeze({
    admitOriginalRun: ({originalRunWire}) => parseCore(runtime.modelOriginalRunAdmit(originalRunWire)),
    admitCallSet: originals => admittedInventory(originals, false),
    admitImmediateCallSet: originals => admittedInventory(originals, true),
    admitAttempt: ({originals, slot, attemptWire, authorityWire, attemptIndex}) =>
      parseCore(runtime.modelImmediateCallAttemptAdmit(canonicalJson(originals), slot.ordinal,
        attemptWire, authorityWire, attemptIndex)),
    // JSON serialization preserves journal data strings verbatim. The bounded
    // Common issuer supplies canonical data identities, not current grants.
    projectOriginalJournalIdentity: ({originals, row}) =>
      parseCore(runtime.modelOriginalJournalIdentity(JSON.stringify(originals), JSON.stringify(row))),
    projectOriginalCurrentCut: ({facts}) =>
      parseCore(runtime.modelOriginalJournalCutData(JSON.stringify(facts))).cut,
    originalStateSaved: Object.freeze({
      inspect: observation => checkpoints().originalModelStateSavedFacts(observation),
      current: observation => checkpoints().originalModelStateSavedObservationCurrent(observation),
    }),
    originalResourceCut: Object.freeze({
      inspect: park => originalResourceCut(park).facts,
      current: park => {
        const original = originalResourceCuts.get(park)?.deref();
        return original?.facts !== undefined && original.current() ? park : undefined;
      },
      invalidationCurrent: (request, park) => originalResourceCut(park).invalidationCurrent(request),
    }),
    admitImmediateEntry({decision, preparedCallSet, inventory, originals, slot, attemptIndex,
      attemptCid, attemptWire, authorityWire, at}) {
      const owner = live.get(preparedCallSet);
      const facts = authorizationDispatchFacts(decision);
      const pending = owner?.pending;
      if (!owner?.available || owner.decision !== decision || facts === undefined ||
          facts.configurationCid !== originals.expectedBoundary.configuration_cid ||
          facts.principal !== originals.expectedBoundary.principal ||
          pending?.slot !== slot.ordinal || pending.callWire !== originals.slotWires[slot.ordinal] ||
          pending.attemptWire !== attemptWire || pending.authorityWire !== authorityWire ||
          !owner.operation.entryCurrent(pending.entry, preparedCallSet) ||
          owner.currentProvider() !== true || Date.parse(at) >= Date.parse(inventory.runValidUntil)) {
        fail('ModelImmediateOwnerRejected');
      }
      const attempted = parseCore(runtime.modelImmediateCallAttemptAdmit(canonicalJson(originals),
        slot.ordinal, attemptWire, authorityWire, attemptIndex));
      if (attempted.attemptCid !== attemptCid) fail('ModelImmediateOwnerRejected');
      const authority = control.admitRunEvidence('model_dispatch_authority', authorityWire, limits);
      return {...select(inventory, scopeKeys), ordinal: slot.ordinal, slotCid: slot.slotCid,
        attemptIndex, attemptCid, authorityCid: authority.identity, current: true,
        admittedAt: at, runValidUntil: inventory.runValidUntil, dispatchValidUntil: inventory.runValidUntil};
    },
    verifySettlement: readSettled,
  });
  async function prime(record) {
    const receiptWire = record.originals.fixedInputReceiptWire;
    const receipt = JSON.parse(receiptWire);
    if (receipt.runId !== record.inventory.runId ||
        receipt.runDefinitionCid !== record.inventory.runDefinitionCid) fail('ModelSnapshotBindingMismatch');
    const bytes = await checkpoints().readModelInput(receipt);
    const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
    const snapshot = JSON.parse(wire);
    if (snapshot.version !== 'actql-installed-model-input/0.1' ||
        snapshot.scopeCid !== record.scopeCid || receipt.runId !== record.inventory.runId ||
        receipt.runDefinitionCid !== record.inventory.runDefinitionCid) fail('ModelSnapshotBindingMismatch');
    checkCapturedInventory(snapshot.capturedContent, receipt.runDefinitionCid, snapshot.capturedContentBinding);
    const token = retain(receiptWire, receipt, snapshot, bytes.byteLength);
    try {
      admittedInventory(record.originals, record.checkpointCid === null, token);
      return token;
    } catch (error) { release(token); throw error; }
  }
  async function observe(entry) {
    const result = await (entry.provenance === 'immediate'
      ? checkpoints().journal.observeImmediateModelCall(entry)
      : checkpoints().journal.observeResumedCall(entry));
    diagnostic('model_call_observed', {ref: {namespaceId, authorityScopeCid,
      runDefinitionCid: entry.runDefinitionCid}, task: entry.taskIndex,
      attempt: entry.attemptIndex, attemptCid: entry.attemptCid, slot: entry.ordinal,
      outcome: {SavedSuccess: 'succeeded', SavedFailure: 'failed',
        EnteredUnknown: 'unknown', Unsent: 'pending'}[result?.state]});
    return result;
  }
  async function openOwned({operation, preparedCallSet, plan, selected, principalId,
    declaredResults, submission, signal, existing, inputToken, claim, parentResume, journalPort,
    sourceContinuation, retainEvidenceCopy, originalPreparation, preserveEvidenceInputs = true}, ownership) {
    let rawSelection = snapshotModelRawCaptureSelection(selected.rawCaptureSelection);
    const rawBinding = rawSelection === undefined ? undefined :
      {attempted: false, complete: false, issue: undefined,
        persistence: undefined, holdings: [], originalsFlight: undefined,
        originalsPending: false, readCleanup: undefined, readCleanupFlight: undefined};
    // Reject a known missing installation before Approval/Entry, not after
    // consuming an attempt. Method checks are availability only: the actual
    // Store remains this controller's selected original, never caller data.
    if (rawBinding !== undefined &&
        (typeof operation.ioNotification?.notify !== 'function' ||
          typeof control.installedModelRawSelectionOriginals !== 'function' ||
          ['confirmModelRawCaptureOriginals', 'confirmModelRawEvidence',
            'prepareModelRawEvidence', 'commitPhysicalHolding'].some(name =>
            typeof store?.[name] !== 'function'))) {
      fail('InstalledModelRawStoreUnavailable');
    }
    // The Host's Checkpoint installation is created after this controller.
    // Fix its actual physical identity only when the original scope is being
    // installed, never from an initial undefined value or future replacement.
    if (originalPreparation !== undefined &&
        (operation.originalResourceScope?.() !== originalPreparation.scope ||
          originalPreparation.scope === undefined || originalPreparation.control !== control ||
          originalPreparation.compiled !== plan.compiled ||
          originalPreparation.runDefinition !== plan.runDefinition)) {
      fail('InstalledModelOriginalScopeMismatch');
    }
    const cp = originalPreparation === undefined ? checkpoints() : installOriginalJournal();
    const facts = operation.preparedFacts(preparedCallSet);
    const run = JSON.parse(plan.runDefinition.wire);
    let token;
    let originals;
    let scope;
    const binding = selected.providerBinding;
    if (binding === undefined) fail('InstalledModelProviderBindingRequired');
    if (existing !== undefined) {
      token = inputToken;
      if (leases.get(token)?.receiptWire !== existing.originals.fixedInputReceiptWire ||
          !token.available) fail('ModelFixedInputCustodyUnavailable');
      originals = existing.originals;
      scope = control.admitRunEvidence('model_invocation_scope', originals.scopeWire, limits);
      if (facts.inputArtifactWire !== originals.inputArtifactWire ||
          !same(facts.slotWires, originals.slotWires) ||
          facts.callScopeSnapshotWire !== token.snapshot.callScopeSnapshotWire) fail('ModelRestoredInventoryChanged');
    } else {
      const account = selected.observeAccount();
      const evaluated = JSON.parse(moon.executionAuthorizationEvaluationJson(
        moon.executionAuthorizationEvaluate(account, principalId, facts.providerId, facts.modelTaskCid, 'infer')));
      if (!['allow', 'delegate'].includes(evaluated.outcome) || typeof evaluated.entry_id !== 'string') {
        fail('InstalledInferAuthorityUnavailable');
      }
      const coordinates = moon.clientProgramInferPlanBoundary(selected.graph);
      const provider = JSON.parse(binding.wire);
      const context = cp.modelContext;
      const expectedBoundary = {unit_id: facts.unitId, task_index: runtimeField(coordinates, 0),
        strategy_revision: runtimeField(coordinates, 2), inference_barrier_cid: runtimeField(coordinates, 3),
        account_id: context.accountId, configuration_cid: context.configurationCid,
        entry_id: evaluated.entry_id, principal: principalId, connection: facts.providerId,
        resource: facts.modelTaskCid, context_cid: context.contextCid,
        installation_revision_cid: provider.installation_revision_cid,
        configuration_contract_cid: provider.configuration_contract_cid,
        provider_configuration_cid: provider.configuration_cid};
      const input = control.admitRunEvidence('model_input_artifact', facts.inputArtifactWire, limits);
      scope = control.sealRunEvidence('model_invocation_scope', canonicalJson({
        version: 'actql-model-invocation-scope/0.1', run_definition_cid: plan.runDefinition.identity,
        task_index: runtimeField(coordinates, 0), strategy_revision: runtimeField(coordinates, 2),
        inference_barrier_cid: runtimeField(coordinates, 3), input_artifact_cid: input.identity,
        model_call_slot_cids: facts.slotWires.map(wire => control.admitRunEvidence('model_call_slot', wire, limits).identity),
        provider_binding_cid: binding.identity,
        authorization_context: {account_id: context.accountId, configuration_cid: context.configurationCid,
          entry_id: evaluated.entry_id, principal: principalId, connection: facts.providerId,
          resource: facts.modelTaskCid, operation: 'infer', boundary: 'activation', context_cid: context.contextCid},
      }), limits);
      const fixedBinding = canonicalJson({version: 'actql-model-fixed-input-binding/0.1',
        run_definition_cid: plan.runDefinition.identity, scope_cid: scope.identity,
        input_artifact_cid: input.identity, task_index: runtimeField(coordinates, 0), strategy_revision: runtimeField(coordinates, 2)});
      const exported = operation.exportPreparedInput(preparedCallSet, fixedBinding);
      originals = {originalRunWire: originalModelRunWire(plan.compiled, plan.runDefinition),
        preparedInvocationWire: plan.compiled.preparedEvidence.wire, scopeWire: scope.wire,
        providerBindingWire: binding.wire, inputArtifactWire: input.wire,
        slotWires: [...facts.slotWires], expectedBoundary};
      const contentGeneration = operation.contentRecovery?.();
      const capturedContent = operation.capturedContentRecovery?.();
      const capturedContentBinding = operation.capturedContentBinding?.();
      checkCapturedInventory(capturedContent, plan.runDefinition.identity, capturedContentBinding);
      if (operation.contentGenerationCount > 0 && contentGeneration === undefined) {
        fail('ModelContentGenerationCustodyMissing');
      }
      let snapshot = {version: 'actql-installed-model-input/0.1', scopeCid: scope.identity,
        inputArtifactCid: input.identity, originals, binding: fixedBinding,
        descriptorWire: exported.descriptorWire, rows: [...exported.rows],
        callScopeSnapshotWire: facts.callScopeSnapshotWire,
        providerOriginals: binding.originals, submission,
        ...(sourceContinuation === undefined ? {} : {sourceContinuation}),
        ...(contentGeneration === undefined ? {} : {contentGeneration}),
        ...(capturedContent === undefined ? {} : {capturedContent, capturedContentBinding})};
      let bodyWire = canonicalJson(snapshot);
      // Fresh Effect projection consumes its still-live completed requests.
      // It needs no optional providerInputs copy in the retained snapshot; the
      // mandatory original fixed-input snapshot and its receipt stay exact.
      const receipt = await withPreparedInferEvidence({configuration: preserveEvidenceInputs ? inferEvidence : undefined,
        moon, control, plan, selected, preparedCallSet, operation, authorityScopeCid,
        retainCopy: retainEvidenceCopy,
        consume(providerInputs) {
          if (providerInputs !== undefined) {
            const candidate = {...snapshot, providerInputs};
            const candidateWire = canonicalJson(candidate);
            // Optional preservation shares the existing custody ceiling.
            // Missing capture remains incomplete; it cannot fail Model work.
            if (Buffer.byteLength(candidateWire) <= MAX_MODEL_INPUT_BYTES) {
              snapshot = candidate;
              bodyWire = candidateWire;
            }
          }
          return cp.retainModelInput({runId: run.run_id,
            runDefinitionCid: plan.runDefinition.identity, bodyWire});
        }});
      checkpoints();
      if (!exported.current()) fail('ModelInputOwnerChangedDuringCommit');
      const receiptWire = canonicalJson(receipt);
      originals = {...originals, fixedInputReceiptWire: receiptWire};
      token = ownership.token = retain(receiptWire, receipt, snapshot, Buffer.byteLength(bodyWire));
    }
    const historicalProvider = control.admitRunEvidence('model_provider_binding', originals.providerBindingWire, limits);
    const bound = operation.bindModelScope(control, plan, preparedCallSet,
      {scope, provider: historicalProvider, expectedBoundary: originals.expectedBoundary});
    const inventory = admittedInventory(originals, existing?.checkpointCid == null, token);
    const owner = {operation, preparedCallSet, available: true, pending: undefined, decision: undefined,
      currentProvider: () => selected.currentProvider?.() !== false && binding.identity === inventory.providerBindingCid,
      entries: new Map()};
    let installedJournalPort;
    let originalInvalidation;
    let originalCut;
    let originalSave;
    let originalDispatchCut;
    function originalResourceReadCurrent(park, acquisition) {
      const originalScope = operation.originalResourceScope?.();
      if (!owner.available || originalPreparation === undefined ||
          originalScope === undefined || originalScope !== originalPreparation.scope ||
          checkpoints() !== cp || operation.originalResourceParkCurrent(park) !== park) {
        fail('ModelOriginalResourceReadUnavailable');
      }
      // Repeat the same original token's complete envelope/currentness after
      // every physical wait, including the later Store custody recheck. A
      // current park alone does not replace cancellation or capacity covers.
      if (acquisition !== undefined && operation.originalMetadataAcquisition(park) !== acquisition) {
        fail('InferOriginalMetadataAcquisitionUnavailable');
      }
      return originalScope;
    }
    async function selectedOriginalStorageEvidence(park, storageBinding, acquisition) {
      originalResourceReadCurrent(park, acquisition);
      if (typeof cp.modelOriginalStorageBindingEvidenceSelected !== 'function') {
        fail('InferOriginalMetadataAcquisitionUnavailable');
      }
      const evidence = await cp.modelOriginalStorageBindingEvidenceSelected({
        storageBinding, runDefinition: plan.runDefinition}, acquisition);
      originalResourceReadCurrent(park, acquisition);
      return evidence;
    }
    async function confirmOriginalResourceStateSaved(park, storageBinding, receipt) {
      const originalScope = originalResourceReadCurrent(park);
      if (typeof cp.confirmOriginalModelStateSavedSelected !== 'function' ||
          typeof cp.retireOriginalModelStateSavedObservation !== 'function') {
        fail('InferOriginalMetadataAcquisitionUnavailable');
      }
      const acquisition = operation.originalMetadataAcquisition(park);
      const original = originalCut;
      const saved = await cp.confirmOriginalModelStateSavedSelected({
        runDefinition: plan.runDefinition, storageBinding, receipt,
        identity: select(inventory, scopeKeys)}, acquisition);
      // Retain the actual issuer's observation before any fallible current or
      // origin recheck. Its original READ duty survives a late failure/stop.
      if (original !== undefined && original.park === park &&
          original.storageBinding === storageBinding && original.receipt === receipt) {
        original.saved = saved;
      }
      originalResourceReadCurrent(park, acquisition);
      const savedFacts = cp.originalModelStateSavedFacts(saved);
      const document = control.readModelOriginalResourceDocument(savedFacts.documentWire,
        {maxWireBytes: MAX_MODEL_INPUT_BYTES, maxNodes: 10000, maxDepth: 64});
      const storage = await selectedOriginalStorageEvidence(park, storageBinding, acquisition);
      originalResourceReadCurrent(park, acquisition);
      control.checkCheckedClientInferOriginalParkedStorageOrigin(plan.compiled,
        plan.runDefinition, selected.graph, originalScope, park, document,
        originalPreparation.nodeInstallation, storage);
      originalResourceReadCurrent(park, acquisition);
      return saved;
    }
    function originalJournalInstallation() {
      if (originalPreparation === undefined ||
          live.get(preparedCallSet) !== owner ||
          operation.originalResourceScope?.() !== originalPreparation.scope ||
          checkpoints() !== cp || cp.journal !== checkpointInstallation?.journal) {
        fail('ModelOriginalJournalInstallationUnavailable');
      }
      if (installedJournalPort === undefined) {
        const observation = cp.journal.observeOriginalModelJournal(inventory);
        installedJournalPort = cp.journal.installOriginalModelJournalPort(observation);
      }
      cp.journal.originalModelJournalPortCurrent(installedJournalPort);
      return installedJournalPort;
    }
    live.set(preparedCallSet, owner);
    ownership.owner = owner;
    const persistence = selected.entryPersistence !== 'async' ? undefined :
      createNodeInferEntryPersistence({moon, preparedCallSet, journal: cp.journal,
        ioNotification: operation.ioNotification,
        settled(entry, receipt) {
          if (owner.pending?.entry !== entry) return;
          if (receipt !== undefined) owner.entries.set(owner.pending.slot, receipt);
          owner.pending = undefined;
        }});
    if (observation?.canMeasure('infer')) {
      const installed = operation.bindModelObservation(preparedCallSet,
        createInferPhysicalObservation({observation,
          reference: {namespaceId, authorityScopeCid},
          receiptAt: slot => owner.entries.get(slot)}));
      if (!installed) observation.noteLoss();
    }
    const unreconciled = new Map();
    let view = existing === undefined ? undefined : cp.journal.readModelCalls(existing.inventory);
    if (view !== undefined) {
      for (const slot of view.slots) {
        const entry = slot.attempts.at(-1);
        if (entry === undefined) continue;
        await observe(entry);
      }
      view = cp.journal.readModelCalls(existing.inventory);
      for (const slot of view.slots) {
        const entry = slot.attempts.at(-1);
        if (entry === undefined) continue;
        owner.entries.set(slot.ordinal, entry);
        const historical = cp.journal.readModelAttemptOriginals(entry);
        if (slot.state === 'EnteredUnknown') {
          if (selected.reconcileResponse !== undefined) unreconciled.set(slot.ordinal, {entry, historical});
          operation.restoreUnknown(preparedCallSet, slot.ordinal,
            checked(moon.strategyRunEvidenceAdmit('model_call_attempt', historical.attemptWire, 16384, 1024, 20)),
            checked(moon.strategyRunEvidenceAdmit('model_dispatch_authority', historical.authorityWire, 16384, 1024, 20)));
        } else {
          // Store remains the authority. Keep response bodies only while
          // restoring this call, rather than caching every settled attempt.
          let stored;
          await readSettled({originals, entry, ...historical}, record => { stored = record; });
          if (stored === undefined) fail('ModelSavedCustodyUnavailable');
          if (stored.terminalFailure === true) fail('ModelSavedTerminalFailure');
          const leaf = name => checked(moon.strategyRunEvidenceAdmit(name, stored.bodies[name], 16384, 1024, 20));
          const bundle = checked(moon.clientProgramReadInferCaptureBundle(stored.bodies.model_capture_bundle,
            stored.evidence.model_capture_bundle.cid));
          try { operation.restoreCall(preparedCallSet, slot.ordinal, leaf('model_slot_capture'),
            moon.clientProgramInferAttemptRecords(leaf('model_call_attempt'), leaf('model_attempt_accounting'),
              leaf('model_attempt_outcome'), leaf('model_dispatch_authority')), bundle,
            stored.bodies.model_attachment_admission === undefined ? undefined : leaf('model_attachment_admission')); }
          finally { moon.clientProgramReleaseInferCaptureBundle(bundle); }
        }
      }
    }
    const preparedBody = JSON.parse(plan.compiled.preparedEvidence.wire);
    const authoring = control.sealRunEvidence('authoring_context', canonicalJson({
      version: 'actql-authoring-context/0.1', program_definition_cid: JSON.parse(facts.inputArtifactWire).program_definition_cid,
      annotations: []}), limits);
    const review = control.sealRunEvidence('run_review_projection', canonicalJson({
      version: 'actql-run-review-projection/0.1', prepared_invocation_cid: plan.compiled.preparedEvidence.identity,
      execution_context_cid: preparedBody.execution_context_cid, host_policy_cid: preparedBody.host_policy_cid,
      approval_claims: ['invocation_scope_approved'], authoring_context_cid: authoring.identity,
      redaction_policy_cid: contentCid({version: 'actql-installed-model-review-redaction/0.1', disclose: 'scope-identities'}),
      sensitivity: 'restricted', retention_class: 'approval-evidence', encryption_required: true,
      expires_at: run.valid_until, displayed_scope: {model_invocation_scope_cid: scope.identity,
        model_call_slot_cids: inventory.slots.map(slot => slot.slotCid)}, displayed_authoring_context: [],
    }), limits);
    let gate, gateOpening;
    let gateCloseAttempted = false, gateReleased = false;
    function rawOriginalsCurrent() {
      checkpoints();
      if (!owner.available || !token.available || !owner.currentProvider() ||
          rawSelection?.selectionAvailable() !== true ||
          originalPreparation !== undefined &&
            operation.originalResourceScope?.() !== originalPreparation.scope) {
        fail('InstalledModelRawOriginalsUnavailable');
      }
      signal?.throwIfAborted();
    }
    function confirmRawOriginals() {
      if (rawBinding === undefined) return;
      rawOriginalsCurrent();
      if (rawBinding.originalsFlight !== undefined) return rawBinding.originalsFlight;
      // The finite Common projection is captured before the first Store await.
      // No copied packet/CID or this availability result issues a raw grant.
      const originals = control.installedModelRawSelectionOriginals(rawSelection);
      rawBinding.originalsPending = true;
      rawBinding.originalsFlight = (async () => {
        try {
          await store.confirmModelRawCaptureOriginals(originals, storeAuthorityCid);
          rawOriginalsCurrent();
        } catch (error) {
          const handle = error?.cleanupHandle;
          // Only this actual selected Store's failed physical read supplies
          // retry custody. Never lose its FD merely because approval failed.
          if (typeof handle?.status === 'function' &&
              typeof handle?.retry === 'function' && handle.status().pending === true) {
            rawBinding.readCleanup = handle;
          }
          throw error;
        } finally { rawBinding.originalsPending = false; }
      })();
      return rawBinding.originalsFlight;
    }
    const cleanup = () => {
      owner.available = false;
      if (gateOpening !== undefined || originalSave?.pending === true || originalDispatchCut?.pending === true ||
          rawBinding?.originalsPending === true || rawBinding?.readCleanupFlight !== undefined) return false;
      if (rawBinding?.readCleanup !== undefined) {
        if (rawBinding.readCleanup.status().pending === true) {
          const handle = rawBinding.readCleanup;
          rawBinding.readCleanupFlight = Promise.resolve().then(() => handle.retry())
            .catch(() => { /* Retain the same original FD for cleanup retry. */ })
            .finally(() => {
              rawBinding.readCleanupFlight = undefined;
              try { operation.ioNotification.notify(); } catch { /* Wake is not cleanup proof. */ }
            });
          return false;
        }
        rawBinding.readCleanup = undefined;
      }
      if (gate !== undefined && !gateReleased) {
        const recover = gateCloseAttempted;
        gateCloseAttempted = true;
        const result = recover ? gate.cleanup() : gate.close();
        gateReleased = result !== false && gate.cleanupPending() === false;
      }
      if (gate !== undefined && !gateReleased || operation.cleanupPending()) return false;
      if (originalCut?.saved !== undefined) {
        // Child cleanup alone cannot retire unresolved cut users. Successful
        // original invalidation already retires these two Common borrows.
        if (originalInvalidation !== undefined || originalCut.matched !== undefined ||
            originalCut.document !== undefined) return false;
        // installed-infer-run awaits THIS cleanup before settling the original
        // READ. Failure keeps the same observation/token for cleanup retry.
        cp.retireOriginalModelStateSavedObservation(originalCut.saved);
        originalCut.saved = undefined;
      }
      if (live.get(preparedCallSet) === owner) live.delete(preparedCallSet);
      if (originalCut !== undefined) {
        originalResourceCuts.delete(originalCut.park);
        if (originalCut.matched !== undefined) operation.retireOriginalCurrentStateMatch(originalCut.matched);
        if (originalCut.document !== undefined) operation.retireOriginalCurrentStateDocument(originalCut.document);
        originalCut = undefined;
      }
      rawSelection = undefined;
      if (rawBinding !== undefined) {
        // Common's physical cleanup has already confirmed every original port's
        // Store/SDK retirement. Drop local aliases, not durable raw custody or
        // escaped saved receipts. A failed cleanup above retains both fields.
        rawBinding.persistence = undefined;
        rawBinding.holdings = undefined;
        rawBinding.originalsFlight = undefined;
      }
      installedJournalPort = undefined;
      originalInvalidation = undefined;
      originalSave = undefined;
      originalDispatchCut = undefined;
      originalPreparation = undefined;
      release(token);
      return true;
    };
    const cleanupPending = () => owner.available || gateOpening !== undefined ||
      gate !== undefined && !gateReleased || token.available;
    const gateOptions = {runId: run.run_id,
      runDefinitionCid: plan.runDefinition.identity, unitId: facts.unitId, scopeCid: scope.identity,
      tuple: {connection: facts.providerId, resource: facts.modelTaskCid, operation: 'infer'},
      declaredResults, modelCallSet: originals, reviewWire: originals.reviewWire ?? review.wire,
      continuationWire: canonicalJson({version: 'actql-installed-model-continuation/0.1',
        scopeCid: scope.identity, receipt: token.receipt, submission: token.snapshot.submission}),
      beforeDefer: async () => { if (!token.available) fail('ModelFixedInputCustodyUnavailable'); },
      attachImmediate: view?.checkpointCid === null,
      ...(journalPort === undefined ? {} : {journalPort})};
    const continuationView = Object.freeze({originals, inventory, token, scope, preparedCallSet,
      originalJournalInstallation,
      prepareOriginalResourcesForDispatch() {
        if (!owner.available || checkpoints()!==cp) fail('ModelOriginalCurrentCutUnavailable');
        if (originalDispatchCut!==undefined) return originalDispatchCut.flight;
        const codec=selectedInferOriginalCurrentStateCodec(originalPreparation?.metadataInstallation,
          originalPreparation?.nodeInstallation);
        if (typeof operation.originalStoreBootstrapAcquisition !== 'function' ||
            typeof cp.observeModelOriginalStorageBindingSelected !== 'function' ||
            typeof cp.modelOriginalStorageBindingBootstrapSelected !== 'function') {
          fail('InferOriginalMetadataAcquisitionUnavailable');
        }
        const acquisition=operation.originalStoreBootstrapAcquisition();
        // This same installed operation already owns all initialization and
        // Store/codec overlap. There is no request-supplied serializer/amount.
        const original=originalDispatchCut={park:undefined,flight:undefined,pending:true};
        original.flight=(async()=>{
          try {
            const storageBinding=await cp.observeModelOriginalStorageBindingSelected(
              {runDefinition:plan.runDefinition},acquisition);
            if (!owner.available || checkpoints()!==cp) fail('ModelOriginalCurrentCutUnavailable');
            if (operation.originalStoreBootstrapAcquisition()!==acquisition) fail('ModelOriginalCurrentCutUnavailable');
            const origin=await continuationView.originalResourceOrigin(storageBinding,acquisition);
            if (!owner.available || checkpoints()!==cp) fail('ModelOriginalCurrentCutUnavailable');
            if (operation.originalStoreBootstrapAcquisition()!==acquisition) fail('ModelOriginalCurrentCutUnavailable');
            // Capture immutable origin DATA before park, and retain the actual
            // returned park immediately before any further fallible operation.
            const originWire=canonicalJson(origin);
            original.park=operation.parkOriginalResourcesForStateWrite();
            const saved=await continuationView.retainOriginalResourceCurrentCut(original.park,
              storageBinding,originWire,codec);
            originalResourceReadCurrent(original.park);
            cp.journal.commitOriginalModelCurrentCut(saved.reference);
            continuationView.beginOriginalResourceInvalidation(saved.reference,original.park);
            continuationView.completeOriginalResourceInvalidation();
            // Unit only: journal ACK/fence consumption never issues InferAllow
            // or bypasses the original final Entry/current send gate.
          } finally {original.pending=false;}
        })();
        return original.flight;
      },
      retainOriginalResourceCurrentCut(park, storageBinding, originWire, codec) {
        if (originalSave !== undefined) {
          if (originalSave.park !== park || originalSave.storageBinding !== storageBinding || originalSave.originWire !== originWire ||
              originalSave.codec.deref() !== codec) fail('ModelOriginalCurrentCutBindingMismatch');
          originalResourceReadCurrent(originalSave.park);
          return originalSave.promise;
        }
        // This method is internal to the original opened operation. Origin DATA
        // was selected before park by its existing checked getter; matching
        // strings never replace the checks against the actual parked Owner.
        if (!owner.available || checkpoints() !== cp ||
            originalPreparation?.scope !== operation.originalResourceScope?.() ||
            typeof originWire !== 'string' ||
            typeof control.encodeModelOriginalResourceDocument !== 'function' ||
            typeof cp.retainOriginalModelStateSelected !== 'function') fail('ModelOriginalCurrentCutUnavailable');
        // The original caller already retains this actual park. Refusing a
        // codec/envelope must not lose a freshly issued fence in a local only.
        originalResourceReadCurrent(park);
        // The original complete simultaneous envelope precedes this record,
        // codec snapshots, Writer, trees, Promise and physical Store I/O.
        const acquisition = operation.originalMetadataAcquisition(park);
        const limits = originalCurrentCodecLimits(codec);
        const original = originalSave = {storageBinding, originWire, codec: new WeakRef(codec),
          park, promise: undefined, receipt: undefined, reference: undefined, pending: true};
        original.promise = (async () => {
          let writer;
          try {
            const observation = cp.journal.observeOriginalModelJournal(inventory);
            const facts = cp.journal.originalModelJournalObservationFacts(observation);
            const cutWire = canonicalJson(verifier.projectOriginalCurrentCut({facts}));
            const envelope = {maxWireBytes: limits.decode.parse.max_input_bytes,
              maxNodes: limits.decode.parse.max_nodes, maxDepth: limits.decode.parse.max_depth};
            originalResourceReadCurrent(park, acquisition);
            writer = operation.prepareOriginalCurrentStateWriter(park, envelope);
            for (;;) {
              originalResourceReadCurrent(park, acquisition);
              const poll = operation.advanceOriginalCurrentStateWriter(park, writer, limits.quantum);
              if (poll.kind === 'complete') break;
              if (poll.kind !== 'continue' || poll.work < 1) fail('ModelOriginalCurrentStateWriteFailed');
              await yieldEventLoop();
            }
            let stateWire = operation.finishOriginalCurrentStateWriter(park, writer);
            operation.cancelOriginalCurrentStateWriter(writer);
            writer = undefined;
            const bodyWire = control.encodeModelOriginalResourceDocument(originWire,
              stateWire, cutWire, 'parked', envelope);
            stateWire = undefined;
            let document = control.readModelOriginalResourceDocument(bodyWire, envelope);
            const storage = await selectedOriginalStorageEvidence(park, storageBinding, acquisition);
            originalResourceReadCurrent(park, acquisition);
            control.checkCheckedClientInferOriginalParkedStorageOrigin(plan.compiled,
              plan.runDefinition, selected.graph, originalPreparation.scope, park,
              document, originalPreparation.nodeInstallation, storage);
            // This temporary canonical view has served its origin guard. Keep
            // the exact wire/park/custody, not this extra tree, across save.
            // This drops one alias, not a GC, Store or Resource retirement ACK.
            document = undefined;
            cp.journal.reconfirmOriginalModelJournal(observation);
            original.receipt = await cp.retainOriginalModelStateSelected({runDefinition: plan.runDefinition,
              storageBinding, bodyWire}, acquisition);
            // A late stop or lost Store response keeps the same park/custody;
            // it cannot be reclassified as unsaved or start another attempt.
            originalResourceReadCurrent(park, acquisition);
            cp.journal.reconfirmOriginalModelJournal(observation);
            original.reference = await continuationView.prepareOriginalResourceCurrentCut(
              park, storageBinding, original.receipt, limits);
            originalResourceReadCurrent(park, acquisition);
            return Object.freeze({park, receipt: original.receipt, reference: original.reference});
          } finally {
            if (writer !== undefined) operation.cancelOriginalCurrentStateWriter(writer);
            original.pending = false;
          }
        })();
        return original.promise;
      },
      prepareOriginalResourceCurrentCut(park, storageBinding, receipt, codec) {
        originalResourceReadCurrent(park);
        // Validate the installed runtime before Store I/O and use the original
        // envelope before even limit-snapshot/validation temporary allocation.
        if (typeof moon.clientProgramAdvanceInferOriginalCurrentStateComparisonWithMatch !== 'function' ||
            typeof moon.clientProgramInferOriginalCurrentStateMatchPoll !== 'function' ||
            typeof moon.clientProgramInferOriginalCurrentStateMatchCurrent !== 'function' ||
            typeof moon.clientProgramRetireInferOriginalCurrentStateMatch !== 'function') {
          fail('ModelOriginalCurrentCutUnavailable');
        }
        const acquisition = operation.originalMetadataAcquisition(park);
        if (originalCut !== undefined) {
          if (originalCut.park !== park || originalCut.storageBinding !== storageBinding ||
              originalCut.receipt !== receipt || originalCut.codec.deref() !== codec) {
            fail('ModelOriginalCurrentCutBindingMismatch');
          }
          return originalCut.promise;
        }
        // This is one private installation caller, not a second Resource or
        // journal state machine. Fund this record, Promise/frames and BOTH
        // Common trees through the original installation before using it.
        const limits = originalCurrentCodecLimits(codec);
        const original = originalCut = {park, storageBinding, receipt, saved: undefined, codec: new WeakRef(codec),
          promise: undefined, document: undefined, matched: undefined, facts: undefined,
          current() {
            return original.matched !== undefined && original.document !== undefined &&
              live.get(preparedCallSet) === owner && checkpoints() === cp &&
              operation.originalCurrentStateMatchCurrent(park, original.matched) === original.matched;
          },
          invalidationCurrent: request => operation.originalResourceInvalidationCurrent(park, request)};
        originalResourceCuts.set(park, new WeakRef(original));
        original.promise = (async () => {
          const observation = cp.journal.observeOriginalModelJournal(inventory);
          const journalFacts = cp.journal.originalModelJournalObservationFacts(observation);
          const saved = await confirmOriginalResourceStateSaved(park, storageBinding, receipt);
          originalResourceReadCurrent(park, acquisition);
          cp.journal.reconfirmOriginalModelJournal(observation);
          const savedFacts = cp.originalModelStateSavedFacts(saved);
          const cut = verifier.projectOriginalCurrentCut({facts: journalFacts});
          if (!same(savedFacts.cut, cut)) fail('ModelOriginalCurrentCutBindingMismatch');
          let decoder, comparison;
          try {
            // Decode exactly THIS authenticated saved wire. An arbitrary
            // completed match cannot be paired with another saved document.
            decoder = operation.startOriginalCurrentStateDecode(park, savedFacts.documentWire, limits.decode);
            for (;;) {
              originalResourceReadCurrent(park, acquisition);
              const poll = operation.advanceOriginalCurrentStateDecode(park, decoder, limits.quantum);
              if (poll.kind === 'failed') fail('ModelOriginalCurrentStateDecodeFailed');
              if (poll.kind === 'complete') {original.document = poll.document; break;}
              if (poll.kind !== 'continue' || poll.work < 1) fail('ModelOriginalCurrentStateDecodeFailed');
            }
            comparison = operation.startOriginalCurrentStateComparison(park, original.document, limits.comparisonWork);
            for (;;) {
              originalResourceReadCurrent(park, acquisition);
              const poll = operation.advanceOriginalCurrentStateComparisonWithMatch(park, comparison, limits.quantum);
              if (poll.kind === 'failed') fail('ModelOriginalCurrentStateComparisonFailed');
              if (poll.kind === 'complete') {original.matched = poll.matched; break;}
              if (poll.kind !== 'continue' || poll.work < 1) fail('ModelOriginalCurrentStateComparisonFailed');
            }
            originalResourceReadCurrent(park, acquisition);
            if (!original.current()) fail('ModelOriginalCurrentCutUnavailable');
            cp.journal.reconfirmOriginalModelJournal(observation);
            // Both data projections originate in existing trusted Owners.
            // Matching strings alone never issue a park or COMMIT permission.
            original.facts = Object.freeze({identity: savedFacts.identity,
              phase: savedFacts.phase, cut: savedFacts.cut});
            return cp.journal.prepareOriginalModelCurrentCut(observation,
              {parkReceipt: park, savedReceipt: saved});
          } catch (error) {
            if (original.matched !== undefined) operation.retireOriginalCurrentStateMatch(original.matched);
            if (original.document !== undefined) operation.retireOriginalCurrentStateDocument(original.document);
            original.matched = undefined;
            original.document = undefined;
            original.facts = undefined;
            throw error;
          } finally {
            if (decoder !== undefined) operation.cancelOriginalCurrentStateDecode(decoder);
            if (comparison !== undefined) operation.cancelOriginalCurrentStateComparison(comparison);
          }
        })();
        return original.promise;
      },
      async readOriginalResourceState(park, storageBinding, receipt) {
        const originalScope = originalResourceReadCurrent(park);
        if (typeof cp.readOriginalModelStateSelected !== 'function') {
          fail('InferOriginalMetadataAcquisitionUnavailable');
        }
        // This exact installed operation supplies its own nominal acquisition.
        // No external operation/J/callback/Bool/CID can issue this selection.
        const acquisition = operation.originalMetadataAcquisition(park);
        const document = await cp.readOriginalModelStateSelected({runDefinition: plan.runDefinition,
          storageBinding, receipt}, acquisition);
        originalResourceReadCurrent(park, acquisition);
        // Actual Store custody is rechecked by CP. Match the twelve checked
        // originals separately; schema/CID equality alone cannot prove them.
        const storage = await selectedOriginalStorageEvidence(park, storageBinding, acquisition);
        originalResourceReadCurrent(park, acquisition);
        control.checkCheckedClientInferOriginalParkedStorageOrigin(plan.compiled,
          plan.runDefinition, selected.graph, originalScope, park, document,
          originalPreparation.nodeInstallation, storage);
        originalResourceReadCurrent(park, acquisition);
        return document;
      },
      confirmOriginalResourceStateSaved,
      async originalResourceOrigin(storageBinding, acquisition) {
        const originalScope = operation.originalResourceScope?.();
        const installation = originalPreparation?.nodeInstallation;
        if (originalScope === undefined || originalScope !== originalPreparation?.scope ||
            installation === undefined || checkpoints() !== cp ||
            typeof control.checkedClientInferOriginalResourceOriginField !== 'function') {
          fail('ModelOriginalResourceOriginUnavailable');
        }
        // This port reopens/rechecks its actual selected encrypted Store. The
        // returned evidence is data from that nominal binding, not a caller CID.
        if (acquisition !== undefined && operation.originalStoreBootstrapAcquisition() !== acquisition) {
          fail('ModelOriginalResourceOriginUnavailable');
        }
        const storage = await (acquisition === undefined
          ? cp.modelOriginalStorageBindingEvidence(storageBinding)
          : cp.modelOriginalStorageBindingBootstrapSelected(
            {storageBinding, runDefinition: plan.runDefinition}, acquisition));
        if (checkpoints() !== cp || operation.originalResourceScope?.() !== originalScope) {
          fail('ModelOriginalJournalInstallationChanged');
        }
        if (acquisition !== undefined && operation.originalStoreBootstrapAcquisition() !== acquisition) {
          fail('ModelOriginalResourceOriginUnavailable');
        }
        // Select these immutable originals BEFORE Resource park. Do not infer
        // them from current census bytes, response data or saved document fields.
        const origin = {};
        for (const field of ['run_id', 'run_definition_cid', 'prepared_invocation_cid',
          'host_policy_cid', 'execution_context_cid', 'program_definition_cid',
          'parameter_values_cid', 'barrier_cid', 'runtime_artifact_cid',
          'layout_artifact_cid', 'response_profile_cid', 'storage_binding_cid']) {
          origin[field] = control.checkedClientInferOriginalResourceOriginField(
            plan.compiled, plan.runDefinition, selected.graph, originalScope,
            installation, storage, field);
        }
        if (checkpoints() !== cp || operation.originalResourceScope?.() !== originalScope) {
          fail('ModelOriginalJournalInstallationChanged');
        }
        // This bounded data record/String overlap belongs to C's original
        // bootstrap inventory; its existence does not prove a numeric profile.
        return Object.freeze(origin);
      },
      originalJournalInvalidationCurrent(receipt, reference, park, request) {
        const port = originalJournalInstallation();
        const observed = cp.journal.originalModelJournalPortInvalidationCurrent(
          port, receipt, reference, park, request);
        if (observed !== receipt || operation.originalResourceParkCurrent(park) !== park ||
            checkpoints() !== cp) {
          fail('ModelOriginalJournalInstallationChanged');
        }
        // C's same request/origin/lifecycle must still be checked synchronously
        // before its once-only consume. This saved observation does not add an
        // INFER Allow prerequisite to cleanup/unpark or permit Model sending.
        return observed;
      },
      beginOriginalResourceInvalidation(reference, park) {
        originalJournalInstallation();
        if (originalInvalidation !== undefined || !owner.available ||
            operation.originalResourceParkCurrent(park) !== park ||
            cp.journal.originalModelCurrentCutOperationStatus(reference).state !== 'linked') {
          fail('ModelOriginalResourceInvalidationUnavailable');
        }
        const observation = cp.journal.originalModelCurrentCutObservation(reference);
        const facts = cp.journal.originalModelJournalObservationFacts(observation);
        if (!same(select(facts.identity, scopeKeys), select(inventory, scopeKeys))) {
          fail('ModelOriginalJournalInstallationChanged');
        }
        // Keep this exact outstanding request even when the following COMMIT
        // fails or is unknown. No replacement intent or approval is issued.
        const request = operation.beginOriginalResourceInvalidation(park);
        originalInvalidation = {reference, park, request, receipt: undefined};
        return request;
      },
      completeOriginalResourceInvalidation() {
        const original = originalInvalidation;
        const port = originalJournalInstallation();
        if (original === undefined || !owner.available ||
            operation.originalResourceInvalidationCurrent(original.park, original.request) !== original.request) {
          fail('ModelOriginalResourceInvalidationUnavailable');
        }
        const receipt = original.receipt ??= cp.journal.invalidateOriginalModelCurrentCut(
          original.reference, original.request);
        // The fixed FFI authenticates this same actual port and all four refs,
        // then synchronously rechecks Core lifecycle and consumes once. It does
        // not demand dispatch=None become Allow or grant a subsequent send.
        operation.completeOriginalJournalInvalidation(port, receipt,
          original.reference, original.park, original.request);
        // Retire comparison/data borrows only AFTER the original Core Owner
        // consumed this exact committed request. Unknown/failure keeps them.
        if (originalCut?.park === original.park) {
          originalResourceCuts.delete(original.park);
          if (originalCut.matched !== undefined) operation.retireOriginalCurrentStateMatch(originalCut.matched);
          if (originalCut.document !== undefined) operation.retireOriginalCurrentStateDocument(originalCut.document);
          originalCut.matched = undefined;
          originalCut.document = undefined;
          originalCut.facts = undefined;
        }
        originalInvalidation = undefined;
        return receipt;
      },
      hasResponseReconciliation: unreconciled.size > 0,
      evaluationInventory() {
        if (!owner.available || !token.available) fail('ModelContinuationClosed');
        const current = cp.journal.readModelCalls(inventory);
        const calls = current.slots.map(slot => {
          const entry = slot.attempts.at(-1);
          const bundle = entry?.settlement?.evidence?.model_capture_bundle;
          return Object.freeze({slotCid: slot.slotCid, callWire: originals.slotWires[slot.ordinal],
            state: slot.state, outcome: slot.state === 'SavedSuccess' ? 'ok' : 'result_unknown',
            entry, captureBundleCid: bundle?.cid});
        });
        return Object.freeze({count: calls.length, calls: Object.freeze(calls),
          async readBundle(slot, beforeRead) {
            if (!owner.available || !token.available) fail('ModelContinuationClosed');
            const call = calls[slot];
            if (call?.state !== 'SavedSuccess' || call.captureBundleCid === undefined) return undefined;
            const historical = cp.journal.readModelAttemptOriginals(call.entry);
            let stored;
            await readSettled({originals, entry: call.entry, ...historical},
              value => {stored = value;}, beforeRead);
            if (!owner.available || !token.available || stored?.state !== 'SavedSuccess' ||
                stored.evidence.model_capture_bundle.cid !== call.captureBundleCid) fail('ModelSettlementCustodyLost');
            return Object.freeze({wire: stored.bodies.model_capture_bundle,
              cid: call.captureBundleCid, count: 1});
          }});
      },
      entry: slot => owner.entries.get(slot), observe,
      async authorize() {
        if (!owner.available) fail('ModelContinuationClosed');
        checkpoints();
        signal?.throwIfAborted();
        if (!owner.currentProvider()) fail('ModelProviderBindingChanged');
        requireModelDispatchPreparation(moon, selected);
        // Never reissue a nominal registration or rebind physical custody
        // after success or failure. Current send permission still belongs to
        // the original Entry's final Common gate, not this cached observation.
        if (rawBinding?.attempted) {
          if (!rawBinding.complete) throw rawBinding.issue;
        }
        // A known missing policy original must refuse before Approval/Entry.
        // Persistence rechecks again after transport; an early observation is
        // neither permanent Store custody nor permission for the final send.
        if (rawBinding !== undefined) {
          await confirmRawOriginals();
          rawOriginalsCurrent();
        }
        if (!owner.available) fail('ModelContinuationClosed');
        signal?.throwIfAborted();
        if (gate === undefined) {
          gateOpening ??= cp.modelAuthorization(gateOptions).then(value => { gate = value; })
            .finally(() => { gateOpening = undefined; });
          await gateOpening;
        }
        checkpoints();
        if (!owner.available) { cleanup(); fail('ModelContinuationClosed'); }
        signal?.throwIfAborted();
        const decision = claim === undefined
          ? await gate.authorize({signal})
          : await gate.resume({signal, resumption: {claim: {checkpointCid: existing.checkpointCid, claim}}});
        checkpoints();
        if (decision.action === 'waiting') return {status: 'waiting_checkpoint', checkpoint: decision.checkpoint};
        if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
        if (!owner.available) fail('ModelContinuationClosed');
        signal?.throwIfAborted();
        if (view === undefined) view = cp.journal.registerImmediateModelCallSet({modelCallSet: originals, declaredResults, parentResume});
        owner.decision = decision;
        if (rawBinding?.complete !== true) {
          const dispatch = {account: selected.observeAccount(), principalId, at: now(), delegated: decision.runtimeDecision,
              observeAccount: selected.observeAccount, observeAt: now,
              enterCall(original) {
                if (!owner.available || !owner.currentProvider() ||
                    original.callWire !== originals.slotWires[original.slot] ||
                    !operation.entryCurrent(original.entry, preparedCallSet)) return false;
                const attempt = control.admitRunEvidence('model_call_attempt', original.attemptWire, limits);
                const reference = {...select(inventory, scopeKeys), ordinal: original.slot,
                  slotCid: inventory.slots[original.slot].slotCid,
                  attemptIndex: JSON.parse(attempt.wire).attempt, attemptCid: attempt.identity,
                  attemptWire: original.attemptWire, authorityWire: original.authorityWire};
                owner.pending = original;
                try {
                  checkpoints();
                  const receipt = claim === undefined
                    ? cp.journal.enterImmediateModelCall(reference, {decision, preparedCallSet, parentResume})
                    : cp.journal.enterResumedCall(claim, {...reference, checkpointCid: existing.checkpointCid,
                        resolutionCid: decision.admission.resolutionCid});
                  owner.entries.set(original.slot, receipt);
                  diagnostic('model_call_entered', {ref: {namespaceId, authorityScopeCid,
                    runDefinitionCid: receipt.runDefinitionCid}, task: receipt.taskIndex,
                    slot: receipt.ordinal, attempt: receipt.attemptIndex,
                    attemptCid: receipt.attemptCid, outcome: 'running'});
                  return true;
                } catch (error) {
                  owner.entryFailure = error;
                  return false;
                } finally { owner.pending = undefined; }
              }};
          let admittedDispatch;
          if (persistence === undefined) {
            admittedDispatch = operation.bindModelDispatch(control, plan, preparedCallSet, bound, dispatch);
          } else {
            admittedDispatch = operation.bindModelEntryPersistence(control, plan, preparedCallSet, bound,
              {...dispatch, beginEntry(original) {
                try { checkpoints(); }
                catch (error) {owner.entryFailure = error; return undefined;}
                if (!owner.available || !owner.currentProvider() ||
                    original.callWire !== originals.slotWires[original.slot] ||
                    !operation.entryCurrent(original.entry, preparedCallSet)) return undefined;
                const attempt = control.admitRunEvidence('model_call_attempt', original.attemptWire, limits);
                const reference = {...select(inventory, scopeKeys), ordinal: original.slot,
                  slotCid: inventory.slots[original.slot].slotCid,
                  attemptIndex: JSON.parse(attempt.wire).attempt, attemptCid: attempt.identity,
                  attemptWire: original.attemptWire, authorityWire: original.authorityWire};
                owner.pending = original;
                // Retain the exact pending Entry across physical journal await.
                // Neither an unknown save nor a late ACK may re-enter or send.
                const view = claim === undefined
                  ? persistence.beginImmediate(original, reference,
                      {decision, parentResume})
                  : persistence.beginResumed(original, {...reference,
                      checkpointCid: existing.checkpointCid,
                      resolutionCid: decision.admission.resolutionCid}, claim);
                if (view === undefined) owner.pending = undefined;
                return view;
              }});
          }
          if (rawBinding !== undefined) {
            rawBinding.attempted = true;
            try {
              const policy = control.issueCheckedClientInferRawCapturePolicy(
                plan.compiled, plan.runDefinition, admittedDispatch, bound,
                {...rawSelection, storeAuthorityCid});
              const registration = control.registerCheckedClientInferRawCapture(
                plan.compiled, plan.runDefinition, admittedDispatch, bound,
                {policy, profile: rawSelection.profile,
                  installation: rawSelection.installation, probability: rawSelection.probability,
                  account: selected.observeAccount(), at: now(), storeAuthorityCid,
                  selectionAvailable: () => owner.available && token.available &&
                    owner.currentProvider() && rawSelection?.selectionAvailable() === true,
                  observeAccount: selected.observeAccount, observeAt: now});
              // Use this continuation's actual selected Store, not a Provider
              // supplied CID, replacement Store or another retention Owner.
              const persistence = createModelRawTransportPersistenceFactory({store, moon, operation,
                registration, notify: operation.ioNotification?.notify,
                retainHolding(value) {
                  if (!rawBinding.holdings.includes(value)) rawBinding.holdings.push(value);
                }});
              rawBinding.persistence = persistence;
              operation.bindModelRawCapture(registration, persistence);
              rawBinding.complete = true;
            } catch (error) {
              rawBinding.issue = error;
              throw error;
            }
          }
        }
        for (const [slot, {entry, historical}] of unreconciled) {
          if (!owner.available || !owner.currentProvider()) fail('ModelProviderBindingChanged');
          signal?.throwIfAborted();
          const responseCustody = operation.prepareResponseReconciliation(preparedCallSet, slot,
            checked(moon.strategyRunEvidenceAdmit('model_call_attempt', historical.attemptWire, 16384, 1024, 20)),
            checked(moon.strategyRunEvidenceAdmit('model_dispatch_authority', historical.authorityWire, 16384, 1024, 20)));
          const request = moon.clientProgramInferPreparedRequest(preparedCallSet, slot);
          if (request === undefined) fail('ModelReconciliationRequestUnavailable');
          const reply = await selected.reconcileResponse(Object.freeze({request,
            inputFrame: moon.clientProgramModelRequestInputFrameBounded(request, 65536),
            entry: Object.freeze(entryIdentity(entry)), callWire: originals.slotWires[slot],
            attemptWire: historical.attemptWire, authorityWire: historical.authorityWire,
            providerBindingCid: inventory.providerBindingCid, signal}));
          // Retrieval has no send callback. Recheck its original owner and
          // current binding across the await before adopting any returned value.
          if (!owner.available || !owner.currentProvider()) fail('ModelProviderBindingChanged');
          signal?.throwIfAborted();
          if (reply !== undefined) {
            if (reply === null || Object.keys(reply).sort().join(',') !==
                'attemptWire,callWire,providerBindingCid,response' ||
                reply.attemptWire !== historical.attemptWire ||
                reply.callWire !== originals.slotWires[slot] ||
                reply.providerBindingCid !== inventory.providerBindingCid ||
                reply.response === undefined) fail('ModelReconciliationIdentityMismatch');
            operation.adoptReconciledResponse(responseCustody, reply.response);
          }
          unreconciled.delete(slot);
        }
        return {status: 'dispatch'};
      },
      // Closing revokes use immediately; a late physical callback remains
      // this continuation's responsibility until the same gate settles.
      close: cleanup, cleanup, cleanupPending,
    });
    return continuationView;
  }
  async function open(options) {
    const ownership = {};
    try { return await openOwned(options, ownership); }
    catch (error) {
      if (ownership.owner !== undefined && live.get(options.preparedCallSet) === ownership.owner) {
        ownership.owner.available = false;
        live.delete(options.preparedCallSet);
      }
      // Restored inputs remain the caller's until their physical consumer is
      // reclaimed. A newly exported snapshot has no token-dependent consumer.
      if (options.inputToken === undefined) release(ownership.token);
      throw error;
    }
  }
  return Object.freeze({verifier, open, prime, release, usage, observe,
    capturedContent: (token, runDefinitionCid) =>
      ownedInput(token, runDefinitionCid).capturedContent,
    capturedContentBinding: (token, runDefinitionCid) =>
      ownedInput(token, runDefinitionCid).capturedContentBinding,
    retire: record => retireReceipt(record.originals.fixedInputReceiptWire),
    discover: runId => checkpoints().journal.discoverModelCallSets({runId, limit: 100}),
    unresolved: runId => checkpoints().journal.hasUnresolvedModelCalls(runId),
    state: identity => checkpoints().journal.readModelCalls(identity),
    savedScope(plan, preparedProgram, selected, token) {
      const snapshot = ownedInput(token, plan.runDefinition.identity);
      // A copied envelope or a lease from another continuation is not custody.
      // Recheck the original lease when the common saved-input owner borrows it.
      const available = () => {
        try { ownedInput(token, plan.runDefinition.identity); return true; }
        catch { return false; }
      };
      return selected.occurrence !== undefined
        ? control.readCheckedClientComposedInferSavedInputScope(plan.compiled, plan.runDefinition,
          selected.occurrence, selected.graph, snapshot.callScopeSnapshotWire,
          authorityScopeCid, available)
        : control.readCheckedClientInferSavedInputScope(plan.compiled, plan.runDefinition,
          preparedProgram, selected.step, selected.graph, snapshot.callScopeSnapshotWire,
          authorityScopeCid, available);
    },
  });
}
