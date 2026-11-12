///|
/// Project the already-retained immutable limit only for this original
/// provider's closed work failure. No new counter or allowance is created.
fn local_managed_provider_failure(
  issue : @connector.FixedComputeIssue,
  initial_work_limit : Int,
) -> LocalDispatchIssue {
  match issue {
    @connector.ControlWorkLimit => ControlWorkLimit(initial_work_limit)
    _ => Configuration(issue)
  }
}

///|
/// Inert diagnosis of one closed original failure. Exhausted slice quantum is
/// not a failure; physical ExecutionLimit is memory and must stay unclassified.
pub fn local_managed_advance_control_work_limit(
  issue : LocalDispatchIssue,
) -> Int? {
  match issue {
    ControlWorkLimit(limit) if limit >= 0 => Some(limit)
    _ => None
  }
}

///|
/// The original value-capture work allowance and Capture step are distinct
/// from the provider control counter. No generic CaptureLimit is classified.
pub fn local_managed_advance_capture_work(
  issue : LocalDispatchIssue,
) -> Array[Int]? {
  match issue {
    Configuration(
      @connector.Execution(
        @execution.Capture(step, @execution.CaptureWorkLimit(limit))
      )
    ) if step >= 0 && limit >= 0 => Some([step, limit])
    _ => None
  }
}
