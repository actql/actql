///|
pub(all) enum ClientEffectCompilationIssue {
  UnsupportedProgram
  EffectPlan(@stage_results.EffectPlanBindingIssue)
  Graph(ClientTaskPlanGraphIssue)
  Template(ClientTaskBoundTemplateIssue)
  Material(ClientExecutionMaterialIssue)
  Plan(ClientValuesExecutablePlanIssue)
  Compilation(ClientTaskCompilationIssue)
  Encoding
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
/// Compile a Values Effect Unit or an acquired root feeding one Effect Unit.
/// Existing task lowering owns the supported Relation operations. Command
/// Effects and other multi-Unit plans are rejected explicitly.
pub fn issue_prepared_client_effect_compilation(
  owner : PreparedClientEffectComputation,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectCompilation, ClientEffectCompilationIssue] {
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  let headers = @checked.effect_program_static_headers(owner.candidate)
  let count = @syntax.effect_header_count(headers)
  let units = @checked.unit_count(@strategy.graph_program(graph))
  if (units != 1 && units != 2) ||
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
  let source_free = units == 1 &&
    @pipeline.input_count(pipeline) == 0 &&
    @pipeline.starts_with_values(
      @lower.pipeline(@lower.bound_preparation(first)),
    )
  let acquired = units == 2 &&
    @pipeline.input_count(pipeline) == 1 &&
    @checked.source_execution_count(checked) == 1 &&
    @checked.unit_pipeline(checked, 1) is Some(effect_pipeline) &&
    @pipeline.input_count(effect_pipeline) == 1 &&
    @checked.unit_result_import_count(checked, 1) == Some(1) &&
    prepare_client_query_acquisition(
      {
        graph,
        source: owner.source,
        check_environment_cid: owner.check_environment_cid,
      },
      0,
      0,
    ) is Ok(_)
  if !source_free && !acquired {
    return Err(UnsupportedProgram)
  }
  // This private compiler view contains the same graph, source and Effects.
  // It is never returned as an Effect-free preparation or checked again.
  let value : PreparedClientProgram = {
    graph,
    source: owner.source,
    check_environment_cid: owner.check_environment_cid,
  }
  let roots : Array[(String, Int)] = []
  let plan_cids : Array[(String, String)] = []
  let names : Array[String] = []
  let rules = @stage_results.effect_static_candidate_mapping_rules(
    @checked.effect_program_static_effects(owner.candidate),
  )
  for index in 0..<count {
    guard @syntax.effect_header_at(headers, index) is Some(header) &&
      @syntax.effect_header_stage(header) == units - 1 &&
      @syntax.effect_header_source_result(header) is Some(_) else {
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
        return Err(UnsupportedProgram)
      }
      if @strategy.checked_effect_source_member(source) == index &&
        @strategy.checked_effect_source_stage(source) == units - 1 {
        if source_task >= 0 {
          return Err(UnsupportedProgram)
        }
        source_task = @strategy.checked_effect_source_task(source)
      }
    }
    if source_task < 0 {
      return Err(UnsupportedProgram)
    }
    roots.push((name, source_task))
    let terminal = match
      @stage_results.effect_plan_terminal_for_member(
        rules, index, max_nodes, max_nodes,
      ) {
      Ok(terminal) => terminal
      Err(issue) => return Err(EffectPlan(issue))
    }
    // Create has no EffectPlan terminal in 0.1. Its declaration and checked
    // mapping remain bound by the complete Program and Check Environment.
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
      value, sequence_limits, max_wire_bytes, max_nodes, max_depth, true, roots,
    ) {
    Ok(graph) => graph
    Err(issue) => return Err(Graph(issue))
  }
  let template = match
    issue_client_task_bound_template(
      value, manifests, max_wire_bytes, max_nodes, max_depth,
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
      effect_plan_cids=plan_cids,
    ) {
    Ok(material) => material
    Err(issue) => return Err(Material(issue))
  }
  let plan = match
    issue_prepared_client_executable_plan_with_parts(
      value,
      task_graph.wire,
      material.wire,
      max_facts,
      max_witnesses,
      max_wire_bytes,
      max_nodes,
      max_depth,
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
    ) {
    Ok(compiled) => compiled
    Err(issue) => return Err(Compilation(issue))
  }
  Ok({ owner, compiled, })
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
) -> Result[ClientEffectCompilation, ClientEffectCompilationAdmissionIssue] {
  let issued = match
    issue_prepared_client_effect_compilation(
      owner, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
      max_nodes, max_depth,
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
