///|
/// A read-only binding of the original confirmed filesystem Sealed record.
/// This transport pins the original parents; it does not commit or authorize.
priv struct StoredPayloadBinding {
  parent : Int
  revision : Int
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut file_binding : @publication.PublicationContract?
  mut produced : Bool
  mut closing : Bool
}

///|
fn payload_binding_parent(
  value : Instance,
  parent : Int,
) -> StoredPayloadRecord? {
  guard value.payload_records.get(parent)
    is Some({ confirmed: true, closing: false, record: Some(original), .. } as record) &&
    @payload.publication_payload_record_state(original) is Sealed &&
    @payload.publication_payload_record_generation(original) is Some(_) &&
    @payload.publication_payload_record_ownership(original) is Some(_) &&
    @payload.publication_payload_record_opaque_ownership(original) is None else {
    return None
  }
  Some(record)
}

///|
fn payload_binding_wire_limit(value : Instance, record : StoredPayloadRecord) -> Int {
  guard record.source is LiveRequest &&
    value.payload_requests.get(record.request) is Some(request) &&
    value.publications.get(request.publication) is Some(publication) &&
    publication.publications.get(request.index) is Some(result) &&
    @local_run.local_result_publication_schema_bytes(result) is Some(bytes) &&
    bytes > 0 && bytes <= 65536 - 2048 else {
    return 65536
  }
  // The only variable fields are names already counted as escaped keys in the
  // original canonical schema. The other properties, CIDs and counts fit 2 KiB.
  // The Common constructor still uses its complete semantic validation bounds.
  2048 + bytes
}

///|
pub fn payload_binding_transport_limit(nonce : Int64, parent : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    payload_binding_parent(value, parent) is Some(record) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  payload_binding_wire_limit(value, record)
}

///|
pub fn reserve_payload_binding(
  nonce : Int64,
  parent : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    payload_binding_parent(value, parent) is Some(record) &&
    record.record is Some(original) else {
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
    @buffers.reserve_output_buffer(
      value.pool,
      payload_binding_wire_limit(value, record),
      physical_copy_bytes,
      () => physical_input_cleanup(physical_ticket) == 0,
    ) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  value.payload_bindings[handle] = {
    parent,
    revision: @payload.publication_payload_record_revision(original),
    slot,
    invoked: false,
    file_binding: None,
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
    is Some({ closing: false, .. } as preflight) &&
    request.index >= 0 &&
    request.index < publication_result_count(publication) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  child.invoked = true
  let binding = match preflight.origin {
    ComputePublicationPreflight({ prepared: Some(prepared), .. }) =>
      @local_run.issue_local_preflight_sealed_result_binding(
        prepared, request.index, publication.publications[request.index], original,
        current.account, 65536, 4096, 64,
      ).map_err(_ => -32)
    FilePublicationPreflight(file) =>
      with_sdk_file_payload_result(value, publication, file, request.index, current.account,
        (prepared, result, recheck) => @local_run.issue_local_captured_task_sealed_result_binding(
          prepared, request.index, result, original,
          { max_results: value.workspace_slots, max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, },
          recheck,
        ))
    SavedEffectPublicationPreflight({ prepared: Some(prepared), .. }) =>
      prepared.bind_sealed_payload(request.index, original).map_err(_ => -32)
    _ => Err(-2)
  }
  let binding = match binding {
    Ok(value) => value
    Err(code) => return code
  }
  let wire = @publication.publication_contract_json(binding)
  if publication.file is Some(file) {
    if child.closing || parent.closing { return -5 }
    let checked = sdk_file_capture_publication_current(value, publication, file, current.account)
    if checked != 0 { return checked }
    child.file_binding = Some(binding)
  }
  if publication.saved_effect is Some(effect) {
    let code = saved_effect_publication_preflight_current(value, effect, current.account)
    if code != 0 { return code }
    child.file_binding = Some(binding)
  }
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
