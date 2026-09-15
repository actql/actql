///|
pub fn duckdb_dispatch_registration(
  installed : DuckDBDispatchModule,
) -> @connector.CapabilityRegistration {
  installed.registration
}

///|
/// The connector, rather than composition, pairs preparation and proposal for
/// its exact installed module. These callbacks do not execute transport.
pub fn[E] duckdb_compute_contribution(
  installed : DuckDBDispatchModule,
  dispatch_issue : (DuckDBDispatchIssue) -> E,
  estimate_issue : (DuckDBEstimateIssue) -> E,
) -> @host.ComputeContribution[Unit, E] {
  {
    prepare: fn(_context, task, revision, request) {
      prepare_duckdb_dispatch(installed, task, revision, request).map_err(
        dispatch_issue,
      )
    },
    propose: fn(_context, task, quantities) {
      estimate_duckdb_installed_offers(installed, task, quantities).map_err(
        estimate_issue,
      )
    },
  }
}

///|
/// Realization labels and static diagnostics belong to this connector. The
/// common Host displays them without interpreting provider-specific reasons.
pub fn duckdb_dispatch_exclusions(
  installed : DuckDBDispatchModule,
) -> Array[(Int, String, String)] {
  let excluded = []
  for index in 0..<installed.sequences.length() {
    if duckdb_dispatch_rejection(installed, index + 1) is Some(reason) {
      excluded.push(
        (
          index + 1,
          @connector.capability_description(installed.registration).name,
          reason,
        ),
      )
    }
  }
  if duckdb_resident_estimates_installed(installed) {
    for index in 0..<installed.sequences.length() {
      if duckdb_dispatch_rejection(installed, index + 1, resident=true)
        is Some(reason) {
        excluded.push((index + 1, "duckdb-resident", reason))
      }
    }
  }
  excluded
}
