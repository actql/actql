///|
/// Existing submitted-intent journal decision over one original transaction.
/// This is a physical write candidate, never admission, dispatch or COMMIT ACK.
pub struct ClientSubmittedJournalAppend {
  key : String
  body : Bytes
  issued_revision : Int64
  issued_body : Bytes
  usage : (Int64, Bytes)?
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
/// The optional usage CAS belongs to the same transaction as the issued CAS
/// and intent insertion. It is neither a new admission nor a COMMIT ACK.
pub fn client_submitted_journal_append_usage(
  value : ClientSubmittedJournalAppend,
) -> (Int64, Bytes)? {
  value.usage
}

///|
/// Canonical cumulative retained-intent usage within the existing Journal.
/// A compatibility indexer must derive these values from the original bounded
/// inventory; ordinary append may only advance its retained original.
pub fn client_submitted_journal_usage_body(
  count : Int,
  retained_bytes : Int64,
  max_records : Int,
) -> Result[Bytes, ClientJournalDecodingIssue] {
  if max_records < 1 ||
    max_records > 1024 ||
    count < 0 ||
    count > max_records ||
    retained_bytes < 0L ||
    retained_bytes > 67108864L ||
    (count == 0 && retained_bytes != 0L) {
    return Err(CustodyLost)
  }
  Ok(@utf8.encode(count.to_string() + ":" + retained_bytes.to_string()))
}

///|
/// Read the canonical retained usage against the same issuance count. This
/// projection neither adopts missing metadata nor commits a quota update.
pub fn client_submitted_journal_usage(
  row : ClientJournalPhysicalRow,
  count : Int,
  max_records : Int,
) -> Result[Int64, ClientJournalDecodingIssue] {
  if row.key != "retained" || row.revision < 0L || row.body.length() > 14 {
    return Err(CustodyLost)
  }
  let text = @utf8.decode(row.body) catch { _ => return Err(CustodyLost) }
  let prefix = count.to_string() + ":"
  if !text.has_prefix(prefix) {
    return Err(CustodyLost)
  }
  let mut bytes = 0L
  for unit in text[prefix.length():].to_owned() {
    let digit = unit.to_int() - 48
    if digit < 0 || digit > 9 || bytes > 67108864L {
      return Err(CustodyLost)
    }
    bytes = bytes * 10L + digit.to_int64()
  }
  match client_submitted_journal_usage_body(count, bytes, max_records) {
    Ok(body) if body == row.body => Ok(bytes)
    _ => Err(CustodyLost)
  }
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
  usage? : (() -> Result[ClientJournalPhysicalRow?, E])? = None,
  before_construction? : ((Int, Int, Int) -> Result[
    Unit,
    ClientJournalEncodingIssue,
  ])? = None,
) -> Result[
  ClientSubmittedJournalAppendPlan,
  ClientSubmittedJournalAppendIssue[E],
] {
  let issuance = match
    journal_issuance_anchor(
      "client_submitted_intent_custody", max_records, read, custody_lost,
    ) {
    Ok(value) => value
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
  let (count, retained_bytes, revision, usage_revision) = match usage {
    Some(observe) => {
      let row = match observe() {
        Ok(Some(value)) => value
        Ok(None) => return Err(Observation(custody_lost))
        Err(issue) => return Err(Observation(issue))
      }
      let bytes = match
        client_submitted_journal_usage(row, issuance.0, max_records) {
        Ok(value) => value
        Err(_) => return Err(Observation(custody_lost))
      }
      (issuance.0, bytes, issuance.1, Some(row.revision))
    }
    // Existing unindexed callers retain their explicit inventory algorithm.
    // They do not acquire indexed completeness from an absent usage original.
    None =>
      match
        inspect_client_submitted_journal_inventory(
          max_records, scan, read, validate_submission, custody_lost,
        ) {
        Ok((count, bytes, revision)) => (count, bytes, revision, None)
        Err(issue) => return Err(Observation(issue))
      }
  }
  // The original Native order preserves retained identity after expiry; only
  // an actually missing original intent may reach this fresh-insertion check.
  if validity != @request_scope.Admissible {
    return Err(EpochRejected(validity))
  }
  let bytes = intent.wire_bytes.to_int64()
  if count == max_records || bytes > 67108864L - retained_bytes {
    return Err(CapacityExceeded)
  }
  let body = match
    client_submitted_intent_journal_row_body(
      client_submission_reference_record_wire(reference),
      intent,
      before_construction~,
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
      usage: usage_revision.map(original => {
        (
          original,
          @utf8.encode(
            (count + 1).to_string() + ":" + (retained_bytes + bytes).to_string(),
          ),
        )
      }),
    }),
  )
}
