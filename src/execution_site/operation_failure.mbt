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
