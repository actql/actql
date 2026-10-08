///|
/// A bounded projection key for an already verified Run observation. This is
/// not an execution identity, transition permission, or terminal-state check.
/// Observation time is deliberately absent: polling does not create a fact.
pub fn run_observation_key(
  outcome : String,
  revision : Int64,
  cleanup_pending : Bool?,
  physical_stop : Bool?,
) -> String? {
  let status : RunOutcomeStatus = match outcome {
    "preparing" => Preparing
    "running" => Running
    "waiting_checkpoint" => WaitingCheckpoint
    "resuming" => Resuming
    "needs_reconciliation" => NeedsReconciliation
    "succeeded" => Succeeded
    "failed" => Failed
    "cancelled" => Cancelled
    _ => return None
  }
  if revision < 0L || revision > 9007199254740991L {
    return None
  }
  let name = match status {
    Preparing => "preparing"
    Running => "running"
    WaitingCheckpoint => "waiting_checkpoint"
    Resuming => "resuming"
    NeedsReconciliation => "needs_reconciliation"
    Succeeded => "succeeded"
    Failed => "failed"
    Cancelled => "cancelled"
  }
  let cleanup = match cleanup_pending {
    None => "?"
    Some(false) => "0"
    Some(true) => "1"
  }
  let stopped = match physical_stop {
    None => "?"
    Some(false) => "0"
    Some(true) => "1"
  }
  Some(name + ";" + revision.to_string() + ";" + cleanup + ";" + stopped)
}
