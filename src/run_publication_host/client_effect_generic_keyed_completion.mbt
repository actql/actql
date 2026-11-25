///|
// Immutable Direct Source provenance on the same generic lookup. It has no
// Native transport/profile/activation or physical cleanup claim.
priv struct ClientEffectKeyedGenericSource {
  identity : @query.CapturedSourceRelationIdentity
  logical : @publication.RunEvidenceValue
  observation : @publication.RunEvidenceValue
  relation : @publication.PublicationContract
  ordering : @publication.PublicationContract
  scope : @publication.PublicationContract
  retention : @publication.PublicationContract
  request : @encode.EncodedDocument
  request_cid : String
}

///|
priv struct ClientEffectKeyedGenericCompletion {
  observation : ClientKeyedLookupObservation
  relation : @publication.PublicationContract
  ordering : @publication.PublicationContract
  relation_scope : @publication.PublicationContract
  scope : @publication.PublicationContract
  retention : @publication.PublicationContract
}

///|
// SAME Source original/lookup custody. Completed Rows and each actual RowRun
// remain on lookup.known; Store content_ref custody remains on its real Store.
priv struct ClientEffectKeyedGenericState {
  lookup : ClientKeyedLookupInput
  source : ClientEffectKeyedGenericSource
  retention : @publication.PublicationContract
  mut observed_at : String?
  mut completed : ClientEffectKeyedGenericCompletion?
  mut bodies : Array[@publication.CapturedEffectDependencyBody]?
}

///|
fn client_effect_keyed_generic_metadata_phase(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
) -> Bool {
  client_effect_keyed_plan_graph_is_generic(parent.plan) &&
  parent.generic is None &&
  !lookup.closed &&
  !lookup.growing &&
  !lookup.identifying &&
  lookup.left.lookup_issue is None &&
  lookup.left.requests == 0L &&
  lookup.left.attempts == 0L &&
  lookup.planned_requests is None &&
  lookup.accepted == 0 &&
  lookup.completed is None &&
  lookup.holding is None &&
  @resources.reservation_open(lookup.reservation)
}

///|
/// Bind the original Direct capture once, before any keyed dispatch. This
/// constructs Source metadata only; no Native protocol or attempt is invented.
pub fn prepare_client_effect_keyed_generic_source_metadata(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  source_evidence : @publication.RunEvidenceValue,
  retention_contract : String,
  available_until : String,
  delete_by : String,
  metadata_delete_by : String,
  metadata_policy : String,
  clock_contract : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, ClientKeyedRequestIssue] {
  guard max_bytes > 0 &&
    max_nodes > 0 &&
    max_depth > 0 &&
    client_effect_keyed_generic_metadata_phase(parent, lookup) &&
    client_effect_keyed_lookup_matches_parent(lookup, parent, parent.ledger) &&
    lookup.left.composed is Some(composed) &&
    composed.sources is [source] &&
    @query.captured_source_relation_identity_matches_source(identity, source) &&
    @query.captured_source_relation_dependency_bodies(identity, source)
    is Some(_) else {
    return Err(Assembly("foreign_generic_source_metadata"))
  }
  guard client_effect_keyed_generic_metadata_phase(parent, lookup) else {
    return Err(Assembly("claimed_generic_source_metadata"))
  }
  lookup.identifying = true
  defer {
    lookup.identifying = false
  }
  let controls = @execution.preparation_representation_cost({
    // Generic state H1/R6, Source H1/R9, retained parent Some H1/R1/W1,
    // original variant/facts/Result/three-contract tuple and time Option.
    record_headers: 8L,
    reference_slots: 29L,
    scalar_words: 6L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  match
    keyed_lookup_body_grow(
      lookup,
      lookup.retained_bytes,
      lookup.execution_bytes,
      controls,
      None,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let original : ClientInferSourceOriginal = if @row_host.row_captured_input_requirement_at(
      composed.captures,
      0,
    )
    is Some(requirement) {
    Query(requirement)
  } else if @row_host.row_captured_inputs_source_original_at(
      composed.captures,
      0,
    )
    is Some(acquisition) {
    Whole(acquisition)
  } else {
    return Err(Assembly("missing_generic_source_original"))
  }
  let facts = match original {
    Query(requirement) =>
      @planning.query_requirement_source_evidence_facts(requirement)
    Whole(acquisition) =>
      @planning.source_acquisition_evidence_facts(acquisition)
  }
  guard facts is Some(facts) else {
    return Err(Assembly("generic_source_facts"))
  }
  let document = match original {
    Query(requirement) =>
      @planning.query_material_request(
        @planning.query_requirement_material(requirement),
      )
    Whole(acquisition) => {
      // The original typed Request emitter supplies its exact constructor
      // geometry. Grow the existing reservation before constructing its wire.
      let shape = match
        @acquisition.parameterized_request_canonical_geometry(
          @acquisition.source_acquisition_request(acquisition),
          max_bytes,
          max_nodes,
          max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Wire(issue))
      }
      let constructed = with_keyed_protocol_construction(
        lookup,
        Int::max(1, shape.bytes),
        shape.nodes.to_int64(),
        max_nodes,
        max_depth,
        fn(_) {
          let document = match
            @acquisition.parameterized_request_canonical_document(
              @acquisition.source_acquisition_request(acquisition),
              shape.bytes,
              shape.nodes,
              shape.depth,
            ) {
            Ok(value) => value
            Err(issue) => return Err(Wire(issue))
          }
          Ok(
            keyed_protocol_built(document, texts=[
              @encode.document_text(document),
            ]),
          )
        },
        _ => Ok(()),
      )
      match constructed {
        Ok(settled) => settled.value
        Err(issue) => return Err(issue)
      }
    }
  }
  let request_cid = match original {
    Query(requirement) =>
      @planning.query_material_cids(
        @planning.query_requirement_material(requirement),
      ).0
    Whole(_) =>
      match @sha.text_hex(@encode.document_text(document)) {
        Ok(value) => "sha256:" + value
        Err(_) => return Err(Assembly("generic_source_request_encoding"))
      }
  }
  let component = match parent.plan.component {
    GenericKeyedPlan(component) => component
    NativeKeyedPlan(_) => return Err(Assembly("foreign_generic_source_plan"))
  }
  let units = @publication.run_evidence_value_json(logical).length().to_int64() +
    @publication.run_evidence_value_json(source_evidence).length().to_int64() +
    facts.source_ref.length().to_int64() +
    retention_contract.length().to_int64() +
    available_until.length().to_int64() +
    delete_by.length().to_int64() +
    2L * metadata_delete_by.length().to_int64() +
    metadata_policy.length().to_int64() +
    clock_contract.length().to_int64() +
    component.original.response_data_policy_cid.length().to_int64()
  guard @execution.checked_preparation_add_product(4096L, units, 6L)
    is Some(bound) else {
    return Err(Assembly("capacity_overflow"))
  }
  let bytes = Int64::min(bound, max_bytes.to_int64()).to_int()
  let constructed = with_keyed_protocol_construction(
    lookup,
    bytes,
    18L,
    max_nodes,
    max_depth,
    fn(_) {
      guard parent.generic is None &&
        !lookup.closed &&
        lookup.left.lookup_issue is None &&
        lookup.left.requests == 0L &&
        lookup.left.attempts == 0L else {
        return Err(Assembly("retired_generic_source_metadata"))
      }
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
      if @publication.admit_completed_source_observation_binding(
          source_evidence,
          logical,
          facts.source_ref,
          facts.source_contract_cid,
          client_request_authority_scope_cid(parent.request),
          facts.source_data_policy_cid,
          max_bytes,
          max_nodes,
          max_depth,
        )
        is Err(_) {
        return Err(Assembly("foreign_generic_source_observation"))
      }
      let wire = try {
        let writer = @encode.writer(bytes, 11, 2)
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
        _ => return Err(Assembly("generic_retention_encoding"))
      }
      let retention = match
        @publication.seal_publication_contract(
          "result_retention_policy", wire, bytes, 11, 2,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Identity(@publication.Contract(issue)))
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
          source_evidence,
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
      let source = {
        identity,
        logical,
        observation: source_evidence,
        relation,
        ordering,
        scope,
        retention: source_retention,
        request: document,
        request_cid,
      }
      let state = {
        lookup,
        source,
        retention,
        observed_at: None,
        completed: None,
        bodies: None,
      }
      Ok(
        keyed_protocol_built(
          state,
          contracts=[retention, source_retention, relation, ordering, scope],
          texts=[request_cid],
        ),
      )
    },
    state => {
      parent.generic = Some(state)
      Ok(())
    },
    copies=6,
  )
  let state = match constructed {
    Ok(settled) => settled.value
    Err(issue) => return Err(issue)
  }
  let retention = state.retention
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    parent.generic is Some(same) &&
    physical_equal(same, state) else {
    return Err(Assembly("retired_generic_source_metadata"))
  }
  Ok(retention)
}

///|
/// Finish the real generic lookup under its SAME open reservation. Its source
/// observation and complete dependency closure exist before holding conversion.
pub fn finish_client_effect_keyed_generic_publication_input(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  observed_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@execution.SuppliedRelationRead, ClientKeyedRequestIssue] {
  guard parent.generic is Some(state) &&
    physical_equal(state.lookup, lookup) &&
    !lookup.closed &&
    !lookup.growing &&
    !lookup.identifying &&
    lookup.left.lookup_issue is None &&
    client_effect_keyed_lookup_matches_parent(lookup, parent, parent.ledger) &&
    @values.timestamp_epoch_milliseconds(observed_at) is Some(_) else {
    return Err(Assembly("foreign_generic_completion"))
  }
  if state.completed is Some(_) {
    return finish_client_keyed_lookup_input(lookup)
  }
  guard state.observed_at is None &&
    lookup.holding is None &&
    @resources.reservation_open(lookup.reservation) else {
    return Err(Assembly("late_generic_completion_purpose"))
  }
  let controls = @execution.preparation_representation_cost({
    // Purpose tuple/Option and retained observation-time Option. The caller's
    // exact UTC String is borrowed, not reencoded or copied here.
    record_headers: 3L,
    reference_slots: 3L,
    scalar_words: 5L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  match
    keyed_lookup_body_grow(
      lookup,
      lookup.retained_bytes,
      lookup.execution_bytes,
      controls,
      None,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  state.observed_at = Some(observed_at)
  finish_client_keyed_lookup_publication_input(
    lookup,
    max_bytes,
    max_nodes,
    max_depth,
    retain_body=true,
    generic_completion=Some((observed_at, max_bytes, max_nodes, max_depth)),
  )
}

///|
fn prepare_client_effect_keyed_generic_completion(
  lookup : ClientKeyedLookupInput,
  observed_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard lookup.identifying &&
    !lookup.closed &&
    lookup.holding is None &&
    lookup.left.lookup_issue is None &&
    lookup.left.composed is Some(original) &&
    original.origin is SourceEffectOrigin(parent) &&
    parent.generic is Some(state) &&
    physical_equal(state.lookup, lookup) &&
    state.completed is None &&
    state.bodies is None &&
    state.observed_at == Some(observed_at) &&
    lookup.identity_receipt is Some(receipt) &&
    lookup.identity_bodies is Some(_) &&
    lookup.publication_identity is Some(requests) &&
    lookup.completed is Some(_) &&
    client_effect_keyed_plan_graph_is_generic(parent.plan) else {
    return Err(Assembly("unavailable_generic_completion_originals"))
  }
  // These are the real RowRun/Request originals. No Native activation, raw
  // response archive, Journal ACK or successful attempt receipt is synthesized.
  for (_, read, history) in lookup.known {
    guard read is Some(read) &&
      history is Some(history) &&
      history._retained_capture is Some(capture) &&
      history.request.io_complete &&
      history.request.attempts > 0L &&
      @row_host.keyed_row_capture_matches_request(
        capture,
        history.request.request,
      ) &&
      @execution.supplied_relation_read_available(read) else {
      return Err(Assembly("incomplete_generic_response_history"))
    }
  }
  let logical_cid = @execution.logical_relation_cid(
    @execution.completed_relation_export_identity(receipt),
  )
  let schema_cid = @execution.relation_schema_cid(
    @execution.completed_relation_export_schema_identity(receipt),
  )
  let snapshot = @execution.output_stream_identity(
      @execution.completed_relation_export_content(receipt),
    ).0
  let controls = @execution.preparation_representation_cost({
    // Observation H1/R4, completion H1/R6, its Some H1/R1/W1,
    // Source-input/evidence result pair and relation/order/scope tuple.
    record_headers: 8L,
    reference_slots: 19L,
    scalar_words: 6L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let units = logical_cid.length().to_int64() +
    schema_cid.length().to_int64() +
    snapshot.length().to_int64() +
    observed_at.length().to_int64() +
    @publication.publication_contract_json(state.retention).length().to_int64() +
    requests.static_request_cid.length().to_int64() +
    client_request_authority_scope_cid(parent.request).length().to_int64()
  guard @execution.checked_preparation_add_product(4096L, units, 6L)
    is Some(bound) else {
    return Err(Assembly("capacity_overflow"))
  }
  let bytes = Int64::min(bound, max_bytes.to_int64()).to_int()
  let constructed = with_keyed_protocol_construction(
    lookup,
    bytes,
    32L,
    max_nodes,
    max_depth,
    fn(_) {
      let (input, source) = match
        build_keyed_lookup_source_observation(
          lookup,
          logical_cid,
          schema_cid,
          snapshot,
          client_request_authority_scope_cid(parent.request),
          observed_at,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let (relation, ordering, relation_scope) = match
        @publication.issue_captured_source_input_relation(
          input,
          source,
          requests.static_request_cid,
          @execution.output_stream_identity(
            @execution.completed_relation_export_content(receipt),
          ).3,
          state.retention,
          bytes,
          max_nodes,
          max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Identity(issue))
      }
      let observation = {
        lookup,
        input,
        source,
        logical_relation_cid: logical_cid,
      }
      let completed = {
        observation,
        relation,
        ordering,
        relation_scope,
        scope: requests.scope,
        retention: state.retention,
      }
      Ok(
        keyed_protocol_built(
          completed,
          contracts=[relation, ordering, relation_scope],
          evidence=[input, source],
        ),
      )
    },
    completed => {
      state.completed = Some(completed)
      Ok(())
    },
    copies=6,
    extra_controls=controls,
  )
  let completed = match constructed {
    Ok(settled) => settled.value
    Err(issue) => return Err(issue)
  }
  prepare_client_effect_keyed_generic_dependencies(
    parent, lookup, state, completed, max_nodes, max_depth,
  )
}
