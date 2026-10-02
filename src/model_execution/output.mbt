///|
/// Output custody belongs to the accepted model execution, not to a caller's
/// ModelCaptureBundle. Keep this owner until its downstream publication ends.
struct ModelOutputPreparation {
  execution : ModelExecution
  materialization : @relation.AdmittedOutputPreparation
  port : @relation.TrustedOutputPort[Unit]
  mut completed : @relation.CompletedOutput?
  mut reclaimed : Bool
}

///|
fn model_output_cell(
  state : ModelState,
  schema : @schema.Schema,
  row : Int,
  column : Int,
) -> @admitted.Value? {
  if !state.accepted || state.reclaimed {
    return None
  }
  guard state.outcomes.get(row) is Some(outcome) &&
    @schema.field_at(schema, column) is Some(field) else {
    return None
  }
  let owner = @relation.prepared_infer_rows_owner(state.rows)
  let name = @schema.reference_name(field.name)
  if name == "outcome" {
    return @admitted.text_value(adopted_model_slot_outcome(outcome), 32)
  }
  if name == "value" {
    return match outcome {
      Success(index) =>
        state.captures.get(index).map(value => value.value.value)
      NoResponseFailure(_) => Some(@admitted.null_value())
    }
  }
  for key in 0..<@infer.key_count(owner) {
    if @infer.key_at(owner, key) is Some(binding) && binding.field == field.name {
      return @relation.prepared_infer_rows_key(state.rows, row, key).map(value => {
        value.value
      })
    }
  }
  None
}

///|
/// Exact typed target selection and a private accepted execution are both
/// required. Raw captures, even with matching CIDs, cannot complete a task.
pub fn start_model_output_preparation(
  execution : ModelExecution,
  completion : @relation.CompletionPreparation,
  max_rows : Int,
  values : @relation.ValueLimits,
  max_step_work : Int,
  max_workspace_slots : Int,
) -> Result[ModelOutputPreparation, ModelExecutionIssue] {
  let state = execution.state
  if !state.accepted ||
    state.reclaimed ||
    state.output_uses == 2147483647 ||
    !@relation.infer_completion_matches_rows(completion, state.rows) {
    return Err(OutputIdentity)
  }
  let owner = @relation.completion_preparation_owner(completion)
  let target = @pipeline.Step(
    @relation.completion_preparation_terminal_step(completion),
  )
  let schema = @infer.output_schema(
    @relation.prepared_infer_rows_owner(state.rows),
  )
  // Field dispatch is small and admitted before execution; nested values are
  // checked incrementally, not hidden inside one callback or row operation.
  if @schema.field_count(schema) > 256 {
    return Err(InvalidLimits)
  }
  let output = match
    @relation.prepare_admitted_output(owner, target, max_rows, values) {
    Ok(value) => value
    Err(_) => return Err(OutputValue)
  }
  let materialization = match
    @relation.start_admitted_output_preparation(
      output,
      state.outcomes.length(),
      max_step_work,
      max_workspace_slots,
      (row, column) => model_output_cell(state, schema, row, column),
    ) {
    Ok(value) => value
    Err(_) => return Err(OutputValue)
  }
  let port = match
    @relation.prepare_trusted_output_port(completion, target, 256, 65536, _ => {
      if state.accepted && !state.reclaimed {
        @relation.admitted_output_preparation_rows(materialization)
      } else {
        None
      }
    }) {
    Ok(value) => value
    Err(_) => {
      @relation.cancel_admitted_output_preparation(materialization) |> ignore
      @relation.advance_admitted_output_preparation(materialization, 1)
      |> ignore
      @relation.cleanup_admitted_output_preparation(materialization) |> ignore
      return Err(OutputIdentity)
    }
  }
  state.output_uses += 1
  Ok({ execution, materialization, port, completed: None, reclaimed: false, })
}

///|
pub fn advance_model_output_preparation(
  value : ModelOutputPreparation,
  quantum : Int,
) -> Result[@relation.AdmittedOutputPoll, ModelExecutionIssue] {
  @relation.advance_admitted_output_preparation(value.materialization, quantum).map_err(issue => {
      Session(issue)
    },
  )
}

///|
pub fn complete_model_output(
  value : ModelOutputPreparation,
) -> Result[@relation.CompletedOutput, ModelExecutionIssue] {
  if value.reclaimed {
    return Err(OutputIdentity)
  }
  if value.completed is Some(output) {
    return Ok(output)
  }
  match @relation.complete_trusted_output(value.port, ()) {
    Ok(output) => {
      value.completed = Some(output)
      Ok(output)
    }
    Err(_) => Err(OutputIdentity)
  }
}

///|
pub fn cancel_model_output_preparation(value : ModelOutputPreparation) -> Bool {
  @relation.cancel_admitted_output_preparation(value.materialization)
}

///|
pub fn cleanup_model_output_preparation(
  value : ModelOutputPreparation,
) -> Result[Bool, ModelExecutionIssue] {
  if value.reclaimed {
    return Ok(true)
  }
  match @relation.cleanup_admitted_output_preparation(value.materialization) {
    Ok(false) => Ok(false)
    Ok(true) => {
      value.execution.state.output_uses -= 1
      value.completed = None
      value.reclaimed = true
      Ok(true)
    }
    Err(issue) => Err(Session(issue))
  }
}
