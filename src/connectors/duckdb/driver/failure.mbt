///|
/// Concrete diagnostics cross the common DAG only as Error. They are failure
/// data, never execution authority or a signal for provider-specific fallback.
pub suberror DuckDBFailure {
  Compute(@compute.DuckDBComputeIssue)
  Preparation(@duckdb.NativeQueryIssue)
}

///|
pub fn compute_failure(
  issue : @compute.DuckDBComputeIssue,
) -> @strategy.RunIssue {
  Implementation(DuckDBFailure::Compute(issue))
}

///|
pub fn preparation_failure(
  issue : @duckdb.NativeQueryIssue,
) -> @strategy.RunIssue {
  Implementation(DuckDBFailure::Preparation(issue))
}

///|
pub fn duckdb_compute_failure(
  issue : @strategy.RunIssue,
) -> @compute.DuckDBComputeIssue? {
  guard issue is Implementation(error) else { return None }
  try {
    raise error
  } catch {
    DuckDBFailure::Compute(issue) => Some(issue)
    _ => None
  }
}
