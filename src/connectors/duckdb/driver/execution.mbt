///|
/// Concrete transport state belongs to the connector, not the common DAG.
struct CapturedDuckDBTask {
  attempt : @compute.DuckDBComputeAttempt
  execution : @strategy.TaskExecution
  cleanup_sql_bytes : Int
  output_plan : Ref[@compute.DuckDBResidentOutput?]
  store : DuckDBResidentStore?
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
  generated : @execution.CompletionPreparation,
  limits : @compute.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
  transfer_bytes : Int64,
  native_execution_bytes : Int64,
  verify : (@compute.DuckDBComputeAttempt) -> Bool,
  resident? : DuckDBResidentInputs,
  retained_storage? : (Int64, () -> Bool),
  auxiliary_retention_bytes? : Int64,
) -> Result[CapturedDuckDBTask, @strategy.RunIssue] {
  let retained_required = retained_storage is Some(_)
  guard (if retained_required {
      @compute.duckdb_stream_retention_capacity(limits)
    } else {
      @compute.duckdb_task_retention_capacity(limits)
    })
    is Some(retention) &&
    (if retained_required {
      @compute.duckdb_stream_scratch_capacity(
        limits,
        transport,
        compute?=@connector.fixed_compute_choice_payload(choice, prepared),
      )
    } else {
      @compute.duckdb_task_scratch_capacity(limits, transport)
    })
    is Some(scratch) &&
    transfer_bytes > 0L &&
    native_execution_bytes > 0L &&
    native_execution_bytes <= 9223372036854775807L - scratch else {
    return Err(Physical(InvalidLimits))
  }
  let storage_bytes = retained_storage.map(value => value.0).unwrap_or(0L)
  let auxiliary_retention_bytes = auxiliary_retention_bytes.unwrap_or(0L)
  if storage_bytes < 0L ||
    auxiliary_retention_bytes < 0L ||
    retention > 9223372036854775807L - storage_bytes ||
    retention + storage_bytes > 9223372036854775807L - auxiliary_retention_bytes {
    return Err(Physical(InvalidLimits))
  }
  let output_plan : Ref[@compute.DuckDBResidentOutput?] = Ref(None)
  let retention_attempt : Ref[@compute.DuckDBComputeAttempt?] = Ref(None)
  let store = resident.map(inputs => inputs.store)
  // A streamed completion's metadata allowance must never stand in for the
  // DB copy. The latter occupies shared environment capacity independently of
  // the file holding charged to this task.
  let copy_retention = if resident is Some(_) {
    match @compute.duckdb_task_retention_capacity(limits) {
      Some(bytes) => bytes
      None => return Err(Physical(InvalidLimits))
    }
  } else {
    retention
  }
  let resident = match resident {
    None => None
    Some(inputs) =>
      match
        @strategy.prepare_resident_execution(
          run,
          task,
          choice,
          prepared,
          inputs.leases,
          copy_retention,
          scratch,
          fn(ordinal) {
            guard @connector.fixed_compute_choice_payload(choice, prepared)
              is Some(compute) else {
              return Err(ForeignCandidate)
            }
            match
              @compute.prepare_duckdb_resident_output(
                @duckdb.fixed_compute_query(compute),
                ordinal,
                limits,
                transport.max_bytes,
              ) {
              Err(issue) => Err(preparation_failure(issue))
              Ok(plan) => {
                output_plan.val = Some(plan)
                Ok(plan)
              }
            }
          },
          fn(plan, output) {
            match @compute.bind_duckdb_resident_output(plan, output) {
              Ok(value) => {
                inputs.store.imports.set(task, value)
                Ok(@duckdb.resident_import_storage(value))
              }
              Err(Read(issue)) => Err(Read(issue))
              Err(Preparation(issue)) => Err(preparation_failure(issue))
            }
          },
          independent_retention=retention + storage_bytes,
        ) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  let capacity : @connector.ExecutionCapacity = {
    transfer_bytes,
    retained_bytes: retention + storage_bytes + auxiliary_retention_bytes,
    scratch_bytes: scratch,
    execution_bytes: native_execution_bytes + scratch,
  }
  let ceilings = match
    @connector.fixed_compute_choice_payload(choice, prepared).bind(compute => {
      @duckdb.fixed_compute_join_output_ceiling(compute)
    }) {
    Some(value) => [(0, value.to_int64())]
    None => []
  }
  let start_attempt = fn() {
    match
      @compute.start_duckdb_compute_attempt(
        choice,
        prepared,
        generated,
        limits,
        verify,
        retained_required~,
        stream_transport?=if retained_required { Some(transport) } else { None },
      ) {
      Err(issue) => Err(compute_failure(issue))
      Ok(attempt) => {
        retention_attempt.val = Some(attempt)
        let lifecycle : @connector.ExecutionLifecycleOperations[
          @strategy.RunIssue,
        ] = {
          cancel: fn() { @compute.abort_duckdb_compute_attempt(attempt) },
          dispose: fn() { @compute.close_duckdb_compute_attempt(attempt) },
          settled: fn() {  },
          retention_released: retained_storage
          .map(value => value.1)
          .unwrap_or(fn() { true }),
          released: fn() { output_plan.val = None },
          ready: fn() { Ok(()) },
        }
        Ok((attempt, lifecycle))
      }
    }
  }
  let retained_bytes : () -> Result[Int64, @strategy.RunIssue] = fn() {
    if !retained_required {
      return Ok(retention)
    }
    guard retention_attempt.val is Some(attempt) &&
      @compute.retained_duckdb_compute_bytes(attempt) is Some(bytes) &&
      bytes >= 0L &&
      bytes <= storage_bytes else {
      return Err(Physical(InvalidCharge))
    }
    Ok(retention + bytes)
  }
  let bound = @connector.bind_prepared_materializing_execution(
    choice,
    prepared,
    capacity,
    ceilings,
    fn(_) { start_attempt() },
    retained_bytes~,
  )
  let bound = match bound {
    Ok(value) => value
    Err(issue) => return Err(Compute(issue))
  }
  let started = @strategy.start_captured_materializing_execution(
    run,
    task,
    bound,
    resident?,
  )
  match started {
    Err(issue) => Err(issue)
    Ok((attempt, execution)) =>
      Ok({
        attempt,
        execution,
        cleanup_sql_bytes: transport.max_bytes,
        output_plan,
        store,
      })
  }
}

///|
/// Finish the exact admitted DuckDB output for the common completion boundary.
/// Resident publication remains owned by the common execution resource and
/// does not require rebuilding or re-reading the result.
pub fn captured_duckdb_completed_output(
  task : CapturedDuckDBTask,
) -> Result[@execution.CompletedOutput, @strategy.RunIssue] {
  match @compute.complete_duckdb_compute_attempt(task.attempt) {
    Ok(output) => Ok(output)
    Err(issue) => Err(compute_failure(issue))
  }
}

///|
/// Commit one exact DuckDB task through the common materializing boundary.
/// The Connector supplies only its admitted physical output; it has no
/// separate finish or publication authority.
pub fn complete_captured_duckdb_task(
  run : @strategy.CapturedDAG,
  task : CapturedDuckDBTask,
) -> Result[Unit, @strategy.RunIssue] {
  @strategy.complete_deferred_materializing_task_execution(
    run,
    task.execution,
    fn() { captured_duckdb_completed_output(task) },
  )
}

///|
pub fn captured_duckdb_query(
  run : @strategy.CapturedDAG,
  task : CapturedDuckDBTask,
) -> @duckdb.ResidentQuery? {
  if !@strategy.captured_resident_output_available(run, task.execution) {
    return None
  }
  task.output_plan.val.map(plan => @compute.duckdb_resident_output_query(plan))
}

///|
/// Physical cleanup compilation stays in the installed connector. Common code
/// chooses and retires the exact last-use set only after all compilation succeeds.
pub fn captured_duckdb_cleanup_sql(
  run : @strategy.CapturedDAG,
  task : CapturedDuckDBTask,
) -> Result[Array[String], @strategy.RunIssue] {
  @strategy.prepare_captured_cleanup(run, task.execution, fn(tables) {
    guard task.store is Some(store) else { return Err(ForeignCandidate) }
    let statements = []
    for table in tables {
      guard resident_store_import(store, table) is Some(imported) else {
        return Err(ForeignCandidate)
      }
      match @duckdb.resident_import_drop_sql(imported, task.cleanup_sql_bytes) {
        Ok(sql) => statements.push(sql)
        Err(issue) => return Err(preparation_failure(issue))
      }
    }
    Ok(statements)
  })
}
