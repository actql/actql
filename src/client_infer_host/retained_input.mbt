///|
/// Recovered Content still enters through the original Local chain's exact
/// receiving port. Its post-generation completion must match the authenticated
/// original Model input before the same saved call scope can resume dispatch.
pub fn start_restored_generated_inputs(
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  generation : @publication_host.ClientSerializationGeneration,
  plan : @publication_host.ClientInferPlanGraph,
  inputs : Array[@local.ManagedProviderInput],
  provider : @model.ModelProvider,
  binding : String,
  descriptor_wire : String,
  custody_available : () -> Bool,
  limits : Limits,
) -> Result[Execution, Issue] {
  guard custody_available() &&
    @publication_host.client_serialization_generation_infer_occurrence(
      generation, run, plan,
    )
    is Some(occurrence) &&
    @publication_host.client_serialization_generation_saved_scope_for(
      generation, run, plan,
    )
    is Some(scope) &&
    @publication_host.client_serialization_generation_capture_for(
      generation, run, definition,
    )
    is Some(_) &&
    inputs is [@local.RelationInput(read)] else {
    return Err(CallScope(ForeignInput))
  }
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  guard @relation.infer_completed_producer_input(owner, step, read)
    is Some(output) else {
    return Err(CallScope(ForeignInput))
  }
  let exported = match
    @input.export_client_infer_retained_input(output, binding) {
    Ok(value) => value
    Err(issue) => return Err(Input(@input.RetainedInput(issue)))
  }
  if !custody_available() ||
    @input.client_infer_retained_input_export_descriptor(exported) !=
    descriptor_wire {
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
      @input.start_client_completed_infer_input(
        occurrence,
        output,
        bounds.mapping,
      )
    },
  ).map(active => {
    active.durable_calls = true
    active.saved_call_scope = Some(scope)
    active.serialized_generation = Some(generation)
    active
  })
}

///|
/// Reopen the original generated-Content occurrence without a Source/encoder
/// prefix. Generation and saved Source scope are one checked borrowed token;
/// physical Model entry remains behind the existing durable approval owner.
pub fn start_restored_generated_input(
  prepared : @publication_host.PreparedClientProgram,
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  generation : @publication_host.ClientSerializationGeneration,
  plan : @publication_host.ClientInferPlanGraph,
  sequence_contracts : @input.ClientInstalledSequenceContracts,
  values : String,
  provider : @model.ModelProvider,
  expected_binding : String,
  saved_binding : String,
  descriptor_wire : String,
  rows : Array[String],
  custody_available : () -> Bool,
  limits : Limits,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[Execution, Issue] {
  guard @publication_host.client_serialization_generation_infer_occurrence(
      generation, run, plan,
    )
    is Some(occurrence) &&
    @publication_host.client_infer_occurrence_matches(occurrence, prepared) &&
    @publication_host.client_serialization_generation_saved_scope_for(
      generation, run, plan,
    )
    is Some(scope) &&
    @publication_host.client_serialization_generation_capture_for(
      generation, run, definition,
    )
    is Some(evidence) else {
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
      @input.start_client_restored_serialized_infer_input(
        prepared,
        run,
        definition,
        plan,
        occurrence,
        evidence,
        sequence_contracts,
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
  ).map(active => {
    active.durable_calls = true
    active.saved_call_scope = Some(scope)
    active.serialized_generation = Some(generation)
    active
  })
}

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
  sequence_contracts : @input.ClientInstalledSequenceContracts,
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
  reference_issuer? : @admitted.ReferenceIssuer,
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
        sequence_contracts,
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
        reference_issuer?,
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
  reference_issuer? : @admitted.ReferenceIssuer,
  root? : (@relation.GeneratedSequence?, @resources.Ledger)? = None,
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
        reference_issuer?,
      )
    },
    composed_sources=sources,
    root=root.map(value => (prefix, value.0, value.1)),
  ).map(active => {
    active.durable_calls = true
    active.saved_call_scope = saved_scope
    active
  })
}
