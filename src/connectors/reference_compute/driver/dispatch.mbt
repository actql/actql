///|
priv suberror ReferenceDispatchFailure {
  Plan(@numeric.PlanIssue)
  Dispatch(@host.DispatchIssue)
  Search(@strategy.SearchIssue)
}

///|
struct NumericDispatchModule {
  driver : @host.DispatchDriver
  context : @host.ComputeAuthorContext
  registry : @connector.CapabilityRegistry
  registration : @connector.CapabilityRegistration
  channel : @host.DispatchChannel[
    @connector.PreparedExecution[
      @numeric.NumericAttempt,
      @strategy.RunIssue,
      @strategy.TaskPublication,
    ],
  ]
  limits : @numeric.NumericExecutionLimits
  expressions : @lower.ExpressionLimits
}

///|
/// Pure connector installation. Sequence handles and typed preparations remain
/// here; the common Host receives only registration-bound work tokens.
pub fn prepare_numeric_dispatch_module(
  driver : @host.DispatchDriver,
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  sequences : Array[@execution.CompletionPreparation],
  limits : @numeric.NumericExecutionLimits,
  expressions : @lower.ExpressionLimits,
) -> Result[NumericDispatchModule, @numeric.PlanIssue] {
  let context = match @host.prepare_compute_author_context(driver, sequences) {
    Ok(value) => value
    Err(_) => return Err(Unsupported)
  }
  match @numeric.numeric_execution_capacity(limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let channel = match
    @host.open_dispatch_channel(driver, registry, registration) {
    Ok(value) => value
    Err(_) => return Err(Unsupported)
  }
  Ok({ driver, context, registry, registration, channel, limits, expressions, })
}

///|
pub fn prepare_numeric_dispatch(
  installed : NumericDispatchModule,
  task : Int,
  revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[@host.DispatchWork, @strategy.RunIssue] {
  guard @host.compute_author_sequence(installed.context, task) is Some(sequence) else {
    return Err(numeric_dispatch_issue(Unsupported))
  }
  let candidate = match
    @numeric.offer_numeric_compute(
      installed.registration,
      request,
      installed.limits.max_entries,
      installed.limits.max_name_bytes,
      installed.expressions,
      0,
      [],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
    ) {
    Ok(value) => value
    Err(issue) => return Err(numeric_dispatch_issue(issue))
  }
  let choice = match
    @connector.choose_fixed_compute_candidate(
      installed.registry,
      request,
      [@connector.prepared_compute_candidate(candidate)],
      Some([0]),
      installed.limits.max_work,
    ) {
    Ok(Proposed(choice)) => choice
    Ok(_) => return Err(numeric_dispatch_issue(Unsupported))
    Err(issue) => return Err(@strategy.RunIssue::Compute(issue))
  }
  let prepared = match
    @numeric.prepare_numeric_execution(
      choice,
      candidate,
      sequence,
      installed.limits,
      numeric_dispatch_issue,
    ) {
    Ok(value) => value
    Err(issue) => return Err(numeric_dispatch_issue(issue))
  }
  match
    @host.stage_dispatch_work(
      installed.channel,
      task,
      revision,
      request,
      prepared,
    ) {
    Ok(work) => Ok(work)
    Err(issue) =>
      return Err(
        @strategy.RunIssue::Implementation(
          ReferenceDispatchFailure::Dispatch(issue),
        ),
      )
  }
}

///|
/// Propose only the independently supported checked shape. No future input or
/// content identity is fabricated; actual input binding remains a later step.
pub fn estimate_numeric_dispatch_offer(
  installed : NumericDispatchModule,
  task : Int,
  milliseconds : Int64?,
  max_work : Int,
) -> Result[@strategy.TaskOffer?, @strategy.RunIssue] {
  if max_work < 1 {
    return Err(numeric_dispatch_issue(Limit))
  }
  guard @host.compute_author_sequence(installed.context, task) is Some(sequence) else {
    return Err(numeric_dispatch_issue(Unsupported))
  }
  match @host.charge_compute_author_planning(installed.context, max_work) {
    Ok(_) => ()
    Err(issue) => return Err(@strategy.RunIssue::Physical(issue))
  }
  match
    @numeric.prepare_numeric_plan(
      @execution.completion_preparation_owner(sequence),
      installed.limits.max_entries,
      installed.limits.max_name_bytes,
      {
        ..installed.expressions,
        max_work: if installed.expressions.max_work < max_work {
          installed.expressions.max_work
        } else {
          max_work
        },
      },
    ) {
    Ok(_) => ()
    Err(Unsupported) => return Ok(None)
    Err(issue) => return Err(numeric_dispatch_issue(issue))
  }
  let capacity = match @numeric.numeric_execution_capacity(installed.limits) {
    Ok(value) => value
    Err(issue) => return Err(numeric_dispatch_issue(issue))
  }
  match
    @host.propose_compute_author_work(
      installed.context,
      task,
      installed.registration,
      1,
      [{ work_slots: [0], milliseconds, }],
      {
        transfer_bytes: capacity.transfer_bytes,
        retained_bytes: capacity.retained_bytes,
        execution_bytes: capacity.execution_bytes,
      },
      max_work,
    ) {
    Ok(value) => Ok(Some(value))
    Err(issue) =>
      Err(
        @strategy.RunIssue::Implementation(
          ReferenceDispatchFailure::Search(issue),
        ),
      )
  }
}

///|
fn numeric_dispatch_issue(issue : @numeric.PlanIssue) -> @strategy.RunIssue {
  @strategy.RunIssue::Implementation(ReferenceDispatchFailure::Plan(issue))
}

///|
fn[C, E] execute_numeric_dispatch(
  installed : NumericDispatchModule,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[Unit, @strategy.RunIssue] {
  @host.execute_compute_author_work(
    installed.context,
    host,
    task,
    installed.channel,
    attempt => {
      @numeric.execute_numeric_attempt(attempt).map_err(numeric_dispatch_issue)
    },
  )
}
