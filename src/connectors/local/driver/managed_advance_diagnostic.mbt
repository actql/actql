///|
/// Inert diagnosis of one closed original failure. Exhausted slice quantum is
/// not a failure; physical ExecutionLimit is memory and must stay unclassified.
pub fn local_managed_advance_failure_kind(
  issue : LocalDispatchIssue,
) -> String? {
  match issue {
    Configuration(@connector.ControlWorkLimit) => Some("control_work")
    _ => None
  }
}
