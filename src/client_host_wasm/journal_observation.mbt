///|
fn physical_journal_current(ticket : Int) -> Int = "actql_host" "journal_current"

///|
fn physical_journal_current_operation(ticket : Int) -> Int64 = "actql_host" "journal_current_operation"

///|
// Same original reader's actual physical format DATA, not current authority.
fn physical_journal_schema(ticket : Int) -> Int = "actql_host" "journal_schema"

///|
// Literal little-endian u32 key length, u32 body length and i64 revision.
// The original ticket retains the row until the second bounded import succeeds.
fn physical_journal_query_header(
  ticket : Int,
  mode : Int,
  namespace_offset : Int,
  namespace_bytes : Int,
  key_offset : Int,
  key_bytes : Int,
  header_offset : Int,
) -> Int = "actql_host" "journal_query_header"

///|
fn physical_journal_copy_row(
  ticket : Int,
  key_offset : Int,
  key_bytes : Int,
  body_offset : Int,
  body_bytes : Int,
) -> Int = "actql_host" "journal_copy_row"

///|
// Source-pinned wasm32 payload borrow. The synchronous Host validates this
// same instance's original memory; no Moon object/header is decoded in Python.
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
  mut outcome : Result[@local_run.LocalSavedSubmissionObservation, Int]?
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
  let header = header.unsafe_reinterpret_as_bytes()
  let code = physical_journal_query_header(
    physical,
    mode,
    journal_bytes_offset(namespace_bytes),
    namespace_bytes.length(),
    journal_bytes_offset(key_bytes),
    key_bytes.length(),
    journal_bytes_offset(header),
  )
  if code == 1 {
    return current().map(_ => None)
  }
  if code != 0 {
    return Err(-41)
  }
  let (key_length, body_length, revision) = match journal_row_header(header) {
    Ok(fields) => fields
    Err(code) => return Err(code)
  }
  let actual_key : FixedArray[Byte] = FixedArray::make(key_length, 0)
  let actual_key = actual_key.unsafe_reinterpret_as_bytes()
  let body : FixedArray[Byte] = FixedArray::make(body_length, 0)
  let body = body.unsafe_reinterpret_as_bytes()
  if physical_journal_copy_row(
      physical,
      journal_bytes_offset(actual_key),
      key_length,
      journal_bytes_offset(body),
      body_length,
    ) !=
    0 {
    return Err(-41)
  }
  let actual_key = @utf8.decode(actual_key) catch { _ => return Err(-41) }
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
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 1048576, physical_copy_bytes, () => {
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
  let outcome = @local_run.inspect_local_saved_submission(
    rows,
    plan,
    original,
    1024,
    scan,
    read,
    submission_append_run_inspection,
    () => {
      @host.inspect_client_empty_cancellation_inventory(
        1024, scan, read, -31, -42,
      )
    },
    -31,
  ).map_err(issue => {
    match issue {
      Inspection(code) => code
      UnresolvedHistory => -43
      NotAdmitted => -44
      Rows(_) => -31
    }
  })
  match journal_current(value, child, plan) {
    Ok(_) => ()
    Err(code) => {
      child.outcome = Some(Err(code))
      return code
    }
  }
  child.outcome = Some(outcome)
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
    child.outcome is Some(Ok(observed)) &&
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
    child.outcome is Some(Ok(observed)) &&
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
pub fn close_journal_observation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.journal_observations.get(handle) is Some(child) else {
    return -2
  }
  child.closing = true
  child.outcome = None
  let result = status(@buffers.close_buffer(value.pool, child.slot))
  if result == 0 {
    value.journal_observations.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
