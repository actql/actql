///|
pub(all) enum NativeResidentEffectPreviewIssue {
  InvalidLimits
  ForeignEvidence
  Encoding
  Request(@host.ClientRequestIdentityIssue)
  Source(@host.ClientEffectSourceArtifactIssue)
  Identity(@host.ClientEffectLocalIdentityIssue)
  Capability(@catalog.WriteCapabilityIssue)
  Mapping(@catalog.DeclarationUseIssue)
  Target(@catalog.TargetObservationIssue)
  Footprint(@catalog.WriteCollectionRequestIssue)
  Preview(@publication.EffectPreviewIdentityIssue)
  Dispatch(@effect.EffectIdentityIssue)
  Keys(@effect.EffectPreviewApplyIdentityIssue)
  Binding(@host.ClientCapturedEffectPreviewIssue)
  Plan(@resident.ResidentEffectPreviewPlanIssue)
}

///|
/// The complete checked single-member Preview of this retained consumer.
/// It carries no approval, current mutation grant, waiting commit or physical
/// Store custody. Original input and Provider-use owners remain with the caller.
pub(all) struct NativeResidentEffectPreview {
  wire : String
  authoring : @publication.RunEvidenceValue
  source : @publication.PublicationContract
  preview : @strategy.CapturedEffectPreviewInputs
  proof : @strategy.CapturedEffectPlanProof
  identity : @host.ClientEffectLocalIdentity
  keys : Array[@effect.EffectDispatchKey]
  capability : @catalog.WriteCapabilityEvidence
}

///|
fn preview_text(
  writer : @encode.Writer,
  key : String,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, key)
  @encode.string_value(writer, value)
}

///|
fn preview_wire(
  writer : @encode.Writer,
  wire : String,
  limits : @host.ClientCapturedEffectPreviewLimits,
) -> Unit raise @encode.EncodeFailure {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => raise @encode.InvalidStructure
  }
  let value = @canonical.from_source(
    source,
    limits.max_nodes,
    limits.max_depth,
    limits.max_wire_bytes,
    data_keys=true,
  ) catch {
    _ => raise @encode.InvalidStructure
  }
  @canonical.emit_value(value, writer)
}

///|
/// Join real target observations with the original retained Result through
/// existing semantic Preview, request-scope, local-identity and plan Owners.
/// This finite initial route has one update member; unsupported shapes fail
/// without rereading Source, computing again or replacing an input identity.
pub fn prepare_native_resident_effect_preview(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  request : @host.ClientRequestIdentity,
  stage : Int,
  effect_id : String,
  local_result : Int,
  artifact : @host.ClientEffectLocalResultArtifact,
  invocation : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  source_binding_cid : String,
  store_authority_cid : String,
  mapping : @catalog.ExecutionMapping,
  runtime_bundle_cid : String,
  current_catalog : @catalog.CatalogObservation,
  targets : Array[
    (
      @catalog.SingleWriteRequest,
      String,
      @catalog.TargetObservation,
      @catalog.TargetPreviewRow,
    ),
  ],
  limits : @host.ClientCapturedEffectPreviewLimits,
  export_limits : @host.PublicationOutputExportLimits,
) -> Result[NativeResidentEffectPreview, NativeResidentEffectPreviewIssue] {
  if limits.max_wire_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_work < 1 ||
    targets.is_empty() ||
    targets.length() > export_limits.max_rows {
    return Err(InvalidLimits)
  }
  guard @host.client_effect_member_descriptor(
      materials.prepared,
      stage,
      effect_id,
      limits.max_work,
    )
    is Ok(descriptor) &&
    descriptor.0 == 0 &&
    descriptor.2 == "update" &&
    descriptor.4 == mapping.mapping_ref &&
    descriptor.5 == mapping.mapping_cid &&
    descriptor.6 is Some(result_name) &&
    @strategy.captured_effect_inputs_count(inputs) == 1 else {
    return Err(ForeignEvidence)
  }
  let scope = match
    @host.prepared_client_effect_request_scope(materials.prepared, request) {
    Ok(value) => value
    Err(issue) => return Err(Request(issue))
  }
  let source = match
    consumer.issue_effect_source_artifact(
      materials,
      inputs,
      0,
      artifact,
      invocation,
      retention,
      source_binding_cid,
      store_authority_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  let identity = match
    @host.issue_source_free_client_effect_local_identity(
      materials.prepared,
      inputs,
      0,
      artifact,
      limits.max_work,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let requests = targets.map(value => value.0)
  let rows : Array[@catalog.TargetPreviewRow] = []
  for (checked_request, _, observed, supplied) in targets {
    match @catalog.check_execution_single_write(mapping, checked_request) {
      Ok(_) => ()
      Err(issue) => return Err(Mapping(issue))
    }
    let row = match
      @catalog.prepare_observed_target_preview_row(
        checked_request,
        observed,
        limits.max_wire_bytes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Target(issue))
    }
    if @catalog.target_preview_row_guard_cid(row) !=
      @catalog.target_preview_row_guard_cid(supplied) ||
      @catalog.target_preview_row_target_wire(row) !=
      @catalog.target_preview_row_target_wire(supplied) ||
      @catalog.target_preview_row_before_wire(row) !=
      @catalog.target_preview_row_before_wire(supplied) ||
      @catalog.target_preview_row_after_wire(row) !=
      @catalog.target_preview_row_after_wire(supplied) {
      return Err(ForeignEvidence)
    }
    rows.push(row)
  }
  let capability = match
    @catalog.prepare_write_capability_evidence(
      requests[0],
      runtime_bundle_cid,
      @catalog.SerialRows,
      limits.max_wire_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capability(issue))
  }
  match @catalog.recheck_write_capability(capability, current_catalog) {
    Ok(_) => ()
    Err(issue) => return Err(Capability(issue))
  }
  for checked_request in requests {
    match
      @catalog.check_write_capability_request(
        capability, checked_request, runtime_bundle_cid,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Capability(issue))
    }
  }
  let footprint = match
    @catalog.single_write_member_footprint(
      requests,
      export_limits.max_rows,
      limits.max_wire_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Footprint(issue))
  }
  let effects = @checked.effect_program_static_effects(
    @host.prepared_client_effect_computation_candidate(materials.prepared),
  )
  guard @results.effect_mapping_shape_count(
      @results.effect_mapping_rules_shapes(
        @results.effect_static_candidate_mapping_rules(effects),
      ),
    ) ==
    1 &&
    @results.effect_plan_terminal_for_member(
      @results.effect_static_candidate_mapping_rules(effects),
      0,
      limits.plan.max_fields,
      limits.plan.max_work,
    )
    is Ok(Some(terminal)) else {
    return Err(ForeignEvidence)
  }
  let definition = @host.prepared_client_effect_computation_definition_cid(
    materials.prepared,
  )
  let authoring = match
    @publication.seal_run_evidence_value(
      "authoring_context",
      "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"" +
      definition +
      "\",\"annotations\":[]}",
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let run_cid = @publication.publication_contract_identity(
    materials.run_definition,
  )
  let authoring_cid = @publication.run_evidence_value_identity(authoring)
  // Seed fields are replaced by the existing Preview author and dispatch-key
  // Owner before any binding is returned; they are not acquired evidence.
  let pending = "sha256:" + "0".repeat(64)
  let draft = try {
    let writer = @encode.writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_object(writer)
    preview_text(writer, "version", "actql-effect-preview/0.1")
    preview_text(writer, "sensitivity", "private")
    preview_text(writer, "retention_class", "authority-evidence")
    @encode.key(writer, "encryption_required")
    @encode.bool_value(writer, true)
    for
      (key, value) in [
        (
          "program_semantics_cid",
          @host.prepared_client_effect_computation_semantics_cid(
            materials.prepared,
          ),
        ),
        ("program_definition_cid", definition),
        (
          "invocation_cid",
          @publication.publication_contract_identity(invocation),
        ),
        ("run_identity_cid", run_cid),
        (
          "compiled_plan_cid",
          @publication.publication_contract_identity(
            @host.client_effect_compilation_compiled_plan(materials.compilation),
          ),
        ),
        (
          "check_environment_cid",
          @host.prepared_client_effect_computation_environment_cid(
            materials.prepared,
          ),
        ),
      ] {
      preview_text(writer, key, value)
    }
    @encode.key(writer, "authoring_context")
    preview_wire(
      writer,
      @publication.run_evidence_value_json(authoring),
      limits,
    )
    for
      key in [
        "barrier_provenance_cids", "model_task_contract_cids", "model_invocation_evidence_cids",
        "model_response_artifact_cids",
      ] {
      @encode.key(writer, key)
      @encode.begin_array(writer)
      @encode.end_array(writer)
    }
    @encode.key(writer, "model_derived")
    @encode.bool_value(writer, false)
    @encode.key(writer, "effects")
    @encode.begin_array(writer)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("effect_id", descriptor.1),
        ("effect_kind", descriptor.2),
        ("target", descriptor.3),
        ("mapping", descriptor.4),
        ("resolved_mapping_contract_cid", descriptor.5),
        (
          "effect_identity_cid",
          @host.client_effect_local_identity_cid(identity),
        ),
        ("source_result", result_name),
        (
          "effect_plan_logical_cid",
          @results.effect_plan_pipeline_cid(
            terminal,
            limits.max_wire_bytes,
            limits.max_nodes,
            limits.max_depth,
          ),
        ),
        (
          "result_artifact_cid",
          @host.client_effect_local_result_artifact_cid(artifact),
        ),
        ("preview_strength", "full_diff"),
        ("source_binding_cid", source_binding_cid),
        (
          "capability_evidence_cid",
          @catalog.write_capability_identity(capability),
        ),
        (
          "authority_scope_cid",
          @request_scope.logical_request_scope_authority(scope),
        ),
        ("approval", "required"),
        ("on_item_failure", descriptor.7),
      ] {
      preview_text(writer, key, value)
    }
    // The installed Mapping is already checked against this member. Its
    // required permission values are copied exactly, not inferred from Source.
    let mapping_source = match
      @source.parse_json_bytes_preserving(@utf8.encode(mapping.body), {
        max_input_bytes: limits.max_wire_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(value) => value
      Err(_) => return Err(Encoding)
    }
    let mapping_value = @canonical.from_source(
      mapping_source,
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
      data_keys=true,
    )
    guard @canonical.object_field(mapping_value, "required_permissions")
      is Some(permissions) else {
      return Err(ForeignEvidence)
    }
    @encode.key(writer, "required_permissions")
    @canonical.emit_value(permissions, writer)
    @encode.key(writer, "write_footprint")
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("kind", footprint.0),
        ("provider_namespace", footprint.1),
        ("provider_boundary_cid", footprint.2),
        ("resource_identity_scheme_cid", footprint.3),
        ("resource_kind", footprint.4),
      ] {
      preview_text(writer, key, value)
    }
    @encode.key(writer, "provider_object_identity_cids")
    @encode.begin_array(writer)
    for cid in footprint.5 {
      @encode.string_value(writer, cid)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    for key in ["count", "max_items"] {
      @encode.key(writer, key)
      @encode.number_value(writer, rows.length().to_double())
    }
    @encode.key(writer, "changes")
    @encode.begin_array(writer)
    for row in rows {
      @encode.begin_object(writer)
      @encode.key(writer, "target_row_identity")
      preview_wire(writer, @catalog.target_preview_row_target_wire(row), limits)
      @encode.key(writer, "target_guard")
      @encode.begin_object(writer)
      preview_text(writer, "state", "version")
      preview_text(
        writer,
        "version_cid",
        @catalog.target_preview_row_guard_cid(row),
      )
      @encode.end_object(writer)
      for
        (key, value) in [
          ("before", @catalog.target_preview_row_before_wire(row)),
          ("after", @catalog.target_preview_row_after_wire(row)),
          ("intended_changes", @catalog.target_preview_row_changes_wire(row)),
        ] {
        @encode.key(writer, key)
        @encode.begin_object(writer)
        preview_text(writer, "state", "present")
        @encode.key(writer, "value")
        preview_wire(writer, value, limits)
        @encode.end_object(writer)
      }
      preview_text(writer, "row_preview_cid", pending)
      preview_text(writer, "row_idempotency_key", pending)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "row_order")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    preview_text(writer, "effect_member_preview_cid", pending)
    @encode.key(writer, "executed")
    @encode.bool_value(writer, false)
    @encode.end_object(writer)
    @encode.end_array(writer)
    @encode.key(writer, "executed")
    @encode.bool_value(writer, false)
    preview_text(writer, "effect_preview_cid", pending)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let (semantic, preview_identity) = match
    @publication.author_effect_preview_semantic_wire(
      draft,
      run_cid,
      authoring_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  let keys : Array[@effect.EffectDispatchKey] = []
  let cids : Array[String] = []
  for index in 0..<rows.length() {
    let correlation = @publication.effect_preview_row_correlation_wire(
      preview_identity, 0, index,
    ).unwrap()
    let key = match
      @effect.prepare_effect_dispatch_key(
        scope,
        @publication.effect_preview_semantic_identity(preview_identity),
        correlation,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Dispatch(issue))
    }
    keys.push(key)
    cids.push(@effect.effect_dispatch_key_cid(key))
  }
  let wire = match
    @publication.complete_effect_preview_dispatch_keys(
      semantic,
      [cids],
      run_cid,
      authoring_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  match
    @effect.admit_effect_preview_apply_identity(
      wire,
      run_cid,
      authoring_cid,
      scope,
      [keys],
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Keys(issue))
  }
  let preview = match
    consumer.bind_effect_preview_inputs(
      materials,
      inputs,
      invocation,
      stage,
      wire,
      authoring_cid,
      [identity],
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  let proof = match
    consumer.verify_effect_preview_plan(
      inputs,
      preview,
      0,
      local_result,
      export_limits,
      limits.plan.max_fields,
      limits.plan.max_work,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  Ok({ wire, authoring, source, preview, proof, identity, keys, capability, })
}
