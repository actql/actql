///|
/// Bounded DATA projection through the existing Run owner. The physical Host
/// supplies the same original row's counter/key, commits its CAS and confirms
/// current authorization before publishing any returned wire.
fn run_observation_issue_code(
  issue : @publication.RunStateObservationIssue,
) -> String {
  match issue {
    InvalidObservation => "InvalidRunStateObservation"
    ForeignRun => "ForeignRunStateObservation"
    InvalidRevision => "InvalidRunStateRevision"
    RevisionExhausted => "RunStateRevisionExhausted"
    InvalidPriorObservation => "InvalidPriorRunStateObservation"
    ObservationEncoding => "RunStateObservationEncoding"
  }
}

///|
#export_name("runStateObservationPrepare")
pub fn run_state_observation_prepare(
  wire : String,
  run_id : String,
  revision : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunStateObservation, String] {
  @publication.prepare_run_state_observation(
    wire, run_id, revision, max_bytes, max_nodes, max_depth,
  ).map_err(run_observation_issue_code)
}

///|
#export_name("runStateObservationKey")
pub fn run_state_observation_key(
  value : @publication.RunStateObservation,
) -> String {
  value.key()
}

///|
#export_name("runStateObservationNextRevision")
pub fn run_state_observation_next_revision(
  value : @publication.RunStateObservation,
  has_prior : Bool,
  prior_key : String,
  revision : Int64,
) -> Result[Int64, String] {
  value
  .next_revision(if has_prior { Some(prior_key) } else { None }, revision)
  .map_err(run_observation_issue_code)
}

///|
#export_name("runStateObservationWire")
pub fn run_state_observation_wire(
  value : @publication.RunStateObservation,
  revision : Int64,
) -> Result[String, String] {
  value.wire(revision).map_err(run_observation_issue_code)
}

///|
/// Identical stable/since decision to the existing Node caller; no new clock,
/// timer, Run state, authorization or physical cleanup is supplied by this ABI.
#export_name("runStateWaitDecision")
pub fn run_state_wait_decision(
  wire : String,
  has_since : Bool,
  since : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String {
  match
    @publication.run_wait_ready(
      wire,
      if has_since {
        Some(since)
      } else {
        None
      },
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(true) => "ready"
    Ok(false) => "pending"
    Err(@publication.InvalidSince) => "InvalidWaitRevision"
    Err(@publication.InvalidState) => "InvalidRunWaitState"
  }
}
