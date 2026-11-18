///|
/// Borrowed original compiler key plus a real task-boundary observation. This
/// is not a public wire value, Sample holding, stop receipt or control grant.
struct ClientLogicalTaskBoundary {
  mut original : ClientLogicalTaskBoundaryOriginal?
  cleanup : @strategy.CapturedTaskBoundary
}

///|
priv struct ClientLogicalTaskBoundaryOriginal {
  facts : ClientStructuralExplanationOriginal
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
  NoCurrentBoundary
  ForeignOriginal
  StaleBoundary
  InvalidReadLimits
  MissingOriginalOccurrence
  Encoding(@encode.EncodeFailure)
  Boundary(@strategy.CapturedTaskBoundaryIssue)
} derive(Eq, Debug)

///|
/// Read the installed hook on this SAME Run, then transfer only an independent
/// logical fork to the consumer. The temporary lower read has its own existing
/// reservation and is returned here; a declined return stays on that Owner's
/// cleanup list. This issues no read/control permission or physical backing.
pub fn read_client_logical_task_boundary(
  original : ClientStructuralExplanationOriginal,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
  run : @strategy.CapturedDAG,
  phase : @strategy.CapturedTaskBoundaryPhase,
  max_nodes : Int,
) -> Result[ClientLogicalTaskBoundaryProjection, ClientLogicalTaskBoundaryIssue] {
  if !explanation_original_matches(original, compiled, prepared) ||
    !physical_equal(@strategy.captured_dag_graph(run), prepared.graph) {
    return Err(ForeignOriginal)
  }
  if max_nodes <= 0 {
    return Err(InvalidReadLimits)
  }
  guard @strategy.captured_task_boundary_hooks(run) is Some(hooks) else {
    return Err(NoCurrentBoundary)
  }
  let observed = match
    @strategy.read_captured_task_boundary(run, hooks, phase) {
    Err(issue) => return Err(Boundary(issue))
    Ok(None) => return Err(NoCurrentBoundary)
    Ok(Some(value)) => value
  }
  let projected = bind_client_logical_task_boundary(
    original, compiled, prepared, run, observed, max_nodes,
  )
  match @strategy.return_captured_task_boundary(observed) {
    Ok(_) => projected
    Err(issue) => {
      // Do not leak the successfully issued higher context if returning this
      // method's separate temporary read declined. Dispose it before its own
      // lower token may settle; either pending token remains with the SAME Run.
      if projected is Ok(Projected(value)) {
        return_client_logical_task_boundary(value) |> ignore
      }
      match projected {
        Err(original_issue) => Err(original_issue)
        _ => Err(Boundary(issue))
      }
    }
  }
}

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
  let owned = match
    @strategy.fork_captured_task_boundary_for_logical_projection(run, observed) {
    Err(issue) => return Err(Boundary(issue))
    Ok(value) => value
  }
  let result = project_client_logical_task_boundary(
    original, prepared, run, owned, max_nodes,
  )
  if result is Ok(Projected(_)) {
    return result
  }
  // No higher wrapper was issued. Return this fork only; never the caller's
  // source observation. A failed return remains on the same Owner's list.
  let returned = @strategy.return_captured_task_boundary(owned)
  match result {
    Err(_) => result // Preserve the original construction failure.
    _ =>
      match returned {
        Err(issue) => Err(Boundary(issue))
        Ok(_) => result
      }
  }
}

///|
// Invoked only with the Owner-issued complete logical construction fork.
fn project_client_logical_task_boundary(
  original : ClientStructuralExplanationOriginal,
  prepared : PreparedClientProgram,
  run : @strategy.CapturedDAG,
  observed : @strategy.CapturedTaskBoundary,
  max_nodes : Int,
) -> Result[ClientLogicalTaskBoundaryProjection, ClientLogicalTaskBoundaryIssue] {
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
        return Ok(
          Projected({
            original: Some({ facts: original, run, observed, step, }),
            cleanup: observed,
          }),
        )
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
  guard value.original is Some(original) else { return false }
  explanation_original_matches(original.facts, compiled, prepared) &&
  @strategy.captured_task_boundary_current(original.run, original.observed) &&
  value.original is Some(current) &&
  physical_equal(current, original)
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
  Ok(explanation_original_text(value.original.unwrap().step, "step_id")) catch {
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
      explanation_original_field(value.original.unwrap().step, "key"),
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
  guard @canonical.object_field(value.original.unwrap().step, "ports")
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

///|
/// Release this higher wrapper's independent original fork. Dispose its heavy
/// context BEFORE the same lower Owner may acknowledge or autonomously retry
/// settlement. Only that exact token remains reachable for pending cleanup.
/// A completed token is a scalar tombstone; repeated logical close is harmless.
pub fn return_client_logical_task_boundary(
  value : ClientLogicalTaskBoundary,
) -> Result[Unit, ClientLogicalTaskBoundaryIssue] {
  // Do not bind the old context to a local across settlement callbacks. The
  // only retained alias is the prequoted original token, never facts/Run/step.
  value.original = None
  match @strategy.return_captured_task_boundary(value.cleanup) {
    Err(@strategy.ReadReturned) | Ok(_) => Ok(())
    Err(issue) => Err(Boundary(issue))
  }
}
