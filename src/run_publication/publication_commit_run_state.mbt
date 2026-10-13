///|
pub(all) enum ObservedPublicationRunStateIssue {
  Commit(PublicationCommitIssue)
  Projection(DeliveryIssuanceIssue)
  State(RunStateIssue)
} derive(Eq, Debug)

///|
/// Project the original completed computation after full stored-chain validation.
/// This is a read-only Run observation, not Store ACK, cleanup, read authority or
/// a new publication. The trusted Host separately fences the actual same Store,
/// six physical facts, current publisher and current Run-read Account permission.
/// Result availability remains unknown until its independent read/retention
/// Owners observe current facts; a committed index alone cannot mark it available.
pub fn PublicationCommitPreparation::observed_run_state_wire(
  preparation : PublicationCommitPreparation,
  view : PublicationCommitReadView,
  observed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ObservedPublicationRunStateIssue] {
  let inputs = match preparation.read_view_inputs(view) {
    Ok(inputs) => inputs
    Err(issue) => return Err(Commit(issue))
  }
  // This admits neither a candidate index nor an action code as stored proof.
  match preparation.finish_observed_commit(view) {
    Ok(_) => ()
    Err(issue) => return Err(Commit(issue))
  }
  let computation = inputs.computation
  let run_id = match run_definition_run_id(computation.run_definition) {
    Ok(value) => value
    Err(issue) => return Err(Projection(issue))
  }
  let names = match manifest_result_names(computation.manifest) {
    Ok(value) => value
    Err(issue) => return Err(Projection(issue))
  }
  let observations = names.map(name => {
    name,
    state: ResultAvailabilityState::Unknown,
    reason: ResultAvailabilityReason::VerificationPending,
  })
  issue_succeeded_run_state(
    run_id,
    observed_at,
    names,
    observations,
    names.map(_ => observed_at),
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => State(issue))
}
