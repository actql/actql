///|
/// One private pending occurrence, bound to its exact managed attempt.
/// Only the common owner can turn its completed reduction into a capture.
struct TaskNumericExecution {
  execution : TaskExecution
  selected : Int
  occurrence : Int
  state : @numeric.ReductionExecution
  mut closed : Bool
}

///|
pub fn start_task_numeric_reduction_for_slot(
  run : CapturedDAG,
  execution : TaskExecution,
  step : Int,
  name : String,
  occurrence : Int,
  contributors : Array[Double],
  expected_count : Int,
  max_work : Int,
) -> Result[TaskNumericExecution, @numeric.ReductionIssue]? {
  if run.stopped ||
    !task_execution_matches(run, execution) ||
    execution.disposed ||
    execution.numeric_sealed ||
    occurrence < 0 {
    return None
  }
  let mut selected_index = None
  for index, selected in execution.numeric {
    if selected.observation.step == step && selected.observation.name == name {
      if selected_index is Some(_) {
        return None
      }
      selected_index = Some(index)
    }
  }
  guard selected_index is Some(index) else { return None }
  if !numeric_reduction_slot_open(execution.numeric_occurrence_counts, index) ||
    execution.numeric_captures.any(capture => {
      capture.selected == index && capture.occurrence == occurrence
    }) ||
    execution.numeric_pending.any(pending => {
      pending.selected == index && pending.occurrence == occurrence
    }) {
    return None
  }
  let selected = execution.numeric[index]
  let state = match
    @numeric.start_reduction(
      selected.reduction,
      selected.observation.operation,
      contributors,
      expected_count,
      max_work,
    ) {
    Err(issue) => return Some(Err(issue))
    Ok(state) => state
  }
  let pending : TaskNumericExecution = {
    execution,
    selected: index,
    occurrence,
    state,
    closed: false,
  }
  execution.numeric_pending.push(pending)
  Some(Ok(pending))
}

///|
fn detach_task_numeric_reduction(pending : TaskNumericExecution) -> Unit {
  let entries = pending.execution.numeric_pending
  for index in 0..<entries.length() {
    if physical_equal(entries[index], pending) {
      entries.remove(index) |> ignore
      break
    }
  }
  @numeric.close_reduction(pending.state)
  pending.closed = true
}

///|
/// Abandon only this occurrence. Consumed work and other slot states remain.
pub fn close_task_numeric_reduction(
  run : CapturedDAG,
  pending : TaskNumericExecution,
) -> Bool {
  if !task_execution_matches(run, pending.execution) {
    return false
  }
  if !pending.closed {
    detach_task_numeric_reduction(pending)
  }
  true
}

///|
pub fn advance_task_numeric_reduction(
  run : CapturedDAG,
  pending : TaskNumericExecution,
) -> Result[@numeric.Outcome?, @numeric.ReductionIssue]? {
  let execution = pending.execution
  if task_execution_matches(run, execution) && run.stopped && !pending.closed {
    detach_task_numeric_reduction(pending)
    return None
  }
  if !task_execution_matches(run, execution) ||
    pending.closed ||
    execution.disposed ||
    execution.numeric_sealed ||
    !numeric_reduction_slot_open(
      execution.numeric_occurrence_counts,
      pending.selected,
    ) {
    return None
  }
  let result = @numeric.advance_reduction(pending.state)
  match result {
    Ok(None) => ()
    Err(_) => detach_task_numeric_reduction(pending)
    Ok(Some(outcome)) => {
      execution.numeric_captures.push({
        selected: pending.selected,
        occurrence: pending.occurrence,
        outcome,
      })
      detach_task_numeric_reduction(pending)
    }
  }
  Some(result)
}
