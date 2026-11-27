///|
/// Candidate metadata for the same authenticated submitted row. Neither its
/// bytes nor its revision is a COMMIT acknowledgement or execution permission.
pub struct ClientSavedRunStateUpdate {
  request : ClientRequestIdentity
  definition_cid : String
  key : String
  prior_revision : Int64
  prior_body : Bytes
  revision : Int64
  body : Bytes
  state_wire : String
}

///|
pub(all) enum ClientSavedRunStateUpdateIssue {
  OriginalUnavailable
  ForeignRun
  RevisionExhausted
  Observation(@publication.RunStateObservationIssue)
  State(ClientJournalDecodingIssue)
  Encoding(ClientJournalEncodingIssue)
} derive(Eq, Debug)

///|
/// The snapshot is issued by the existing original Submission/Run reader.
/// The physical Host must retain the same authenticated Store/current frame,
/// atomically CAS this row, and confirm that exact saved row before exposure.
pub fn prepare_client_saved_run_state_update(
  snapshot : ClientSavedSubmissionSnapshot,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  state_wire : String,
) -> Result[ClientSavedRunStateUpdate, ClientSavedRunStateUpdateIssue] {
  prepare_client_run_state_update_body(
    snapshot,
    request,
    definition,
    Some(manifest),
    state_wire,
  )
}

///|
/// The same authenticated observation CAS for unpublished metadata. This
/// neither invents a successful Manifest nor bypasses original row currentness.
pub fn prepare_client_unpublished_run_state_update(
  snapshot : ClientSavedSubmissionSnapshot,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  state_wire : String,
) -> Result[ClientSavedRunStateUpdate, ClientSavedRunStateUpdateIssue] {
  prepare_client_run_state_update_body(
    snapshot,
    request,
    definition,
    None,
    state_wire,
  )
}

///|
fn prepare_client_run_state_update_body(
  snapshot : ClientSavedSubmissionSnapshot,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  manifest : @publication.PublicationContract?,
  state_wire : String,
) -> Result[ClientSavedRunStateUpdate, ClientSavedRunStateUpdateIssue] {
  guard snapshot.inspection is Some(original) &&
    snapshot.run is Some(_) &&
    snapshot.record.run_admission is Some(_) else {
    return Err(OriginalUnavailable)
  }
  let definition_cid = @publication.publication_contract_identity(definition)
  if client_request_identity_relation(original.request, request) != SameRequest ||
    @publication.publication_contract_identity(original.definition) !=
    definition_cid {
    return Err(ForeignRun)
  }
  // Absence is historical absence, never issuance of a new zero counter.
  guard snapshot.record.run_state_observation is Some((revision, prior_key)) else {
    return Err(OriginalUnavailable)
  }
  let run_id = match @publication.run_definition_run_id(definition) {
    Ok(value) => value
    Err(_) => return Err(ForeignRun)
  }
  let prior = match (prior_key, snapshot.record.run_state_original) {
    (None, None) if revision == 0L => {
      guard snapshot.state_original is None else {
        return Err(OriginalUnavailable)
      }
      None
    }
    (Some(key), Some(wire)) => {
      // The snapshot reader has already authenticated and restored this exact
      // state under its checked Definition. Keep that backing through CAS.
      guard snapshot.state_original is Some(retained) &&
        retained.matches(definition, wire, revision, key) &&
        retained.resolve() is Ok(state) else {
        return Err(OriginalUnavailable)
      }
      let same_manifest = match (state.original_manifest(), manifest) {
        (None, _) => true
        (Some(_), None) => false
        (Some(original), Some(candidate)) =>
          @publication.publication_contract_json(original) ==
          @publication.publication_contract_json(candidate)
      }
      if !same_manifest {
        return Err(ForeignRun)
      }
      Some(state)
    }
    _ => return Err(OriginalUnavailable)
  }
  let observation = match
    @publication.prepare_run_state_observation(
      state_wire, run_id, revision, 65536, 8192, 64,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let next = match observation.next_revision(prior_key, revision) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  // Reobserving the same fact retains its exact durable original. Clock-only
  // changes do not create another metadata write or observation revision.
  if next == revision && prior is Some(state) {
    return Ok({
      request,
      definition_cid,
      key: snapshot.submission.key,
      prior_revision: snapshot.submission.revision,
      prior_body: snapshot.submission.body,
      revision: snapshot.submission.revision,
      body: snapshot.submission.body,
      state_wire: state.state_wire(),
    })
  }
  if snapshot.submission.revision == 9223372036854775807L {
    return Err(RevisionExhausted)
  }
  let wire = match observation.wire(next) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let prepared = match manifest {
    Some(manifest) =>
      prepare_client_run_state_original(definition, manifest, wire)
    None => prepare_client_unpublished_run_state_original(definition, wire)
  }
  let state = match prepared {
    Ok(value) => value
    Err(issue) => return Err(State(issue))
  }
  if prior is Some(original) &&
    (
      original.status == @publication.Succeeded ||
      original.status == @publication.Failed ||
      original.status == @publication.Cancelled
    ) &&
    original.status != state.status {
    return Err(ForeignRun)
  }
  let record = snapshot.record
  let body = match
    client_submitted_intent_journal_row_body(
      client_submission_reference_record_wire(record.reference),
      record.intent,
      run_admission=record.run_admission,
      run_state_original=Some(state.wire()),
      run_state_observation=Some((next, Some(observation.key()))),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  Ok({
    request,
    definition_cid,
    key: snapshot.submission.key,
    prior_revision: snapshot.submission.revision,
    prior_body: snapshot.submission.body,
    revision: snapshot.submission.revision + 1L,
    body,
    state_wire: state.state_wire(),
  })
}

///|
pub fn client_saved_run_state_update_row(
  update : ClientSavedRunStateUpdate,
) -> (String, Int64, Int64, Bytes) {
  (update.key, update.prior_revision, update.revision, update.body)
}

///|
/// Candidate wire only. Exposure still requires exact same-row confirmation.
pub fn client_saved_run_state_update_candidate_wire(
  update : ClientSavedRunStateUpdate,
) -> String {
  update.state_wire
}

///|
/// Recheck the exact original row inside the physical write transaction. Its
/// metadata CAS never updates the accepted Run/control revision or dispatch.
pub fn validate_client_saved_run_state_update_original(
  update : ClientSavedRunStateUpdate,
  snapshot : ClientSavedSubmissionSnapshot,
) -> Result[Unit, ClientSavedRunStateUpdateIssue] {
  guard snapshot.inspection is Some(original) && snapshot.run is Some(_) else {
    return Err(OriginalUnavailable)
  }
  if client_request_identity_relation(update.request, original.request) !=
    SameRequest ||
    @publication.publication_contract_identity(original.definition) !=
    update.definition_cid {
    return Err(ForeignRun)
  }
  if snapshot.submission.key != update.key ||
    snapshot.submission.revision != update.prior_revision ||
    snapshot.submission.body != update.prior_body {
    return Err(OriginalUnavailable)
  }
  Ok(())
}

///|
/// Confirm only the actual original row read after its physical commit. A
/// candidate, scalar success, different row or later equivalent key is no ACK.
pub fn confirm_client_saved_run_state_update(
  update : ClientSavedRunStateUpdate,
  snapshot : ClientSavedSubmissionSnapshot,
) -> Result[String, ClientSavedRunStateUpdateIssue] {
  guard snapshot.inspection is Some(original) && snapshot.run is Some(_) else {
    return Err(OriginalUnavailable)
  }
  if client_request_identity_relation(update.request, original.request) !=
    SameRequest ||
    @publication.publication_contract_identity(original.definition) !=
    update.definition_cid {
    return Err(ForeignRun)
  }
  if snapshot.submission.key != update.key ||
    snapshot.submission.revision != update.revision ||
    snapshot.submission.body != update.body {
    return Err(OriginalUnavailable)
  }
  Ok(update.state_wire)
}
