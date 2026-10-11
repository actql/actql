///|
/// A child of the exact acquisition/Compute custody. This is Source evidence,
/// not terminal Run publication or a new durable completion record.
priv struct StoredSourcePublication {
  compute : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut preparation : @local_run.LocalSourcePublicationPreparation?
  mut publication : @local_run.LocalSourcePublication?
  mut observed_at : String?
  mut invoked : Bool
  mut pending : Bool
  mut closing : Bool
  mut finished : Bool
  mut produced : Bool
  mut output_closed : Bool
  mut progress : (Bool, Int)?
}

///|
#export_name("actql_source_publication_reserve")
pub fn reserve_source_publication(
  nonce : Int64,
  compute : Int,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.computes.get(compute)
    is Some(
      {
        closing: false,
        outcome: Some(Ok(_)),
        host: Some(_),
        capture: Some(_),
        ..
      }
    ) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) {
    return -3
  }
  let handle = value.next_handle
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 65536, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.source_publications[handle] = {
    compute,
    borrow,
    slot,
    preparation: None,
    publication: None,
    observed_at: None,
    invoked: false,
    pending: false,
    closing: false,
    finished: false,
    produced: false,
    output_closed: false,
    progress: None,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
#export_name("actql_source_publication_prepare")
pub fn prepare_source_publication(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.source_publications.get(handle) is Some(record) &&
    value.computes.get(record.compute)
    is Some(
      { host: Some(host), capture: Some(capture), attempt, closing: false, .. }
    ) &&
    value.native_attempts.get(attempt) is Some(original) &&
    !original.closing &&
    value.native_sources.get(original.configuration)
    is Some({ outcome: Some(Ok(configuration)), .. }) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if record.preparation is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "observed_at", "max_work", "max_workspace_slots",
    ])
    is Ok(object) &&
    required_text(object, "observed_at") is Some(observed_at) &&
    required_int32(object, "max_work") is Some(max_work) &&
    required_int32(object, "max_workspace_slots") is Some(max_workspace_slots) else {
    return -31
  }
  let limits = result_export_limits()
  record.pending = true
  let preparation = @local_run.prepare_local_source_publication(
    configuration,
    host,
    capture,
    current.account,
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    max_work,
    max_workspace_slots,
  )
  record.pending = false
  match preparation {
    Err(_) => -32
    Ok(preparation) => {
      record.preparation = Some(preparation)
      record.observed_at = Some(observed_at)
      0
    }
  }
}

///|
#export_name("actql_source_publication_advance")
pub fn advance_source_publication(
  nonce : Int64,
  handle : Int,
  quantum : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.source_publications.get(handle) is Some(record) &&
    record.preparation is Some(preparation) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if record.pending || record.finished {
    return -33
  }
  record.pending = true
  let progress = preparation.advance(quantum)
  record.pending = false
  match progress {
    Err(_) => -32
    Ok(progress) => {
      record.progress = Some(progress)
      0
    }
  }
}

///|
#export_name("actql_source_publication_progress")
pub fn source_publication_progress(
  nonce : Int64,
  handle : Int,
  field : Int,
) -> Int64 {
  guard selected(nonce) is Some(value) &&
    value.source_publications.get(handle) is Some(record) &&
    record.preparation is Some(preparation) else {
    return -2L
  }
  if field == 2 {
    return preparation.work()
  }
  guard record.progress is Some((done, work)) else { return -33L }
  match field {
    0 => if done { 1L } else { 0L }
    1 => work.to_int64()
    _ => -3L
  }
}

///|
#export_name("actql_source_publication_finish")
pub fn finish_source_publication(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.source_publications.get(handle) is Some(record) &&
    record.preparation is Some(preparation) &&
    record.observed_at is Some(observed_at) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if record.produced {
    return 0
  }
  if record.pending || record.finished {
    return -33
  }
  guard record.progress is Some((true, _)) else { return -7 }
  record.finished = true
  record.pending = true
  let publication = preparation.finish(current.account, observed_at)
  record.pending = false
  let publication = match publication {
    Ok(publication) => publication
    Err(_) => return -32
  }
  record.publication = Some(publication)
  guard record.publication is Some(publication) else { return -33 }
  let logical = @local_run.local_source_publication_logical(publication)
  let evidence = @local_run.local_source_publication_evidence(publication)
  let writer = @encode.writer(65536, 3, 1) catch { _ => return -34 }
  let wire = try {
    @encode.begin_object(writer)
    for (name, fact) in [("logical", logical), ("evidence", evidence)] {
      @encode.key(writer, name)
      @encode.string_value(writer, @publication.run_evidence_value_json(fact))
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return -34
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
#export_name("actql_source_publication_length")
pub fn source_publication_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.source_publications.get(handle) is Some(record) else {
    return -2
  }
  match @buffers.buffer_length(value.pool, record.slot) {
    Some(length) => length
    None => -33
  }
}

///|
#export_name("actql_source_publication_close")
pub fn close_source_publication(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.source_publications.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if record.pending {
    return -33
  }
  if record.preparation is Some(preparation) {
    preparation.cancel() |> ignore
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  let result = match record.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if result == 0 {
    value.source_publications.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
