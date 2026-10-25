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
struct PreparationPhaseWork {
  spend_original : (Int) -> Result[Unit, PreparationWorkIssue]
  finish_original : () -> Result[Int, PreparationWorkIssue]
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
    SemanticCheck => 9
    LowerAndGraph => 10
    ExecutionPlan => 11
    PublicationProof => 12
  }
}

///|
/// Only the fixed Common phase plan supplies maximum_work, from original-input
/// inspection/construction proof and applicable installed phase restrictions.
/// No Node caller receives a raw constructor with caller-selected quotas.
/// This is independent of Ledger.planning_work (dispatch work); it neither
/// debits nor resets that counter, and makes no aggregate CPU quota claim.
/// All receipt/closure/control allocations must be funded before this call.
pub fn[I, P] begin_preparation_phase_work(
  owner : PreparationCapacity[I, P],
  input : I,
  phase : PreparationWorkPhase,
  maximum_work : Int,
) -> Result[PreparationPhaseWork, PreparationWorkIssue] {
  if !(owner.input is Some(original) && physical_equal(original, input)) {
    return Err(ForeignOriginal)
  }
  if owner.phase != Working || owner.active_phase_work is Some(_) {
    return Err(WrongPhase)
  }
  if maximum_work < 0 {
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
  let remaining = Ref(maximum_work)
  owner.last_work_phase = ordinal
  owner.active_phase_work = Some(live)
  Ok({
    spend_original: amount => {
      if !live.val {
        return Err(Closed)
      }
      if owner.phase != Working {
        return Err(WrongPhase)
      }
      if owner.ledger.imported_child is Some(origin) && origin.stopping {
        return Err(Stopping)
      }
      if amount < 0 {
        return Err(InvalidWork)
      }
      if amount > remaining.val {
        return Err(WorkLimit)
      }
      remaining.val -= amount
      Ok(())
    },
    finish_original: () => {
      if !live.val {
        return Err(Closed)
      }
      if !(owner.active_phase_work is Some(active) &&
        physical_equal(active, live)) {
        return Err(ForeignOriginal)
      }
      live.val = false
      owner.active_phase_work = None
      Ok(maximum_work - remaining.val)
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
/// The fixed synchronous phase owner closes this only after its constructor
/// or failed constructor unwinds. Closing is not physical cancellation ACK,
/// memory release or permission to replay/refill the same named phase.
pub fn finish_preparation_phase_work(
  receipt : PreparationPhaseWork,
) -> Result[Int, PreparationWorkIssue] {
  (receipt.finish_original)()
}
