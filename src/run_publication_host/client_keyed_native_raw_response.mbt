///|
/// Original metadata retained by the physical Source. This neither records an
/// attempt event nor acknowledges durable byte custody or page adoption.
pub struct ClientKeyedNativeRawResponse {
  metadata : @publication.PublicationContract
  retention : @publication.PublicationContract
  holding : String
  priv mut store_preparing : Bool
  priv mut store_prepared : Bool
}

///|
/// Bind the completed original transport bytes before any physical document or
/// derived Content page is admitted. The installing Source supplies its actual
/// byte digest/count; the SAME Store independently verifies them on persistence.
/// Activation and response policy come from this original checked lookup, not
/// caller-built request JSON or a replacement compilation.
pub fn prepare_client_keyed_native_raw_response(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : ClientKeyedRequest,
  retention : @publication.PublicationContract,
  binding_wire : String,
  content_cid : String,
  size_bytes : Int,
  captured_at : String,
  now_ms : Int64,
  limits : @values.ReferenceLimits,
) -> Result[ClientKeyedNativeRawResponse, ClientKeyedRequestIssue] {
  guard size_bytes >= 0 &&
    limits.max_bytes > 0 &&
    request.assembly_accounting is Some(state) &&
    !state.closed &&
    !state.growing &&
    state.left.lookup_issue is None &&
    @values.timestamp_epoch_milliseconds(captured_at) is Some(captured_epoch) &&
    request.attempts == 1L &&
    !request.io_complete &&
    state.selected_request is Some(selected) &&
    physical_equal(selected, request) &&
    state.planned_requests is Some(requests) &&
    requests.get(request.row) is Some((same, slot)) &&
    physical_equal(same, request) &&
    state.known.get(slot) is Some((_, None, Some(history))) &&
    history._retained_activation is Some(activation) &&
    physical_equal(activation.request, request) &&
    state.left.composed is Some(original) &&
    physical_equal(original.compiled, compiled) &&
    physical_equal(original.definition, definition) &&
    original.plan.keyed is Some(component) else {
    return Err(Assembly("foreign_native_raw_response"))
  }
  if captured_epoch <
    activation.deadline_epoch_ms - activation.reserved_duration_ms ||
    captured_epoch > activation.deadline_epoch_ms {
    return Err(InvalidObservation)
  }
  // Two closed bodies (Source retention and raw envelope), their writers and
  // holding hash, plus result/holder/temporary tuples. This is the existing
  // lookup reservation; Store disk quota supplies none of this live backing.
  // The holding hashing writer has its existing fixed 2048-byte input bound.
  // Fund that constructor too, without imposing it as a minimum raw codec limit.
  let controls = @execution.preparation_representation_cost({
    record_headers: 22L,
    reference_slots: 39L,
    scalar_words: 23L,
    owned_utf16_units: 71L,
    owned_wire_bytes: 0L,
  }).unwrap()
  // The declared-file supplier already has the exact closed binding and
  // retention wires. Fund their bounded escaping plus this raw descriptor,
  // rather than treating the accepted wire ceiling as allocated backing.
  // Native keeps its original codec and reservation policy unchanged.
  let codec_bytes = if @publication.publication_contract_name(
      component.original.profile,
    ) ==
    "declared_file_content_read" {
    let units = binding_wire.length().to_int64() +
      @publication.publication_contract_json(retention).length().to_int64() +
      content_cid.length().to_int64() +
      captured_at.length().to_int64() +
      activation.issuer_id.length().to_int64() +
      component.original.response_data_policy_cid.length().to_int64()
    guard @execution.checked_preparation_add_product(4096L, units, 6L)
      is Some(bound) else {
      return Err(Assembly("capacity_overflow"))
    }
    Int64::min(bound, limits.max_bytes.to_int64()).to_int()
  } else {
    limits.max_bytes
  }
  let metadata_phase = match
    grow_keyed_lookup_protocol_metadata(
      state,
      Int::max(codec_bytes, 2048),
      2L,
      copies=3,
      extra_controls=controls,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match keyed_lookup_observation(request, now_ms) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The last external current observation may synchronously retire/reenter.
  // Retain its result, then use only original reference/phase comparisons.
  guard !state.closed &&
    state.left.lookup_issue is None &&
    request.attempts == 1L &&
    !request.io_complete &&
    state.selected_request is Some(same) &&
    physical_equal(same, request) &&
    state.known.get(slot) is Some((_, None, Some(retained))) &&
    physical_equal(retained, history) &&
    history._retained_activation is Some(same_activation) &&
    physical_equal(same_activation, activation) else {
    return Err(Assembly("retired_native_raw_response"))
  }
  let binding = match
    @publication.parse_content_reference_binding(binding_wire, limits) {
    Ok(value) => value
    Err(_) => return Err(Assembly("native_raw_storage_binding"))
  }
  let scope = client_request_authority_scope_cid(activation.client_request)
  guard binding.capture_authority_cid == scope &&
    binding.workspace_scope_cid == scope &&
    binding.effective_data_policy_cid ==
    component.original.response_data_policy_cid &&
    @publication.run_definition_lifetime(definition) is Some((_, until)) &&
    binding.expires_at == Some(until) else {
    return Err(Assembly("native_raw_storage_binding"))
  }
  let source_retention = match
    @publication.issue_result_retention_for_data_policy(
      retention,
      component.original.response_data_policy_cid,
      codec_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(@publication.Contract(issue)))
  }
  if !(@publication.result_retention_interval_state(
      source_retention, captured_at,
    )
    is Ok("available")) {
    return Err(Assembly("native_raw_retention_unavailable"))
  }
  let body = try {
    let writer = @encode.writer(codec_bytes, limits.max_nodes, limits.max_depth)
    @encode.begin_object(writer)
    for
      (field, text) in [
        ("version", "actql-lookup-raw-response/0.1"),
        (
          "call_slot_cid",
          @publication.publication_contract_identity(activation.slot),
        ),
        ("content_cid", content_cid),
        ("media_type", "application/json"),
        ("captured_at", captured_at),
        (
          "effective_data_policy_cid",
          component.original.response_data_policy_cid,
        ),
        (
          "effective_retention_policy_cid",
          @publication.publication_contract_identity(source_retention),
        ),
        ("issuer_id", activation.issuer_id),
        ("authority_scope_cid", scope),
      ] {
      @encode.key(writer, field)
      @encode.string_value(writer, text)
    }
    @encode.key(writer, "network_attempt")
    @encode.number_value(writer, request.attempts.to_double())
    @encode.key(writer, "size_bytes")
    @encode.number_value(writer, size_bytes.to_double())
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Assembly("native_raw_encoding"))
  }
  let metadata = match
    native_lookup_seal(
      "native_file_lookup_raw_response",
      body,
      codec_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let holding = try {
    let writer = @encode.hashing_writer(2048, 64, 2)
    @encode.begin_object(writer)
    for
      (field, text) in [
        ("capture_authority_cid", scope),
        (
          "raw_response_cid",
          @publication.publication_contract_identity(metadata),
        ),
        ("role", "lookup_raw_response_bytes"),
        (
          "run_definition_cid",
          @publication.publication_contract_identity(definition),
        ),
        ("store_authority_cid", binding.content_store_cid),
        ("version", "actql-content-private-holding/0.1"),
      ] {
      @encode.key(writer, field)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    "sha256:" + @encode.finish_hash(writer)
  } catch {
    _ => return Err(Assembly("native_raw_holding"))
  }
  let result = {
    metadata,
    retention: source_retention,
    holding,
    store_preparing: false,
    store_prepared: false,
  }
  match
    finish_keyed_lookup_protocol_metadata(
      state,
      metadata_phase,
      limits.max_nodes,
      limits.max_depth,
      [metadata, source_retention],
      texts=[holding],
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard !state.closed &&
    state.left.lookup_issue is None &&
    state.selected_request is Some(same) &&
    physical_equal(same, request) &&
    request.attempts == 1L &&
    !request.io_complete &&
    state.known.get(slot) is Some((_, None, Some(same_history))) &&
    physical_equal(same_history, history) &&
    history._retained_activation is Some(same_activation) &&
    physical_equal(same_activation, activation) else {
    return Err(Assembly("retired_native_raw_response"))
  }
  Ok(result)
}
