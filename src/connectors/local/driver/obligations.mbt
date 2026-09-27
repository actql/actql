///|
/// Eligibility for the existing Local engine, not a language or DAG limit.
pub fn local_dispatch_rejection(
  installed : LocalDispatchModule,
  task : Int,
) -> String? {
  if installed.estimate_configuration is Some(configuration) &&
    configuration.eligible.get(task - 1) is Some(false) {
    return Some("policy_ineligible")
  }
  let graph = @strategy.captured_dag_graph(installed.run)
  guard @strategy.graph_task_operation_count(graph, task) is Some(count) else {
    return Some("invalid_task")
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
        ValuesPublication(_) =>
          if !@local.local_module_bounded_values_publication(
              installed.implementation,
              local_task_slot(installed, task),
            ) {
            return Some("unsupported_execution_obligation")
          }
        AppendRows(_) =>
          if !@local.local_module_bounded_append_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
            ) {
            return Some("unsupported_execution_obligation")
          }
        SetRows(_) =>
          if !@local.local_module_bounded_set_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
            ) {
            return Some("unsupported_execution_obligation")
          }
        CrossJoinRows(_) | CrossJoinIdentity(_) =>
          if !@local.local_module_bounded_cross_join_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
            ) {
            return Some("unsupported_execution_obligation")
          }
        _ => return Some("unsupported_execution_obligation")
      }
    }
  }
  None
}

///|
/// A memory-only managed provider cannot discharge a retained-output offer.
/// Keep unsupported tasks out of whole-graph planning before predecessors run.
fn local_dispatch_offer_supported(
  installed : LocalDispatchModule,
  task : Int,
) -> Bool {
  local_dispatch_rejection(installed, task) is None ||
  (
    installed.output_policy is None &&
    @local.local_module_managed_sequence_supported(
      installed.implementation,
      local_task_slot(installed, task),
    )
  )
}

///|
fn local_task_interval_search_ceilings(
  run : @strategy.CapturedDAG,
  task : Int,
) -> Array[(Int, Int64)]? {
  guard @strategy.captured_task_interval_search_count(run, task) is Some(count) else {
    return None
  }
  let ceilings = []
  for index in 0..<count {
    guard @strategy.captured_task_interval_search_at(run, task, index)
      is Some(ceiling) else {
      return None
    }
    ceilings.push(ceiling)
  }
  Some(ceilings)
}

///|
fn local_task_asof_search_ceilings(
  run : @strategy.CapturedDAG,
  task : Int,
) -> Array[(Int, Int64)]? {
  guard @strategy.captured_task_asof_search_count(run, task) is Some(count) else {
    return None
  }
  let ceilings = []
  for index in 0..<count {
    guard @strategy.captured_task_asof_search_at(run, task, index)
      is Some(ceiling) else {
      return None
    }
    ceilings.push(ceiling)
  }
  Some(ceilings)
}

///|
fn local_task_join_output_ceilings(
  run : @strategy.CapturedDAG,
  task : Int,
) -> Array[(Int, Int64)]? {
  guard @strategy.captured_task_join_output_count(run, task) is Some(count) else {
    return None
  }
  let ceilings = []
  for index in 0..<count {
    guard @strategy.captured_task_join_output_at(run, task, index)
      is Some(ceiling) else {
      return None
    }
    ceilings.push(ceiling)
  }
  Some(ceilings)
}

///|
fn local_task_aggregate_output_ceilings(
  run : @strategy.CapturedDAG,
  task : Int,
) -> Array[@connector.AggregateOutputCeiling]? {
  guard @strategy.captured_task_aggregate_output_count(run, task) is Some(count) else {
    return None
  }
  let ceilings = []
  for index in 0..<count {
    guard @strategy.captured_task_aggregate_output_at(run, task, index)
      is Some(ceiling) else {
      return None
    }
    ceilings.push(ceiling)
  }
  Some(ceilings)
}

///|
fn local_task_analytic_envelopes(
  run : @strategy.CapturedDAG,
  task : Int,
) -> Array[@connector.AnalyticEnvelope]? {
  guard @strategy.captured_task_analytic_envelope_count(run, task)
    is Some(count) else {
    return None
  }
  let envelopes = []
  for index in 0..<count {
    guard @strategy.captured_task_analytic_envelope_at(run, task, index)
      is Some(envelope) else {
      return None
    }
    envelopes.push(envelope)
  }
  Some(envelopes)
}
