///|
struct TraverseExecution {
  kernel : TraversePathsExecution
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
  TraversePathIssue(TraversePathsIssue)
} derive(Eq, Debug)

///|
/// Run only the current keyed path contract. The shared path owner validates
/// the exact input, completion owner, hop bounds and resources before use;
/// node emission must never select the retired homogeneous reach kernel.
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
    @lower.graph_traverse_emits_paths(prepared) else {
    return Err(UnsupportedTraverseKernel)
  }
  start_traverse_paths(
    control, preparation, sequence, step, input, max_rows, limits, max_workspace_slots,
    max_entries, max_name_bytes, inputs,
  )
  .map(paths => ({ kernel: paths, } : TraverseExecution))
  .map_err(issue => TraversePathIssue(issue))
}

///|
/// Use the same bounded path owner for an exact retained Graph handoff.
pub fn start_traverse_view(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  view : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
) -> Result[TraverseExecution, TraverseIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphTraverseStep(prepared)) &&
    @lower.graph_traverse_emits_paths(prepared) &&
    @lifecycle.producer_view_kind(view) == @carrier.GraphKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(view),
      owner,
      step,
      0,
    ) else {
    return Err(UnsupportedTraverseKernel)
  }
  start_traverse_paths_read(
    control,
    preparation,
    sequence,
    step,
    Viewed(view),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
  )
  .map(paths => ({ kernel: paths, } : TraverseExecution))
  .map_err(issue => TraversePathIssue(issue))
}

///|
pub fn advance_traverse(
  value : TraverseExecution,
  quantum : Int,
) -> Result[TraversePoll, TraverseIssue] {
  advance_traverse_paths(value.kernel, quantum)
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

///|
pub fn traverse_stopped(value : TraverseExecution) -> Bool {
  traverse_paths_stopped(value.kernel)
}

///|
pub fn traverse_cleanup_pending(value : TraverseExecution) -> Bool {
  traverse_paths_cleanup_pending(value.kernel)
}

///|
pub fn traverse_private_entry_count(value : TraverseExecution) -> Int {
  traverse_paths_private_entry_count(value.kernel)
}

///|
/// Diagnostic structural reservation, including selected-start overlap.
pub fn traverse_private_workspace_usage(
  value : TraverseExecution,
) -> (Int, Int) {
  traverse_paths_workspace_usage(value.kernel)
}

///|
pub fn traverse_value_item_attempts(value : TraverseExecution) -> Int {
  traverse_paths_value_item_attempts(value.kernel)
}

///|
pub fn cleanup_traverse(
  value : TraverseExecution,
) -> Result[Bool, TraverseIssue] {
  cleanup_traverse_paths(value.kernel).map_err(issue => TraversePathIssue(issue))
}
