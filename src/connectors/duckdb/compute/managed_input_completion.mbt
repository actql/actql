///|
/// Managed-input count realization. Its direct demand law needs input/output
/// counts, not predicate cells. FilterSelect must use a future measured demand
/// path; compiling such SQL alone never qualifies for this completion port.
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
  let native = @duckdb.managed_fixed_query_query(query)
  let input = @duckdb.managed_fixed_query_input(query)
  guard native is CountGroup(_) else { return Err(ForeignPreparation) }
  if !physical_equal(
      @execution.completion_preparation_owner(generated),
      @duckdb.fixed_query_owner(native),
    ) ||
    !@duckdb.managed_fixed_query_matches(query, input) {
    return Err(ForeignPreparation)
  }
  if !authorize() || !@duckdb.managed_fixed_query_matches(query, input) {
    return Err(InvalidState)
  }
  let measurement = match
    @execution.prepare_reused_managed_producer_measurement(
      [input],
      @duckdb.fixed_query_target(native),
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
  // 0 prepared, 1 completing, 2 completed, 3 cancelled/failed.
  let state = Ref(0)
  let port = match
    @execution.prepare_managed_completion_port(
      profile,
      generated,
      @duckdb.fixed_query_target(native),
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
          !@duckdb.managed_fixed_query_matches(query, input) {
          return None
        }
        Some(material)
      },
      managed_inputs=[input],
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
    input_available: fn() { @duckdb.managed_fixed_query_matches(query, input) },
  })
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
      Err(Completion(issue))
    }
  }
}
