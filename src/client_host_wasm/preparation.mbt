///|
/// Private references to existing Core owners and their exact input loans.
/// These registries contain no Run states, recovery decisions or authority.
priv struct StoredEnvironment {
  borrow : @buffers.BufferBorrow
  environment : @checked.CheckEnvironment
  wire : String
  context : @preparation.LocalInputContext
}

///|
priv struct StoredPreparation {
  borrow : @buffers.BufferBorrow
  slot : @buffers.BufferSlot
  environment : Int
  kind : Int
  mut restoration : Int?
  mut submitted : @preparation.LocalSubmittedPreparation?
  mut started : Bool
  mut outcome : Result[
    @preparation.LocalPreparedInput,
    @preparation.LocalPreparationIssue,
  ]?
}

///|
/// Submitted readiness must retain the exact prepared Owner belonging to its
/// original intent, rather than another independently prepared document.
fn stored_preparation_input(
  record : StoredPreparation,
) -> @preparation.LocalPreparedInput? {
  guard record.outcome is Some(Ok(input)) else { return None }
  if record.kind == 3 {
    guard record.submitted is Some(submitted) &&
      physical_equal(
        input,
        @preparation.local_submitted_preparation_input(submitted),
      ) else {
      return None
    }
  }
  Some(input)
}

///|
fn input_cursor(
  value : Instance,
  slot : @buffers.BufferSlot,
) -> @decode.Cursor? {
  guard @buffers.buffer_source(value.pool, slot) is Some(source) else {
    return None
  }
  match
    @decode.admit(source, {
      max_nodes: 16384,
      max_depth: 64,
      max_string_bytes: 1048576,
      max_total_string_bytes: 1048576,
    }) {
    Ok(cursor) => Some(cursor)
    Err(_) => None
  }
}

///|
/// Private, trusted Host configuration; not caller-provided Check evidence.
/// The environment Owner validates the original canonical wire and its CID.
pub fn install_environment(nonce : Int64, input : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.copies.get(input) is Some((slot, physical)) else { return -2 }
  if value.next_handle == 2147483647 {
    return -4
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.open_object(cursor) is Ok(object) &&
    @decode.required(object, "evidence_bundle_cid") is Ok(cid_cursor) &&
    @decode.text(cid_cursor) is Ok(cid) &&
    @buffers.buffer_wire(value.pool, slot) is Some(wire) else {
    return -20
  }
  let body = @utf8.decode(wire) catch { _ => return -12 }
  guard @host.admit_client_check_environment(
      body,
      cid,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    )
    is Some(environment) else {
    return -20
  }
  // This entry installs the source-free profile. Source-backed aliases must
  // come from the publication Owner, not from Client-submitted configuration.
  let context = match
    @preparation.bind_local_input_context(environment, [], "python.local") {
    Ok(context) => context
    Err(_) => return -20
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.environments[handle] = { borrow, environment, wire: body, context, }
  value.next_handle += 1
  handle
}

///|
/// Trusted installed environment and publication share one pre-reserved input.
/// The common publication interpreter binds aliases to admitted Catalog facts;
/// no caller-defined file, schema or Source read permission is accepted here.
pub fn install_source_environment(nonce : Int64, input : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["environment", "publication"]) is Ok(object) &&
    required_text(object, "environment") is Some(body) &&
    required_text(object, "publication") is Some(publication) else {
    return -20
  }
  guard @host.admit_client_check_environment(
      body,
      environment_body_cid(body),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    )
    is Some(environment) else {
    return -20
  }
  let context = match
    @preparation.bind_local_published_input_context(
      environment,
      publication,
      None,
    ) {
    Ok(context) => context
    Err(_) => return -20
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.environments[handle] = { borrow, environment, wire: body, context, }
  value.next_handle += 1
  handle
}

///|
fn environment_body_cid(body : String) -> String {
  let node = match
    @source.parse_json_bytes(@utf8.encode(body), {
      max_input_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
    }) {
    Ok(node) => node
    Err(_) => return ""
  }
  guard @decode.admit(node, {
      max_nodes: 4096,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    })
    is Ok(cursor) &&
    @decode.open_object(cursor) is Ok(object) else {
    return ""
  }
  required_text(object, "evidence_bundle_cid").unwrap_or("")
}

///|
/// Reserve original input custody before invoking the Checker. The caller
/// receives this handle even if a later Wasm invocation traps or is cancelled.
/// No physical reader or semantic preparation starts during reservation.
pub fn reserve_preparation(
  nonce : Int64,
  environment : Int,
  input : Int,
  kind : Int,
) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.environments.contains(environment) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  if kind != 1 && kind != 2 && kind != 3 {
    return -3
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.preparations[handle] = {
    borrow,
    slot,
    environment,
    kind,
    restoration: None,
    submitted: None,
    started: false,
    outcome: None,
  }
  value.next_handle += 1
  handle
}

///|
/// kind=1 is structured JSON; kind=2 is original AQL carried as a JSON string.
/// kind=3 keeps the original SDK submitted-intent envelope and bindings.
/// Readiness is not Run admission. A completed call is not silently repeated.
pub fn prepare_program(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.preparations.get(handle) is Some(record) &&
    value.environments.get(record.environment) is Some(configuration) else {
    return -2
  }
  if record.restoration is Some(_) {
    return -3
  }
  if record.outcome is Some(_) {
    return 0
  }
  if record.started {
    return -23
  }
  // A trap after this point leaves the original loan and invocation marker
  // reachable under the handle already issued to the caller.
  record.started = true
  let slot = record.slot
  let kind = record.kind
  if kind == 3 {
    guard @buffers.buffer_wire(value.pool, slot) is Some(wire) else {
      return -5
    }
    let wire = @utf8.decode(wire) catch { _ => return -12 }
    record.outcome = Some(
      match
        @preparation.prepare_local_submitted_input(
          wire,
          configuration.environment,
          Some(configuration.context),
          @host.client_standard_program_preparation_limits(),
        ) {
        Ok(submitted) => {
          record.submitted = Some(submitted)
          Ok(@preparation.local_submitted_preparation_input(submitted))
        }
        Err(issue) => Err(issue)
      },
    )
    return 0
  }
  let document = if kind == 1 {
    guard @buffers.buffer_wire(value.pool, slot) is Some(wire) else {
      return -5
    }
    @utf8.decode(wire) catch {
      _ => return -12
    }
  } else {
    guard input_cursor(value, slot) is Some(cursor) &&
      @decode.text(cursor) is Ok(text) else {
      return -21
    }
    text
  }
  let input = if kind == 1 {
    @preparation.Program(document)
  } else {
    @preparation.Aql(document)
  }
  let outcome = @preparation.prepare_local_input_material(
    input,
    configuration.environment,
    None,
    Some(configuration.context),
    @host.client_standard_program_preparation_limits(),
  )
  record.outcome = Some(outcome)
  0
}

///|
/// Bind the existing input loan to the same original codec input. The supplied
/// environment and intent must match the saved originals; this entry never
/// calls the ordinary query lowerer or Checker, even after interruption.
pub fn bind_restored_preparation(
  nonce : Int64,
  handle : Int,
  restoration_handle : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.preparations.get(handle) is Some(record) &&
    record.kind == 3 &&
    value.environments.get(record.environment) is Some(environment) &&
    value.restorations.get(restoration_handle) is Some(restoration) &&
    restoration.saved_original is Some(original) else {
    return -2
  }
  match sdk_restoration_snapshot(value, restoration) {
    Ok(_) => ()
    Err(code) => return code
  }
  if record.restoration is Some(previous) && previous != restoration_handle {
    return -3
  }
  if record.outcome is Some(_) {
    return if record.restoration == Some(restoration_handle) { 0 } else { -3 }
  }
  if record.started {
    return -23
  }
  record.restoration = Some(restoration_handle)
  record.started = true
  let retained = @host.client_saved_task_materials_input(original)
  if environment.wire !=
    @host.client_task_run_materials_retained_environment(retained) ||
    @checked.checking_environment_cid(environment.environment) !=
    @host.prepared_client_check_environment_cid(
      @host.client_task_run_materials_retained_program(retained),
    ) {
    return -35
  }
  guard @buffers.buffer_wire(value.pool, record.slot) is Some(bytes) else {
    return -5
  }
  let wire = @utf8.decode(bytes) catch { _ => return -12 }
  let intent = match
    @host.prepare_client_submitted_intent(wire, 65536, 8192, 64) {
    Ok(value) => value
    Err(_) => return -31
  }
  if @host.client_submitted_intent_wire(intent) !=
    @host.client_submitted_intent_wire(
      @host.client_saved_task_materials_intent(original),
    ) {
    return -45
  }
  record.outcome = Some(
    match @preparation.restore_local_submitted_input(original) {
      Ok(submitted) => {
        record.submitted = Some(submitted)
        Ok(@preparation.local_submitted_preparation_input(submitted))
      }
      Err(issue) => Err(issue)
    },
  )
  0
}

///|
pub fn prepared_results(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.preparations.get(handle) is Some(record) else { return -2 }
  match record.outcome {
    Some(Ok(prepared)) =>
      @host.prepared_client_result_count(
        @preparation.local_prepared_program(prepared),
      )
    Some(Err(_)) => -22
    None => -23
  }
}

///|
pub fn prepared_tasks(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.preparations.get(handle) is Some(record) else { return -2 }
  match record.outcome {
    Some(Ok(prepared)) =>
      @strategy.graph_task_count(
        @host.prepared_client_graph(
          @preparation.local_prepared_program(prepared),
        ),
      )
    Some(Err(_)) => -22
    None => -23
  }
}

///|
pub fn close_preparation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.preparations.get(handle) is Some(record) else { return -2 }
  if value.runs.values().any(run => run.preparation == handle) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.preparations.remove(handle) |> ignore
  }
  result
}

///|
pub fn close_environment(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.environments.get(handle) is Some(record) else { return -2 }
  if value.preparations.values().any(prepared => prepared.environment == handle) ||
    value.client_checks.values().any(report => report.environment == handle) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.environments.remove(handle) |> ignore
  }
  result
}

///|
/// Read only this original Owner's retained typed outcome. Counts, exception
/// codes and a second parser invocation cannot supply this classification.
pub fn prepared_outcome(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.preparations.get(handle) is Some(record) else {
    return -2
  }
  match record.outcome {
    None => 0
    Some(Ok(_)) => 1
    Some(Err(_)) => 2
  }
}
