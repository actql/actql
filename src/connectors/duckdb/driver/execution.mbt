///|
/// Concrete transport state belongs to the connector, not the common DAG.
struct CapturedDuckDBTask {
  attempt : @compute.DuckDBComputeAttempt
  execution : @strategy.TaskExecution
}

///|
pub fn captured_duckdb_attempt(
  task : CapturedDuckDBTask,
) -> @compute.DuckDBComputeAttempt {
  task.attempt
}

///|
pub fn captured_duckdb_execution(
  task : CapturedDuckDBTask,
) -> @strategy.TaskExecution {
  task.execution
}

///|
/// Installed connector wiring. Transport I/O starts only after common admission
/// returns the exact task execution. This function itself performs no I/O.
pub fn start_captured_duckdb_task(
  run : @strategy.CapturedDAG,
  task : Int,
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@duckdb.FixedCompute],
  generated : @execution.GeneratedSequence,
  limits : @compute.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
  transfer_bytes : Int64,
  native_execution_bytes : Int64,
  verify : (@compute.DuckDBComputeAttempt) -> Bool,
  resident? : @strategy.ResidentInputs,
) -> Result[CapturedDuckDBTask, @strategy.RunIssue] {
  guard @compute.duckdb_task_retention_capacity(limits) is Some(retention) &&
    @compute.duckdb_task_scratch_capacity(limits, transport) is Some(scratch) &&
    transfer_bytes > 0L &&
    native_execution_bytes > 0L &&
    native_execution_bytes <= 9223372036854775807L - scratch else {
    return Err(Physical(InvalidLimits))
  }
  let resident = match resident {
    None => None
    Some(inputs) =>
      match
        @strategy.prepare_resident_execution(
          run, task, choice, prepared, inputs, limits, transport,
        ) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  let bound = @connector.bind_prepared_execution(
    choice,
    prepared,
    {
      transfer_bytes,
      retained_bytes: retention,
      scratch_bytes: scratch,
      execution_bytes: native_execution_bytes + scratch,
    },
    @connector.fixed_compute_choice_payload(choice, prepared).bind(compute => {
      @duckdb.fixed_compute_join_output_ceiling(compute).map(value => {
        (0, value.to_int64())
      })
    }),
    fn(_payload) {
      match
        @compute.start_duckdb_compute_attempt(
          choice, prepared, generated, limits, verify,
        ) {
        Err(issue) => Err(@strategy.RunIssue::DuckDB(issue))
        Ok(attempt) => {
          let operations : @connector.ExecutionOperations[
            @strategy.RunIssue,
            @strategy.TaskPublication,
          ] = {
            cancel: fn() { @compute.abort_duckdb_compute_attempt(attempt) },
            dispose: fn() { @compute.close_duckdb_compute_attempt(attempt) },
            settled: fn() {  },
            released: fn() {  },
            ready: fn() { Ok(()) },
            finish: fn() {
              match @compute.complete_duckdb_compute_attempt(attempt) {
                Err(issue) => Err(DuckDB(issue))
                Ok(output) => Ok(output)
              }
            },
            publish: fn(_) { Ok(()) },
          }
          Ok((attempt, operations))
        }
      }
    },
  )
  let bound = match bound {
    Ok(value) => value
    Err(issue) => return Err(Compute(issue))
  }
  match @strategy.start_captured_execution(run, task, bound, resident?) {
    Err(issue) => Err(issue)
    Ok((attempt, execution)) => Ok({ attempt, execution, })
  }
}
