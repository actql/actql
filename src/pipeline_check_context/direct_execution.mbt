///|
// Ordered first-match dispatch. Stop on either a match or an error; do not
// eagerly evaluate later checkers or turn an unresolved result into permission.
// Window/watermark candidates were already prepared under the shared budget.
fn direct_execution_candidate(
  site : OperationRequirementSite,
  policy : @policy.Policy,
  window : Result[OperationExecutionCheck?, OperationResolutionIndexIssue],
  watermark : Result[OperationExecutionCheck?, OperationResolutionIndexIssue],
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  match append_execution_check(site, policy) {
    Ok(None) => ()
    other => return other
  }
  match set_execution_check(site, policy) {
    Ok(None) => ()
    other => return other
  }
  match assertion_execution_check(site) {
    Ok(None) => ()
    other => return other
  }
  match group_execution_check(site) {
    Ok(None) => ()
    other => return other
  }
  match top_k_execution_check(site, policy) {
    Ok(None) => ()
    other => return other
  }
  match lag_execution_check(site, policy) {
    Ok(None) => ()
    other => return other
  }
  match json_pick_execution_check(site, policy) {
    Ok(None) => ()
    other => return other
  }
  match expansion_execution_check(site, policy) {
    Ok(None) => ()
    other => return other
  }
  match analytic_envelope_check(site, policy) {
    Ok(None) => ()
    other => return other
  }
  match analytic_execution_check(site) {
    Ok(None) => ()
    other => return other
  }
  match window {
    Ok(None) => ()
    other => return other
  }
  match watermark {
    Ok(None) => ()
    other => return other
  }
  match interval_execution_check(site) {
    Ok(None) => ()
    other => return other
  }
  match asof_execution_check(site) {
    Ok(None) => ()
    other => return other
  }
  match event_execution_check(site) {
    Ok(None) => ()
    other => return other
  }
  match graph_projection_execution_check(site) {
    Ok(None) => ()
    other => return other
  }
  match graph_projection_envelope_check(site, policy) {
    Ok(None) => ()
    other => return other
  }
  match graph_construction_execution_check(site, policy) {
    Ok(None) => ()
    other => return other
  }
  match graph_execution_check(site) {
    Ok(None) => ()
    other => return other
  }
  graph_resources_check(site, policy)
}
