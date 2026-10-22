///|
/// Existing submitted-intent journal decision over one original transaction.
/// This is a physical write candidate, never admission, dispatch or COMMIT ACK.
pub struct ClientSubmittedJournalAppend {
  key : String
  body : Bytes
  issued_revision : Int64
  issued_body : Bytes
}

///|
pub(all) enum ClientSubmittedJournalAppendPlan {
  Retained(ClientSavedSubmissionSnapshot)
  Append(ClientSubmittedJournalAppend)
}

///|
pub(all) enum ClientSubmittedJournalAppendIssue[E] {
  Observation(E)
  ChangedIntent
  EpochRejected(SubmissionEpochValidity)
  CapacityExceeded
  Encoding(ClientJournalEncodingIssue)
}

///|
/// Project the same original issued-row CAS and preparing-row insertion.
/// Both writes must share the original physical transaction and current fence.
pub fn client_submitted_journal_append_rows(
  value : ClientSubmittedJournalAppend,
) -> (String, Bytes, Int64, Bytes) {
  (value.key, value.body, value.issued_revision, value.issued_body)
}

///|
/// Delegate the original Native record_submitted_intent decision. The Host
/// authenticates the original epoch/current scope before entering its same
/// transaction. Ports observe actual original rows; query failure is Err, not
/// NotFound. No input checking, Run preparation, write, resend or execution runs.
pub fn[E] prepare_client_submitted_journal_append(
  reference : ClientSubmissionReferenceRecord,
  intent : ClientSubmittedIntent,
  validity : SubmissionEpochValidity,
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_submission : (ClientJournalPhysicalRow) -> Result[
    ClientSubmittedJournalEncoding,
    E,
  ],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
) -> Result[
  ClientSubmittedJournalAppendPlan,
  ClientSubmittedJournalAppendIssue[E],
] {
  match journal_issuance_anchor("client_submitted_intent_custody", max_records, read, custody_lost) {
    Ok(_) => ()
    Err(issue) => return Err(Observation(issue))
  }
  match
    read_client_saved_submission(reference, read, validate_run, custody_lost) {
    Ok(Some(snapshot)) => {
      if client_submitted_intent_cid(snapshot.record.intent) !=
        client_submitted_intent_cid(intent) {
        return Err(ChangedIntent)
      }
      return Ok(Retained(snapshot))
    }
    Ok(None) => ()
    Err(issue) => return Err(Observation(issue))
  }
  let (count, retained_bytes, revision) = match
    inspect_client_submitted_journal_inventory(
      max_records, scan, read, validate_submission, custody_lost,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  // The original Native order preserves retained identity after expiry; only
  // an actually missing original intent may reach this fresh-insertion check.
  if validity != @request_scope.Admissible {
    return Err(EpochRejected(validity))
  }
  let bytes = @utf8.encode(client_submitted_intent_wire(intent))
    .length()
    .to_int64()
  if count == max_records || bytes > 67108864L - retained_bytes {
    return Err(CapacityExceeded)
  }
  let body = match
    client_submitted_intent_journal_row_body(
      client_submission_reference_record_wire(reference),
      intent,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  Ok(
    Append({
      key: client_submission_reference_record_request_id(reference),
      body,
      issued_revision: revision,
      issued_body: @utf8.encode((count + 1).to_string()),
    }),
  )
}
