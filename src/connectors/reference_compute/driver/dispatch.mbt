///|
priv suberror ReferenceDispatchFailure {
  Plan(@numeric.PlanIssue)
  Dispatch(@host.DispatchIssue)
}

///|
struct NumericDispatchModule {
  run : @strategy.CapturedDAG
  registry : @connector.CapabilityRegistry
  registration : @connector.CapabilityRegistration
  channel : @host.DispatchChannel[
    @connector.PreparedExecution[
      @numeric.NumericAttempt,
      @strategy.RunIssue,
      @strategy.TaskPublication,
    ],
  ]
  sequences : Array[@execution.GeneratedSequence]
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
  sequences : Array[@execution.GeneratedSequence],
  limits : @numeric.NumericExecutionLimits,
  expressions : @lower.ExpressionLimits,
) -> Result[NumericDispatchModule, @numeric.PlanIssue] {
  let run = @host.dispatch_driver_run(driver)
  let graph = @strategy.captured_dag_graph(run)
  if sequences.length() != @strategy.graph_task_count(graph) - 1 {
    return Err(Unsupported)
  }
  for index, sequence in sequences {
    if !(@strategy.graph_task_owner(graph, index + 1) is Some(owner) &&
      physical_equal(owner, @execution.generated_sequence_owner(sequence))) {
      return Err(Unsupported)
    }
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
  Ok({
    run,
    registry,
    registration,
    channel,
    sequences: sequences.copy(),
    limits,
    expressions,
  })
}

///|
pub fn prepare_numeric_dispatch(
  installed : NumericDispatchModule,
  task : Int,
  revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[@host.DispatchWork, @strategy.RunIssue] {
  guard installed.sequences.get(task - 1) is Some(sequence) else {
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
fn numeric_dispatch_issue(issue : @numeric.PlanIssue) -> @strategy.RunIssue {
  @strategy.RunIssue::Implementation(ReferenceDispatchFailure::Plan(issue))
}

///|
pub fn[C, E] start_numeric_dispatch(
  installed : NumericDispatchModule,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[
  (@numeric.NumericAttempt, @strategy.TaskExecution),
  @strategy.RunIssue,
] {
  let prepared = match
    @host.take_installed_task(host, task, installed.channel) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        @strategy.RunIssue::Implementation(
          ReferenceDispatchFailure::Dispatch(issue),
        ),
      )
  }
  @strategy.start_captured_execution(
    installed.run,
    @host.prepared_task_index(task),
    prepared,
  )
}
