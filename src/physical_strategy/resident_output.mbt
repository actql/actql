///|
priv struct ResidentPendingOutput {
  environment : ResidentEnvironment
  allocation : @resources.SharedAllocation
  bind_output : (@execution.CompletedOutput) -> Result[
    @execution.ProducerStorage,
    RunIssue,
  ]
  mut committed : Bool
  mut cleanup_prepared : Bool
  retired_inputs : Array[ResidentTable]
}

///|
fn prepare_resident_output(
  run : CapturedDAG,
  env : ResidentEnvironment,
  bytes : Int64,
  prepare : (Int) -> Result[
    (@execution.CompletedOutput) -> Result[@execution.ProducerStorage, RunIssue],
    RunIssue,
  ],
) -> Result[ResidentPendingOutput, RunIssue] {
  if env.next_table >= @resources.ledger_limits(run.ledger).holdings {
    return Err(Physical(HoldingLimit))
  }
  let bind_output = match prepare(env.next_table) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let allocation = match
    @resources.allocate_shared_capacity(env.capacity, bytes) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  env.next_table += 1
  env.allocations.push(allocation)
  Ok({
    environment: env,
    allocation,
    bind_output,
    committed: false,
    cleanup_prepared: false,
    retired_inputs: [],
  })
}

///|
/// Includes the current task's final use, but never another unstarted consumer.
/// The trusted implementation prepares its physical cleanup without I/O. Only
/// successful preparation retires the selected allocations; actual cleanup
/// confirmation remains separate. This operation grants no result authority.
pub fn[T] prepare_captured_cleanup(
  run : CapturedDAG,
  resource : TaskExecution,
  prepare : (Array[ResidentTable]) -> Result[T, RunIssue],
) -> Result[T, RunIssue] {
  guard task_execution_matches(run, resource) &&
    run.running is Some((task, active)) &&
    physical_equal(active, resource) &&
    resource.resident.bind(value => value.pending) is Some(pending) else {
    return Err(ForeignCandidate)
  }
  if pending.cleanup_prepared {
    return Err(NotReady)
  }
  let tables = []
  for table in pending.environment.tables {
    guard table is Some(table) &&
      table.committed &&
      !@resources.shared_allocation_usage(table.allocation).retiring else {
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
      tables.push(table)
    }
  }
  // Only handles are copied. The implementation cannot edit the selected set.
  let prepared = match prepare(tables.copy()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if run.stopped ||
    resource.disposed ||
    pending.cleanup_prepared ||
    !resident_environment_available(run, pending.environment) {
    return Err(NotReady)
  }
  for table in tables {
    if !owns_resident_table(run, table) ||
      @resources.shared_allocation_usage(table.allocation).retiring {
      return Err(ForeignCandidate)
    }
  }
  for table in tables {
    @resources.retire_shared_capacity(table.allocation)
    pending.retired_inputs.push(table)
  }
  pending.cleanup_prepared = true
  Ok(prepared)
}

///|
pub fn captured_resident_output_available(
  run : CapturedDAG,
  resource : TaskExecution,
) -> Bool {
  task_execution_matches(run, resource) &&
  !resource.disposed &&
  resource.resident.bind(value => value.pending) is Some(_)
}

///|
/// Trusted transport confirms this attempt's materialized table transaction.
/// Host receiving/guard validation must also succeed before task publication.
pub fn confirm_captured_resident_output(
  run : CapturedDAG,
  resource : TaskExecution,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard task_execution_matches(run, resource) &&
    run.running is Some((_, active)) &&
    physical_equal(active, resource) &&
    resource.resident.bind(value => value.pending) is Some(output) else {
    return Err(ForeignCandidate)
  }
  if resource.disposed ||
    !resource.execution_settled ||
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
/// Bind a resident result after common output validation. This function
/// receives no publication authority and cannot make the task visible in the
/// DAG.
fn bind_resident_output(
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
  let storage = match (pending.bind_output)(output) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !@execution.producer_storage_matches_output(storage, output) {
    return Err(ForeignCandidate)
  }
  pending.environment.tables[task] = Some({
    environment: pending.environment,
    producer: task,
    storage,
    allocation: pending.allocation,
    committed: true,
    import_started: true,
  })
  Ok(())
}
