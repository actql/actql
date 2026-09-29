///|
/// Construct a realization request from the exact completed predecessors of the
/// checked-ready task. No generated sequence or provider preparation is needed
/// to identify ports. The bounded handle array does not copy retained row data.
pub fn prepare_dispatch_inputs(
  driver : DispatchDriver,
  task : Int,
  revision : @strategy.StrategyRevision,
  capacity : @connector.FixedComputeCapacity,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[@connector.FixedComputeRequest, DispatchIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(Candidate(InvalidLimits))
  }
  let run = driver.owner.run
  if @strategy.next_captured_task(run) != Some(task) ||
    !(@strategy.captured_dag_strategy(run) is Some(current) &&
    physical_equal(current, revision)) {
    return Err(StaleTask)
  }
  match @resources.charge_planning(@strategy.captured_dag_ledger(run), 1) {
    Err(issue) => return Err(Run(Physical(issue)))
    Ok(_) => ()
  }
  let owner = @strategy.graph_task_owner(
    @strategy.captured_dag_graph(run),
    task,
  ).unwrap()
  // A selected task receives its checked operation ports, which can differ
  // from the enclosing Stage's authored input count.
  let count = @strategy.graph_task_input_count(
    @strategy.captured_dag_graph(run),
    task,
  ).unwrap()
  let inputs = []
  for port in 0..<count {
    match
      @strategy.captured_task_input(
        run,
        task,
        max_entries,
        max_name_bytes,
        input_index=port,
      ) {
      Ok(input) => inputs.push(input)
      Err(issue) => return Err(Run(issue))
    }
  }
  let prepared = match
    @strategy.graph_task_selected_step(@strategy.captured_dag_graph(run), task) {
    Some(step) =>
      @connector.prepare_selected_fixed_compute_request(
        owner, step, inputs, capacity,
      )
    None =>
      if count == 0 {
        @connector.prepare_source_free_fixed_compute_request(owner, capacity)
      } else {
        @connector.prepare_fixed_compute_request(inputs, capacity)
      }
  }
  prepared.map_err(issue => Candidate(issue))
}
