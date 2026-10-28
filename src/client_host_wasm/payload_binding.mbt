///|
/// A read-only binding of the original confirmed filesystem Sealed record.
/// This transport pins the original parents; it does not commit or authorize.
priv struct StoredPayloadBinding {
  parent : Int
  revision : Int
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
  mut closing : Bool
}

///|
pub fn reserve_payload_binding(
  nonce : Int64,
  parent : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(parent)
    is Some({ confirmed: true, closing: false, record: Some(original), .. }) &&
    @payload.publication_payload_record_state(original) is Sealed &&
    @payload.publication_payload_record_generation(original) is Some(_) &&
    @payload.publication_payload_record_ownership(original) is Some(_) &&
    @payload.publication_payload_record_opaque_ownership(original) is None else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.payload_bindings.values().any(child => child.parent == parent) ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(child => child.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(child => child.physical_ticket == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) {
    return -3
  }
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 65536, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  value.payload_bindings[handle] = {
    parent,
    revision: @payload.publication_payload_record_revision(original),
    slot,
    invoked: false,
    produced: false,
    closing: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_payload_binding(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_bindings.get(handle) is Some(child) &&
    value.payload_records.get(child.parent) is Some(parent) &&
    parent.record is Some(original) else {
    return -2
  }
  if value.closing || value.runtime_closing || child.closing || parent.closing {
    return -5
  }
  if !parent.confirmed ||
    !(@payload.publication_payload_record_state(original) is Sealed) ||
    @payload.publication_payload_record_generation(original) is None ||
    @payload.publication_payload_record_revision(original) != child.revision {
    return -32
  }
  let saved_binding = if parent.source is SavedResult(_, _) {
    match saved_payload_binding(value, parent, current_configuration) {
      Ok(binding) => Some(binding)
      Err(code) => return code
    }
  } else {
    if !payload_record_current(value, parent, current_configuration) {
      return -32
    }
    None
  }
  if child.produced {
    return 0
  }
  if child.invoked {
    return -33
  }
  if saved_binding is Some(binding) {
    child.invoked = true
    let code = status(
      @buffers.supply_buffer_output(
        value.pool,
        child.slot,
        @utf8.encode(@publication.publication_contract_json(binding)),
      ),
    )
    if code == 0 {
      child.produced = true
    }
    return code
  }
  guard value.payload_requests.get(parent.request) is Some(request) &&
    value.publications.get(request.publication) is Some(publication) &&
    value.publication_preflights.get(publication.preflight)
    is Some({ closing: false, preflight: Some(preflight), .. }) &&
    request.index >= 0 &&
    request.index < publication.publications.length() &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  child.invoked = true
  let binding = match
    @local_run.issue_local_preflight_sealed_result_binding(
      preflight,
      request.index,
      publication.publications[request.index],
      original,
      current.account,
      65536,
      4096,
      64,
    ) {
    Ok(binding) => binding
    Err(_) => return -32
  }
  let wire = @publication.publication_contract_json(binding)
  let result = status(
    @buffers.supply_buffer_output(value.pool, child.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    child.produced = true
  }
  result
}

///|
pub fn validate_payload_binding(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_bindings.get(handle) is Some(child) &&
    value.payload_records.get(child.parent) is Some(parent) &&
    parent.record is Some(original) else {
    return -2
  }
  if value.closing || value.runtime_closing || child.closing || parent.closing {
    return -5
  }
  if !child.produced {
    return -33
  }
  if parent.confirmed &&
    @payload.publication_payload_record_state(original) is Sealed &&
    @payload.publication_payload_record_generation(original) is Some(_) &&
    @payload.publication_payload_record_revision(original) == child.revision &&
    payload_record_current(value, parent, current_configuration) {
    0
  } else {
    -32
  }
}

///|
pub fn payload_binding_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_bindings.get(handle) is Some(child) else {
    return -2
  }
  if !child.produced || child.closing {
    return -33
  }
  @buffers.buffer_length(value.pool, child.slot).unwrap_or(-33)
}

///|
pub fn close_payload_binding(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_bindings.get(handle) is Some(child) else {
    return -2
  }
  child.closing = true
  let result = status(@buffers.close_buffer(value.pool, child.slot))
  if result == 0 {
    value.payload_bindings.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
