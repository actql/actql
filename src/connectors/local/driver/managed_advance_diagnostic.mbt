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
        @execution.Capture(
          step,
          @execution.CaptureWorkRefusal(limit, remaining)
        )
      )
    ) if step >= 0 && limit >= 0 && remaining >= 0 && remaining <= limit =>
      Some([step, limit])
    Configuration(
      @connector.Execution(
        @execution.Capture(step, @execution.CaptureWorkLimit(limit))
      )
    ) if step >= 0 && limit >= 0 => Some([step, limit])
    _ => None
  }
}

///|
/// Project only the exact original physical quota constructor, never a
/// generic configuration, row, capture, current or cleanup refusal.
pub fn local_managed_failure_resource_dimension(
  issue : LocalDispatchIssue,
) -> String? {
  match issue {
    ExecutionCapacityRefusal(@resources.RetentionLimit, _, _, _) =>
      Some("retained_bytes")
    ExecutionCapacityRefusal(@resources.ExecutionLimit, _, _, _) =>
      Some("execution_bytes")
    Execution(@strategy.Physical(@resources.RetentionLimit)) =>
      Some("retained_bytes")
    Execution(@strategy.Physical(@resources.ExecutionLimit)) =>
      Some("execution_bytes")
    _ => None
  }
}

///|
/// Closed diagnostic quantities from this original failed reserve/probe.
/// The Bool distinguishes exact demand from a proved lower bound. All memory
/// quantities are logical bytes; work is the original UTF8 probe's work unit.
pub fn local_managed_failure_budget(
  issue : LocalDispatchIssue,
) -> (String, Bool, Int64, Int64, Int64)? {
  match issue {
    ExecutionCapacityRefusal(original, needed, available, policy) if needed >
      available &&
      available >= 0L &&
      policy >= available => {
      let dimension = match original {
        @resources.RetentionLimit => "retained_bytes"
        @resources.ExecutionLimit => "execution_bytes"
        _ => return None
      }
      Some((dimension, true, needed, available, policy))
    }
    Configuration(
      @connector.Execution(
        @execution.Capture(_, @execution.CaptureWorkRefusal(policy, available))
      )
    ) if policy >= 0 && available >= 0 && available <= policy =>
      Some(
        (
          "value_capture_work",
          false,
          available.to_int64() + 1L,
          available.to_int64(),
          policy.to_int64(),
        ),
      )
    _ => None
  }
}
