///|
/// Diagnostic DATA from the original managed advance result only. Physical
/// memory, row/byte/workspace bounds and unclassified failures remain distinct.
#export_name("strategyModule_local_ManagedAdvanceControlWorkLimit")
pub fn local_managed_advance_control_work_limit(
  result : Result[
    @local_driver.LocalManagedAdvance,
    @local_driver.LocalDispatchIssue,
  ],
) -> Int? {
  match result {
    Err(issue) => @local_driver.local_managed_advance_control_work_limit(issue)
    _ => None
  }
}

///|
/// Project only this SAME original failed advance's typed Capture work cause.
#export_name("strategyModule_local_ManagedAdvanceCaptureWork")
pub fn local_managed_advance_capture_work(
  result : Result[
    @local_driver.LocalManagedAdvance,
    @local_driver.LocalDispatchIssue,
  ],
) -> Array[Int]? {
  match result {
    Err(issue) => @local_driver.local_managed_advance_capture_work(issue)
    _ => None
  }
}
