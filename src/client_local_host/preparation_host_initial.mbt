///|
priv enum ClientHostInitializationPhase {
  Open
  Selected
  Closed
} derive(Eq)

///|
// Backend acquisition/physical retirement stay with their original issuers.
// The input, working body, selection and close fence below are shared.
priv enum ClientHostInitializationOriginal[I] {
  NodeInitial(@resources.NodePreparationAdmission[I])
  BackedInitial(@resources.BackedInitializationAdmission[I])
}

///|
/// The existing Host initialization retains this original before Source
/// loading. This is distinct from every per-Request parent: installation
/// material survives those Requests and is retired only by the Host close.
struct ClientHostInitializationPreparation[I] {
  initial : ClientHostInitializationOriginal[I]
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
  begin_host_initialization_preparation_original(
    NodeInitial(initial),
    input,
    policy,
  )
}

///|
/// Native assembly selects a fresh preparation-purpose original and installs
/// its actual bootstrap census BEFORE this call. A Read cannot be converted.
/// The original Native issuer retains the frame and actual physical cleanup;
/// neither a raw Ledger/input pair nor caller cleanup callbacks enter here.
pub fn[I] begin_backed_host_initialization_preparation(
  initial : @resources.BackedInitializationAdmission[I],
  input : I,
  policy : ClientLocalResourcePolicy,
) -> Result[
  ClientHostInitializationPreparation[I],
  ClientHostInitializationIssue,
] {
  begin_host_initialization_preparation_original(
    BackedInitial(initial),
    input,
    policy,
  )
}

///|
fn[I] begin_host_initialization_preparation_original(
  initial : ClientHostInitializationOriginal[I],
  input : I,
  policy : ClientLocalResourcePolicy,
) -> Result[
  ClientHostInitializationPreparation[I],
  ClientHostInitializationIssue,
] {
  guard client_local_preparation_initial_limits(policy) is Some(expected) else {
    return Err(Policy)
  }
  let checked = match initial {
    NodeInitial(value) => @resources.check_node_preparation_input(value, input)
    BackedInitial(value) =>
      @resources.check_backed_initialization_input(value, input)
  }
  match checked {
    Err(issue) => return Err(Initial(issue))
    Ok(_) => ()
  }
  let started = match initial {
    NodeInitial(value) => @resources.start_node_preparation_admission(value)
    BackedInitial(value) =>
      @resources.take_backed_initialization_admission(value, input)
  }
  let ledger = match started {
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
/// Backed cleanup stays pending until the original Native issuer has observed
/// its actual C-context/report/after-owner-ACK retirement in its own order.
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
  let cleanup = match owner.initial {
    NodeInitial(value) => @resources.cleanup_node_preparation_admission(value)
    BackedInitial(value) =>
      @resources.cleanup_backed_initialization_admission(value)
  }
  match cleanup {
    Err(issue) => return Err(Initial(issue))
    Ok(_) => {
      owner.input = None
      owner.phase = Closed
      Ok(())
    }
  }
}
