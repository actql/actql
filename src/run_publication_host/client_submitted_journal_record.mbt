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
/// Construction observations only, not admission, a decoded value or authority.
/// Parse covers the existing full parser limits. Canonical uses measurements
/// from that SAME completed preserving parse, without another sizing traversal.
pub(all) enum ClientSubmittedJournalConstruction {
  SubmittedJournalParse(Int)
  SubmittedJournalCanonical(Int, Int64, Int, Int)
}

///|
/// Legacy callers retain their original finite profile. A physical caller
/// selecting observed extents must back every construction before it starts;
/// the observer can refuse resources but cannot replace any codec validation.
pub fn decode_client_submitted_journal_row(
  body : Bytes,
  before_construction? : ((ClientSubmittedJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
) -> Result[ClientSubmittedJournalEncoding, ClientJournalDecodingIssue] {
  if before_construction is Some(reserve) {
    match reserve(SubmittedJournalParse(body.length())) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  decode_client_submitted_journal_row_profile(
    body,
    before_construction is Some(_),
    before_construction~,
  )
}

///|
// One codec implementation for the explicit finite profile and the observed
// row profile. The public observer is resource preparation, not validation:
// the enclosing Native caller backs parsing and then the measured canonical
// construction before each phase. Both routes keep the same full codec law.
fn decode_client_submitted_journal_row_profile(
  body : Bytes,
  observed : Bool,
  before_construction? : ((ClientSubmittedJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
) -> Result[ClientSubmittedJournalEncoding, ClientJournalDecodingIssue] {
  let row_bytes = if observed { body.length() } else { 262144 }
  if row_bytes <= 0 || row_bytes >= 2147483519 {
    return Err(CustodyLost)
  }
  let source = @source.parse_json_bytes_preserving(body, {
    max_input_bytes: row_bytes,
    max_nodes: 16,
    max_depth: 2,
  }).to_option()
  guard source is Some(source) &&
    @decode.admit(source, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: if observed {
        row_bytes
      } else {
        131072
      },
      max_total_string_bytes: row_bytes,
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
  // Only the original intent's bound changes in the observed profile. Keep
  // every other original field's finite string obligation; a larger intent
  // must not silently widen the retained Run/control schema.
  let mut other_text_units = 0L
  if observed {
    for
      key in [
        "phase", "preparation_problem_classification", "preparation_problem_code",
        "reference", "run_admission", "run_state_key", "run_state_original", "version",
      ] {
      if @decode.lookup(object, key) is Some(value) &&
        @decode.text(value) is Ok(text) {
        if @scalar.admit_utf8_length(text, 131072) is Err(_) {
          return Err(CustodyLost)
        }
        // Fixed closed-row fields, not a second input sizing traversal.
        other_text_units += text.length().to_int64()
      }
    }
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
  let intent = match before_construction {
    Some(reserve) =>
      match
        restore_observed_client_submitted_intent(
          intent_wire, row_bytes, other_text_units, reserve,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    None =>
      match
        prepare_client_submitted_intent(
          intent_wire,
          if observed {
            row_bytes
          } else {
            65536
          },
          65536,
          64,
        ) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
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
      // Canonical comparison belongs to the SAME enclosing codec lifetime,
      // not a second independently admitted construction or current callback.
      before_construction=if observed {
        Some((_, _, _) => Ok(()))
      } else {
        None
      },
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

///|
// Reuse the preserving parser's own completed measurements. Literal JSON has
// different number semantics, so it is deliberately not substituted here.
fn restore_observed_client_submitted_intent(
  wire : String,
  row_bytes : Int,
  other_text_units : Int64,
  reserve : (ClientSubmittedJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ],
) -> Result[ClientSubmittedIntent, ClientJournalDecodingIssue] {
  let parser = match
    @source.start_json_parse(
      wire,
      { max_input_bytes: row_bytes, max_nodes: 65536, max_depth: 64, },
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let parsed = while true {
    match @source.advance_json_parse(parser, 65536) {
      Ok(@source.JsonParseContinue(_)) => continue
      Ok(@source.JsonParseComplete(value, ..)) => break value
      _ => return Err(CustodyLost)
    }
  } nobreak {
    return Err(CustodyLost)
  }
  match
    reserve(
      SubmittedJournalCanonical(
        row_bytes,
        // The complete parsed intent's canonical wire cannot exceed its
        // original byte count on an accepted exact-row comparison. Larger
        // transient candidates remain execution scratch and still refuse.
        parsed.usage.input_bytes.to_int64() + 2L * other_text_units,
        parsed.usage.nodes,
        parsed.usage.depth,
      ),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let value = @canonical.from_source(
    parsed.node,
    65536,
    64,
    row_bytes,
    data_keys=true,
  ) catch {
    _ => return Err(CustodyLost)
  }
  prepare_client_submitted_intent_value(value, row_bytes, 65536, 64).map_err(_ => {
    CustodyLost
  })
}
