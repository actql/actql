///|
/// Install before any offer policy or selection. This realizes independent
/// output as a canonical file, optionally alongside a separately budgeted
/// resident DB copy. Neither representation changes logical identity.
/// file_work_ms includes file writing, sealing and cleanup; unknown stays unknown.
pub fn configure_duckdb_retained_output(
  installed : DuckDBDispatchModule,
  max_file_bytes : Int64,
  file_work_ms : Int64?,
) -> Result[Unit, DuckDBDispatchIssue] {
  if max_file_bytes <= 0L ||
    max_file_bytes > 2147483647L ||
    (file_work_ms is Some(ms) && ms < 0L) ||
    installed.retained_output is Some(_) ||
    installed.output_policy_sealed ||
    installed.estimate_configuration is Some(_) ||
    !installed.resident_estimates.is_empty() ||
    @strategy.strategy_history_count(installed.run) != 0 {
    return Err(InvalidConfiguration)
  }
  installed.retained_output = Some((max_file_bytes, file_work_ms))
  Ok(())
}
