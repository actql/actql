///|
/// Private references to existing Core owners and their exact input loans.
/// These registries contain no Run states, recovery decisions or authority.
priv struct StoredEnvironment {
  borrow : @buffers.BufferBorrow
  environment : @checked.CheckEnvironment
  context : @preparation.LocalInputContext
}

///|
priv struct StoredPreparation {
  borrow : @buffers.BufferBorrow
  slot : @buffers.BufferSlot
  environment : Int
  kind : Int
  mut started : Bool
  mut outcome : Result[
    @host.PreparedClientProgram,
    @preparation.LocalPreparationIssue,
  ]?
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
#export_name("actql_program_install_environment")
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
  value.environments[handle] = { borrow, environment, context, }
  value.next_handle += 1
  handle
}

///|
/// Reserve original input custody before invoking the Checker. The caller
/// receives this handle even if a later Wasm invocation traps or is cancelled.
/// No physical reader or semantic preparation starts during reservation.
#export_name("actql_program_reserve_preparation")
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
  if kind != 1 && kind != 2 {
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
    started: false,
    outcome: None,
  }
  value.next_handle += 1
  handle
}

///|
/// kind=1 is structured JSON; kind=2 is original AQL carried as a JSON string.
/// Readiness is not Run admission. A completed call is not silently repeated.
#export_name("actql_program_prepare")
pub fn prepare_program(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.preparations.get(handle) is Some(record) &&
    value.environments.get(record.environment) is Some(configuration) else {
    return -2
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
  let outcome = @preparation.prepare_local_input(
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
#export_name("actql_program_prepared_results")
pub fn prepared_results(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.preparations.get(handle) is Some(record) else { return -2 }
  match record.outcome {
    Some(Ok(prepared)) => @host.prepared_client_result_count(prepared)
    Some(Err(_)) => -22
    None => -23
  }
}

///|
#export_name("actql_program_prepared_tasks")
pub fn prepared_tasks(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.preparations.get(handle) is Some(record) else { return -2 }
  match record.outcome {
    Some(Ok(prepared)) =>
      @strategy.graph_task_count(@host.prepared_client_graph(prepared))
    Some(Err(_)) => -22
    None => -23
  }
}

///|
#export_name("actql_program_close_preparation")
pub fn close_preparation(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.preparations.get(handle) is Some(record) else { return -2 }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.preparations.remove(handle) |> ignore
  }
  result
}

///|
#export_name("actql_program_close_environment")
pub fn close_environment(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) else { return -1 }
  guard value.environments.get(handle) is Some(record) else { return -2 }
  if value.preparations.values().any(prepared => prepared.environment == handle) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.environments.remove(handle) |> ignore
  }
  result
}
