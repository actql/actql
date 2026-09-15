///|
/// Connector-owned compilation/preflight split. The Host sees the bounded work
/// admission requirement, never the physical table names or join compiler plan.
struct DuckDBDispatchPreparation {
  registry : @connector.CapabilityRegistry
  registration : @connector.CapabilityRegistration
  request : @connector.FixedComputeRequest
  work : DispatchPreparationWork
  max_entries : Int
  mut bound : Bool
}

///|
priv enum DispatchPreparationWork {
  Ready(@connector.PreparedCompute[@duckdb.FixedCompute])
  Join(DuckDBJoinPreparation, @execution.FixedJoinValidationLimits, Int)
}

///|
struct DuckDBSelectedCompute {
  choice : @connector.FixedComputeChoice
  candidate : @connector.PreparedCompute[@duckdb.FixedCompute]
}

///|
pub(all) enum DuckDBDispatchIssue {
  Native(DuckDBComputeCandidateIssue)
  Selection(@connector.FixedComputeIssue)
  NotSelected
}

///|
pub fn prepare_duckdb_dispatch_candidate(
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  request : @connector.FixedComputeRequest,
  compilation : @duckdb.NativeQueryLimits,
  validation : @execution.FixedJoinValidationLimits,
  join_ceiling : Int64?,
  max_entries : Int,
) -> Result[DuckDBDispatchPreparation, DuckDBComputeCandidateIssue] {
  let work = match join_ceiling {
    Some(required) => {
      let query = match compile_duckdb_join_candidate(request, compilation) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let maximum = @connector.fixed_compute_request_capacity(request).max_rows
      let ceiling = if required < maximum.to_int64() {
        required.to_int()
      } else {
        maximum
      }
      DispatchPreparationWork::Join(query, validation, ceiling)
    }
    None => {
      let candidate = match
        duckdb_fixed_compute_candidate(
          registration,
          request,
          "owned_input",
          compilation,
          [],
          { transfer_bytes: None, retained_bytes: None, money_units: None, },
          max_entries,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      DispatchPreparationWork::Ready(candidate)
    }
  }
  Ok({ registry, registration, request, work, max_entries, bound: false, })
}

///|
/// The common Host must charge this work before binding scans the fixed inputs.
/// None means this preparation has no join preflight, not an unknown zero cost.
pub fn duckdb_dispatch_preflight_work(
  preparation : DuckDBDispatchPreparation,
) -> Int? {
  match preparation.work {
    Ready(_) => None
    Join(_, validation, _) => Some(validation.max_work)
  }
}

///|
/// Trusted connector/Host wiring after common work admission. Exact request,
/// registry, physical names, limits and compiled join are not replaceable here.
pub fn bind_duckdb_dispatch_candidate(
  preparation : DuckDBDispatchPreparation,
) -> Result[DuckDBSelectedCompute, DuckDBDispatchIssue] {
  if preparation.bound {
    return Err(NotSelected)
  }
  preparation.bound = true
  let candidate = match preparation.work {
    Ready(candidate) => candidate
    Join(query, validation, ceiling) =>
      match
        bind_duckdb_join_candidate(
          preparation.registration,
          query,
          validation,
          ceiling,
          [],
          { transfer_bytes: None, retained_bytes: None, money_units: None, },
          preparation.max_entries,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Native(issue))
      }
  }
  match
    @connector.choose_fixed_compute_candidate(
      preparation.registry,
      preparation.request,
      [@connector.prepared_compute_candidate(candidate)],
      Some([0]),
      preparation.max_entries,
    ) {
    Ok(Proposed(choice)) => Ok({ choice, candidate, })
    Ok(_) => Err(NotSelected)
    Err(issue) => Err(Selection(issue))
  }
}

///|
pub fn duckdb_selected_compute_choice(
  selected : DuckDBSelectedCompute,
) -> @connector.FixedComputeChoice {
  selected.choice
}

///|
pub fn duckdb_selected_compute_candidate(
  selected : DuckDBSelectedCompute,
) -> @connector.PreparedCompute[@duckdb.FixedCompute] {
  selected.candidate
}
