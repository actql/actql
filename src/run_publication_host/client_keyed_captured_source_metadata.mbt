///|
/// Bind the SAME already-captured Query metadata before request planning.
/// The actual original Source supplied identity/logical/observation once;
/// neither the Source scan nor its observation issuer is repeated here.
pub fn bind_client_keyed_query_source_metadata(
  lookup : ClientKeyedLookupInput,
  index : Int,
  requirement : @planning.QueryRequirement,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  request : ClientRequestIdentity,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedNativeSourceEvidence, ClientKeyedRequestIssue] {
  bind_client_keyed_captured_source_metadata(
    lookup,
    index,
    Query(requirement),
    identity,
    logical,
    observation,
    request,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// The original complete-input capture retains its SourceAcquisition. Derive
/// that original from the lookup's existing captured inventory, never a caller
/// Query substitute, reported coordinate or a reconstructed Source check.
pub fn bind_client_keyed_whole_source_metadata(
  lookup : ClientKeyedLookupInput,
  index : Int,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  request : ClientRequestIdentity,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedNativeSourceEvidence, ClientKeyedRequestIssue] {
  guard lookup.left.composed is Some(composed) &&
    @row_host.row_captured_inputs_source_original_at(composed.captures, index)
    is Some(original) else {
    return Err(Assembly("foreign_whole_source_metadata"))
  }
  bind_client_keyed_captured_source_metadata(
    lookup,
    index,
    Whole(original),
    identity,
    logical,
    observation,
    request,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn bind_client_keyed_captured_source_metadata(
  lookup : ClientKeyedLookupInput,
  index : Int,
  original : ClientInferSourceOriginal,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  request : ClientRequestIdentity,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedNativeSourceEvidence, ClientKeyedRequestIssue] {
  guard max_bytes > 0 &&
    max_nodes > 0 &&
    max_depth > 0 &&
    native_source_metadata_phase(lookup, index) &&
    client_keyed_native_left_identity(lookup) is Some(_) &&
    lookup.left.composed is Some(composed) &&
    composed.keyed.program is KeyedEffect(prepared) &&
    prepared_client_effect_request_scope(prepared, request) is Ok(_) &&
    composed.plan.keyed is Some(component) &&
    @publication.publication_contract_name(component.original.profile) ==
    "declared_file_content_read" &&
    composed.sources.get(index) is Some(source) &&
    @row_host.row_captured_inputs_source_at(composed.captures, index)
    is Some(same_source) &&
    physical_equal(source, same_source) &&
    client_infer_source_tuple_matches(
      composed.plan.owner,
      source,
      identity,
      original,
      index,
    ) &&
    client_keyed_left_available(lookup.left) else {
    return Err(Assembly("foreign_captured_source_metadata"))
  }
  // The final external current callback may retire or reenter this source.
  // Keep the original phase; an inner completed slot is never overwritten.
  guard native_source_metadata_phase(lookup, index) else {
    return Err(Assembly("claimed_captured_source_metadata"))
  }
  lookup.identifying = true
  defer {
    lookup.identifying = false
  }
  let state = match keyed_lookup_source_metadata_state(lookup, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let facts = match original {
    Query(requirement) =>
      @planning.query_requirement_source_evidence_facts(requirement)
    Whole(acquisition) =>
      @planning.source_acquisition_evidence_facts(acquisition)
  }
  guard facts is Some(facts) else {
    return Err(Assembly("missing_captured_source_facts"))
  }
  let request_bound = match original {
    Query(requirement) =>
      @encode.document_bytes(
        @planning.query_material_request(
          @planning.query_requirement_material(requirement),
        ),
      )
    Whole(acquisition) => {
      let original = @acquisition.source_acquisition_request(acquisition)
      // The selected unfiltered file Source has an empty typed Request. Its
      // required durable document is exactly {}, without a Value/Ref walk.
      // Existing nonempty request encoding retains its original codec limit.
      if @acquisition.parameterized_request_field_count(original) == 0 {
        2
      } else {
        max_bytes
      }
    }
  }
  let controls = @execution.preparation_representation_cost({
    record_headers: 12L,
    reference_slots: 23L + 16L * (index.to_int64() + 1L),
    scalar_words: 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  guard @execution.checked_preparation_add_product(
      4096L,
      @publication.publication_contract_json(retention).length().to_int64() +
      facts.source_ref.length().to_int64() +
      @publication.run_evidence_value_json(logical).length().to_int64() +
      @publication.run_evidence_value_json(observation).length().to_int64() +
      request_bound.to_int64(),
      6L,
    )
    is Some(bound) else {
    return Err(Assembly("capacity_overflow"))
  }
  let bytes = Int64::min(bound, max_bytes.to_int64()).to_int()
  let phase = match
    grow_keyed_lookup_protocol_metadata(
      lookup,
      bytes,
      7L,
      copies=5,
      extra_controls=controls,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.planned_requests is None &&
    state.sources.length() == index &&
    state.source_identity is None else {
    return Err(Assembly("retired_captured_source_metadata"))
  }
  // This Some and the new Source metadata are constructed only after the
  // same lookup has funded them. The original argument/capture stays borrowed
  // across growth; the identifying fence excludes reentrant slot creation.
  state.source_identity = Some(identity)
  match
    @publication.admit_completed_source_input_logical(
      logical,
      @query.captured_source_relation_logical_cid(identity),
      @query.captured_source_relation_schema_cid(identity),
      facts.source_contract_cid,
      "{\"stable\":false,\"keys\":[]}",
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(SourceLogical(Admission(issue)))
  }
  match
    @publication.admit_completed_source_observation_binding(
      observation,
      logical,
      facts.source_ref,
      facts.source_contract_cid,
      client_request_authority_scope_cid(request),
      facts.source_data_policy_cid,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => ()
    Err(_) => return Err(Assembly("foreign_captured_source_observation"))
  }
  let document = match original {
    Query(requirement) =>
      @planning.query_material_request(
        @planning.query_requirement_material(requirement),
      )
    Whole(acquisition) =>
      match
        @acquisition.parameterized_request_document(
          @acquisition.source_acquisition_request(acquisition),
          request_bound,
          max_nodes,
          max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Wire(issue))
      }
  }
  // The original nonempty Request emitter may observe a Ref. No new protocol
  // body follows a reentered/retired original; an empty request invokes none.
  guard client_keyed_left_available(lookup.left) &&
    !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.planned_requests is None &&
    state.sources.length() == index else {
    return Err(Assembly("retired_captured_source_metadata"))
  }
  let request_cid = match original {
    Query(requirement) =>
      @planning.query_material_cids(
        @planning.query_requirement_material(requirement),
      ).0
    Whole(_) =>
      match @sha.text_hex(@encode.document_text(document)) {
        Ok(value) => "sha256:" + value
        Err(_) => return Err(Assembly("captured_source_request_encoding"))
      }
  }
  let source_retention = match
    @publication.issue_result_retention_for_data_policy(
      retention,
      facts.source_data_policy_cid,
      bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(@publication.Contract(issue)))
  }
  let (relation, ordering, scope) = match
    @publication.issue_captured_source_input_relation(
      logical,
      observation,
      request_cid,
      @query.captured_source_relation_row_count(identity),
      source_retention,
      bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let result = {
    identity,
    logical,
    observation,
    relation,
    ordering,
    scope,
    retention: source_retention,
    request: document,
    request_cid,
  }
  state.sources.push(result)
  state.source_identity = None
  match
    finish_keyed_lookup_protocol_metadata(
      lookup,
      phase,
      max_nodes,
      max_depth,
      [relation, ordering, scope, source_retention],
      texts=match original {
        Query(_) => [request_cid]
        Whole(_) => [@encode.document_text(document), request_cid]
      },
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // Workspace return may observe current. A retired/replaced original cannot
  // escape as a successful metadata binding after that last callback.
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.planned_requests is None &&
    state.sources.get(index) is Some(same) &&
    physical_equal(same, result) else {
    return Err(Assembly("retired_captured_source_metadata"))
  }
  Ok(result)
}
