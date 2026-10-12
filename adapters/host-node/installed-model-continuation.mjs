// Installed composition of the actual Model owner, immutable input custody,
// existing Checkpoint journal and Store. This is neither a slot scheduler nor
// a source of dispatch permission from historical bytes.
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

const limits = Object.freeze({maxWireBytes: 1048576, maxNodes: 100000, maxDepth: 100});
const fail = code => { throw Object.assign(new Error(code), {code}); };
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
  // Synchronous journal checks need the previously authenticated receipt and
  // original digest while a Run is waiting or unknown. They do not need input
  // rows, submitted programs or responses, and cannot authorize a fresh send.
  const inventories = new Map();
  const diagnostic = diagnosticObserver(observeDiagnostic);
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
    return value;
  };
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
    sourceContinuation, retainEvidenceCopy}, ownership) {
    let rawSelection = snapshotModelRawCaptureSelection(selected.rawCaptureSelection);
    const rawBinding = rawSelection === undefined ? undefined :
      {attempted: false, complete: false, issue: undefined};
    const cp = checkpoints();
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
      const expectedBoundary = {unit_id: facts.unitId, task_index: coordinates._0,
        strategy_revision: coordinates._2, inference_barrier_cid: coordinates._3,
        account_id: context.accountId, configuration_cid: context.configurationCid,
        entry_id: evaluated.entry_id, principal: principalId, connection: facts.providerId,
        resource: facts.modelTaskCid, context_cid: context.contextCid,
        installation_revision_cid: provider.installation_revision_cid,
        configuration_contract_cid: provider.configuration_contract_cid,
        provider_configuration_cid: provider.configuration_cid};
      const input = control.admitRunEvidence('model_input_artifact', facts.inputArtifactWire, limits);
      scope = control.sealRunEvidence('model_invocation_scope', canonicalJson({
        version: 'actql-model-invocation-scope/0.1', run_definition_cid: plan.runDefinition.identity,
        task_index: coordinates._0, strategy_revision: coordinates._2,
        inference_barrier_cid: coordinates._3, input_artifact_cid: input.identity,
        model_call_slot_cids: facts.slotWires.map(wire => control.admitRunEvidence('model_call_slot', wire, limits).identity),
        provider_binding_cid: binding.identity,
        authorization_context: {account_id: context.accountId, configuration_cid: context.configurationCid,
          entry_id: evaluated.entry_id, principal: principalId, connection: facts.providerId,
          resource: facts.modelTaskCid, operation: 'infer', boundary: 'activation', context_cid: context.contextCid},
      }), limits);
      const fixedBinding = canonicalJson({version: 'actql-model-fixed-input-binding/0.1',
        run_definition_cid: plan.runDefinition.identity, scope_cid: scope.identity,
        input_artifact_cid: input.identity, task_index: coordinates._0, strategy_revision: coordinates._2});
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
      const receipt = await withPreparedInferEvidence({configuration: inferEvidence,
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
              leaf('model_attempt_outcome'), leaf('model_dispatch_authority')), bundle); }
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
    const cleanup = () => {
      owner.available = false;
      if (gateOpening !== undefined) return false;
      if (gate !== undefined && !gateReleased) {
        const recover = gateCloseAttempted;
        gateCloseAttempted = true;
        const result = recover ? gate.cleanup() : gate.close();
        gateReleased = result !== false && gate.cleanupPending() === false;
      }
      if (gate !== undefined && !gateReleased || operation.cleanupPending()) return false;
      if (live.get(preparedCallSet) === owner) live.delete(preparedCallSet);
      rawSelection = undefined;
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
    return Object.freeze({originals, inventory, token, scope, preparedCallSet,
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
        signal?.throwIfAborted();
        if (!owner.currentProvider()) fail('ModelProviderBindingChanged');
        if (selected.egressAdmission === undefined) throw selected.egressFailure ?? new Error('InstalledModelEgressUnavailable');
        // Never reissue a nominal registration or rebind physical custody
        // after success or failure. Current send permission still belongs to
        // the original Entry's final Common gate, not this cached observation.
        if (rawBinding?.attempted) {
          if (!rawBinding.complete) throw rawBinding.issue;
        }
        if (gate === undefined) {
          gateOpening ??= cp.modelAuthorization(gateOptions).then(value => { gate = value; })
            .finally(() => { gateOpening = undefined; });
          await gateOpening;
        }
        if (!owner.available) { cleanup(); fail('ModelContinuationClosed'); }
        signal?.throwIfAborted();
        const decision = claim === undefined
          ? await gate.authorize({signal})
          : await gate.resume({signal, resumption: {claim: {checkpointCid: existing.checkpointCid, claim}}});
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
              operation.bindModelRawCapture(registration);
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
