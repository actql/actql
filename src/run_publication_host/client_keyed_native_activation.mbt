///|
/// Actual observations on the SAME original first Native attempt. These are
/// consumed counters, not reservations, a receipt, current permission or ACK.
/// The original token owns the mutable history; consumers only borrow it.
pub struct ClientKeyedNativeAttemptUsage {
  mut request_bytes : Int64
  mut response_wire_bytes : Int64
  mut response_decoded_bytes : Int64
  mut started_ms : Int64
  mut observed_ms : Int64
  mut usage_final : Bool
}

///|
/// Prepared original metadata on the SAME lookup. Only this checked constructor
/// can create it; the Native Journal still owes actual durable persistence and
/// current Source permission before dispatch. None of these bodies is an ACK.
pub struct ClientKeyedNativeActivation {
  priv original : ClientKeyedLookupInput
  priv request : ClientKeyedRequest
  priv client_request : ClientRequestIdentity
  priv definition : @publication.PublicationContract
  priv graph : ClientInferPlanGraph
  priv usage : ClientKeyedNativeAttemptUsage
  batch : @publication.PublicationContract
  transport : @publication.PublicationContract
  keys : @publication.PublicationContract
  semantic_request : @publication.PublicationContract
  slot : @publication.PublicationContract
  activation : @publication.PublicationContract
  batch_index : Int
  batch_count : Int
  deadline_epoch_ms : Int64
  issuer_id : String
  reserved_wire_bytes : Int64
  reserved_decoded_bytes : Int64
  reserved_duration_ms : Int64
}

///|
fn native_lookup_seal(
  kind : String,
  body : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, ClientKeyedRequestIssue] {
  @publication.seal_publication_contract(
    kind, body, max_bytes, max_nodes, max_depth,
  ).map_err(issue => Identity(@publication.Contract(issue)))
}

///|
/// Prepare the selected original singleton's first and only physical attempt.
/// The already encoded full typed Request is borrowed unchanged: no second
/// semantic check, Ref re-emission, JSON request classifier or key-CID-to-Ref
/// conversion. Clock observation starts this actual acquisition interval;
/// failure retains spent time/work/capacity rather than issuing another budget.
pub fn prepare_client_keyed_native_activation(
  state : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
  client_request : ClientRequestIdentity,
  issuer_id : String,
  recorded_at : String,
  now_ms : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedNativeActivation, ClientKeyedRequestIssue] {
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 || issuer_id.is_empty() {
    return Err(Assembly("native_activation_limits"))
  }
  guard !state.closed &&
    !state.growing &&
    !state.identifying &&
    state.selected_request is Some(selected) &&
    physical_equal(selected, request) &&
    state.selected_index == Some(-1) &&
    request.attempts == 0L &&
    !request.io_complete &&
    request.row == keyed_lookup_next_original_row(state) &&
    state.selected_key is Some(wire) &&
    state.native_batch_plan is Some(batch) &&
    state.native_transport is Some(transport) &&
    state.native_read_profile is Some(profile) &&
    state.publication_identity is Some(identity) &&
    state.planned_requests is Some(requests) &&
    requests.get(request.row) is Some((same, slot_index)) &&
    physical_equal(same, request) &&
    state.known.get(slot_index) is Some((same_wire, None, Some(history))) &&
    same_wire == wire &&
    physical_equal(history.request, request) &&
    history._retained_activation is None &&
    state.planned_order is Some(order) &&
    state.left.composed is Some(original) &&
    original.plan.keyed is Some(component) &&
    original.keyed.program is KeyedEffect(prepared) &&
    prepared_client_effect_request_scope(prepared, client_request) is Ok(_) &&
    physical_equal(original.keyed, state.left.acquisition) &&
    physical_equal(component.original.fragments.acquisition, original.keyed) &&
    @publication.file_read_profile_contract_bindings(profile)
    is Some((source, schema, _)) &&
    @values.timestamp_epoch_milliseconds(recorded_at) is Some(epoch) else {
    return Err(Assembly("foreign_or_unavailable_native_activation"))
  }
  // The immutable canonical schedule groups equal-key occurrences. Completed
  // distinct responses therefore select its next physical singleton directly;
  // do not scan the whole checked inventory again for each call.
  let batch_index = state.completed_responses
  if order.get(batch_index) != Some(slot_index) {
    return Err(Assembly("foreign_native_batch_slot"))
  }
  let controls = @execution.preparation_representation_cost({
    // Original token1H13R6W + history Some1H1R1W + deadline String1H/24U
    // and SAME actual attempt usage1H6W. No per-poll snapshot is allocated.
    record_headers: 4L,
    reference_slots: 14L,
    scalar_words: 13L,
    owned_utf16_units: 24L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let writer_bytes = if @publication.publication_contract_name(profile) == "declared_file_content_read" {
    // The original encoded Request is already retained by this plan. Only
    // its actual subtree and the closed issuer/envelope Strings are next;
    // a large accepted codec ceiling is not an allocation request.
    let units = wire.length().to_int64() + issuer_id.length().to_int64() +
      @publication.publication_contract_json(profile).length().to_int64() +
      @publication.publication_contract_identity(batch).length().to_int64() +
      @publication.publication_contract_identity(transport).length().to_int64() +
      source.length().to_int64() + schema.length().to_int64() +
      client_request_authority_scope_cid(client_request).length().to_int64() +
      component.barrier.logical_cid.length().to_int64()
    guard @execution.checked_preparation_add_product(4096L, units, 6L) is Some(bytes) else {
      return Err(Assembly("capacity_overflow"))
    }
    Int64::min(bytes, max_bytes.to_int64()).to_int()
  } else { max_bytes }
  let metadata_phase = match
    grow_keyed_lookup_protocol_metadata(
      state,
      writer_bytes,
      3L,
      extra_controls=controls,
      copies=3,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let policy = match keyed_lookup_observation(request, now_ms) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let remaining = @environment.lookup_execution_ceiling(
      policy,
      @environment.TotalDurationMs,
    ) -
    (now_ms - state.left.started_ms.unwrap())
  let response_bound = @environment.lookup_capacity_response_bytes_per_page(
    @acquisition.keyed_source_capacity(state.left.acquisition.facts),
  )
  // This Native implementation emits the same per-page ceiling from its
  // actual physical file limits. There is no compression or pagination. A
  // smaller remaining Host allowance cannot silently cap that original read.
  if response_bound < 0L ||
    response_bound >
    @environment.lookup_execution_ceiling(
      policy,
      @environment.TotalResponseWireBytes,
    ) -
    state.left.response_bytes ||
    response_bound >
    @environment.lookup_execution_ceiling(
      policy,
      @environment.TotalResponseDecodedBytes,
    ) -
    state.left.decoded_bytes {
    return Err(LookupLimit("native_activation_reservation"))
  }
  guard remaining > 0L &&
    epoch <= 9223372036854775807L - remaining &&
    @values.epoch_milliseconds_timestamp(epoch + remaining) is Some(deadline) else {
    return Err(InvalidObservation)
  }
  // All interpolated identities are the admitted ASCII CIDs above. wire is
  // the original typed encoder output already retained by this SAME request
  // plan; it is neither caller JSON nor a capability reconstructed from a key.
  let transport_cid = @publication.publication_contract_identity(transport)
  let body = "{\"continuation\":null,\"request_schema_cid\":\"" +
    schema +
    "\",\"request_values\":" +
    wire +
    ",\"source_view_contract_cid\":\"" +
    source +
    "\",\"transport_plan_cid\":\"" +
    transport_cid +
    "\",\"version\":\"actql-lookup-semantic-request/0.1\"}"
  let semantic_request = match
    native_lookup_seal(
      "native_file_lookup_request", body, writer_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let batch_cid = @publication.publication_contract_identity(batch)
  let slot_body = "{\"batch_index\":" +
    batch_index.to_string() +
    ",\"batch_plan_cid\":\"" +
    batch_cid +
    "\",\"page_index\":0,\"semantic_request_cid\":\"" +
    @publication.publication_contract_identity(semantic_request) +
    "\",\"version\":\"actql-lookup-call-slot/0.1\"}"
  let slot = match
    native_lookup_seal(
      "native_file_lookup_call_slot", slot_body, writer_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let activation_body = try {
    let writer = @encode.writer(writer_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    for
      (name, value) in [
        (
          "authority_scope_cid",
          client_request_authority_scope_cid(client_request),
        ),
        ("barrier_cid", component.barrier.logical_cid),
        ("batch_plan_cid", batch_cid),
        ("call_slot_cid", @publication.publication_contract_identity(slot)),
        ("deadline", deadline),
        ("issuer_id", issuer_id),
        ("recorded_at", recorded_at),
        ("version", "actql-lookup-attempt-activation/0.1"),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "network_attempt")
    @encode.number_value(writer, 1.0)
    @encode.key(writer, "previous_activation_cid")
    @encode.null_value(writer)
    @encode.key(writer, "previous_attempt_event_cid")
    @encode.null_value(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Assembly("native_activation_encoding"))
  }
  let activation = match
    native_lookup_seal(
      "native_file_lookup_activation", activation_body, writer_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if state.closed ||
    state.left.lookup_issue is Some(_) ||
    !(state.selected_request is Some(same) && physical_equal(same, request)) {
    return Err(Assembly("retired_native_activation"))
  }
  // Growth/current/observation can reenter this SAME preparation. The inner
  // caller may already have received its original. After the last callback,
  // compare only our retained slot/history; never replace or poison that token.
  guard state.known.get(slot_index) is Some((_, None, Some(retained))) &&
    physical_equal(retained, history) &&
    history._retained_activation is None else {
    return Err(Assembly("claimed_native_activation"))
  }
  let result = {
    original: state,
    request,
    client_request,
    definition: original.definition,
    graph: original.plan,
    usage: {
      request_bytes: 0L,
      response_wire_bytes: 0L,
      response_decoded_bytes: 0L,
      started_ms: -1L,
      observed_ms: -1L,
      usage_final: false,
    },
    batch,
    transport,
    keys: identity.keys,
    semantic_request,
    slot,
    activation,
    batch_index,
    batch_count: order.length(),
    deadline_epoch_ms: epoch + remaining,
    issuer_id,
    reserved_wire_bytes: response_bound,
    reserved_decoded_bytes: response_bound,
    reserved_duration_ms: remaining,
  }
  history._retained_activation = Some(result)
  match
    finish_keyed_lookup_protocol_metadata(
      state,
      metadata_phase,
      max_nodes,
      max_depth,
      [semantic_request, slot, activation],
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard !state.closed &&
    state.left.lookup_issue is None &&
    state.selected_request is Some(same_request) &&
    physical_equal(same_request, request) &&
    state.selected_index == Some(-1) &&
    request.attempts == 0L &&
    !request.io_complete &&
    history._retained_activation is Some(same) &&
    physical_equal(same, result) else {
    return Err(Assembly("retired_native_activation"))
  }
  Ok(result)
}

///|
/// Callback-free original/phase binding used by the existing Native Journal
/// after its own captured Read/current observation. This issues no permission,
/// durable acknowledgement or replacement Request; metadata alone is not I/O.
pub fn client_keyed_native_activation_matches(
  value : ClientKeyedNativeActivation,
  request : ClientRequestIdentity,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : ClientInferPlanGraph,
) -> Bool {
  let state = value.original
  !state.closed &&
  state.left.lookup_issue is None &&
  state.left.composed is Some(original) &&
  physical_equal(original.compiled, compiled) &&
  physical_equal(value.definition, definition) &&
  physical_equal(value.graph, graph) &&
  client_request_identity_relation(value.client_request, request) is SameRequest &&
  state.native_batch_plan is Some(batch) &&
  physical_equal(batch, value.batch) &&
  state.planned_requests is Some(requests) &&
  requests.get(value.request.row) is Some((same, slot)) &&
  physical_equal(same, value.request) &&
  state.known.get(slot) is Some((_, _, Some(history))) &&
  history._retained_activation is Some(original_activation) &&
  physical_equal(original_activation, value) &&
  state.selected_request is Some(selected) &&
  physical_equal(selected, value.request) &&
  value.request.row == keyed_lookup_next_original_row(state) &&
  value.request.attempts == 0L &&
  !value.request.io_complete
}

///|
/// Borrow the original consumed counters, including after refusal/retirement.
/// No callback, reset, snapshot allocation or completion claim is performed.
pub fn client_keyed_native_attempt_usage(
  original : ClientKeyedNativeActivation,
) -> ClientKeyedNativeAttemptUsage {
  original.usage
}

///|
// Pure original association after the existing observation's current fence.
// Return the retained Option itself; no new registry or observation callback.
fn native_keyed_observed_activation(
  request : ClientKeyedRequest,
) -> ClientKeyedNativeActivation? {
  guard request.assembly_accounting is Some(state) &&
    state.planned_requests is Some(requests) &&
    requests.get(request.row) is Some((same, slot)) &&
    physical_equal(same, request) &&
    state.known.get(slot) is Some((_, _, Some(history))) else {
    return None
  }
  history._retained_activation
}
