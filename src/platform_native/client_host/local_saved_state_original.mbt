///|
// Current authorization and retained-row custody belong to the caller. This
// consumes only its admitted state DATA; the original observation counter/key
// and control revision remain separate and must still agree exactly.
fn restore_native_saved_run_state(
  submitted : NativeClientSubmittedIntentRecord,
  run : NativeClientRunRecord,
  resolve_model_failure? : ((String, String) -> @publication.BoundModelHttpFailure?)? = None,
  resolve_dependent_model_unknown? : ((String, String) -> Bool)? = None,
) -> Result[NativeClientSavedRunState?, NativeClientRunJournalIssue] {
  guard submitted.run_state_original is Some(wire) &&
    submitted.run_state_observation is Some((revision, Some(key))) else {
    // The authenticated Run row already owns this exact Checkpoint lifecycle
    // projection. It is not a completed Result/Manifest observation and issues
    // no missing historical counter. Preserve its original optional-revision
    // wire; never substitute the SQL/control revision for an observation.
    let unobserved = match submitted.run_state_observation {
      None | Some((0L, None)) => true
      _ => false
    }
    if submitted.run_state_original is None &&
      unobserved &&
      run.checkpoint is Some(checkpoint) {
      return Ok(
        Some({
          original: None,
          state_wire: checkpoint.state.wire,
          control_revision: run.revision,
        }),
      )
    }
    return Ok(None)
  }
  let retained = match submitted.restored_state_original {
    Some(original) => {
      if !original.matches(run.definition, wire, revision, key) {
        return Err(CustodyLost)
      }
      original
    }
    // Separate legacy/maintenance constructors have no retained snapshot.
    // Their original bounded reader remains mandatory, without recapture.
    None =>
      match
        @host.admit_client_retained_run_state_original(
          run.definition,
          wire,
          revision,
          key,
        ) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
  }
  let state = match
    retained.resolve(resolve_model_failure~, resolve_dependent_model_unknown~) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  Ok(
    Some({
      original: Some(state),
      state_wire: state.state_wire(),
      control_revision: run.revision,
    }),
  )
}
