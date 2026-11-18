///|
/// Named constructor phases of one preparation, not session issuance counts.
/// Repeated cells/fields belong to one phase's proof-derived work envelope.
pub(all) enum PreparationWorkPhase {
  HeaderInspection
  OwnDataScan
  TextEligibility
  SnapshotSerialization
  LexicalScan
  IntentIdentity
  SourceAndIndex
  ShapeInspection
  ProgramStructure
  ParameterDeclarationInventory
  ParameterDeclarationBodyInventory
  ParameterSourceConstruction
  ParameterBindingHeaderInventory
  ParameterBindingBodyInventory
  CapacityInputInspection
  CapacityInputRecheck
  CapacityInputBinding
  SemanticPrelude
  CatalogInspection
  CatalogAdmission
  CatalogContentsInspection
  CatalogContentsAdmission
  CatalogReferencesInspection
  CatalogReferencesAdmission
  CatalogPoliciesInspection
  CatalogPoliciesAdmission
  CatalogValuesInspection
  CatalogValuesAdmission
  CatalogViewsInspection
  CatalogViewsAdmission
  CatalogCarriersInspection
  CatalogCarriersAdmission
  CatalogRequestsInspection
  CatalogRequestsAdmission
  SourceCollectionInspection
  SourceCollection
  SourceResolutionInspection
  SourceSelection
  SourcePipelineRegistration
  SourceLocalEntry
  SourceLocalIndexInspection
  SourceLocalIndex
  SourceLocalGroups
  SourceLocalSnapshotReferenceInspection
  SourceLocalSnapshotBodyInspection
  SourceLocalSnapshotBody
  SourceLocalTailInspection
  SourceLocalTailBody
  SourceContextInputInspection
  SourceContextInputBody
  SourceTopologyEntry
  SourceTopologyBody
  SemanticCheck
  LowerAndGraph
  ExecutionPlan
  PublicationProof
  // Appended to preserve existing constructor tags; execution ordering is below.
  RequestValuePolicyCheck
  RequestPolicySubjectPreparation
  HttpInputPreflight
  NormalizationAudit
  AuthoringContext
} derive(Eq, Debug)

///|
pub(all) enum PreparationWorkIssue {
  ForeignOriginal
  WrongPhase
  AlreadyClaimed
  Closed
  InvalidWork
  WorkLimit
  Stopping
} derive(Eq, Debug)

///|
/// Same narrow/wide phase-work construction envelope: original state/live
/// cell, two original closures, receipt, active Some and returned carriers.
/// This is constructor DATA, not work credit, a tariff or a Resource Owner.
pub(all) struct PreparationWorkConstructionInventory {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
let preparation_work_construction : PreparationWorkConstructionInventory = {
  record_headers: 12L,
  reference_slots: 16L,
  scalar_words: 19L,
}

///|
pub fn preparation_phase_work_construction_inventory() -> PreparationWorkConstructionInventory {
  preparation_work_construction
}

///|
struct PreparationPhaseWork {
  spend_original : (Int) -> Result[Unit, PreparationWorkIssue]
  finish_original : () -> Result[Int, PreparationWorkIssue]
}

///|
/// Same fixed Common phase work, not dispatch/session quota. Callers select
/// the phase and a checked construction-derived bound; input DATA is no grant.
/// Same original phase meter with explicit wide DATA quantities. This distinct
/// receipt cannot be passed to the unchanged public Int-only consumer.
struct PreparationPhaseWork64 {
  spend_original : (Int64) -> Result[Unit, PreparationWorkIssue]
  finish_original : () -> Result[Int64, PreparationWorkIssue]
}

///|
/// One original phase meter for staged constructors. This is an alternative
/// receipt, not a wrapper issuing a second receipt or another work allowance.
struct PreparationPhaseWorkContinuation64 {
  ledger_original : Ledger
  spend_original : (Int64) -> Result[Unit, PreparationWorkIssue]
  finish_original : () -> Result[Int64, PreparationWorkIssue]
  return_original : () -> Result[Unit, PreparationWorkIssue]
  resume_original : () -> Result[Unit, PreparationWorkIssue]
  remaining_original : () -> Result[Int64, PreparationWorkIssue]
}

///|
priv enum PreparationWorkState {
  Executing
  Returned
  Closed
} derive(Eq)

///|
priv struct PreparationPhaseWorkState[I, P] {
  owner : PreparationCapacity[I, P]
  live : Ref[PreparationWorkState]
  maximum : Int64
  run : Bool
  mut remaining : Int64
}

///|
// Shared fresh-state sentinel; optional raw HTTP work precedes Header0.
let preparation_work_unclaimed : Int = -2

///|
fn preparation_work_ordinal(phase : PreparationWorkPhase) -> Int {
  match phase {
    HttpInputPreflight => -1
    HeaderInspection => 0
    OwnDataScan => 1
    TextEligibility => 2
    SnapshotSerialization => 3
    // The ordinary SDK finishes its original intent before compiling SQL/Pipe.
    // Enum declaration order is not the execution order of this private fence.
    IntentIdentity => 4
    LexicalScan => 5
    SourceAndIndex => 6
    ShapeInspection => 7
    ProgramStructure => 8
    ParameterDeclarationInventory => 9
    ParameterDeclarationBodyInventory => 10
    ParameterSourceConstruction => 11
    ParameterBindingHeaderInventory => 12
    ParameterBindingBodyInventory => 13
    CapacityInputInspection => 14
    CapacityInputRecheck => 15
    CapacityInputBinding => 16
    SemanticPrelude => 17
    CatalogInspection => 18
    CatalogAdmission => 19
    CatalogContentsInspection => 20
    CatalogContentsAdmission => 21
    CatalogReferencesInspection => 22
    CatalogReferencesAdmission => 23
    CatalogPoliciesInspection => 24
    CatalogPoliciesAdmission => 25
    CatalogValuesInspection => 26
    CatalogValuesAdmission => 27
    CatalogViewsInspection => 28
    CatalogViewsAdmission => 29
    CatalogCarriersInspection => 30
    CatalogCarriersAdmission => 31
    CatalogRequestsInspection => 32
    CatalogRequestsAdmission => 33
    SourceCollectionInspection => 34
    SourceCollection => 35
    SourceResolutionInspection => 36
    SourceSelection => 37
    SourcePipelineRegistration => 38
    SourceLocalEntry => 39
    SourceLocalIndexInspection => 40
    SourceLocalIndex => 41
    SourceLocalGroups => 42
    SourceLocalSnapshotReferenceInspection => 43
    SourceLocalSnapshotBodyInspection => 44
    SourceLocalSnapshotBody => 45
    SourceLocalTailInspection => 46
    SourceLocalTailBody => 47
    SourceContextInputInspection => 48
    SourceContextInputBody => 49
    SourceTopologyEntry => 50
    SourceTopologyBody => 51
    SemanticCheck => 52
    RequestPolicySubjectPreparation => 53
    RequestValuePolicyCheck => 54
    LowerAndGraph => 55
    // This private fence is not a constructor/ABI tag or serialized counter.
    // Normalization belongs to the same Prepared before Plan construction.
    NormalizationAudit => 56
    AuthoringContext => 57
    ExecutionPlan => 58
    PublicationProof => 59
  }
}

///|
// Sole admission rule for narrow/wide receipts. The original input, phase,
// active cell and stopping checks are unchanged; no callback or grant is added.
fn[I, P] begin_preparation_work_state(
  owner : PreparationCapacity[I, P],
  input : I,
  phase : PreparationWorkPhase,
  maximum : Int64,
) -> Result[PreparationPhaseWorkState[I, P], PreparationWorkIssue] {
  if !(owner.input is Some(original) && physical_equal(original, input)) {
    return Err(ForeignOriginal)
  }
  if !preparation_capacity_phase_is_working(owner.phase) ||
    owner.active_phase_work is Some(_) {
    return Err(WrongPhase)
  }
  if maximum < 0L {
    return Err(InvalidWork)
  }
  let ordinal = preparation_work_ordinal(phase)
  if ordinal <= owner.last_work_phase {
    return Err(AlreadyClaimed)
  }
  if owner.ledger.imported_child is Some(origin) && origin.stopping {
    return Err(Stopping)
  }
  let live = Ref(PreparationWorkState::Executing)
  owner.last_work_phase = ordinal
  owner.active_phase_work = Some(live)
  Ok({ owner, live, maximum, run: false, remaining: maximum, })
}

///|
fn[I, P] spend_preparation_work_state(
  state : PreparationPhaseWorkState[I, P],
  amount : Int64,
) -> Result[Unit, PreparationWorkIssue] {
  if state.live.val == Closed {
    return Err(Closed)
  }
  if state.live.val != Executing {
    return Err(WrongPhase)
  }
  if !(if state.run {
      state.owner.phase == Run && !state.owner.inventory_growth_active
    } else {
      preparation_capacity_phase_is_working(state.owner.phase)
    }) {
    return Err(WrongPhase)
  }
  if state.owner.ledger.imported_child is Some(origin) && origin.stopping {
    return Err(Stopping)
  }
  if amount < 0L {
    return Err(InvalidWork)
  }
  if amount > state.remaining {
    return Err(WorkLimit)
  }
  state.remaining -= amount
  Ok(())
}

///|
fn[I, P] finish_preparation_work_state(
  state : PreparationPhaseWorkState[I, P],
) -> Result[Int64, PreparationWorkIssue] {
  if state.live.val == Closed {
    return Err(Closed)
  }
  if !(state.owner.active_phase_work is Some(active) &&
    physical_equal(active, state.live)) {
    return Err(ForeignOriginal)
  }
  // A returned receipt can span a resize, whose original current callback may
  // reenter. Finishing inside that callback must not sever the live phase.
  if state.run &&
    (state.owner.phase != Run || state.owner.inventory_growth_active) {
    return Err(WrongPhase)
  }
  if state.owner.phase == Completing ||
    state.owner.phase == Transferring ||
    state.owner.phase == Settling {
    return Err(WrongPhase)
  }
  state.live.val = Closed
  state.owner.active_phase_work = None
  Ok(state.maximum - state.remaining)
}

///|
fn[I, P] return_preparation_work_state(
  state : PreparationPhaseWorkState[I, P],
) -> Result[Unit, PreparationWorkIssue] {
  if state.live.val == Closed {
    return Err(Closed)
  }
  if state.live.val != Executing ||
    !(if state.run {
      state.owner.phase == Run && !state.owner.inventory_growth_active
    } else {
      preparation_capacity_phase_is_working(state.owner.phase)
    }) ||
    !(state.owner.active_phase_work is Some(active) &&
    physical_equal(active, state.live)) {
    return Err(WrongPhase)
  }
  state.live.val = Returned
  Ok(())
}

///|
fn[I, P] resume_preparation_work_state(
  state : PreparationPhaseWorkState[I, P],
) -> Result[Unit, PreparationWorkIssue] {
  if state.live.val == Closed {
    return Err(Closed)
  }
  if state.live.val != Returned ||
    !(if state.run {
      state.owner.phase == Run && !state.owner.inventory_growth_active
    } else {
      preparation_capacity_phase_is_working(state.owner.phase)
    }) ||
    !(state.owner.active_phase_work is Some(active) &&
    physical_equal(active, state.live)) {
    return Err(WrongPhase)
  }
  if state.owner.ledger.imported_child is Some(origin) && origin.stopping {
    return Err(Stopping)
  }
  state.live.val = Executing
  Ok(())
}

///|
/// Existing public Int contract. The shared state never receives a larger
/// maximum through this constructor; its exact finished usage fits Int.
pub fn[I, P] begin_preparation_phase_work(
  owner : PreparationCapacity[I, P],
  input : I,
  phase : PreparationWorkPhase,
  maximum_work : Int,
) -> Result[PreparationPhaseWork, PreparationWorkIssue] {
  let state = match
    begin_preparation_work_state(owner, input, phase, maximum_work.to_int64()) {
    Err(issue) => return Err(issue)
    Ok(state) => state
  }
  Ok({
    spend_original: amount => {
      spend_preparation_work_state(state, amount.to_int64())
    },
    finish_original: () => {
      match finish_preparation_work_state(state) {
        Err(issue) => Err(issue)
        Ok(value) => Ok(value.to_int())
      }
    },
  })
}

///|
pub fn spend_preparation_phase_work(
  receipt : PreparationPhaseWork,
  amount : Int,
) -> Result[Unit, PreparationWorkIssue] {
  (receipt.spend_original)(amount)
}

///|
/// Close only after the original synchronous constructor has unwound. This
/// reports work, never physical stop, freed backing or a refill allowance.
pub fn finish_preparation_phase_work(
  receipt : PreparationPhaseWork,
) -> Result[Int, PreparationWorkIssue] {
  (receipt.finish_original)()
}

///|
pub fn[I, P] begin_preparation_phase_work64(
  owner : PreparationCapacity[I, P],
  input : I,
  phase : PreparationWorkPhase,
  maximum_work : Int64,
) -> Result[PreparationPhaseWork64, PreparationWorkIssue] {
  let state = match
    begin_preparation_work_state(owner, input, phase, maximum_work) {
    Err(issue) => return Err(issue)
    Ok(state) => state
  }
  Ok({
    spend_original: amount => spend_preparation_work_state(state, amount),
    finish_original: () => finish_preparation_work_state(state),
  })
}

///|
pub fn spend_preparation_phase_work64(
  receipt : PreparationPhaseWork64,
  amount : Int64,
) -> Result[Unit, PreparationWorkIssue] {
  (receipt.spend_original)(amount)
}

///|
pub fn finish_preparation_phase_work64(
  receipt : PreparationPhaseWork64,
) -> Result[Int64, PreparationWorkIssue] {
  (receipt.finish_original)()
}

///|
/// Only the fixed synchronous constructor driver calls this AFTER the current
/// constructor has returned. It retains the same maximum, spent work and phase
/// ordinal. It does not close/refill work or acknowledge physical cleanup.
pub fn return_preparation_phase_work_continuation64(
  receipt : PreparationPhaseWorkContinuation64,
) -> Result[Unit, PreparationWorkIssue] {
  (receipt.return_original)()
}

///|
/// Resume the SAME original receipt after backing the next constructor. This
/// performs no external current callback; actual resize/current boundaries
/// retain their original checks. Returning a receipt never authorizes transfer.
pub fn resume_preparation_phase_work_continuation64(
  receipt : PreparationPhaseWorkContinuation64,
) -> Result[Unit, PreparationWorkIssue] {
  (receipt.resume_original)()
}

///|
/// Staged receipt adds three original closures3H3R and three receipt fields3R.
/// The same state/status cell remains one scalar word. Ordinary narrow/wide
/// receipts retain their exact original fields and constructor inventory.
pub fn preparation_phase_work_continuation64_construction_inventory() -> PreparationWorkConstructionInventory {
  {
    record_headers: preparation_work_construction.record_headers + 3L,
    reference_slots: preparation_work_construction.reference_slots + 7L,
    scalar_words: preparation_work_construction.scalar_words,
  }
}

///|
/// Claim the existing original work state once. The caller backs this exact
/// receipt before entry and uses it across returned constructor boundaries.
pub fn[I, P] begin_preparation_phase_work_continuation64(
  owner : PreparationCapacity[I, P],
  input : I,
  phase : PreparationWorkPhase,
  maximum_work : Int64,
) -> Result[PreparationPhaseWorkContinuation64, PreparationWorkIssue] {
  let state = match
    begin_preparation_work_state(owner, input, phase, maximum_work) {
    Err(issue) => return Err(issue)
    Ok(state) => state
  }
  Ok({
    ledger_original: owner.ledger,
    spend_original: amount => spend_preparation_work_state(state, amount),
    finish_original: () => finish_preparation_work_state(state),
    return_original: () => return_preparation_work_state(state),
    resume_original: () => resume_preparation_work_state(state),
    remaining_original: () => {
      spend_preparation_work_state(state, 0L).map(_ => state.remaining)
    },
  })
}

///|
pub fn spend_preparation_phase_work_continuation64(
  receipt : PreparationPhaseWorkContinuation64,
  amount : Int64,
) -> Result[Unit, PreparationWorkIssue] {
  (receipt.spend_original)(amount)
}

///|
/// Borrow the SAME executing phase's remaining amount without consuming or
/// refilling it. Returned, closed, stopping and wrong-phase receipts retain
/// their existing refusal, before another bounded constructor can advance.
pub fn remaining_preparation_phase_work_continuation64(
  receipt : PreparationPhaseWorkContinuation64,
) -> Result[Int64, PreparationWorkIssue] {
  (receipt.remaining_original)()
}

///|
/// Finish the SAME total once, including cleanup of a returned constructor.
pub fn finish_preparation_phase_work_continuation64(
  receipt : PreparationPhaseWorkContinuation64,
) -> Result[Int64, PreparationWorkIssue] {
  (receipt.finish_original)()
}

///|
/// Live portion of the SAME staged receipt: state1H2R2W, live Ref1H1W,
/// five original state closures5H5R, receipt1H6R and active Some1H1R1W.
/// Construction-return/argument carriers have unwound before reconciliation.
/// The caller's own receipt Some stays with that caller's control inventory.
pub fn preparation_phase_work_continuation64_retained_inventory() -> PreparationWorkConstructionInventory {
  { record_headers: 9L, reference_slots: 14L, scalar_words: 5L, }
}

///|
// Run adoption is an explicit alternative, never a change to Working phase
// eligibility. Only PublicationProof may claim this same original active cell.
fn[I, P] begin_run_publication_work_continuation64(
  owner : PreparationCapacity[I, P],
  body : P,
  ledger : Ledger,
  maximum : Int64,
) -> Result[PreparationPhaseWorkContinuation64, PreparationWorkIssue] {
  if !physical_equal(owner.ledger, ledger) ||
    owner.input is None ||
    !(owner.body is Some(original) && physical_equal(original, body)) {
    return Err(ForeignOriginal)
  }
  if owner.phase != Run ||
    owner.active_phase_work is Some(_) ||
    !owner.reservation.reservation.open ||
    owner.inventory_growth_active {
    return Err(WrongPhase)
  }
  if maximum < 0L {
    return Err(InvalidWork)
  }
  let ordinal = preparation_work_ordinal(PublicationProof)
  if ordinal <= owner.last_work_phase {
    return Err(AlreadyClaimed)
  }
  if (ledger.imported_child is Some(origin) && origin.stopping) ||
    (ledger.original_inventory is Some(inventory) && inventory.closing) {
    return Err(Stopping)
  }
  if reservation_check_current(ledger, owner.reservation.reservation) is Err(_) {
    return Err(ForeignOriginal)
  }
  let live = Ref(PreparationWorkState::Executing)
  owner.last_work_phase = ordinal
  owner.active_phase_work = Some(live)
  let state : PreparationPhaseWorkState[I, P] = {
    owner,
    live,
    maximum,
    run: true,
    remaining: maximum,
  }
  Ok({
    ledger_original: ledger,
    spend_original: amount => spend_preparation_work_state(state, amount),
    finish_original: () => finish_preparation_work_state(state),
    return_original: () => return_preparation_work_state(state),
    resume_original: () => resume_preparation_work_state(state),
    remaining_original: () => {
      spend_preparation_work_state(state, 0L).map(_ => state.remaining)
    },
  })
}

///|
// Only this adopted PublicationProof continuation may be parked around an
// existing Run resize. No Working receipt or executing cursor is eligible.
fn[I, P] preparation_run_publication_work_returned(
  owner : PreparationCapacity[I, P],
) -> Bool {
  owner.phase == Run &&
  owner.last_work_phase == preparation_work_ordinal(PublicationProof) &&
  owner.active_phase_work is Some(active) &&
  active.val == Returned
}
