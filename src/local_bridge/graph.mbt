///|
struct RowsToGraphExecution {
  session : @bounded.Session[
    GraphConstructionState,
    @graph.Completed,
    GraphBridgeIssue,
  ]
  mut token : @bounded.Token?
}

///|
pub enum RowsToGraphPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@graph.Completed, progress~ : Int64, work~ : Int64)
  Failed(GraphBridgeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum GraphBridgeIssue {
  InvalidGraphKernel
  GraphInputUnavailable
  InvalidGraphRecord(Int)
  GraphWorkspaceLimit
  GraphControlWorkLimit
  GraphRelationOutput(@execution.CaptureIssue)
  GraphCompletion(@execution.TrustedOutputIssue)
  GraphExecution(@bounded.Issue)
  GraphSnapshot(@snapshot.Issue)
  GraphSnapshotOutput(@graph.Issue)
} derive(Eq, Debug)

///|
fn graph_checked_cell(
  input : @execution.ProducerRead,
  row : Int,
  column : Int,
  limits : @value.Limits,
) -> @value.CheckedValue? {
  @execution.producer_read_checked_cell(input, row, column, limits)
}

///|
/// The common constructor accepts only the admitted definition-scoped contract.
/// Historical endpoint-tuple sequences are not executable through this entry.
pub fn start_rows_to_graph(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@execution.ProducerRead],
  limits : @graph_storage.Limits,
  storage_bytes : Int64,
  max_workspace_slots : Int,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[RowsToGraphExecution, GraphBridgeIssue] {
  start_rows_to_property_graph(
    control,
    sequence,
    step,
    inputs,
    limits,
    storage_bytes,
    max_workspace_slots,
    available,
    control_work_limit~,
  )
}

///|
pub fn advance_rows_to_graph(
  value : RowsToGraphExecution,
  quantum : Int,
) -> Result[RowsToGraphPoll, GraphBridgeIssue] {
  guard value.token is Some(token) else {
    return Err(GraphExecution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(GraphExecution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(Complete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_rows_to_graph(
  value : RowsToGraphExecution,
) -> Result[Bool, GraphBridgeIssue] {
  @bounded.cleanup(value.session).map_err(issue => GraphExecution(issue))
}

///|
pub fn rows_to_graph_cleanup_pending(value : RowsToGraphExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}
