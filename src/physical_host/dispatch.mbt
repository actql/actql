///|
/// Common Host ownership of a prepared, not-yet-started task. Implementation
/// payloads stay with the installed connector; they are not stored here.
struct DispatchDriver {
  owner : DispatchOwner
  mut pending : DispatchTicket?
}

///|
priv struct DispatchOwner {
  run : @strategy.CapturedDAG
}

///|
struct DispatchTicket {
  owner : DispatchOwner
  task : Int
  revision : @strategy.StrategyRevision
  mut consumed : Bool
}

///|
pub(all) enum DispatchIssue {
  PendingTask
  StaleTask
  Run(@strategy.RunIssue)
  Candidate(@connector.FixedComputeIssue)
}

///|
pub fn open_dispatch_driver(run : @strategy.CapturedDAG) -> DispatchDriver {
  { owner: { run, }, pending: None, }
}

///|
pub fn dispatch_driver_run(driver : DispatchDriver) -> @strategy.CapturedDAG {
  driver.owner.run
}

///|
pub fn dispatch_driver_pending(driver : DispatchDriver) -> Bool {
  driver.pending is Some(_)
}

///|
/// Before preparation, discard only a ticket whose selection was invalidated.
/// This does not restore a failed search or alter its history/resource ledger.
pub fn check_dispatch_idle(
  driver : DispatchDriver,
) -> Result[Unit, DispatchIssue] {
  if driver.pending is Some(pending) && !pending.consumed {
    if @strategy.captured_dag_strategy(driver.owner.run) is Some(revision) &&
      physical_equal(revision, pending.revision) {
      return Err(PendingTask)
    }
    pending.consumed = true
  }
  driver.pending = None
  Ok(())
}

///|
/// Preparation grants neither resource creation nor successful task completion.
/// The task's existing common start boundary still enforces reservation/ownership.
pub fn prepare_dispatch_ticket(
  driver : DispatchDriver,
  task : Int,
  revision : @strategy.StrategyRevision,
) -> Result[DispatchTicket, DispatchIssue] {
  match check_dispatch_idle(driver) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if @strategy.next_captured_task(driver.owner.run) != Some(task) ||
    !(@strategy.captured_dag_strategy(driver.owner.run) is Some(current) &&
    physical_equal(current, revision)) {
    return Err(StaleTask)
  }
  let ticket = { owner: driver.owner, task, revision, consumed: false, }
  driver.pending = Some(ticket)
  Ok(ticket)
}

///|
pub fn consume_dispatch_ticket(
  driver : DispatchDriver,
  ticket : DispatchTicket,
) -> Result[Unit, DispatchIssue] {
  if !physical_equal(driver.owner, ticket.owner) ||
    ticket.consumed ||
    @strategy.next_captured_task(driver.owner.run) != Some(ticket.task) ||
    !(driver.pending is Some(expected) && physical_equal(expected, ticket)) ||
    !(@strategy.captured_dag_strategy(driver.owner.run) is Some(revision) &&
    physical_equal(revision, ticket.revision)) {
    return Err(StaleTask)
  }
  ticket.consumed = true
  driver.pending = None
  Ok(())
}

///|
pub fn dispatch_ticket_task(ticket : DispatchTicket) -> Int {
  ticket.task
}

///|
pub fn dispatch_ticket_revision(
  ticket : DispatchTicket,
) -> @strategy.StrategyRevision {
  ticket.revision
}

///|
pub fn stop_dispatch_driver(driver : DispatchDriver) -> Unit {
  if driver.pending is Some(ticket) {
    ticket.consumed = true
  }
  driver.pending = None
  @strategy.stop_captured_dag(driver.owner.run)
}
