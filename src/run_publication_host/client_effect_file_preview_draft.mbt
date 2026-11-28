///|
/// Checked identities of one selected file Effect. Rows and permissions are
/// supplied by the same owner in their original order.
pub(all) struct ClientEffectFilePreviewMemberDraft {
  effect_id : String
  effect_kind : String
  target : String
  mapping : String
  mapping_cid : String
  effect_identity_cid : String
  source_result : String
  result_artifact_cid : String
  binding_cid : String
  authority_scope_cid : String
  capabilities : ClientEffectFilePreviewIdentity
  on_item_failure : String
  resource_kind : String
  plan_cid : String?
  count : Int
}

///|
fn[T] project_client_effect_file_preview_member(
  fields : ClientEffectFilePreviewMemberDraft,
  pending : String,
  changes : T,
  permissions : T,
  empty : T,
  unexecuted : T,
  text : (String) -> T,
  integer : (Int) -> T,
  object : (Array[(String, T)]) -> T,
) -> T {
  let entries = [
    ("approval", text("required")),
    ("authority_scope_cid", text(fields.authority_scope_cid)),
    ("capability_evidence_cid", text(fields.capabilities.capability_cid)),
    ("changes", changes),
    ("count", integer(fields.count)),
    ("effect_id", text(fields.effect_id)),
    ("effect_identity_cid", text(fields.effect_identity_cid)),
    ("effect_kind", text(fields.effect_kind)),
    ("effect_member_preview_cid", text(pending)),
    ("executed", unexecuted),
    ("mapping", text(fields.mapping)),
    ("max_items", integer(fields.count)),
    ("on_item_failure", text(fields.on_item_failure)),
    ("preview_strength", text("full_diff")),
    ("required_permissions", permissions),
    ("resolved_mapping_contract_cid", text(fields.mapping_cid)),
    ("result_artifact_cid", text(fields.result_artifact_cid)),
    ("row_order", empty),
    ("source_binding_cid", text(fields.binding_cid)),
    ("source_result", text(fields.source_result)),
    ("target", text(fields.target)),
    (
      "write_footprint",
      object([
        ("kind", text("opaque")),
        ("provider_boundary_cid", text(fields.binding_cid)),
        ("provider_namespace", text("local-mock-file")),
        ("provider_object_identity_cids", empty),
        (
          "resource_identity_scheme_cid",
          text(fields.capabilities.resource_identity_cid),
        ),
        ("resource_kind", text(fields.resource_kind)),
      ]),
    ),
  ]
  if fields.plan_cid is Some(plan) {
    entries.insert(9, ("effect_plan_logical_cid", text(plan)))
  }
  object(entries)
}

///|
pub fn client_effect_file_preview_member_json(
  fields : ClientEffectFilePreviewMemberDraft,
  pending : String,
  changes : Array[Json],
  permissions : Json,
) -> Json {
  project_client_effect_file_preview_member(
    fields,
    pending,
    Json::array(changes),
    permissions,
    Json::array([]),
    Json::boolean(false),
    Json::string,
    count => Json::number(count.to_double()),
    file_preview_json_object,
  )
}

///|
/// Emit the same original member without reconstructing its row documents.
/// Exact ordinals are borrowed from its retained target and capture owner.
pub fn emit_client_effect_file_preview_member(
  writer : @encode.Writer,
  fields : ClientEffectFilePreviewMemberDraft,
  pending : String,
  row_at : (Int) -> @encode.EncodedDocument?,
  permission_count : Int,
  permission_at : (Int) -> String?,
) -> Unit raise @encode.EncodeFailure {
  let changes : FilePreviewRowEmitter = out => {
    @encode.begin_array(out)
    for index in 0..<fields.count {
      guard row_at(index) is Some(row) else { raise @encode.InvalidStructure }
      @encode.emit_document(out, row)
    }
    @encode.end_array(out)
  }
  let permissions : FilePreviewRowEmitter = out => {
    @encode.begin_array(out)
    for index in 0..<permission_count {
      guard permission_at(index) is Some(permission) else {
        raise @encode.InvalidStructure
      }
      @encode.string_value(out, permission)
    }
    @encode.end_array(out)
  }
  let empty : FilePreviewRowEmitter = out => {
    @encode.begin_array(out)
    @encode.end_array(out)
  }
  let unexecuted : FilePreviewRowEmitter = out => @encode.bool_value(out, false)
  let emit = project_client_effect_file_preview_member(
    fields,
    pending,
    changes,
    permissions,
    empty,
    unexecuted,
    file_preview_text_emitter,
    count => out => @encode.number_value(out, count.to_double()),
    file_preview_object_emitter,
  )
  emit(writer)
}

///|
/// Immutable original identities and evidence selected for one whole Preview.
pub(all) struct ClientEffectFilePreviewDraftHeader {
  check_environment_cid : String
  compiled_plan_cid : String
  invocation_cid : String
  program_definition_cid : String
  program_semantics_cid : String
  run_cid : String
  pending_cid : String
  barriers : Array[String]
  model_task : String?
  model_invocations : Array[String]
  model_responses : Array[String]
}

///|
fn[T] project_client_effect_file_preview_draft(
  header : ClientEffectFilePreviewDraftHeader,
  authoring : T,
  effects : T,
  text : (String) -> T,
  strings : (Array[String]) -> T,
  flag : (Bool) -> T,
  object : (Array[(String, T)]) -> T,
) -> T {
  object([
    ("authoring_context", authoring),
    ("barrier_provenance_cids", strings(header.barriers)),
    ("check_environment_cid", text(header.check_environment_cid)),
    ("compiled_plan_cid", text(header.compiled_plan_cid)),
    ("effect_preview_cid", text(header.pending_cid)),
    ("effects", effects),
    ("encryption_required", flag(true)),
    ("executed", flag(false)),
    ("invocation_cid", text(header.invocation_cid)),
    ("model_derived", flag(header.model_task is Some(_))),
    ("model_invocation_evidence_cids", strings(header.model_invocations)),
    ("model_response_artifact_cids", strings(header.model_responses)),
    (
      "model_task_contract_cids",
      strings(
        match header.model_task {
          Some(task) => [task]
          None => []
        },
      ),
    ),
    ("program_definition_cid", text(header.program_definition_cid)),
    ("program_semantics_cid", text(header.program_semantics_cid)),
    ("retention_class", text("authority-evidence")),
    ("run_identity_cid", text(header.run_cid)),
    ("sensitivity", text("private")),
    ("version", text("actql-effect-preview/0.1")),
  ])
}

///|
pub fn client_effect_file_preview_draft_json(
  header : ClientEffectFilePreviewDraftHeader,
  authoring : Json,
  effects : Array[Json],
) -> Json {
  project_client_effect_file_preview_draft(
    header,
    authoring,
    Json::array(effects),
    Json::string,
    names => Json::array(names.map(Json::string)),
    Json::boolean,
    file_preview_json_object,
  )
}

///|
/// Stream the same draft using the existing admitted authoring and members.
pub fn emit_client_effect_file_preview_draft(
  writer : @encode.Writer,
  header : ClientEffectFilePreviewDraftHeader,
  authoring : @encode.EncodedDocument,
  members : Int,
  emit_member : (Int, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  let context : FilePreviewRowEmitter = out => {
    @encode.emit_document(out, authoring)
  }
  let effects : FilePreviewRowEmitter = out => {
    @encode.begin_array(out)
    for index in 0..<members {
      emit_member(index, out)
    }
    @encode.end_array(out)
  }
  let emit = project_client_effect_file_preview_draft(
    header,
    context,
    effects,
    file_preview_text_emitter,
    names => {
      out => {
        @encode.begin_array(out)
        for name in names {
          @encode.string_value(out, name)
        }
        @encode.end_array(out)
      }
    },
    enabled => out => @encode.bool_value(out, enabled),
    file_preview_object_emitter,
  )
  emit(writer)
}

///|
/// Resolve fields from the same checked Mapping and locally issued identity.
/// The selected Target and original Result must agree with that exact member.
pub fn prepare_client_effect_file_preview_member_draft(
  owner : PreparedClientEffectComputation,
  request : ClientRequestIdentity,
  inputs : @strategy.CapturedEffectInputs,
  index : Int,
  artifact : ClientEffectLocalResultArtifact,
  identity : ClientEffectLocalIdentity,
  installed_target : String,
  installed_mapping : String,
  installed_mapping_cid : String,
  binding : String,
  resource : String,
  capability : ClientEffectFilePreviewIdentity,
  rows : Int,
  max_fields : Int,
  limits : ClientEffectComputationLimits,
  before_permissions : (Int) -> Bool,
) -> Result[(ClientEffectFilePreviewMemberDraft, Array[String]), Unit] {
  guard client_effect_local_identity_matches(identity, owner, index, artifact) &&
    @strategy.captured_effect_inputs_match_computation(inputs, owner.graph) &&
    @strategy.captured_effect_input_at(inputs, index) is Some(input) &&
    prepared_client_effect_request_scope(owner, request) is Ok(scope) else {
    return Err(())
  }
  let stage = @strategy.captured_effect_input_stage(input)
  let headers = @checked.effect_program_static_headers(owner.candidate)
  guard @syntax.effect_header_at(headers, index) is Some(header) &&
    client_effect_member_descriptor(
      owner,
      stage,
      @syntax.effect_header_id(header),
      limits.effects.max_work,
    )
    is Ok(descriptor) &&
    descriptor.0 == index &&
    descriptor.2 == "update" &&
    descriptor.3 == installed_target &&
    descriptor.4 == installed_mapping &&
    descriptor.5 == installed_mapping_cid &&
    descriptor.6 is Some(result_name) &&
    descriptor.8 is None else {
    return Err(())
  }
  let rules = @stage_results.effect_static_candidate_mapping_rules(
    @checked.effect_program_static_effects(owner.candidate),
  )
  guard @stage_results.effect_plan_terminal_for_member(
      rules,
      index,
      max_fields,
      limits.effects.max_work,
    )
    is Ok(Some(terminal)) else {
    return Err(())
  }
  let selected = @stage_results.effect_mapping_rule_selection(terminal.rule)
  guard before_permissions(selected.required_permissions.length()) else {
    return Err(())
  }
  let plan_cid = @stage_results.effect_plan_pipeline_cid(
    terminal,
    limits.effects.max_admission_text_bytes,
    limits.effects.max_admission_nodes,
    limits.effects.max_admission_depth,
  ) catch {
    _ => return Err(())
  }
  Ok(
    (
      {
        effect_id: descriptor.1,
        effect_kind: descriptor.2,
        target: installed_target,
        mapping: installed_mapping,
        mapping_cid: installed_mapping_cid,
        effect_identity_cid: identity.cid,
        source_result: result_name,
        result_artifact_cid: client_effect_local_result_artifact_cid(artifact),
        binding_cid: binding,
        authority_scope_cid: @request_scope.logical_request_scope_authority(
          scope,
        ),
        capabilities: capability,
        on_item_failure: descriptor.7,
        resource_kind: resource,
        plan_cid: Some(plan_cid),
        count: rows,
      },
      @environment.mapping_permission_required_names(selected),
    ),
  )
}
