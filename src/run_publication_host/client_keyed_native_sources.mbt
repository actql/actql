///|
// Private cleanup ownership only; never a caller-supplied permission or proof.
priv enum ClientKeyedSourceIdentityCustody {
  ScannedHere
  BorrowedOriginal
}

///|
/// Captured Source metadata on the existing left/lookup owner. No Request,
/// Source, Account or cleanup owner is created by this borrowed original.
pub struct ClientKeyedNativeSourceEvidence {
  identity : @query.CapturedSourceRelationIdentity
  priv identity_custody : ClientKeyedSourceIdentityCustody
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
// Metadata on the SAME lookup cleanup owner. Never exposed as an authority,
// standing registry, allocation domain or independent physical cleanup handle.
priv struct ClientKeyedNativeSourceState {
  sources : Array[ClientKeyedNativeSourceEvidence]
  mut source_scan : @query.CapturedSourceCellIdentityScan?
  mut source_identity : @query.CapturedSourceRelationIdentity?
  mut source_identity_custody : ClientKeyedSourceIdentityCustody
  mut request : ClientRequestIdentity?
  mut relation : ClientKeyedNativeLeftRelation?
  mut retention_base : @publication.PublicationContract?
  mut dependency_bodies : Array[@publication.CapturedEffectDependencyBody]?
  mut physical_source : (String, String)?
}

///|
pub struct ClientKeyedNativeLeftRelation {
  artifact : @publication.PublicationContract
  ordering : @publication.ResultOrderingEvidence
  scope : @publication.PublicationContract
  retention : @publication.PublicationContract
}

///|
// Same pure no-dispatch phase before and after callbacks. The cache index is
// actual completed Source inventory, never a reported CID or caller Bool.
fn native_source_metadata_phase(
  lookup : ClientKeyedLookupInput,
  index : Int,
) -> Bool {
  !lookup.closed &&
  !lookup.growing &&
  !lookup.identifying &&
  lookup.planned_requests is None &&
  lookup.left.requests == 0L &&
  lookup.left.attempts == 0L &&
  lookup.left.lookup_issue is None &&
  (match lookup.native_sources {
    None => index == 0
    Some(state) =>
      index == state.sources.length() &&
      state.source_scan is None &&
      state.source_identity is None &&
      state.relation is None
  })
}

///|
/// Identify and bind ONE actual already-captured Whole Source before dispatch.
/// The same lookup backs each actual scan peak and closed protocol metadata.
/// No Model Read is claimed while later acquisition may still mutate its census.
pub fn prepare_client_keyed_native_whole_source_evidence(
  lookup : ClientKeyedLookupInput,
  index : Int,
  original : @acquisition.SourceAcquisition,
  acquisition : @row_host.RowInputAcquisition,
  capture : @row_host.RowSourceCapture,
  request : ClientRequestIdentity,
  retention : @publication.PublicationContract,
  observed_at : String,
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
) -> Result[ClientKeyedNativeSourceEvidence, ClientKeyedRequestIssue] {
  guard client_keyed_native_left_identity(lookup) is Some(left) &&
    native_source_metadata_phase(lookup, index) &&
    lookup.left.composed is Some(composed) &&
    composed.keyed.program is KeyedEffect(prepared) &&
    prepared_client_effect_request_scope(prepared, request) is Ok(_) &&
    @row_host.row_captured_inputs_source_original_at(composed.captures, index)
    is Some(same_original) &&
    physical_equal(same_original, original) &&
    composed.sources.get(index) is Some(source) &&
    @row_host.row_capture_source(capture) is Ok(same_source) &&
    physical_equal(same_source, source) &&
    @query.captured_source_matches_input_acquisition(source, original) &&
    select_client_direct_acquisition_occurrences(composed.plan.owner, max_work)
    is Ok(direct) &&
    client_direct_acquisition_occurrence_at(direct, index) is Some((_, _, task)) &&
    client_keyed_left_available(lookup.left) else {
    return Err(Assembly("foreign_native_source_metadata"))
  }
  // Pure final fence: a nested completed Source or started request plan wins.
  guard native_source_metadata_phase(lookup, index) else {
    return Err(Assembly("claimed_native_source_metadata"))
  }
  lookup.identifying = true
  let result = build_client_keyed_native_whole_source_evidence(
    lookup, left, composed, source, task, index, original, acquisition, capture,
    request, retention, observed_at, max_rows, values, payload_wire, logical_wire,
    schema, max_work, workspace, max_bytes, max_nodes, max_depth,
  )
  lookup.identifying = false
  match result {
    Ok(value) => Ok(value)
    Err(issue) => {
      keyed_lookup_fail(lookup.left, issue) |> ignore
      Err(issue)
    }
  }
}

///|
fn build_client_keyed_native_whole_source_evidence(
  lookup : ClientKeyedLookupInput,
  left : ClientKeyedNativeLeftIdentity,
  composed : ClientComposedKeyedOriginal,
  source : @query.CapturedInputSource,
  task : Int,
  index : Int,
  original : @acquisition.SourceAcquisition,
  acquisition : @row_host.RowInputAcquisition,
  capture : @row_host.RowSourceCapture,
  request : ClientRequestIdentity,
  retention : @publication.PublicationContract,
  observed_at : String,
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
) -> Result[ClientKeyedNativeSourceEvidence, ClientKeyedRequestIssue] {
  let state = match keyed_lookup_source_metadata_state(lookup, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Entry record9R plus the retained EncodedDocument H1/R1/W3,
  // scan/identity/result/tuple/Some refusal frontiers, old/new
  // cache backing and the later Native borrowed identity/logical/observation
  // arrays. All counts use this actual Source index, not a policy maximum.
  let controls = @execution.preparation_representation_cost({
    record_headers: 25L,
    reference_slots: 39L + 16L * (index.to_int64() + 1L),
    scalar_words: 26L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let basis_r = lookup.retained_bytes
  let basis_e = lookup.execution_bytes
  guard @query.captured_source_cell_identity_start_capacity(source)
    is Some(start) else {
    return Err(Assembly("native_source_start_capacity"))
  }
  match
    keyed_lookup_body_grow(lookup, basis_r, basis_e, controls, Some(start)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let scan = match
    @query.start_captured_source_cell_identity(
      source, max_rows, values, payload_wire, logical_wire, schema, max_work, workspace,
      16777216,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  state.source_scan = Some(scan)
  let mut previous_work = 0L
  while true {
    guard @query.captured_source_cell_identity_next_capacity(scan) is Some(next) else {
      return Err(Assembly("native_source_next_capacity"))
    }
    match
      keyed_lookup_body_grow(lookup, basis_r, basis_e, controls, Some(next)) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let advanced = @query.advance_captured_source_cell_identity(scan, 31, next)
    let actual = @query.captured_source_cell_identity_work(scan)
    let delta = actual - previous_work
    if delta < 0L || delta > 9223372036854775807L - lookup.native_left_work {
      return Err(Assembly("native_source_work_overflow"))
    }
    lookup.native_left_work += delta
    previous_work = actual
    match advanced {
      Err(issue) => return Err(Capture(issue))
      Ok((false, _)) => ()
      Ok((true, _)) => break
    }
  }
  let identity = match @query.finish_captured_source_cell_identity(scan) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  state.source_identity_custody = ScannedHere
  state.source_identity = Some(identity)
  state.source_scan = None
  // Existing metadata codec grows the same reservation before any body is
  // encoded. Keep completed identity/body backing alive beside these outputs.
  let order_fields = @acquisition.parameterized_request_field_count(
    @acquisition.source_acquisition_request(original),
  )
  guard @execution.preparation_array_representation(
      if order_fields > 1 {
        1L
      } else {
        0L
      },
      if order_fields > 1 {
        order_fields.to_int64()
      } else {
        0L
      },
      true,
    )
    is Some(ordering) &&
    @execution.preparation_representation_cost(ordering) is Some(ordering_bytes) &&
    @execution.checked_preparation_add_product(controls, ordering_bytes, 1L)
    is Some(document_controls) else {
    return Err(Assembly("capacity_overflow"))
  }
  let metadata_phase = match
    grow_keyed_lookup_protocol_metadata(
      lookup,
      max_bytes,
      7L,
      copies=7,
      extra_controls=document_controls,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.native_left_identity is Some(same) &&
    physical_equal(same, left) &&
    state.sources.length() == index else {
    return Err(Assembly("retired_native_source_metadata"))
  }
  let dag = match composed.keyed.program {
    KeyedEffect(prepared) =>
      @strategy.checked_effect_computation_graph(prepared.graph)
    _ => return Err(ForeignLeft)
  }
  let logical = match
    issue_captured_whole_source_input_logical(
      dag,
      source,
      identity,
      original,
      task~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SourceLogical(issue))
  }
  let facts = @row_host.row_input_acquisition_facts(acquisition)
  let observation = match
    @row_host.issue_row_input_source_evidence(
      acquisition,
      capture,
      identity,
      logical,
      client_request_authority_scope_cid(request),
      facts.source_data_policy_cid,
      observed_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SourceObservation(issue))
  }
  let request_document = match
    @acquisition.parameterized_request_canonical_document(
      @acquisition.source_acquisition_request(original),
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  // The final Ref-emission callback may retire the original. No derived
  // artifact follows it without retaining that original current observation.
  guard client_keyed_left_available(lookup.left) &&
    !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.planned_requests is None &&
    state.sources.length() == index else {
    return Err(Assembly("retired_native_source_metadata"))
  }
  let request_cid = match
    @sha.text_hex(@encode.document_text(request_document)) {
    Ok(hash) => "sha256:" + hash
    Err(_) => return Err(Assembly("native_source_request_encoding"))
  }
  let source_retention = match
    @publication.issue_result_retention_for_data_policy(
      retention,
      facts.source_data_policy_cid,
      max_bytes,
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
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let result = {
    identity,
    identity_custody: ScannedHere,
    logical,
    observation,
    relation,
    ordering,
    scope,
    retention: source_retention,
    request: request_document,
    request_cid,
  }
  state.sources.push(result)
  state.source_identity = None
  match
    finish_keyed_lookup_protocol_metadata(
      lookup,
      metadata_phase,
      max_nodes,
      max_depth,
      [relation, ordering, scope, source_retention],
      evidence=[logical, observation],
      texts=[@encode.document_text(request_document), request_cid],
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.planned_requests is None &&
    lookup.left.attempts == 0L &&
    state.sources.get(index) is Some(same) &&
    physical_equal(same, result) else {
    return Err(Assembly("retired_native_source_metadata"))
  }
  Ok(result)
}

///|
/// Borrow the same original Source observation; no scan, reseal or callback.
pub fn client_keyed_native_source_evidence(
  lookup : ClientKeyedLookupInput,
  index : Int,
) -> ClientKeyedNativeSourceEvidence? {
  guard client_keyed_native_left_identity(lookup) is Some(_) else {
    return None
  }
  guard lookup.native_sources is Some(state) else { return None }
  state.sources.get(index)
}

///|
fn native_left_relation_phase(
  lookup : ClientKeyedLookupInput,
  state : ClientKeyedNativeSourceState,
  source_count : Int,
) -> Bool {
  !lookup.closed &&
  !lookup.growing &&
  !lookup.identifying &&
  lookup.planned_requests is None &&
  lookup.left.requests == 0L &&
  lookup.left.attempts == 0L &&
  lookup.left.lookup_issue is None &&
  state.sources.length() == source_count &&
  source_count > 0 &&
  state.source_scan is None &&
  state.source_identity is None &&
  state.relation is None
}

///|
/// Bind the actual completed left to ALL admitted contributing Source Relations
/// and the original checked left policy. This is not a Result publication or
/// an attempt/right-side coverage claim. Source authority/Journal remain Host duties.
pub fn prepare_client_keyed_native_left_relation(
  lookup : ClientKeyedLookupInput,
  request : ClientRequestIdentity,
  retention : @publication.PublicationContract,
  issuer : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientKeyedNativeLeftRelation, ClientKeyedRequestIssue] {
  guard client_keyed_native_left_identity(lookup) is Some(left) &&
    lookup.native_sources is Some(state) &&
    state.request is Some(same_request) &&
    client_request_identity_relation(same_request, request) is SameRequest &&
    lookup.left.composed is Some(composed) &&
    composed.keyed.program is KeyedEffect(prepared) &&
    prepared_client_effect_request_scope(prepared, request) is Ok(_) &&
    composed.plan.keyed is Some(component) &&
    component.original.policies.left is Some(policy) &&
    native_left_relation_phase(lookup, state, composed.sources.length()) else {
    return Err(Assembly("incomplete_native_left_sources"))
  }
  // All Source logical/observation issuers above admitted complete original
  // captures. Never reinterpret unknown/partial external envelopes as complete.
  // The declared-file consumer borrows already-retained Source bodies. Price
  // its next closed envelopes from those original wires/CIDs, not the policy
  // ceiling. Native's selected caller keeps its existing codec geometry.
  let writer_bytes = if @publication.publication_contract_name(
      component.original.profile,
    ) ==
    "declared_file_content_read" {
    let mut units = issuer.length().to_int64() +
      policy.cid.length().to_int64() +
      @publication.publication_contract_json(retention).length().to_int64() +
      left.producer_contract_cid.length().to_int64() +
      left.logical_value_cid.length().to_int64() +
      left.relation_schema_cid.length().to_int64() +
      left.computation_contract_cid.length().to_int64() +
      client_request_authority_scope_cid(request).length().to_int64()
    for source in state.sources {
      let borrowed_units = @publication.publication_contract_json(
          source.relation,
        )
        .length()
        .to_int64() +
        @publication.publication_contract_json(source.scope).length().to_int64()
      guard @execution.checked_preparation_add_product(
          units, borrowed_units, 1L,
        )
        is Some(next) else {
        return Err(Assembly("capacity_overflow"))
      }
      units = next
    }
    guard @execution.checked_preparation_add_product(4096L, units, 6L)
      is Some(bytes) else {
      return Err(Assembly("capacity_overflow"))
    }
    Int64::min(bytes, max_bytes.to_int64()).to_int()
  } else {
    max_bytes
  }
  let metadata_phase = match
    grow_keyed_lookup_protocol_metadata(
      lookup,
      writer_bytes,
      state.sources.length().to_int64(),
      copies=5,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard native_left_relation_phase(lookup, state, composed.sources.length()) &&
    lookup.native_left_identity is Some(same_left) &&
    physical_equal(same_left, left) else {
    return Err(Assembly("claimed_native_left_relation"))
  }
  lookup.identifying = true
  defer {
    lookup.identifying = false
  }
  let scope = match
    @publication.issue_combined_acquisition_scope(
      state.sources.map(value => value.scope),
      writer_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let selected_retention = match
    @publication.issue_result_retention_for_data_policy(
      retention,
      policy.cid,
      writer_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(@publication.Contract(issue)))
  }
  // Derivation inputs are a sorted distinct CID set (artifacts.md), while
  // state.sources and the checked computation retain every actual occurrence.
  // Assemble that set from admitted originals before issuing the new body;
  // never normalize or reseal an incoming evidence envelope.
  let inputs = state.sources.map(value => {
    @publication.publication_contract_identity(value.relation)
  })
  inputs.sort()
  let mut index = inputs.length() - 1
  while index > 0 {
    if inputs[index] == inputs[index - 1] {
      inputs.remove(index) |> ignore
    }
    index -= 1
  }
  let ordering = match
    @publication.issue_local_result_occurrence_evidence(
      left.producer_contract_cid,
      left.logical_value_cid,
      left.relation_schema_cid,
      left.computation_contract_cid,
      inputs,
      @publication.publication_contract_identity(scope),
      policy.cid,
      issuer,
      client_request_authority_scope_cid(request),
      writer_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Derivation(issue))
  }
  let artifact = match
    @publication.issue_computed_input_relation(
      ordering,
      scope,
      selected_retention,
      left.rows,
      "complete",
      writer_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let result = { artifact, ordering, scope, retention: selected_retention, }
  state.relation = Some(result)
  match
    finish_keyed_lookup_protocol_metadata(
      lookup,
      metadata_phase,
      max_nodes,
      max_depth,
      [
        artifact,
        scope,
        selected_retention,
        @publication.result_ordering_evidence_contract(ordering),
        @publication.result_ordering_derivation_contract(ordering),
      ],
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.planned_requests is None &&
    lookup.left.attempts == 0L &&
    state.relation is Some(same) &&
    physical_equal(same, result) else {
    return Err(Assembly("retired_native_left_relation"))
  }
  Ok(result)
}

///|
pub fn client_keyed_native_left_relation(
  lookup : ClientKeyedLookupInput,
) -> ClientKeyedNativeLeftRelation? {
  guard client_keyed_native_left_identity(lookup) is Some(_) &&
    lookup.native_sources is Some(state) else {
    return None
  }
  state.relation
}

///|
// One original Source metadata inventory on the lookup for both installed
// declared-file and Native writers. This neither owns physical Sources nor
// issues another Request/current permission or a completed Model input.
fn keyed_lookup_source_metadata_state(
  lookup : ClientKeyedLookupInput,
  request : ClientRequestIdentity,
) -> Result[ClientKeyedNativeSourceState, ClientKeyedRequestIssue] {
  let state = match lookup.native_sources {
    Some(state) => {
      guard state.request is Some(same) &&
        client_request_identity_relation(same, request) is SameRequest else {
        return Err(Assembly("foreign_native_source_request"))
      }
      state
    }
    None => {
      let array = @shape.reference_array_retained_extent(1L, 0L).unwrap()
      let fixed = @execution.preparation_representation_cost({
        record_headers: 3L + array.record_headers,
        reference_slots: 10L + array.reference_slots,
        scalar_words: 3L + array.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }).unwrap()
      match
        keyed_lookup_body_grow(
          lookup,
          lookup.retained_bytes,
          lookup.execution_bytes,
          fixed,
          None,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard !lookup.closed &&
        lookup.native_sources is None &&
        lookup.planned_requests is None else {
        return Err(Assembly("claimed_native_source_state"))
      }
      let state = {
        sources: [],
        source_scan: None,
        source_identity: None,
        source_identity_custody: BorrowedOriginal,
        request: Some(request),
        relation: None,
        retention_base: None,
        dependency_bodies: None,
        physical_source: None,
      }
      lookup.native_sources = Some(state)
      state
    }
  }
  Ok(state)
}
