///|
/// Common progression for a failed Site operation. The adapter observes
/// physical stop and performs settlement; it does not decide when settlement
/// is permitted.
pub(all) enum FailedSiteOperationAction {
  FailedSiteAwaitStop
  FailedSiteSettle
  FailedSiteFinished
} derive(Eq, Debug)

///|
/// Common state for settling one failed Site operation. The adapter reports
/// physical stop and performs the selected settlement operation; it does not
/// own a parallel settlement flag.
struct FailedSiteOperationProgress {
  cleanup_required : Bool
  mut cleanup_stopped : Bool
  mut operation_settled : Bool
}

///|
pub fn begin_failed_site_operation_progress(
  cleanup_required : Bool,
  already_settled : Bool,
) -> FailedSiteOperationProgress {
  {
    cleanup_required,
    cleanup_stopped: false,
    operation_settled: already_settled,
  }
}

///|
pub fn record_failed_site_operation_stop(
  progress : FailedSiteOperationProgress,
) -> Bool {
  if !progress.cleanup_required {
    false
  } else {
    progress.cleanup_stopped = true
    true
  }
}

///|
pub fn record_failed_site_operation_settlement(
  progress : FailedSiteOperationProgress,
) -> Bool {
  if progress.operation_settled ||
    (progress.cleanup_required && !progress.cleanup_stopped) {
    false
  } else {
    progress.operation_settled = true
    true
  }
}

///|
pub fn prepare_failed_site_operation_progress_step(
  progress : FailedSiteOperationProgress,
) -> FailedSiteOperationAction {
  prepare_failed_site_operation_step(
    progress.cleanup_required,
    progress.cleanup_stopped,
    progress.operation_settled,
  )
}

///|
pub fn prepare_failed_site_operation_step(
  cleanup_required : Bool,
  cleanup_stopped : Bool,
  operation_settled : Bool,
) -> FailedSiteOperationAction {
  if operation_settled {
    return FailedSiteFinished
  }
  if cleanup_required && !cleanup_stopped {
    return FailedSiteAwaitStop
  }
  FailedSiteSettle
}

///|
pub fn failed_site_operation_action_code(
  action : FailedSiteOperationAction,
) -> Int {
  match action {
    FailedSiteAwaitStop => 0
    FailedSiteSettle => 1
    FailedSiteFinished => 2
  }
}

///|
/// Common progression for releasing the Site holding of a retained output.
/// The environment owns the physical close operation and reports its observed
/// outcome; only this progression decides when the holding may be released.
pub(all) enum RetainedSiteHoldingAction {
  RetainedSiteStartClose
  RetainedSiteAwaitClose
  RetainedSiteAwaitCleanup
  RetainedSiteReleaseHolding
  RetainedSiteHoldingFinished
  RetainedSiteHoldingInvalid
} derive(Eq, Debug)

///|
/// Common close state shared by every Site holding backed by one physical
/// output owner. The environment reports physical observations into this
/// owner instead of maintaining a parallel set of lifecycle flags.
struct RetainedSiteCloseProgress {
  mut close_started : Bool
  mut close_succeeded : Bool
  mut close_failed : Bool
  mut cleanup_authority : Bool
  mut cleanup_stopped : Bool
}

///|
/// Per-holding release state linked to a shared physical close owner.
struct RetainedSiteHoldingProgress {
  close : RetainedSiteCloseProgress
  mut holding_released : Bool
}

///|
pub(all) enum RetainedSiteCloseAction {
  RetainedSiteCloseStart
  RetainedSiteCloseAwaitPhysical
  RetainedSiteCloseAwaitCleanup
  RetainedSiteCloseFinished
  RetainedSiteCloseInvalid
} derive(Eq, Debug)

///|
pub fn begin_retained_site_close_progress() -> RetainedSiteCloseProgress {
  {
    close_started: false,
    close_succeeded: false,
    close_failed: false,
    cleanup_authority: false,
    cleanup_stopped: false,
  }
}

///|
pub fn begin_retained_site_holding_progress(
  close : RetainedSiteCloseProgress,
) -> RetainedSiteHoldingProgress? {
  if close.close_started {
    None
  } else {
    Some({ close, holding_released: false, })
  }
}

///|
pub fn record_retained_site_close_started(
  progress : RetainedSiteCloseProgress,
) -> Bool {
  if progress.close_started {
    false
  } else {
    progress.close_started = true
    true
  }
}

///|
pub fn record_retained_site_close_succeeded(
  progress : RetainedSiteCloseProgress,
) -> Bool {
  if !progress.close_started || progress.close_failed {
    false
  } else {
    progress.close_succeeded = true
    true
  }
}

///|
pub fn record_retained_site_close_failed(
  progress : RetainedSiteCloseProgress,
) -> Bool {
  if !progress.close_started || progress.close_succeeded {
    false
  } else {
    progress.close_failed = true
    true
  }
}

///|
pub fn record_retained_site_cleanup_authority(
  progress : RetainedSiteCloseProgress,
) -> Bool {
  if !progress.close_started || !progress.close_failed {
    false
  } else {
    progress.cleanup_authority = true
    true
  }
}

///|
pub fn record_retained_site_cleanup_stopped(
  progress : RetainedSiteCloseProgress,
) -> Bool {
  if !progress.cleanup_authority {
    false
  } else {
    progress.cleanup_stopped = true
    true
  }
}

///|
pub fn record_retained_site_holding_released(
  progress : RetainedSiteHoldingProgress,
) -> Bool {
  if progress.holding_released {
    true
  } else if prepare_retained_site_holding_progress_step(progress)
    is RetainedSiteReleaseHolding {
    progress.holding_released = true
    true
  } else {
    false
  }
}

///|
pub fn prepare_retained_site_holding_progress_step(
  progress : RetainedSiteHoldingProgress,
) -> RetainedSiteHoldingAction {
  prepare_retained_site_holding_step(
    progress.close.close_started,
    progress.close.close_succeeded,
    progress.close.close_failed,
    progress.close.cleanup_authority,
    progress.close.cleanup_stopped,
    progress.holding_released,
  )
}

///|
pub fn prepare_retained_site_close_progress_step(
  progress : RetainedSiteCloseProgress,
) -> RetainedSiteCloseAction {
  if (progress.close_succeeded && progress.close_failed) ||
    (progress.cleanup_stopped && !progress.cleanup_authority) ||
    (
      (
        progress.close_succeeded ||
        progress.close_failed ||
        progress.cleanup_authority
      ) &&
      !progress.close_started
    ) {
    return RetainedSiteCloseInvalid
  }
  if !progress.close_started {
    return RetainedSiteCloseStart
  }
  if progress.close_succeeded ||
    (
      progress.close_failed &&
      progress.cleanup_authority &&
      progress.cleanup_stopped
    ) {
    return RetainedSiteCloseFinished
  }
  if progress.close_failed {
    return RetainedSiteCloseAwaitCleanup
  }
  RetainedSiteCloseAwaitPhysical
}

///|
pub fn retained_site_close_action_code(action : RetainedSiteCloseAction) -> Int {
  match action {
    RetainedSiteCloseStart => 0
    RetainedSiteCloseAwaitPhysical => 1
    RetainedSiteCloseAwaitCleanup => 2
    RetainedSiteCloseFinished => 3
    RetainedSiteCloseInvalid => 4
  }
}

///|
pub fn prepare_retained_site_holding_step(
  close_started : Bool,
  close_succeeded : Bool,
  close_failed : Bool,
  cleanup_authority : Bool,
  cleanup_stopped : Bool,
  holding_released : Bool,
) -> RetainedSiteHoldingAction {
  if (close_succeeded && close_failed) ||
    (cleanup_stopped && !cleanup_authority) ||
    ((close_succeeded || close_failed || cleanup_authority) && !close_started) ||
    (holding_released && !close_started) {
    return RetainedSiteHoldingInvalid
  }
  if holding_released {
    return RetainedSiteHoldingFinished
  }
  if !close_started {
    return RetainedSiteStartClose
  }
  if close_succeeded || (close_failed && cleanup_authority && cleanup_stopped) {
    return RetainedSiteReleaseHolding
  }
  if close_failed {
    return RetainedSiteAwaitCleanup
  }
  RetainedSiteAwaitClose
}

///|
pub fn retained_site_holding_action_code(
  action : RetainedSiteHoldingAction,
) -> Int {
  match action {
    RetainedSiteStartClose => 0
    RetainedSiteAwaitClose => 1
    RetainedSiteAwaitCleanup => 2
    RetainedSiteReleaseHolding => 3
    RetainedSiteHoldingFinished => 4
    RetainedSiteHoldingInvalid => 5
  }
}
