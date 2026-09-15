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
) -> Result[CapturedDuckDBTask, RunIssue] {
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
  guard @duckdb_compute.duckdb_task_retention_capacity(limits)
    is Some(retention) &&
    @duckdb_compute.duckdb_task_scratch_capacity(limits, transport)
    is Some(scratch) &&
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
      @resources.shared_capacity_usage(read.environment.capacity).capacity
    }
  }
  let bound = @connector.bind_prepared_execution(
    choice,
    prepared,
    {
      transfer_bytes,
      retained_bytes: retention,
      scratch_bytes: scratch,
      execution_bytes: execution,
    },
    @connector.fixed_compute_choice_payload(choice, prepared).bind(compute => {
      @duckdb.fixed_compute_join_output_ceiling(compute).map(value => {
        (0, value.to_int64())
      })
    }),
    fn(_compute) {
      let resident_output = match resident {
        None => None
        Some(read) => {
          guard @connector.fixed_compute_choice_payload(choice, prepared)
            is Some(compute) else {
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
            Err(issue) => return Err(issue)
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
          let pending_output = Ref(resident_output)
          let hooks : @connector.ExecutionOperations[RunIssue, TaskPublication] = {
            cancel: fn() {
              @duckdb_compute.abort_duckdb_compute_attempt(attempt)
            },
            dispose: fn() {
              @duckdb_compute.close_duckdb_compute_attempt(attempt)
            },
            settled: fn() {
              if resident is Some(read) {
                return_resident_inputs(read) |> ignore
              }
            },
            released: fn() { pending_output.val = None },
            ready: fn() {
              if pending_output.val is Some(pending) &&
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
            publish: fn(publication) {
              match pending_output.val {
                Some(pending) =>
                  publish_resident_output(run, task, pending, publication)
                None => Ok(())
              }
            },
          }
          Ok(((attempt, pending_output), hooks))
        }
        Err(issue) => {
          // No native work has started: only synchronous admission failed.
          if resident_output is Some(output) {
            @resources.retire_shared_capacity(output.allocation)
            @resources.release_shared_capacity(output.allocation) |> ignore
          }
          fail_captured_task(run, task, DuckDB(issue))
          Err(DuckDB(issue))
        }
      }
    },
  )
  let bound = match bound {
    Ok(value) => value
    Err(issue) => return Err(Compute(issue))
  }
  let started = match resident {
    None => start_captured_execution(run, task, bound)
    Some(_) => start_task_execution(run, task, bound, database)
  }
  match started {
    Err(issue) => Err(issue)
    Ok(((attempt, resident_output), execution)) =>
      Ok({ attempt, execution, resident_output, })
  }
}
