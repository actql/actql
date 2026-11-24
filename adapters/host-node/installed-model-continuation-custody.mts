// The original continuation owns these Maps, its retained input leases and
// one installation of the SQLite Journal. Verification borrows those owners
// without making new dispatch or Store authority.
import {checked} from '../host-common/runtime-result.mjs';
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {bytesCid} from './local-account-config.mjs';
import {checkCapturedInventory, createInstalledModelInputCustody} from './installed-model-input-custody.mjs';

import type {runtimeCore} from '../host-common/runtime-core.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import type {CheckpointRuntime} from './checkpoint-runtime.mjs';
import type {openNodeInferOperation} from './infer-operation.mjs';
import type {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';
import type {createModelResumeState} from './model-resume-state.mjs';

type Verifier = NonNullable<Parameters<typeof createModelResumeState>[1]['verifier']>;
type Originals = Parameters<NonNullable<Verifier['admitCallSet']>>[0];
type Inventory = ReturnType<NonNullable<Verifier['admitCallSet']>>;
type CallSetFacts = Omit<Inventory, 'fixedInputCustody' | 'retryBinding'>;
type RunIdentity = ReturnType<NonNullable<Verifier['admitOriginalRun']>>;
type AttemptIdentity = ReturnType<NonNullable<Verifier['admitAttempt']>>;
type JournalIdentity = ReturnType<NonNullable<Verifier['projectOriginalJournalIdentity']>>;
type CurrentCut = ReturnType<NonNullable<Verifier['projectOriginalCurrentCut']>>;
type Settlement = NonNullable<Awaited<ReturnType<NonNullable<Verifier['verifySettlement']>>>>;
type SavedCallFacts = Readonly<{attemptCid: string; slotCid: string; captureCid: string; state: Settlement['state']}>;
type SettlementInput = Parameters<NonNullable<Verifier['verifySettlement']>>[0];
type Entry = SettlementInput['entry'];
type ParkFacts = ReturnType<NonNullable<Verifier['originalResourceCut']>['inspect']>;
type SavedFacts = ReturnType<NonNullable<Verifier['originalStateSaved']>['inspect']>;
type Journal = ReturnType<typeof openSqliteCheckpointJournal>;
type InputCustody = ReturnType<typeof createInstalledModelInputCustody>;
type Token = ReturnType<InputCustody['retain']>;
type StoredInput = Parameters<InputCustody['retain']>;
type Receipt = StoredInput[1];
type Snapshot = StoredInput[2];
type SourceInventory = Readonly<{originals: Originals; inventory: Inventory;
  scopeCid: string; checkpointCid: string | null}>;
type PendingEntry = Readonly<{entry: unknown; slot: number; callWire: string; attemptWire: string; authorityWire: string}>;
type LiveOwner = Readonly<{
  available: boolean; decision?: unknown; pending?: PendingEntry;
  operation: Pick<ReturnType<typeof openNodeInferOperation>, 'entryCurrent'>;
  currentProvider(): boolean;
}>;
type ResourceCut = Readonly<{
  facts?: ParkFacts;
  current(): boolean;
  invalidationCurrent(request: unknown): unknown;
}>;
type InputIdentity = Readonly<{digest: string; receipt: Receipt; scopeCid: string; inputArtifactCid: string}>;
type CheckpointInstallation = Readonly<{
  journal: Journal;
  readModelInput(receipt: Receipt): Promise<Uint8Array<ArrayBufferLike>>;
  originalModelStateSavedFacts(observation: unknown): SavedFacts;
  originalModelStateSavedObservationCurrent(observation: unknown): unknown;
}>;
type Control = Pick<ReturnType<typeof runtimeCore>['publicationControl'],
  'admit' | 'admitRunEvidence' | 'modelScopedPrivateHoldingCid'>;
type Store = Pick<Awaited<ReturnType<typeof openLocalPublicationStore>>,
  'inspectPhysicalHolding' | 'readPrivateEvidence' | 'confirmPrivateEvidence'>;
type Runtime = Readonly<{
  strategyRunEvidenceAdmit(name: string, wire: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramVerifyInferAttachmentAdmission(capture: unknown, authority: unknown, attachment: unknown): unknown;
  clientProgramReadInferCaptureBundle(wire: string, cid: string): unknown;
  clientProgramReleaseInferCaptureBundle(bundle: unknown): unknown;
}>;
type Ports<Installation extends CheckpointInstallation> = Readonly<{
  moon: Runtime; control: Control; store: Store; storeAuthorityCid: string;
  namespaceId: string; authorityScopeCid: string; runtime: CheckpointRuntime;
  getCheckpoints(): Installation | undefined;
  observeDiagnostic?: unknown;
}>;
type ModelInputOriginal = Pick<Snapshot['originals'],
  'originalRunWire' | 'preparedInvocationWire' | 'scopeWire' | 'providerBindingWire' |
  'inputArtifactWire' | 'slotWires' | 'expectedBoundary'>;
type EvidenceRole = typeof roles[number];
type StoredBodies = Partial<Record<EvidenceRole, string>>;
type StoredEvidence = Partial<Record<EvidenceRole, Readonly<{cid: string; holdingCid: string}>>>;
type SettledRecord = Readonly<{bodies: StoredBodies; evidence: StoredEvidence;
  state: Settlement['state']; terminalFailure?: true}>;

export const limits = Object.freeze({maxWireBytes: 1048576, maxNodes: 100000, maxDepth: 100});
export const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const parseCore = <Facts extends object>(wire: string): Facts => {
  const value = JSON.parse(wire) as {ok: boolean; code?: string} & Facts;
  if (value.ok !== true) fail(value.code ?? 'InstalledModelAdmissionRejected');
  const {ok, ...facts} = value;
  return facts as Facts;
};
export const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
export const scopeKeys = ['runId', 'runDefinitionCid', 'preparedInvocationCid', 'scopeCid',
  'providerBindingCid', 'inputArtifactCid', 'taskIndex', 'strategyRevision'] as const;
export const select = <Value extends object, Key extends keyof Value>(value: Value, keys: readonly Key[]) =>
  Object.fromEntries(keys.map(key => [key, value[key]])) as Pick<Value, Key>;
export const entryIdentity = (entry: Entry): Settlement['entry'] => select(entry, entry.provenance === 'deferred'
  ? ['runId', 'runDefinitionCid', 'preparedInvocationCid', 'checkpointCid',
      ...scopeKeys.slice(3), 'ordinal', 'slotCid', 'attemptIndex', 'attemptCid',
      'intentId', 'claimant', 'generation', 'resolutionCid']
  : [...scopeKeys, 'provenance', 'ordinal', 'slotCid', 'attemptIndex', 'attemptCid', 'authorityCid']) as Settlement['entry'];
const originalKeys = ['originalRunWire', 'preparedInvocationWire', 'scopeWire',
  'providerBindingWire', 'inputArtifactWire', 'slotWires', 'expectedBoundary'] as const;
// Hash opaque original wires without the configuration canonicalizer's text normalization.
const originalDigest = (originals: ModelInputOriginal) => bytesCid(Buffer.from(canonicalJson(select(originals, originalKeys))));
const roles = ['model_call_attempt', 'model_attempt_accounting', 'model_attempt_outcome',
  'model_dispatch_authority', 'model_slot_capture', 'model_capture_bundle', 'model_attachment_admission'] as const;


export function createInstalledModelContinuationCustody<Installation extends CheckpointInstallation>({moon, control, store, storeAuthorityCid, namespaceId,
  authorityScopeCid, runtime, getCheckpoints, observeDiagnostic}: Ports<Installation>) {
  const live = new WeakMap<object, LiveOwner>();
  // Route only the original bare park to its existing installed operation's
  // completed Common comparison. Escaped park refs retain no new callback or
  // Owner graph through this weak membership; the operation keeps its borrow.
  const originalResourceCuts = new WeakMap<object, WeakRef<ResourceCut>>();
  function originalResourceCut(park: unknown): ResourceCut & Readonly<{facts: ParkFacts}> {
    const original = originalResourceCuts.get(park as object)?.deref();
    if (original?.facts === undefined || !original.current()) {
      fail('ModelOriginalCurrentCutUnavailable');
    }
    return original as ResourceCut & Readonly<{facts: ParkFacts}>;
  }
  // Synchronous journal checks need the previously authenticated receipt and
  // original digest while a Run is waiting or unknown. They do not need input
  // rows, submitted programs or responses, and cannot authorize a fresh send.
  const inventories = new Map<string, InputIdentity>();
  const diagnostic = diagnosticObserver(observeDiagnostic);
  let checkpointInstallation: Readonly<{checkpoints: Installation; journal: Journal}> | undefined;
  const {retain, ownedInput, release, usage, changed, hasRetainedReceipt, firstRetained, leaseReceiptWire} =
    createInstalledModelInputCustody({inventorySize: () => inventories.size, retireReceipt, diagnostic, fail});
  function retireReceipt(receiptWire: string) {
    const held = inventories.get(receiptWire);
    if (held === undefined || hasRetainedReceipt(receiptWire)) return;
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
  function admittedInventory(originals: Originals, immediate: boolean, token?: Token): Inventory {
    const retained = token ?? firstRetained(originals.fixedInputReceiptWire);
    const prior = inventories.get(originals.fixedInputReceiptWire);
    if (retained === undefined && prior === undefined || retained?.available === false) {
      fail('ModelFixedInputCustodyUnavailable');
    }
    const admitted = retained === undefined ? prior! : {
      digest: originalDigest(retained.snapshot!.originals), receipt: retained.receipt,
      scopeCid: retained.snapshot!.scopeCid, inputArtifactCid: retained.snapshot!.inputArtifactCid};
    if (originalDigest(originals as Originals & ModelInputOriginal) !== admitted.digest) fail('ModelFixedInputOriginalMismatch');
    const facts = parseCore<CallSetFacts>((immediate ? runtime.modelImmediateCallSetAdmit
      : runtime.modelCallSetAdmit)(canonicalJson(originals)));
    if (facts.scopeCid !== admitted.scopeCid ||
        facts.inputArtifactCid !== admitted.inputArtifactCid) fail('ModelFixedInputOriginalMismatch');
    if (retained !== undefined) inventories.set(originals.fixedInputReceiptWire, admitted);
    return JSON.parse(canonicalJson({...facts, fixedInputCustody: {...admitted.receipt, inputArtifactCid: facts.inputArtifactCid},
      retryBinding: {owner: 'single_attempt_model_execution', maxAttempts: 1},
      slots: facts.slots.map(slot => ({...slot, maxAttempts: 1}))})) as Inventory;
  }
  async function readSettled({originals, entry, attemptWire, authorityWire}:
    Pick<SettlementInput, 'originals' | 'entry' | 'attemptWire' | 'authorityWire'>,
    retainRecord?: (record: SettledRecord) => void, beforeRead?: (bytes: number) => void): Promise<Settlement | null> {
    const definition = control.admit('run_definition',
      (JSON.parse(originals.originalRunWire) as {runDefinitionWire: string}).runDefinitionWire, limits);
    const bodies: StoredBodies = {};
    const evidence: StoredEvidence = {};
    for (const name of roles) {
      const holdingCid = control.modelScopedPrivateHoldingCid(definition, storeAuthorityCid, entry, name);
      const holding = await store.inspectPhysicalHolding(holdingCid);
      if (holding === undefined) break;
      // Optional Evidence reserves its copy envelope before private decoding.
      // Normal execution restoration keeps its existing Store-owned limits.
      beforeRead?.(holding.objects.reduce((sum, object) => sum + object.byte_count, 0));
      // The Store's selected holding reader already checks the exact manifest CID.
      const wire = new TextDecoder('utf-8', {fatal: true}).decode(
        await store.readPrivateEvidence(name, holding.manifest_cid as string, holdingCid));
      if (await store.confirmPrivateEvidence({name, semanticCid: holding.manifest_cid, holdingCid, wire}) === undefined) {
        fail('ModelSettlementCustodyLost');
      }
      bodies[name] = wire;
      evidence[name] = {cid: holding.manifest_cid as string, holdingCid};
    }
    if (roles.slice(0, 4).some(role => bodies[role] === undefined)) return null;
    if (bodies.model_call_attempt !== attemptWire || bodies.model_dispatch_authority !== authorityWire) {
      fail('ModelSettlementAttemptMismatch');
    }
    if (bodies.model_slot_capture === undefined || bodies.model_capture_bundle === undefined) {
      if (roles.slice(0, 4).some(role => bodies[role] === undefined)) return null;
      const admitted = JSON.parse(runtime.modelStoppedCallAdmit(canonicalJson(originals), entry.ordinal,
        attemptWire, authorityWire, bodies.model_attempt_accounting!, bodies.model_attempt_outcome!));
      if (admitted.ok !== true) return null;
      if (admitted.attemptCid !== entry.attemptCid || admitted.slotCid !== entry.slotCid ||
          admitted.accountingCid !== evidence.model_attempt_accounting!.cid ||
          admitted.outcomeCid !== evidence.model_attempt_outcome!.cid) fail('ModelStoppedProofMismatch');
      const record = Object.freeze({bodies, evidence, state: 'SavedFailure', terminalFailure: true as const});
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
      evidence.model_capture_bundle!.cid));
    try {
      const document = JSON.parse(bodies.model_capture_bundle);
      if (document.captures.length !== (outcome === 'ok' ? 1 : 0)) fail('ModelSettlementResponseMismatch');
      const observationWire = outcome === 'ok' ? canonicalJson(document.captures[0].evidence) : undefined;
      const facts = parseCore<SavedCallFacts>(runtime.modelSavedCallAdmit(canonicalJson(originals), entry.ordinal,
        attemptWire, authorityWire, bodies.model_attempt_accounting!,
        bodies.model_attempt_outcome!, bodies.model_slot_capture, observationWire));
      if (facts.attemptCid !== entry.attemptCid || facts.slotCid !== entry.slotCid ||
          facts.captureCid !== evidence.model_slot_capture!.cid) fail('ModelSettlementProofMismatch');
      const record = Object.freeze({bodies, evidence, state: facts.state});
      retainRecord?.(record);
      return {entry: entryIdentity(entry), state: facts.state, durable: true, evidence, retryAllowed: false};
    } finally { moon.clientProgramReleaseInferCaptureBundle(bundle); }
  }
  const verifier = Object.freeze<Required<Verifier>>({
    admitOriginalRun: ({originalRunWire}) => parseCore<RunIdentity>(runtime.modelOriginalRunAdmit(originalRunWire)),
    admitCallSet: originals => admittedInventory(originals, false),
    admitImmediateCallSet: originals => admittedInventory(originals, true),
    admitAttempt: ({originals, slot, attemptWire, authorityWire, attemptIndex}) =>
      parseCore<AttemptIdentity>(runtime.modelImmediateCallAttemptAdmit(canonicalJson(originals), slot.ordinal,
        attemptWire, authorityWire, attemptIndex)),
    // JSON serialization preserves journal data strings verbatim. The bounded
    // Common issuer supplies canonical data identities, not current grants.
    projectOriginalJournalIdentity: ({originals, row}) =>
      parseCore<JournalIdentity>(runtime.modelOriginalJournalIdentity(JSON.stringify(originals), JSON.stringify(row))),
    projectOriginalCurrentCut: ({facts}) =>
      parseCore<{cut: CurrentCut}>(runtime.modelOriginalJournalCutData(JSON.stringify(facts))).cut,
    originalStateSaved: Object.freeze<NonNullable<Verifier['originalStateSaved']>>({
      inspect: observation => checkpoints().originalModelStateSavedFacts(observation),
      current: observation => checkpoints().originalModelStateSavedObservationCurrent(observation),
    }),
    originalResourceCut: Object.freeze<Required<NonNullable<Verifier['originalResourceCut']>>>({
      inspect: park => originalResourceCut(park).facts,
      current: park => {
        const original = originalResourceCuts.get(park as object)?.deref();
        return original?.facts !== undefined && original.current() ? park : undefined;
      },
      invalidationCurrent: (request, park) => originalResourceCut(park).invalidationCurrent(request),
    }),
    admitImmediateEntry({decision, preparedCallSet, inventory, originals, slot, attemptIndex,
      attemptCid, attemptWire, authorityWire, at}) {
      const owner = live.get(preparedCallSet as object);
      const facts = authorizationDispatchFacts(decision);
      const pending = owner?.pending;
      if (!owner?.available || owner.decision !== decision || facts === undefined ||
          facts.configurationCid !== (originals as Originals & ModelInputOriginal).expectedBoundary.configuration_cid ||
          facts.principal !== (originals as Originals & ModelInputOriginal).expectedBoundary.principal ||
          pending?.slot !== slot.ordinal || pending.callWire !== originals.slotWires[slot.ordinal] ||
          pending.attemptWire !== attemptWire || pending.authorityWire !== authorityWire ||
          !owner.operation.entryCurrent(pending.entry, preparedCallSet) ||
          owner.currentProvider() !== true || Date.parse(at) >= Date.parse(inventory.runValidUntil!)) {
        fail('ModelImmediateOwnerRejected');
      }
      const attempted = parseCore<AttemptIdentity>(runtime.modelImmediateCallAttemptAdmit(canonicalJson(originals),
        slot.ordinal, attemptWire, authorityWire, attemptIndex));
      if (attempted.attemptCid !== attemptCid) fail('ModelImmediateOwnerRejected');
      const authority = control.admitRunEvidence('model_dispatch_authority', authorityWire, limits);
      return {...select(inventory, scopeKeys), ordinal: slot.ordinal, slotCid: slot.slotCid,
        attemptIndex, attemptCid, authorityCid: authority.identity, current: true,
        admittedAt: at, runValidUntil: inventory.runValidUntil!, dispatchValidUntil: inventory.runValidUntil!};
    },
    verifySettlement: readSettled,
  });
  async function prime(record: SourceInventory) {
    const receiptWire = record.originals.fixedInputReceiptWire;
    const receipt = JSON.parse(receiptWire) as Receipt;
    if (receipt.runId !== record.inventory.runId ||
        receipt.runDefinitionCid !== record.inventory.runDefinitionCid) fail('ModelSnapshotBindingMismatch');
    const bytes = await checkpoints().readModelInput(receipt);
    const wire = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
    const snapshot = JSON.parse(wire) as Snapshot;
    if (snapshot.version !== 'actql-installed-model-input/0.1' ||
        snapshot.scopeCid !== record.scopeCid || receipt.runId !== record.inventory.runId ||
        receipt.runDefinitionCid !== record.inventory.runDefinitionCid) fail('ModelSnapshotBindingMismatch');
    checkCapturedInventory(snapshot.capturedContent, receipt.runDefinitionCid,
      snapshot.capturedContentBinding, fail);
    const token = retain(receiptWire, receipt, snapshot, bytes.byteLength);
    try {
      admittedInventory(record.originals, record.checkpointCid === null, token);
      return token;
    } catch (error) { release(token); throw error; }
  }
  async function observe(entry: Settlement['entry']) {
    const result = await (entry.provenance === 'immediate'
      ? checkpoints().journal.observeImmediateModelCall(entry)
      : checkpoints().journal.observeResumedCall(entry));
    diagnostic('model_call_observed', {ref: {namespaceId, authorityScopeCid,
      runDefinitionCid: entry.runDefinitionCid}, task: entry.taskIndex,
      attempt: entry.attemptIndex, attemptCid: entry.attemptCid, slot: entry.ordinal,
      outcome: {SavedSuccess: 'succeeded', SavedFailure: 'failed',
        EnteredUnknown: 'unknown', Unsent: 'pending'}[result?.state!]});
    return result;
  }
  return Object.freeze({live, originalResourceCuts, diagnostic, retain, ownedInput, release, usage, leaseReceiptWire,
    retireReceipt, checkpoints, installOriginalJournal, admittedInventory, readSettled, verifier, prime, observe,
    get checkpointInstallation() { return checkpointInstallation; }});
}
