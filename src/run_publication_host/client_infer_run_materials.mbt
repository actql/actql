///|
/// Project the source and normalized Environment from the original compiled
/// owner. The supplied Parameter Values still pass the same identity check;
/// this API cannot replace the compilation with current installation defaults.
pub fn issue_prepared_client_infer_run_materials(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  environment : @checked.CheckEnvironment,
  parameters_wire : String?,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[String, ClientTaskRunMaterialsIssue] {
  let prepared = compiled.owner
  let environment_body = @checked.checking_environment_wire(environment)
  let (program, environment_wire) = try {
    let writer = @encode.writer(65536, 8192, 64)
    @syntax.emit_program_source(prepared.source, writer)
    let program = @encode.finish(writer)
    let writer = @encode.writer(65536, 4096, 64)
    @environment.emit(environment_body, writer)
    (program, @encode.finish(writer))
  } catch {
    _ => return Err(Input(MaterialsMalformed))
  }
  issue_client_infer_run_materials(
    compiled, definition, environment, environment_wire, program, parameters_wire,
    limits,
  )
}

///|
/// Retain one installed INFER compilation in the original Run
/// materials codec. The original Environment contains the normalized Task and
/// handling/generation settings; no current project or provider default is read.
/// Physical input custody, current authority and restore admission stay separate.
pub fn issue_client_infer_run_materials(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  environment : @checked.CheckEnvironment,
  environment_wire : String,
  program : String,
  parameters_wire : String?,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[String, ClientTaskRunMaterialsIssue] {
  guard compiled.compilation is Tasks(compilation) &&
    compilation.infers.length() == 1 &&
    compilation.serialization is None else {
    return Err(Binding(UnsupportedProgram))
  }
  let graph = compilation.infers[0]
  match
    bind_client_task_run(
      compiled.owner,
      compilation,
      compiled.admission,
      definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  // This material form encodes the installed compiler's original dependency
  // selection. Custom graphs must not emit bundles their inverse would reject.
  let installed = match
    infer_run_materials_installed_graph(compiled.owner, graph.execution, limits) {
    Ok(value) => value
    Err(_) => return Err(Binding(UnsupportedProgram))
  }
  if installed.graph.wire != graph.graph.wire {
    return Err(Binding(UnsupportedProgram))
  }
  let execution = try {
    let writer = @encode.writer(65536, 4096, 64)
    @syntax.emit_admitted_source_value(
      @environment.model_execution_source(graph.execution),
      writer,
    )
    (@environment.model_execution_cid(graph.execution), @encode.finish(writer))
  } catch {
    _ => return Err(Input(MaterialsEvidence("infer_execution_contract")))
  }
  issue_client_run_materials_input(
    compiled.owner,
    compiled.admission,
    definition,
    environment,
    environment_wire,
    program,
    parameters_wire,
    infer_input=Some(execution),
  ).map_err(issue => Input(issue))
}

///|
/// Reconstruct only from saved materials, then compare the whole original Run.
/// This never resolves a current registry, configuration, model or generation
/// default. Equal DATA cannot become a live installation or a send permission.
/// Ordinary Values/Source readers retain their existing INFER-field refusal.
pub fn admit_client_infer_run_materials(
  materials : String,
  expected_run_definition_cid : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : ClientCompilationManifests,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientTaskRunMaterials, ClientTaskRunMaterialsIssue] {
  let input = match
    read_client_run_materials_input(
      materials,
      expressions,
      operations,
      limits,
      allow_infer=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  guard input.infer_input is Some((cid, wire)) else {
    return Err(Input(MaterialsEvidence("infer_execution_contract")))
  }
  let legacy_step = prepared_client_infer_step(input.prepared)
  let execution_result = if legacy_step is Some(step) {
    read_prepared_client_infer_model_execution(
      input.prepared,
      step,
      @utf8.encode(wire),
      cid,
      { max_bytes: 65536, max_nodes: 4096, max_depth: 64, max_members: 256, },
      1000000,
    )
  } else if prepared_client_composed_infer_occurrence(input.prepared)
    is Some(occurrence) {
    read_client_infer_occurrence_model_execution(
      occurrence,
      @utf8.encode(wire),
      cid,
      { max_bytes: 65536, max_nodes: 4096, max_depth: 64, max_members: 256, },
      1000000,
    )
  } else {
    return Err(Input(MaterialsEvidence("infer_execution_contract")))
  }
  let execution = match execution_result {
    Ok(value) => value
    Err(_) => return Err(Input(MaterialsEvidence("infer_execution_contract")))
  }
  let graph = match
    infer_run_materials_installed_graph(input.prepared, execution, limits) {
    Ok(value) => value
    Err(_) => return Err(Input(MaterialsEvidence("infer_execution_contract")))
  }
  let compilation_result = if legacy_step is Some(_) {
    issue_prepared_client_infer_compilation(
      input.prepared,
      graph,
      manifests,
      limits.max_sequence_steps,
      limits.max_sequence_work,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    )
  } else {
    issue_prepared_client_multi_infer_compilation(
      input.prepared,
      [graph],
      manifests,
      limits.sequence,
      limits.max_sequence_steps,
      limits.max_sequence_work,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    )
  }
  let compilation = match compilation_result {
    Ok(value) => value
    Err(issue) => return Err(Compilation(issue))
  }
  admit_client_task_run_materials_compilation(
    input, compilation, expected_run_definition_cid, limits,
  )
}

///|
// Both directions select from the same checked Program. Preserve the legacy
// component graph, including its Result transformations, byte-for-byte. A
// composed Program must have exactly one whole checked Model occurrence; its
// surrounding producers and Results belong to the ordinary composed compiler.
fn infer_run_materials_installed_graph(
  prepared : PreparedClientProgram,
  execution : @environment.ModelExecutionContract,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientInferPlanGraph, ClientInferPlanGraphIssue] {
  if prepared_client_infer_step(prepared) is Some(step) {
    return issue_installed_client_infer_plan_graph(
      prepared,
      step,
      execution,
      limits.sequence,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    )
  }
  guard prepared_client_composed_infer_occurrence(prepared) is Some(occurrence) else {
    return Err(UnsupportedProgram)
  }
  issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    limits.sequence,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  )
}
