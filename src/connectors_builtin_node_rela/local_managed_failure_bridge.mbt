///|
/// Diagnostic DATA from the original managed advance result only. Physical
/// memory, row/byte/workspace bounds and unclassified failures remain distinct.
#export_name("strategyModule_local_ManagedAdvanceFailureKind")
pub fn local_managed_advance_failure_kind(
  result : Result[
    @local_driver.LocalManagedAdvance,
    @local_driver.LocalDispatchIssue,
  ],
) -> String? {
  match result {
    Err(issue) => @local_driver.local_managed_advance_failure_kind(issue)
    _ => None
  }
}
