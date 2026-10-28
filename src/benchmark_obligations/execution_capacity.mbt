///|
/// Benchmark-only combined admission for one database and the simultaneous
/// bounded scratch outside it. Both are suballocations of one execution limit.
struct ObligationExecution {
  ledger : @resources.Ledger
  capacity : @resources.SharedCapacity
  database : @resources.SharedAllocation
  scratch : @resources.SharedAllocation
  task_count : Int
  mut started_tasks : Int
  mut active_task : Bool
  task_reservations : Array[@resources.Reservation]
  mut closed : Bool
}

///|
suberror ExecutionCapacityFailure {
  State
  Capacity(@resources.LedgerIssue)
}

///|
#export_name("obligationExecution")
pub fn obligation_execution(
  limit : Int64,
  database : Int64,
  scratch : Int64,
  task_count : Int,
) -> ObligationExecution raise ExecutionCapacityFailure {
  if limit < 0L ||
    database <= 0L ||
    scratch < 0L ||
    database > limit ||
    scratch > limit - database ||
    task_count < 1 ||
    task_count > 16 {
    raise State
  }
  let ledger = match
    @resources.create_ledger({
      planning_work: 0,
      attempts: task_count,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: limit,
    }) {
    Ok(value) => value
    Err(issue) => raise Capacity(issue)
  }
  let capacity = match
    @resources.reserve_shared_workspace_capacity(ledger, 0L, database + scratch) {
    Ok(value) => value
    Err(issue) => raise Capacity(issue)
  }
  let database_allocation = match
    @resources.allocate_shared_capacity(capacity, database) {
    Ok(value) => value
    Err(issue) => raise Capacity(issue)
  }
  let scratch_allocation = match
    @resources.allocate_shared_capacity(capacity, scratch) {
    Ok(value) => value
    Err(issue) => raise Capacity(issue)
  }
  {
    ledger,
    capacity,
    database: database_allocation,
    scratch: scratch_allocation,
    task_count,
    started_tasks: 0,
    active_task: false,
    task_reservations: [],
    closed: false,
  }
}

///|
/// Shared database capacity does not represent a dispatched Compute task. Each
/// task consumes its own attempt serial immediately before its native work;
/// zero additional bytes are reserved because the same bounded database and
/// scratch allocation remain active throughout the independent Run.
#export_name("obligationExecutionTaskBegin")
pub fn obligation_execution_task_begin(
  owner : ObligationExecution,
) -> Unit raise ExecutionCapacityFailure {
  if owner.closed ||
    owner.active_task ||
    owner.task_reservations.length() != owner.started_tasks ||
    owner.started_tasks >= owner.task_count {
    raise State
  }
  let reservation = match @resources.reserve_attempt(owner.ledger, 0L, 0L, 0L) {
    Ok(value) => value
    Err(issue) => raise Capacity(issue)
  }
  // Keep the original reservation even if admission becomes uncertain. Only
  // confirmed database stop may release an unfinished task's custody.
  owner.task_reservations.push(reservation)
  match @resources.consume_reserved_attempt(owner.ledger, reservation) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
  owner.started_tasks += 1
  owner.active_task = true
}

///|
#export_name("obligationExecutionTaskFinish")
pub fn obligation_execution_task_finish(
  owner : ObligationExecution,
) -> Unit raise ExecutionCapacityFailure {
  if owner.closed || !owner.active_task {
    raise State
  }
  let reservation = owner.task_reservations[owner.started_tasks - 1]
  match @resources.settle_reservation(owner.ledger, reservation) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
  owner.active_task = false
}

///|
#export_name("obligationExecutionUsage")
pub fn obligation_execution_usage(
  owner : ObligationExecution,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(owner.ledger)
}

///|
/// Call only after the database and bounded scratch can no longer be used.
#export_name("obligationExecutionReleased")
pub fn obligation_execution_released(
  owner : ObligationExecution,
) -> Unit raise ExecutionCapacityFailure {
  if owner.closed {
    raise State
  }
  // A failed task is settled only after the database has actually stopped.
  for reservation in owner.task_reservations {
    if @resources.reservation_open(reservation) {
      match @resources.settle_reservation(owner.ledger, reservation) {
        Ok(_) => ()
        Err(issue) => raise Capacity(issue)
      }
    }
  }
  match @resources.retire_shared_capacity(owner.database) {
    Err(issue) => raise Capacity(issue)
    Ok(_) => ()
  }
  match @resources.retire_shared_capacity(owner.scratch) {
    Err(issue) => raise Capacity(issue)
    Ok(_) => ()
  }
  match @resources.release_shared_capacity(owner.database) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
  match @resources.release_shared_capacity(owner.scratch) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
  match @resources.close_shared_capacity(owner.capacity) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
  match @resources.settle_shared_capacity(owner.capacity) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
  owner.closed = true
}
