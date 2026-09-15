///|
/// Eligibility for the existing Local engine, not a language or DAG limit.
/// Its selected join ceiling currently supports one occurrence per invocation.
pub fn local_dispatch_rejection(
  installed : LocalDispatchModule,
  task : Int,
) -> String? {
  let graph = @strategy.captured_dag_graph(installed.run)
  guard @strategy.graph_task_operation_count(graph, task) is Some(count) else {
    return Some("invalid_task")
  }
  if @strategy.captured_task_join_output_count(installed.run, task).unwrap() > 1 {
    return Some("multiple_join_ceilings_unsupported")
  }
  for index in 0..<count {
    let requirement = @strategy.graph_task_operation_at(graph, task, index).unwrap()
    if requirement.disposition is ExecutionCheck(check) {
      match check {
        GroupExecution(_)
        | JoinOutputLimit(_)
        | JoinRowOrder(_)
        | JoinInputValidation(_)
        | JoinIdentity(_)
        | DedupeTopTie(_) => ()
        _ => return Some("unsupported_execution_obligation")
      }
    }
  }
  None
}
