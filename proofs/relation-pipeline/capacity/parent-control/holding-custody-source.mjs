// Reviewed production ownership boundaries. Whitespace/comments may vary;
// altered guards, publication, parent retention or release ordering require review.
import assert from 'node:assert/strict';
import {blockAfter} from './driver-retirement-source.mjs';
const normalize=s=>s.replace(/\/\/[^\n]*/g,'').replace(/\s+/g,'').replace(/,\)/g,')');
const reviewed = [
  {path:"src/physical_resources/ledger.mbt", anchor:"pub fn retain_allocation(", body:`{
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if reservation.completed_output is Some(_) {
    return Err(ClosedReservation)
  }
  if bytes < 0L {
    return Err(InvalidCharge)
  }
  if bytes > reservation.retention {
    return Err(RetentionLimit)
  }
  let u = ledger.usage
  if u.holdings >= ledger.limits.holdings - ledger.delegated_holdings {
    return Err(HoldingLimit)
  }
  reservation.retention -= bytes
  ledger.usage = {
    ..u,
    holdings: u.holdings + 1,
    reserved_retention_bytes: u.reserved_retention_bytes - bytes,
    held_bytes: u.held_bytes + bytes,
  }
  Ok({
    owner: ledger,
    serial: u.holdings,
    reservation_serial: reservation.serial,
    bytes,
    live: true,
  })
}`},
  {path:"src/physical_resources/ledger.mbt", anchor:"pub fn release_allocation(", body:`{
  if !physical_equal(ledger, holding.owner) {
    return Err(ForeignOwner)
  }
  if !holding.live {
    return Err(ClosedHolding)
  }
  ledger.usage = {
    ..ledger.usage,
    held_bytes: ledger.usage.held_bytes - holding.bytes,
  }
  holding.live = false
  Ok(())
}`},
  {path:"src/physical_strategy/retention.mbt", anchor:"fn collect_captured_retention(", body:`{
  // Backward edges ensure one descending pass releases newly unreferenced
  // ancestors. This traversal is bounded by the checked graph's task limit.
  for task = run.resources.length() - 1; task >= 0; task = task - 1 {
    guard !run.lifetimes[task].live &&
      run.lifetimes[task].pins == 0 &&
      run.resources[task] is Some(resource) else {
      continue
    }
    let mut needed = false
    if run.executions[task] is Some(execution) &&
      (!execution.disposed || !task_execution_retention_released(execution)) {
      needed = true
    }
    for child in run.resources {
      if child is Some(child) && child.parents.contains(task) {
        needed = true
      }
    }
    if run.running is Some((active, _)) &&
      run.graph.data.any(edge => {
        edge.consumer == active && edge.producer == task
      }) {
      needed = true
    }
    if !needed && (resource.release_confirmed)() {
      if resource.holding is Some(holding) {
        @resources.release_allocation(run.ledger, holding) |> ignore
      }
      run.resources[task] = None
    }
  }
}`},
  {path:"src/physical_strategy/task_completion.mbt", anchor:"fn commit_task_output(", body:`{
  if run.stopped {
    return Err(Stopped)
  }
  guard task >= captured_compute_first_task(run) &&
    task < run.outputs.length() &&
    !run.done[task] &&
    run.outputs[task] is None &&
    run.resources[task] is None else {
    return Err(ForeignCandidate)
  }
  if holding is Some(value) && !@resources.holding_available(run.ledger, value) {
    return Err(Physical(InvalidCharge))
  }
  match
    @resources.settle_completed_output_reservation(
      run.ledger,
      reservation,
      holding,
      output_bytes,
      remaining_execution,
    ) {
    Err(issue) => return Err(Physical(issue))
    Ok(_) => ()
  }
  run.resources[task] = Some({
    holding,
    release_confirmed: fn() { true },
    parents: task_parents(run, task),
  })
  run.outputs[task] = Some(output)
  run.done[task] = true
  clear_captured_inputs(run, task)
  run.generation += 1
  Ok(())
}`},
  {path:"src/physical_strategy/task_completion.mbt", anchor:"pub fn[T] complete_managed_task_execution_with_inputs(", body:`{
  if run.stopped {
    return Err(Stopped)
  }
  guard run.running is Some((task, active)) &&
    physical_equal(active, execution) &&
    task_execution_matches(run, execution) else {
    return Err(ForeignCandidate)
  }
  if execution.disposed ||
    !execution.execution_settled ||
    execution.resident is Some(_) ||
    !numeric_reductions_ready_for_completion(
      execution.numeric.length(),
      execution.numeric_sealed,
    ) {
    return Err(Physical(InvalidCharge))
  }
  match task_execution_ready(execution) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard captured_task_target(run, task) is Some(target) &&
    @execution.managed_completed_output_matches_port(
      output,
      run.graph.owners[task],
      target,
    ) &&
    @execution.managed_completed_output_matches_attempt(
      output,
      execution.attempt,
    ) else {
    return Err(ForeignCandidate)
  }
  let input_matches = match managed_inputs {
    Some(inputs) =>
      admitted_managed_inputs_match(execution, inputs) &&
      @execution.managed_completed_output_matches_common_inputs(output, inputs)
    None => {
      let inputs = []
      for input in run.inputs[task] {
        guard input is Some(input) else { return Err(ForeignCandidate) }
        inputs.push(input)
      }
      @execution.managed_completed_output_matches_inputs(output, inputs)
    }
  }
  if !input_matches {
    return Err(ForeignCandidate)
  }
  guard @execution.managed_completed_output_storage_bytes(output)
    is Some(storage_bytes) else {
    return Err(MissingOutput)
  }
  let holding = if storage_bytes == 0L {
    if allocation is Some(_) {
      return Err(Physical(InvalidCharge))
    }
    None
  } else {
    guard allocation is Some(owned) &&
      owned.live &&
      physical_equal(owned.owner, run) &&
      physical_equal(owned.execution, execution) &&
      owned.bytes == storage_bytes &&
      @resources.holding_available(run.ledger, owned.holding) else {
      return Err(Physical(InvalidCharge))
    }
    Some(owned.holding)
  }
  if run.stopped || !@execution.managed_completed_output_available(output) {
    return Err(if run.stopped { Stopped } else { MissingOutput })
  }
  match
    commit_task_output(
      run,
      task,
      Managed(@execution.managed_completed_reference(output)),
      holding,
      execution.reservation,
      storage_bytes,
      task_output_remaining_scratch(execution),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if allocation is Some(owned) {
    // Ownership moved to the graph's retained task resource. The old Host
    // token can no longer release it independently.
    owned.live = false
  }
  execution.retained_bytes = None
  run.running = None
  Ok(())
}`},
]
export function checkHoldingCustodySource(read) {
  for (const {path,anchor,body} of reviewed)
    assert.equal(normalize(blockAfter(read(path).toString(),anchor)),normalize(body),'Changed reviewed holding custody boundary '+anchor);
  return {scope:'managed completion token transfer, Ledger retain/release and captured parent retention',wholePhysicalLifetimeUpper:false};
}
