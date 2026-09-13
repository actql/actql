///|
/// Trusted application preparation. No connection, source grant or SQL string
/// is accepted; the selected candidate already owns its fixed producer input.
struct ComputeHostConfiguration {
  choice : @planning.FixedComputeChoice
  prepared : @planning.PreparedCompute[@duckdb.FixedCompute]
  generated : @execution.GeneratedSequence
  limits : @planning.DuckDBComputeLimits
  transport : @duckdb.TransportColumnLimits
}

///|
pub fn configure_compute_host(
  choice : @planning.FixedComputeChoice,
  prepared : @planning.PreparedCompute[@duckdb.FixedCompute],
  generated : @execution.GeneratedSequence,
  limits : @planning.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
) -> ComputeHostConfiguration {
  { choice, prepared, generated, limits, transport, }
}

///|
pub fn start_configured_compute_host(
  setup : ComputeHostConfiguration,
  verify : (@planning.DuckDBComputeAttempt) -> Bool,
) -> Result[@planning.DuckDBComputeAttempt, @planning.DuckDBComputeIssue] {
  @planning.start_duckdb_compute_attempt(
    setup.choice,
    setup.prepared,
    setup.generated,
    setup.limits,
    verify,
  )
}

///|
pub fn configured_compute_transport(
  setup : ComputeHostConfiguration,
) -> @duckdb.TransportColumnLimits {
  setup.transport
}
