///|
/// Host-installed admission for one selected attempt. The authorization callback
/// covers the admitted profile obligations, demanded identities, use rights and
/// resource settlement; it cannot replace the connector's execution checks.
struct ManagedDuckDBCompletion[T] {
  attempt : DuckDBComputeAttempt
  port : @execution.ManagedCompletionPort[
    (ManagedDuckDBComputeOutput, @execution.ManagedRetainedOutput[T]),
    T,
  ]
  authorize : () -> Bool
  mut consumed : Bool
}

///|
pub fn[T] prepare_managed_duckdb_completion(
  attempt : DuckDBComputeAttempt,
  profile : @execution.ManagedExecutionProfile,
  authorize : () -> Bool,
) -> Result[ManagedDuckDBCompletion[T], DuckDBComputeIssue] {
  if !attempt.live ||
    attempt.completed ||
    attempt.managed ||
    attempt.receiving is Some(_) ||
    !authorize() ||
    !attempt.live ||
    attempt.completed ||
    attempt.managed ||
    attempt.receiving is Some(_) {
    return Err(InvalidState)
  }
  guard duckdb_completed_fixed_inputs(attempt.request) is Some(inputs) else {
    return Err(UnsupportedInputShape)
  }
  let port = match
    @execution.prepare_managed_completion_port(
      profile,
      attempt.generated,
      @duckdb.fixed_query_target(@duckdb.fixed_compute_query(attempt.compute)),
      attempt.limits.completion_entries,
      attempt.limits.completion_name_bytes,
      fn(
        proof : (
          ManagedDuckDBComputeOutput,
          @execution.ManagedRetainedOutput[T],
        ),
      ) {
        let (output, material) = proof
        if !physical_equal(output.attempt, attempt) ||
          !authorize() ||
          !attempt.live {
          return None
        }
        verified_managed_duckdb_compute_material(output, material)
      },
      inputs~,
    ) {
    Ok(port) => port
    Err(issue) => return Err(Completion(issue))
  }
  Ok({ attempt, port, authorize, consumed: false, })
}

///|
pub fn[T] bind_managed_duckdb_completion_attempt(
  completion : ManagedDuckDBCompletion[T],
  attempt : @execution.ManagedExecutionAttempt,
) -> Bool {
  @execution.bind_managed_completion_attempt(completion.port, attempt)
}

///|
pub fn[T] complete_managed_duckdb_compute_attempt(
  completion : ManagedDuckDBCompletion[T],
  output : ManagedDuckDBComputeOutput,
  material : @execution.ManagedRetainedOutput[T],
) -> Result[@execution.ManagedCompletedOutput[T], DuckDBComputeIssue] {
  if completion.consumed {
    return Err(InvalidState)
  }
  completion.consumed = true
  let attempt = completion.attempt
  if !physical_equal(output.attempt, attempt) ||
    !attempt.live ||
    attempt.completed {
    @execution.cancel_managed_completion_port(completion.port) |> ignore
    abort_duckdb_compute_attempt(attempt)
    return Err(InvalidState)
  }
  let result = @execution.complete_managed_output(
    completion.port,
    (output, material),
  )
  match result {
    Ok(completed) => {
      if !attempt.live ||
        attempt.completed ||
        !(completion.authorize)() ||
        !attempt.live ||
        attempt.completed ||
        !@execution.managed_completed_output_available(completed) ||
        !attempt.live ||
        attempt.completed {
        cancel_managed_duckdb_compute_output(output)
        return Err(Completion(Unverified))
      }
      attempt.completed = true
      Ok(completed)
    }
    Err(issue) => {
      cancel_managed_duckdb_compute_output(output)
      Err(Completion(issue))
    }
  }
}
