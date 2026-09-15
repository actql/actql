///|
/// Exact environment generation and producer allocation, never a content cache.
struct ResidentTable {
  environment : ResidentEnvironment
  producer : Int
  storage : @execution.ProducerStorage
  allocation : @resources.SharedAllocation
  mut committed : Bool
  mut import_started : Bool
}

///|
/// One native borrower. Completion/stop returns it once; cancellation does not.
struct ResidentRead {
  table : ResidentTable
  input : @execution.ProducerRead
  mut returned : Bool
  borrow : @resources.SharedBorrow
}

///|
pub fn prepare_resident_storage(
  run : CapturedDAG,
  env : ResidentEnvironment,
  producer : Int,
  bytes : Int64,
  max_entries : Int,
  max_name_bytes : Int,
  prepare : (@execution.ProducerStorage, Int) -> Result[
    @execution.ProducerStorage,
    RunIssue,
  ],
) -> Result[ResidentTable, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if !resident_environment_available(run, env) {
    return Err(ForeignCandidate)
  }
  if producer < 0 ||
    producer >= env.tables.length() ||
    !task_done(run, producer) {
    return Err(NotReady)
  }
  if env.tables[producer] is Some(_) {
    return Err(NotReady)
  }
  if bytes <= 0L {
    return Err(Physical(InvalidCharge))
  }
  let selected = match selected_resident_import(run, env, producer) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if bytes != selected.table_bytes {
    return Err(Physical(InvalidCharge))
  }
  if env.next_table >= @resources.ledger_limits(run.ledger).holdings {
    return Err(Physical(HoldingLimit))
  }
  let storage = if producer == 0 {
    guard run.source is Some(source) else { return Err(MissingOutput) }
    match
      @planning.captured_source_storage(source, max_entries, max_name_bytes) {
      Ok(value) => value
      Err(issue) => return Err(Capture(issue))
    }
  } else {
    guard captured_task_target(run, producer) is Some(target) &&
      captured_task_output(run, producer, target) is Some(output) else {
      return Err(MissingOutput)
    }
    match
      @execution.prepare_producer_storage(output, max_entries, max_name_bytes) {
      Ok(value) => value
      Err(issue) => return Err(Read(issue))
    }
  }
  match @resources.charge_planning(run.ledger, 1) {
    Err(issue) => return Err(Physical(issue))
    Ok(_) => ()
  }
  let ordinal = env.next_table
  let prepared_storage = match prepare(storage, ordinal) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Trusted preparation cannot substitute equal-content storage or publish an
  // allocation after changing the selected environment's preparation state.
  if run.stopped ||
    !resident_environment_available(run, env) ||
    env.next_table != ordinal ||
    env.tables[producer] is Some(_) ||
    !physical_equal(prepared_storage, storage) ||
    !@execution.producer_storage_available(storage) {
    return Err(ForeignCandidate)
  }
  let allocation = match
    @resources.allocate_shared_capacity(env.capacity, bytes) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let table = {
    environment: env,
    producer,
    storage,
    allocation,
    committed: false,
    import_started: false,
  }
  env.next_table += 1
  env.allocations.push(allocation)
  env.tables[producer] = Some(table)
  Ok(table)
}

///|
fn owns_resident_table(run : CapturedDAG, table : ResidentTable) -> Bool {
  owns_resident_environment(run, table.environment) &&
  table.environment.tables[table.producer] is Some(owned) &&
  physical_equal(owned, table)
}

///|
/// Cancel the most recent, unstarted table preparation. No native resource or
/// import reservation may exist. Reclaim its slot, quota and unused SQL name
/// together; stale handles stay invalid by exact ownership. Planning work stays
/// spent. Once begin_resident_transfer succeeds, use abort and confirmed cleanup.
pub fn cancel_resident_table_preparation(
  run : CapturedDAG,
  table : ResidentTable,
) -> Result[Unit, @resources.LedgerIssue] {
  let env = table.environment
  if !owns_resident_table(run, table) {
    return Err(ForeignOwner)
  }
  guard env.allocations.last() is Some(last) else { return Err(InvalidCharge) }
  if table.import_started ||
    table.committed ||
    @resources.shared_allocation_usage(table.allocation).retiring ||
    !physical_equal(last, table.allocation) {
    return Err(InvalidCharge)
  }
  @resources.retire_shared_capacity(table.allocation)
  match @resources.release_shared_capacity(table.allocation) {
    Err(issue) => Err(issue)
    Ok(_) => {
      env.tables[table.producer] = None
      env.allocations.pop() |> ignore
      env.next_table -= 1
      Ok(())
    }
  }
}

///|
pub fn resident_table_storage(
  table : ResidentTable,
) -> @execution.ProducerStorage {
  table.storage
}

///|
pub fn resident_table_producer(table : ResidentTable) -> Int {
  table.producer
}

///|
pub fn resident_table_environment(table : ResidentTable) -> ResidentEnvironment {
  table.environment
}

///|
pub fn resident_table_at(
  run : CapturedDAG,
  env : ResidentEnvironment,
  producer : Int,
) -> ResidentTable? {
  if !resident_environment_available(run, env) {
    return None
  }
  env.tables
  .get(producer)
  .bind(value => value)
  .filter(table => {
    table.committed &&
    !@resources.shared_allocation_usage(table.allocation).retiring
  })
}

///|
/// Trusted import completion only, after the exact transport and transaction
/// commit. This does not discharge any receiver's guards or grant dispatch.
pub fn confirm_resident_table(
  run : CapturedDAG,
  table : ResidentTable,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if !owns_resident_table(run, table) ||
    !resident_environment_available(run, table.environment) {
    return Err(ForeignCandidate)
  }
  if table.committed ||
    @resources.shared_allocation_usage(table.allocation).retiring {
    return Err(NotReady)
  }
  if !@execution.producer_storage_available(table.storage) {
    return Err(Read(ProducerUnavailable))
  }
  table.committed = true
  run.generation += 1
  Ok(())
}

///|
pub fn borrow_resident_table(
  run : CapturedDAG,
  table : ResidentTable,
  task : Int,
  max_entries : Int,
  max_name_bytes : Int,
  prepare_view : (ResidentTable, @execution.ProducerRead) -> Result[
    Unit,
    RunIssue,
  ],
  input_index? : Int = 0,
) -> Result[ResidentRead, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if !owns_resident_table(run, table) ||
    !table.committed ||
    !resident_environment_available(run, table.environment) {
    return Err(ForeignCandidate)
  }
  let input = match
    captured_task_input(run, task, max_entries, max_name_bytes, input_index~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Receiver/producer ownership is a common contract, not an adapter's
  // optional view-compilation check. This only builds a bounded index mapping;
  // it neither copies rows nor re-admits their values.
  match
    @execution.producer_storage_projection(table.storage, input, max_entries) {
    Ok(_) => ()
    Err(issue) => return Err(Read(issue))
  }
  match prepare_view(table, input) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if run.stopped ||
    !owns_resident_table(run, table) ||
    !table.committed ||
    !resident_environment_available(run, table.environment) ||
    !@execution.producer_storage_available(table.storage) ||
    !@execution.producer_read_available(input) {
    return Err(ForeignCandidate)
  }
  match
    @resources.borrow_shared_capacity(
      table.environment.capacity,
      table.allocation,
    ) {
    Err(issue) => Err(Physical(issue))
    Ok(borrow) => Ok({ table, input, borrow, returned: false, })
  }
}

///|
pub fn resident_read_matches(
  run : CapturedDAG,
  read : ResidentRead,
  input : @execution.ProducerRead,
) -> Bool {
  !read.returned &&
  physical_equal(read.input, input) &&
  owns_resident_table(run, read.table) &&
  read.table.committed &&
  !@resources.shared_allocation_usage(read.table.allocation).retiring &&
  resident_environment_available(run, read.table.environment) &&
  @execution.producer_storage_available(read.table.storage) &&
  @execution.producer_read_available(input)
}

///|
pub fn return_resident_read(
  read : ResidentRead,
) -> Result[Unit, @resources.LedgerIssue] {
  if read.returned {
    return Err(InvalidCharge)
  }
  match @resources.return_shared_capacity(read.borrow) {
    Err(issue) => Err(issue)
    Ok(_) => {
      read.returned = true
      Ok(())
    }
  }
}

///|
pub fn retire_resident_table(
  run : CapturedDAG,
  table : ResidentTable,
) -> Result[Unit, @resources.LedgerIssue] {
  if !owns_resident_table(run, table) {
    return Err(ForeignOwner)
  }
  if @resources.shared_allocation_usage(table.allocation).retiring {
    return Ok(())
  }
  @resources.retire_shared_capacity(table.allocation)
  run.generation += 1
  run.strategy = None
  Ok(())
}

///|
/// Actual native removal confirmation. Retiring/busy tables stay accounted.
pub fn release_resident_table(
  run : CapturedDAG,
  table : ResidentTable,
) -> Result[Unit, @resources.LedgerIssue] {
  if !owns_resident_table(run, table) {
    return Err(ForeignOwner)
  }
  match @resources.release_shared_capacity(table.allocation) {
    Err(issue) => Err(issue)
    Ok(_) => {
      table.environment.tables[table.producer] = None
      run.generation += 1
      Ok(())
    }
  }
}
