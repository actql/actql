///|
priv struct SourceLimits {
  topology : @results.LocalProgramLimits
  context : @context.LocalContextLimits
  requests : @sourceviews.RequestLimits
  checks : @context.PreparationBudget
  identity : @context.SourcePreparationLimits
  max_parameters : Int
  max_bindings : Int
  max_slots : Int
  max_policy_depth : Int
  max_requirements : Int
  max_regex_depth : Int
}

///|
pub suberror SourceFailure {
  DeclarationWorkLimit
  CapacityMetadataBudget
  UnsupportedBindings(@decode.Cursor)
  UnsupportedEffects(@decode.Cursor)
  Requests(@context.PrepareSourcesIssue)
  RequestForm(@sourceviews.RequestFormIssue)
  Checks(@context.PrepareChecksIssue)
  Identity(@context.SourcePreparationIssue)
  Declarations(@stages.Issue)
  Registration(@context.SourceRegistrationIssue)
  SourceView(@context.SourceViewContextIssue)
}

///|
// Source identity emission can represent these declarations without checking
// their semantics. Do not mistake serialization support for static admission.
// Scan indexed source fields before allocation; diagnostics retain the cursor.
priv struct DeclarationAuditWork {
  mut declaration_remaining : Int
}

///|
fn audit_declarations(
  program : @syntax.Program,
  max_work : Int,
  effect_headers? : @syntax.EffectHeaders? = None,
) -> Int raise SourceFailure {
  let state = DeclarationAuditWork::{ declaration_remaining: max_work, }
  audit_declarations_owned(program, state, effect_headers~)
  max_work - state.declaration_remaining
}

///|
// SAME audit and declaration_remaining-work cell on success and failure. The observer does
// not walk a second copy or substitute the allowed maximum for performed work.
fn audit_declarations_owned(
  program : @syntax.Program,
  state : DeclarationAuditWork,
  effect_headers? : @syntax.EffectHeaders? = None,
) -> Unit raise SourceFailure {
  if effect_headers is Some(headers) &&
    !physical_equal(@syntax.effect_headers_owner(headers), program) {
    raise UnsupportedEffects(@syntax.program_body(program))
  }
  let charge = () => {
    if state.declaration_remaining <= 0 {
      raise DeclarationWorkLimit
    }
    state.declaration_remaining -= 1
  }
  charge()
  let root = @syntax.program_body(program)
  for i in 0..<@decode.object_length(root).unwrap() {
    charge()
    let (name, value) = @decode.field_at(root, i).unwrap()
    if name == "bindings" {
      raise UnsupportedBindings(value)
    }
    if name == "stages" {
      for stage in 0..<@decode.array_length(value).unwrap() {
        charge()
        let body = @decode.element_at(value, stage).unwrap()
        for field in 0..<@decode.object_length(body).unwrap() {
          charge()
          let (key, declaration) = @decode.field_at(body, field).unwrap()
          if key == "effects" &&
            @decode.object_length(declaration) != Some(0) &&
            effect_headers is None {
            raise UnsupportedEffects(declaration)
          }
        }
      }
    }
  }
  ()
}

///|
// The admitted Catalog owns its Environment. There is deliberately no second
// Environment argument that could replace policy or Local snapshot ownership.
// Catalog admission and complete obligation coverage remain outer phases.
fn prepare_catalog_source(
  program : @syntax.Program,
  supplied : @decode.Cursor?,
  catalog : @environment.SourceRequestContracts,
  material : Array[Array[@context.CapacityMaterial]],
  locations : Array[Array[(Int, Int)]]?,
  expression_profiles : @context.ExpressionProfiles,
  operation_profiles : @context.PureOperationProfiles,
  limits : SourceLimits,
  calendar? : @environment.SelectedCalendarProfile? = None,
  capacity_inputs? : @context.ProgramCapacityInputs? = None,
  model_tasks? : @environment.ModelTasks? = None,
  derived_capacity_limits? : @wire.Limits? = None,
  graph? : Bool = false,
  source_preparation? : @stages.Source? = None,
  collected_inputs_out? : Ref[@source_inputs.Inputs?]? = None,
) -> @context.ProgramSourceIdentity raise SourceFailure {
  let source = prepare_catalog_stage_source(program, limits, source_preparation)
  let (views, locals) = match
    @context.prepare_source_registrations(
      source,
      catalog,
      catalog_registration_limits(limits),
      max_inputs=limits.max_slots,
      max_views=limits.max_slots,
      max_order_keys=limits.max_slots,
      collected_inputs_out~,
    ) {
    Ok(v) => v
    Err(e) => raise Registration(e)
  }
  prepare_registered_catalog_source(
    views,
    locals,
    supplied,
    material,
    locations,
    expression_profiles,
    operation_profiles,
    limits,
    calendar~,
    capacity_inputs~,
    model_tasks~,
    derived_capacity_limits~,
    graph~,
  )
}

///|
// Internal original registration continuation. Its only alternate caller is
// the consumed ParsedCheckRegistry; no public tuple/Program substitution enters.
fn prepare_registered_catalog_source(
  views : @sourceviews.PipelineInputs,
  locals : @local_inputs.ProgramEnvironmentInputs,
  supplied : @decode.Cursor?,
  material : Array[Array[@context.CapacityMaterial]],
  locations : Array[Array[(Int, Int)]]?,
  expression_profiles : @context.ExpressionProfiles,
  operation_profiles : @context.PureOperationProfiles,
  limits : SourceLimits,
  calendar? : @environment.SelectedCalendarProfile? = None,
  capacity_inputs? : @context.ProgramCapacityInputs? = None,
  model_tasks? : @environment.ModelTasks? = None,
  derived_capacity_limits? : @wire.Limits? = None,
  graph? : Bool = false,
  source_context? : @context.SourceViewContextInput? = None,
) -> @context.ProgramSourceIdentity raise SourceFailure {
  let prepared = match source_context {
    None =>
      @context.prepare_sourceview_context(
        views,
        locals,
        supplied,
        material,
        limits.topology,
        limits.context,
        calendar~,
        capacity_inputs~,
        model_tasks~,
        derived_capacity_limits~,
      )
    Some(original) =>
      @context.prepare_sourceview_context_from_input(
        original,
        supplied,
        material,
        capacity_inputs~,
        derived_capacity_limits~,
      )
  }
  let selected = match prepared {
    Ok(value) => value
    Err(issue) => raise SourceView(issue)
  }
  prepare_selected_source(
    selected,
    locations,
    expression_profiles,
    operation_profiles,
    limits,
    graph~,
  )
}

///|
fn prepare_selected_source(
  selected : @context.SelectedPolicyContext,
  locations : Array[Array[(Int, Int)]]?,
  expression_profiles : @context.ExpressionProfiles,
  operation_profiles : @context.PureOperationProfiles,
  limits : SourceLimits,
  graph? : Bool = false,
) -> @context.ProgramSourceIdentity raise SourceFailure {
  let (generated_bytes, generated_nodes) = @context.selected_capacity_metadata_usage(
    selected,
  )
  let identity_limits = limits.identity.identity
  if generated_bytes > identity_limits.max_hash_bytes ||
    generated_nodes > identity_limits.max_hash_nodes {
    raise CapacityMetadataBudget
  }
  let limits = {
    ..limits,
    identity: {
      ..limits.identity,
      identity: {
        ..identity_limits,
        max_hash_bytes: identity_limits.max_hash_bytes - generated_bytes,
        max_hash_nodes: identity_limits.max_hash_nodes - generated_nodes,
      },
    },
  }
  let prepared = match locations {
    Some(locations) =>
      @context.prepare_program_source_acquisitions(
        selected,
        locations,
        limits.requests,
        max_bindings=limits.max_bindings,
        max_slots=limits.max_slots,
      )
    None =>
      @context.prepare_program_source_acquisitions_auto(
        selected,
        limits.requests,
        max_bindings=limits.max_bindings,
        max_slots=limits.max_slots,
      )
  }
  let producer = match prepared {
    Ok(v) => v
    Err(e) => raise Requests(e)
  }
  let operations = match
    @context.prepare_program_checks(
      producer,
      expression_profiles,
      operation_profiles,
      limits.checks,
      max_policy_depth=limits.max_policy_depth,
      max_requirements=limits.max_requirements,
      max_regex_depth=limits.max_regex_depth,
      graph~,
    ) {
    Ok(v) => v
    Err(e) => raise Checks(e)
  }
  match @context.prepare_program_source_identity(operations, limits.identity) {
    Ok(v) => v
    Err(e) => raise Identity(e)
  }
}

///|
fn prepare_catalog_stage_source(
  program : @syntax.Program,
  limits : SourceLimits,
  original : @stages.Source?,
) -> @stages.Source raise SourceFailure {
  match
    @stages.prepare(
      program,
      {
        max_parameters: limits.max_parameters,
        max_nodes: limits.topology.max_nodes,
        max_depth: limits.topology.max_depth,
        max_text_bytes: limits.topology.max_text_bytes,
      },
      original~,
    ) {
    Ok(v) => v
    Err(e) => raise Declarations(e)
  }
}

///|
fn catalog_registration_limits(limits : SourceLimits) -> @local_inputs.Limits {
  {
    max_work: Int::min(limits.topology.max_work, limits.context.stages.max_work),
    max_nodes: limits.topology.max_nodes,
    max_depth: limits.topology.max_depth,
    max_text_bytes: limits.topology.max_text_bytes,
  }
}
