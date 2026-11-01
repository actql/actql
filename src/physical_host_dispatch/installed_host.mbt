///|
/// Immutable implementation installation and input-admission policy for one
/// common driver. C is trusted preparation context, not an execution payload.
/// Implementations perform pure preparation; actual work uses the existing
/// common reservation, start, completion and cleanup boundaries.
struct DispatchHost[C, E] {
  owner : DispatchHostOwner
  implementations : @connector.CapabilityImplementations[
    (C, Int, @strategy.StrategyRevision, @connector.FixedComputeRequest) -> Result[
      DispatchWork,
      E,
    ],
  ]
  capacity : @connector.FixedComputeCapacity
  max_entries : Int
  max_name_bytes : Int
}

///|
priv struct DispatchHostOwner {
  driver : DispatchDriver
}

///|
struct PreparedTaskDispatch {
  owner : DispatchHostOwner
  ticket : DispatchTicket
  work : DispatchWork
}

///|
pub fn[C, E] open_dispatch_host(
  driver : DispatchDriver,
  implementations : @connector.CapabilityImplementations[
    (C, Int, @strategy.StrategyRevision, @connector.FixedComputeRequest) -> Result[
      DispatchWork,
      E,
    ],
  ],
  capacity : @connector.FixedComputeCapacity,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[DispatchHost[C, E], DispatchIssue] {
  if max_entries < 0 ||
    max_name_bytes < 0 ||
    capacity.max_rows < 0 ||
    capacity.max_value_bytes < 0 {
    return Err(Candidate(InvalidLimits))
  }
  Ok({
    owner: { driver, },
    implementations,
    capacity,
    max_entries,
    max_name_bytes,
  })
}

///|
pub fn[C, E] prepare_next_installed_task(
  host : DispatchHost[C, E],
  context : C,
) -> Result[PreparedTaskDispatch?, InstalledDispatchIssue[E]] {
  let driver = host.owner.driver
  match check_dispatch_idle(driver) {
    Err(issue) => return Err(Dispatch(issue))
    Ok(_) => ()
  }
  let run = driver.owner.run
  guard @strategy.next_captured_task(run) is Some(task) else { return Ok(None) }
  guard @strategy.captured_dag_strategy(run) is Some(revision) else {
    return Err(NoStrategy)
  }
  let (ticket, work) = match
    prepare_installed_dispatch(
      driver,
      host.implementations,
      context,
      task,
      revision,
      host.capacity,
      host.max_entries,
      host.max_name_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // A trusted implementation may still return a miswired/stale preparation.
  // Never expose its payload or leave the newly created ticket dispatchable.
  if !physical_equal(work.owner, driver.owner) ||
    work.task != task ||
    !physical_equal(work.revision, revision) ||
    !(@strategy.strategy_registration(revision, task) is Some(selected) &&
    physical_equal(selected, work.registration)) {
    stop_dispatch_driver(driver)
    return Err(Dispatch(StaleTask))
  }
  Ok(Some({ owner: host.owner, ticket, work, }))
}

///|
pub fn[C, E, T] take_installed_task(
  host : DispatchHost[C, E],
  task : PreparedTaskDispatch,
  channel : DispatchChannel[T],
) -> Result[T, DispatchIssue] {
  if !physical_equal(host.owner, task.owner) {
    return Err(StaleTask)
  }
  take_dispatch_work(channel, host.owner.driver, task.ticket, task.work)
}

///|
pub fn prepared_task_index(task : PreparedTaskDispatch) -> Int {
  task.ticket.task
}

///|
pub fn prepared_task_revision(
  task : PreparedTaskDispatch,
) -> @strategy.StrategyRevision {
  task.ticket.revision
}

///|
pub fn prepared_task_registration(
  task : PreparedTaskDispatch,
) -> @connector.CapabilityRegistration {
  task.work.registration
}
