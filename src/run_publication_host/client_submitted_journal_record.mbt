///|
/// Decoded original row fields, not a committed admission or Run authority.
/// The retained Run, complete inventories, authenticated epoch and physical
/// transaction must still be checked by their existing Owners.
pub(all) struct ClientSubmittedJournalEncoding {
  reference : ClientSubmissionReferenceRecord
  intent : ClientSubmittedIntent
  run_admission : (ClientRequestIdentity, String, Int64)?
  run_state_original : String?
  // Original public observation counter/key, separate from SQL/control CAS.
  // None is historical absence, not a newly issued zero-counter row.
  run_state_observation : (Int64, String?)?
  // An existing accepted preparation terminal; never a Run admission.
  preparation_problem : (String, String)?
}

///|
/// Preserve the original Native submitted-row reader, caps and exact bytes.
pub fn decode_client_submitted_journal_row(
  body : Bytes,
) -> Result[ClientSubmittedJournalEncoding, ClientJournalDecodingIssue] {
  let source = @source.parse_json_bytes_preserving(body, {
    max_input_bytes: 262144,
    max_nodes: 16,
    max_depth: 2,
  }).to_option()
  guard source is Some(source) &&
    @decode.admit(source, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: 131072,
      max_total_string_bytes: 262144,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "intent", "phase", "preparation_problem_classification", "preparation_problem_code",
      "reference", "run_admission", "run_state_key", "run_state_original", "run_state_revision",
      "version",
    ])
    is Ok(object) else {
    return Err(CustodyLost)
  }
  let text = key => {
    @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
  }
  guard text("version") == Some("actql-native-client-submitted-intent-row/0.1") &&
    text("phase") is Some(phase) &&
    text("reference") is Some(reference_wire) &&
    text("intent") is Some(intent_wire) else {
    return Err(CustodyLost)
  }
  let reference = match
    admit_client_submission_reference_record(reference_wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let intent = match
    prepare_client_submitted_intent(intent_wire, 65536, 65536, 64) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let run_admission = match @decode.lookup(object, "run_admission") {
    None => None
    Some(value) => {
      guard @decode.text(value) is Ok(wire) else { return Err(CustodyLost) }
      match admit_client_submitted_run_admission_wire(wire) {
        Ok(value) => Some(value)
        Err(_) => return Err(CustodyLost)
      }
    }
  }
  let run_state_original = match @decode.lookup(object, "run_state_original") {
    None => None
    Some(value) =>
      match @decode.text(value) {
        Ok(wire) if run_admission is Some(_) => Some(wire)
        _ => return Err(CustodyLost)
      }
  }
  let run_state_observation = match
    (
      @decode.lookup(object, "run_state_revision"),
      @decode.lookup(object, "run_state_key"),
    ) {
    (None, None) => None
    (Some(counter), Some(key)) => {
      let revision = match @decode.safe_integer(counter) {
        Ok(value) if value >= 0L => value
        _ => return Err(CustodyLost)
      }
      let key = if @decode.is_null(key) {
        None
      } else {
        match @decode.text(key) {
          Ok(value) => Some(value)
          _ => return Err(CustodyLost)
        }
      }
      Some((revision, key))
    }
    _ => return Err(CustodyLost)
  }
  let preparation_problem = match
    (
      @decode.lookup(object, "preparation_problem_code"),
      @decode.lookup(object, "preparation_problem_classification"),
    ) {
    (None, None) => None
    (Some(code), Some(classification)) => {
      guard @decode.text(code) is Ok(code) &&
        @decode.text(classification) is Ok(classification) else {
        return Err(CustodyLost)
      }
      Some((code, classification))
    }
    _ => return Err(CustodyLost)
  }
  let expected_phase = if run_admission is Some(_) {
    "ready"
  } else if preparation_problem is Some(_) {
    "preparation_failed"
  } else {
    "preparing"
  }
  if phase != expected_phase ||
    !client_submitted_intent_transition(phase, phase) {
    return Err(CustodyLost)
  }
  match
    client_submitted_intent_journal_row_body(
      client_submission_reference_record_wire(reference),
      intent,
      run_admission~,
      run_state_original~,
      run_state_observation~,
      preparation_problem~,
    ) {
    Ok(original) if original == body =>
      Ok({
        reference,
        intent,
        run_admission,
        run_state_original,
        run_state_observation,
        preparation_problem,
      })
    _ => Err(CustodyLost)
  }
}

///|
/// The original retained-admission relationship used by Native and portable
/// Hosts. Actual rows and revisions come from the same physical snapshot.
/// This does not validate nested Run originals, a complete journal, current
/// authority, a COMMIT acknowledgement or permission to start/retry.
pub fn validate_client_submitted_retained_run(
  reference : ClientSubmissionReferenceRecord,
  admission : (ClientRequestIdentity, String, Int64),
  retained_request : ClientRequestIdentity,
  retained_definition : @publication.PublicationContract,
  retained_revision : Int64,
) -> Result[Unit, ClientJournalDecodingIssue] {
  let (request, definition_cid, admitted_revision) = admission
  if !client_submission_reference_matches_request(reference, request) ||
    client_request_identity_relation(request, retained_request) != SameRequest ||
    @publication.publication_contract_name(retained_definition) !=
    "run_definition" ||
    @publication.publication_contract_identity(retained_definition) !=
    definition_cid ||
    admitted_revision < 0L ||
    retained_revision < admitted_revision {
    return Err(CustodyLost)
  }
  Ok(())
}
