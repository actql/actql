///|
fn local_estimate_issue(
  issue : @local_driver.LocalEstimateIssue,
) -> DispatchIssue {
  match issue {
    InvalidConfiguration => InvalidConfiguration
    Rate(issue) => dispatch_rate_issue(issue)
    Dispatch(issue) => local_dispatch_issue(issue)
  }
}

///|
fn duckdb_estimate_issue(
  issue : @duckdb_driver.DuckDBEstimateIssue,
) -> DispatchIssue {
  match issue {
    InvalidConfiguration => InvalidConfiguration
    Rate(issue) => dispatch_rate_issue(issue)
    Search(issue) => Search(issue)
  }
}
