///|
priv enum ClientHostInitializationPhase {
  Open
  Selected
  Closed
} derive(Eq)

///|
/// The existing Host initialization retains this original before Source
/// loading. This is distinct from every per-Request parent: installation
/// material survives those Requests and is retired only by the Host close.
struct ClientHostInitializationPreparation[I] {
  initial : @resources.NodePreparationAdmission[I]
  capacity : @resources.PreparationCapacity[I, Unit]
  mut input : I?
  mut phase : ClientHostInitializationPhase
}

///|
pub(all) enum ClientHostInitializationIssue {
  ForeignOriginal
  WrongPhase
  Policy
  Initial(@resources.ImportedChildLedgerIssue)
  Capacity(@resources.PreparationCapacityIssue)
} derive(Debug)

///|
/// Open the actual original Node admission before the first Source constructor.
/// Fixed VM/control wrappers use the existing startup envelope. No variable
/// Source bytes are granted here: the selected domain adds its complete quote
/// to this same empty working reservation before allocating its material.
pub fn[I] begin_host_initialization_preparation(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  policy : ClientLocalResourcePolicy,
) -> Result[
  ClientHostInitializationPreparation[I],
  ClientHostInitializationIssue,
] {
  guard client_local_preparation_initial_limits(policy) is Some(expected) else {
    return Err(Policy)
  }
  match @resources.check_node_preparation_input(initial, input) {
    Err(issue) => return Err(Initial(issue))
    Ok(_) => ()
  }
  let ledger = match @resources.start_node_preparation_admission(initial) {
    Err(issue) => return Err(Initial(issue))
    Ok(value) => value
  }
  if @resources.ledger_limits(ledger) != expected {
    return Err(Policy)
  }
  let capacity : @resources.PreparationCapacity[I, Unit] = match
    @resources.reserve_preparation_capacity(
      ledger,
      input,
      0L,
      0L,
      // Counter representation bound, not policy, preallocated slots,
      // physical attempts or a grant for any material/Request.
      max_borrowers=2147483647,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  Ok({ initial, capacity, input: Some(input), phase: Open, })
}

///|
/// The fixed Source constructor takes this one original working capacity. It
/// selects its actual body type with the existing typed continuation and
/// retains that successor before any fallible allocation. No Ledger escapes
/// to JavaScript, and no completed Request or equal input can be substituted.
pub fn[I] take_host_initialization_preparation_capacity(
  owner : ClientHostInitializationPreparation[I],
) -> Result[
  (I, @resources.PreparationCapacity[I, Unit]),
  ClientHostInitializationIssue,
] {
  if owner.phase != Open {
    return Err(WrongPhase)
  }
  guard owner.input is Some(input) else { return Err(ForeignOriginal) }
  owner.phase = Selected
  Ok((input, owner.capacity))
}

///|
/// After selected Source material, Request borrows and physical children have
/// actually retired, close the SAME imported initial admission. A selected
/// live token, even at zero bytes, cannot be mistaken for an empty Host.
/// The Source owner must settle its original successor; this caller cannot
/// abort a Continued handle or acknowledge another owner's physical cleanup.
pub fn[I] close_host_initialization_preparation(
  owner : ClientHostInitializationPreparation[I],
) -> Result[Unit, ClientHostInitializationIssue] {
  if owner.phase == Closed {
    return Ok(())
  }
  if owner.phase == Open {
    guard owner.input is Some(input) else { return Err(ForeignOriginal) }
    match
      @resources.abort_preparation_capacity_after_cleanup(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(_) => ()
    }
    owner.phase = Selected
  }
  if !@resources.preparation_capacity_reservation_retired(owner.capacity) {
    return Err(WrongPhase)
  }
  match @resources.cleanup_node_preparation_admission(owner.initial) {
    Err(issue) => return Err(Initial(issue))
    Ok(_) => {
      owner.input = None
      owner.phase = Closed
      Ok(())
    }
  }
}
