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
