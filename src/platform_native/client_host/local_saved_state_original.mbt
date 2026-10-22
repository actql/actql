///|
// The shared reader already restored this exact immutable observed state while
// joining the original Submission and Run. Preserve that result rather than
// parsing its same envelope, Manifest and state a second time.
fn native_saved_submission_state(
  snapshot : @host.ClientSavedSubmissionSnapshot,
) -> (String, @host.ClientRunStateOriginal)? {
  let record = @host.client_saved_submission_record(snapshot)
  match
    (
      record.run_admission,
      @host.client_saved_submission_state_original(snapshot),
    ) {
    (Some((_, definition_cid, _)), Some(state)) => Some((definition_cid, state))
    _ => None
  }
}

///|
// Current authorization and retained-row custody belong to the caller. This
// consumes only its admitted state DATA; the original observation counter/key
// and control revision remain separate and must still agree exactly.
fn restore_native_saved_run_state(
  submitted : NativeClientSubmittedIntentRecord,
  run : NativeClientRunRecord,
) -> Result[NativeClientSavedRunState?, NativeClientRunJournalIssue] {
  guard submitted.run_state_original is Some(wire) &&
    submitted.run_state_observation is Some((revision, Some(key))) else {
    return Ok(None)
  }
  let state = match submitted.restored_state_original {
    Some((definition_cid, original)) => {
      if definition_cid !=
        @publication.publication_contract_identity(run.definition) ||
        original.wire() != wire {
        return Err(CustodyLost)
      }
      original
    }
    // Separate legacy/maintenance constructors have no retained snapshot.
    // Their original bounded reader remains mandatory, without recapture.
    None =>
      match @host.restore_client_run_state_original(run.definition, wire) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
  }
  let observation = match native_saved_state_observation(run, state, revision) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if observation.key() != key ||
    observation.wire(revision).to_option() != Some(state.state_wire()) {
    return Err(CustodyLost)
  }
  Ok(Some({ original: state, control_revision: run.revision, }))
}
