// Installed composition of the actual Model owner, immutable input custody,
// existing Checkpoint journal and Store. This is neither a slot scheduler nor
// a source of dispatch permission from historical bytes.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {assertAuthorizationAccountCurrent, ExecutionAuthorizationError} from '../host-common/authorization-gate.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {contentCid} from './local-account-config.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';
import {checkCapturedInventory, MAX_MODEL_INPUT_BYTES} from
  './installed-model-input-custody.mjs';
import {createInstalledModelContinuationCustody, entryIdentity, fail, limits, same, scopeKeys, select} from
  './installed-model-continuation-custody.mjs';
import {loadCheckpointRuntime} from './checkpoint-runtime.mjs';
import {withPreparedInferEvidence} from './infer-evaluation-evidence.mjs';
import {createNodeInferEntryPersistence} from './infer-entry-persistence.mjs';
import {createInferPhysicalObservation} from './infer-physical-observation.mjs';
import {snapshotModelRawCaptureSelection} from './infer-raw-selection.mjs';
import {createModelRawTransportPersistenceFactory} from './infer-raw-capture.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {selectedInferOriginalCurrentStateCodec,
  snapshotInferOriginalCurrentStateCodec as originalCurrentCodecLimits} from './infer-original-installation.mjs';

import type {runtimeCore} from '../host-common/runtime-core.mjs';
import type {createLocalAuthorizationGate} from './local-account-config.mjs';
import type {openNodeInferOperation} from './infer-operation.mjs';

type Custody = ReturnType<typeof createInstalledModelContinuationCustody>;
type CustodyPorts = Parameters<typeof createInstalledModelContinuationCustody>[0];
type CheckpointCustody = ReturnType<Custody['checkpoints']>;
type Journal = CheckpointCustody['journal'];
type Control = ReturnType<typeof runtimeCore>['publicationControl'];
type InferOperation = ReturnType<typeof openNodeInferOperation>;
type Operation = Omit<InferOperation, 'ioNotification'> & Readonly<{
  ioNotification?: Readonly<{notify(): void}>;
}>;
type PreparedEvidence = Parameters<typeof withPreparedInferEvidence>[0];
type RawTransport = Parameters<typeof createModelRawTransportPersistenceFactory>[0];
type PersistenceOptions = Parameters<typeof createNodeInferEntryPersistence>[0];
type PhysicalObservation = Parameters<typeof createInferPhysicalObservation>[0]['observation'] &
  Readonly<{canMeasure(owner: 'infer'): boolean}>;
type Runtime = CustodyPorts['moon'] & PreparedEvidence['moon'] & RawTransport['moon'] & PersistenceOptions['moon'] & Readonly<{
  clientProgramOriginalMockProvider?(installation: unknown): unknown;
  executionAuthorizationEvaluate(account: unknown, principal: string, provider: string, resource: string, operation: 'infer'): unknown;
  executionAuthorizationEvaluationJson(evaluation: unknown): string;
  clientProgramInferPlanBoundary(graph: unknown): unknown;
  clientProgramInferAttemptRecords(attempt: unknown, accounting: unknown, outcome: unknown, authority: unknown): unknown;
  clientProgramInferPreparedRequest(prepared: unknown, slot: number): unknown;
  clientProgramModelRequestInputFrameBounded(request: unknown, maxBytes: number): unknown;
  clientProgramAdvanceInferOriginalCurrentStateComparisonWithMatch?: unknown;
  clientProgramInferOriginalCurrentStateMatchPoll?: unknown;
  clientProgramInferOriginalCurrentStateMatchCurrent?: unknown;
  clientProgramRetireInferOriginalCurrentStateMatch?: unknown;
}>;
type Store = CustodyPorts['store'] & RawTransport['store'];
type RunDefinition = Parameters<Control['checkCheckedClientInferOriginalParkedStorageOrigin']>[1] &
  Readonly<{identity: string; wire: string}>;
type Compiled = Parameters<Control['issueCheckedClientInferRawCapturePolicy']>[0] &
  Readonly<{preparedEvidence: Readonly<{identity: string; wire: string}>}>;
type Plan = PreparedEvidence['plan'] & Readonly<{compiled: Compiled; runDefinition: RunDefinition}>;
type Token = ReturnType<Custody['retain']>;
type Snapshot = Parameters<Custody['retain']>[2];
type Receipt = Parameters<Custody['retain']>[1];
type Originals = Snapshot['originals'] & Readonly<{fixedInputReceiptWire: string}>;
type Inventory = ReturnType<Custody['admittedInventory']>;
type SourceInventory = Parameters<Custody['prime']>[0] & Readonly<{originals: Originals}>;
type ModelSlot = ReturnType<Journal['readModelCalls']>['slots'][number];
type Entry = ModelSlot['attempts'][number];
type OpaqueEntryOriginal = Parameters<Parameters<Operation['bindModelDispatch']>[4]['enterCall']>[0];
type EntryOriginal = Readonly<{entry: object; slot: number; callWire: string; attemptWire: string; authorityWire: string}>;
type ImmediateInput = NonNullable<Parameters<Journal['enterImmediateModelCall']>[1]>;
type Claim = Parameters<Journal['enterResumedCall']>[0];
type Gate = Awaited<ReturnType<typeof createLocalAuthorizationGate>>;
type Decision = Awaited<ReturnType<Gate['authorize']>>;
type ModelGate = Pick<Gate, 'configurationCid' | 'close' | 'cleanup' | 'cleanupPending'> & Readonly<{
  authorize(options: Parameters<Gate['authorize']>[2]): Promise<Decision>;
  resume(options: Parameters<Gate['resume']>[2]): Promise<Decision>;
}>;
type ProviderBinding = Readonly<{wire: string; identity: string; originals: unknown}>;
type ResponseReply = Readonly<{attemptWire: string; callWire: string; providerBindingCid: string; response: unknown}>;
type Selected = Record<string, unknown> & PreparedEvidence['selected'] & Readonly<{
  provider: unknown; localMock?: boolean; originalMockInstallation?: unknown;
  egressAdmission?: unknown; egressFailure?: unknown; entryPersistence?: 'async';
  graph: unknown; step: number; currentProvider?(): unknown;
  providerBinding?: ProviderBinding; observeAccount(): unknown;
  rawCaptureSelection?: Parameters<typeof snapshotModelRawCaptureSelection>[0];
  reconcileResponse?(request: Readonly<{
    request: unknown; inputFrame: unknown; entry: ReturnType<typeof entryIdentity>;
    callWire: string; attemptWire: string; authorityWire: string; providerBindingCid: string;
    signal?: AbortSignal;
  }>): ResponseReply | null | undefined | PromiseLike<ResponseReply | null | undefined>;
}>;
type OriginalPreparation = Readonly<{
  scope: unknown; control: Control; compiled: Compiled; runDefinition: RunDefinition;
  nodeInstallation: Parameters<Control['checkCheckedClientInferOriginalParkedStorageOrigin']>[6];
  metadataInstallation: Parameters<typeof selectedInferOriginalCurrentStateCodec>[0];
}>;
type OpenOptions = Readonly<{
  operation: Operation; preparedCallSet: object; plan: Plan; selected: Selected; principalId: string;
  declaredResults: readonly string[]; submission: unknown; signal?: AbortSignal;
  existing?: SourceInventory; inputToken?: Token; claim?: Claim; parentResume?: ImmediateInput['parentResume'];
  journalPort?: Pick<Journal, 'admitResume'>;
  sourceContinuation?: Snapshot['sourceContinuation']; retainEvidenceCopy: PreparedEvidence['retainCopy'];
  originalPreparation?: OriginalPreparation; preserveEvidenceInputs?: boolean;
}>;
type GateOptions = Readonly<{
  runId: string; runDefinitionCid: string; unitId: string; scopeCid: string;
  tuple: Readonly<{connection: string; resource: string; operation: 'infer'}>;
  declaredResults: readonly string[]; modelCallSet: Originals; reviewWire: string; continuationWire: string;
  beforeDefer(): Promise<void>; attachImmediate: boolean; journalPort?: OpenOptions['journalPort'];
}>;
type RetainedCutFacts = ReturnType<CheckpointCustody['originalModelStateSavedFacts']>;
type StorageBinding = unknown;
type StateReceipt = unknown;
type StateObservation = unknown;
type StorageRead = Readonly<{storageBinding: StorageBinding; runDefinition: RunDefinition}>;
type StateRead = StorageRead & Readonly<{receipt: StateReceipt}>;
type CheckpointInstallation = CheckpointCustody & Readonly<{
  modelContext: Readonly<{accountId: string; configurationCid: string; contextCid: string}>;
  retainModelInput(inputs: Readonly<{runId: string; runDefinitionCid: string; bodyWire: string}>): Promise<Receipt>;
  modelAuthorization(inputs: GateOptions): Promise<ModelGate>;
  modelOriginalStorageBindingEvidence(binding: StorageBinding): Promise<unknown>;
  modelOriginalStorageBindingEvidenceSelected(inputs: StorageRead, acquisition: object): Promise<unknown>;
  modelOriginalStorageBindingBootstrapSelected(inputs: StorageRead, acquisition: object): Promise<unknown>;
  observeModelOriginalStorageBindingSelected(inputs: Readonly<{runDefinition: RunDefinition}>, acquisition: object): Promise<StorageBinding>;
  confirmOriginalModelStateSavedSelected(inputs: StateRead & Readonly<{identity: RetainedCutFacts['identity']}>, acquisition: object): Promise<StateObservation>;
  readOriginalModelStateSelected(inputs: StateRead, acquisition: object): Promise<unknown>;
  retainOriginalModelStateSelected(inputs: StorageRead & Readonly<{bodyWire: string}>, acquisition: object): Promise<StateReceipt>;
  retireOriginalModelStateSavedObservation(observation: StateObservation): void;
}>;
type Inputs = Omit<CustodyPorts, 'moon' | 'control' | 'store' | 'runtime' | 'getCheckpoints' | 'observeDiagnostic'> & Readonly<{
  moon: Runtime; control: Control; store: Store; now(): string;
  getCheckpoints(): CheckpointInstallation | undefined;
  observe?: unknown; observation?: PhysicalObservation; inferEvidence?: PreparedEvidence['configuration'];
}>;
type Owner = {
  operation: Operation; preparedCallSet: object; available: boolean; pending?: EntryOriginal; decision?: Decision;
  currentProvider(): boolean; entries: Map<number, Entry>; entryFailure?: unknown;
};
type OpenCustody = {owner?: Owner; token?: Token};
type CurrentStateReference = ReturnType<Journal['prepareOriginalModelCurrentCut']>;
type InvalidationReceipt = ReturnType<Journal['invalidateOriginalModelCurrentCut']>;
type OriginalInvalidation = {reference: CurrentStateReference; park: object; request: unknown; receipt?: InvalidationReceipt};
type OriginalCut = {
  park: unknown; storageBinding: StorageBinding; receipt: StateReceipt; saved?: StateObservation;
  codec: WeakRef<object>; promise?: Promise<CurrentStateReference>; document?: unknown; matched?: unknown;
  facts?: Pick<RetainedCutFacts, 'identity' | 'phase' | 'cut'>;
  current(): boolean; invalidationCurrent(request: unknown): unknown;
};
type SavedCut = Readonly<{park: unknown; receipt: StateReceipt; reference: CurrentStateReference}>;
type OriginalSave = {
  storageBinding: StorageBinding; originWire: string; codec: WeakRef<object>; park: unknown;
  promise?: Promise<SavedCut>; receipt?: StateReceipt; reference?: CurrentStateReference; pending: boolean;
};
type OriginalDispatchCut = {park?: unknown; flight?: Promise<void>; pending: boolean};
type CleanupHandle = Readonly<{status(): Readonly<{pending: boolean}>; retry(): unknown}>;
type RawBinding = {
  attempted: boolean; complete: boolean; issue?: unknown;
  persistence?: ReturnType<typeof createModelRawTransportPersistenceFactory>;
  holdings: Parameters<RawTransport['retainHolding']>[0][] | undefined;
  originalsFlight?: Promise<void>; originalsPending: boolean;
  readCleanup?: CleanupHandle; readCleanupFlight?: Promise<unknown>;
};
type UnreconciledEntry = Readonly<{entry: Entry; historical: ReturnType<Journal['readModelAttemptOriginals']>}>;
type StoredSettlement = Parameters<NonNullable<Parameters<Custody['readSettled']>[1]>>[0];
type EvidenceRole = keyof StoredSettlement['bodies'];
type CapturedFacts = Omit<ReturnType<Operation['preparedFacts']>, 'providerId' | 'modelTaskCid' | 'unitId' | 'callScopeSnapshotWire'> &
  Readonly<{providerId: string; modelTaskCid: string; unitId: string; callScopeSnapshotWire: string}>;

function requireModelDispatchPreparation(moon: Runtime, selected: Selected) {
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
export async function installNodeModelContinuation({moon, control, store, storeAuthorityCid, namespaceId,
  authorityScopeCid, now, getCheckpoints, observe: observeDiagnostic, observation, inferEvidence}: Inputs) {
  const runtime = await loadCheckpointRuntime();
  const custody = createInstalledModelContinuationCustody({moon, control, store, storeAuthorityCid, namespaceId,
    authorityScopeCid, runtime, getCheckpoints, observeDiagnostic});
  const {live, originalResourceCuts, diagnostic, retain, ownedInput, release, usage, leaseReceiptWire,
    retireReceipt, checkpoints, installOriginalJournal, admittedInventory, readSettled, verifier, prime, observe} = custody;

  async function openOwned({operation, preparedCallSet, plan, selected, principalId,
    declaredResults, submission, signal, existing, inputToken, claim, parentResume, journalPort,
    sourceContinuation, retainEvidenceCopy, originalPreparation, preserveEvidenceInputs = true}: OpenOptions, ownership: OpenCustody) {
    let rawSelection = snapshotModelRawCaptureSelection(selected.rawCaptureSelection);
    const rawBinding: RawBinding | undefined = rawSelection === undefined ? undefined :
      {attempted: false, complete: false, issue: undefined,
        persistence: undefined, holdings: [], originalsFlight: undefined,
        originalsPending: false, readCleanup: undefined, readCleanupFlight: undefined};
    // Reject a known missing installation before Approval/Entry, not after
    // consuming an attempt. Method checks are availability only: the actual
    // Store remains this controller's selected original, never caller data.
    if (rawBinding !== undefined &&
        (typeof operation.ioNotification?.notify !== 'function' ||
          typeof control.installedModelRawSelectionOriginals !== 'function' ||
          (['confirmModelRawCaptureOriginals', 'confirmModelRawEvidence',
            'prepareModelRawEvidence', 'commitPhysicalHolding'] as const).some(name =>
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
    const facts = operation.preparedFacts(preparedCallSet) as CapturedFacts;
    const run = JSON.parse(plan.runDefinition.wire) as Readonly<{run_id: string; valid_until: string}>;
    let token: Token;
    let originals: Originals | Snapshot['originals'];
    let scope: ReturnType<Control['admitRunEvidence']>;
    const binding = selected.providerBinding;
    if (binding === undefined) fail('InstalledModelProviderBindingRequired');
    if (existing !== undefined) {
      token = inputToken!;
      if (leaseReceiptWire(token) !== existing.originals.fixedInputReceiptWire ||
          !token.available) fail('ModelFixedInputCustodyUnavailable');
      originals = existing.originals;
      scope = control.admitRunEvidence('model_invocation_scope', originals.scopeWire, limits);
      if (facts.inputArtifactWire !== originals.inputArtifactWire ||
          !same(facts.slotWires, originals.slotWires) ||
          facts.callScopeSnapshotWire !== token.snapshot!.callScopeSnapshotWire) fail('ModelRestoredInventoryChanged');
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
      originals = {originalRunWire: originalModelRunWire(plan.compiled, plan.runDefinition)!,
        preparedInvocationWire: plan.compiled.preparedEvidence.wire, scopeWire: scope.wire,
        providerBindingWire: binding.wire, inputArtifactWire: input.wire,
        slotWires: [...facts.slotWires], expectedBoundary};
      const contentGeneration = operation.contentRecovery?.() as Snapshot['contentGeneration'];
      const capturedContent = operation.capturedContentRecovery?.() as Snapshot['capturedContent'];
      const capturedContentBinding = operation.capturedContentBinding?.() as Snapshot['capturedContentBinding'];
      checkCapturedInventory(capturedContent, plan.runDefinition.identity, capturedContentBinding, fail);
      if (operation.contentGenerationCount > 0 && contentGeneration === undefined) {
        fail('ModelContentGenerationCustodyMissing');
      }
      let snapshot: Snapshot = {version: 'actql-installed-model-input/0.1', scopeCid: scope.identity,
        inputArtifactCid: input.identity, originals, binding: fixedBinding,
        descriptorWire: exported.descriptorWire, rows: [...exported.rows as readonly unknown[]],
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
    const inventory = admittedInventory(originals as Originals, existing?.checkpointCid == null, token);
    const owner: Owner = {operation, preparedCallSet, available: true, pending: undefined, decision: undefined,
      currentProvider: () => selected.currentProvider?.() !== false && binding.identity === inventory.providerBindingCid,
      entries: new Map()};
    let installedJournalPort: ReturnType<Journal['installOriginalModelJournalPort']> | undefined;
    let originalInvalidation: OriginalInvalidation | undefined;
    let originalCut: OriginalCut | undefined;
    let originalSave: OriginalSave | undefined;
    let originalDispatchCut: OriginalDispatchCut | undefined;
    function originalResourceReadCurrent(park: unknown, acquisition?: object) {
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
    async function selectedOriginalStorageEvidence(park: unknown, storageBinding: StorageBinding, acquisition: object) {
      originalResourceReadCurrent(park, acquisition);
      if (typeof cp.modelOriginalStorageBindingEvidenceSelected !== 'function') {
        fail('InferOriginalMetadataAcquisitionUnavailable');
      }
      const evidence = await cp.modelOriginalStorageBindingEvidenceSelected({
        storageBinding, runDefinition: plan.runDefinition}, acquisition);
      originalResourceReadCurrent(park, acquisition);
      return evidence;
    }
    async function confirmOriginalResourceStateSaved(park: unknown, storageBinding: StorageBinding, receipt: StateReceipt) {
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
        originalPreparation!.nodeInstallation, storage);
      originalResourceReadCurrent(park, acquisition);
      return saved;
    }
    function originalJournalInstallation() {
      if (originalPreparation === undefined ||
          live.get(preparedCallSet) !== owner ||
          operation.originalResourceScope?.() !== originalPreparation.scope ||
          checkpoints() !== cp || cp.journal !== custody.checkpointInstallation?.journal) {
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
        ioNotification: operation.ioNotification!,
        settled(entry, receipt) {
          if (owner.pending?.entry !== entry) return;
          owner.pending = undefined;
          if (receipt === undefined) return;
          owner.entries.set(receipt.ordinal, receipt);
          diagnostic('model_call_entered', {ref: {namespaceId, authorityScopeCid,
            runDefinitionCid: receipt.runDefinitionCid}, task: receipt.taskIndex,
            slot: receipt.ordinal, attempt: receipt.attemptIndex,
            attemptCid: receipt.attemptCid, outcome: 'running'});
        }});
    if (observation?.canMeasure('infer')) {
      const installed = operation.bindModelObservation(preparedCallSet,
        createInferPhysicalObservation({observation,
          reference: {namespaceId, authorityScopeCid},
          receiptAt: slot => owner.entries.get(slot)}) as Parameters<Operation['bindModelObservation']>[1]);
      if (!installed) observation.noteLoss();
    }
    const unreconciled = new Map<number, UnreconciledEntry>();
    let view = existing === undefined ? undefined : cp.journal.readModelCalls(existing!.inventory);
    if (view !== undefined) {
      for (const slot of view.slots) {
        const entry = slot.attempts.at(-1);
        if (entry === undefined) continue;
        await observe(entry);
      }
      view = cp.journal.readModelCalls(existing!.inventory);
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
          let stored: StoredSettlement | undefined;
          await readSettled({originals: originals as Originals, entry,
            ...historical as Omit<typeof historical, 'entry'>}, record => { stored = record; });
          if (stored === undefined) fail('ModelSavedCustodyUnavailable');
          if (stored.terminalFailure === true) fail('ModelSavedTerminalFailure');
          const leaf = (name: EvidenceRole) => checked(moon.strategyRunEvidenceAdmit(name, stored!.bodies[name]!, 16384, 1024, 20));
          const bundle = checked(moon.clientProgramReadInferCaptureBundle(stored.bodies.model_capture_bundle!,
            stored.evidence.model_capture_bundle!.cid));
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
    let gate: ModelGate | undefined, gateOpening: Promise<void> | undefined;
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
      const originals = control.installedModelRawSelectionOriginals(rawSelection!);
      rawBinding.originalsPending = true;
      rawBinding.originalsFlight = (async () => {
        try {
          await store.confirmModelRawCaptureOriginals(originals, storeAuthorityCid);
          rawOriginalsCurrent();
        } catch (error) {
          const handle = (error as Readonly<{cleanupHandle?: CleanupHandle}> | null | undefined)?.cleanupHandle;
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
              try { operation.ioNotification!.notify(); } catch { /* Wake is not cleanup proof. */ }
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
        originalResourceCuts.delete(originalCut.park as object);
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
    const gateOptions: GateOptions = {runId: run.run_id,
      runDefinitionCid: plan.runDefinition.identity, unitId: facts.unitId, scopeCid: scope.identity,
      tuple: {connection: facts.providerId, resource: facts.modelTaskCid, operation: 'infer'},
      declaredResults, modelCallSet: originals as Originals, reviewWire: originals.reviewWire ?? review.wire,
      continuationWire: canonicalJson({version: 'actql-installed-model-continuation/0.1',
        scopeCid: scope.identity, receipt: token.receipt, submission: token.snapshot!.submission}),
      beforeDefer: async () => { if (!token.available) fail('ModelFixedInputCustodyUnavailable'); },
      attachImmediate: view?.checkpointCid === null,
      ...(journalPort === undefined ? {} : {journalPort})};
    const continuationView = Object.freeze({originals: originals as Originals, inventory, token, scope, preparedCallSet,
      originalJournalInstallation,
      prepareOriginalResourcesForDispatch() {
        if (!owner.available || checkpoints()!==cp) fail('ModelOriginalCurrentCutUnavailable');
        if (originalDispatchCut!==undefined) return originalDispatchCut.flight;
        const codec=selectedInferOriginalCurrentStateCodec(originalPreparation?.metadataInstallation!,
          originalPreparation?.nodeInstallation);
        if (typeof operation.originalStoreBootstrapAcquisition !== 'function' ||
            typeof cp.observeModelOriginalStorageBindingSelected !== 'function' ||
            typeof cp.modelOriginalStorageBindingBootstrapSelected !== 'function') {
          fail('InferOriginalMetadataAcquisitionUnavailable');
        }
        const acquisition=operation.originalStoreBootstrapAcquisition();
        // This same installed operation already owns all initialization and
        // Store/codec overlap. There is no request-supplied serializer/amount.
        const original: OriginalDispatchCut=originalDispatchCut={park:undefined,flight:undefined,pending:true};
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
            cp.journal.commitOriginalModelCurrentCut(saved.reference, claim);
            continuationView.beginOriginalResourceInvalidation(saved.reference,original.park as object);
            continuationView.completeOriginalResourceInvalidation();
            // Unit only: journal ACK/fence consumption never issues InferAllow
            // or bypasses the original final Entry/current send gate.
          } finally {original.pending=false;}
        })();
        return original.flight;
      },
      retainOriginalResourceCurrentCut(park: unknown, storageBinding: StorageBinding, originWire: string, codec: object): Promise<SavedCut> {
        if (originalSave !== undefined) {
          if (originalSave.park !== park || originalSave.storageBinding !== storageBinding || originalSave.originWire !== originWire ||
              originalSave.codec.deref() !== codec) fail('ModelOriginalCurrentCutBindingMismatch');
          originalResourceReadCurrent(originalSave.park);
          return originalSave.promise!;
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
        const original: OriginalSave = originalSave = {storageBinding, originWire, codec: new WeakRef(codec),
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
              if (poll.kind !== 'continue' || (poll.work as number) < 1) fail('ModelOriginalCurrentStateWriteFailed');
              await yieldEventLoop();
            }
            let stateWire = operation.finishOriginalCurrentStateWriter(park, writer) as string | undefined;
            operation.cancelOriginalCurrentStateWriter(writer);
            writer = undefined;
            const bodyWire = control.encodeModelOriginalResourceDocument(originWire,
              stateWire!, cutWire, 'parked', envelope);
            stateWire = undefined;
            let document: ReturnType<Control['readModelOriginalResourceDocument']> | undefined =
              control.readModelOriginalResourceDocument(bodyWire, envelope);
            const storage = await selectedOriginalStorageEvidence(park, storageBinding, acquisition);
            originalResourceReadCurrent(park, acquisition);
            control.checkCheckedClientInferOriginalParkedStorageOrigin(plan.compiled,
              plan.runDefinition, selected.graph, originalPreparation!.scope, park,
              document, originalPreparation!.nodeInstallation, storage);
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
      prepareOriginalResourceCurrentCut(park: unknown, storageBinding: StorageBinding, receipt: StateReceipt, codec: object): Promise<CurrentStateReference> {
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
          return originalCut.promise!;
        }
        // This is one private installation caller, not a second Resource or
        // journal state machine. Fund this record, Promise/frames and BOTH
        // Common trees through the original installation before using it.
        const limits = originalCurrentCodecLimits(codec);
        const original: OriginalCut = originalCut = {park, storageBinding, receipt, saved: undefined, codec: new WeakRef(codec),
          promise: undefined, document: undefined, matched: undefined, facts: undefined,
          current() {
            return original.matched !== undefined && original.document !== undefined &&
              live.get(preparedCallSet) === owner && checkpoints() === cp &&
              operation.originalCurrentStateMatchCurrent(park, original.matched) === original.matched;
          },
          invalidationCurrent: request => operation.originalResourceInvalidationCurrent(park, request)};
        originalResourceCuts.set(park as object, new WeakRef(original));
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
              if (poll.kind !== 'continue' || (poll.work as number) < 1) fail('ModelOriginalCurrentStateDecodeFailed');
            }
            comparison = operation.startOriginalCurrentStateComparison(park, original.document, limits.comparisonWork);
            for (;;) {
              originalResourceReadCurrent(park, acquisition);
              const poll = operation.advanceOriginalCurrentStateComparisonWithMatch(park, comparison, limits.quantum);
              if (poll.kind === 'failed') fail('ModelOriginalCurrentStateComparisonFailed');
              if (poll.kind === 'complete') {original.matched = poll.matched; break;}
              if (poll.kind !== 'continue' || (poll.work as number) < 1) fail('ModelOriginalCurrentStateComparisonFailed');
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
      async readOriginalResourceState(park: unknown, storageBinding: StorageBinding, receipt: StateReceipt) {
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
          originalPreparation!.nodeInstallation, storage);
        originalResourceReadCurrent(park, acquisition);
        return document;
      },
      confirmOriginalResourceStateSaved,
      async originalResourceOrigin(storageBinding: StorageBinding, acquisition?: object) {
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
        const origin: Record<string, unknown> = {};
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
      originalJournalInvalidationCurrent(receipt: InvalidationReceipt, reference: CurrentStateReference, park: unknown, request: unknown) {
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
      beginOriginalResourceInvalidation(reference: CurrentStateReference, park: object) {
        originalJournalInstallation();
        if (originalInvalidation !== undefined || !owner.available ||
            operation.originalResourceParkCurrent(park) !== park ||
            cp.journal.originalModelCurrentCutOperationStatus(reference).state !== 'linked') {
          fail('ModelOriginalResourceInvalidationUnavailable');
        }
        const observation = cp.journal.originalModelCurrentCutObservation(reference);
        const facts = cp.journal.originalModelJournalObservationFacts(observation!);
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
          originalResourceCuts.delete(original.park as object);
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
          async readBundle(slot: number, beforeRead?: (bytes: number) => void) {
            if (!owner.available || !token.available) fail('ModelContinuationClosed');
            const call = calls[slot];
            if (call?.state !== 'SavedSuccess' || call.captureBundleCid === undefined) return undefined;
            const historical = cp.journal.readModelAttemptOriginals(call.entry);
            let stored: StoredSettlement | undefined;
            await readSettled({originals: originals as Originals, entry: call.entry,
              ...historical as Omit<typeof historical, 'entry'>},
              value => {stored = value;}, beforeRead);
            if (!owner.available || !token.available || stored?.state !== 'SavedSuccess' ||
                stored.evidence.model_capture_bundle!.cid !== call.captureBundleCid) fail('ModelSettlementCustodyLost');
            return Object.freeze({wire: stored.bodies.model_capture_bundle!,
              cid: call.captureBundleCid, count: 1});
          }});
      },
      entry: (slot: number) => owner.entries.get(slot), observe,
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
          ? await gate!.authorize({signal})
          : await gate!.resume({signal, resumption: {claim: {checkpointCid: existing!.checkpointCid!, claim}}});
        checkpoints();
        if (decision.action === 'waiting') return {status: 'waiting_checkpoint', checkpoint: decision.checkpoint};
        if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
        if (!owner.available) fail('ModelContinuationClosed');
        signal?.throwIfAborted();
        if (operation.hasModelCredentialPreparation?.()) {
          operation.prepareModelCredentials(preparedCallSet, owner.entries, () => {
            assertAuthorizationAccountCurrent(decision);
            if (claim !== undefined) {
              const current = (journalPort ?? cp.journal).admitResume(claim,
                {checkpointCid: existing!.checkpointCid!});
              if (current.resolutionCid !== decision.admission!.resolutionCid ||
                  current.configurationCid !== gate!.configurationCid) {
                fail('ModelCredentialResumeChanged');
              }
            }
            if (checkpoints() !== cp || !owner.available || !token.available ||
                live.get(preparedCallSet) !== owner || !owner.currentProvider()) {
              fail('ModelProviderBindingChanged');
            }
            signal?.throwIfAborted();
          });
        }
        if (view === undefined) view = cp.journal.registerImmediateModelCallSet({modelCallSet: originals as Originals, declaredResults, parentResume});
        owner.decision = decision;
        if (rawBinding?.complete !== true) {
          const dispatch = {account: selected.observeAccount(), principalId, at: now(), delegated: decision.runtimeDecision,
              observeAccount: selected.observeAccount, observeAt: now,
              enterCall(selectedEntry: OpaqueEntryOriginal) {
                const original = selectedEntry as EntryOriginal;
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
                    : cp.journal.enterResumedCall(claim, {...reference, checkpointCid: existing!.checkpointCid!,
                        resolutionCid: decision.admission!.resolutionCid});
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
              {...dispatch, beginEntry(selectedEntry: OpaqueEntryOriginal) {
                const original = selectedEntry as EntryOriginal;
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
                      checkpointCid: existing!.checkpointCid!,
                      resolutionCid: decision.admission!.resolutionCid}, claim);
                if (view === undefined) owner.pending = undefined;
                return view;
              }});
          }
          if (rawBinding !== undefined) {
            rawBinding.attempted = true;
            try {
              const policy = control.issueCheckedClientInferRawCapturePolicy(
                plan.compiled, plan.runDefinition, admittedDispatch, bound,
                {...rawSelection, storeAuthorityCid} as Parameters<Control['issueCheckedClientInferRawCapturePolicy']>[4]);
              const registration = control.registerCheckedClientInferRawCapture(
                plan.compiled, plan.runDefinition, admittedDispatch, bound,
                {policy, profile: rawSelection!.profile,
                  installation: rawSelection!.installation, probability: rawSelection!.probability,
                  account: selected.observeAccount(), at: now(), storeAuthorityCid,
                  selectionAvailable: () => owner.available && token.available &&
                    owner.currentProvider() && rawSelection?.selectionAvailable() === true,
                  observeAccount: selected.observeAccount, observeAt: now});
              // Use this continuation's actual selected Store, not a Provider
              // supplied CID, replacement Store or another retention Owner.
              const persistence = createModelRawTransportPersistenceFactory({store, moon, operation,
                registration, notify: (operation.ioNotification?.notify)!,
                retainHolding(value) {
                  if (!rawBinding.holdings!.includes(value)) rawBinding.holdings!.push(value);
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
          const reply = await selected.reconcileResponse!(Object.freeze({request,
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
  async function open(options: OpenOptions) {
    const ownership: OpenCustody = {};
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
    capturedContent: (token: Token, runDefinitionCid: string) =>
      ownedInput(token, runDefinitionCid).capturedContent,
    capturedContentBinding: (token: Token, runDefinitionCid: string) =>
      ownedInput(token, runDefinitionCid).capturedContentBinding,
    retire: (record: Pick<SourceInventory, 'originals'>) => retireReceipt(record.originals.fixedInputReceiptWire),
    discover: (runId: string) => checkpoints().journal.discoverModelCallSets({runId, limit: 100}),
    unresolved: (runId: string) => checkpoints().journal.hasUnresolvedModelCalls(runId),
    state: (identity: Parameters<Journal['readModelCalls']>[0]) => checkpoints().journal.readModelCalls(identity),
    savedScope(plan: Plan, preparedProgram: unknown, selected: Selected, token: Token) {
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
