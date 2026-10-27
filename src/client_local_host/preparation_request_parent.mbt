///|
priv enum ClientRequestPreparationPhase {
  Open
  Selecting
  Selected
  Retiring
  Closed
} derive(Eq)

///|
/// Request bootstrap on the original Node preparation child, before an output
/// body type is selected. Unit is never completed or interpreted as a body.
/// This record owns no second Ledger, byte allowance, parser or serializer.
struct ClientRequestPreparation[I] {
  initial : @resources.NodePreparationAdmission[I]
  policy : ClientLocalResourcePolicy
  ledger : @resources.Ledger
  capacity : @resources.PreparationCapacity[I, Unit]
  mut input : I?
  mut phase : ClientRequestPreparationPhase
}

///|
pub(all) enum ClientRequestPreparationIssue {
  ForeignOriginal
  WrongPhase
  Policy
  Initial(@resources.ImportedChildLedgerIssue)
  Capacity(@resources.PreparationCapacityIssue)
} derive(Debug)

///|
/// Fixed controls only. No Values shape, source count, compiler body, wire,
/// parsed tree or provider inventory is included here. Each selected next
/// phase must reserve its own complete representation before constructing it.
fn request_preparation_control_units() -> @execution.PreparationRepresentationUnits {
  // JS producer/empty receipt/preparation state; original Resource record and
  // state; fixed quota6 and weak identity membership; ports and six closures.
  // The original runtime's fixed validation arrays have lengths4,6,3,7,5,5;
  // their slots borrow existing names/purpose or contain scalar counters.
  let js_headers = 3L * 2L +
    2L +
    1L +
    1L +
    1L +
    2L +
    2L +
    1L +
    6L +
    1L +
    2L * 6L +
    4L
  let js_refs = 1L +
    1L +
    3L * 3L +
    8L +
    6L +
    6L +
    1L +
    1L +
    4L +
    12L +
    2L +
    6L +
    4L +
    6L +
    1L
  let js_words = 1L + 1L + 5L + 2L + 6L + 2L * 6L + 3L + 7L + 2L * 5L
  // Original imported origin/child/admission/initial wrapper and eight fixed
  // closures. Ledger/limits/reservation/byte wrapper retain the same token;
  // old/new usage and zero quantity records coexist during initial reserve.
  let import_headers = 1L + 1L + 1L + 1L + 8L
  let import_refs = 7L + 8L + 7L + 1L + 9L
  let import_words = 4L + 3L + 4L + 1L
  let ledger_headers = 1L + 1L + 2L + 4L + 1L + 1L + 1L
  let ledger_refs = 7L + 3L + 5L + 1L
  let ledger_words = 4L + 6L + 20L + 9L + 6L + 3L
  // Capacity: six reference fields and four scalars. Parent: six references
  // and phase. Live Some/Result carriers conservatively cover eight headers,
  // eight references and eight tags. Original-current/resize scratch has
  // sixteen headers, thirty-two references and twenty-four scalar slots.
  {
    record_headers: js_headers + import_headers + ledger_headers + 2L + 8L + 16L,
    reference_slots: js_refs + import_refs + ledger_refs + 12L + 8L + 32L,
    scalar_words: js_words + import_words + ledger_words + 5L + 8L + 24L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// Fixed supplier precondition before JS per-request controls exist. This is
/// only a control quote under the original Local policy, not a body budget.
pub fn client_request_preparation_control_capacity(
  policy : ClientLocalResourcePolicy,
) -> (Int64, Int64)? {
  guard client_local_preparation_initial_limits(policy) is Some(limits) &&
    @execution.preparation_representation_cost(
      request_preparation_control_units(),
    )
    is Some(retained) else {
    return None
  }
  if retained > limits.retained_bytes {
    return None
  }
  Some((retained, 0L))
}

///|
pub fn[I] begin_request_preparation(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  policy : ClientLocalResourcePolicy,
) -> Result[ClientRequestPreparation[I], ClientRequestPreparationIssue] {
  guard client_local_preparation_initial_limits(policy) is Some(expected) &&
    client_request_preparation_control_capacity(policy)
    is Some((retained, execution)) else {
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
      retained,
      execution,
      max_borrowers=6,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  // The manager stores this original before any shape-specific constructor.
  Ok({ initial, policy, ledger, capacity, input: Some(input), phase: Open, })
}

///|
/// First concrete consumer. Select only the body type, retaining exactly the
/// original child, Ledger and reservation. The old bootstrap and new driver
/// coexist until the fixed JS caller stores the result and cuts its old link.
pub fn[I] select_closed_values_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  module_containers~ : @execution.PreparationRepresentationUnits,
) -> Result[ClientClosedValuesPreparation[I], ClientRequestPreparationIssue] {
  if owner.phase != Open {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  guard client_closed_values_initial_control_capacity(
      owner.policy,
      module_containers~,
    )
    is Some((retained, execution)) &&
    client_request_preparation_control_capacity(owner.policy)
    is Some((bootstrap, _)) &&
    retained <= 9223372036854775807L - bootstrap else {
    return Err(Policy)
  }
  owner.phase = Selecting
  let outcome = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    retained + bootstrap,
    execution,
  )
  match outcome {
    Err(issue) => {
      owner.phase = Open
      return Err(Capacity(issue))
    }
    Ok(_) => ()
  }
  let capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ] = match @resources.continue_preparation_capacity(owner.capacity, input) {
    Err(issue) => {
      owner.phase = Open
      return Err(Capacity(issue))
    }
    Ok(value) => value
  }
  owner.phase = Selected
  owner.input = None
  Ok(
    make_closed_values_preparation(
      owner.initial,
      input,
      owner.policy,
      capacity,
      retained + bootstrap,
      execution,
      module_containers,
    ),
  )
}

///|
/// Only after this fixed callback's construction/snapshot aliases unwound.
/// Pending original report/stop remains on this same admission; a later callback
/// cannot replace its original unknown outcome with an acknowledgement.
/// A selected stale bootstrap cannot settle its successor's shared token.
pub fn[I] abort_request_preparation_after_cleanup(
  owner : ClientRequestPreparation[I],
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.phase == Selected || owner.phase == Selecting {
    return Err(WrongPhase)
  }
  if owner.phase == Closed {
    return Ok(())
  }
  let retiring = owner.phase == Retiring
  owner.phase = Retiring
  let stopped = if retiring {
    @resources.retire_preparation_capacity(owner.capacity)
  } else {
    guard owner.input is Some(input) else { return Err(ForeignOriginal) }
    @resources.abort_preparation_capacity_after_cleanup(owner.capacity, input)
  }
  match stopped {
    Err(issue) => return Err(Capacity(issue))
    Ok(false) => return Err(WrongPhase)
    Ok(true) => owner.input = None
  }
  match @resources.cleanup_node_preparation_admission(owner.initial) {
    Err(issue) => Err(Initial(issue))
    Ok(_) => {
      owner.phase = Closed
      Ok(())
    }
  }
}

///|
/// Both entrances install the same body-specific driver. The request-parent
/// entrance reserves its complete old/new control overlap before this call.
fn[I] make_closed_values_preparation(
  initial : @resources.NodePreparationAdmission[I],
  input : I,
  policy : ClientLocalResourcePolicy,
  capacity : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ],
  retained : Int64,
  execution : Int64,
  module_containers : @execution.PreparationRepresentationUnits,
) -> ClientClosedValuesPreparation[I] {
  let value : ClientClosedValuesPreparation[I] = {
    original: None,
    input: Some(input),
    initial,
    policy,
    module_containers,
    capacity,
    work: None,
    header_fields: 0,
    header_rows: 0,
    retiring: false,
    module_constructing: false,
    text_checked: false,
    scan_complete: false,
    document: None,
    parsed: None,
    program: None,
    prepared: None,
    shape: None,
    lexical: None,
    envelope: None,
    retained_quote: retained,
    execution_quote: execution,
    source_free: None,
    compilation: None,
    body_ready: false,
    manager_issued: false,
    adopted: false,
    adopted_run: None,
    submitted_intent: None,
    manager_original: None,
    publication: None,
    publication_started: false,
    publication_invocation_started: false,
    publication_definition: None,
    publication_invocation: None,
  }
  value.original = Some(value)
  value
}
