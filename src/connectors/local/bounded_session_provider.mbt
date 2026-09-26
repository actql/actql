///|
/// One cumulative poll of a bounded execution session, before conversion to
/// the per-advance deltas the managed driver consumes.
priv enum BoundedSessionPoll {
  SessionContinue(Int64, Int64)
  SessionComplete(@execution.CompletedOutput, Int64, Int64)
  SessionFailed(@connector.FixedComputeIssue, Int64, Int64)
  SessionStopped(Int64, Int64)
}

///|
/// Adapt a bounded session whose polls report cumulative progress and work.
/// A non-monotonic report fails the attempt; the first terminal poll ends
/// advancement, and cleanup is idempotent once it has reclaimed the session.
fn bounded_session_execution(
  advance : (Int) -> Result[BoundedSessionPoll, @connector.FixedComputeIssue],
  cancel : () -> Bool,
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue],
) -> ManagedProviderExecution {
  let terminated = Ref(false)
  let reclaimed = Ref(false)
  let progress = Ref(0L)
  let work = Ref(0L)
  managed_provider_execution(
    quantum => {
      if quantum <= 0 || terminated.val {
        return Err(@connector.InvalidLimits)
      }
      let poll = match advance(quantum) {
        Ok(value) => value
        Err(issue) => {
          terminated.val = true
          return Ok(managed_provider_failed(issue, 0L, 0L))
        }
      }
      let (next_progress, next_work, terminal) = match poll {
        SessionContinue(progress, work) => (progress, work, false)
        SessionComplete(_, progress, work)
        | SessionFailed(_, progress, work)
        | SessionStopped(progress, work) => (progress, work, true)
      }
      if next_progress < progress.val || next_work < work.val {
        terminated.val = true
        return Ok(
          managed_provider_failed(
            @connector.Execution(@execution.InputSet),
            0L,
            0L,
          ),
        )
      }
      let progress_delta = next_progress - progress.val
      let work_delta = next_work - work.val
      progress.val = next_progress
      work.val = next_work
      if terminal {
        terminated.val = true
      }
      match poll {
        SessionContinue(_, _) =>
          Ok(managed_provider_continue(progress_delta, work_delta))
        SessionComplete(output, _, _) =>
          Ok(managed_provider_complete(output, progress_delta, work_delta))
        SessionFailed(issue, _, _) =>
          Ok(managed_provider_failed(issue, progress_delta, work_delta))
        SessionStopped(_, _) =>
          Ok(managed_provider_stopped_poll(progress_delta, work_delta))
      }
    },
    cancel,
    fn() { terminated.val },
    fn() {
      if !terminated.val {
        return Ok(false)
      }
      if reclaimed.val {
        return Ok(true)
      }
      match cleanup() {
        Ok(true) => {
          reclaimed.val = true
          Ok(true)
        }
        Ok(false) => Ok(false)
        Err(issue) => Err(issue)
      }
    },
  )
}
