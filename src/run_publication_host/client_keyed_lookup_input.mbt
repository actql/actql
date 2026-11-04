///|
/// Bounded assembly owned by the original captured-left use site. Per-key
/// RowRuns still own their physical readers and holdings. This continuation
/// borrows them into the ordinary Relation input buffer; it creates neither
/// a second acquisition ledger nor a Direct query receipt.
struct ClientKeyedLookupInput {
  left : ClientKeyedLeftRead
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  max_bytes : Int
  max_work : Int
  retained_bytes : Int64
  rows : Int
  mut input : @execution.AdmittedInput?
  mut known : Array[(String, @execution.SuppliedRelationRead?)]
  mut accepted : Int
  mut work : Int
  mut retired_row_work : Int64
  mut copying : @execution.AdmittedOutputRowCursor?
  mut preparation : ClientKeyedRequestPreparation?
  mut preparation_work : Int
  mut pending_key : String?
  mut pending_read : @execution.SuppliedRelationRead?
  mut selected_request : ClientKeyedRequest?
  mut selected_key : String?
  mut selected_index : Int?
  mut completed : @execution.CapturedRows?
  mut read : @execution.SuppliedRelationRead?
  mut holding : @resources.Holding?
  mut identity : String?
  mut closed : Bool
}

///|
fn keyed_lookup_layout_capacity(
  rows : Int64,
  max_bytes : Int,
  max_work : Int,
) -> (Int64, Int64)? {
  if rows < 0L || rows > 2147483647L || max_bytes < 1 || max_work < 1 {
    return None
  }
  let base = max_bytes.to_int64() * 8L + rows * 64L + 4096L
  let per_key = max_bytes.to_int64() * 2L
  if rows > (9223372036854775807L - base) / per_key {
    return None
  }
  Some(
    (
      base + rows * per_key,
      max_work.to_int64() * 32L + max_bytes.to_int64() * 8L + 4096L,
    ),
  )
}

///|
/// Declaration-derived ceilings before the Direct Source is opened. Repeated
/// left rows still occupy assembly slots; the request bound does not collapse
/// input occurrences into distinct logical dependencies.
pub fn client_keyed_lookup_capacity(
  acquisition : ClientKeyedAcquisition,
  max_bytes : Int,
  max_work : Int,
) -> (Int64, Int64, Int64, Int64)? {
  guard @acquisition.lookup_bounds_at(
      acquisition.binding.bounds,
      acquisition.binding.index,
    )
    is Some(counts) &&
    counts.distinct_keys >= 0L &&
    counts.distinct_keys <= counts.input_rows &&
    keyed_lookup_layout_capacity(counts.input_rows, max_bytes, max_work)
    is Some((retained, execution)) else {
    return None
  }
  // Requests includes page/network ceilings. Physical RowRun holdings are
  // per complete key, while all left occurrences remain in the assembly.
  Some((counts.input_rows, counts.distinct_keys, retained, execution))
}

///|
pub fn start_client_keyed_lookup_input(
  left : ClientKeyedLeftRead,
  ledger : @resources.Ledger,
  max_bytes : Int,
  max_work : Int,
) -> Result[ClientKeyedLookupInput, ClientKeyedRequestIssue] {
  start_client_keyed_lookup_input_owned(left, ledger, max_bytes, max_work, None)
}

///|
// Original initialization adds only the existing opaque census prerequisite.
// Recheck it after producer liveness/count callbacks and before allocating the
// admitted input. No caller Bool, replacement Ledger or permanent field.
fn start_client_keyed_lookup_input_owned(
  left : ClientKeyedLeftRead,
  ledger : @resources.Ledger,
  max_bytes : Int,
  max_work : Int,
  original : @resources.OriginalLedgerIdentity?,
  prefix? : @resources.Reservation? = None,
) -> Result[ClientKeyedLookupInput, ClientKeyedRequestIssue] {
  if max_bytes < 1 ||
    max_work < 1 ||
    left.assembly_started ||
    left.lookup_issue is Some(_) ||
    !@execution.producer_read_available(left.read) {
    return Err(Assembly("unavailable"))
  }
  let rows = @execution.producer_read_row_count(left.read)
  if original is Some(identity) &&
    !@resources.original_ledger_captured_preparation_available(
      identity,
      prefix~,
    ) {
    return Err(Assembly("original_custody_changed"))
  }
  // The original completed producer supplies the actual assembly length.
  // A present checked bound still constrains it; an absent estimate neither
  // invents a count nor requires a second acquisition of the same Source.
  if @acquisition.lookup_bounds_at(
      left.acquisition.binding.bounds,
      left.acquisition.binding.index,
    )
    is Some(counts) &&
    rows.to_int64() > counts.input_rows {
    return Err(Assembly("input_rows"))
  }
  guard keyed_lookup_layout_capacity(rows.to_int64(), max_bytes, max_work)
    is Some((retained_bytes, execution_bytes)) else {
    return Err(Assembly("capacity_overflow"))
  }
  let owner = left.acquisition.owner
  let index = @acquisition.keyed_join_input(left.acquisition.binding.join)
  // Admit the existing layout/workspace envelope before materializing the
  // input buffer. The original per-key holdings are independent live owners.
  let reserve = match
    @resources.reserve_attempt(ledger, 0L, retained_bytes, execution_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let input = match
    @execution.prepare_bounded_admitted_input(owner, index, rows, {
      max_work,
      max_nodes: max_work,
      max_depth: 100,
      max_text_bytes: max_bytes,
    }) {
    Ok(value) => value
    Err(issue) => {
      // Failed preparation has no escaped input or physical reader. Retire
      // this exact attempt, without refunding its spent attempt identity.
      @resources.settle_reservation(ledger, reserve) |> ignore
      return Err(InputCapture(issue))
    }
  }
  if !@execution.charge_admitted_input_external_work(input, 1) {
    @execution.cancel_admitted_input(input) |> ignore
    @resources.settle_reservation(ledger, reserve) |> ignore
    return Err(LookupLimit("work"))
  }
  left.assembly_started = true
  Ok({
    left,
    ledger,
    reservation: reserve,
    max_bytes,
    max_work,
    retained_bytes,
    rows,
    input: Some(input),
    known: [],
    accepted: 0,
    work: 1,
    retired_row_work: 0L,
    copying: None,
    preparation: None,
    preparation_work: 0,
    pending_key: None,
    pending_read: None,
    selected_request: None,
    selected_key: None,
    selected_index: None,
    completed: None,
    read: None,
    holding: None,
    identity: None,
    closed: false,
  })
}

///|
fn charge_keyed_lookup_input_work(
  state : ClientKeyedLookupInput,
  units : Int,
) -> Bool {
  guard state.input is Some(input) &&
    @execution.charge_admitted_input_external_work(input, units) else {
    keyed_lookup_fail(state.left, LookupLimit("work")) |> ignore
    return false
  }
  state.work += units
  true
}

///|
/// A physical verification scan consumes one logical unit per examined byte,
/// under this same original lookup allowance. The installed Host calls this
/// before bounded checksum chunks; neither bytes transferred nor rereading a
/// counter implies billing permission. No foreign/reused/completed Request can
/// charge or renew this allowance, and cleanup never refunds its consumed work.
pub fn charge_client_keyed_lookup_verification(
  state : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
  bytes : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard !state.closed &&
    state.completed is None &&
    state.copying is None &&
    state.preparation is None &&
    state.selected_request is Some(selected) &&
    physical_equal(selected, request) &&
    physical_equal(request.left, state.left) &&
    state.selected_index is Some(-1) &&
    request.attempts > 0L &&
    !request.io_complete &&
    state.left.lookup_issue is None &&
    bytes > 0 else {
    return Err(Assembly("invalid_verification_observation"))
  }
  if !charge_keyed_lookup_input_work(state, bytes) {
    return Err(LookupLimit("work"))
  }
  Ok(())
}

///|
/// Preparation is the original request cursor with this assembly's remaining
/// shared allowance, not a fresh per-key budget. Failed poll work is retained.
pub fn start_client_keyed_lookup_request(
  state : ClientKeyedLookupInput,
  row : Int,
) -> Result[ClientKeyedRequestPreparation, ClientKeyedRequestIssue] {
  if state.closed ||
    state.copying is Some(_) ||
    state.preparation is Some(_) ||
    state.selected_request is Some(_) ||
    state.completed is Some(_) ||
    row != state.accepted ||
    row >= state.rows ||
    state.left.lookup_issue is Some(_) {
    return Err(Assembly("unavailable_request"))
  }
  guard state.input is Some(input) else { return Err(Assembly("closed_input")) }
  let remaining = state.max_work -
    state.work -
    @execution.admitted_input_work(input)
  let preparation = match
    start_client_keyed_row_request(state.left, row, {
      max_work: remaining,
      max_pairs: 100,
      values: {
        max_nodes: 10000,
        max_depth: 100,
        max_text_bytes: state.max_bytes,
      },
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let work = client_keyed_request_preparation_work(preparation)
  if !charge_keyed_lookup_input_work(state, work) {
    cancel_client_keyed_row_request(preparation)
    return Err(LookupLimit("work"))
  }
  state.preparation = Some(preparation)
  state.preparation_work = work
  Ok(preparation)
}

///|
pub fn advance_client_keyed_lookup_request(
  state : ClientKeyedLookupInput,
  preparation : ClientKeyedRequestPreparation,
) -> ClientKeyedRequestPoll {
  if state.closed ||
    state.left.lookup_issue is Some(_) ||
    !(state.preparation is Some(owned) && physical_equal(owned, preparation)) {
    return ClientKeyedRequestFailed(
      Assembly("foreign_or_stopped_preparation"),
      work=client_keyed_request_preparation_work(preparation),
    )
  }
  let poll = advance_client_keyed_row_request(preparation)
  let work = client_keyed_request_preparation_work(preparation)
  if work < state.preparation_work ||
    !charge_keyed_lookup_input_work(state, work - state.preparation_work) {
    cancel_client_keyed_row_request(preparation)
    return ClientKeyedRequestFailed(LookupLimit("work"), work~)
  }
  state.preparation_work = work
  match poll {
    ClientKeyedRequestComplete(request, ..) => {
      request.assembly_accounting = Some(state)
      state.preparation = None
    }
    ClientKeyedRequestFailed(issue, ..) =>
      keyed_lookup_fail(state.left, issue) |> ignore
    ClientKeyedRequestContinue(..) => ()
  }
  poll
}

///|
fn keyed_lookup_input_request(
  state : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
) -> Result[String, ClientKeyedRequestIssue] {
  if state.closed ||
    state.copying is Some(_) ||
    state.preparation is Some(_) ||
    state.completed is Some(_) ||
    !physical_equal(request.left, state.left) ||
    request.row != state.accepted ||
    state.accepted >= state.rows ||
    state.left.lookup_issue is Some(_) ||
    !client_keyed_request_matches_acquisition(request, state.left.acquisition) {
    return Err(Assembly("foreign_or_unavailable_request"))
  }
  if state.selected_request is Some(selected) {
    if physical_equal(selected, request) {
      return Ok(state.selected_key.unwrap())
    }
    return Err(Assembly("unfinished_request"))
  }
  match request.assembly_accounting {
    Some(owner) =>
      if !physical_equal(owner, state) {
        return Err(Assembly("foreign_request_accounting"))
      }
    None => {
      if !charge_keyed_lookup_input_work(state, request.work) {
        return Err(LookupLimit("work"))
      }
      request.assembly_accounting = Some(state)
    }
  }
  let wire = match
    client_keyed_request_wire(request, state.max_bytes, 10000, 100) {
    Ok(wire) => wire
    Err(issue) => return Err(issue)
  }
  if !charge_keyed_lookup_input_work(state, wire.length()) {
    return Err(LookupLimit("work"))
  }
  state.selected_request = Some(request)
  state.selected_key = Some(wire)
  Ok(wire)
}

///|
/// Canonical request data uses the same admitted key contracts and exact
/// original SourceView. No NFC, URI normalization or provider key replaces it.
/// The returned index is private Host plumbing, not an acquisition receipt.
pub fn find_client_keyed_lookup_response(
  state : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
) -> Result[Int, ClientKeyedRequestIssue] {
  let wire = match keyed_lookup_input_request(state, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if state.selected_index is Some(index) {
    return Ok(index)
  }
  for index, (key, _) in state.known {
    let amount = key.length().to_int64() + wire.length().to_int64() + 1L
    if amount > 2147483647L ||
      !charge_keyed_lookup_input_work(state, amount.to_int()) {
      return Err(LookupLimit("work"))
    }
    if key == wire {
      state.selected_index = Some(index)
      return Ok(index)
    }
  }
  state.selected_index = Some(-1)
  Ok(-1)
}

///|
/// Called only after current read authority is rechecked for the original
/// capture. Repeated left occurrences reuse one right row but remain separate
/// left rows in the subsequent JOIN, avoiding accidental multiplicative fanout.
pub fn reuse_client_keyed_lookup_response(
  state : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
  index : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  let wire = match keyed_lookup_input_request(state, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard state.known.get(index) is Some((key, Some(read))) &&
    key == wire &&
    @execution.supplied_relation_read_available(read) &&
    request.attempts == 0L else {
    return Err(Assembly("unavailable_reuse"))
  }
  state.accepted += 1
  request.io_complete = true
  state.selected_request = None
  state.selected_key = None
  state.selected_index = None
  Ok(())
}

///|
/// The installed bridge verifies the exact successful RowRun/Request before
/// entering. Foreign right ports and responses remain rejected by this owner.
pub fn begin_client_keyed_lookup_response(
  state : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
  read : @execution.SuppliedRelationRead,
) -> Result[Unit, ClientKeyedRequestIssue] {
  let index = match find_client_keyed_lookup_response(state, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if index >= 0 {
    return Err(Assembly("duplicate_response"))
  }
  let wire = match keyed_lookup_input_request(state, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let acquisition = state.left.acquisition
  if !request.io_complete ||
    request.attempts == 0L ||
    !@execution.supplied_relation_read_matches_input(
      read,
      acquisition.owner,
      @acquisition.keyed_join_input(acquisition.binding.join),
    ) ||
    @execution.supplied_relation_read_row_count(read) != 1 {
    return Err(Assembly("unverified_response"))
  }
  guard state.input is Some(input) else { return Err(Assembly("closed_input")) }
  let cursor = match
    @execution.start_admitted_presence_input_row(input, state.max_work, column => {
      @execution.supplied_relation_read_presence_cell(read, 0, column)
    }) {
    Ok(cursor) => cursor
    Err(issue) => return Err(Row(issue))
  }
  state.copying = Some(cursor)
  state.pending_key = Some(wire)
  state.pending_read = Some(read)
  state.selected_request = None
  state.selected_key = None
  state.selected_index = None
  Ok(())
}

///|
pub fn advance_client_keyed_lookup_input(
  state : ClientKeyedLookupInput,
  quantum : Int,
) -> Result[Bool, ClientKeyedRequestIssue] {
  if state.closed ||
    quantum <= 0 ||
    state.left.lookup_issue is Some(_) ||
    !@execution.producer_read_available(state.left.read) {
    return Err(Assembly("unavailable"))
  }
  guard state.input is Some(_) else { return Err(Assembly("closed_input")) }
  if state.completed is Some(_) {
    return Ok(true)
  }
  for _ in 0..<quantum {
    if state.copying is Some(cursor) {
      if !charge_keyed_lookup_input_work(state, 1) {
        return Err(LookupLimit("work"))
      }
      guard state.pending_read is Some(read) &&
        @execution.supplied_relation_read_available(read) else {
        return Err(Assembly("response_closed"))
      }
      match @execution.advance_admitted_input_row(cursor) {
        Err(issue) => {
          keyed_lookup_fail(state.left, Row(issue)) |> ignore
          return Err(Row(issue))
        }
        Ok(false) => continue
        Ok(true) => {
          if !@execution.cleanup_admitted_input_row(cursor) {
            return Err(Assembly("row_cleanup"))
          }
          let key = state.pending_key.unwrap()
          state.known.push((key, Some(read)))
          state.accepted += 1
          state.copying = None
          state.pending_key = None
          state.pending_read = None
        }
      }
    } else {
      return Ok(true)
    }
  }
  Ok(state.copying is None)
}

///|
pub fn finish_client_keyed_lookup_input(
  state : ClientKeyedLookupInput,
) -> Result[@execution.SuppliedRelationRead, ClientKeyedRequestIssue] {
  if state.closed ||
    state.copying is Some(_) ||
    state.accepted != state.rows ||
    state.left.lookup_issue is Some(_) ||
    !@execution.producer_read_available(state.left.read) {
    return Err(Assembly("incomplete"))
  }
  if state.completed is None {
    guard state.input is Some(input) else {
      return Err(Assembly("closed_input"))
    }
    let rows = match @execution.finish_admitted_input(input) {
      Ok(value) => value
      Err(issue) => return Err(InputCapture(issue))
    }
    state.completed = Some(rows)
    let wire = match
      @execution.identify_captured_rows(rows, {
        max_bytes: state.max_bytes,
        max_nodes: state.max_work,
        max_columns: state.max_work,
        max_order_work: state.max_work,
        max_depth: 100,
      }) {
      Ok(value) => value
      Err(_) => return Err(Assembly("wire_limit"))
    }
    let holding = match
      @resources.retain_allocation(
        state.ledger,
        state.reservation,
        state.retained_bytes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Physical(issue))
    }
    state.holding = Some(holding)
    state.identity = Some(@execution.row_wire_cid(wire))
  }
  if @resources.reservation_open(state.reservation) {
    match @resources.settle_reservation(state.ledger, state.reservation) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  if state.holding is None {
    return Err(Assembly("unretained"))
  }
  if state.read is Some(read) {
    if @execution.supplied_relation_read_available(read) {
      return Ok(read)
    }
    return Err(Assembly("closed_response"))
  }
  let read = match
    @execution.prepare_supplied_relation_read(
      state.left.acquisition.owner,
      @acquisition.keyed_join_input(state.left.acquisition.binding.join),
      state.completed.unwrap(),
      () => {
        !state.closed &&
        state.left.lookup_issue is None &&
        @execution.producer_read_available(state.left.read) &&
        state.known.all(entry => {
          entry.1
          .map(@execution.supplied_relation_read_available)
          .unwrap_or(false)
        })
      },
    ) {
    Ok(read) => read
    Err(issue) => return Err(Read(issue))
  }
  state.read = Some(read)
  Ok(read)
}

///|
pub fn client_keyed_lookup_input_work(state : ClientKeyedLookupInput) -> Int64 {
  state.work.to_int64() +
  state.input
  .map(input => @execution.admitted_input_work(input).to_int64())
  .unwrap_or(state.retired_row_work)
}

///|
pub fn client_keyed_lookup_acquisition(
  state : ClientKeyedLookupInput,
) -> ClientKeyedAcquisition {
  state.left.acquisition
}

///|
/// Open the original checked task graph with its verified Direct prefix and
/// sealed keyed input on the caller's existing ledger. The keyed input is not
/// a fabricated Source capture or task completion. Borrowed holdings remain
/// the acquisition caller's responsibility through the final consumer stop.
pub fn open_client_keyed_lookup_dag(
  prepared : PreparedClientProgram,
  lookup : ClientKeyedLookupInput,
  ledger : @resources.Ledger,
) -> Result[@strategy.CapturedDAG, ClientKeyedRequestIssue] {
  let acquisition = client_keyed_lookup_acquisition(lookup)
  guard physical_equal(ledger, lookup.ledger) &&
    client_keyed_acquisition_matches_program(acquisition, prepared) &&
    client_keyed_acquisition_coordinates(acquisition) is Some((_, task, step)) &&
    @strategy.graph_task_selected_step(prepared.graph, task) == Some(step) &&
    @strategy.graph_captured_prefix(prepared.graph) == 1 &&
    @strategy.graph_task_prefix_end(prepared.graph, 0) == Some(1) else {
    return Err(ForeignLeft)
  }
  let read = match finish_client_keyed_lookup_input(lookup) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @strategy.open_captured_dag(prepared.graph, lookup.left.source, ledger, supplied_reads=[
    (task, 1, read),
  ]).map_err(_ => Assembly("ForeignCapturedGraph"))
}

///|
pub fn client_keyed_lookup_dag_matches(
  lookup : ClientKeyedLookupInput,
  run : @strategy.CapturedDAG,
) -> Bool {
  let prepared = match lookup.left.acquisition.program {
    KeyedPure(value) => value
    KeyedEffect(value) => client_effect_program_view(value)
  }
  physical_equal(@strategy.captured_dag_graph(run), prepared.graph) &&
  physical_equal(@strategy.captured_dag_ledger(run), lookup.ledger)
}

///|
/// Borrow the exact original JOIN inputs only after the whole key-set barrier.
/// Equal schemas, an acquisition prefix, or another Program's generated
/// sequence cannot complete this operation. Selection retains the original
/// expression contexts but does not replay WHERE or projection.
pub fn prepare_client_keyed_lookup_join_inputs(
  state : ClientKeyedLookupInput,
  generated : @execution.GeneratedSequence,
) -> Result[
  (
    @execution.GeneratedSequence,
    @execution.ProducerRead,
    @execution.SuppliedRelationRead,
  ),
  ClientKeyedRequestIssue,
] {
  let acquisition = state.left.acquisition
  if !physical_equal(
      @execution.generated_sequence_owner(generated),
      acquisition.owner,
    ) {
    return Err(Assembly("foreign_join_owner"))
  }
  let step = @acquisition.keyed_join_step(acquisition.binding.join)
  guard @execution.select_generated_sequence_step(generated, step)
    is Some(selected) &&
    @execution.producer_read_matches_operation_input(
      state.left.read,
      acquisition.owner,
      step,
      0,
    ) else {
    return Err(Assembly("foreign_join_left"))
  }
  let right = match finish_client_keyed_lookup_input(state) {
    Ok(right) => right
    Err(issue) => return Err(issue)
  }
  if !@execution.supplied_relation_read_matches_operation_input(
      right,
      acquisition.owner,
      step,
      1,
    ) {
    return Err(Assembly("foreign_join_right"))
  }
  Ok((selected, state.left.read, right))
}

///|
/// Bind the same sealed key-set to the original serialization prefix. This
/// does not transfer custody: the caller keeps the lookup and Direct capture
/// until the dependent provider has physically stopped and cleaned up.
pub fn prepare_client_keyed_serialization_inputs(
  prepared : PreparedClientProgram,
  state : ClientKeyedLookupInput,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
  generated : @execution.GeneratedSequence,
) -> Result[
  (@execution.ProducerRead, @execution.SuppliedRelationRead),
  ClientKeyedRequestIssue,
] {
  guard client_keyed_acquisition_matches_program(
      state.left.acquisition,
      prepared,
    ) &&
    physical_equal(source, state.left.source) &&
    physical_equal(ledger, state.ledger) else {
    return Err(ForeignLeft)
  }
  prepare_client_keyed_lookup_join_inputs(state, generated).map(value => {
    (value.1, value.2)
  })
}

///|
pub fn client_keyed_lookup_input_identity(
  state : ClientKeyedLookupInput,
) -> String? {
  if state.closed ||
    state.left.lookup_issue is Some(_) ||
    state.holding is None ||
    @resources.reservation_open(state.reservation) ||
    !@execution.producer_read_available(state.left.read) ||
    !(state.read is Some(read) &&
    @execution.supplied_relation_read_available(read)) {
    None
  } else {
    state.identity
  }
}

///|
/// Invalidate reads without reclaiming capacity before physical child cleanup.
pub fn stop_client_keyed_lookup_input(state : ClientKeyedLookupInput) -> Unit {
  state.closed = true
  if state.preparation is Some(preparation) {
    cancel_client_keyed_row_request(preparation)
    state.preparation = None
  }
}

///|
/// Stop assembly only. The caller still closes every original physical RowRun
/// and keeps their failed/pending cleanup handles. No borrowed source is erased.
pub fn cleanup_client_keyed_lookup_input(
  state : ClientKeyedLookupInput,
  quantum : Int,
) -> Result[Bool, ClientKeyedRequestIssue] {
  stop_client_keyed_lookup_input(state)
  if quantum <= 0 {
    return Ok(false)
  }
  if state.copying is Some(cursor) {
    @execution.cleanup_admitted_input_row(cursor) |> ignore
    state.copying = None
  }
  state.pending_key = None
  state.pending_read = None
  state.selected_request = None
  state.selected_key = None
  state.selected_index = None
  if state.input is Some(input) &&
    !@execution.reclaim_admitted_input(input, quantum) {
    if @resources.reservation_open(state.reservation) {
      match @resources.mark_cleanup_pending(state.ledger, state.reservation) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
    }
    return Ok(false)
  }
  for _ in 0..<quantum {
    if state.known.is_empty() {
      break
    }
    state.known[state.known.length() - 1] = ("", None)
    state.known.pop() |> ignore
  }
  if !state.known.is_empty() {
    return Ok(false)
  }
  state.known = []
  if state.input is Some(input) {
    state.retired_row_work = @execution.admitted_input_work(input).to_int64()
  }
  state.input = None
  state.completed = None
  state.read = None
  if state.holding is Some(holding) {
    match @resources.release_allocation(state.ledger, holding) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
    state.holding = None
  }
  if @resources.reservation_open(state.reservation) {
    match @resources.settle_reservation(state.ledger, state.reservation) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok(true)
}
