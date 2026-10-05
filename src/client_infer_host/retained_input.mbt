///|
/// Only the actual live Model inventory can identify the pre-INFER completion
/// to retain. Caller-supplied rows or an equal output cannot issue this token.
pub fn export_prepared_input(
  active : Execution,
  prepared : @model.ModelPreparedCallSet,
  binding : String,
) -> Result[
  @input.ClientInferRetainedInputExport,
  @input.ClientInferRetainedInputIssue,
] {
  guard !active.reclaimed &&
    !active.cancelled &&
    !active.advancing &&
    active.model is Some(model) &&
    @model.prepared_model_matches(prepared, model) &&
    @model.prepared_model_input(prepared) is Some(input) else {
    return Err(@input.BindingMismatch)
  }
  @input.export_client_infer_retained_input(input, binding)
}

///|
/// A Store adapter can bind its completed write to this exact live export.
/// After restart it must instead authenticate and readmit saved originals.
pub fn prepared_input_export_matches(
  active : Execution,
  prepared : @model.ModelPreparedCallSet,
  exported : @input.ClientInferRetainedInputExport,
) -> Bool {
  guard !active.reclaimed &&
    !active.advancing &&
    active.model is Some(model) &&
    @model.prepared_model_matches(prepared, model) &&
    @model.prepared_model_input(prepared) is Some(input) else {
    return false
  }
  @input.client_infer_retained_input_export_matches(exported, input)
}

///|
pub fn prepared_input_scope_snapshot(
  active : Execution,
  prepared : @model.ModelPreparedCallSet,
) -> Result[String, @publication_host.ClientInferCallScopeIssue] {
  guard !active.reclaimed &&
    !active.cancelled &&
    !active.advancing &&
    active.model is Some(model) &&
    @model.prepared_model_matches(prepared, model) &&
    active.call_scope is Some(scope) else {
    return Err(ForeignInput)
  }
  @publication_host.client_infer_call_scope_snapshot(scope)
}

///|
pub fn prepared_input_unit_id(
  active : Execution,
  prepared : @model.ModelPreparedCallSet,
) -> String? {
  guard !active.reclaimed &&
    !active.cancelled &&
    !active.advancing &&
    active.model is Some(model) &&
    @model.prepared_model_matches(prepared, model) &&
    active.call_scope is Some(scope) else {
    return None
  }
  @publication_host.client_infer_call_scope_unit_id(scope)
}

///|
pub fn read_saved_input_scope(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  plan : @publication_host.ClientInferPlanGraph,
  snapshot_wire : String,
  authority_scope_cid : String,
  custody_available : () -> Bool,
) -> Result[
  @publication_host.ClientInferSavedCallScope,
  @publication_host.ClientInferCallScopeIssue,
] {
  guard @publication_host.prepared_client_infer_execution_occurrence(
      prepared, step,
    )
    is Some(occurrence) else {
    return Err(ForeignOwner)
  }
  @publication_host.read_client_infer_saved_call_scope(
    compiled, definition, occurrence, plan, snapshot_wire, authority_scope_cid, custody_available,
  )
}

///|
/// Reopen the same checked occurrence using its authenticated fixed input.
/// Sequence preparation is metadata-only; neither a Source nor the Local
/// prefix is run again. Fresh physical calls remain behind durable entry.
pub fn start_restored_input(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry : String,
  values : String,
  provider : @model.ModelProvider,
  plan : @publication_host.ClientInferPlanGraph,
  expected_binding : String,
  saved_binding : String,
  descriptor_wire : String,
  rows : Array[String],
  custody_available : () -> Bool,
  limits : Limits,
  acquired_input? : @publication_host.ClientInferCapturedInput? = None,
  saved_scope? : @publication_host.ClientInferSavedCallScope? = None,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[Execution, Issue] {
  guard @publication_host.prepared_client_infer_execution_occurrence(
      prepared, step,
    )
    is Some(occurrence) else {
    return Err(Input(@input.UnsupportedProgram))
  }
  if @publication_host.client_acquired_infer_prefix_owner(prepared, 0, step)
    is Some(_) &&
    acquired_input is None &&
    saved_scope is None {
    return Err(CallScope(ForeignInput))
  }
  if acquired_input is Some(captured) &&
    @publication_host.client_infer_captured_input_source(
      captured, prepared, step,
    )
    is None {
    return Err(CallScope(ForeignInput))
  }
  if saved_scope is Some(saved) &&
    (
      acquired_input is Some(_) ||
      !@publication_host.client_infer_saved_call_scope_matches_occurrence(
        saved, occurrence, plan,
      )
    ) {
    return Err(CallScope(ForeignInput))
  }
  start_occurrence(
    occurrence,
    Some(prepared),
    Physical(provider),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
    bounds => {
      @input.start_client_restored_infer_input(
        prepared,
        0,
        step,
        registry,
        values,
        expected_binding,
        saved_binding,
        descriptor_wire,
        rows,
        custody_available,
        bounds.input,
        bounds.mapping,
        fragment_body~,
        ordered_body~,
      )
    },
    acquired_input~,
  ).map(active => {
    active.durable_calls = true
    active.saved_call_scope = saved_scope
    active
  })
}

///|
/// The existing common Local task driver remains the component's only
/// scheduler. Restored producer content is admitted under the same occurrence.
pub fn start_restored_composed_input(
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
  prefix : @relation.GeneratedSequence,
  provider : @model.ModelProvider,
  expected_binding : String,
  saved_binding : String,
  descriptor_wire : String,
  rows : Array[String],
  custody_available : () -> Bool,
  limits : Limits,
  sources? : @publication_host.ClientInferComposedSources? = None,
  saved_scope? : @publication_host.ClientInferSavedCallScope? = None,
) -> Result[Execution, Issue] {
  if sources is Some(value) &&
    !@publication_host.client_infer_composed_sources_matches(value, occurrence) {
    return Err(CallScope(ForeignInput))
  }
  if @publication_host.client_infer_occurrence_has_captured_sources(occurrence) &&
    sources is None &&
    saved_scope is None {
    return Err(CallScope(ForeignInput))
  }
  if saved_scope is Some(saved) &&
    (
      sources is Some(_) ||
      !@publication_host.client_infer_saved_call_scope_matches_occurrence(
        saved, occurrence, plan,
      )
    ) {
    return Err(CallScope(ForeignInput))
  }
  start_occurrence(
    occurrence,
    None,
    Physical(provider),
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    Some(plan),
    bounds => {
      @input.start_client_restored_composed_infer_input(
        occurrence,
        prefix,
        expected_binding,
        saved_binding,
        descriptor_wire,
        rows,
        custody_available,
        bounds.input,
        bounds.mapping,
      )
    },
    composed_sources=sources,
  ).map(active => {
    active.durable_calls = true
    active.saved_call_scope = saved_scope
    active
  })
}
