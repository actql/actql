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
/// Retain the installed INFER compilation in the original Run
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
    !compilation.infers.is_empty() &&
    compilation.serialization is None else {
    return Err(Binding(UnsupportedProgram))
  }
  if compilation.infers.length() > 1 {
    return issue_plural_client_infer_run_materials(
      compiled, definition, environment, environment_wire, program, parameters_wire,
      limits,
    )
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
    infer_run_materials_installed_graph(
      compiled.owner,
      graph.execution,
      limits,
      compilation.infer is None,
    ) {
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
  if input.infer_inputs_wire is Some(wire) {
    let graphs = match
      read_plural_client_infer_run_graphs(input.prepared, wire, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let compilation = match
      issue_prepared_client_multi_infer_compilation(
        input.prepared,
        graphs,
        manifests,
        limits.sequence,
        limits.max_sequence_steps,
        limits.max_sequence_work,
        limits.max_evidence_bytes,
        limits.max_evidence_nodes,
        limits.max_evidence_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Compilation(issue))
    }
    return admit_client_task_run_materials_compilation(
      input, compilation, expected_run_definition_cid, limits,
    )
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
  // A one-task Program can have either the historical whole-INFER compiler
  // or the composed compiler used by the ordinary Host. Syntax alone cannot
  // select its original: only a complete saved admission/Run match can do so.
  // Both candidates use this same checked input and saved Model contract.
  let modes = if legacy_step is Some(_) { [false, true] } else { [true] }
  let mut selected : ClientTaskRunMaterials? = None
  let mut first_error : ClientTaskRunMaterialsIssue? = None
  for composed in modes {
    let candidate = infer_run_materials_compilation(
      input, execution, composed, manifests, limits,
    ).bind(compilation => {
      admit_client_task_run_materials_compilation(
        input, compilation, expected_run_definition_cid, limits,
      )
    })
    match candidate {
      Ok(value) => {
        if selected is Some(_) {
          return Err(Binding(UnsupportedProgram))
        }
        selected = Some(value)
      }
      Err(issue) => if first_error is None { first_error = Some(issue) }
    }
  }
  match selected {
    Some(value) => Ok(value)
    None => Err(first_error.unwrap_or(Binding(UnsupportedProgram)))
  }
}

///|
fn infer_run_materials_compilation(
  input : ClientRunMaterialsInput,
  execution : @environment.ModelExecutionContract,
  composed : Bool,
  manifests : ClientCompilationManifests,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientTaskCompilation, ClientTaskRunMaterialsIssue] {
  let graph = match
    infer_run_materials_installed_graph(
      input.prepared,
      execution,
      limits,
      composed,
    ) {
    Ok(value) => value
    Err(_) => return Err(Input(MaterialsEvidence("infer_execution_contract")))
  }
  let result = if composed {
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
  } else {
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
  }
  result.map_err(issue => Compilation(issue))
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
  composed : Bool,
) -> Result[ClientInferPlanGraph, ClientInferPlanGraphIssue] {
  if !composed {
    guard prepared_client_infer_step(prepared) is Some(step) else {
      return Err(UnsupportedProgram)
    }
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

///|
/// Store the complete original occurrence order, not a set of Task CIDs. Two
/// occurrences may legitimately share one Task/execution contract. Their
/// checked coordinates and original component graphs must still be distinct.
fn issue_plural_client_infer_run_materials(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  environment : @checked.CheckEnvironment,
  environment_wire : String,
  program : String,
  parameters_wire : String?,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[String, ClientTaskRunMaterialsIssue] {
  guard compiled.compilation is Tasks(compilation) &&
    compilation.infer is None &&
    prepared_client_composed_infer_occurrences(compiled.owner)
    is Some(occurrences) &&
    occurrences.length() > 1 &&
    occurrences.length() == compilation.infers.length() else {
    return Err(Binding(UnsupportedProgram))
  }
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
  let inventory = match encode_client_infer_original_inventory(occurrences, compilation.infers, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }

  issue_client_run_materials_input(
    compiled.owner,
    compiled.admission,
    definition,
    environment,
    environment_wire,
    program,
    parameters_wire,
    infer_inputs_wire=Some(inventory),
  ).map_err(issue => Input(issue))
}

///|
fn read_plural_client_infer_run_graphs(
  prepared : PreparedClientProgram,
  wire : String,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[Array[ClientInferPlanGraph], ClientTaskRunMaterialsIssue] {
  let invalid = ClientTaskRunMaterialsIssue::Input(
    MaterialsEvidence("infer_execution_contracts"),
  )
  guard prepared_client_composed_infer_occurrences(prepared)
    is Some(occurrences) &&
    occurrences.length() > 1 else {
    return Err(invalid)
  }
  let parsed = match
    @source.parse_json_bytes(@utf8.encode(wire), {
      max_input_bytes: limits.max_evidence_bytes,
      max_nodes: limits.max_evidence_nodes,
      max_depth: limits.max_evidence_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(invalid)
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_evidence_nodes,
      max_depth: limits.max_evidence_depth,
      max_string_bytes: limits.max_evidence_bytes,
      max_total_string_bytes: limits.max_evidence_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(invalid)
  }
  guard @decode.array_length(root) == Some(occurrences.length()) else {
    return Err(invalid)
  }
  let graphs = []
  for index in 0..<occurrences.length() {
    let occurrence = occurrences[index]
    let object = match
      @decode.closed_object(@decode.element_at(root, index).unwrap(), [
        "execution_contract_cid", "execution_contract_json", "stage", "step", "task",
      ]) {
      Ok(value) => value
      Err(_) => return Err(invalid)
    }
    let (task, stage, step) = client_infer_occurrence_coordinates(occurrence)
    for (name, expected) in [("stage", stage), ("step", step), ("task", task)] {
      guard @decode.lookup(object, name) is Some(value) &&
        @decode.safe_integer(value) == Ok(expected.to_int64()) else {
        return Err(invalid)
      }
    }
    guard @decode.lookup(object, "execution_contract_cid") is Some(cid) &&
      @decode.text(cid) is Ok(cid) &&
      @decode.lookup(object, "execution_contract_json") is Some(body) &&
      @decode.text(body) is Ok(body) else {
      return Err(invalid)
    }
    let execution = match
      read_client_infer_occurrence_model_execution(
        occurrence,
        @utf8.encode(body),
        cid,
        { max_bytes: 65536, max_nodes: 4096, max_depth: 64, max_members: 256, },
        1000000,
      ) {
      Ok(value) => value
      Err(_) => return Err(invalid)
    }
    let graph = match
      issue_installed_client_composed_infer_plan_graph(
        occurrence,
        execution,
        limits.sequence,
        limits.max_evidence_bytes,
        limits.max_evidence_nodes,
        limits.max_evidence_depth,
      ) {
      Ok(value) => value
      Err(_) => return Err(invalid)
    }
    graphs.push(graph)
  }
  Ok(graphs)
}

///|
// The same closed ordered inventory codec serves Program and Effect owners;
// each caller first proves its own typed compilation/Run correspondence.
fn encode_client_infer_original_inventory(
  occurrences : Array[ClientInferOccurrence],
  graphs : Array[ClientInferPlanGraph],
  limits : ClientValuesRunMaterialsLimits,
) -> Result[String, ClientTaskRunMaterialsIssue] {
  if occurrences.length() < 2 || occurrences.length() > 128 || graphs.length() != occurrences.length() {
    return Err(Binding(UnsupportedProgram))
  }
  let inventory = try {
    let writer = @encode.writer(
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    )
    @encode.begin_array(writer)
    for index in 0..<occurrences.length() {
      let occurrence = occurrences[index]
      let graph = graphs[index]
      if !client_infer_occurrence_matches_plan(occurrence, graph) {
        return Err(Binding(UnsupportedProgram))
      }
      let installed = match
        issue_installed_client_composed_infer_plan_graph(
          occurrence,
          graph.execution,
          limits.sequence,
          limits.max_evidence_bytes,
          limits.max_evidence_nodes,
          limits.max_evidence_depth,
        ) {
        Ok(value) => value
        Err(_) => return Err(Binding(UnsupportedProgram))
      }
      if installed.graph.wire != graph.graph.wire {
        return Err(Binding(UnsupportedProgram))
      }
      let body = @encode.writer(65536, 4096, 64)
      @syntax.emit_admitted_source_value(
        @environment.model_execution_source(graph.execution),
        body,
      )
      let (task, stage, step) = client_infer_occurrence_coordinates(occurrence)
      @encode.begin_object(writer)
      @encode.key(writer, "execution_contract_cid")
      @encode.string_value(
        writer,
        @environment.model_execution_cid(graph.execution),
      )
      @encode.key(writer, "execution_contract_json")
      @encode.string_value(writer, @encode.finish(body))
      for (name, value) in [("stage", stage), ("step", step), ("task", task)] {
        @encode.key(writer, name)
        @encode.number_value(writer, value.to_double())
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Input(MaterialsEvidence("infer_execution_contracts")))
  }
  Ok(inventory)
}
