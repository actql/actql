///|
/// One exact run/task execution. Physical lifecycle belongs to the common
/// driver; the installed implementation owns its private transport state.
/// Construction is private: callers cannot attach arbitrary completion hooks.
priv struct TaskExecution {
  task : Int
  reservation : @resources.Reservation
  retention : Int64
  scratch : Int64
  mut hooks : TaskExecutionHooks?
  mut execution_settled : Bool
  mut disposed : Bool
  mut failed_holding : @resources.Holding?
}

///|
/// Installed implementation references live only until final disposal and
/// settlement. A retained closed handle must not retain the whole driver graph.
priv struct TaskExecutionHooks {
  cancel : () -> Unit
  dispose : () -> Unit
  settled : () -> Unit
  released : () -> Unit
  ready : () -> Result[Unit, RunIssue]
  finish : () -> Result[@execution.CompletedOutput, RunIssue]
  publish : (@execution.CompletedOutput) -> Result[Unit, RunIssue]
}

///|
fn task_execution_matches(run : CapturedDAG, execution : TaskExecution) -> Bool {
  run.executions.get(execution.task).bind(x => x) is Some(owned) &&
  physical_equal(owned, execution)
}

///|
fn charge_task_execution_transfer(
  run : CapturedDAG,
  execution : TaskExecution,
  bytes : Int64,
) -> Result[Unit, @resources.LedgerIssue] {
  if !task_execution_matches(run, execution) {
    return Err(ForeignOwner)
  }
  if execution.disposed || execution.execution_settled {
    return Err(ClosedReservation)
  }
  @resources.charge_transfer(run.ledger, execution.reservation, bytes)
}

///|
/// Acknowledgement is supplied by the installed trusted transport, not by
/// ordinary selection. False retains cleanup responsibility and all capacity.
fn settle_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
  confirmed : Bool,
) -> Result[Unit, @resources.LedgerIssue] {
  if !task_execution_matches(run, execution) {
    return Err(ForeignOwner)
  }
  if execution.execution_settled {
    return Ok(())
  }
  if !confirmed {
    return @resources.mark_cleanup_pending(run.ledger, execution.reservation)
  }
  let result = if execution.disposed {
    @resources.settle_reservation(run.ledger, execution.reservation)
  } else {
    @resources.settle_execution_reservation(
      run.ledger,
      execution.reservation,
      remaining_execution=execution.scratch,
    )
  }
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      execution.execution_settled = true
      (execution.hooks.unwrap().settled)()
      if execution.disposed {
        release_task_execution(run, execution)
      }
      Ok(())
    }
  }
}

///|
/// Verification, result holding and successful DAG completion are one boundary.
/// No success is exposed if the implementation cannot supply its owned output.
fn complete_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard run.running is Some((task, active)) &&
    physical_equal(active, execution) &&
    task_execution_matches(run, execution) else {
    return Err(ForeignCandidate)
  }
  if execution.disposed || !execution.execution_settled {
    return Err(Physical(InvalidCharge))
  }
  let hooks = execution.hooks.unwrap()
  match (hooks.ready)() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let holding = match
    @resources.retain_allocation(
      run.ledger,
      execution.reservation,
      execution.retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  match (hooks.finish)() {
    Ok(output) => {
      guard captured_task_target(run, task) is Some(target) &&
        @execution.completed_output_matches_port(
          output,
          run.graph.owners[task],
          target,
        ) &&
        captured_output_inputs_match(run, task, output) else {
        execution.failed_holding = Some(holding)
        fail_captured_task(run, task, ForeignCandidate)
        return Err(ForeignCandidate)
      }
      match (hooks.publish)(output) {
        Err(issue) => {
          execution.failed_holding = Some(holding)
          fail_captured_task(run, task, issue)
          return Err(issue)
        }
        Ok(_) => ()
      }
      run.completed[task] = Some(output)
      record_task_retention(run, task)
      run.resources[task].unwrap().holding = Some(holding)
      @resources.settle_reservation(run.ledger, execution.reservation) |> ignore
      clear_captured_inputs(run, task)
      run.running = None
      run.generation += 1
      Ok(())
    }
    Err(issue) => {
      execution.failed_holding = Some(holding)
      fail_captured_task(run, task, issue)
      Err(issue)
    }
  }
}

///|
fn close_task_execution(run : CapturedDAG, execution : TaskExecution) -> Unit {
  if !task_execution_matches(run, execution) || execution.disposed {
    return
  }
  if run.running is Some((_, active)) && physical_equal(active, execution) {
    stop_captured_dag(run)
  }
  execution.disposed = true
  (execution.hooks.unwrap().dispose)()
  close_captured_task_output(run, execution.task)
  if execution.execution_settled {
    release_task_execution(run, execution)
  }
}

///|
/// Private finalization only after disposal AND actual execution settlement.
/// Completed descendant holdings and already consumed transfer stay intact.
fn release_task_execution(run : CapturedDAG, execution : TaskExecution) -> Unit {
  if !execution.disposed ||
    !execution.execution_settled ||
    !task_execution_matches(run, execution) {
    return
  }
  if execution.failed_holding is Some(holding) {
    @resources.release_allocation(run.ledger, holding) |> ignore
    execution.failed_holding = None
  }
  if @resources.reservation_open(execution.reservation) {
    @resources.settle_reservation(run.ledger, execution.reservation) |> ignore
  }
  captured_cleanup_confirmed(run, execution)
  run.executions[execution.task] = None
  let hooks = execution.hooks.unwrap()
  execution.hooks = None
  (hooks.released)()
}
