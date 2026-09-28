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
        JoinOutputLimit(_)
        | JoinRowOrder(_)
        | JoinInputValidation(_)
        | JoinIdentity(_) => ()
        GroupExecution(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.Group,
            ) {
            return Some("unsupported_execution_obligation")
          }
        AnalyticExecution(_) | AnalyticEnvelope(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.Analytic,
            ) {
            return Some("unsupported_execution_obligation")
          }
        PivotExecution(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.Pivot,
            ) {
            return Some("unsupported_execution_obligation")
          }
        WindowExecution(_) | WindowMembershipLimit(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.RowWindow,
            ) {
            return Some("unsupported_execution_obligation")
          }
        TopKExecution(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.TopK,
            ) {
            return Some("unsupported_execution_obligation")
          }
        LagExecution(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.Lag,
            ) {
            return Some("unsupported_execution_obligation")
          }
        DedupeTopTie(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.Dedupe,
            ) {
            return Some("unsupported_execution_obligation")
          }
        RowAssertion(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.Assertion,
            ) {
            return Some("unsupported_execution_obligation")
          }
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
