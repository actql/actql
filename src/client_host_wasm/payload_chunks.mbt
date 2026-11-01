///|
priv enum StoredPayloadReplayIssue {
  Output(@host.PublicationOutputExportIssue)
  Buffer(@buffers.BufferIssue)
}

///|
fn payload_replay_issue_code(issue : StoredPayloadReplayIssue) -> Int {
  match issue {
    Output(issue) => if issue is InvalidState { -33 } else { -32 }
    Buffer(issue) => issue_code(issue)
  }
}

///|
/// Physical custody of one bounded replay chunk. The existing completed-output
/// Owner determines bytes and EOF; this handle cannot seal or publish a payload.
priv struct StoredPayloadChunk {
  request : Int
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut pending : Bool
  mut produced : Bool
  mut final_chunk : Bool
  mut closing : Bool
}

///|
fn payload_replay_current(
  value : Instance,
  record : StoredPayloadRequest,
  current_configuration : Int,
  pending_confirmation? : Bool = false,
) -> Bool {
  guard record.produced &&
    record.request is Some(_) &&
    value.publications.get(record.publication) is Some(parent) &&
    (pending_confirmation || !parent.closing) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return false
  }
  publication_current(value, parent, current.account, pending_confirmation~)
}

///|
pub fn start_payload_replay(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_requests.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
    value.publication_preflights.get(parent.preflight)
    is Some({ preflight: Some(preflight), .. }) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing || parent.closing {
    return -5
  }
  guard record.produced && record.request is Some(request) else { return -33 }
  if !payload_replay_current(value, record, current_configuration) {
    return -32
  }
  if record.replay is Some(_) {
    return 0
  }
  match
    @local_run.prepare_local_preflight_payload_replay(
      preflight,
      record.index,
      parent.publications[record.index],
      request,
      current.account,
    ) {
    Ok(replay) => {
      record.replay = Some(replay)
      0
    }
    Err(_) => -32
  }
}

///|
pub fn reserve_payload_chunk(
  nonce : Int64,
  request : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_requests.get(request) is Some(record) &&
    value.publications.get(record.publication) is Some({ closing: false, .. }) &&
    record.replay is Some(_) else {
    return -2
  }
  if value.closing ||
    value.runtime_closing ||
    record.closing ||
    record.replay_ended {
    return -5
  }
  if record.replay_issue is Some(issue) {
    return payload_replay_issue_code(issue)
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.payload_chunks.values().any(chunk => chunk.request == request) ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) ||
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
  value.payload_chunks[handle] = {
    request,
    slot,
    invoked: false,
    pending: false,
    produced: false,
    final_chunk: false,
    closing: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_payload_chunk(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_chunks.get(handle) is Some(chunk) &&
    value.payload_requests.get(chunk.request) is Some(record) &&
    record.replay is Some(replay) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing || chunk.closing {
    return -5
  }
  // The retained request and a previously produced chunk are not permanent
  // authorization. Recheck the original Run/Source and publication custody.
  if !payload_replay_current(value, record, current_configuration) {
    return -32
  }
  if chunk.produced {
    return 0
  }
  if chunk.invoked || chunk.pending {
    return -33
  }
  if record.replay_issue is Some(issue) {
    return payload_replay_issue_code(issue)
  }
  chunk.invoked = true
  chunk.pending = true
  let next = match replay.next() {
    Err(issue) => Err(issue)
    Ok(Some(wire)) => Ok((wire, false))
    Ok(None) => replay.finish().map(wire => (wire, true))
  }
  match next {
    Err(issue) => record.replay_issue = Some(Output(issue))
    Ok((wire, final_chunk)) =>
      match
        @buffers.supply_buffer_output(
          value.pool,
          chunk.slot,
          @utf8.encode(wire),
        ) {
        Err(issue) => record.replay_issue = Some(Buffer(issue))
        Ok(_) => {
          chunk.produced = true
          chunk.final_chunk = final_chunk
          record.replay_ended = final_chunk
        }
      }
  }
  chunk.pending = false
  match record.replay_issue {
    Some(issue) => payload_replay_issue_code(issue)
    None => 0
  }
}

///|
pub fn validate_payload_chunk(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_chunks.get(handle) is Some(chunk) &&
    value.payload_requests.get(chunk.request) is Some(record) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing || chunk.closing {
    return -5
  }
  if !payload_replay_current(value, record, current_configuration) {
    return -32
  }
  if !chunk.produced || chunk.pending {
    -33
  } else {
    0
  }
}

///|
pub fn payload_chunk_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_chunks.get(handle) is Some(chunk) &&
    chunk.produced &&
    !chunk.closing else {
    return -33
  }
  @buffers.buffer_length(value.pool, chunk.slot).unwrap_or(-33)
}

///|
/// This final marker proves only exact original Result replay completion.
pub fn payload_chunk_final(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_chunks.get(handle) is Some(chunk) &&
    chunk.produced &&
    !chunk.closing else {
    return -33
  }
  if chunk.final_chunk {
    1
  } else {
    0
  }
}

///|
pub fn close_payload_chunk(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_chunks.get(handle) is Some(chunk) else {
    return -2
  }
  chunk.closing = true
  if chunk.pending {
    return -33
  }
  let code = status(@buffers.close_buffer(value.pool, chunk.slot))
  if code == 0 {
    value.payload_chunks.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  code
}
