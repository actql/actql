///|
priv enum TraverseKernel {
  TraverseNodes(ReachExecution)
  TraversePaths(TraversePathsExecution)
}

///|
struct TraverseExecution {
  kernel : TraverseKernel
}

///|
pub enum TraversePoll {
  TraverseContinue(progress~ : Int64, work~ : Int64)
  TraverseComplete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  TraverseFailed(TraverseIssue, progress~ : Int64, work~ : Int64)
  TraverseStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum TraverseIssue {
  UnsupportedTraverseKernel
  TraverseReachIssue(ReachIssue)
  TraversePathIssue(TraversePathsIssue)
} derive(Eq, Debug)

///|
/// Start a finite node-emitting traversal kernel.
/// Homogeneous bounds and authored hop patterns share the managed lifecycle,
/// while path emission remains a separate unsupported result contract.
pub fn start_traverse(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
) -> Result[TraverseExecution, TraverseIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphTraverseStep(prepared)) else {
    return Err(UnsupportedTraverseKernel)
  }
  let hop_count = @lower.graph_traverse_hop_count(prepared)
  let patterned = @lower.graph_traverse_patterned(prepared)
  let bounds = if patterned {
    Some((hop_count.to_int64(), hop_count.to_int64()))
  } else {
    @lower.graph_traverse_bounds(prepared)
  }
  guard bounds is Some((minimum, maximum)) &&
    minimum <= 2147483647L &&
    maximum <= 2147483647L &&
    (
      @lower.graph_traverse_start_id_count(prepared) > 0 ||
      @lower.graph_traverse_start_relation_field(prepared) is Some(_) ||
      @lower.graph_traverse_start_predicate(prepared) is Some(_)
    ) &&
    hop_count > 0 &&
    @lower.graph_traverse_hop_direction(prepared, 0) is Some(direction) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) &&
    @graph.producer_read_storage(input) is Some(source) else {
    return Err(UnsupportedTraverseKernel)
  }
  for hop in 0..<hop_count {
    guard @lower.graph_traverse_hop_direction(prepared, hop) is Some(_) else {
      return Err(UnsupportedTraverseKernel)
    }
  }
  if @lower.graph_traverse_emits_paths(prepared) {
    return start_traverse_paths(
        control, preparation, sequence, step, input, max_rows, limits, max_workspace_slots,
        max_entries, max_name_bytes, inputs,
      )
      .map(paths => ({ kernel: TraversePaths(paths), } : TraverseExecution))
      .map_err(issue => TraversePathIssue(issue))
  }
  let starts = match
    (
      @lower.graph_traverse_start_relation_field(prepared),
      @lower.graph_traverse_start_predicate(prepared),
    ) {
    (None, None) => TraversalReachStarts(prepared)
    (None, Some(predicate)) => TraversalPredicateStarts(predicate)
    (Some(field), None) => {
      let mut selector = None
      for candidate in inputs {
        if @execution.producer_read_matches_operation_input(
            candidate, owner, step, 1,
          ) {
          selector = Some(candidate)
          break
        }
      }
      guard selector is Some(selector) else {
        return Err(UnsupportedTraverseKernel)
      }
      let schema = @execution.producer_read_schema(selector)
      let mut column = -1
      for index in 0..<@schema.field_count(schema) {
        if @schema.field_at(schema, index).map(value => value.name) ==
          Some(field) {
          column = index
          break
        }
      }
      guard column >= 0 else { return Err(UnsupportedTraverseKernel) }
      TraversalRelationStarts(selector, column)
    }
    _ => return Err(UnsupportedTraverseKernel)
  }
  let max_rows = match @lower.graph_traverse_output_guard(prepared) {
    Some(limit) if limit < max_rows.to_int64() => limit.to_int()
    _ => max_rows
  }
  let edge_filter = if patterned {
    AllReachEdges
  } else {
    match @lower.graph_traverse_hop_type_count(prepared, 0) {
      None => AllReachEdges
      Some(_) => TraversalReachEdgeTypes(prepared, 0)
    }
  }
  start_reach_state(
    control,
    preparation,
    sequence,
    step,
    input,
    source,
    @lower.graph_traverse_output_schema(prepared),
    starts,
    if patterned {
      Some(prepared)
    } else {
      None
    },
    direction,
    edge_filter,
    @lower.graph_traverse_hop_edge_predicate(prepared, 0),
    @lower.graph_traverse_hop_node_predicate(prepared, 0),
    minimum.to_int(),
    maximum.to_int(),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
  )
  .map(inner => ({ kernel: TraverseNodes(inner), } : TraverseExecution))
  .map_err(issue => TraverseReachIssue(issue))
}

///|
pub fn advance_traverse(
  value : TraverseExecution,
  quantum : Int,
) -> Result[TraversePoll, TraverseIssue] {
  match value.kernel {
    TraverseNodes(inner) =>
      advance_reach(inner, quantum)
      .map(poll => {
        match poll {
          ReachContinue(progress~, work~) => TraverseContinue(progress~, work~)
          ReachComplete(output, progress~, work~) =>
            TraverseComplete(output, progress~, work~)
          ReachFailed(issue, progress~, work~) =>
            TraverseFailed(TraverseReachIssue(issue), progress~, work~)
          ReachStopped(reason, progress~, work~) =>
            TraverseStopped(reason, progress~, work~)
        }
      })
      .map_err(issue => TraverseReachIssue(issue))
    TraversePaths(paths) =>
      advance_traverse_paths(paths, quantum)
      .map(poll => {
        match poll {
          TraversePathsContinue(progress~, work~) =>
            TraverseContinue(progress~, work~)
          TraversePathsComplete(output, progress~, work~) =>
            TraverseComplete(output, progress~, work~)
          TraversePathsFailed(issue, progress~, work~) =>
            TraverseFailed(TraversePathIssue(issue), progress~, work~)
          TraversePathsStopped(reason, progress~, work~) =>
            TraverseStopped(reason, progress~, work~)
        }
      })
      .map_err(issue => TraversePathIssue(issue))
  }
}

///|
pub fn traverse_stopped(value : TraverseExecution) -> Bool {
  match value.kernel {
    TraverseNodes(inner) => reach_stopped(inner)
    TraversePaths(paths) => traverse_paths_stopped(paths)
  }
}

///|
pub fn traverse_cleanup_pending(value : TraverseExecution) -> Bool {
  match value.kernel {
    TraverseNodes(inner) => reach_cleanup_pending(inner)
    TraversePaths(paths) => traverse_paths_cleanup_pending(paths)
  }
}

///|
pub fn traverse_private_entry_count(value : TraverseExecution) -> Int {
  match value.kernel {
    TraverseNodes(_) => 0
    TraversePaths(paths) => traverse_paths_private_entry_count(paths)
  }
}

///|
pub fn traverse_value_item_attempts(value : TraverseExecution) -> Int {
  match value.kernel {
    TraverseNodes(_) => 0
    TraversePaths(paths) => traverse_paths_value_item_attempts(paths)
  }
}

///|
pub fn cleanup_traverse(
  value : TraverseExecution,
) -> Result[Bool, TraverseIssue] {
  match value.kernel {
    TraverseNodes(inner) =>
      cleanup_reach(inner).map_err(issue => TraverseReachIssue(issue))
    TraversePaths(paths) =>
      cleanup_traverse_paths(paths).map_err(issue => TraversePathIssue(issue))
  }
}
