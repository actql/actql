///|
/// Benchmark-only combined admission for one database and the simultaneous
/// bounded scratch outside it. Both are suballocations of one execution limit.
struct ObligationExecution {
  ledger : @resources.Ledger
  capacity : @resources.SharedCapacity
  database : @resources.SharedAllocation
  scratch : @resources.SharedAllocation
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
) -> ObligationExecution raise ExecutionCapacityFailure {
  if limit < 0L ||
    database <= 0L ||
    scratch < 0L ||
    database > limit ||
    scratch > limit - database {
    raise State
  }
  let ledger = match
    @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: limit,
    }) {
    Ok(value) => value
    Err(issue) => raise Capacity(issue)
  }
  let capacity = match
    @resources.reserve_shared_capacity(ledger, database + scratch) {
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
    closed: false,
  }
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
  @resources.retire_shared_capacity(owner.database)
  @resources.retire_shared_capacity(owner.scratch)
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
