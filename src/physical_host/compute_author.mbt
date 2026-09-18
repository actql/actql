///|
/// Checked, immutable task inputs for a basic Compute implementation. The
/// driver and ledger remain private; this context grants neither publication
/// nor arbitrary reservation/settlement authority.
struct ComputeAuthorContext {
  driver : DispatchDriver
  sequences : Array[@execution.CompletionPreparation]
}

///|
pub fn prepare_compute_author_context(
  driver : DispatchDriver,
  sequences : Array[@execution.CompletionPreparation],
) -> Result[ComputeAuthorContext, @connector.FixedComputeIssue] {
  let graph = @strategy.captured_dag_graph(driver.owner.run)
  if sequences.length() != @strategy.graph_task_count(graph) - 1 {
    return Err(ForeignPreparation)
  }
  for index, sequence in sequences {
    if !(@strategy.graph_task_owner(graph, index + 1) is Some(owner) &&
      physical_equal(owner, @execution.completion_preparation_owner(sequence))) {
      return Err(ForeignPreparation)
    }
  }
  Ok({ driver, sequences: sequences.copy(), })
}

///|
pub fn compute_author_sequence(
  context : ComputeAuthorContext,
  task : Int,
) -> @execution.CompletionPreparation? {
  context.sequences.get(task - 1)
}

///|
pub fn charge_compute_author_planning(
  context : ComputeAuthorContext,
  work : Int,
) -> Result[Unit, @resources.LedgerIssue] {
  @resources.charge_planning(
    @strategy.captured_dag_ledger(context.driver.owner.run),
    work,
  )
}

///|
pub fn propose_compute_author_work(
  context : ComputeAuthorContext,
  task : Int,
  registration : @connector.CapabilityRegistration,
  work_slots : Int,
  lines : Array[@cost.SerialEstimateLine],
  envelope : @strategy.PhysicalEnvelope,
  max_work : Int,
) -> Result[@strategy.TaskOffer, @strategy.SearchIssue] {
  @strategy.prepare_task_offer(
    context.driver.owner.run,
    task,
    registration,
    work_slots,
    lines,
    envelope,
    max_work,
  )
}

///|
/// In-process prepared execution, not an asynchronous transport adapter. Return
/// from `execute` confirms that no external work is still running. Selection,
/// reservation, owned completion evidence and result holding are enforced here;
/// a successful callback alone cannot publish output. Asynchronous transports
/// must retain the separate explicit settlement protocol instead.
pub fn[C, E, T] execute_compute_author_work(
  context : ComputeAuthorContext,
  host : DispatchHost[C, E],
  task : PreparedTaskDispatch,
  channel : DispatchChannel[
    @connector.PreparedExecution[
      T,
      @strategy.RunIssue,
      @strategy.TaskPublication,
    ],
  ],
  execute : (T) -> Result[Unit, @strategy.RunIssue],
) -> Result[Unit, @strategy.RunIssue] {
  execute_compute_author_work_with_completion_admission(
    context,
    host,
    task,
    channel,
    execute,
    fn() { true },
  )
}

///|
/// Execute synchronous work while preserving a Host-owned final completion
/// admission. The callback is checked only after execution has stopped and
/// settled, immediately before common completion is committed.
pub fn[C, E, T] execute_compute_author_work_with_completion_admission(
  context : ComputeAuthorContext,
  host : DispatchHost[C, E],
  task : PreparedTaskDispatch,
  channel : DispatchChannel[
    @connector.PreparedExecution[
      T,
      @strategy.RunIssue,
      @strategy.TaskPublication,
    ],
  ],
  execute : (T) -> Result[Unit, @strategy.RunIssue],
  completion_ready : () -> Bool,
) -> Result[Unit, @strategy.RunIssue] {
  if !physical_equal(context.driver, host.owner.driver) {
    return Err(ForeignCandidate)
  }
  let prepared = match take_installed_task(host, task, channel) {
    Ok(value) => value
    Err(_) => return Err(ForeignCandidate)
  }
  let run = context.driver.owner.run
  let (payload, execution) = match
    @strategy.start_captured_execution(run, prepared_task_index(task), prepared) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result = execute(payload)
  match @strategy.settle_task_execution(run, execution, true) {
    Err(issue) => {
      @strategy.close_task_execution(run, execution)
      return Err(Physical(issue))
    }
    Ok(_) => ()
  }
  let result = match result {
    Err(issue) => Err(issue)
    Ok(_) =>
      if completion_ready() {
        @strategy.complete_task_execution(run, execution)
      } else {
        Err(@strategy.RunIssue::Stopped)
      }
  }
  if result is Err(_) {
    @strategy.close_task_execution(run, execution)
  }
  result
}
