///|
struct TraverseExecution {
  inner : ReachExecution
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
} derive(Eq, Debug)

///|
/// Start the homogeneous, literal-singleton, node-emitting traversal kernel.
/// Other checked traversal forms remain unsupported until their exact typed
/// selector, hop, and path contracts are implemented.
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
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphTraverseStep(prepared)) &&
    !@lower.graph_traverse_patterned(prepared) &&
    !@lower.graph_traverse_emits_paths(prepared) &&
    @lower.graph_traverse_bounds(prepared) is Some((minimum, maximum)) &&
    minimum <= 2147483647L &&
    maximum <= 2147483647L &&
    @lower.graph_traverse_start_id_count(prepared) == 1 &&
    @lower.graph_traverse_start_id_at(prepared, 0) is Some(start) &&
    @lower.graph_traverse_start_predicate(prepared) is None &&
    @lower.graph_traverse_start_relation_field(prepared) is None &&
    @lower.graph_traverse_hop_count(prepared) == 1 &&
    @lower.graph_traverse_hop_direction(prepared, 0) is Some(direction) &&
    @lower.graph_traverse_hop_type_count(prepared, 0) is None &&
    @lower.graph_traverse_hop_edge_predicate(prepared, 0) is None &&
    @lower.graph_traverse_hop_node_predicate(prepared, 0) is None &&
    @graph.producer_read_storage(input) is Some(source) else {
    return Err(UnsupportedTraverseKernel)
  }
  let max_rows = match @lower.graph_traverse_output_guard(prepared) {
    Some(limit) if limit < max_rows.to_int64() => limit.to_int()
    _ => max_rows
  }
  start_reach_state(
    control,
    preparation,
    sequence,
    step,
    input,
    source,
    @lower.graph_traverse_output_schema(prepared),
    start,
    direction,
    minimum.to_int(),
    maximum.to_int(),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
  )
  .map(inner => ({ inner, } : TraverseExecution))
  .map_err(issue => TraverseReachIssue(issue))
}

///|
pub fn advance_traverse(
  value : TraverseExecution,
  quantum : Int,
) -> Result[TraversePoll, TraverseIssue] {
  advance_reach(value.inner, quantum)
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
}

///|
pub fn traverse_stopped(value : TraverseExecution) -> Bool {
  reach_stopped(value.inner)
}

///|
pub fn traverse_cleanup_pending(value : TraverseExecution) -> Bool {
  reach_cleanup_pending(value.inner)
}

///|
pub fn cleanup_traverse(
  value : TraverseExecution,
) -> Result[Bool, TraverseIssue] {
  cleanup_reach(value.inner).map_err(issue => TraverseReachIssue(issue))
}
