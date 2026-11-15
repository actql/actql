///|
/// Complete Source-only keyed Unit semantics. Both the direct capture and the
/// full completed lookup remain provenance of the actual computed producer.
/// This is neither a SingleSourceUnit nor a Model contribution/observation.
struct ClientEffectKeyedSourceUnit {
  parent : ClientEffectKeyedOriginal
  lookup : ClientKeyedLookupInput
  completed : ClientEffectKeyedCompletion
  host : @strategy.CapturedEffectRunDAG
  invocation : ClientEffectLocalInvocation
  scope : @publication.PublicationContract
  relations : Array[String]
  retention : @publication.PublicationContract
}

///|
priv enum ClientEffectKeyedCompletion {
  NativeSourceCompleted(ClientKeyedNativeCompletion)
  GenericSourceCompleted(ClientEffectKeyedGenericCompletion)
}

///|
/// Retained Unit H1/R8 and its relation/source/scope arrays and construction
/// tuples coexist with the encoded local invocation. All protocol, captured
/// rows and body strings remain owned by their existing lookup/Read.
pub fn client_effect_keyed_source_unit_construction_inventory() -> @execution.PreparationRepresentationUnits {
  let arrays = @execution.preparation_array_representation(3L, 6L, true).unwrap()
  {
    record_headers: arrays.record_headers + 5L,
    reference_slots: arrays.reference_slots + 13L,
    scalar_words: arrays.scalar_words + 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
fn client_effect_keyed_source_completed(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
) -> Bool {
  if parent.generic is Some(state) {
    return client_effect_keyed_generic_completed(parent, lookup, state)
  }
  client_effect_keyed_lookup_matches_parent(lookup, parent, parent.ledger) &&
  lookup.native_completion is Some(completed) &&
  lookup.identity is Some(_) &&
  lookup.read is Some(_) &&
  lookup.holding is Some(holding) &&
  @resources.holding_available(parent.ledger, holding) &&
  completed.authority_scope_cid ==
  client_request_authority_scope_cid(parent.request) &&
  lookup.native_sources is Some(sources) &&
  sources.sources.length() == 1 &&
  sources.relation is Some(_) &&
  sources.request is Some(request) &&
  client_request_identity_relation(parent.request, request) is SameRequest
}

///|
fn client_effect_keyed_source_host_matches(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  host : @strategy.CapturedEffectRunDAG,
) -> Bool {
  guard client_effect_keyed_source_completed(parent, lookup) &&
    client_keyed_acquisition_coordinates(parent.keyed) is Some((_, task, _)) &&
    lookup.read is Some(read) &&
    client_keyed_lookup_dag_matches(
      lookup,
      @strategy.captured_effect_run_dag(host),
    ) else {
    return false
  }
  @strategy.captured_effect_keyed_supplied_input_matches(
    @strategy.captured_effect_run_dag(host),
    task,
    @acquisition.keyed_join_input(parent.keyed.binding.join),
    read,
  )
}

///|
fn emit_client_effect_keyed_observation(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  started_at : String,
  completed_at : String,
  self_cid : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "capture_completed_at")
  @encode.string_value(writer, completed_at)
  @encode.key(writer, "capture_started_at")
  @encode.string_value(writer, started_at)
  @encode.key(writer, "captured_input_artifact_cids")
  @encode.begin_array(writer)
  @encode.end_array(writer)
  @encode.key(writer, "consistency")
  @encode.string_value(writer, "independent_snapshots")
  @encode.key(writer, "data_policy_cid")
  @encode.string_value(
    writer,
    prepared_client_effect_publication_data_policy_cid(parent.prepared).unwrap(),
  )
  @encode.key(writer, "invocation_template_cid")
  @encode.string_value(
    writer,
    @publication.run_evidence_value_identity(
      client_effect_compilation_template(parent.compilation),
    ),
  )
  @encode.key(writer, "replayability")
  @encode.begin_object(writer)
  @encode.key(writer, "availability_evidence_cids")
  @encode.begin_array(writer)
  @encode.end_array(writer)
  @encode.key(writer, "materialized")
  @encode.bool_value(writer, false)
  @encode.end_object(writer)
  if self_cid is Some(cid) {
    @encode.key(writer, "observation_set_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "source_evidence_cids")
  @encode.begin_array(writer)
  if parent.generic is Some(state) && state.completed is Some(completed) {
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(state.source.observation),
    )
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(completed.observation.source),
    )
  } else {
    for source in lookup.native_sources.unwrap().sources {
      @encode.string_value(
        writer,
        @publication.run_evidence_value_identity(source.observation),
      )
    }
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(
        lookup.native_completion.unwrap().source,
      ),
    )
  }
  @encode.end_array(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-observation-set/0.1")
  @encode.end_object(writer)
}

///|
/// Issue the Run observation from the full actual lookup and direct Source,
/// after the original installed owner has admitted its constructor geometry.
/// No Model slot, new capture, Source retry or durable ACK is synthesized.
pub fn issue_client_effect_keyed_captured_invocation(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  started_at : String,
  completed_at : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body? : ((String, @encode.EncodingConstructionGeometry) -> Bool)? = None,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  guard client_effect_keyed_source_completed(parent, lookup) &&
    physical_equal(parent.compilation.owner, parent.prepared) &&
    parent.compilation.compiled.infers.is_empty() &&
    parent.compilation.compiled.serialization is None &&
    physical_equal(parent.definition, run_definition) &&
    @publication.check_run_publication_program_binding(
      admission,
      run_definition,
      prepared_client_effect_computation_definition_cid(parent.prepared),
      prepared_client_effect_computation_semantics_cid(parent.prepared),
      prepared_client_effect_computation_environment_cid(parent.prepared),
    )
    is Ok(_) &&
    prepared_client_effect_publication_data_policy_cid(parent.prepared)
    is Some(_) else {
    return Err(
      @publication.RunEvidenceReferenceMismatch("keyed_effect_original"),
    )
  }
  if before_body is Some(back) {
    let shape = try {
      let measure = @encode.construction_measuring_writer(
        max_bytes, max_nodes, max_depth,
      )
      emit_client_effect_keyed_observation(
        parent,
        lookup,
        started_at,
        completed_at,
        Some("sha256:" + "0".repeat(64)),
        measure,
      )
      @encode.finish_construction_measurement(measure)
    } catch {
      _ => return Err(@publication.RunEvidenceEncoding)
    }
    if !back("observation_set", shape) ||
      !client_effect_keyed_source_completed(parent, lookup) {
      return Err(
        @publication.RunEvidenceReferenceMismatch("keyed_effect_construction"),
      )
    }
    // The existing Run invocation issuer owns a second sealed body. Measure
    // its exact fixed grammar before either body is built; only the future
    // observation CID is represented by its canonical SHA-256 width.
    let invocation_shape = try {
      let measure = @encode.construction_measuring_writer(
        max_bytes, max_nodes, max_depth,
      )
      @encode.begin_object(measure)
      @encode.key(measure, "invocation_template_cid")
      @encode.string_value(
        measure,
        @publication.run_evidence_value_identity(
          client_effect_compilation_template(parent.compilation),
        ),
      )
      @encode.key(measure, "observation_set_cid")
      @encode.string_value(measure, "sha256:" + "0".repeat(64))
      @encode.key(measure, "invocation_cid")
      @encode.string_value(measure, "sha256:" + "0".repeat(64))
      @encode.key(measure, "version")
      @encode.string_value(measure, "actql-run-invocation/0.1")
      @encode.end_object(measure)
      @encode.finish_construction_measurement(measure)
    } catch {
      _ => return Err(@publication.RunEvidenceEncoding)
    }
    if !back("run_invocation", invocation_shape) ||
      !client_effect_keyed_source_completed(parent, lookup) {
      return Err(
        @publication.RunEvidenceReferenceMismatch("keyed_effect_construction"),
      )
    }
  }
  let body = try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_client_effect_keyed_observation(
      parent,
      lookup,
      started_at,
      completed_at,
      None,
      writer,
    )
    @encode.finish(writer)
  } catch {
    _ => return Err(@publication.RunEvidenceEncoding)
  }
  let observation = match
    @publication.seal_run_evidence_value(
      "observation_set", body, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let invocation = match
    @publication.issue_run_invocation(
      client_effect_compilation_template(parent.compilation),
      observation,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard client_effect_keyed_source_completed(parent, lookup) else {
    return Err(
      @publication.RunEvidenceReferenceMismatch("retired_keyed_effect_original"),
    )
  }
  Ok((observation, invocation))
}

///|
pub fn prepare_client_effect_keyed_source_unit(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  host : @strategy.CapturedEffectRunDAG,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body? : ((String, @encode.EncodingConstructionGeometry) -> Bool)? = None,
) -> Result[ClientEffectKeyedSourceUnit, ClientEffectAcquiredEvidenceIssue] {
  if parent.generic is Some(state) {
    return prepare_client_effect_generic_keyed_source_unit(
      parent,
      lookup,
      state,
      host,
      retention,
      max_bytes,
      max_nodes,
      max_depth,
      before_body~,
    )
  }
  guard client_effect_keyed_source_host_matches(parent, lookup, host) &&
    lookup.native_completion is Some(completed) &&
    lookup.native_sources is Some(sources) &&
    sources.relation is Some(_) &&
    lookup.publication_identity is Some(identity) &&
    @publication.result_retention_bounds_equal(completed.retention, retention) &&
    sources.sources.all(source => {
      @publication.result_retention_bounds_equal(source.retention, retention)
    }) &&
    client_keyed_acquisition_coordinates(parent.keyed) is Some((unit, _, _)) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let program = @checked.effect_program_static_checked_computation(
    parent.prepared.candidate,
  )
  guard @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_result_import_count(program, unit) == Some(0) &&
    @checked.unit_import_cid_count(program, unit) == Some(0) else {
    return Err(Invocation(MissingUnit))
  }
  let observations = sources.sources.map(value => {
    @publication.run_evidence_value_identity(value.observation)
  })
  observations.push(@publication.run_evidence_value_identity(completed.source))
  let scopes = sources.sources.map(value => value.scope)
  scopes.push(identity.scope)
  let scope = match
    @publication.issue_combined_acquisition_scope(
      scopes,
      max_bytes,
      max_nodes,
      max_depth,
      before_body~,
    ) {
    Err(issue) => return Err(Relation(issue))
    Ok(value) => value
  }
  let invocation = match
    issue_client_effect_local_invocation_body(
      parent.prepared,
      unit,
      definition,
      values,
      contracts,
      @checked.checked_local_policy_cid(program),
      observations,
      max_bytes,
      max_nodes,
      max_depth,
      before_body~,
    ) {
    Err(issue) => return Err(Invocation(issue))
    Ok(value) => value
  }
  let relations = sources.sources.map(value => {
    @publication.publication_contract_identity(value.relation)
  })
  relations.push(@publication.publication_contract_identity(completed.relation))
  relations.sort_by(@canonical_value.compare_utf16)
  guard client_effect_keyed_source_host_matches(parent, lookup, host) &&
    lookup.native_completion is Some(same) &&
    physical_equal(same, completed) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  Ok({
    parent,
    lookup,
    completed: NativeSourceCompleted(completed),
    host,
    invocation,
    scope,
    relations,
    retention,
  })
}

///|
pub fn client_effect_keyed_source_unit_invocation(
  value : ClientEffectKeyedSourceUnit,
) -> ClientEffectLocalInvocation {
  value.invocation
}

///|
pub fn client_effect_keyed_source_unit_scope_json(
  value : ClientEffectKeyedSourceUnit,
) -> String {
  @publication.publication_contract_json(value.scope)
}

///|
fn client_effect_keyed_source_unit_current(
  value : ClientEffectKeyedSourceUnit,
) -> Bool {
  // Artifact publication follows Compute. Its Source closure retains the
  // exact successful completion even after the internal JOIN output port is
  // reclaimed. Active execution/read eligibility remains a separate gate.
  guard client_effect_keyed_source_completed(value.parent, value.lookup) &&
    client_keyed_acquisition_coordinates(value.parent.keyed)
    is Some((_, task, _)) &&
    value.lookup.read is Some(read) &&
    value.lookup.holding is Some(holding) &&
    client_keyed_lookup_dag_matches(
      value.lookup,
      @strategy.captured_effect_run_dag(value.host),
    ) else {
    return false
  }
  @strategy.captured_effect_keyed_completed_input_matches(
    value.host,
    task,
    @acquisition.keyed_join_input(value.parent.keyed.binding.join),
    read,
  ) &&
  !value.lookup.closed &&
  (value.lookup.read is Some(same) && physical_equal(same, read)) &&
  (value.lookup.holding is Some(same) && physical_equal(same, holding)) &&
  @resources.holding_available(value.parent.ledger, holding) &&
  (match value.completed {
    NativeSourceCompleted(completed) =>
      value.lookup.native_completion is Some(same) &&
      physical_equal(completed, same)
    GenericSourceCompleted(completed) =>
      value.parent.generic is Some(state) &&
      state.completed is Some(same) &&
      physical_equal(completed, same)
  })
}

///|
/// Only newly composed metadata. Complete lookup DATA is already retained by
/// its same original completion/export and must accompany these two bodies.
pub fn client_effect_keyed_source_unit_metadata_bodies(
  value : ClientEffectKeyedSourceUnit,
) -> Array[(String, String, String)] {
  [
    (
      "acquisition_scope",
      @publication.publication_contract_identity(value.scope),
      @publication.publication_contract_json(value.scope),
    ),
    (
      "result_retention_policy",
      @publication.publication_contract_identity(value.retention),
      @publication.publication_contract_json(value.retention),
    ),
  ]
}

///|
/// Borrow only the already-admitted inventory frozen on this SAME completed
/// Source lookup before its reservation became a holding. Return its existing
/// Option and Array themselves: no export, admission, wire copy, new container
/// or durable ACK. Caller publication still binds its checked Run data policy;
/// these original bodies may only accompany the same custody/time bounds.
pub fn client_effect_keyed_cached_dependency_bodies(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  retention : @publication.PublicationContract,
) -> Array[@publication.CapturedEffectDependencyBody]? {
  if parent.generic is Some(state) {
    return client_effect_keyed_generic_cached_dependency_bodies(
      parent, lookup, state, retention,
    )
  }
  // Refuse incomplete/foreign-time metadata before any Source callback. The
  // one current boundary follows the existing immutable completed inventory.
  guard !lookup.closed &&
    !lookup.growing &&
    !lookup.identifying &&
    lookup.left.lookup_issue is None &&
    !@resources.reservation_open(lookup.reservation) &&
    lookup.completed is Some(_) &&
    lookup.native_completion is Some(completed) &&
    lookup.native_sources is Some(state) &&
    state.dependency_bodies is Some(bodies) &&
    state.retention_base is Some(original_retention) &&
    @publication.result_retention_bounds_equal(original_retention, retention) &&
    @publication.result_retention_bounds_equal(completed.retention, retention) &&
    client_effect_keyed_source_completed(parent, lookup) else {
    return None
  }
  // The current callback may reenter cleanup. Pure final correspondence only;
  // never restart an export or another current walk to repair that change.
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.native_completion is Some(same) &&
    physical_equal(same, completed) &&
    lookup.native_sources is Some(same_state) &&
    physical_equal(same_state, state) &&
    state.retention_base is Some(same_retention) &&
    physical_equal(same_retention, original_retention) &&
    state.dependency_bodies is Some(same_bodies) &&
    physical_equal(same_bodies, bodies) else {
    return None
  }
  state.dependency_bodies
}
