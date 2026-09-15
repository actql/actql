///|
pub(all) enum InstalledDispatchIssue[E] {
  NoStrategy
  Dispatch(DispatchIssue)
  MissingImplementation
  Implementation(E)
}

///|
/// Prepare through this Host's immutable implementation installation. The
/// selected exact registration, not a provider name, determines the operation.
/// C is trusted Host wiring and W stays opaque to this driver. Preparation must
/// not start I/O; consuming the ticket does not replace common start admission.
pub fn[C, W, E] prepare_installed_dispatch(
  driver : DispatchDriver,
  installed : @connector.CapabilityImplementations[
    (C, Int, @strategy.StrategyRevision, @connector.FixedComputeRequest) -> Result[
      W,
      E,
    ],
  ],
  context : C,
  task : Int,
  revision : @strategy.StrategyRevision,
  capacity : @connector.FixedComputeCapacity,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[(DispatchTicket, W), InstalledDispatchIssue[E]] {
  match check_dispatch_idle(driver) {
    Err(issue) => return Err(Dispatch(issue))
    Ok(_) => ()
  }
  guard @strategy.strategy_registration(revision, task) is Some(registration) else {
    return Err(MissingImplementation)
  }
  guard @connector.capability_implementation(installed, registration)
    is Some(implementation) else {
    return Err(MissingImplementation)
  }
  let request = match
    prepare_dispatch_inputs(
      driver, task, revision, capacity, max_entries, max_name_bytes,
    ) {
    Err(issue) => return Err(Dispatch(issue))
    Ok(request) => request
  }
  let work = match implementation(context, task, revision, request) {
    Err(issue) => return Err(Implementation(issue))
    Ok(work) => work
  }
  // Revalidate after trusted preparation: a callback cannot make a stale
  // revision dispatchable by returning a successful payload.
  if @connector.capability_implementation(installed, registration) is None {
    return Err(MissingImplementation)
  }
  match prepare_dispatch_ticket(driver, task, revision) {
    Err(issue) => Err(Dispatch(issue))
    Ok(ticket) => Ok((ticket, work))
  }
}
