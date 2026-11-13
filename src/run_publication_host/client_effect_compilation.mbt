///|
pub(all) enum ClientEffectCompilationIssue {
  UnsupportedProgram
  ForeignInferOwner
  Serialization(ClientSerializationEffectPlanIssue)
  EffectPlan(@stage_results.EffectPlanBindingIssue)
  Graph(ClientTaskPlanGraphIssue)
  Template(ClientTaskBoundTemplateIssue)
  Material(ClientExecutionMaterialIssue)
  Plan(ClientValuesExecutablePlanIssue)
  Compilation(ClientTaskCompilationIssue)
  Encoding
  Normalization(ClientEffectNormalizationIssue)
}

///|
pub(all) enum ClientEffectCompilationAdmissionIssue {
  Issue(ClientEffectCompilationIssue)
  MismatchedCompilation
}

///|
/// Retain the original checked Effect owner alongside the common compiler
/// output. Neither this value nor its Template authorizes physical apply.
pub struct ClientEffectCompilation {
  owner : PreparedClientEffectComputation
  compiled : ClientTaskCompilation
  normalization_profile : ClientEffectNormalizationInventory?
}

///|
pub fn client_effect_compilation_plan(
  value : ClientEffectCompilation,
) -> ClientTaskExecutablePlan {
  value.compiled.plan
}

///|
pub fn client_effect_compilation_template(
  value : ClientEffectCompilation,
) -> @publication.RunEvidenceValue {
  value.compiled.template
}

///|
pub fn client_effect_compilation_compiled_plan(
  value : ClientEffectCompilation,
) -> @publication.PublicationContract {
  value.compiled.compiled_plan
}

///|
pub fn client_effect_compilation_owner(
  value : ClientEffectCompilation,
) -> PreparedClientEffectComputation {
  value.owner
}

///|
/// Borrow the original component and its nominal checked occurrence together.
/// A newly created Effect compiler view cannot substitute that wrapper. This
/// projection grants no current Provider or dispatch authority.
pub fn client_effect_compilation_infer_original(
  value : ClientEffectCompilation,
) -> (ClientInferPlanGraph, ClientInferOccurrence)? {
  guard value.compiled.infer is Some(component) &&
    physical_equal(component.owner, value.compiled.owner) &&
    prepared_client_composed_infer_occurrence(component.owner)
    is Some(occurrence) &&
    client_infer_occurrence_matches_effect(occurrence, value.owner) &&
    client_infer_occurrence_matches_plan(occurrence, component) else {
    return None
  }
  Some((component, occurrence))
}

///|
/// Only the original checked Effect owner can obtain a compiled Result
/// selection. The retained compiler view is not reconstructed or rechecked.
pub fn client_effect_compilation_result_transformation(
  value : ClientEffectCompilation,
  owner : PreparedClientEffectComputation,
  result : Int,
) -> Result[ClientResultTransformation?, ClientEffectCompilationAdmissionIssue] {
  if !physical_equal(value.owner, owner) ||
    @strategy.graph_result_occurrence(value.compiled.owner.graph, result)
    is None {
    return Err(MismatchedCompilation)
  }
  for selection in value.compiled.plan.plan.transformations {
    if client_result_transformation_matches(
        selection,
        value.compiled.owner,
        result,
      ) {
      return Ok(Some(selection))
    }
  }
  Ok(None)
}

///|
/// Compile a Values Effect Unit or independent acquired roots feeding Local
/// computation and a final Effect Unit. Existing task lowering and the checked
/// graph own supported operations and input edges. Command members retain their
/// Catalog binding instead of being approximated as an AoA Mapping terminal.
pub fn issue_prepared_client_effect_compilation(
  owner : PreparedClientEffectComputation,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  infer? : ClientInferPlanGraph? = None,
  infers? : Array[ClientInferPlanGraph] = [],
  normalization? : ClientEffectNormalization? = None,
  source_free_policy? : @publication.CapturedEffectDependencyBody? = None,
) -> Result[ClientEffectCompilation, ClientEffectCompilationIssue] {
  match normalization {
    Some(original) =>
      match prepared_client_effect_normalization_evidence(owner, original) {
        Ok(_) => ()
        Err(issue) => return Err(Normalization(issue))
      }
    None => ()
  }
  issue_client_effect_compilation_internal(
    owner,
    manifests,
    sequence_limits,
    max_facts,
    max_witnesses,
    max_wire_bytes,
    max_nodes,
    max_depth,
    normalization.map(fn(original) { original.inventory }),
    infer~,
    infers~,
    source_free_policy~,
  )
}

///|
/// Restoration selects a candidate profile only provisionally. The saved
/// invocation/authorization and expected original Run CID must then bind it.
/// This verifies an inventory but never issues a new normalization journal.
fn issue_client_effect_compilation_internal(
  owner : PreparedClientEffectComputation,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  normalization_profile : ClientEffectNormalizationInventory?,
  infer? : ClientInferPlanGraph? = None,
  infers? : Array[ClientInferPlanGraph] = [],
  source_free_policy? : @publication.CapturedEffectDependencyBody? = None,
) -> Result[ClientEffectCompilation, ClientEffectCompilationIssue] {
  if (infer is Some(_) && !infers.is_empty()) ||
    (source_free_policy is Some(_) && (infer is Some(_) || !infers.is_empty())) {
    return Err(Serialization(UnsupportedGraph))
  }
  if normalization_profile is Some(inventory) &&
    !client_effect_normalization_inventory_matches(inventory, owner) {
    return Err(Normalization(ForeignPreparation))
  }
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  let headers = @checked.effect_program_static_headers(owner.candidate)
  let count = @syntax.effect_header_count(headers)
  let units = @checked.unit_count(@strategy.graph_program(graph))
  if units < 1 ||
    count == 0 ||
    count > max_nodes ||
    @strategy.checked_effect_source_count(owner.graph) != count {
    return Err(UnsupportedProgram)
  }
  let checked = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @strategy.graph_task_owner(graph, 0) is Some(first) &&
    @checked.unit_pipeline(checked, 0) is Some(pipeline) &&
    @checked.unit_result_import_count(checked, 0) == Some(0) &&
    @checked.unit_import_cid_count(checked, 0) == Some(0) else {
    return Err(UnsupportedProgram)
  }
  let source_free = @strategy.graph_source_free_inputs_complete(graph) &&
    @pipeline.input_count(pipeline) == 0 &&
    @pipeline.starts_with_values(
      @lower.pipeline(@lower.bound_preparation(first)),
    )
  let prefix = @strategy.graph_captured_prefix(graph)
  // Acquired roots may feed further checked Local Units. Their actual graph
  // edges, not the number of consumers, bind every input occurrence.
  let mut acquired = prefix >= 1 && prefix <= units
  if acquired {
    // Acquisition coordinates come from the checked Direct originals. A
    // complete Input can precede authored joins without becoming a Query Step.
    acquired = select_client_effect_direct_acquisition_occurrences(
        owner, 1000000,
      )
      .map(value => {
        let count = client_direct_acquisition_occurrence_count(value)
        if count == 0 {
          return false
        }
        for index in 0..<count {
          let (stage, input, _) = client_direct_acquisition_occurrence_at(
            value, index,
          ).unwrap()
          guard @context.program_identity_stage_requests(
              @checked.source_identity(@strategy.graph_program(graph)),
              stage,
            )
            is Some(requests) else {
            return false
          }
          match
            @acquisition.select_source_acquisition_route(
              requests, input, 1000000,
            ) {
            Ok(@acquisition.WholeInputRoute(_)) => ()
            Ok(@acquisition.QueryRoute(_)) =>
              if prepare_client_query_acquisition_shape(
                  client_effect_program_view(owner),
                  stage,
                  input,
                )
                is Err(_) {
                return false
              }
            Err(_) => return false
          }
        }
        true
      })
      .unwrap_or(false)
  }

  if !source_free && !acquired {
    return Err(UnsupportedProgram)
  }
  // This private compiler view contains the same graph, source and Effects.
  // It is never returned as an Effect-free preparation or checked again.
  let value = match infer {
    None if !infers.is_empty() => {
      let first = infers[0]
      guard prepared_client_composed_infer_occurrences(first.owner)
        is Some(expected) &&
        expected.length() == infers.length() &&
        infers.length() > 1 else {
        return Err(ForeignInferOwner)
      }
      for index, component in infers {
        if !physical_equal(component.owner, first.owner) ||
          !physical_equal(component.owner.graph, graph) ||
          !physical_equal(component.owner.source, owner.source) ||
          component.owner.check_environment_cid != owner.check_environment_cid ||
          !client_infer_occurrence_matches_plan(expected[index], component) {
          return Err(ForeignInferOwner)
        }
      }
      first.owner
    }
    None => client_effect_program_view(owner)
    Some(infer) => {
      guard prepared_client_composed_infer_occurrences(infer.owner)
        is Some(expected) &&
        expected.length() == 1 &&
        client_infer_occurrence_matches_plan(expected[0], infer) else {
        return Err(ForeignInferOwner)
      }
      if !physical_equal(infer.owner.graph, graph) ||
        !physical_equal(infer.owner.source, owner.source) ||
        infer.owner.check_environment_cid != owner.check_environment_cid {
        return Err(ForeignInferOwner)
      }
      infer.owner
    }
  }
  let serialization = if infer is Some(_) || !infers.is_empty() {
    None
  } else {
    match
      issue_client_serialization_effect_component(
        value,
        sequence_limits,
        max_wire_bytes,
        max_nodes,
        max_depth,
        source_free_policy~,
      ) {
      Ok(component) => component
      Err(issue) => return Err(Serialization(issue))
    }
  }
  let required_profiles = match infer {
    None => {
      let profiles = []
      for component in infers {
        for profile in client_infer_required_profiles(component) {
          if !profiles.contains(profile) {
            profiles.push(profile)
          }
        }
      }
      profiles
    }
    Some(component) => client_infer_required_profiles(component)
  }
  if serialization is Some(_) {
    required_profiles.push(
      (
        "actql-content/0.1",
        @environment.compiler_content_barrier_contract_cid(),
      ),
    )
  }
  if normalization_profile is Some(inventory) {
    required_profiles.push(
      client_effect_normalization_inventory_profile(inventory),
    )
  }
  let roots : Array[(String, Int)] = []
  let plan_cids : Array[(String, String)] = []
  let names : Array[String] = []
  let rules = @stage_results.effect_static_candidate_mapping_rules(
    @checked.effect_program_static_effects(owner.candidate),
  )
  for index in 0..<count {
    guard @syntax.effect_header_at(headers, index) is Some(header) &&
      @syntax.effect_header_stage(header) == units - 1 else {
      return Err(UnsupportedProgram)
    }
    let name = @syntax.effect_header_id(header)
    if names.contains(name) {
      return Err(UnsupportedProgram)
    }
    names.push(name)
    let mut source_task = -1
    for source_index in 0..<@strategy.checked_effect_source_count(owner.graph) {
      guard @strategy.checked_effect_source_at(owner.graph, source_index)
        is Some(source) else {
        continue
      }
      if @strategy.checked_effect_source_member(source) == index &&
        @strategy.checked_effect_source_stage(source) == units - 1 {
        if source_task >= 0 {
          return Err(UnsupportedProgram)
        }
        source_task = @strategy.checked_effect_source_task(source)
      }
    }
    // The same checked inventory owns both namespaces. A private Table input
    // supplies an Effect root, never an ordinary Result or a send permission.
    match @strategy.checked_effect_table_input_at(owner.graph, index) {
      Some(source) => {
        guard @syntax.effect_header_kind(header) == "store" &&
          @syntax.effect_header_source_result(header) is None &&
          @syntax.effect_header_source_table_input(header) is Some(_) &&
          @strategy.checked_effect_table_input_member(source) == index &&
          @strategy.checked_effect_table_input_stage(source) == units - 1 &&
          source_task < 0 else {
          return Err(UnsupportedProgram)
        }
        source_task = @strategy.checked_effect_table_input_task(source)
      }
      None =>
        if @syntax.effect_header_source_result(header) is None ||
          @syntax.effect_header_source_table_input(header) is Some(_) {
          return Err(UnsupportedProgram)
        }
    }
    if source_task < 0 {
      return Err(UnsupportedProgram)
    }
    roots.push((name, source_task))
    let command = match
      @stage_results.effect_command_input_for_member(
        @stage_results.effect_static_candidate_command_inputs(
          @checked.effect_program_static_effects(owner.candidate),
        ),
        index,
        max_nodes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(EffectPlan(issue))
    }
    let terminal = if command is Some(_) {
      None
    } else {
      match
        @stage_results.effect_plan_terminal_for_member(
          rules, index, max_nodes, max_nodes,
        ) {
        Ok(terminal) => terminal
        Err(issue) => return Err(EffectPlan(issue))
      }
    }
    // Create and Command have no AoA EffectPlan terminal in 0.1. Their
    // admitted Mapping or Command bindings remain in the complete checked
    // Program and Environment; this does not authorize physical apply.
    if terminal is Some(terminal) {
      let cid = @stage_results.effect_plan_pipeline_cid(
        terminal, max_wire_bytes, max_nodes, max_depth,
      ) catch {
        _ => return Err(Encoding)
      }
      plan_cids.push((name, cid))
    }
  }
  let task_graph = match
    issue_client_task_plan_graph(
      value,
      sequence_limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      true,
      roots,
      infer~,
      infers~,
      serialization~,
    ) {
    Ok(graph) => graph
    Err(issue) => return Err(Graph(issue))
  }
  let template = match
    issue_client_task_bound_template(
      value,
      manifests,
      max_wire_bytes,
      max_nodes,
      max_depth,
      required_profiles~,
    ) {
    Ok(template) => template
    Err(issue) => return Err(Template(issue))
  }
  let material = match
    issue_prepared_client_execution_material_with_template(
      value,
      manifests,
      template,
      max_wire_bytes,
      max_nodes,
      max_depth,
      result_plans=task_graph.result_plans,
      effect_plan_cids=plan_cids,
      effect_target_selections=owner.target_selections,
    ) {
    Ok(material) => material
    Err(issue) => return Err(Material(issue))
  }
  let plan = match
    issue_prepared_client_executable_plan_with_parts(
      value,
      task_graph.wire,
      task_graph.transformations,
      material,
      max_facts,
      max_witnesses,
      max_wire_bytes,
      max_nodes,
      max_depth,
      required_profiles~,
      result_plans=task_graph.result_plans,
    ) {
    Ok(plan) => plan
    Err(issue) => return Err(Plan(issue))
  }
  let compiled = match
    finish_client_task_compilation(
      value,
      { plan, },
      template,
      task_graph,
      max_wire_bytes,
      max_nodes,
      max_depth,
      infer~,
      infers~,
      serialization=match infer {
        Some(component) => component.serialization
        None => serialization.map(component => component.serialization)
      },
    ) {
    Ok(compiled) => compiled
    Err(issue) => return Err(Compilation(issue))
  }
  if @publication.publication_contract_effect_target_selections_cid(
      compiled.compiled_plan,
    ) !=
    client_effect_target_selections_cid(owner) {
    return Err(Encoding)
  }
  Ok({ owner, compiled, normalization_profile, })
}

///|
/// Regenerate all compiler artifacts against the exact checked owner before
/// admitting saved evidence. Equal local Unit identity is insufficient.
pub fn admit_prepared_client_effect_compilation(
  owner : PreparedClientEffectComputation,
  plan_wire : String,
  fact_manifest_wire : String,
  template_wire : String,
  compiled_plan_wire : String,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  infer? : ClientInferPlanGraph? = None,
  source_free_policy? : @publication.CapturedEffectDependencyBody? = None,
) -> Result[ClientEffectCompilation, ClientEffectCompilationAdmissionIssue] {
  let issued = match
    issue_prepared_client_effect_compilation(
      owner,
      manifests,
      sequence_limits,
      max_facts,
      max_witnesses,
      max_wire_bytes,
      max_nodes,
      max_depth,
      infer~,
      source_free_policy~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Issue(issue))
  }
  let plan = issued.compiled.plan.plan
  if plan.wire != plan_wire ||
    plan.fact_manifest_wire != fact_manifest_wire ||
    @publication.run_evidence_value_json(issued.compiled.template) !=
    template_wire ||
    @publication.publication_contract_json(issued.compiled.compiled_plan) !=
    compiled_plan_wire {
    return Err(MismatchedCompilation)
  }
  Ok(issued)
}

///|
pub(all) enum ClientEffectCompiledRunIssue {
  ForeignCompilation
  Policy(ClientAllowedRunEvidenceIssue)
  Admission(@publication.RunPublicationAdmissionIssue)
  Binding(ClientEffectRunIssue)
}

///|
pub struct ClientEffectAllowedRun {
  compilation : ClientEffectCompilation
  prepared : @publication.RunEvidenceValue
  authorization : @publication.RunEvidenceValue
  admission : @publication.RunPublicationAdmission
}

///|
/// The compilation retains its exact checked owner. Current Host policy is
/// external; this operation issues linked evidence after that authorization.
pub fn issue_client_effect_allowed_run(
  compilation : ClientEffectCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientEffectAllowedRun, ClientEffectCompiledRunIssue] {
  let template = client_effect_compilation_template(compilation)
  let plan = client_effect_compilation_compiled_plan(compilation)
  let (prepared, authorization) = match
    issue_client_allowed_run_evidence(
      template, plan, execution_context_cid, host_policy_cid, expires_at,
    ) {
    Ok(values) => values
    Err(issue) => return Err(Policy(issue))
  }
  let admission = match
    admit_prepared_client_effect_run_publication(
      compilation.owner,
      template,
      prepared,
      authorization,
      plan,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  Ok({ compilation, prepared, authorization, admission, })
}

///|
pub fn client_effect_allowed_run_prepared(
  value : ClientEffectAllowedRun,
) -> @publication.RunEvidenceValue {
  value.prepared
}

///|
pub fn client_effect_allowed_run_authorization(
  value : ClientEffectAllowedRun,
) -> @publication.RunEvidenceValue {
  value.authorization
}

///|
pub fn client_effect_allowed_run_admission(
  value : ClientEffectAllowedRun,
) -> @publication.RunPublicationAdmission {
  value.admission
}

///|
/// The Model component consumes the original Effect Run's admission. The
/// original checked Effect owner stays retained in this compilation variant;
/// no separate Effect-free Run, authorization or public Program is issued.
pub fn client_effect_allowed_infer_run(
  value : ClientEffectAllowedRun,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  client_effect_allowed_infer_run_with_policy_body(
    value,
    None,
    None,
    1024,
    100,
    8,
  )
}

///|
/// Bind the Host-selected Result Policy original before Model dispatch.
/// This does not replace the separate Model egress admission.
pub fn client_effect_allowed_infer_run_with_policy_body(
  value : ClientEffectAllowedRun,
  policy_cid : String?,
  policy_wire : String?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  let compilation = value.compilation
  guard client_effect_compilation_infer_originals(compilation) is Some(_) else {
    return Err(ForeignOwner)
  }
  let graph = @strategy.checked_effect_computation_graph(
    compilation.owner.graph,
  )
  let source_free_result_policy = if @strategy.graph_source_free_inputs_complete(
      graph,
    ) {
    // No checked Source closure can authorize a lower classification. The
    // selected Host original is required, not synthesized from Model egress.
    guard policy_cid is Some(cid) && policy_wire is Some(wire) else {
      return Err(MissingResultPolicy)
    }
    match
      admit_source_free_result_policy_body(
        cid, wire, max_bytes, max_nodes, max_depth,
      ) {
      Ok(policy) => Some(policy)
      Err(issue) => return Err(issue)
    }
  } else {
    if policy_cid is Some(_) || policy_wire is Some(_) {
      return Err(InvalidResultPolicy)
    }
    None
  }
  Ok(client_effect_allowed_component_run(value, source_free_result_policy))
}

///|
/// Borrow the checked Content component from this exact allowed Effect Run.
/// This is neither approval of the Command nor an Effect-free admission. The
/// compiler retains either the actual acquired Source closure or the explicit
/// source-free Host policy selected before compilation. The same Plan/Run
/// carries it; this projection neither samples policy nor authorizes the write.
pub fn client_effect_allowed_serialization_run(
  value : ClientEffectAllowedRun,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  let compilation = value.compilation
  guard compilation.compiled.serialization is Some(component) &&
    physical_equal(component.owner, compilation.compiled.owner) else {
    return Err(ForeignOwner)
  }
  let source_free_policy = if @strategy.graph_source_free_inputs_complete(
      component.owner.graph,
    ) {
    Some(component.policy)
  } else {
    None
  }
  Ok(client_effect_allowed_component_run(value, source_free_policy))
}

///|
/// Retain the original prepared evidence, authorization and admission. The
/// component-specific callers check their selected physical owner first.
fn client_effect_allowed_component_run(
  value : ClientEffectAllowedRun,
  source_free_result_policy : @publication.CapturedEffectDependencyBody?,
) -> ClientCompiledRun {
  let compilation = value.compilation
  {
    owner: compilation.compiled.owner,
    compilation: Effects(value),
    template: compilation.compiled.template,
    plan: compilation.compiled.compiled_plan,
    prepared: value.prepared,
    authorization: value.authorization,
    admission: value.admission,
    source_free_result_policy,
    definition_binding: None,
  }
}

///|
/// Admission of the Host's explicit source-free Result Policy original can
/// precede Run creation. This is an unknown-provenance policy, never a grant
/// to Model egress or a replacement for checked Source-derived constraints.
pub fn admit_source_free_result_policy_body(
  cid : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.CapturedEffectDependencyBody, ClientCompiledRunIssue] {
  if wire !=
    "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}" {
    return Err(InvalidResultPolicy)
  }
  match
    @publication.admit_captured_effect_dependency_body(
      "data_policy",
      Some(cid),
      wire,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(body) => Ok(body)
    Err(_) => Err(InvalidResultPolicy)
  }
}

///|
/// Use the saved policy and exact Run Definition at physical-start time.
/// Current Host authorization remains an independent requirement.
pub fn client_effect_run_start_current(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  at : String,
) -> Bool {
  @publication.run_publication_start_current(allowed.admission, definition, at)
}

///|
/// A saved definition binds the original policy evidence, not a newly issued
/// authorization. The Host retains those records in the same request custody.
pub fn admit_client_effect_allowed_run(
  compilation : ClientEffectCompilation,
  prepared : @publication.RunEvidenceValue,
  authorization : @publication.RunEvidenceValue,
) -> Result[ClientEffectAllowedRun, ClientEffectCompiledRunIssue] {
  let admission = match
    admit_prepared_client_effect_run_publication(
      compilation.owner,
      client_effect_compilation_template(compilation),
      prepared,
      authorization,
      client_effect_compilation_compiled_plan(compilation),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  Ok({ compilation, prepared, authorization, admission, })
}

///|
pub fn bind_client_effect_compiled_run(
  owner : PreparedClientEffectComputation,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
) -> Result[PreparedClientEffectRun, ClientEffectCompiledRunIssue] {
  if !physical_equal(owner, allowed.compilation.owner) ||
    !@publication.run_definition_has_empty_initial_input_artifact_set(
      definition,
    ) {
    return Err(ForeignCompilation)
  }
  bind_prepared_client_effect_run(owner, allowed.admission, definition).map_err(issue => {
      Binding(issue)
    },
  )
}

///|
pub fn issue_client_effect_run_definition(
  allowed : ClientEffectAllowedRun,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[@publication.PublicationContract, ClientEffectCompiledRunIssue] {
  let definition = match
    @publication.issue_run_definition(
      allowed.admission,
      scope_id,
      run_id,
      @publication.empty_initial_input_artifact_set_cid(),
      created_at,
      valid_until,
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  match
    bind_client_effect_compiled_run(
      allowed.compilation.owner,
      allowed,
      definition,
    ) {
    Ok(_) => Ok(definition)
    Err(issue) => Err(issue)
  }
}

///|
pub fn client_effect_compilation_result_names(
  value : ClientEffectCompilation,
) -> Array[String] {
  client_task_compilation_result_names(value.compiled)
}

///|
/// Read the retained original compilation inventory; do not reconstruct or
/// compile the Effect Program when projecting a committed Run's availability.
pub fn client_effect_allowed_run_result_names(
  value : ClientEffectAllowedRun,
) -> Array[String] {
  client_effect_compilation_result_names(value.compilation)
}

///|
/// Compilation admits one Effect-bearing Unit (possibly after acquisition).
/// Return its authored coordinate from the same checked owner, not a Host label.
pub fn client_effect_compilation_unit_id(
  value : ClientEffectCompilation,
) -> String {
  let stages = @syntax.stages(value.owner.source)
  stages[stages.length() - 1].id
}

///|
/// Copy only the outer inventory; each member remains the original checked
/// component/occurrence. A subset, reorder or equal graph cannot qualify.
pub fn client_effect_compilation_infer_originals(
  value : ClientEffectCompilation,
) -> Array[(ClientInferPlanGraph, ClientInferOccurrence)]? {
  guard prepared_client_composed_infer_occurrences(value.compiled.owner)
    is Some(expected) &&
    !expected.is_empty() &&
    expected.length() == value.compiled.infers.length() else {
    return None
  }
  let originals = []
  for index, component in value.compiled.infers {
    let occurrence = expected[index]
    if !physical_equal(component.owner, value.compiled.owner) ||
      !client_infer_occurrence_matches_effect(occurrence, value.owner) ||
      !client_infer_occurrence_matches_plan(occurrence, component) {
      return None
    }
    originals.push((component, component.occurrence))
  }
  Some(originals)
}

///|
/// The original Effect compilation supplies its retained graph Array in place;
/// the caller funds only the same two read-partition projection arrays.
pub fn bind_client_effect_model_read_scopes(
  compilation : ClientEffectCompilation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
  retained_bytes : Array[Int64],
  execution_bytes : Array[Int64],
) -> Result[Array[ClientModelReadScope], ClientModelReadPreparationIssue] {
  if !client_compiled_run_matches_effect(
      compiled,
      compilation.owner,
      compilation,
    ) {
    return Err(ForeignRun)
  }
  bind_client_model_read_scopes(
    compiled,
    definition,
    compilation.compiled.infers,
    ledger,
    identity,
    retained_bytes,
    execution_bytes,
  )
}

///|
// Reuse the original typed Model owner. The private Effect view never escapes
// as an effect-free checked Program, and equal CIDs cannot replace originals.
fn client_effect_compilation_original_view(
  owner : PreparedClientEffectComputation,
  infer : ClientInferPlanGraph?,
  infers : Array[ClientInferPlanGraph],
) -> Result[PreparedClientProgram, ClientEffectCompilationIssue] {
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  let value = match infer {
    None if !infers.is_empty() => {
      let first = infers[0]
      guard prepared_client_composed_infer_occurrences(first.owner)
        is Some(expected) &&
        expected.length() == infers.length() &&
        infers.length() > 1 else {
        return Err(ForeignInferOwner)
      }
      for index, component in infers {
        if !physical_equal(component.owner, first.owner) ||
          !physical_equal(component.owner.graph, graph) ||
          !physical_equal(component.owner.source, owner.source) ||
          component.owner.check_environment_cid != owner.check_environment_cid ||
          !client_infer_occurrence_matches_plan(expected[index], component) {
          return Err(ForeignInferOwner)
        }
      }
      first.owner
    }
    None => client_effect_program_view(owner)
    Some(infer) => {
      guard prepared_client_composed_infer_occurrences(infer.owner)
        is Some(expected) &&
        expected.length() == 1 &&
        client_infer_occurrence_matches_plan(expected[0], infer) else {
        return Err(ForeignInferOwner)
      }
      if !physical_equal(infer.owner.graph, graph) ||
        !physical_equal(infer.owner.source, owner.source) ||
        infer.owner.check_environment_cid != owner.check_environment_cid {
        return Err(ForeignInferOwner)
      }
      infer.owner
    }
  }
  Ok(value)
}

///|
fn client_effect_compilation_original_roots(
  owner : PreparedClientEffectComputation,
  max_nodes : Int,
) -> Result[
  (Array[(String, Int)], Array[(String, @stage_results.EffectPlanTerminal)]),
  ClientEffectCompilationIssue,
] {
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  let units = @checked.unit_count(@strategy.graph_program(graph))
  let headers = @checked.effect_program_static_headers(owner.candidate)
  let count = @syntax.effect_header_count(headers)
  let roots : Array[(String, Int)] = []
  let terminals : Array[(String, @stage_results.EffectPlanTerminal)] = []
  let names : Array[String] = []
  let rules = @stage_results.effect_static_candidate_mapping_rules(
    @checked.effect_program_static_effects(owner.candidate),
  )
  for index in 0..<count {
    guard @syntax.effect_header_at(headers, index) is Some(header) &&
      @syntax.effect_header_stage(header) == units - 1 else {
      return Err(UnsupportedProgram)
    }
    let name = @syntax.effect_header_id(header)
    if names.contains(name) {
      return Err(UnsupportedProgram)
    }
    names.push(name)
    let mut source_task = -1
    for source_index in 0..<@strategy.checked_effect_source_count(owner.graph) {
      guard @strategy.checked_effect_source_at(owner.graph, source_index)
        is Some(source) else {
        continue
      }
      if @strategy.checked_effect_source_member(source) == index &&
        @strategy.checked_effect_source_stage(source) == units - 1 {
        if source_task >= 0 {
          return Err(UnsupportedProgram)
        }
        source_task = @strategy.checked_effect_source_task(source)
      }
    }
    // The same checked inventory owns both namespaces. A private Table input
    // supplies an Effect root, never an ordinary Result or a send permission.
    match @strategy.checked_effect_table_input_at(owner.graph, index) {
      Some(source) => {
        guard @syntax.effect_header_kind(header) == "store" &&
          @syntax.effect_header_source_result(header) is None &&
          @syntax.effect_header_source_table_input(header) is Some(_) &&
          @strategy.checked_effect_table_input_member(source) == index &&
          @strategy.checked_effect_table_input_stage(source) == units - 1 &&
          source_task < 0 else {
          return Err(UnsupportedProgram)
        }
        source_task = @strategy.checked_effect_table_input_task(source)
      }
      None =>
        if @syntax.effect_header_source_result(header) is None ||
          @syntax.effect_header_source_table_input(header) is Some(_) {
          return Err(UnsupportedProgram)
        }
    }
    if source_task < 0 {
      return Err(UnsupportedProgram)
    }
    roots.push((name, source_task))
    let command = match
      @stage_results.effect_command_input_for_member(
        @stage_results.effect_static_candidate_command_inputs(
          @checked.effect_program_static_effects(owner.candidate),
        ),
        index,
        max_nodes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(EffectPlan(issue))
    }
    let terminal = if command is Some(_) {
      None
    } else {
      match
        @stage_results.effect_plan_terminal_for_member(
          rules, index, max_nodes, max_nodes,
        ) {
        Ok(terminal) => terminal
        Err(issue) => return Err(EffectPlan(issue))
      }
    }
    // Create and Command have no AoA EffectPlan terminal in 0.1. Their
    // admitted Mapping or Command bindings remain in the complete checked
    // Program and Environment; this does not authorize physical apply.
    if terminal is Some(terminal) {
      terminals.push((name, terminal))
    }
  }
  Ok((roots, terminals))
}
