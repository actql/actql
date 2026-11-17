///|
/// Borrowed original compiler key plus a real task-boundary observation. This
/// is not a public wire value, Sample holding, stop receipt or control grant.
struct ClientLogicalTaskBoundary {
  original : ClientStructuralExplanationOriginal
  run : @strategy.CapturedDAG
  observed : @strategy.CapturedTaskBoundary
  step : @canonical.CanonicalValue
}

///|
pub(all) enum ClientLogicalBoundaryUnavailable {
  FusedPhysicalTask
  NoLogicalOperation
} derive(Eq, Debug)

///|
pub enum ClientLogicalTaskBoundaryProjection {
  Projected(ClientLogicalTaskBoundary)
  NotProjected(ClientLogicalBoundaryUnavailable)
}

///|
pub(all) enum ClientLogicalTaskBoundaryIssue {
  ForeignOriginal
  StaleBoundary
  InvalidReadLimits
  MissingOriginalOccurrence
  Encoding(@encode.EncodeFailure)
} derive(Eq, Debug)

///|
/// Only a separately owned selected operation, or a genuinely single-operation
/// task, has this exact logical boundary. A fused prefix cannot name its last
/// card as if all internal operations independently stopped or emitted output.
pub fn bind_client_logical_task_boundary(
  original : ClientStructuralExplanationOriginal,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  run : @strategy.CapturedDAG,
  observed : @strategy.CapturedTaskBoundary,
  max_nodes : Int,
) -> Result[ClientLogicalTaskBoundaryProjection, ClientLogicalTaskBoundaryIssue] {
  if !explanation_original_matches(original, compiled, prepared) {
    return Err(ForeignOriginal)
  }
  if !@strategy.captured_task_boundary_current(run, observed) {
    return Err(StaleBoundary)
  }
  if !@strategy.captured_task_boundary_matches_graph(observed, prepared.graph) {
    return Err(ForeignOriginal)
  }
  if max_nodes <= 0 {
    return Err(InvalidReadLimits)
  }
  guard @canonical.object_field(original.map, "steps")
    is Some(@canonical.Array(steps)) else {
    return Err(MissingOriginalOccurrence)
  }
  if @canonical.array_count(steps) > max_nodes {
    return Err(InvalidReadLimits)
  }
  let graph = prepared.graph
  let task = @strategy.captured_task_boundary_task(observed)
  guard @strategy.graph_task_unit_index(graph, task) is Some(stage) &&
    @checked.unit_pipeline(@strategy.graph_program(graph), stage)
    is Some(pipeline) else {
    return Err(MissingOriginalOccurrence)
  }
  let selected = @strategy.graph_task_selected_step(graph, task)
  let index = match selected {
    Some(index) => index
    None => {
      let count = @pipeline.step_count(pipeline)
      if count == 0 {
        return Ok(NotProjected(NoLogicalOperation))
      }
      if !(@strategy.graph_task_prefix_end(graph, task) == Some(0) ||
        (@strategy.graph_task_prefix_end(graph, task) is None && count == 1)) {
        return Ok(NotProjected(FusedPhysicalTask))
      }
      guard @strategy.graph_task_target(graph, task) is Some(@pipeline.Step(0)) else {
        return Ok(NotProjected(FusedPhysicalTask))
      }
      0
    }
  }
  if @strategy.graph_stage_operation_task(graph, stage, index) != Some(task) {
    return Err(MissingOriginalOccurrence)
  }
  try {
    for i in 0..<@canonical.array_count(steps) {
      let step = @canonical.array_at(steps, i).unwrap()
      let key = explanation_original_field(step, "key")
      if explanation_original_ordinal(key, "stage_ordinal") != stage {
        continue
      }
      let occurrence = explanation_original_field(key, "occurrence")
      if explanation_original_text(occurrence, "kind") == "operation" &&
        explanation_original_ordinal(occurrence, "operation_ordinal") == index {
        return Ok(Projected({ original, run, observed, step, }))
      }
    }
    Err(MissingOriginalOccurrence)
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// Uses the same original task generation/strategy fence, not a new control
/// clock. Actual Run read/egress/control authorization remains with its Owner.
pub fn client_logical_task_boundary_current(
  value : ClientLogicalTaskBoundary,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
) -> Bool {
  explanation_original_matches(value.original, compiled, prepared) &&
  @strategy.captured_task_boundary_current(value.run, value.observed)
}

///|
pub fn client_logical_task_boundary_step_id(
  value : ClientLogicalTaskBoundary,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
) -> Result[String, ClientLogicalTaskBoundaryIssue] {
  if !client_logical_task_boundary_current(value, compiled, prepared) {
    return Err(StaleBoundary)
  }
  Ok(explanation_original_text(value.step, "step_id")) catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// Bounded emission of the existing complete original key; no identity is
/// issued or changed. The caller first backs this read/emit overlap.
pub fn client_logical_task_boundary_key_json(
  value : ClientLogicalTaskBoundary,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientLogicalTaskBoundaryIssue] {
  if !client_logical_task_boundary_current(value, compiled, prepared) {
    return Err(StaleBoundary)
  }
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidReadLimits)
  }
  Ok(
    @canonical.stringify_value(
      explanation_original_field(value.step, "key"),
      max_bytes,
      max_nodes,
      max_depth,
    ),
  ) catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// Existing output identity only, not permission to read/capture its value.
pub fn client_logical_task_boundary_output_port_id(
  value : ClientLogicalTaskBoundary,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  ordinal : Int,
  max_ports : Int,
) -> Result[String?, ClientLogicalTaskBoundaryIssue] {
  if !client_logical_task_boundary_current(value, compiled, prepared) {
    return Err(StaleBoundary)
  }
  if ordinal < 0 || max_ports <= 0 {
    return Err(InvalidReadLimits)
  }
  guard @canonical.object_field(value.step, "ports")
    is Some(@canonical.Array(ports)) else {
    return Err(MissingOriginalOccurrence)
  }
  if @canonical.array_count(ports) > max_ports {
    return Err(InvalidReadLimits)
  }
  try {
    for i in 0..<@canonical.array_count(ports) {
      let port = @canonical.array_at(ports, i).unwrap()
      if explanation_original_text(port, "role") == "output" &&
        explanation_original_ordinal(port, "port_ordinal") == ordinal {
        return Ok(Some(explanation_original_text(port, "port_id")))
      }
    }
    Ok(None)
  } catch {
    issue => Err(Encoding(issue))
  }
}
