///|
fn saved_payload_record_context(
  value : Instance,
  record : StoredPayloadRecord,
  configuration : Int,
) -> Result[
  (StoredSubmissionProjection, StoredSavedResultRead, StoredRunConfiguration),
  Int,
] {
  guard record.source is SavedResult(parent, saved) &&
    saved_result_export_parent(value, record.request)
    is Some((actual, original)) &&
    physical_equal(parent, actual) &&
    physical_equal(saved, original) &&
    parent.configuration == configuration &&
    value.run_configurations.get(configuration) is Some(current) else {
    return Err(-2)
  }
  if value.closing || value.runtime_closing || record.closing {
    return Err(-5)
  }
  match validate_saved_result_read(value, parent, current) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  if record.closing || parent.output_closed {
    return Err(-5)
  }
  Ok((parent, saved, current))
}

///|
fn observe_saved_payload_record(
  value : Instance,
  record : StoredPayloadRecord,
  configuration : Int,
) -> Result[Unit, Int] {
  let (_, saved, current) = match
    saved_payload_record_context(value, record, configuration) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  guard saved.source is Some(source) &&
    saved.owner is Some(owner) &&
    saved.view is Some(view) else {
    return Err(-32)
  }
  if record.record is Some(original) {
    match
      @local_run.validate_local_sdk_saved_payload_record(
        source,
        current.account,
        owner,
        view,
        saved.result_name,
        original,
      ) {
      Err(_) => return Err(-32)
      Ok(_) => ()
    }
    guard record.saved_row is Some((revision, body)) else { return Err(-32) }
    let key = @payload.publication_payload_material_identity(
      @payload.publication_payload_record_request(original),
    )
    match sdk_run_journal_port(value, current, 1, "payload_record", key) {
      Ok(Some(row)) if row.key == key &&
        row.revision == revision &&
        row.body == body => ()
      Err(code) => return Err(code)
      _ => return Err(-41)
    }
  }
  if record.closing {
    Err(-5)
  } else {
    Ok(())
  }
}

///|
fn saved_payload_record_current(
  value : Instance,
  record : StoredPayloadRecord,
  configuration : Int,
) -> Bool {
  if record.pending {
    return false
  }
  record.pending = true
  let result = observe_saved_payload_record(value, record, configuration)
  record.pending = false
  result is Ok(_) && !record.closing
}

///|
fn load_saved_payload_record(
  value : Instance,
  record : StoredPayloadRecord,
  configuration : Int,
) -> Result[Unit, Int] {
  let (_, saved, current) = match
    saved_payload_record_context(value, record, configuration) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  guard saved.source is Some(source) &&
    saved.owner is Some(owner) &&
    saved.view is Some(view) else {
    return Err(-32)
  }
  if record.record is None {
    if record.restore_invoked {
      return Err(-33)
    }
    record.restore_invoked = true
    let material = match
      owner.observed_result_read_materials(view, saved.result_name, 8) {
      Ok(value) => value
      Err(_) => return Err(-32)
    }
    let key = material.read.material_generation_cid
    let row = match
      sdk_run_journal_port(value, current, 1, "payload_record", key) {
      Ok(Some(row)) if row.key == key &&
        row.revision >= 0L &&
        row.body.length() <= 65536 => row
      Err(code) => return Err(code)
      _ => return Err(-41)
    }
    // Retain the physical row before admission; any failure stays on this same
    // child until explicit cleanup, never another read/prepare/reseal attempt.
    record.saved_row = Some((row.revision, row.body))
    let (original, _) = match
      @local_run.restore_local_sdk_saved_payload_record(
        source,
        current.account,
        owner,
        view,
        saved.result_name,
        row.body,
      ) {
      Ok(value) => value
      Err(_) => return Err(-32)
    }
    if row.revision !=
      @payload.publication_payload_record_revision(original).to_int64() {
      return Err(-41)
    }
    record.record = Some(original)
    // Read-only observation of an existing Sealed state, not a write/COMMIT ACK.
    record.confirmed = true
  }
  observe_saved_payload_record(value, record, configuration)
}

///|
fn produce_saved_payload_record(
  value : Instance,
  record : StoredPayloadRecord,
  configuration : Int,
) -> Int {
  if record.pending || record.closing {
    return -5
  }
  record.pending = true
  let result = load_saved_payload_record(value, record, configuration)
  record.pending = false
  match result {
    Err(code) => return code
    Ok(_) => ()
  }
  if record.produced {
    return 0
  }
  let wire = match
    @payload.publication_payload_record_durable_json(record.record.unwrap()) {
    Ok(value) => value
    Err(_) => return -32
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  if code == 0 {
    record.produced = true
  }
  code
}

///|
fn saved_payload_binding(
  value : Instance,
  record : StoredPayloadRecord,
  configuration : Int,
) -> Result[@publication.PublicationContract, Int] {
  if !record.confirmed ||
    !saved_payload_record_current(value, record, configuration) {
    return Err(-32)
  }
  guard record.source is SavedResult(_, saved) &&
    saved.source is Some(source) &&
    saved.owner is Some(owner) &&
    saved.view is Some(view) &&
    record.record is Some(original) &&
    value.run_configurations.get(configuration) is Some(current) else {
    return Err(-2)
  }
  @local_run.validate_local_sdk_saved_payload_record(
    source,
    current.account,
    owner,
    view,
    saved.result_name,
    original,
  ).map_err(_ => -32)
}
