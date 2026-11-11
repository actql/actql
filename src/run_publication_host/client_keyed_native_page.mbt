///|
// Partial construction remains on the existing lookup before any callback can
// fail. The physical Source/RowRun still owns its read and cleanup duties.
priv struct ClientKeyedNativePageState {
  mut read : @execution.SuppliedRelationRead?
  mut capture : @row_host.RowKeyedSourceCapture?
  mut output : @execution.CompletedOutput?
  mut scan : @execution.CompletedRelationIdentityScan?
  mut receipt : @execution.CompletedRelationExportReceipt?
  mut result : ClientKeyedNativeCapturedPage?
}

///|
/// Immutable captured-page metadata only. It has no lookup/Source/Scope
/// backpointer and does not attest Journal COMMIT, adoption or physical ACK.
pub struct ClientKeyedNativeCapturedPage {
  batch_index : Int
  deadline_epoch_ms : Int64
  call_slot_cid : String
  batch_plan_cid : String
  activation_cid : String
  raw : @publication.PublicationContract
  raw_retention : @publication.PublicationContract
  event : @publication.PublicationContract
  adoption : @publication.PublicationContract
  logical_value_cid : String
  body : String
  schema_wire : String
}

///|
fn native_captured_page_phase(
  state : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
  history : ClientKeyedResponseHistory,
) -> Bool {
  !state.closed &&
  !state.growing &&
  !state.identifying &&
  state.left.lookup_issue is None &&
  state.selected_request is Some(same) &&
  physical_equal(same, request) &&
  state.selected_index == Some(-1) &&
  state.copying is None &&
  state.preparation is None &&
  request.io_complete &&
  request.attempts == 1L &&
  history._retained_native_page is None
}

///|
/// The Native Source calls this with its SAME confirmed raw Store metadata
/// and validated original page, before assembly. The later Host must persist
/// these exact bodies atomically under the still-current durable activation.
pub fn prepare_client_keyed_native_captured_page(
  request : ClientKeyedRequest,
  capture : @row_host.RowKeyedSourceCapture,
  raw : ClientKeyedNativeRawResponse,
  recorded_at : String,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  workspace : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedNativeCapturedPage, ClientKeyedRequestIssue] {
  guard request.assembly_accounting is Some(state) &&
    state.planned_requests is Some(requests) &&
    requests.get(request.row) is Some((same, slot)) &&
    physical_equal(same, request) &&
    state.known.get(slot) is Some((_, None, Some(history))) &&
    history._retained_activation is Some(activation) &&
    physical_equal(activation.request, request) &&
    activation.usage.usage_final &&
    native_captured_page_phase(state, request, history) &&
    @publication.lookup_raw_response_attempt(raw.metadata)
    is Some((raw_slot, attempt, captured_at)) &&
    raw_slot == @publication.publication_contract_identity(activation.slot) &&
    attempt == 1L &&
    @values.timestamp_epoch_milliseconds(recorded_at) is Some(recorded_epoch) &&
    @values.timestamp_epoch_milliseconds(captured_at) is Some(captured_epoch) &&
    recorded_epoch >= captured_epoch &&
    state.native_read_profile is Some(profile) &&
    @publication.file_read_profile_contract_bindings(profile)
    is Some((_, _, response_schema)) &&
    state.left.composed is Some(original) &&
    original.plan.keyed is Some(component) &&
    @row_host.keyed_row_capture_matches_request(capture, request.request) &&
    client_keyed_left_available(state.left) else {
    return Err(Assembly("foreign_native_captured_page"))
  }
  guard native_captured_page_phase(state, request, history) else {
    return Err(Assembly("claimed_native_captured_page"))
  }
  state.identifying = true
  let result = build_client_keyed_native_captured_page(
    state,
    original,
    component.barrier.logical_cid,
    request,
    history,
    activation,
    capture,
    raw,
    recorded_at,
    response_schema,
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema,
    max_work,
    workspace,
    max_bytes,
    max_nodes,
    max_depth,
  )
  state.identifying = false
  match result {
    Ok(value) => Ok(value)
    Err(issue) => {
      keyed_lookup_fail(state.left, issue) |> ignore
      Err(issue)
    }
  }
}

///|
fn build_client_keyed_native_captured_page(
  state : ClientKeyedLookupInput,
  original : ClientComposedKeyedOriginal,
  barrier : String,
  request : ClientKeyedRequest,
  history : ClientKeyedResponseHistory,
  activation : ClientKeyedNativeActivation,
  capture : @row_host.RowKeyedSourceCapture,
  raw : ClientKeyedNativeRawResponse,
  recorded_at : String,
  response_schema : String,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema : @execution.RelationSchemaIdentityLimits,
  max_work : Int,
  workspace : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedNativeCapturedPage, ClientKeyedRequestIssue] {
  // Existing supplied-input export frame12H16R11W, page state1H6R,
  // capture/read/result/history Some4H4R4W and immutable metadata1H9R2W.
  // The raw binding projection's tuple/Some adds2H3R2W. Scanner and protocol
  // writers have their own existing dynamic constructor quotes below.
  let declared = state.native_read_profile
    .map(@publication.publication_contract_name)
    .unwrap_or("") ==
    "declared_file_content_read"
  let controls = @execution.preparation_representation_cost({
    // Actual shape tuple1H2W; selected declared page wire/schema records3H14W.
    record_headers: 21L + (if declared { 3L } else { 0L }),
    reference_slots: 39L,
    scalar_words: 21L + (if declared { 14L } else { 0L }),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  guard @row_host.keyed_row_capture_export_construction_capacity(capture)
    is Some(input_quote) else {
    return Err(Assembly("native_page_input_capacity"))
  }
  let basis_r = state.retained_bytes
  let basis_e = state.execution_bytes
  match
    keyed_lookup_body_grow(state, basis_r, basis_e, controls, Some(input_quote)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard history._retained_native_page is None && !state.closed else {
    return Err(Assembly("claimed_native_page_state"))
  }
  let (actual_rows, actual_columns) = if declared {
    @row_host.keyed_row_capture_dimensions(capture)
  } else {
    (max_rows, payload_wire.max_columns)
  }
  let payload_wire = if declared {
    { ..payload_wire, max_columns: actual_columns, }
  } else {
    payload_wire
  }
  let logical_wire = if declared {
    { ..logical_wire, max_columns: actual_columns, }
  } else {
    logical_wire
  }
  let schema = if declared {
    { ..schema, max_fields: actual_columns, }
  } else {
    schema
  }
  let partial : ClientKeyedNativePageState = {
    read: None,
    capture: Some(capture),
    output: None,
    scan: None,
    receipt: None,
    result: None,
  }
  history._retained_native_page = Some(partial)
  let read = match @row_host.keyed_row_capture_read(capture) {
    Ok(value) => value
    Err(issue) => return Err(SourceObservation(issue))
  }
  partial.read = Some(read)
  let output = match
    @execution.capture_generated_supplied_source_input(
      original.sequence,
      read,
      max_work,
      payload_wire.max_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(Assembly("native_page_source_input"))
  }
  partial.output = Some(output)
  guard @execution.completed_relation_identity_scan_start_construction_capacity(
      output,
      retain_body=true,
    )
    is Some(start) else {
    return Err(Assembly("native_page_identity_start_capacity"))
  }
  match keyed_lookup_body_grow(state, basis_r, basis_e, controls, Some(start)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let scan = match
    @execution.start_completed_relation_identity_scan(
      output,
      actual_rows,
      values,
      payload_wire,
      logical_wire,
      schema,
      max_work,
      workspace,
      incremental_metadata=true,
      retain_body=true,
      source_input=Some(read),
    ) {
    Ok(value) => value
    Err(issue) => return Err(CompletedIdentity(issue))
  }
  partial.scan = Some(scan)
  let mut previous_work = 0L
  while true {
    guard @execution.completed_relation_identity_scan_next_construction_capacity(
        scan,
      )
      is Some(next) else {
      return Err(Assembly("native_page_identity_next_capacity"))
    }
    match
      keyed_lookup_body_grow(state, basis_r, basis_e, controls, Some(next)) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let advanced = @execution.advance_completed_relation_identity_scan(
      scan,
      31,
      construction_capacity=Some(next),
    )
    let work = @execution.completed_relation_identity_scan_work(scan)
    let delta = work - previous_work
    if delta < 0L || delta > 9223372036854775807L - state.native_left_work {
      return Err(Assembly("native_page_identity_work_overflow"))
    }
    state.native_left_work += delta
    previous_work = work
    match advanced {
      Err(issue) => return Err(CompletedIdentity(issue))
      Ok((false, _)) => ()
      Ok((true, _)) => break
    }
  }
  let receipt = match @execution.finish_completed_relation_identity_scan(scan) {
    Ok(value) => value
    Err(issue) => return Err(CompletedIdentity(issue))
  }
  partial.receipt = Some(receipt)
  guard @execution.completed_relation_identity_scan_body(scan, receipt)
    is Some(body) else {
    return Err(Assembly("native_page_identity_body"))
  }
  let logical = @execution.completed_relation_export_identity(receipt)
  let schema = @execution.completed_relation_export_schema_identity(receipt)
  let logical_bytes = @execution.logical_relation_usage(logical).0
  let schema_bytes = @execution.relation_schema_usage(schema).0
  if logical_bytes > 16777216 || schema_bytes > 16777216 - logical_bytes {
    return Err(Assembly("native_page_dependency_limit"))
  }
  let codec_bytes = if state.native_read_profile
    .map(@publication.publication_contract_name)
    .unwrap_or("") ==
    "declared_file_content_read" {
    let units = @publication.publication_contract_json(raw.metadata)
      .length()
      .to_int64() +
      activation.issuer_id.length().to_int64() +
      recorded_at.length().to_int64() +
      response_schema.length().to_int64() +
      barrier.length().to_int64()
    guard @execution.checked_preparation_add_product(4096L, units, 6L)
      is Some(bound) else {
      return Err(Assembly("capacity_overflow"))
    }
    Int64::min(bound, max_bytes.to_int64()).to_int()
  } else {
    max_bytes
  }
  let metadata_phase = match
    grow_keyed_lookup_protocol_metadata(
      state,
      codec_bytes,
      2L,
      copies=3,
      extra_controls=controls,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard @row_host.keyed_row_capture_matches_request(capture, request.request) &&
    !state.closed &&
    state.left.lookup_issue is None &&
    state.selected_request is Some(same) &&
    physical_equal(same, request) &&
    partial.capture is Some(same_capture) &&
    physical_equal(same_capture, capture) &&
    partial.read is Some(same_read) &&
    physical_equal(same_read, read) &&
    partial.output is Some(same_output) &&
    physical_equal(same_output, output) &&
    partial.result is None else {
    return Err(Assembly("retired_native_captured_page"))
  }
  let slot = @publication.publication_contract_identity(activation.slot)
  let batch = @publication.publication_contract_identity(activation.batch)
  let activation_cid = @publication.publication_contract_identity(
    activation.activation,
  )
  let raw_cid = @publication.publication_contract_identity(raw.metadata)
  let authority = client_request_authority_scope_cid(activation.client_request)
  let event_body = try {
    let writer = @encode.writer(codec_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    for
      (name, text) in [
        ("version", "actql-lookup-attempt-event/0.1"),
        ("barrier_cid", barrier),
        ("batch_plan_cid", batch),
        ("call_slot_cid", slot),
        ("recorded_at", recorded_at),
        ("outcome", "captured"),
        ("raw_response_artifact_cid", raw_cid),
        ("issuer_id", activation.issuer_id),
        ("authority_scope_cid", authority),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    @encode.key(writer, "network_attempt")
    @encode.number_value(writer, 1.0)
    for name in ["previous_event_cid", "runtime_error_cid", "failure_code"] {
      @encode.key(writer, name)
      @encode.null_value(writer)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Assembly("native_capture_event_encoding"))
  }
  let event = match
    native_lookup_seal(
      "native_file_lookup_attempt_event", event_body, codec_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let page_cid = @execution.logical_relation_cid(logical)
  let adoption_body = try {
    let writer = @encode.writer(codec_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    for
      (name, text) in [
        ("version", "actql-lookup-page-adoption/0.1"),
        ("barrier_cid", barrier),
        ("batch_plan_cid", batch),
        ("call_slot_cid", slot),
        ("activation_cid", activation_cid),
        ("capture_event_cid", @publication.publication_contract_identity(event)),
        ("raw_response_artifact_cid", raw_cid),
        ("response_schema_cid", response_schema),
        ("page_value_cid", page_cid),
        ("recorded_at", recorded_at),
        ("issuer_id", activation.issuer_id),
        ("authority_scope_cid", authority),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    @encode.key(writer, "network_attempt")
    @encode.number_value(writer, 1.0)
    for name in ["previous_adoption_cid", "next_token"] {
      @encode.key(writer, name)
      @encode.null_value(writer)
    }
    @encode.key(writer, "terminal")
    @encode.bool_value(writer, true)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Assembly("native_page_adoption_encoding"))
  }
  let adoption = match
    native_lookup_seal(
      "native_file_lookup_adoption", adoption_body, codec_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result = {
    batch_index: activation.batch_index,
    deadline_epoch_ms: activation.deadline_epoch_ms,
    call_slot_cid: slot,
    batch_plan_cid: batch,
    activation_cid,
    raw: raw.metadata,
    raw_retention: raw.retention,
    event,
    adoption,
    logical_value_cid: page_cid,
    body,
    schema_wire: @execution.relation_schema_wire(schema),
  }
  partial.result = Some(result)
  @execution.cancel_completed_relation_identity_scan(scan) |> ignore
  partial.scan = None
  match
    finish_keyed_lookup_protocol_metadata(
      state,
      metadata_phase,
      max_nodes,
      max_depth,
      [event, adoption],
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !client_keyed_native_captured_page_matches(
      result,
      request,
      activation.client_request,
      original.compiled,
      original.definition,
      original.plan,
    ) {
    return Err(Assembly("retired_native_captured_page"))
  }
  Ok(result)
}

///|
/// Callback-free SAME original correspondence, not current permission or COMMIT.
pub fn client_keyed_native_captured_page_matches(
  page : ClientKeyedNativeCapturedPage,
  request : ClientKeyedRequest,
  client_request : ClientRequestIdentity,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : ClientInferPlanGraph,
) -> Bool {
  guard request.assembly_accounting is Some(state) &&
    !state.closed &&
    state.left.lookup_issue is None &&
    state.left.composed is Some(original) &&
    physical_equal(original.compiled, compiled) &&
    physical_equal(original.definition, definition) &&
    physical_equal(original.plan, graph) &&
    state.planned_requests is Some(requests) &&
    requests.get(request.row) is Some((same, slot)) &&
    physical_equal(same, request) &&
    state.known.get(slot) is Some((_, None, Some(history))) &&
    history._retained_activation is Some(activation) &&
    client_request_identity_relation(activation.client_request, client_request)
    is SameRequest &&
    history._retained_native_page is Some(partial) &&
    partial.result is Some(same_page) else {
    return false
  }
  physical_equal(same_page, page) &&
  request.io_complete &&
  activation.usage.usage_final
}
