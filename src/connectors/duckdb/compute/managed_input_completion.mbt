///|
/// Managed-input realization with finite count/scalar-comparison demand.
/// Compilation alone never qualifies for this completion port.
/// Host-installed callbacks attest the exact native operation and independently
/// admit policy, demanded identities, pin/use rights and resource settlement.
struct ManagedInputDuckDBCompletion[T] {
  values : @execution.ManagedOutputValues
  port : @execution.ManagedCompletionPort[
    (@execution.ManagedOutputValueReceipt, @execution.ManagedRetainedOutput[T]),
    T,
  ]
  state : Ref[Int]
  authorize : () -> Bool
  input_available : () -> Bool
  demand_issue : Ref[@duckdb.NativeDemandIssue?]
  demand_usage : Ref[@duckdb.FixedComputeDemandUsage?]
}

///|
pub fn[T] prepare_managed_input_duckdb_completion(
  query : @duckdb.ManagedFixedQuery[T],
  generated : @execution.CompletionPreparation,
  profile : @execution.ManagedExecutionProfile,
  limits : DuckDBComputeLimits,
  max_rows : Int,
  max_value_bytes : Int,
  authorize : () -> Bool,
  transport_matches : (@execution.ManagedOutputValueReceipt) -> Bool,
) -> Result[ManagedInputDuckDBCompletion[T], DuckDBComputeIssue] {
  let inputs = @duckdb.managed_fixed_query_inputs(query)
  if !physical_equal(
      @execution.completion_preparation_owner(generated),
      @duckdb.managed_fixed_query_owner(query),
    ) ||
    !@duckdb.managed_fixed_query_matches_inputs(query, inputs) {
    return Err(ForeignPreparation)
  }
  if !authorize() || !@duckdb.managed_fixed_query_matches_inputs(query, inputs) {
    return Err(InvalidState)
  }
  let measurement = match
    @execution.prepare_reused_managed_producer_measurement(
      inputs,
      @duckdb.managed_fixed_query_target(query),
      max_rows~,
      max_value_bytes~,
      limits.values,
      limits.metadata_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Guard(issue))
  }
  let values = match
    @execution.prepare_reused_managed_output_values(
      measurement,
      limits.retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ManagedValues(Values(issue)))
  }
  let demand = match
    @duckdb.prepare_managed_query_demand(query, max_value_bytes, limits.demand) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_managed_output_values(values) |> ignore
      return Err(Demand(issue))
    }
  }
  // 0 prepared, 1 completing, 2 completed, 3 cancelled/failed.
  let state = Ref(0)
  let demand_issue = Ref(None)
  let demand_usage = Ref(None)
  let port = match
    @execution.prepare_managed_completion_port(
      profile,
      generated,
      @duckdb.managed_fixed_query_target(query),
      limits.completion_entries,
      limits.completion_name_bytes,
      fn(
        proof : (
          @execution.ManagedOutputValueReceipt,
          @execution.ManagedRetainedOutput[T],
        ),
      ) {
        let (receipt, material) = proof
        if state.val != 1 ||
          !@execution.managed_output_value_managed_measurement_matches(
            receipt, measurement,
          ) ||
          !@execution.managed_retained_output_matches(material, receipt) ||
          !authorize() ||
          state.val != 1 ||
          !transport_matches(receipt) ||
          state.val != 1 ||
          !@duckdb.managed_fixed_query_matches_inputs(query, inputs) {
          return None
        }
        match @duckdb.finish_managed_query_demand(demand, query, receipt) {
          Err(issue) => {
            demand_issue.val = Some(issue)
            return None
          }
          Ok(usage) => demand_usage.val = Some(usage)
        }
        Some(material)
      },
      managed_inputs=inputs,
    ) {
    Ok(port) => port
    Err(issue) => {
      @execution.cancel_managed_output_values(values) |> ignore
      return Err(Completion(issue))
    }
  }
  Ok({
    values,
    port,
    state,
    authorize,
    demand_issue,
    demand_usage,
    input_available: fn() {
      @duckdb.managed_fixed_query_matches_inputs(query, inputs)
    },
  })
}

///|
pub fn[T] managed_input_duckdb_demand_usage(
  completion : ManagedInputDuckDBCompletion[T],
) -> @duckdb.FixedComputeDemandUsage? {
  if completion.state.val == 2 {
    completion.demand_usage.val
  } else {
    None
  }
}

///|
pub fn[T] managed_input_duckdb_output_values(
  completion : ManagedInputDuckDBCompletion[T],
) -> @execution.ManagedOutputValues {
  completion.values
}

///|
pub fn[T] cancel_managed_input_duckdb_completion(
  completion : ManagedInputDuckDBCompletion[T],
) -> Bool {
  if completion.state.val == 2 || completion.state.val == 3 {
    return false
  }
  completion.state.val = 3
  @execution.cancel_managed_output_values(completion.values) |> ignore
  @execution.cancel_managed_completion_port(completion.port) |> ignore
  true
}

///|
pub fn[T] complete_managed_input_duckdb(
  completion : ManagedInputDuckDBCompletion[T],
  receipt : @execution.ManagedOutputValueReceipt,
  material : @execution.ManagedRetainedOutput[T],
) -> Result[@execution.ManagedCompletedOutput[T], DuckDBComputeIssue] {
  if completion.state.val != 0 {
    return Err(InvalidState)
  }
  completion.state.val = 1
  let result = @execution.complete_managed_output(
    completion.port,
    (receipt, material),
  )
  match result {
    Ok(output) => {
      if completion.state.val != 1 ||
        !(completion.authorize)() ||
        completion.state.val != 1 ||
        !@execution.managed_completed_output_available(output) ||
        !(completion.input_available)() ||
        completion.state.val != 1 {
        cancel_managed_input_duckdb_completion(completion) |> ignore
        return Err(Completion(Unverified))
      }
      completion.state.val = 2
      Ok(output)
    }
    Err(issue) => {
      cancel_managed_input_duckdb_completion(completion) |> ignore
      match completion.demand_issue.val {
        Some(demand) => Err(Demand(demand))
        None => Err(Completion(issue))
      }
    }
  }
}
