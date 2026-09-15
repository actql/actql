///|
/// Trusted Host wiring only. The standard Node entry constructs the transport
/// verifier internally. Choice freezes before any temporary DB or import work.
pub fn start_captured_duckdb_task(
  run : CapturedDAG,
  task : Int,
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@duckdb.FixedCompute],
  generated : @execution.GeneratedSequence,
  limits : @duckdb_compute.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
  transfer_bytes : Int64,
  native_execution_bytes : Int64,
  verify : (@duckdb_compute.DuckDBComputeAttempt) -> Bool,
  resident? : ResidentInputs,
) -> Result[@duckdb_compute.DuckDBComputeAttempt, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  let selected_profile = run.strategy.bind(revision => {
    strategy_resident_profile(revision, task)
  })
  match (selected_profile, resident) {
    (None, None) => ()
    (Some(selected), Some(read)) => {
      guard read.environment.profile is Some(actual) &&
        physical_equal(selected, actual) else {
        return Err(ForeignCandidate)
      }
    }
    _ => return Err(ForeignCandidate)
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  if !strategy_candidate_matches(
      run,
      task,
      @connector.prepared_compute_candidate(prepared),
    ) {
    return Err(ForeignCandidate)
  }
  guard captured_request_inputs_match(run, task, request) else {
    return Err(ForeignCandidate)
  }
  if captured_task_join_output_limit(run, task) is Some(required) {
    guard @connector.fixed_compute_choice_payload(choice, prepared)
      is Some(compute) &&
      @duckdb.fixed_compute_join_output_ceiling(compute) is Some(actual) &&
      actual.to_int64() <= required else {
      return Err(ForeignCandidate)
    }
  }
  guard duckdb_task_retention_capacity(limits) is Some(retention) &&
    duckdb_task_scratch_capacity(limits, transport) is Some(scratch) &&
    transfer_bytes > 0L &&
    native_execution_bytes > 0L &&
    native_execution_bytes <= 9223372036854775807L - scratch else {
    return Err(Physical(InvalidLimits))
  }
  let execution = native_execution_bytes + scratch
  let database = match resident {
    None => 0L
    Some(read) => {
      guard @connector.fixed_compute_choice_payload(choice, prepared)
        is Some(compute) &&
        resident_inputs_match(run, read, task, compute) else {
        return Err(ForeignCandidate)
      }
      read.environment.capacity.capacity
    }
  }
  if execution > 9223372036854775807L - database {
    return Err(Physical(InvalidLimits))
  }
  if strategy_task_envelope(run, task) is Some(capacity) &&
    (
      transfer_bytes > capacity.transfer_bytes ||
      retention > capacity.retained_bytes ||
      execution + database > capacity.execution_bytes
    ) {
    return Err(Physical(InvalidCharge))
  }
  // This boundary creates its own initial reservation for the exact run/task,
  // current selection and configuration; caller-owned tokens cannot be reused.
  let reservation = match
    @resources.reserve_attempt(run.ledger, transfer_bytes, retention, execution) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let resident_output = match resident {
    None => None
    Some(read) => {
      guard @connector.fixed_compute_choice_payload(choice, prepared)
        is Some(compute) else {
        @resources.settle_reservation(run.ledger, reservation) |> ignore
        return Err(ForeignCandidate)
      }
      match
        prepare_resident_output(
          run,
          read.environment,
          @duckdb.fixed_compute_query(compute),
          retention,
          limits,
          transport.max_bytes,
        ) {
        Ok(value) => Some(value)
        Err(issue) => {
          @resources.settle_reservation(run.ledger, reservation) |> ignore
          return Err(issue)
        }
      }
    }
  }
  match
    @duckdb_compute.start_duckdb_compute_attempt(
      choice, prepared, generated, limits, verify,
    ) {
    Ok(attempt) => {
      if resident is Some(inputs) {
        inputs.claimed = true
      }
      let execution : TaskExecution = {
        task,
        reservation,
        retention,
        scratch,
        cancel: fn() { @duckdb_compute.abort_duckdb_compute_attempt(attempt) },
        dispose: fn() { @duckdb_compute.close_duckdb_compute_attempt(attempt) },
        settled: fn() {
          if resident is Some(read) {
            return_resident_inputs(read) |> ignore
          }
        },
        released: fn() { run.native_resources[task] = None },
        ready: fn() {
          if resident_output is Some(pending) &&
            (
              !pending.committed ||
              !resident_environment_available(run, pending.environment)
            ) {
            Err(NotReady)
          } else {
            Ok(())
          }
        },
        finish: fn() {
          match @duckdb_compute.complete_duckdb_compute_attempt(attempt) {
            Err(issue) => Err(DuckDB(issue))
            Ok(output) => Ok(output)
          }
        },
        publish: fn(output) {
          match resident_output {
            Some(pending) => publish_resident_output(run, task, pending, output)
            None => Ok(())
          }
        },
        execution_settled: false,
        disposed: false,
        failed_holding: None,
      }
      run.executions[task] = Some(execution)
      run.native_resources[task] = Some({ attempt, execution, resident_output, })
      run.running = Some((task, execution))
      Ok(attempt)
    }
    Err(issue) => {
      // No native work has started: only synchronous admission failed.
      if resident_output is Some(output) {
        retire_resident_capacity(output.allocation)
        release_resident_capacity(output.allocation) |> ignore
      }
      @resources.settle_reservation(run.ledger, reservation) |> ignore
      fail_captured_task(run, task, DuckDB(issue))
      Err(DuckDB(issue))
    }
  }
}

///|
/// Exact owned attempt only: cannot accept unrelated successful outputs, even
/// from the same checked owner and identical input contents. Existing completion
/// verifies transport, capacity, demand and retention before recording success.
pub fn complete_captured_duckdb_task(
  run : CapturedDAG,
  attempt : @duckdb_compute.DuckDBComputeAttempt,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard native_task_resource(run, attempt) is Some((_, resource)) else {
    return Err(ForeignCandidate)
  }
  complete_task_execution(run, resource.execution)
}
