// Shared private custody for the existing installed Model component. Local
// and Effect-free Runs keep their own execution/publication owners; accepted
// captures, attempt proofs and Store writes follow this same persistence path.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
// @ts-expect-error TS7016 until the authored Infer operation owner is migrated.
import {fundInferCaptureInventory, fundedInferCaptureInventoryCount, fundedInferStoppedAttemptCount} from './infer-operation.mjs';
import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type Holding = ReturnType<typeof preparePrivatePublicationHolding>;
type HoldingName = Extract<Parameters<typeof preparePrivatePublicationHolding>[1], {contentCid?: never}>['name'];
type Store = Parameters<typeof preparePrivatePublicationHolding>[0] & Readonly<{
  privateEvidenceWireLimit?(): number;
}>;
type Evidence = Readonly<{wire: string; identity: string}>;
type ModelEntry = Readonly<{ordinal: number; scopeCid: string; attemptCid: string}>;
type EntryObservation = Readonly<{state: string}>;
type ObserveEntry = (entry: ModelEntry) => Awaitable<EntryObservation | undefined>;
type ReadEntry = (slot: number) => ModelEntry | undefined;
type EntryJournal = Readonly<{observe: ObserveEntry; entry: ReadEntry}>;
type HoldingPhase = 'entered' | 'settled';
type Settlement = {settlement: unknown; entry: ModelEntry; wire: string; complete: boolean; exporter?: unknown};
type FaultDetails = Readonly<{role: HoldingName; slot: number} | {complete: boolean} |
  {slot: number; scopeCid: string; attemptCid: string; state?: string}>;
type FaultInjection = (site: 'infer_private_holding_commit' | 'infer_model_response_stored' |
  'infer_model_settlement_committed' | 'infer_observation_advanced', details: FaultDetails) => Awaitable<unknown>;
type Control = Readonly<{
  modelPrivateHoldingCid(definition: unknown, authority: string, role: HoldingName, slot: number): string;
  modelScopedPrivateHoldingCid(definition: unknown, authority: string, entry: ModelEntry, role: HoldingName, phase: HoldingPhase): string;
  admitRunEvidence(role: HoldingName, wire: string,
    limits: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>): Evidence;
}>;
type Operation = Readonly<{
  physicalStopped(): boolean;
  cleanupProgress?(): unknown;
  cleanup(): boolean;
  stop(): Awaitable<unknown>;
  reserveOriginalPublicationCapacity?(): void;
  acquireOutput(): unknown;
  acquireCapture(): unknown;
  issuedAttachmentAdmission(slot: number): unknown;
  stoppedAttemptCount(): number;
  stoppedAttemptSlot?(index: number): number | undefined;
  advanceStoppedAttemptUsage?(slot: number, work: number): Readonly<{complete: boolean}> | undefined;
  attemptEvidence(slot: number): unknown;
  settlementSlot(settlement: unknown): number;
  issuedSlotCapture(slot: number): unknown;
  invocationEvidenceView(control: Control, slot: number): Evidence | undefined;
  acknowledgeSettlement(settlement: unknown): void;
  startObservation(bounds: Readonly<{maxSlots: number; maxWireBytes: number; maxWork: number}>): unknown;
  prepareOriginalUsage?(source: Operation, capture: unknown, count: number): void;
  beginOriginalUsage?(source: Operation, capture: unknown, count: number, maxBytes: number): unknown;
  installSettlementCleanup(cleanup: (settlement: unknown) => Promise<EntryObservation>): void;
}>;
// Keep Common values opaque. Only the existing Int, Bool, String and unboxed
// Option slots cross into typed Host data at the compiler binding.
type Runtime = Readonly<{
  clientProgramReleaseInferInvocationBinding(binding: unknown): boolean;
  clientProgramCancelInferObservationIssuance(issuance: unknown): boolean;
  clientProgramAdvanceInferObservationIssuance(issuance: unknown, work: number): unknown;
  clientProgramCleanupInferObservationIssuance(issuance: unknown): unknown;
  clientProgramCancelInferCaptureExport(exporter: unknown): boolean;
  clientProgramAdvanceInferCaptureExport(exporter: unknown, work: number): unknown;
  clientProgramCleanupInferCaptureExport(exporter: unknown): unknown;
  clientProgramReleaseInferCapture(capture: unknown): boolean;
  clientProgramReleaseInferOutput(output: unknown): boolean;
  clientProgramInferCaptureCallCount(capture: unknown): number | undefined;
  strategyRunEvidenceJson(value: unknown): string;
  clientProgramInferAttemptLeaf(proof: unknown, kind: string): unknown;
  clientProgramStartInferCallSettlementExport(settlement: unknown, wireBytes: number, work: number): unknown;
  clientProgramInferCaptureExportIdentity(exporter: unknown): string | undefined;
  clientProgramBindInferSlotCapture(capture: unknown, slot: number, adopted: unknown): unknown;
  clientProgramStartInferCaptureExport(capture: unknown, wireBytes: number, work: number): unknown;
  clientProgramInferCaptureCall(capture: unknown, slot: number): unknown;
  clientProgramInferCaptureOutcome(capture: unknown, slot: number): string | undefined;
  strategyRunEvidenceIdentity(value: unknown): string;
  clientProgramInferCaptureExportWireUsage?(exporter: unknown): unknown;
}>;
type Publication = Readonly<{binding: unknown; observation: Evidence; invocation: Evidence}>;
type PublicationFor<Value extends Publication> = (values: Readonly<{
  operation: Operation; issuance: unknown; modelEvidence: readonly Evidence[];
}>) => Awaitable<Value>;
type CustodyOptions<Value extends Publication> = Readonly<{
  moon: Runtime; control: Control; operation: Operation; plan: Readonly<{runDefinition: unknown}>;
  store: Store; storeAuthorityCid: string; sourceEvidence?: readonly Evidence[];
  replay?: boolean; faultInjection?: FaultInjection; publicationFor?: PublicationFor<Value>;
  durableCalls?: boolean; captureOnly?: boolean;
}>;
type RetiredPort = 'moon' | 'control' | 'operation' | 'plan' | 'store';
type RetirableOptions<Value extends Publication> = Omit<CustodyOptions<Value>, RetiredPort> & {
  [Key in RetiredPort]: CustodyOptions<Value>[Key] | undefined;
};
type UsageCall = Readonly<{slotCid: string; outcome: string}>;
type UsageInventory = Readonly<{count: number; calls: readonly UsageCall[]; cid: string | undefined}>;
type EvaluationBundle = Readonly<Omit<UsageInventory, 'calls'> & {
  wire: string; usage?: unknown; calls: readonly (UsageCall & Readonly<{callWire: string}>)[];
}>;
type CaptureCustody<Value extends Publication> = Readonly<{
  custody: Readonly<{cleanup(): Promise<boolean>; retirePublication(): Promise<boolean>;
    cleanupPending(): boolean; close(): Promise<void>}>;
  retainCompleted(publicationOriginal?: Operation): boolean;
  persistStoppedAttempts(): Promise<void>;
  completedCallCount(): number | undefined;
  completedInventoryReceipt(): object | undefined;
  modelEvidence(): readonly Evidence[] | undefined;
  usageInventory(current: () => void): UsageInventory | undefined;
  beginUsage(maxBytes: number, current: () => void): unknown;
  evaluationBundle(): EvaluationBundle | undefined;
  configureModelJournal(journal: EntryJournal): void;
  persistSettlement(settlement: unknown, entry: ModelEntry): Promise<EntryObservation>;
  persist(): Promise<Value | undefined>;
}>;

const pending = () => Object.assign(new Error('ClientDispatchCleanupPending'),
  {code: 'ClientDispatchCleanupPending'});

export function openNodeInferCaptureCustody<Value extends Publication>(options: CustodyOptions<Value>): CaptureCustody<Value>;
export function openNodeInferCaptureCustody<Value extends Publication>({moon, control, operation, plan,
  store, storeAuthorityCid, sourceEvidence = [] as readonly Evidence[] | undefined, replay = false, faultInjection,
  publicationFor, durableCalls = false, captureOnly = false}: RetirableOptions<Value>): CaptureCustody<Value> {
  if ((!captureOnly && typeof publicationFor !== 'function') ||
      captureOnly && !durableCalls || !Array.isArray(sourceEvidence)) {
    throw new TypeError('InvalidInferCaptureCustody');
  }
  let issuance: unknown, publication: Value | undefined, capture: unknown, exporter: unknown,
    captureOutput: unknown, count: number | undefined;
  let reclaimed = false;
  let pendingHolding: Holding | undefined;
  let captureStored = false;
  let capturePersisted = false;
  let issuanceComplete = false;
  let persistCapture: (preparePublication?: boolean) => Promise<void>;
  let attemptsStored = false;
  let sourceStored = false;
  let settling: Settlement | undefined;
  let observeModelEntry: ObserveEntry | undefined;
  let modelEntryFor: ReadEntry | undefined;
  let durableSettlements: Map<number, string> | undefined = new Map();
  let cleanupFlight: Promise<boolean> | undefined;
  let publicationCleanupFlight: Promise<boolean> | undefined,
    publicationRetirementFlight: Promise<boolean> | undefined;
  let publicationCleaned = false, publicationRetired = false;
  let storedCaptureWireLimit: number | undefined;
  let captureInventory: object | undefined, publicationFunding: Operation | undefined,
    evaluation: EvaluationBundle | undefined, projectedModelEvidence: readonly Evidence[] | undefined;

  // Same immutable original Store extent, before constructing its exporter.
  // This scalar is not funding, persistence, currentness or a cleanup ACK.
  // Cache a known zero as zero; absence/invalid DATA never defaults to1MiB.
  function maximumStoredCaptureWire() {
    if (storedCaptureWireLimit !== undefined) return storedCaptureWireLimit;
    const select = store!.privateEvidenceWireLimit;
    if (typeof select !== 'function') {
      throw Object.assign(new Error('InstalledInferCaptureStoreWireLimitUnavailable'),
        {code: 'InstalledInferCaptureStoreWireLimitUnavailable'});
    }
    const limit = Reflect.apply(select, store, []);
    if (!Number.isSafeInteger(limit) || limit < 0) {
      throw Object.assign(new Error('InstalledInferCaptureStoreWireLimitUnavailable'),
        {code: 'InstalledInferCaptureStoreWireLimitUnavailable'});
    }
    storedCaptureWireLimit = Math.min(1048576, limit);
    return storedCaptureWireLimit;
  }

  // Retire only this adapter's aliases after its existing physical/Core
  // cleanup succeeds. Durable Store originals and previously transferred
  // immutable views retain their own custody; this does not erase them or
  // claim that GC has reclaimed their backing allocations.
  function retirePublicationAliases() {
    wire = '';
    modelEvidence = undefined;
    durableSettlements = undefined;
    observeModelEntry = undefined;
    modelEntryFor = undefined;
    settling = undefined;
    pendingHolding = undefined;
    sourceEvidence = undefined;
    publicationFor = undefined;
    faultInjection = undefined;
    storedCaptureWireLimit = undefined;
    captureInventory = publicationFunding = evaluation = projectedModelEvidence = undefined;
    publicationRetired = true;
  }
  function retireAliases() {
    retirePublicationAliases();
    operation = undefined;
    plan = undefined;
    control = undefined;
    store = undefined;
    moon = undefined;
  }

  // A failed write retains its exact physical owner. Cleanup retries only
  // that write, never operation.run or the provider.
  const cleanupPublicationOwned = async () => {
    if (publicationCleaned) return true;
    if (!operation!.physicalStopped()) return false;
    if (settling !== undefined) await persistSettlement();
    // Once a response has been accepted, reclamation cannot discard it
    // merely because a private write failed. Resume persistence of the same
    // common-owned evidence; this never reruns Compute or dispatch.
    if (capture !== undefined && !capturePersisted) {
      await persistCapture(false);
    }
    if (capture === undefined && !replay) await persistStoppedAttempts();
    if (pendingHolding !== undefined) {
      await pendingHolding.commit();
      pendingHolding = undefined;
    }
    if (publication !== undefined) {
      moon!.clientProgramReleaseInferInvocationBinding(publication.binding);
      publication = undefined;
    }
    if (issuance !== undefined) {
      if (moon!.clientProgramCancelInferObservationIssuance(issuance)) {
        checked(moon!.clientProgramAdvanceInferObservationIssuance(issuance, 1));
      }
      if (!checked(moon!.clientProgramCleanupInferObservationIssuance(issuance))) {
        return false;
      }
      issuance = undefined;
    }
    if (exporter !== undefined) {
      if (moon!.clientProgramCancelInferCaptureExport(exporter)) {
        checked(moon!.clientProgramAdvanceInferCaptureExport(exporter, 1));
      }
      if (!checked(moon!.clientProgramCleanupInferCaptureExport(exporter))) {
        return false;
      }
      exporter = undefined;
    }
    if (capture !== undefined) {
      moon!.clientProgramReleaseInferCapture(capture);
      capture = undefined;
    }
    if (captureOutput !== undefined) {
      moon!.clientProgramReleaseInferOutput(captureOutput);
      captureOutput = undefined;
    }
    publicationCleaned = true;
    return true;
  };
  const cleanupPublication = () => {
    // Both the normal parent cleanup and the private byte-borrow caller use
    // this same physical child flight. A pending/failed write or exporter
    // keeps its original responsibility and permits retry of only that child.
    if (publicationCleanupFlight !== undefined) return publicationCleanupFlight;
    publicationCleanupFlight = cleanupPublicationOwned().then(value => {
      if (!value) publicationCleanupFlight = undefined;
      return value;
    }, error => { publicationCleanupFlight = undefined; throw error; });
    return publicationCleanupFlight;
  };
  const retirePublication = () => {
    // This is local alias retirement, not Model cleanup or a capacity grant.
    // Its existing same-Ledger borrower is released separately, BEFORE the
    // parent Model cleanup that waits for that borrow's output use. The parent
    // operation/Store/Core originals remain retained for pending final cleanup.
    if (publicationRetirementFlight !== undefined) return publicationRetirementFlight;
    publicationRetirementFlight = cleanupPublication().then(value => {
      if (value) retirePublicationAliases();
      else publicationRetirementFlight = undefined;
      return value;
    }, error => { publicationRetirementFlight = undefined; throw error; });
    return publicationRetirementFlight;
  };
  const cleanupOwned = async () => {
    if (reclaimed) return true;
    if (!await cleanupPublication()) return false;
    for (;;) {
      const before = operation!.cleanupProgress?.();
      reclaimed = operation!.cleanup();
      if (reclaimed) { retireAliases(); return true; }
      if (operation!.cleanupProgress?.() === before) return false;
      // The common owner released one more physical cursor. Yield before
      // advancing cleanup again; an unchanged/pending cursor remains owned.
      await yieldEventLoop();
    }
  };
  const cleanup = () => {
    // Several existing parents may observe the same pending cleanup. Do not
    // let a second await race the first owner's final alias retirement.
    // Keep the successful flight stable; false/rejection permits retry of
    // the same original responsibility, never persistence or dispatch anew.
    if (cleanupFlight !== undefined) return cleanupFlight;
    cleanupFlight = cleanupOwned().then(value => {
      if (!value) cleanupFlight = undefined;
      return value;
    }, error => { cleanupFlight = undefined; throw error; });
    return cleanupFlight;
  };
  const custody = Object.freeze({cleanup, retirePublication,
    cleanupPending: () => !reclaimed,
    async close() {
      if (reclaimed) return;
      // Stop without reclaiming: failed executions still own attempt proofs
      // that must reach private custody before the model owner is released.
      await operation!.stop();
      if (!await cleanup()) throw pending();
    }});
  function retainCompleted(publicationOriginal: Operation | undefined = operation) {
    if (reclaimed || publicationCleaned) throw new Error('InstalledInferCaptureUnavailable');
    if (capture !== undefined) return true;
    // The actual original operation selects and reserves terminal publication
    // capacity before these additional captures/exporters/metadata are built.
    // Its initial record and per-slot/raw phases require earlier startup funds.
    publicationOriginal!.reserveOriginalPublicationCapacity?.();
    captureInventory = fundInferCaptureInventory(operation, publicationOriginal);
    publicationFunding = publicationOriginal;
    captureOutput ??= operation!.acquireOutput();
    if (captureOutput === undefined) throw new Error('InstalledInferOutputUnavailable');
    capture = operation!.acquireCapture();
    count = moon!.clientProgramInferCaptureCallCount(capture);
    const funded = fundedInferCaptureInventoryCount(captureInventory, operation);
    if (!Number.isInteger(count) || count! < 0 || count! > 2147483647 ||
        (count! > 128 && funded !== count) || funded !== undefined && funded !== count) {
      throw new Error('InstalledInferCaptureInventoryUnavailable');
    }
    return true;
  }
  async function hold(name: HoldingName, slot: number, wire: string, semanticCid: string,
    entry?: ModelEntry, phase: HoldingPhase = 'settled') {
    if (pendingHolding !== undefined) {
      await pendingHolding.commit();
      pendingHolding = undefined;
    }
    pendingHolding = preparePrivatePublicationHolding(store!, {name, wire,
      semanticCid, holdingCid: entry === undefined
        ? control!.modelPrivateHoldingCid(plan!.runDefinition, storeAuthorityCid, name, slot)
        : control!.modelScopedPrivateHoldingCid(plan!.runDefinition, storeAuthorityCid, entry, name, phase)});
    await faultInjection?.('infer_private_holding_commit', {role: name, slot});
    await pendingHolding.commit();
    pendingHolding = undefined;
  }
  async function holdEvidence(name: HoldingName, slot: number, evidence: unknown,
    entry?: ModelEntry, phase?: HoldingPhase) {
    const wire = moon!.strategyRunEvidenceJson(evidence);
    const admitted = control!.admitRunEvidence(name, wire,
      {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20});
    await hold(name, slot, admitted.wire, admitted.identity, entry, phase);
    return admitted;
  }
  async function holdAttachments(slot: number, entry?: ModelEntry, phase?: HoldingPhase) {
    const admission = operation!.issuedAttachmentAdmission(slot);
    if (admission !== undefined) {
      await holdEvidence('model_attachment_admission', slot, admission, entry, phase);
    }
  }
  async function persistStoppedAttempts() {
    if (reclaimed || publicationCleaned) return;
    if (attemptsStored) return;
    await persistSourceObservation();
    const attempts = operation!.stoppedAttemptCount();
    const funded = fundedInferStoppedAttemptCount(operation);
    if (!Number.isInteger(attempts) || attempts < 0 || attempts > 2147483647 ||
        (attempts > 128 && funded !== attempts)) {
      throw new Error('InstalledInferAttemptInventoryUnavailable');
    }
    for (let index = 0; index < attempts; index++) {
      const slot = operation!.stoppedAttemptSlot?.(index) ?? index;
      const entry = durableCalls ? modelEntryFor?.(slot) : undefined;
      // This same custody already persisted AND acknowledged that exact
      // attempt. A completed Model refuses the stopped-only usage reader;
      // do not reopen it merely because publication was never acquired.
      // Other/unknown attempts still retire their original reader below.
      if (entry !== undefined) {
        const acknowledgedAttempt = durableSettlements!.get(slot);
        if (acknowledgedAttempt !== undefined && acknowledgedAttempt === entry.attemptCid) continue;
      }
      if (typeof operation!.advanceStoppedAttemptUsage !== 'function') {
        throw new Error('InstalledInferRawUsageUnavailable');
      }
      // Persist only after the original Common usage child has retired.
      // Common preserves partials and reader issues on the same attempt; JS
      // neither decodes raw bytes nor classifies a stopped outcome as success.
      for (;;) {
        const progress = operation!.advanceStoppedAttemptUsage(slot, 1);
        if (typeof progress?.complete !== 'boolean') {
          throw new Error('InstalledInferRawUsageUnavailable');
        }
        if (progress.complete) break;
        await yieldEventLoop();
      }
      const proof = operation!.attemptEvidence(slot);
      let terminalFailure = false;
      if (durableCalls) {
        const outcome = JSON.parse(moon!.strategyRunEvidenceJson(
          moon!.clientProgramInferAttemptLeaf(proof, 'outcome')));
        // Adopted responses/failures reached their settled Store cells before
        // the next send. A stopped unknown keeps separate entered-phase proof.
        if (['ok', 'provider_failure'].includes(outcome.category)) continue;
        terminalFailure = outcome.category === 'contract_violation';
        if (entry === undefined) throw new Error('InferStoppedAttemptEntryMissing');
      }
      for (const [kind, name] of [
        ['attempt', 'model_call_attempt'],
        ['accounting', 'model_attempt_accounting'],
        ['outcome', 'model_attempt_outcome'],
        ['authority', 'model_dispatch_authority'],
      ] as const) {
        await holdEvidence(name, slot,
          moon!.clientProgramInferAttemptLeaf(proof, kind), entry,
          durableCalls && !terminalFailure ? 'entered' : undefined);
      }
      await holdAttachments(slot, entry, durableCalls && !terminalFailure ? 'entered' : undefined);
      if (terminalFailure) await observeModelEntry!(entry!);
      await yieldEventLoop();
    }
    attemptsStored = true;
  }
  async function persistSourceObservation() {
    if (sourceStored) return;
    for (const [slot, evidence] of sourceEvidence!.entries()) {
      await hold('source_evidence', slot, evidence.wire, evidence.identity);
    }
    sourceStored = true;
  }
  async function persistSettlement() {
    if (settling === undefined) throw new Error('InferSettlementMissing');
    const current = settling;
    const slot = operation!.settlementSlot(current.settlement);
    if (slot !== current.entry.ordinal) throw new Error('InferSettlementBindingMismatch');
    await persistSourceObservation();
    const proof = operation!.attemptEvidence(slot);
    for (const [kind, name] of [
      ['attempt', 'model_call_attempt'], ['accounting', 'model_attempt_accounting'],
      ['outcome', 'model_attempt_outcome'], ['authority', 'model_dispatch_authority'],
    ] as const) {
      await holdEvidence(name, slot, moon!.clientProgramInferAttemptLeaf(proof, kind), current.entry);
    }
    await holdAttachments(slot, current.entry);
    await holdEvidence('model_slot_capture', slot, operation!.issuedSlotCapture(slot), current.entry);
    const observation = operation!.invocationEvidenceView(control!, slot);
    if (observation !== undefined) {
      await hold('model_invocation_evidence', slot, observation.wire,
        observation.identity, current.entry);
    }
    current.exporter ??= checked(moon!.clientProgramStartInferCallSettlementExport(
      current.settlement, maximumStoredCaptureWire(), 1000000));
    while (!current.complete) {
      const progress = checked(moon!.clientProgramAdvanceInferCaptureExport(current.exporter, 256));
      current.wire += runtimeField(progress, 1) as string;
      current.complete = runtimeField(progress, 0) as boolean;
      if (!current.complete) await yieldEventLoop();
    }
    await hold('model_capture_bundle', slot, current.wire,
      moon!.clientProgramInferCaptureExportIdentity(current.exporter)!, current.entry);
    await faultInjection?.('infer_model_response_stored', {slot,
      scopeCid: current.entry.scopeCid, attemptCid: current.entry.attemptCid});
    if (typeof observeModelEntry !== 'function') throw new Error('InferSettlementObserverMissing');
    const observed = await observeModelEntry(current.entry);
    if (!['SavedSuccess', 'SavedFailure'].includes(observed?.state as string)) {
      throw new Error('InferSettlementNotDurable');
    }
    await faultInjection?.('infer_model_settlement_committed', {slot,
      scopeCid: current.entry.scopeCid, attemptCid: current.entry.attemptCid, state: observed!.state});
    if (!checked(moon!.clientProgramCleanupInferCaptureExport(current.exporter))) throw pending();
    operation!.acknowledgeSettlement(current.settlement);
    // Store observation alone is not this same Common settlement ACK.
    // Failed cleanup/ACK must keep the stopped-reader responsibility above.
    durableSettlements!.set(slot, current.entry.attemptCid);
    // Both original duties succeeded. Retire only this record's aliases even
    // if its completed async frame remains reachable; Store/Core originals
    // and a later terminal export retain their independent lifetimes.
    current.exporter = undefined;
    current.wire = '';
    settling = undefined;
    return observed!;
  }
  let modelEvidence: Evidence[] | undefined = [];
  let wire = '';
  let exportComplete = false;
  persistCapture = async (preparePublication = true) => {
    if (captureStored) return;
    if (!capturePersisted) {
      await persistSourceObservation();
      modelEvidence!.length = 0;
      for (let slot = 0; slot < count!; slot++) {
        if (captureOnly) {
          const entry = modelEntryFor?.(slot);
          if (entry === undefined || durableSettlements!.get(slot) !== entry.attemptCid) {
            throw new Error('InferSettlementNotDurable');
          }
        }
        // Replay already adopted verified slot records and their original
        // attempt proofs. It must not issue a new physical attempt or accounting.
        if (!replay && !captureOnly) {
          const proof = operation!.attemptEvidence(slot);
          for (const [kind, name] of [
            ['attempt', 'model_call_attempt'],
            ['accounting', 'model_attempt_accounting'],
            ['outcome', 'model_attempt_outcome'],
            ['authority', 'model_dispatch_authority'],
          ] as const) {
            await holdEvidence(name, slot,
              moon!.clientProgramInferAttemptLeaf(proof, kind));
          }
          await holdAttachments(slot);
          const adopted = operation!.issuedSlotCapture(slot);
          checked(moon!.clientProgramBindInferSlotCapture(capture, slot, adopted));
          await holdEvidence('model_slot_capture', slot, adopted);
        }
        const evidence = operation!.invocationEvidenceView(control!, slot);
        if (evidence !== undefined) {
          modelEvidence!.push(evidence);
        }
      }
      // captureOnly's whole bundle is not stored in this per-slot cell. Keep
      // its existing bound; do not mistake a different Store's extent for it.
      exporter ??= checked(moon!.clientProgramStartInferCaptureExport(capture,
        captureOnly ? 1048576 : maximumStoredCaptureWire(), 1000000));
      while (!exportComplete) {
        const progress = checked(moon!.clientProgramAdvanceInferCaptureExport(
          exporter, 256));
        wire += runtimeField(progress, 1) as string;
        if (runtimeField(progress, 0)) { exportComplete = true; break; }
        await yieldEventLoop();
      }
      if (captureOnly) {
        // Each original slot already reached scoped private Store custody at
        // Settling. Multiple components must not compete for the legacy single
        // whole-bundle cell. The complete Run issuer is retained by the parent.
        capturePersisted = true;
        captureStored = true;
        return;
      }
      await hold('model_capture_bundle', -1, wire,
        moon!.clientProgramInferCaptureExportIdentity(exporter)!);
      capturePersisted = true;
    }
    // A failed semantic projection cannot make first close reconstruct it.
    // Preserve the SAME accepted capture in Store, then release the existing
    // issuer/exporter/output owners. Any pending physical write remains owned
    // by pendingHolding below; no publication or Run success is fabricated.
    if (!preparePublication) return;
    if (publication === undefined) {
      // A persistence retry must keep the original issuer, its reservations
      // and progress, including completion before the publication binding.
      if (issuance === undefined) {
        issuance = operation!.startObservation({maxSlots: count!,
          maxWireBytes: 16384, maxWork: count! + 2});
      }
      while (!issuanceComplete) {
        issuanceComplete = runtimeField(checked(
          moon!.clientProgramAdvanceInferObservationIssuance(issuance, 1)), 0) as boolean;
        await faultInjection?.('infer_observation_advanced', {
          complete: issuanceComplete,
        });
        if (!issuanceComplete) await yieldEventLoop();
      }
      publication = await publicationFor!({operation: operation!, issuance, modelEvidence: modelEvidence!});
    }
    await hold('observation_set', -1, publication.observation.wire,
      publication.observation.identity);
    await hold('run_invocation', -1, publication.invocation.wire,
      publication.invocation.identity);
    captureStored = true;
  };
  return Object.freeze({custody, retainCompleted, persistStoppedAttempts,
    // Count of the actual retained completed capture, not a persistence proof
    // or publication grant. The same Core issuer verifies the complete slots.
    completedCallCount() {return capture !== undefined && !publicationCleaned && !reclaimed ? count : undefined;},
    completedInventoryReceipt() {return capture !== undefined && !publicationCleaned && !reclaimed ? captureInventory : undefined;},
    modelEvidence() {return !publicationRetired && !reclaimed && captureStored
      ? projectedModelEvidence ??= Object.freeze([...modelEvidence!]) : undefined;},
    usageInventory(current) {
      if (typeof current !== 'function') return undefined;
      current();
      if (!captureStored || !exportComplete || reclaimed || publicationCleaned ||
          fundedInferCaptureInventoryCount(captureInventory, operation) !== count) return undefined;
      current();
      if (typeof publicationFunding?.prepareOriginalUsage !== 'function') return undefined;
      publicationFunding.prepareOriginalUsage(operation!, capture, count!);
      current();
      const calls = [];
      for (let slot = 0; slot < count!; slot++) {
        const call = moon!.clientProgramInferCaptureCall(capture, slot);
        const outcome = moon!.clientProgramInferCaptureOutcome(capture, slot);
        if (call === undefined || outcome === undefined) return undefined;
        calls.push(Object.freeze({slotCid: moon!.strategyRunEvidenceIdentity(call), outcome}));
      }
      current();
      return Object.freeze({count: count!, calls: Object.freeze(calls),
        cid: moon!.clientProgramInferCaptureExportIdentity(exporter)});
    },
    beginUsage(maxBytes, current) {
      if (typeof current !== 'function') throw new Error('RequiredEvidenceUnavailable');
      current();
      if (!captureStored || !exportComplete || reclaimed || publicationCleaned ||
          fundedInferCaptureInventoryCount(captureInventory, operation) !== count ||
          typeof publicationFunding?.beginOriginalUsage !== 'function') {
        throw new Error('RequiredEvidenceUnavailable');
      }
      current();
      // Do not run another callback between issuance and handing the same
      // child to its consumer: refusal there could orphan a funded action.
      return publicationFunding.beginOriginalUsage(operation!, capture, count!, maxBytes);
    },
    // This immutable original is available only after the existing Store
    // commit. It conveys no read/capture permission and retains no new owner.
    evaluationBundle() {
      if (!captureStored || !exportComplete || reclaimed || publicationCleaned) return undefined;
      if (evaluation !== undefined) return evaluation;
      const funded = fundInferCaptureInventory(operation, publicationFunding);
      if (count! > 128 && fundedInferCaptureInventoryCount(funded, operation) !== count) return undefined;
      const calls = [];
      for (let slot = 0; slot < count!; slot++) {
        const call = moon!.clientProgramInferCaptureCall(capture, slot);
        const outcome = moon!.clientProgramInferCaptureOutcome(capture, slot);
        if (call === undefined || outcome === undefined) return undefined;
        calls.push(Object.freeze({slotCid: moon!.strategyRunEvidenceIdentity(call),
          callWire: moon!.strategyRunEvidenceJson(call), outcome}));
      }
      const usage = typeof moon!.clientProgramInferCaptureExportWireUsage === 'function'
        ? checked(moon!.clientProgramInferCaptureExportWireUsage(exporter)) : undefined;
      return evaluation = Object.freeze({wire, cid: moon!.clientProgramInferCaptureExportIdentity(exporter), count: count!,
        ...(usage === undefined ? {} : {usage}),
        calls: Object.freeze(calls)});
    },
    configureModelJournal({observe, entry}) {
      if (publicationCleaned || reclaimed || !durableCalls || typeof observe !== 'function' || observeModelEntry !== undefined) {
        throw new TypeError('InvalidInferModelJournal');
      }
      if (typeof entry !== 'function') throw new TypeError('InvalidInferModelEntryReader');
      observeModelEntry = observe;
      modelEntryFor = entry;
      operation!.installSettlementCleanup(async settlement => {
        if (publicationCleaned || reclaimed) throw new Error('ForeignInferSettlement');
        const receipt = entry(operation!.settlementSlot(settlement));
        if (receipt === undefined) throw new Error('InferSettlementEntryMissing');
        settling ??= {settlement, entry: receipt, wire: '', complete: false};
        return persistSettlement();
      });
    },
    async persistSettlement(settlement, entry) {
      if (publicationCleaned || reclaimed || !durableCalls || settling !== undefined &&
          (operation!.settlementSlot(settling.settlement) !== operation!.settlementSlot(settlement) ||
            settling.entry.attemptCid !== entry.attemptCid)) {
        throw new Error('ForeignInferSettlement');
      }
      settling ??= {settlement, entry, wire: '', complete: false};
      return persistSettlement();
    },
    async persist() {
      if (capture === undefined) throw new Error('InstalledInferCaptureUnavailable');
      await persistCapture();
      return publication;
    }});
}
