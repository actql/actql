///|
fn physical_publisher_current(ticket : Int) -> Int = "actql_host" "publisher_current"

///|
fn physical_publisher_begin(ticket : Int, length : Int) -> Int = "actql_host" "publisher_begin"

///|
fn physical_publisher_copy(
  ticket : Int,
  index : Int,
  offset : Int,
  length : Int,
) -> Int = "actql_host" "publisher_copy"

///|
fn physical_publisher_finish(ticket : Int) -> Int = "actql_host" "publisher_finish"

///|
/// Transport custody only. The original common port owns scope and authority.
priv struct StoredPublisher {
  parent : Int
  physical : Int
  slot : @buffers.BufferSlot
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  mut configuration : Int
  mut store : String
  mut port : @publication.PublicationPublisherPort?
  mut closing : Bool
  mut unknown : Bool
}

///|
fn publisher_current(value : Instance, child : StoredPublisher) -> Bool {
  guard value.publication_preflights.get(child.parent) is Some(parent) else {
    return false
  }
  if value.closing || value.runtime_closing || child.closing || parent.closing {
    return false
  }
  guard value.run_configurations.get(child.configuration) is Some(current) else {
    return false
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => {
      if code == -41 {
        child.unknown = true
      }
      return false
    }
  }
  let code = physical_publisher_current(child.physical)
  if code != 0 && code != -1 {
    child.unknown = true
  }
  code == 0
}

///|
/// Encode the six Owner facts with the existing bounded value encoder. No
/// policy/target bodies or grant are manufactured in this physical bridge.
fn publisher_authorize(
  child : StoredPublisher,
  fact : @publication.PublicationPublisherAuthorization,
) -> Bool {
  let writer = @encode.writer(8192, 7, 1) catch {
    _ => {
      child.unknown = true
      return false
    }
  }
  let wire = try {
    @encode.begin_object(writer)
    for
      (name, text) in [
        ("stage", fact.stage),
        ("namespace_id", fact.namespace_id),
        ("authority_scope_cid", fact.authority_scope_cid),
        ("run_definition_cid", fact.run_definition_cid),
        ("publication_request_cid", fact.publication_request_cid),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    @encode.key(writer, "public_index_entry_cid")
    match fact.public_index_entry_cid {
      Some(cid) => @encode.string_value(writer, cid)
      None => @encode.null_value(writer)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => {
      child.unknown = true
      return false
    }
  }
  let bytes = @utf8.encode(wire)
  if physical_publisher_begin(child.physical, bytes.length()) != 0 {
    child.unknown = true
    return false
  }
  let mut index = 0
  while index < bytes.length() {
    let length = (bytes.length() - index).min(16384)
    if physical_publisher_copy(
        child.physical,
        index,
        journal_bytes_offset(bytes) + index,
        length,
      ) !=
      length {
      child.unknown = true
      return false
    }
    index += length
  }
  let code = physical_publisher_finish(child.physical)
  if code != 0 && code != -1 {
    child.unknown = true
  }
  code == 0
}

///|
pub fn reserve_publisher(
  nonce : Int64,
  parent : Int,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publication_preflights.get(parent)
    is Some({ closing: false, produced: true, preflight: Some(_), .. }) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) ||
    value.native_commands
    .values()
    .any(child => child.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(child => child.physical_ticket == physical_ticket) {
    return -3
  }
  // Hold bounded encoder text/UTF-8 and the physical collector together in the
  // existing pool. No raw Wasm pointer or unreserved callback payload escapes.
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 16384, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.publishers[handle] = {
    parent,
    physical: physical_ticket,
    slot,
    borrow,
    configuration: 0,
    store: "",
    port: None,
    closing: false,
    unknown: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn install_publisher(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publishers.get(handle) is Some(child) &&
    value.publication_preflights.get(child.parent)
    is Some({ closing: false, preflight: Some(preflight), compute, .. }) &&
    value.run_configurations.get(current_configuration) is Some(_) else {
    return -2
  }
  if value.closing || value.runtime_closing || child.closing {
    return -5
  }
  if child.port is Some(_) {
    return -3
  }
  // Follow the original Run's retained configuration. A newer current Account
  // may revoke publication, but cannot supply or replace its original policy.
  guard value.computes.get(compute) is Some(compute) &&
    stored_compute_original_run(value, compute) is Some(original_run) &&
    value.run_configurations.get(original_run.configuration) is Some(original) else {
    return -36
  }
  let borrow = match child.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) else { return -31 }
  let store = if original.sdk is Some(sdk) {
    guard @decode.closed_object(cursor, []) is Ok(_) else { return -31 }
    sdk.store_authority_cid
  } else {
    guard @decode.closed_object(cursor, ["store_authority_cid"]) is Ok(object) &&
      required_text(object, "store_authority_cid") is Some(store) else {
      return -31
    }
    store
  }
  child.configuration = current_configuration
  child.unknown = false
  match
    @local_run.install_local_preflight_publisher_port(
      preflight,
      store,
      original.account,
      () => value.run_configurations.get(child.configuration).unwrap().account,
      () => publisher_current(value, child),
      fact => publisher_authorize(child, fact),
    ) {
    Ok(port) => {
      // Installation is not an authorization grant.
      child.port = Some(port)
      child.store = store
      0
    }
    Err(issue) =>
      if child.unknown {
        -36
      } else {
        match issue {
          AccessDenied => -35
          NotCurrent => -32
          _ => -31
        }
      }
  }
}

///|
/// Authorization only. Even return_committed permission is not a durable
/// Store acknowledgement, public Run admission, or execution/retry permission.
pub fn authorize_publisher(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
  stage : Int,
  publication : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publishers.get(handle) is Some(child) &&
    child.port is Some(port) &&
    value.publication_preflights.get(child.parent) is Some(parent) &&
    parent.preflight is Some(preflight) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || value.runtime_closing || child.closing || parent.closing {
    return -5
  }
  if !stored_preflight_current(value, parent, current.account) {
    return -32
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  let (selected_stage, index) = match stage {
    0 if publication == 0 => (@publication.Request, None)
    1 | 2 => {
      guard value.publications.get(publication)
        is Some(
          {
            preflight: original_parent,
            closing: false,
            commit_finished: true,
            commit_index: Some(index),
            ..
          }
        ) &&
        original_parent == child.parent else {
        return -2
      }
      (
        if stage == 1 {
          @publication.Commit
        } else {
          @publication.ReturnCommitted
        },
        Some(index),
      )
    }
    _ => return -3
  }
  child.configuration = current_configuration
  child.unknown = false
  let (request, attempt) = @local_run.local_publication_preflight_contracts(
    preflight,
  )
  let result = port.check(request, attempt, child.store, selected_stage, index)
  if child.unknown {
    return -36
  }
  match result {
    Ok(_) => 0
    Err(AccessDenied) => -35
    Err(NotCurrent) => -32
    Err(_) => -31
  }
}

///|
pub fn close_publisher(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publishers.get(handle) is Some(child) else {
    return -2
  }
  child.closing = true
  if value.publications
    .values()
    .any(record => {
      (
        record.observation_publisher == Some(handle) &&
        record.observation_input is Some(_)
      ) ||
      (
        record.lookup_publisher == Some(handle) &&
        record.lookup_input is Some(_)
      )
    }) {
    return -9
  }
  let code = status(@buffers.close_buffer(value.pool, child.slot))
  if code != 0 {
    return code
  }
  let code = match child.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if code == 0 {
    value.publishers.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  code
}
