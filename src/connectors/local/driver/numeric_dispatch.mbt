///|
/// The common ticket owns every selected reduction and occurrence seal. Both
/// managed and retained Store dispatch use this same exact attempt binding.
fn local_task_numeric_execution(
  run : @strategy.CapturedDAG,
  ticket : @strategy.TaskExecution,
  count : Int,
) -> @execution.NumericAggregateExecution? {
  if count == 0 {
    return None
  }
  Some(
    @execution.numeric_aggregate_execution_with_steps(
      fn(step, name, occurrence, contributors, expected_count, max_work) {
        @strategy.execute_task_numeric_reduction_for_slot(
          run, ticket, step, name, occurrence, contributors, expected_count, max_work,
        )
      },
      fn(step, name, occurrence_count) {
        @strategy.seal_task_numeric_reduction_slot(
          run, ticket, step, name, occurrence_count,
        )
      },
      fn(step, name, occurrence, contributors, expected_count, max_work) {
        @strategy.start_task_numeric_reduction_for_slot(
          run, ticket, step, name, occurrence, contributors, expected_count, max_work,
        ).map(result => {
          result.map(pending => {
            @execution.numeric_aggregate_step(
              () => @strategy.advance_task_numeric_reduction(run, pending),
              () => @strategy.close_task_numeric_reduction(run, pending),
            )
          })
        })
      },
    ),
  )
}
