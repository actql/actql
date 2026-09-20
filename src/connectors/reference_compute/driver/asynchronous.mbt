///|
/// Connector-owned pending work. The common task owns its reservation and
/// retained completion. No caller can reconstruct this from data or an ID.
struct AsyncNumericExecution {
  run : @strategy.CapturedDAG
  task : @strategy.TaskExecution
  payload : @numeric.NumericAttempt
}

///|
/// Begin through the same installed channel and common reservation boundary as
/// synchronous execution, but leave stopping/settlement explicit for a Host
/// that controls an asynchronous test transport.
pub fn[C, E] begin_numeric_contribution(
  configured : NumericComputeContribution,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[AsyncNumericExecution, @strategy.RunIssue] {
  let installed = configured.installed
  let prepared = match
    @host.take_installed_task(host, task, installed.channel) {
    Ok(value) => value
    Err(_) => return Err(ForeignCandidate)
  }
  let run = @host.dispatch_driver_run(installed.driver)
  match
    @strategy.start_captured_materializing_execution(
      run,
      @host.prepared_task_index(task),
      prepared,
    ) {
    Ok((payload, task)) => Ok({ run, task, payload, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn execute_async_numeric(
  work : AsyncNumericExecution,
) -> Result[Unit, @strategy.RunIssue] {
  @numeric.execute_numeric_attempt(work.payload).map_err(numeric_dispatch_issue)
}

///|
/// Cancellation is not a stop confirmation and does not release reservation.
pub fn close_async_numeric(work : AsyncNumericExecution) -> Unit {
  @strategy.close_task_execution(work.run, work.task)
}

///|
/// Called only by the trusted transport after its pending work has stopped.
pub fn settle_async_numeric(
  work : AsyncNumericExecution,
) -> Result[Unit, @strategy.RunIssue] {
  @strategy.settle_task_execution(work.run, work.task, true).map_err(issue => {
    Physical(issue)
  })
}

///|
pub fn complete_async_numeric(
  work : AsyncNumericExecution,
) -> Result[Unit, @strategy.RunIssue] {
  guard @numeric.numeric_attempt_completed_output(work.payload) is Some(output) else {
    return Err(@strategy.RunIssue::NotReady)
  }
  @strategy.complete_materializing_task_execution(work.run, work.task, output)
}
