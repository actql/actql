///|
/// One INFER occurrence selected from the original checked task graph. This
/// connects compilation to the Model component; it grants no dispatch or
/// egress authority and does not replace the checked Effect owner.
pub struct ClientInferOccurrence {
  owner : PreparedClientProgram
  task : Int
  stage : Int
  step : Int
  preparation : @lower.BoundPrepared
}

///|
pub fn client_infer_occurrence_coordinates(
  value : ClientInferOccurrence,
) -> (Int, Int, Int) {
  (value.task, value.stage, value.step)
}

///|
/// Installed provider selection uses the Task retained by the original
/// checked occurrence. This identity is never a dispatch authorization.
pub fn client_infer_occurrence_model_task_cid(
  value : ClientInferOccurrence,
) -> String? {
  guard client_infer_occurrence_matches(value, value.owner) &&
    @lower.node_at(@lower.bound_preparation(value.preparation), value.step)
    is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) else {
    return None
  }
  Some(@environment.model_task_identity(@infer.model_task(infer)).2)
}

///|
pub fn read_client_infer_occurrence_model_execution(
  value : ClientInferOccurrence,
  body : Bytes,
  expected_cid : String,
  limits : @environment.Limits,
  max_work : Int,
) -> Result[@environment.ModelExecutionContract, ClientInferPlanGraphIssue] {
  if !client_infer_occurrence_matches(value, value.owner) {
    return Err(UnsupportedProgram)
  }
  read_client_infer_owner_model_execution(
    value.preparation,
    value.step,
    body,
    expected_cid,
    limits,
    max_work,
  )
}

///|
pub fn client_infer_occurrence_matches(
  value : ClientInferOccurrence,
  owner : PreparedClientProgram,
) -> Bool {
  physical_equal(value.owner, owner) &&
  @strategy.graph_task_selected_step(owner.graph, value.task) is None &&
  client_infer_occurrence_output_step(value)
  .map(last => value.step <= last)
  .unwrap_or(false) &&
  @strategy.graph_task_owner(owner.graph, value.task)
  .map(preparation => physical_equal(preparation, value.preparation))
  .unwrap_or(false)
}

///|
/// Select by checked ownership and task boundaries, never Program JSON. A
/// selected Compute task cannot claim an INFER elsewhere in the same Unit.
/// A retained prefix keeps the same complete Model occurrence and its original
/// Stage inputs; independently selected suffix tasks cannot claim that Model.
pub fn prepared_client_composed_infer_occurrence(
  owner : PreparedClientProgram,
) -> ClientInferOccurrence? {
  guard prepared_client_composed_infer_occurrences(owner) is Some(occurrences) &&
    occurrences.length() == 1 else {
    return None
  }
  occurrences.get(0)
}

///|
/// Enumerate exact checked occurrences in graph order. Each component retains
/// one whole Unit or fused prefix; selected tasks and two Model boundaries in
/// one Unit still need their own input-custody connection. This grants no dispatch.
pub fn prepared_client_composed_infer_occurrences(
  owner : PreparedClientProgram,
) -> Array[ClientInferOccurrence]? {
  let graph = owner.graph
  let selected : Array[ClientInferOccurrence] = []
  for task in 0..<@strategy.graph_task_count(graph) {
    guard @strategy.graph_task_owner(graph, task) is Some(preparation) &&
      @strategy.graph_task_unit_index(graph, task) is Some(stage) else {
      return None
    }
    let count = @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(preparation)),
    )
    if count == 0 {
      // A checked input-only task has a real receiving Carrier, not a
      // fabricated output operation. Keep the same owner/target validation.
      guard client_task_output_target(graph, task) is Some(@pipeline.Input(_)) else {
        return None
      }
      continue
    }
    guard client_task_output_step(graph, task, count) is Some(last) else {
      return None
    }
    let first = @strategy.graph_task_selected_step(graph, task).unwrap_or(0)
    let mut selected_in_task = false
    for step in first..<(last + 1) {
      guard @lower.node_at(@lower.bound_preparation(preparation), step)
        is Some(node) else {
        return None
      }
      if @lower.payload(node) is @lower.Infer(_) {
        // The original checked graph already owns its task/work inventory.
        // Keep Unit/selected-task custody restrictions, not another count cap.
        if selected_in_task ||
          @strategy.graph_task_selected_step(graph, task) is Some(_) {
          return None
        }
        selected.push({ owner, task, stage, step, preparation, })
        selected_in_task = true
      }
    }
  }
  Some(selected)
}

///|
pub fn client_infer_occurrence_target_name(
  occurrence : ClientInferOccurrence,
) -> String? {
  if !client_infer_occurrence_matches(occurrence, occurrence.owner) {
    return None
  }
  client_infer_owner_target_name(occurrence.preparation, occurrence.step)
}

///|
/// Retain the same private compiler view already used by Effect compilation.
/// No Effect-free Program is reconstructed or checked again.
pub fn prepared_client_effect_infer_occurrence(
  owner : PreparedClientEffectComputation,
) -> ClientInferOccurrence? {
  prepared_client_composed_infer_occurrence(client_effect_program_view(owner))
}

///|
/// Keep the existing component constructor's admitted input scope. Composed
/// execution obtains its occurrence from compilation, never this fallback.
pub fn prepared_client_infer_execution_occurrence(
  owner : PreparedClientProgram,
  step : Int,
) -> ClientInferOccurrence? {
  client_infer_metadata_owner(owner, 0, step).map(preparation => {
    owner,
    task: 0,
    stage: 0,
    step,
    preparation,
  })
}

///|
/// Only the Relation preparation escapes; the private Effect compiler view
/// is never returned as an Effect-free prepared Program.
pub fn client_infer_occurrence_preparation(
  occurrence : ClientInferOccurrence,
) -> @lower.BoundPrepared {
  occurrence.preparation
}

///|
pub fn client_infer_occurrence_terminal(
  occurrence : ClientInferOccurrence,
) -> Bool {
  client_infer_occurrence_matches(occurrence, occurrence.owner) &&
  client_infer_occurrence_output_step(occurrence) == Some(occurrence.step)
}

///|
/// The original physical task's checked output, not the terminal of a later
/// independently owned suffix in the same authored Unit.
pub fn client_infer_occurrence_output_step(
  occurrence : ClientInferOccurrence,
) -> Int? {
  client_task_output_step(
    occurrence.owner.graph,
    occurrence.task,
    @lower.node_count(@lower.bound_preparation(occurrence.preparation)),
  )
}

///|
pub fn client_infer_occurrence_matches_plan(
  occurrence : ClientInferOccurrence,
  plan : ClientInferPlanGraph,
) -> Bool {
  client_infer_occurrence_matches(occurrence, plan.owner) &&
  occurrence.task == plan.task &&
  occurrence.stage == plan.stage &&
  occurrence.step == plan.source_ordinal
}

///|
pub fn client_infer_occurrence_matches_compiled_run(
  occurrence : ClientInferOccurrence,
  compiled : ClientCompiledRun,
) -> Bool {
  client_infer_occurrence_matches(occurrence, compiled.owner) &&
  client_compiled_run_infers(compiled).any(plan => {
    client_infer_occurrence_matches_plan(occurrence, plan)
  })
}

///|
pub fn client_infer_occurrence_has_captured_sources(
  occurrence : ClientInferOccurrence,
) -> Bool {
  @strategy.graph_captured_prefix(occurrence.owner.graph) > 0
}

///|
pub fn client_infer_occurrence_matches_effect(
  occurrence : ClientInferOccurrence,
  owner : PreparedClientEffectComputation,
) -> Bool {
  physical_equal(occurrence.owner.source, owner.source) &&
  physical_equal(
    occurrence.owner.graph,
    @strategy.checked_effect_computation_graph(owner.graph),
  ) &&
  occurrence.owner.check_environment_cid == owner.check_environment_cid
}

///|
pub fn client_infer_occurrence_matches_egress(
  occurrence : ClientInferOccurrence,
  admission : ClientInferEgressAdmission,
  plan : ClientInferPlanGraph,
) -> Bool {
  client_infer_occurrence_matches_plan(occurrence, plan) &&
  client_infer_egress_matches(admission, occurrence.owner, plan)
}

///|
pub fn client_infer_occurrence_host_ceilings(
  occurrence : ClientInferOccurrence,
) -> Result[(Int64, Int64), ClientInferHostCapacityIssue] {
  if !client_infer_occurrence_matches(occurrence, occurrence.owner) {
    return Err(UnsupportedProgram)
  }
  let items = match
    read_client_infer_host_ceiling(
      occurrence.owner,
      "max_infer_items",
      MissingItemCeiling,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  read_client_infer_host_ceiling(
    occurrence.owner,
    "max_model_request_bytes_per_item",
    MissingRequestCeiling,
  ).map(bytes => (items, bytes))
}

///|
/// Exact checked Effect occurrences in the existing task order. This borrows
/// its private compiler view without issuing an Effect-free preparation.
pub fn prepared_client_effect_infer_occurrences(
  owner : PreparedClientEffectComputation,
) -> Array[ClientInferOccurrence]? {
  prepared_client_composed_infer_occurrences(client_effect_program_view(owner))
}
