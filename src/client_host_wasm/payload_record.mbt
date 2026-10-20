///|
priv enum StoredPayloadRecordSource {
  LiveRequest
  SavedResult(StoredSubmissionProjection, StoredSavedResultRead)
}

///|
/// One original Core Intent and its physical write responsibility. The existing
/// payload Owner owns the record; this bridge adds no Run or recovery state.
priv struct StoredPayloadRecord {
  request : Int
  source : StoredPayloadRecordSource
  mut saved_row : (Int64, Bytes)?
  mut restore_invoked : Bool
  mut pending : Bool
  slot : @buffers.BufferSlot
  mut record : @payload.PublicationPayloadRecord?
  mut produced : Bool
  mut begun : Bool
  mut confirmed : Bool
  mut closing : Bool
}

///|
#export_name("actql_payload_record_reserve")
pub fn reserve_payload_record(
  nonce : Int64,
  request : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) else { return -2 }
  let source = match value.payload_requests.get(request) {
    Some({ produced: true, request: Some(_), closing: false, publication, .. }) => {
      guard value.publications.get(publication) is Some({ closing: false, .. }) else {
        return -2
      }
      LiveRequest
    }
    _ => {
      guard saved_result_export_parent(value, request) is Some((parent, saved)) else {
        return -2
      }
      SavedResult(parent, saved)
    }
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.payload_records.values().any(record => record.request == request) ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(record => record.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(record => record.physical_ticket == physical_ticket) ||
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
  value.payload_records[handle] = {
    request,
    source,
    saved_row: None,
    restore_invoked: false,
    pending: false,
    slot,
    record: None,
    produced: false,
    begun: false,
    confirmed: false,
    closing: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
fn payload_record_current(
  value : Instance,
  record : StoredPayloadRecord,
  current_configuration : Int,
  pending_confirmation? : Bool = false,
) -> Bool {
  if record.source is SavedResult(_, _) {
    return saved_payload_record_current(value, record, current_configuration)
  }
  match value.payload_requests.get(record.request) {
    Some(request) =>
      payload_replay_current(
        value,
        request,
        current_configuration,
        pending_confirmation~,
      )
    None => false
  }
}

///|
#export_name("actql_payload_record_produce")
pub fn produce_payload_record(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(handle) is Some(record) else {
    return -2
  }
  if record.source is SavedResult(_, _) {
    return produce_saved_payload_record(value, record, current_configuration)
  }
  guard value.payload_requests.get(record.request)
    is Some({ closing: false, request: Some(request), .. }) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing {
    return -5
  }
  if !payload_record_current(value, record, current_configuration) {
    return -32
  }
  if record.produced {
    return 0
  }
  if record.record is None {
    record.record = Some(@payload.prepare_publication_payload_record(request))
  }
  let wire = match
    @payload.publication_payload_record_durable_json(record.record.unwrap()) {
    Ok(wire) => wire
    Err(_) => return -34
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    record.produced = true
  }
  result
}

///|
#export_name("actql_payload_record_validate")
pub fn validate_payload_record(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(handle) is Some(record) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if !record.produced {
    return -33
  }
  if payload_record_current(value, record, current_configuration) {
    0
  } else {
    -32
  }
}

///|
#export_name("actql_payload_record_begin")
pub fn begin_payload_record(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(handle) is Some(original) &&
    original.source is LiveRequest else {
    return -2
  }
  let result = validate_payload_record(nonce, handle, current_configuration)
  if result != 0 {
    return result
  }
  let record = selected(nonce).unwrap().payload_records.get(handle).unwrap()
  // Repeating begin is never permission to repeat the physical CAS. Lookup and
  // confirmation retain this original handle after a lost acknowledgement.
  if record.begun {
    return -33
  }
  record.begun = true
  0
}

///|
/// The trusted Host supplies an actual read from the original physical Store.
/// Input bytes are read synchronously; no cursor or input loan escapes this call.
#export_name("actql_payload_record_confirm")
pub fn confirm_payload_record(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(handle) is Some(record) &&
    record.record is Some(original) &&
    value.copies.get(input) is Some((slot, _)) else {
    return -2
  }
  if !record.produced || !record.begun {
    return -33
  }
  // A pending write may be resolved while its bridge is closing. It still needs
  // current original Run/Source authorization; closure cannot supply permission.
  if !payload_record_current(
      value,
      record,
      current_configuration,
      pending_confirmation=true,
    ) {
    return -32
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "store_authority_cid", "material_generation_cid", "physical_revision", "record_json",
    ])
    is Ok(object) &&
    required_text(object, "store_authority_cid") is Some(store) &&
    required_text(object, "material_generation_cid") is Some(material) &&
    required_int32(object, "physical_revision") is Some(revision) &&
    required_text(object, "record_json") is Some(wire) else {
    return -31
  }
  let durable = match
    @payload.admit_durable_publication_payload_record(@utf8.encode(wire)) {
    Ok(durable) => durable
    Err(_) => return -31
  }
  match
    @payload.confirm_initial_publication_payload_record(
      original,
      store,
      material,
      revision.to_int64(),
      durable,
    ) {
    Err(_) => -32
    Ok(_) => {
      record.confirmed = true
      0
    }
  }
}

///|
#export_name("actql_payload_record_length")
pub fn payload_record_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(handle) is Some(record) else {
    return -2
  }
  if !record.produced || record.closing {
    return -33
  }
  @buffers.buffer_length(value.pool, record.slot).unwrap_or(-33)
}

///|
#export_name("actql_payload_record_close")
pub fn close_payload_record(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if record.pending {
    return -9
  }
  if value.payload_reservations.values().any(child => child.parent == handle) ||
    value.payload_writings.values().any(child => child.parent == handle) ||
    value.payload_allocations.values().any(child => child.parent == handle) ||
    value.payload_names.values().any(child => child.parent == handle) ||
    value.payload_bindings.values().any(child => child.parent == handle) ||
    value.commit_exports
    .values()
    .any(child => {
      match child.sdk_payload_record {
        Some((original, _, _)) => original == handle
        None => false
      }
    }) {
    return -9
  }
  if record.begun && !record.confirmed {
    return -9
  }
  let result = status(@buffers.close_buffer(value.pool, record.slot))
  if result == 0 {
    value.payload_records.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
