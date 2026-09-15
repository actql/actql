///|
priv struct ResidentPendingOutput {
  environment : ResidentEnvironment
  allocation : ResidentAllocation
  table_name : String
  query : @duckdb.ResidentQuery
  limits : @duckdb_compute.DuckDBComputeLimits
  max_sql_bytes : Int
  mut committed : Bool
  mut cleanup_prepared : Bool
  retired_inputs : Array[ResidentTable]
}

///|
fn prepare_resident_output(
  run : CapturedDAG,
  env : ResidentEnvironment,
  query : @duckdb.FixedQuery,
  bytes : Int64,
  limits : @duckdb_compute.DuckDBComputeLimits,
  max_sql_bytes : Int,
) -> Result[ResidentPendingOutput, RunIssue] {
  if env.next_table >= @resources.ledger_limits(run.ledger).holdings {
    return Err(Physical(HoldingLimit))
  }
  let table_name = "resident_" + env.next_table.to_string()
  let query = match
    @duckdb.prepare_resident_query(query, table_name, max_sql_bytes) {
    Ok(value) => value
    Err(issue) => return Err(NativePreparation(issue))
  }
  let allocation = match allocate_resident_capacity(env.capacity, bytes) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  env.next_table += 1
  env.allocations.push(allocation)
  Ok({
    environment: env,
    allocation,
    table_name,
    query,
    limits,
    max_sql_bytes,
    committed: false,
    cleanup_prepared: false,
    retired_inputs: [],
  })
}

///|
/// Includes the current task's final use, but never another unstarted consumer.
/// DROP executes inside this task's transaction after its reads have finished.
pub fn captured_resident_cleanup_sql(
  run : CapturedDAG,
  resource : CapturedDuckDBTask,
) -> Result[Array[String], RunIssue] {
  guard captured_duckdb_task_matches(run, resource) &&
    run.running is Some((task, active)) &&
    physical_equal(active, resource.execution) &&
    resource.resident_output.val is Some(pending) else {
    return Err(ForeignCandidate)
  }
  if pending.cleanup_prepared {
    return Err(NotReady)
  }
  let sql = []
  let tables = []
  for table in pending.environment.tables {
    guard table is Some(table) && table.committed && !table.allocation.retiring else {
      continue
    }
    match @resources.charge_planning(run.ledger, run.graph.data.length() + 1) {
      Err(issue) => return Err(Physical(issue))
      Ok(_) => ()
    }
    let mut needed = false
    for edge in run.graph.data {
      if edge.producer == table.producer &&
        edge.consumer != task &&
        !task_done(run, edge.consumer) {
        needed = true
      }
    }
    if !needed {
      match
        @duckdb.resident_import_drop_sql(table.imported, pending.max_sql_bytes) {
        Ok(value) => sql.push(value)
        Err(issue) => return Err(NativePreparation(issue))
      }
      tables.push(table)
    }
  }
  for table in tables {
    retire_resident_capacity(table.allocation)
    pending.retired_inputs.push(table)
  }
  pending.cleanup_prepared = true
  Ok(sql)
}

///|
pub fn captured_resident_query(
  run : CapturedDAG,
  resource : CapturedDuckDBTask,
) -> @duckdb.ResidentQuery? {
  if captured_duckdb_task_matches(run, resource) {
    resource.resident_output.val.map(value => value.query)
  } else {
    None
  }
}

///|
/// Trusted transport confirms this attempt's materialized table transaction.
/// Host receiving/guard validation must also succeed before task publication.
pub fn confirm_captured_resident_output(
  run : CapturedDAG,
  resource : CapturedDuckDBTask,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard captured_duckdb_task_matches(run, resource) &&
    run.running is Some((_, active)) &&
    physical_equal(active, resource.execution) &&
    resource.resident_output.val is Some(output) else {
    return Err(ForeignCandidate)
  }
  if resource.execution.disposed ||
    !resource.execution.execution_settled ||
    output.committed ||
    !resident_environment_available(run, output.environment) {
    return Err(NotReady)
  }
  output.committed = true
  // Native settlement returned borrowers; transaction commit confirms the DROP.
  for table in output.retired_inputs {
    match release_resident_table(run, table) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok(())
}

///|
fn publish_resident_output(
  run : CapturedDAG,
  task : Int,
  pending : ResidentPendingOutput,
  output : @execution.CompletedOutput,
) -> Result[Unit, RunIssue] {
  if !pending.committed ||
    !resident_environment_available(run, pending.environment) ||
    pending.environment.tables[task] is Some(_) {
    return Err(NotReady)
  }
  let storage = match
    @execution.prepare_producer_storage(
      output,
      pending.limits.metadata_work,
      pending.limits.completion_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Read(issue))
  }
  let imported = match
    @duckdb.prepare_resident_import(
      storage,
      pending.table_name,
      pending.limits.completion_entries,
      pending.max_sql_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NativePreparation(issue))
  }
  pending.environment.tables[task] = Some({
    environment: pending.environment,
    producer: task,
    imported,
    allocation: pending.allocation,
    committed: true,
    import_started: true,
  })
  Ok(())
}
