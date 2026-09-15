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
    exclusions: max_entries => {
      duckdb_dispatch_exclusions(installed, max_entries)
    },
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
fn duckdb_dispatch_exclusions(
  installed : DuckDBDispatchModule,
  max_entries : Int,
) -> Array[(Int, String, String)]? {
  if max_entries < 0 {
    return None
  }
  let excluded = []
  for index in 0..<installed.sequences.length() {
    if duckdb_dispatch_rejection(installed, index + 1) is Some(reason) {
      if excluded.length() >= max_entries {
        return None
      }
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
        if excluded.length() >= max_entries {
          return None
        }
        excluded.push((index + 1, "duckdb-resident", reason))
      }
    }
  }
  Some(excluded)
}
