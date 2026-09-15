///|
priv struct PublicationScope {
  mut active : Bool
  mut claimed : Bool
}

///|
/// Constructed only after common port/input/holding verification. A connector
/// publication hook cannot exchange the output or keep publication authority
/// after returning. No public constructor or output getter is provided.
struct TaskPublication {
  owner : StrategyOfferOwner
  task : Int
  holding : @resources.Holding
  scope : PublicationScope
  mut output : @execution.CompletedOutput?
}

///|
fn claim_publication_scope(scope : PublicationScope) -> Bool {
  if !scope.active || scope.claimed {
    return false
  }
  scope.claimed = true
  true
}

///|
fn close_publication_scope(scope : PublicationScope) -> Unit {
  scope.active = false
}

///|
fn claim_task_publication(
  run : CapturedDAG,
  task : Int,
  publication : TaskPublication,
) -> @execution.CompletedOutput? {
  if run.stopped ||
    !physical_equal(run.offer_owner, publication.owner) ||
    task != publication.task ||
    !@resources.holding_available(run.ledger, publication.holding) ||
    !claim_publication_scope(publication.scope) {
    return None
  }
  publication.output
}

///|
/// The common success boundary for synchronous and asynchronous realizations.
/// This stays private: the caller must already own a verified execution and its
/// allocation. Connector-specific publication runs only after exact output-port
/// and input-binding checks, and cannot expose a DAG success without retention.
fn publish_task_completion(
  run : CapturedDAG,
  task : Int,
  output : @execution.CompletedOutput,
  holding : @resources.Holding,
  mismatch : RunIssue,
  publish : (TaskPublication) -> Result[Unit, RunIssue],
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard captured_task_target(run, task) is Some(target) &&
    @execution.completed_output_matches_port(
      output,
      run.graph.owners[task],
      target,
    ) &&
    captured_output_inputs_match(run, task, output) else {
    return Err(mismatch)
  }
  if !@resources.holding_available(run.ledger, holding) {
    return Err(Physical(InvalidCharge))
  }
  let publication = {
    owner: run.offer_owner,
    task,
    holding,
    scope: { active: true, claimed: false, },
    output: Some(output),
  }
  let published = publish(publication)
  close_publication_scope(publication.scope)
  publication.output = None
  match published {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if run.stopped {
    return Err(Stopped)
  }
  if !@resources.holding_available(run.ledger, holding) {
    return Err(Physical(InvalidCharge))
  }
  // No connector callback or fallible operation splits retention attachment
  // from success. Completed descendants do not borrow upstream availability.
  run.resources[task] = Some({
    holding: Some(holding),
    parents: task_parents(run, task),
  })
  run.completed[task] = Some(output)
  run.done[task] = true
  clear_captured_inputs(run, task)
  run.generation += 1
  Ok(())
}
