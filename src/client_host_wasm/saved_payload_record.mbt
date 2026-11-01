///|
fn saved_payload_record_context(
  value : Instance,
  record : StoredPayloadRecord,
  configuration : Int,
  selection? : OriginalSDKReadContext? = None,
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
  match selection {
    Some(context) => {
      // Only the closed finish caller supplies its SAME context immediately
      // after check_current. Reuse immutable selection, never an Allow or a
      // successful check across an IO/stop callback or another invocation.
      guard physical_equal(context.current, current) &&
        saved.source is Some(source) &&
        physical_equal(context.source, source) &&
        saved.finite is Some(finite) &&
        physical_equal(context.finite, finite) &&
        saved.owner is Some(owner) &&
        physical_equal(context.owner, owner) &&
        saved.view is Some(view) &&
        physical_equal(context.view, view) &&
        context.result_name == saved.result_name else {
        return Err(-32)
      }
      // Keep the original view/observed-child liveness check here even though
      // this private handoff does not repeat its completed physical row scan.
      if owner.finish_observed_commit(view) is Err(_) {
        return Err(-32)
      }
    }
    None =>
      match validate_saved_result_read(value, parent, current) {
        Err(code) => return Err(code)
        Ok(_) => ()
      }
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
  selection? : OriginalSDKReadContext? = None,
) -> Result[@publication.PublicationContract?, Int] {
  let (_, saved, current) = match
    saved_payload_record_context(value, record, configuration, selection~) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  guard saved.source is Some(source) &&
    saved.owner is Some(owner) &&
    saved.view is Some(view) else {
    return Err(-32)
  }
  let mut binding = None
  if record.record is Some(original) {
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
    guard record.saved_allocation
      is Some((allocation_revision, allocation_body, _)) else {
      return Err(-32)
    }
    match
      sdk_run_journal_port(
        value, current, 1, "publication_payload_allocation", key,
      ) {
      Ok(Some(row)) if row.key == key &&
        row.revision == allocation_revision &&
        row.body == allocation_body => ()
      Err(code) => return Err(code)
      _ => return Err(-41)
    }
    // Consume this invocation's original validator result once, after the
    // physical row fences. It is not cached across calls or Store snapshots.
    binding = Some(
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
        Ok(value) => value
      },
    )
  }
  if record.closing {
    Err(-5)
  } else {
    Ok(binding)
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
  if record.restore_invoked && !record.confirmed {
    return Err(-33)
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
    let allocation_row = match
      sdk_run_journal_port(
        value, current, 1, "publication_payload_allocation", key,
      ) {
      Ok(Some(row)) if row.key == key &&
        row.revision >= 0L &&
        row.body.length() <= 65536 => row
      Err(code) => return Err(code)
      _ => return Err(-41)
    }
    let allocation = match
      @payload.admit_publication_payload_allocation(
        @payload.publication_payload_record_request(original),
        allocation_row.body,
      ) {
      Ok(value) => value
      Err(_) => return Err(-32)
    }
    // The allocation owns its directory, while the Sealed record owns the
    // finalized payload file. Each original is checked separately by the
    // physical reader; directory and file inodes must not be conflated.
    if @payload.publication_payload_allocation_ownership(allocation) is None {
      return Err(-32)
    }
    record.saved_allocation = Some(
      (allocation_row.revision, allocation_row.body, allocation),
    )
    // Read-only observation of an existing Sealed state, not a write/COMMIT ACK.
    record.confirmed = true
  }
  observe_saved_payload_record(value, record, configuration).map(_ => ())
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
  selection? : OriginalSDKReadContext? = None,
) -> Result[@publication.PublicationContract, Int] {
  if !record.confirmed || record.pending || record.closing {
    return Err(-32)
  }
  record.pending = true
  let result = observe_saved_payload_record(
    value,
    record,
    configuration,
    selection~,
  )
  record.pending = false
  if record.closing {
    return Err(-5)
  }
  match result {
    Ok(Some(binding)) => Ok(binding)
    Ok(None) => Err(-32)
    Err(code) => Err(code)
  }
}

///|
fn saved_payload_names_json(
  record : StoredPayloadRecord,
) -> Result[String, Int] {
  guard record.record is Some(original) &&
    record.saved_allocation is Some((_, _, allocation)) &&
    @payload.publication_payload_allocation_ownership(allocation)
    is Some(directory) else {
    return Err(-32)
  }
  let request = @payload.publication_payload_record_request(original)
  try {
    let writer = @encode.writer(1024, 32, 1)
    @encode.begin_object(writer)
    for
      (name, text) in [
        ("staging_name", @payload.publication_payload_staging_name(request)),
        ("object_name", @payload.publication_payload_object_name(request)),
        (
          "material_generation_cid",
          @payload.publication_payload_material_identity(request),
        ),
        (
          "store_authority_cid",
          @payload.publication_payload_request_store_authority(request),
        ),
        (
          "record_revision",
          @payload.publication_payload_record_revision(original).to_string(),
        ),
        ("request_cid", @payload.publication_payload_request_identity(request)),
        (
          "allocation_name",
          @payload.publication_payload_allocation_name(allocation),
        ),
        ("allocation_device", directory.device.to_string()),
        ("allocation_inode", directory.inode.to_string()),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(-34)
  }
}
