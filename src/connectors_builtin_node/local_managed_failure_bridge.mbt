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

///|
#export_name("strategyModule_local_ManagedAdvanceResourceDimension")
pub fn local_managed_advance_resource_dimension(
  result : Result[
    @local_driver.LocalManagedAdvance,
    @local_driver.LocalDispatchIssue,
  ],
) -> String? {
  match result {
    Err(issue) => @local_driver.local_managed_failure_resource_dimension(issue)
    _ => None
  }
}

///|
/// Same failed result only; amounts are diagnostic DATA, never capacity.
#export_name("strategyModule_local_ManagedAdvanceBudget")
pub fn local_managed_advance_budget(
  result : Result[
    @local_driver.LocalManagedAdvance,
    @local_driver.LocalDispatchIssue,
  ],
) -> (String, Bool, Int64, Int64, Int64)? {
  match result {
    Err(issue) => @local_driver.local_managed_failure_budget(issue)
    _ => None
  }
}
