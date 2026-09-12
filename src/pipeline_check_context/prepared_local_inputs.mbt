///|
pub enum PreparedLocalInputsIssue {
  InvalidLimits
  MissingEnvironment
  MissingStage(Int)
  BudgetExceeded
  Inputs(ReconciledIssue)
}

///|
/// Consume only registrations retained by this wiring's own preparation. Never
/// re-admit equal-shaped inputs or accept a second Environment at this join.
pub fn attach_prepared_local_inputs(
  wired : WiredStages,
  max_work~ : Int,
  max_text_bytes~ : Int,
  max_local_input_nodes~ : Int,
) -> Result[ReconciledContexts, PreparedLocalInputsIssue] {
  if max_work < 0 || max_text_bytes < 0 || max_local_input_nodes < 0 {
    return Err(InvalidLimits)
  }
  let snapshots = match @stage_results.wiring_local_environment(wired.wiring) {
    Some(v) => v
    None => return Err(MissingEnvironment)
  }
  let count = wired.stages.contexts.length()
  let prior = @local_inputs.program_environment_usage(snapshots)
  if wired.work > max_work ||
    count > max_work - wired.work ||
    prior.work > max_work - wired.work - count ||
    wired.text > max_text_bytes ||
    prior.text_bytes > max_text_bytes - wired.text ||
    prior.nodes > max_local_input_nodes {
    return Err(BudgetExceeded)
  }
  let locals = []
  for i in 0..<count {
    match @stage_results.wiring_reconciled_input_at(wired.wiring, i) {
      Some(v) => locals.push(v)
      None => return Err(MissingStage(i))
    }
  }
  match
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      max_work=max_work - count,
      max_text_bytes~,
      max_local_input_nodes~,
    ) {
    Err(e) => Err(Inputs(e))
    Ok(v) => Ok({ ..v, usage: { ..v.usage, work: v.usage.work + count, }, })
  }
}
