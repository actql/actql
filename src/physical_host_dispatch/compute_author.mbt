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
  let first = @strategy.captured_compute_first_task(driver.owner.run)
  if sequences.length() != @strategy.graph_task_count(graph) - first {
    return Err(ForeignPreparation)
  }
  for index, sequence in sequences {
    if !(@strategy.graph_task_owner(graph, index + first) is Some(owner) &&
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
  context.sequences.get(
    task - @strategy.captured_compute_first_task(context.driver.owner.run),
  )
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
/// Execute synchronous materializing work through the common output boundary.
/// The implementation returns its exact admitted output but owns no separate
/// finish or publication authority.
pub fn[C, E, T] execute_materializing_compute_author_work_with_completion_admission(
  context : ComputeAuthorContext,
  host : DispatchHost[C, E],
  task : PreparedTaskDispatch,
  channel : DispatchChannel[@connector.PreparedExecution[T, @strategy.RunIssue]],
  execute : (T) -> Result[@execution.CompletedOutput, @strategy.RunIssue],
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
    @strategy.start_captured_materializing_execution(
      run,
      prepared_task_index(task),
      prepared,
    ) {
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
    Ok(output) =>
      if completion_ready() {
        @strategy.complete_materializing_task_execution(run, execution, output)
      } else {
        Err(@strategy.RunIssue::Stopped)
      }
  }
  if result is Err(_) {
    @strategy.close_task_execution(run, execution)
  }
  result
}
