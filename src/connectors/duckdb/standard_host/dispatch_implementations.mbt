///|
fn local_dispatch_issue(
  issue : @local_driver.LocalDispatchIssue,
) -> DispatchIssue {
  match issue {
    Configuration(_) => InvalidConfiguration
    Preparation(Candidate(issue)) => Candidate(issue)
    Preparation(NotSelected) => ForeignSelection
    Preparation(Capacity) => Run(Physical(InvalidLimits))
    Preparation(Execution(issue)) => Run(Compute(issue))
    Preparation(Materializing(Candidate(issue))) => Run(Compute(issue))
    Preparation(Materializing(Capacity)) => Run(Physical(InvalidLimits))
    Preparation(Materializing(State | Import(_) | Export(_))) =>
      InvalidConfiguration
    Dispatch(issue) => dispatch_driver_issue(issue)
    Execution(issue) => Run(issue)
    Search(issue) => Search(issue)
    ManagedValues(_) => InvalidConfiguration
    ManagedCopy(_) => InvalidConfiguration
    ManagedRetention(_) => InvalidConfiguration
    ManagedCompletion(_) => InvalidConfiguration
    // An identity export over the import limits is a resource limit.
    IdentityExport(_) => Run(Physical(InvalidLimits))
  }
}

///|
fn duckdb_dispatch_issue(
  issue : @duckdb_driver.DuckDBDispatchIssue,
) -> DispatchIssue {
  match issue {
    InvalidConfiguration => InvalidConfiguration
    ForeignSelection => ForeignSelection
    Run(issue) => Run(issue)
    Candidate(issue) => Candidate(issue)
    NativeCandidate(issue) => NativeCandidate(issue)
    JoinPreparation(issue) => JoinPreparation(issue)
    Dispatch(issue) => dispatch_driver_issue(issue)
  }
}
