///|
fn physical_journal_current(ticket : Int) -> Int = "actql_host" "journal_current"

///|
fn physical_journal_current_operation(ticket : Int) -> Int64 = "actql_host" "journal_current_operation"

///|
// Check the one current catalog on the original Reader. 1 acknowledges
// the check; it carries no authority or supported-format selection.
fn physical_journal_schema(ticket : Int) -> Int = "actql_host" "journal_schema"

///|
// Literal little-endian u32 key length, u32 body length and i64 revision.
// The original ticket retains the row until the second bounded import succeeds.
// Borrow the buffers through the actual import, not an earlier offset extractor.
#unsafe_skip_stub_check
#borrow(namespace_buffer, key_buffer, header_buffer)
fn physical_journal_query_header(
  ticket : Int,
  mode : Int,
  namespace_buffer : Bytes,
  namespace_bytes : Int,
  key_buffer : Bytes,
  key_bytes : Int,
  header_buffer : FixedArray[Byte],
) -> Int = "actql_host" "journal_query_header"

///|
#unsafe_skip_stub_check
#borrow(key_buffer, body_buffer)
fn physical_journal_copy_row(
  ticket : Int,
  key_buffer : FixedArray[Byte],
  key_bytes : Int,
  body_buffer : FixedArray[Byte],
  body_bytes : Int,
) -> Int = "actql_host" "journal_copy_row"

///|
// Source-pinned wasm32 payload offset only. Callers must retain the Bytes
// separately across any later foreign call; this extraction extends no loan.
// Python validates original memory and never decodes a Moon object header.
#borrow(bytes)
extern "wasm" fn journal_bytes_offset(bytes : Bytes) -> Int =
  #|(func (param i32) (result i32) local.get 0)

///|
/// Original Core inputs and transient physical query custody only. The Host
/// keeps the same SQLite transaction and epoch/config/current fences borrowed.
priv struct StoredJournalObservation {
  material : Int
  configuration : Int
  physical : Int
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut closing : Bool
  mut outcome : StoredJournalObservationOutcome?
  mut admission_produced : Bool
}

///|
fn journal_current(
  value : Instance,
  child : StoredJournalObservation,
  plan : @local_run.LocalRunPlan,
) -> Result[Unit, Int] {
  if value.closing || value.runtime_closing || child.closing {
    return Err(-5)
  }
  guard value.run_configurations.get(child.configuration) is Some(current) else {
    return Err(-2)
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  let permit = @authorization.bind_dispatch_authorization(
    current.account,
    current.tuple,
    @authorization.Activation,
    @host.prepared_client_identity(@local_run.local_run_prepared(plan)).program_definition_cid,
    current.context_cid,
  )
  guard permit is Ok(permit) &&
    @local_run.authorize_local_compute_configuration(
      plan,
      permit,
      current.account,
      current.tuple,
      current.context_cid,
    )
    is Ok(_) else {
    return Err(-32)
  }
  // A trusted physical epoch/config/transaction fence, not a caller grant.
  if physical_journal_current(child.physical) == 0 {
    Ok(())
  } else {
    Err(-41)
  }
}

///|
fn journal_query_row(
  value : Instance,
  child : StoredJournalObservation,
  plan : @local_run.LocalRunPlan,
  mode : Int,
  table_name : String,
  key : String,
) -> Result[@host.ClientJournalPhysicalRow?, Int] {
  physical_journal_row(
    child.physical,
    () => journal_current(value, child, plan),
    mode,
    table_name,
    key,
  )
}

///|
// Validate the literal header before either exact-sized payload allocation.
// This pure private decoder is independently exercised with malformed headers.
fn journal_row_header(header : Bytes) -> Result[(Int, Int, Int64), Int] {
  if header.length() != 16 {
    return Err(-41)
  }
  let mut key_length = 0
  let mut body_length = 0
  let mut revision = 0L
  for index in 0..<4 {
    key_length = key_length | (header[index].to_int() << (8 * index))
    body_length = body_length | (header[4 + index].to_int() << (8 * index))
  }
  for index in 0..<8 {
    revision = revision | (header[8 + index].to_int().to_int64() << (8 * index))
  }
  if key_length <= 0 ||
    key_length > 4096 ||
    body_length < 0 ||
    body_length > 262144 ||
    revision < 0L {
    return Err(-41)
  }
  Ok((key_length, body_length, revision))
}

///|
/// Shared physical transfer for an original scoped namespace-reader loan.
/// The owning caller supplies its existing typed current fence before/after
/// every query. This transfer cannot issue scope, completeness or permission.
fn physical_journal_row(
  physical : Int,
  current : () -> Result[Unit, Int],
  mode : Int,
  table_name : String,
  key : String,
) -> Result[@host.ClientJournalPhysicalRow?, Int] {
  match current() {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  let namespace_bytes = @utf8.encode(table_name)
  let key_bytes = @utf8.encode(key)
  if namespace_bytes.length() > 4096 || key_bytes.length() > 4096 {
    return Err(-41)
  }
  // The original current/journal ticket's physical-copy reservation includes
  // a separate 64-byte header/control envelope before this allocation. The
  // existing fixed VM and row reservations still own the exact-sized fields.
  // This replaces the old input list, fields Array and two tuple staging loop;
  // none of that removed staging is needed to fund the new header.
  let header : FixedArray[Byte] = FixedArray::make(16, 0)
  let code = physical_journal_query_header(
    physical,
    mode,
    namespace_bytes,
    namespace_bytes.length(),
    key_bytes,
    key_bytes.length(),
    header,
  )
  if code == 1 {
    return current().map(_ => None)
  }
  if code != 0 {
    return Err(-41)
  }
  let (key_length, body_length, revision) = match
    journal_row_header(header.unsafe_reinterpret_as_bytes()) {
    Ok(fields) => fields
    Err(code) => return Err(code)
  }
  let actual_key : FixedArray[Byte] = FixedArray::make(key_length, 0)
  let body : FixedArray[Byte] = FixedArray::make(body_length, 0)
  if physical_journal_copy_row(
      physical, actual_key, key_length, body, body_length,
    ) !=
    0 {
    return Err(-41)
  }
  let actual_key = @utf8.decode(actual_key.unsafe_reinterpret_as_bytes()) catch {
    _ => return Err(-41)
  }
  let body = body.unsafe_reinterpret_as_bytes()
  match current() {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  Ok(Some({ key: actual_key, body, revision, }))
}

///|
/// Reserve the physical query/decoder holding before allocating/calling it.
/// The original material's input borrow owns the Reference and checked rows.
pub fn reserve_journal_observation(
  nonce : Int64,
  material : Int,
  configuration : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.materials.get(material) is Some(parent) &&
    parent.produced &&
    parent.submission is Some({ rows: Some(_), .. }) &&
    value.run_configurations.contains(configuration) else {
    return -2
  }
  // Explicit transport retirement leaves the nominal saved rows/input alive.
  // A full-close attempt or missing parent cannot issue a new child.
  if value.closing || value.runtime_closing || parent.closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) {
    return -3
  }
  // The canonical saved-admission writer bounds this output at 4096 bytes.
  // The separate physical allowance still covers the original Journal rows.
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 4096, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  value.journal_observations[handle] = {
    material,
    configuration,
    physical: physical_ticket,
    slot,
    invoked: false,
    closing: false,
    outcome: None,
    admission_produced: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
/// Core chooses each query and validates the same original saved snapshot.
/// Completion here is inspection only; physical COMMIT/Store ACK is separate.
pub fn inspect_journal_observation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.journal_observations.get(handle) is Some(child) &&
    value.materials.get(child.material) is Some(material) &&
    material.submission is Some({ rows: Some(rows), .. }) &&
    value.runs.get(material.run) is Some(record) &&
    record.outcome is Some(Ok(plan)) &&
    value.preparations.get(record.preparation)
    is Some({ submitted: Some(original), .. }) else {
    return -2
  }
  if child.invoked {
    return -33
  }
  match journal_current(value, child, plan) {
    Ok(_) => ()
    Err(code) => return code
  }
  child.invoked = true
  let scan = (table_name, cursor) => {
    journal_query_row(value, child, plan, 0, table_name, cursor)
  }
  let read = (table_name, key) => {
    journal_query_row(value, child, plan, 1, table_name, key)
  }
  let frame = open_journal_decode_frame(
    value,
    handle,
    child,
    @host.client_request_scope_cid(@local_run.local_run_request(plan)),
  )
  let inspect_run = row => {
    match frame {
      None => submission_append_run_inspection(row)
      Some(frame) => journal_decode_run_inspection(value, child, frame, row)
    }
  }
  let outcome = @local_run.inspect_local_saved_submission(
    rows,
    plan,
    original,
    1024,
    scan,
    read,
    inspect_run,
    () => submission_cancellation_inventory(scan, read),
    -31,
  ).map_err(issue => {
    match issue {
      Inspection(code) => code
      UnresolvedHistory => -43
      NotAdmitted => -44
      Rows(_) => -31
    }
  })
  let outcome = match journal_current(value, child, plan) {
    Ok(_) => outcome
    Err(code) => Err(code)
  }
  let keep_selected = outcome is Ok(_)
  let retained_frame = match frame {
    None => None
    Some(frame) => {
      let code = dispose_journal_decode_rows(value, frame, keep_selected)
      if code != 0 {
        // The original inspection failure stays primary; all exact pending
        // tokens remain reachable under this child's normal cleanup.
        let outcome = match outcome {
          Err(original) => Err(original)
          Ok(_) => Err(code)
        }
        child.outcome = Some(Observed(outcome, Some(frame)))
        return match outcome {
          Ok(_) => 0
          Err(code) => code
        }
      }
      if frame.selected is Some(_) {
        // All foreign cells have retired; the selected pure result and its
        // distinct fresh row copy now belong to this SAME child's outcome.
        guard journal_decode_frame_capacity() is Some(retention) &&
          @resources.shrink_capacity_reservation(
            value.root,
            frame.capacity,
            retention,
            0L,
          )
          is Ok(_) else {
          child.outcome = Some(Observed(Err(-4), Some(frame)))
          return -4
        }
        Some(frame)
      } else {
        match @resources.settle_capacity(value.root, frame.capacity) {
          Err(_) => {
            let failure = match outcome {
              Err(original) => original
              Ok(_) => -4
            }
            child.outcome = Some(Observed(Err(failure), Some(frame)))
            return failure
          }
          Ok(_) => None
        }
      }
    }
  }
  child.outcome = Some(Observed(outcome, retained_frame))
  match outcome {
    Ok(_) => 0
    Err(code) => code
  }
}

///|
pub fn journal_observation_revision(
  nonce : Int64,
  handle : Int,
  field : Int,
) -> Int64 {
  guard selected(nonce) is Some(value) &&
    value.journal_observations.get(handle) is Some(child) &&
    !child.closing &&
    child.outcome is Some(Observed(Ok(observed), _)) &&
    value.materials.get(child.material) is Some(material) &&
    material.submission is Some({ rows: Some(rows), .. }) &&
    value.runs.get(material.run) is Some(record) &&
    record.outcome is Some(Ok(plan)) &&
    value.preparations.get(record.preparation)
    is Some({ submitted: Some(original), .. }) &&
    journal_current(value, child, plan) is Ok(_) else {
    return -1L
  }
  match
    @local_run.local_saved_submission_revisions(observed, rows, plan, original) {
    Ok((admission, run, submission)) =>
      match field {
        0 => admission
        1 => run
        2 => submission
        _ => -1L
      }
    Err(_) => -1L
  }
}

///|
/// Produce the saved Owner admission under the original current/snapshot
/// frame. Cached output still requires current validation on every read.
pub fn journal_admission_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.journal_observations.get(handle) is Some(child) &&
    !child.closing &&
    child.outcome is Some(Observed(Ok(observed), _)) &&
    value.materials.get(child.material) is Some(material) &&
    material.submission is Some({ rows: Some(rows), .. }) &&
    value.runs.get(material.run) is Some(record) &&
    record.outcome is Some(Ok(plan)) &&
    value.preparations.get(record.preparation)
    is Some({ submitted: Some(original), .. }) else {
    return -2
  }
  match journal_current(value, child, plan) {
    Ok(_) => ()
    Err(code) => return code
  }
  if !child.admission_produced {
    let wire = match
      @local_run.local_saved_submission_admission_wire(
        observed, rows, plan, original,
      ) {
      Ok(wire) => wire
      Err(UnrepresentableRevision) => return -45
      Err(_) => return -31
    }
    let code = status(
      @buffers.supply_buffer_output(value.pool, child.slot, @utf8.encode(wire)),
    )
    if code != 0 {
      return code
    }
    child.admission_produced = true
  }
  match journal_current(value, child, plan) {
    Ok(_) => ()
    Err(code) => return code
  }
  @buffers.buffer_length(value.pool, child.slot).unwrap_or(-33)
}

///|
// A close debt contains NO successful T payload. The same function is used
// for the actual saved observation; returning ends its temporary payload loan
// before the caller may settle selected backing. It grants no operation.
fn[T] journal_close_payload(
  observed : Result[T, Int],
  frame : StoredJournalDecodeFrame,
) -> StoredJournalObservationOutcome {
  frame.active = false
  match observed {
    Err(issue) => frame.issue = issue
    Ok(_) => ()
  }
  Decoding(frame)
}

///|
fn begin_journal_observation_close(child : StoredJournalObservation) -> Unit {
  child.closing = true
  match child.outcome {
    Some(Observed(observed, Some(frame))) =>
      child.outcome = Some(journal_close_payload(observed, frame))
    Some(Observed(Ok(_), None)) => child.outcome = None
    Some(Decoding(frame)) => frame.active = false
    _ => ()
  }
  // No successful snapshot remains in the child, or in this helper's stack
  // after return. Exact pending tokens/original error remain in the frame.
}

///|
// Drop the actual frame while its SAME controller token still covers it.
// No frame reference escapes this helper's return; pending close then owns
// only the existing token/scalar debt phase, never an unfunded controller.
fn prepare_journal_observation_close(
  value : Instance,
  child : StoredJournalObservation,
) -> Int {
  begin_journal_observation_close(child)
  match child.outcome {
    Some(Decoding(frame)) => {
      let code = dispose_journal_decode_rows(value, frame, false)
      if code != 0 {
        return code
      }
      child.outcome = Some(ReservingDecode(frame.capacity, frame.issue))
      0
    }
    Some(Observed(_, Some(_))) => -4
    _ => 0
  }
}

///|
fn settle_journal_observation_close_capacity(
  value : Instance,
  child : StoredJournalObservation,
) -> Int {
  match child.outcome {
    Some(ReservingDecode(capacity, issue)) => {
      let code = settle_journal_decode_original(value, capacity)
      if code != 0 {
        return code
      }
      child.outcome = if issue == 0 {
        None
      } else {
        Some(Observed(Err(issue), None))
      }
      0
    }
    _ => 0
  }
}

///|
pub fn close_journal_observation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.journal_observations.get(handle) is Some(child) else {
    return -2
  }
  let prepared = prepare_journal_observation_close(value, child)
  if prepared != 0 {
    return prepared
  }
  // The prior helper returned with NO successful payload or frame loan.
  let cleanup = settle_journal_observation_close_capacity(value, child)
  if cleanup != 0 {
    return cleanup
  }
  let result = status(@buffers.close_buffer(value.pool, child.slot))
  if result == 0 {
    child.outcome = None
    value.journal_observations.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
