///|
/// The existing lookup retains this original pre-dispatch record through its
/// Journal write. This is neither durable admission nor permission to send.
/// Native's existing private record format and reader remain unchanged.
pub fn prepare_client_keyed_declared_file_activation_record(
  original : ClientKeyedNativeActivation,
  request : ClientRequestIdentity,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : ClientInferPlanGraph,
  max_bytes : Int,
) -> Result[String, ClientKeyedRequestIssue] {
  let state = original.original
  guard !state.growing &&
    !state.identifying &&
    client_keyed_native_activation_matches(
      original, request, compiled, definition, graph,
    ) &&
    state.native_read_profile is Some(profile) &&
    @publication.publication_contract_name(profile) ==
    "declared_file_content_read" else {
    return Err(Assembly("foreign_declared_file_activation_record"))
  }
  let request_scope = client_request_scope_cid(request)
  let definition_cid = @publication.publication_contract_identity(definition)
  // These are the original retained closed wires, not a second Request walk.
  let units = request_scope.length().to_int64() +
    definition_cid.length().to_int64() +
    @publication.publication_contract_json(original.activation)
    .length()
    .to_int64() +
    @publication.publication_contract_json(original.batch).length().to_int64() +
    @publication.publication_contract_json(original.slot).length().to_int64() +
    @publication.publication_contract_json(original.keys).length().to_int64() +
    @publication.publication_contract_json(original.semantic_request)
    .length()
    .to_int64() +
    @publication.publication_contract_json(original.transport)
    .length()
    .to_int64()
  guard max_bytes > 0 &&
    @execution.checked_preparation_add_product(4096L, units, 6L) is Some(bound) else {
    return Err(Assembly("capacity_overflow"))
  }
  let bytes = Int64::min(bound, max_bytes.to_int64()).to_int()
  let phase = match
    grow_keyed_lookup_protocol_metadata(state, bytes, 15L, copies=2) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Growth observes the same current owner. A reentered retirement cannot
  // turn an old activation into a new dispatch or Journal constructor.
  guard !state.growing &&
    !state.identifying &&
    client_keyed_native_activation_matches(
      original, request, compiled, definition, graph,
    ) else {
    return Err(Assembly("retired_declared_file_activation_record"))
  }
  state.identifying = true
  defer {
    state.identifying = false
  }
  let wire = try {
    let writer = @encode.writer(bytes, 15, 2)
    @encode.begin_object(writer)
    for
      (name, contract) in [
        ("activation", original.activation),
        ("batch_plan", original.batch),
        ("call_slot", original.slot),
        ("key_set", original.keys),
        ("request", original.semantic_request),
        ("transport", original.transport),
      ] {
      @encode.key(writer, name)
      @encode.string_value(
        writer,
        @publication.publication_contract_json(contract),
      )
    }
    @encode.key(writer, "request_scope_cid")
    @encode.string_value(writer, request_scope)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, definition_cid)
    for
      (name, value) in [
        ("batch_index", original.batch_index.to_int64()),
        ("batch_count", original.batch_count.to_int64()),
        ("reserved_wire_bytes", original.reserved_wire_bytes),
        ("reserved_decoded_bytes", original.reserved_decoded_bytes),
        ("reserved_duration_ms", original.reserved_duration_ms),
      ] {
      @encode.key(writer, name)
      @encode.number_value(writer, value.to_double())
    }
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-declared-file-lookup-activation-original/0.1",
    )
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Assembly("declared_file_activation_record_encoding"))
  }
  match
    finish_keyed_lookup_protocol_metadata(state, phase, 15, 2, [], texts=[wire]) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard client_keyed_native_activation_matches(
    original, request, compiled, definition, graph,
  ) else {
    return Err(Assembly("retired_declared_file_activation_record"))
  }
  Ok(wire)
}

///|
/// Resolve this installed lookup's existing Host retention metadata before
/// any Source Relation or attempt writer. Policies come from the same checked
/// component; only the Host's already resolved custody clocks/contracts enter.
/// No permission, extension, Resource or second preparation is issued here.
pub fn prepare_client_keyed_declared_file_retention(
  lookup : ClientKeyedLookupInput,
  request : ClientRequestIdentity,
  retention_contract : String,
  available_until : String,
  delete_by : String,
  metadata_delete_by : String,
  metadata_policy : String,
  clock_contract : String,
  max_bytes : Int,
) -> Result[@publication.PublicationContract, ClientKeyedRequestIssue] {
  guard !lookup.closed &&
    !lookup.growing &&
    !lookup.identifying &&
    lookup.planned_requests is None &&
    lookup.left.requests == 0L &&
    lookup.left.attempts == 0L &&
    lookup.left.lookup_issue is None &&
    lookup.left.composed is Some(original) &&
    original.plan.keyed is Some(component) &&
    original.keyed.program is KeyedEffect(prepared) &&
    prepared_client_effect_request_scope(prepared, request) is Ok(_) &&
    @publication.publication_contract_name(component.original.profile) ==
    "declared_file_content_read" else {
    return Err(Assembly("foreign_declared_file_retention"))
  }
  lookup.identifying = true
  defer {
    lookup.identifying = false
  }
  let state = match keyed_lookup_source_metadata_state(lookup, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if state.retention_base is Some(_) {
    return Err(Assembly("retention_already_prepared"))
  }
  let units = retention_contract.length().to_int64() +
    available_until.length().to_int64() +
    delete_by.length().to_int64() +
    2L * metadata_delete_by.length().to_int64() +
    metadata_policy.length().to_int64() +
    clock_contract.length().to_int64() +
    component.original.response_data_policy_cid.length().to_int64()
  guard max_bytes > 0 &&
    @execution.checked_preparation_add_product(2048L, units, 6L) is Some(bound) else {
    return Err(Assembly("capacity_overflow"))
  }
  let bytes = Int64::min(bound, max_bytes.to_int64()).to_int()
  let controls = @shape.collection_construction_extent({
    records: 11L,
    record_references: 20L,
    record_words: 2L,
    reference_arrays: 3L,
    reference_items: 10L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let extra_controls = @execution.preparation_representation_cost({
    record_headers: controls.record_headers,
    reference_slots: controls.reference_slots,
    scalar_words: controls.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let phase = match
    grow_keyed_lookup_protocol_metadata(lookup, bytes, 11L, extra_controls~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard !lookup.closed &&
    lookup.planned_requests is None &&
    lookup.left.lookup_issue is None &&
    state.retention_base is None else {
    return Err(Assembly("retired_declared_file_retention"))
  }
  let wire = try {
    let writer = @encode.writer(bytes, 10, 2)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-result-retention-policy/0.1"),
        ("retention_contract_cid", retention_contract),
        (
          "effective_data_policy_cid",
          component.original.response_data_policy_cid,
        ),
        ("available_until", available_until),
        ("delete_by", delete_by),
        ("extension_ceiling_at", metadata_delete_by),
        ("metadata_retention_policy_cid", metadata_policy),
        ("metadata_delete_by", metadata_delete_by),
        ("clock_contract_cid", clock_contract),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Assembly("declared_file_retention_encoding"))
  }
  let result = match
    native_lookup_seal("result_retention_policy", wire, bytes, 11, 2) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  state.retention_base = Some(result)
  match finish_keyed_lookup_protocol_metadata(lookup, phase, 11, 2, [result]) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    state.retention_base is Some(same) &&
    physical_equal(same, result) else {
    return Err(Assembly("retired_declared_file_retention"))
  }
  Ok(result)
}

///|
/// The admitted component and retained LEFT Relation, not a copied profile or
/// labels, select this existing request-plan purpose before even an empty batch.
pub fn start_client_keyed_declared_file_request_plan(
  lookup : ClientKeyedLookupInput,
  recorded_at : String,
  now_ms : Int64,
  issuer : String,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard lookup.left.composed is Some(original) &&
    original.plan.keyed is Some(component) &&
    @publication.publication_contract_name(component.original.profile) ==
    "declared_file_content_read" &&
    lookup.native_sources is Some(sources) &&
    sources.relation is Some(_) else {
    return Err(Assembly("missing_declared_file_plan_originals"))
  }
  start_client_keyed_lookup_request_plan(
    lookup,
    native_read_profile=Some(component.original.profile),
    native_start=Some((recorded_at, now_ms, issuer)),
  )
}

///|
/// Retain the SAME completed page preimages for the existing Journal's ordered
/// activation CAS. This issuer neither acknowledges Store bytes nor commits a
/// page; the physical caller still owes both observations before assembly.
pub fn prepare_client_keyed_declared_file_page_record(
  page : ClientKeyedNativeCapturedPage,
  keyed_request : ClientKeyedRequest,
  request : ClientRequestIdentity,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : ClientInferPlanGraph,
  max_bytes : Int,
) -> Result[String, ClientKeyedRequestIssue] {
  guard client_keyed_native_captured_page_matches(
      page, keyed_request, request, compiled, definition, graph,
    ) &&
    keyed_request.assembly_accounting is Some(state) &&
    !state.identifying &&
    !state.growing &&
    state.native_read_profile is Some(profile) &&
    @publication.publication_contract_name(profile) ==
    "declared_file_content_read" else {
    return Err(Assembly("foreign_declared_file_page_record"))
  }
  let scope = client_request_scope_cid(request)
  let definition_cid = @publication.publication_contract_identity(definition)
  let units = @publication.publication_contract_json(page.adoption)
    .length()
    .to_int64() +
    @publication.publication_contract_json(page.event).length().to_int64() +
    @publication.publication_contract_json(page.raw).length().to_int64() +
    page.body.length().to_int64() +
    page.schema_wire.length().to_int64() +
    scope.length().to_int64() +
    definition_cid.length().to_int64()
  guard max_bytes > 0 &&
    @execution.checked_preparation_add_product(2048L, units, 6L) is Some(bound) else {
    return Err(Assembly("capacity_overflow"))
  }
  let bytes = Int64::min(bound, max_bytes.to_int64()).to_int()
  let phase = match
    grow_keyed_lookup_protocol_metadata(state, bytes, 9L, copies=2) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard client_keyed_native_captured_page_matches(
      page, keyed_request, request, compiled, definition, graph,
    ) &&
    !state.identifying else {
    return Err(Assembly("retired_declared_file_page_record"))
  }
  state.identifying = true
  defer {
    state.identifying = false
  }
  let wire = try {
    let writer = @encode.writer(bytes, 9, 2)
    @encode.begin_object(writer)
    for
      (name, text) in [
        ("adoption", @publication.publication_contract_json(page.adoption)),
        ("event", @publication.publication_contract_json(page.event)),
        ("raw", @publication.publication_contract_json(page.raw)),
        ("page_value_wire", page.body),
        ("page_schema_wire", page.schema_wire),
        ("request_scope_cid", scope),
        ("run_definition_cid", definition_cid),
        ("version", "actql-declared-file-lookup-page-original/0.1"),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Assembly("declared_file_page_record_encoding"))
  }
  match
    finish_keyed_lookup_protocol_metadata(state, phase, 9, 2, [], texts=[wire]) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard client_keyed_native_captured_page_matches(
    page, keyed_request, request, compiled, definition, graph,
  ) else {
    return Err(Assembly("retired_declared_file_page_record"))
  }
  Ok(wire)
}

///|
/// Fund the existing private Store's two encrypted objects BEFORE its callback.
/// The raw input already belongs to the Source; this same lookup retains the
/// extra encryption/read/failed-writer overlap until its actual retirement.
/// These are established executor units and actual closed envelope geometry,
/// not a Store quota, physical ACK, byte policy or another resource owner.
pub fn prepare_client_keyed_declared_file_raw_store(
  request : ClientKeyedRequest,
  raw : ClientKeyedNativeRawResponse,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard !raw.store_preparing &&
    !raw.store_prepared &&
    request.assembly_accounting is Some(state) &&
    !state.closed &&
    !state.growing &&
    !state.identifying &&
    state.left.lookup_issue is None &&
    request.attempts == 1L &&
    !request.io_complete &&
    state.selected_request is Some(same) &&
    physical_equal(same, request) &&
    state.native_read_profile is Some(profile) &&
    @publication.publication_contract_name(profile) ==
    "declared_file_content_read" &&
    state.planned_requests is Some(requests) &&
    requests.get(request.row) is Some((same, slot)) &&
    physical_equal(same, request) &&
    state.known.get(slot) is Some((_, None, Some(history))) &&
    history._retained_activation is Some(activation) &&
    @publication.lookup_raw_response_attempt(raw.metadata)
    is Some((raw_slot, 1L, _)) &&
    raw_slot == @publication.publication_contract_identity(activation.slot) &&
    @publication.lookup_raw_response_content(raw.metadata) is Some((_, size)) &&
    size >= 0L else {
    return Err(Assembly("foreign_declared_file_raw_store"))
  }
  let units = @publication.publication_contract_json(raw.metadata)
    .length()
    .to_int64()
  // Descriptor UTF-8 is at most three bytes per original UTF-16 code unit.
  // The SAME Store format uses exactly128 fixed ASCII bytes plus padded Base64.
  guard @execution.checked_preparation_add_product(0L, units, 3L)
    is Some(descriptor) &&
    @execution.checked_preparation_add_product(128L, (size + 2L) / 3L, 4L)
    is Some(content_envelope) &&
    @execution.checked_preparation_add_product(128L, (descriptor + 2L) / 3L, 4L)
    is Some(descriptor_envelope) &&
    @execution.checked_preparation_add_product(
      content_envelope, descriptor_envelope, 1L,
    )
    is Some(envelopes) &&
    @execution.execution_capacity_inventory(
      [
        // Original Store read/failed-close pieces and its existing fixed Host
        // control allowance; these are the same units as capture recovery.
        { unit: QuotedBytes, count: 65536L, copies: 2, },
        { unit: QuotedBytes, count: 4096L, copies: 1, },
        { unit: QuotedBytes, count: 32L + 12L + 16L, copies: 2, },
        // Both four-field AEAD envelopes, their parsed Strings and descriptor
        // comparison coexist with the original holding and failed writer.
        { unit: ValueNodeSlots, count: 24L, copies: 1, },
        { unit: DecodedTextBytes, count: envelopes, copies: 3, },
        { unit: CanonicalWireBytes, count: envelopes, copies: 4, },
        { unit: CanonicalWireBytes, count: size + descriptor, copies: 4, },
      ],
      [],
      RetainedAlongsideExecution,
    )
    is Some(capacity) else {
    return Err(Assembly("capacity_overflow"))
  }
  raw.store_preparing = true
  defer {
    raw.store_preparing = false
  }
  match
    keyed_lookup_body_grow(
      state,
      state.retained_bytes,
      state.execution_bytes,
      0L,
      Some(capacity),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard !state.closed &&
    state.left.lookup_issue is None &&
    state.selected_request is Some(same) &&
    physical_equal(same, request) &&
    request.attempts == 1L &&
    !request.io_complete &&
    history._retained_activation is Some(same) &&
    physical_equal(same, activation) else {
    return Err(Assembly("retired_declared_file_raw_store"))
  }
  raw.store_prepared = true
  Ok(())
}

///|
/// Construct the original private storage-binding DATA under the SAME lookup
/// before any Store callback. Source policy/classification and Request lifetime
/// come from its checked original, never from an arbitrary Host JSON record.
pub fn prepare_client_keyed_declared_file_raw_capture(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : ClientKeyedRequest,
  retention : @publication.PublicationContract,
  store_id : String,
  store_cid : String,
  availability_cid : String,
  issuer_cid : String,
  content_cid : String,
  size_bytes : Int,
  captured_at : String,
  now_ms : Int64,
  limits : @values.ReferenceLimits,
) -> Result[ClientKeyedNativeRawResponse, ClientKeyedRequestIssue] {
  guard limits.max_bytes > 0 &&
    request.assembly_accounting is Some(state) &&
    !state.closed &&
    !state.growing &&
    !state.identifying &&
    state.left.lookup_issue is None &&
    request.attempts == 1L &&
    !request.io_complete &&
    state.selected_request is Some(same) &&
    physical_equal(same, request) &&
    state.left.composed is Some(original) &&
    physical_equal(original.compiled, compiled) &&
    physical_equal(original.definition, definition) &&
    original.plan.keyed is Some(component) &&
    @publication.publication_contract_name(component.original.profile) ==
    "declared_file_content_read" &&
    client_keyed_acquisition_source_evidence_facts(original.keyed)
    is Some(facts) &&
    state.planned_requests is Some(requests) &&
    requests.get(request.row) is Some((same, slot)) &&
    physical_equal(same, request) &&
    state.known.get(slot) is Some((_, None, Some(history))) &&
    history._retained_activation is Some(activation) &&
    @publication.run_definition_lifetime(definition) is Some((_, until)) else {
    return Err(Assembly("foreign_declared_file_raw_capture"))
  }
  let scope = client_request_authority_scope_cid(activation.client_request)
  let units = store_id.length().to_int64() +
    store_cid.length().to_int64() +
    availability_cid.length().to_int64() +
    issuer_cid.length().to_int64() +
    facts.source_data_policy_cid.length().to_int64() +
    facts.data_classification.length().to_int64() +
    2L * scope.length().to_int64() +
    until.length().to_int64()
  guard @execution.checked_preparation_add_product(2048L, units, 6L)
    is Some(bound) else {
    return Err(Assembly("capacity_overflow"))
  }
  let bytes = Int64::min(bound, limits.max_bytes.to_int64()).to_int()
  let phase = match
    grow_keyed_lookup_protocol_metadata(state, bytes, 12L, copies=2) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard !state.closed &&
    state.left.lookup_issue is None &&
    state.selected_request is Some(same) &&
    physical_equal(same, request) &&
    request.attempts == 1L &&
    !request.io_complete &&
    history._retained_activation is Some(same) &&
    physical_equal(same, activation) else {
    return Err(Assembly("retired_declared_file_raw_capture"))
  }
  let binding = try {
    let writer = @encode.writer(bytes, 12, 2)
    @encode.begin_object(writer)
    for
      (name, text) in [
        ("content_store_id", store_id),
        ("content_store_cid", store_cid),
        ("workspace_scope_cid", scope),
        ("storage_scope", "workspace"),
        ("retention_class", "local-content"),
        ("expires_at", until),
        ("availability_evidence_cid", availability_cid),
        ("effective_data_policy_cid", facts.source_data_policy_cid),
        ("data_classification", facts.data_classification),
        ("issuer_contract_cid", issuer_cid),
        ("capture_authority_cid", scope),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Assembly("declared_file_raw_binding_encoding"))
  }
  match
    finish_keyed_lookup_protocol_metadata(state, phase, 12, 2, [], texts=[
      binding,
    ]) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let raw = match
    prepare_client_keyed_native_raw_response(
      compiled, definition, request, retention, binding, content_cid, size_bytes,
      captured_at, now_ms, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match prepare_client_keyed_declared_file_raw_store(request, raw) {
    Ok(_) => Ok(raw)
    Err(issue) => Err(issue)
  }
}

///|
// Capture the existing full dependency closure while the SAME lookup can
// still grow its reservation, before it becomes the Model's immutable Read.
// Each real writer/parser is funded from its original dimensions before call;
// no configured wire ceiling is substituted for a constructed body.
fn prepare_declared_file_lookup_dependencies(
  lookup : ClientKeyedLookupInput,
  completed : ClientKeyedNativeCompletion,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard lookup.identifying &&
    !lookup.closed &&
    lookup.holding is None &&
    lookup.left.lookup_issue is None &&
    lookup.native_sources is Some(state) &&
    state.dependency_bodies is None &&
    state.retention_base is Some(retention) &&
    lookup.native_completion is Some(same) &&
    physical_equal(same, completed) else {
    return Err(Assembly("foreign_declared_file_dependency_entry"))
  }
  // Callback/Result/Map/Array controls and bounded measuring-writer frames.
  // Per-member controls, spare slots, text and parser/workspace follow below.
  match
    grow_keyed_lookup_protocol_metadata(
      lookup,
      1,
      64L + 2L * max_depth.to_int64(),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let primary : Ref[ClientKeyedRequestIssue?] = Ref(None)
  let before = (bytes : Int, nodes : Int, depth : Int) => {
    if primary.val is Some(_) ||
      bytes < 0 ||
      nodes < 0 ||
      depth < 0 ||
      lookup.closed ||
      lookup.left.lookup_issue is Some(_) {
      return false
    }
    let capacity = @execution.execution_capacity_inventory(
      [
        // Shared capture-recovery units: parsed body, retained typed body and
        // partial constructor; Strings and canonical/hash writer backing.
        { unit: ValueNodeSlots, count: nodes.to_int64(), copies: 3, },
        { unit: DecodedTextBytes, count: bytes.to_int64(), copies: 3, },
        { unit: CanonicalWireBytes, count: bytes.to_int64(), copies: 4, },
        // The same original member's Map/spare-array entries and later opaque
        // getter/Node DATA aliases use the established fixed Host allowance.
        { unit: QuotedBytes, count: 4096L, copies: 1, },
      ],
      [{ unit: CursorRootSlots, count: depth.to_int64() + 1L, copies: 2, }],
      RetainedAlongsideExecution,
    )
    guard capacity is Some(capacity) else {
      primary.val = Some(Assembly("capacity_overflow"))
      return false
    }
    match
      keyed_lookup_body_grow(
        lookup,
        lookup.retained_bytes,
        lookup.execution_bytes,
        0L,
        Some(capacity),
      ) {
      Ok(_) => true
      Err(issue) => {
        primary.val = Some(issue)
        false
      }
    }
  }
  let bodies = match
    keyed_lookup_native_dependency_bodies_from_original(
      lookup,
      completed,
      retention,
      {
        max_entries: 4096,
        max_total_bytes: 16777216,
        max_references: 65536,
        max_depth,
      },
      max_nodes,
      max_depth,
      state.physical_source,
      Some(before),
    ) {
    Ok(value) => value
    Err(issue) => return Err(primary.val.unwrap_or(Dependency(issue)))
  }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.native_completion is Some(same) &&
    physical_equal(same, completed) &&
    state.dependency_bodies is None else {
    return Err(Assembly("retired_declared_file_dependency_entry"))
  }
  state.dependency_bodies = Some(bodies)
  Ok(())
}

///|
/// Borrow the SAME installing declaration selected by original Graph preparation
/// before planning. The profile owner already checked and retained this View;
/// no Source, Graph, policy, permission or replacement metadata is issued here.
pub fn bind_client_keyed_declared_file_physical_source(
  lookup : ClientKeyedLookupInput,
  declarations : Array[@row_host.RowDeclaration],
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard !lookup.closed &&
    !lookup.growing &&
    !lookup.identifying &&
    lookup.left.lookup_issue is None &&
    lookup.left.attempts == 0L &&
    lookup.planned_requests is None &&
    lookup.native_sources is Some(state) &&
    state.physical_source is None &&
    lookup.left.composed is Some(original) &&
    original.plan.keyed is Some(component) &&
    @publication.publication_contract_name(component.original.profile) ==
    "declared_file_content_read" else {
    return Err(Assembly("foreign_declared_file_source_body"))
  }
  // Getter/Some/original-pair controls only. The immutable String belongs to
  // the same installed declaration; later dependency parsing is funded there.
  match grow_keyed_lookup_protocol_metadata(lookup, 1, 6L) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.planned_requests is None &&
    state.physical_source is None else {
    return Err(Assembly("retired_declared_file_source_body"))
  }
  let mut selected = None
  for declaration in declarations {
    if @row_host.row_declaration_file_read_physical_source(
        declaration,
        component.original.profile,
      )
      is Some(body) {
      guard selected is None &&
        @publication.file_read_profile_physical_source_contract_cid(
          component.original.profile,
        ) ==
        Some(body.0) else {
        return Err(Assembly("foreign_declared_file_source_body"))
      }
      selected = Some(body)
    }
  }
  guard selected is Some(body) else {
    return Err(Assembly("missing_declared_file_source_body"))
  }
  state.physical_source = Some(body)
  Ok(())
}
