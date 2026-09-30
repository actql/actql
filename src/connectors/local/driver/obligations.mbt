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
        JsonPickExecution(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.JsonPick,
            ) {
            return Some("unsupported_execution_obligation")
          }
        WatermarkExecution(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.Watermark,
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
        SeriesExecution(_) =>
          if !@local.local_module_bounded_temporal_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.TimeSeries,
            ) {
            return Some("unsupported_execution_obligation")
          }
        IntervalExecution(_) | IntervalSearch(_) =>
          if !@local.local_module_bounded_temporal_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.IntervalJoin,
            ) {
            return Some("unsupported_execution_obligation")
          }
        AsOfExecution(_) | AsOfSearch(_) =>
          if !@local.local_module_bounded_temporal_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.AsOfJoin,
            ) {
            return Some("unsupported_execution_obligation")
          }
        RankingExecution(_) =>
          if !@local.local_module_bounded_ranking_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
            ) {
            return Some("unsupported_execution_obligation")
          }
        NearestExecution(_) =>
          if !@local.local_module_bounded_nearest_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
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
        ExpansionExecution(_) =>
          if !@local.local_module_bounded_relation_obligation(
              installed.implementation,
              local_task_slot(installed, task),
              requirement.site.step,
              @local.Expansion,
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
/// Every selected expansion must carry its exact checked output envelope.
/// A missing or foreign envelope keeps the task out of retained execution.
fn local_task_expansion_output_ceilings(
  run : @strategy.CapturedDAG,
  task : Int,
) -> Array[(Int, Int64)]? {
  let graph = @strategy.captured_dag_graph(run)
  guard @strategy.graph_task_operation_count(graph, task) is Some(count) else {
    return None
  }
  let expansion_steps : Array[Int] = []
  let ceilings : Array[(Int, Int64)] = []
  for index in 0..<count {
    let requirement = @strategy.graph_task_operation_at(graph, task, index).unwrap()
    if requirement.disposition is ExecutionCheck(ExpansionExecution(check)) {
      let step = requirement.site.step
      match check.rule {
        EmitUnpivotOccurrences | EmitArrayOccurrences =>
          if !expansion_steps.contains(step) {
            expansion_steps.push(step)
          }
        EnforceOutputEnvelope(ceiling) => {
          let maximum = @policy.ceiling_value(ceiling)
          if maximum < 0L || ceilings.any(entry => entry.0 == step) {
            return None
          }
          ceilings.push((step, maximum))
          if !expansion_steps.contains(step) {
            expansion_steps.push(step)
          }
        }
      }
    }
  }
  for step in expansion_steps {
    if !ceilings.any(entry => entry.0 == step) {
      return None
    }
  }
  Some(ceilings)
}

///|
/// A row-only retained-output offer requires the file-capable implementation.
/// A Carrier path can instead retain its typed managed generations, including
/// Relation views produced by a formal Bridge. Policy ineligibility is never
/// overridden by that alternative representation.
fn local_dispatch_offer_supported(
  installed : LocalDispatchModule,
  task : Int,
) -> Bool {
  if installed.estimate_configuration is Some(configuration) &&
    configuration.eligible.get(task - 1) is Some(false) {
    return false
  }
  local_dispatch_rejection(installed, task) is None ||
  (
    @local.local_module_managed_sequence_supported(
      installed.implementation,
      local_task_slot(installed, task),
    ) &&
    (
      installed.output_policy is None ||
      local_dispatch_carrier_path(installed, task)
    )
  )
}

///|
/// The bounded managed route stays selected for every descendant that must
/// consume a managed Carrier or Relation generation from the same path.
/// Checked physical tasks are topologically ordered; index each dependency
/// once, then propagate along predecessors in task order.
fn carrier_path_table_from_edges(
  first : Int,
  own_carrier : Array[Bool],
  edge_count : Int,
  edge_at : (Int) -> (Int, Int),
  scans : (Ref[Int], Ref[Int])?,
) -> Array[Bool] {
  let count = own_carrier.length()
  let predecessors : Array[Array[Int]] = Array::makei(count, _ => [])
  for index in 0..<edge_count {
    let (producer, consumer) = edge_at(index)
    if scans is Some((edge_scans, _)) {
      edge_scans.val += 1
    }
    if consumer >= first &&
      consumer < count &&
      producer >= first &&
      producer < consumer {
      predecessors[consumer].push(producer)
    }
  }
  let paths = Array::make(count, false)
  for task in first..<count {
    let mut carrier = own_carrier[task]
    if !carrier {
      for producer in predecessors[task] {
        if scans is Some((_, predecessor_scans)) {
          predecessor_scans.val += 1
        }
        if paths[producer] {
          carrier = true
          break
        }
      }
    }
    paths[task] = carrier
  }
  paths
}

///|
fn local_dispatch_carrier_path_table(
  run : @strategy.CapturedDAG,
  implementation : @local.LocalComputeModule,
) -> Array[Bool] {
  let graph = @strategy.captured_dag_graph(run)
  let first = @strategy.captured_compute_first_task(run)
  let count = @strategy.graph_task_count(graph)
  let own_carrier = Array::make(count, false)
  for task in first..<count {
    let slot = task - first
    own_carrier[task] = @local.local_module_sequence_outputs_carrier(
        implementation, slot,
      ) ||
      @local.local_module_sequence_contains_carrier_step(implementation, slot) ||
      @local.local_module_sequence_has_carrier_input(implementation, slot)
  }
  carrier_path_table_from_edges(
    first,
    own_carrier,
    @strategy.graph_data_count(graph),
    index => {
      let edge = @strategy.graph_data_at(graph, index).unwrap()
      (edge.producer, edge.consumer)
    },
    None,
  )
}

///|
fn local_dispatch_carrier_path(
  installed : LocalDispatchModule,
  task : Int,
) -> Bool {
  installed.carrier_paths.get(task).unwrap_or(false)
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
