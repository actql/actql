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
  @strategy.graph_task_prefix_end(owner.graph, value.task) is None &&
  @strategy.graph_task_owner(owner.graph, value.task)
  .map(preparation => physical_equal(preparation, value.preparation))
  .unwrap_or(false)
}

///|
/// Select by checked ownership and task boundaries, never Program JSON. A
/// selected Compute task cannot claim an INFER elsewhere in the same Unit.
/// The initial composition increment accepts exactly one Model occurrence in
/// a complete Unit task. Split-task input custody needs a separate connection.
pub fn prepared_client_composed_infer_occurrence(
  owner : PreparedClientProgram,
) -> ClientInferOccurrence? {
  let graph = owner.graph
  let mut selected : ClientInferOccurrence? = None
  for task in 0..<@strategy.graph_task_count(graph) {
    guard @strategy.graph_task_owner(graph, task) is Some(preparation) &&
      @strategy.graph_task_unit_index(graph, task) is Some(stage) else {
      return None
    }
    let count = @pipeline.step_count(
      @lower.pipeline(@lower.bound_preparation(preparation)),
    )
    guard client_task_output_step(graph, task, count) is Some(last) else {
      return None
    }
    let first = @strategy.graph_task_selected_step(graph, task).unwrap_or(0)
    for step in first..<(last + 1) {
      guard @lower.node_at(@lower.bound_preparation(preparation), step)
        is Some(node) else {
        return None
      }
      if @lower.payload(node) is @lower.Infer(_) {
        if selected is Some(_) ||
          @strategy.graph_task_selected_step(graph, task) is Some(_) ||
          @strategy.graph_task_prefix_end(graph, task) is Some(_) {
          return None
        }
        selected = Some({ owner, task, stage, step, preparation, })
      }
    }
  }
  selected
}

///|
/// Retain the same private compiler view already used by Effect compilation.
/// No Effect-free Program is reconstructed or checked again.
pub fn prepared_client_effect_infer_occurrence(
  owner : PreparedClientEffectComputation,
) -> ClientInferOccurrence? {
  prepared_client_composed_infer_occurrence(client_effect_program_view(owner))
}
