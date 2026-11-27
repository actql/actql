///|
priv enum StoredPayloadReplayIssue {
  Output(@host.PublicationOutputExportIssue)
  Buffer(@buffers.BufferIssue)
  Current(Int)
}

///|
fn payload_replay_issue_code(issue : StoredPayloadReplayIssue) -> Int {
  match issue {
    Output(issue) => if issue is InvalidState { -33 } else { -32 }
    Buffer(issue) => issue_code(issue)
    Current(code) => code
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
    value.publication_preflights.get(parent.preflight) is Some(preflight) &&
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
  if record.replay_issue is Some(issue) { return payload_replay_issue_code(issue) }
  if record.replay is Some(_) {
    return 0
  }
  let replay = match preflight.origin {
    ComputePublicationPreflight({ prepared: Some(original), .. }) =>
      @local_run.prepare_local_preflight_payload_replay(
        original, record.index, parent.publications[record.index], request, current.account,
      ).map_err(_ => -32)
    FilePublicationPreflight(file) =>
      with_sdk_file_payload_result(value, parent, file, record.index, current.account,
        (original, result, recheck) => @local_run.prepare_local_captured_task_payload_replay(
          original, record.index, result, request, recheck,
        ))
    SavedEffectPublicationPreflight({ prepared: Some(original), .. }) => {
      guard original.snapshot(record.index) is Some(snapshot) else { return -32 }
      if record.replay_capacity is Some(_) { return -33 }
      let (bytes, _, depth) = @publication.captured_result_snapshot_payload_extent(snapshot)
      let chunk = Int::min(bytes, 65536)
      guard chunk > 0 &&
        @host.client_protocol_metadata_construction_bytes(
          chunk, 64L + 8L * depth.to_int64(), copies=2,
        ) is Some((working, _)) &&
        @resources.reserve_capacity(value.root, 0L, working) is Ok(capacity) else {
        return -4
      }
      record.replay_capacity = Some(capacity)
      @host.prepare_captured_snapshot_payload_replay(snapshot, chunk).map_err(_ => -32)
    }
    _ => Err(-2)
  }
  match replay {
    Ok(replay) => {
      record.replay = Some(replay)
      if parent.file is Some(file) {
        let code = if record.closing { -5 } else {
          sdk_file_capture_publication_current(value, parent, file, current.account)
        }
        if code != 0 {
          record.replay_issue = Some(Current(code))
          return code
        }
      }
      if parent.saved_effect is Some(effect) {
        let code = saved_effect_publication_preflight_current(value, effect, current.account)
        if code != 0 {
          record.replay_issue = Some(Current(code))
          return code
        }
      }
      0
    }
    Err(code) => code
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
    record.request is Some(original) &&
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
  // A replay chunk is bounded by both the existing chunk ceiling and the
  // measured size of the entire original payload behind this request.
  let limit = Int64::min(
    65536L, @payload.publication_payload_request_max_bytes(original),
  ).to_int()
  let slot = match
    @buffers.reserve_output_buffer(value.pool, limit, physical_copy_bytes, () => {
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
    Ok((wire, final_chunk)) => {
      if value.publications.get(record.publication) is Some({ file: Some(file), .. } as parent) {
        let code = if record.closing || chunk.closing { -5 } else {
          match value.run_configurations.get(current_configuration) {
            Some(current) => sdk_file_capture_publication_current(value, parent, file, current.account)
            None => -35
          }
        }
        if code != 0 { record.replay_issue = Some(Current(code)) }
      }
      if value.publications.get(record.publication) is Some({ saved_effect: Some(_), .. }) &&
        !payload_replay_current(value, record, current_configuration) {
        record.replay_issue = Some(Current(-32))
      }
      if record.replay_issue is None {
        match @buffers.supply_buffer_output(value.pool, chunk.slot, @utf8.encode(wire)) {
          Err(issue) => record.replay_issue = Some(Buffer(issue))
          Ok(_) => {
            chunk.produced = true
            chunk.final_chunk = final_chunk
            record.replay_ended = final_chunk
          }
        }
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
