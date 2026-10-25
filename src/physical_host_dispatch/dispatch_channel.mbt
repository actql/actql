///|
/// One typed preparation slot owned by an installed implementation for this
/// driver. Only the routing token crosses the common dispatch boundary; T is
/// never erased, cast, or interpreted by the Host. Staging performs no I/O.
struct DispatchChannel[T] {
  owner : DispatchOwner
  registry : @connector.CapabilityRegistry
  registration : @connector.CapabilityRegistration
  mut pending : (DispatchWork, T)?
}

///|
/// This is not a start permit or a completion proof. Recovering the connector's
/// preparation still consumes the exact common dispatch ticket; reservation and
/// execution admission remain mandatory afterwards.
struct DispatchWork {
  owner : DispatchOwner
  registration : @connector.CapabilityRegistration
  task : Int
  revision : @strategy.StrategyRevision
}

///|
pub fn[T] open_dispatch_channel(
  driver : DispatchDriver,
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
) -> Result[DispatchChannel[T], DispatchIssue] {
  if !@connector.capability_registration_matches(registration, registry) ||
    !@connector.capability_description(registration).fixed_compute {
    return Err(Candidate(ComputeUnsupported))
  }
  Ok({ owner: driver.owner, registry, registration, pending: None, })
}

///|
pub fn[T] stage_dispatch_work(
  channel : DispatchChannel[T],
  task : Int,
  revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
  payload : T,
) -> Result[DispatchWork, DispatchIssue] {
  let run = channel.owner.run
  if !@connector.capability_registration_matches(
      channel.registration,
      channel.registry,
    ) ||
    @strategy.next_captured_task(run) != Some(task) ||
    !(@strategy.captured_dag_strategy(run) is Some(current) &&
    physical_equal(current, revision)) ||
    !(@strategy.strategy_registration(revision, task) is Some(selected) &&
    physical_equal(selected, channel.registration)) ||
    !(@strategy.graph_task_owner(@strategy.captured_dag_graph(run), task)
    is Some(owner) &&
    physical_equal(owner, @connector.fixed_compute_request_owner(request))) {
    return Err(StaleTask)
  }
  if channel.pending is Some((previous, _)) &&
    physical_equal(previous.revision, revision) &&
    previous.task == task {
    return Err(PendingTask)
  }
  // The previous slot belongs to a stale selection or an earlier task. It held
  // only a pure preparation, never an active attempt or unrecovered resources.
  let work = {
    owner: channel.owner,
    registration: channel.registration,
    task,
    revision,
  }
  channel.pending = Some((work, payload))
  Ok(work)
}

///|
pub fn[T] take_dispatch_work(
  channel : DispatchChannel[T],
  driver : DispatchDriver,
  ticket : DispatchTicket,
  work : DispatchWork,
) -> Result[T, DispatchIssue] {
  guard channel.pending is Some((expected, payload)) else {
    return Err(StaleTask)
  }
  if !physical_equal(expected, work) ||
    !physical_equal(channel.owner, driver.owner) ||
    !physical_equal(work.owner, ticket.owner) ||
    work.task != ticket.task ||
    !physical_equal(work.revision, ticket.revision) ||
    !@connector.capability_registration_matches(
      channel.registration,
      channel.registry,
    ) {
    return Err(StaleTask)
  }
  match consume_dispatch_ticket(driver, ticket) {
    Err(issue) => Err(issue)
    Ok(_) => {
      channel.pending = None
      Ok(payload)
    }
  }
}

///|
pub fn dispatch_work_registration(
  work : DispatchWork,
) -> @connector.CapabilityRegistration {
  work.registration
}
