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
  SemanticCheck
  LowerAndGraph
  ExecutionPlan
  PublicationProof
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
  scalar_words: 18L,
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
priv struct PreparationPhaseWorkState[I, P] {
  owner : PreparationCapacity[I, P]
  live : Ref[Bool]
  maximum : Int64
  mut remaining : Int64
}

///|
fn preparation_work_ordinal(phase : PreparationWorkPhase) -> Int {
  match phase {
    HeaderInspection => 0
    OwnDataScan => 1
    TextEligibility => 2
    SnapshotSerialization => 3
    LexicalScan => 4
    IntentIdentity => 5
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
    SemanticCheck => 43
    LowerAndGraph => 44
    ExecutionPlan => 45
    PublicationProof => 46
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
  let live = Ref(true)
  owner.last_work_phase = ordinal
  owner.active_phase_work = Some(live)
  Ok({ owner, live, maximum, remaining: maximum, })
}

///|
fn[I, P] spend_preparation_work_state(
  state : PreparationPhaseWorkState[I, P],
  amount : Int64,
) -> Result[Unit, PreparationWorkIssue] {
  if !state.live.val {
    return Err(Closed)
  }
  if !preparation_capacity_phase_is_working(state.owner.phase) {
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
  if !state.live.val {
    return Err(Closed)
  }
  if !(state.owner.active_phase_work is Some(active) &&
    physical_equal(active, state.live)) {
    return Err(ForeignOriginal)
  }
  state.live.val = false
  state.owner.active_phase_work = None
  Ok(state.maximum - state.remaining)
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
