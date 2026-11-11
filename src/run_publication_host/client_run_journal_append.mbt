///|
/// Validated original physical row, not a new admission or a COMMIT ACK.
pub struct ClientRetainedRunJournalRow {
  row : ClientJournalPhysicalRow
  original : ClientRunJournalInspection
}

///|
/// Same-transaction issued CAS and initial Run insert. The physical Host must
/// keep the original current fence and atomically save the submitted ready row.
pub struct ClientRunJournalAppend {
  key : String
  body : Bytes
  issued_revision : Int64
  issued_body : Bytes
}

///|
pub(all) enum ClientRunJournalAppendPlan {
  Retained(ClientRetainedRunJournalRow)
  Append(ClientRunJournalAppend)
}

///|
pub(all) enum ClientRunJournalAppendIssue[E] {
  Observation(E)
  ChangedIntent
  ForeignRun
  CapacityExceeded
  InvalidOriginal
  Encoding(ClientJournalEncodingIssue)
}

///|
pub fn client_retained_run_journal_row(
  value : ClientRetainedRunJournalRow,
) -> ClientJournalPhysicalRow {
  value.row
}

///|
pub fn client_run_journal_append_rows(
  value : ClientRunJournalAppend,
) -> (String, Bytes, Int64, Bytes) {
  (value.key, value.body, value.issued_revision, value.issued_body)
}

///|
/// Lookup precedes any new Plan or policy issuance. The existing validator
/// must check all saved Run originals/custody, not just decode its outer row.
/// Query failure is Observation; confirmed NotFound is not resend permission.
pub fn[E] read_client_retained_run_journal(
  request : ClientRequestIdentity,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
) -> Result[ClientRetainedRunJournalRow?, ClientRunJournalAppendIssue[E]] {
  let key = client_request_scope_cid(request)
  let row = match read("client_runs", key) {
    Ok(Some(value)) if value.key == key && value.revision >= 0L => value
    Ok(None) => return Ok(None)
    Ok(Some(_)) => return Err(Observation(custody_lost))
    Err(issue) => return Err(Observation(issue))
  }
  let original = match validate_run(row) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  match client_request_identity_relation(request, original.request) {
    SameRequest => Ok(Some({ row, original, }))
    ChangedIntent => Err(ChangedIntent)
    DifferentRequest => Err(Observation(custody_lost))
  }
}

///|
/// Finite decision using the existing complete inventory and row codec. Ports
/// must observe one original Store transaction; no write or execution occurs.
/// A candidate is never accepted until the same transaction's ACK is known.
pub fn[E] prepare_client_run_journal_append(
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  local_policy_original? : ClientLocalRunPolicyOriginal? = None,
  run_observation_originals? : ClientRunObservationOriginals? = None,
  task_materials_cid? : String? = None,
  publication_policy_originals? : String? = None,
) -> Result[ClientRunJournalAppendPlan, ClientRunJournalAppendIssue[E]] {
  match
    read_client_retained_run_journal(request, read, validate_run, custody_lost) {
    Ok(Some(retained)) => {
      if @publication.publication_contract_identity(
          retained.original.definition,
        ) !=
        @publication.publication_contract_identity(definition) {
        return Err(ForeignRun)
      }
      // Adopt the actually saved bytes, including their original policy/time.
      return Ok(Retained(retained))
    }
    Ok(None) => ()
    Err(issue) => return Err(issue)
  }
  if @publication.publication_contract_name(definition) != "run_definition" {
    return Err(InvalidOriginal)
  }
  let (count, revision) = match
    inspect_client_run_journal_inventory(
      max_records, scan, read, validate_run, confirm_cancellation, custody_lost,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  if revision < 0L {
    return Err(Observation(custody_lost))
  }
  if count == max_records {
    return Err(CapacityExceeded)
  }
  let mut cursor = ""
  let mut observed = 0
  while true {
    let row = match scan("client_runs", cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(Observation(issue))
    }
    if observed >= count || row.key <= cursor {
      return Err(Observation(custody_lost))
    }
    observed += 1
    let other = match validate_run(row) {
      Ok(value) => value
      Err(issue) => return Err(Observation(issue))
    }
    if row.revision < 0L || row.key != client_request_scope_cid(other.request) {
      return Err(Observation(custody_lost))
    }
    if @publication.publication_contract_identity(other.definition) ==
      @publication.publication_contract_identity(definition) {
      return Err(ForeignRun)
    }
    cursor = row.key
  }
  if observed != count {
    return Err(Observation(custody_lost))
  }
  let policy = match local_policy_original {
    None => None
    Some(original) => {
      let body = client_local_run_policy_original_body(original)
      if validate_client_local_run_policy_original_run(
          body, request, definition,
        )
        is Err(_) {
        return Err(InvalidOriginal)
      }
      let wire = @utf8.decode(body) catch { _ => return Err(InvalidOriginal) }
      Some(wire)
    }
  }
  let observation = match run_observation_originals {
    None => None
    Some(original) => {
      if @publication.validate_original_interactive_run_evidence(
          definition,
          original.prepared(),
          original.authorization(),
        )
        is Err(_) {
        return Err(InvalidOriginal)
      }
      match original.wire() {
        Ok(wire) => Some(wire)
        Err(_) => return Err(InvalidOriginal)
      }
    }
  }
  if publication_policy_originals is Some(wire) &&
    read_client_run_policy_originals(wire) is Err(_) {
    return Err(InvalidOriginal)
  }
  let record : ClientRunJournalEncoding = {
    request,
    definition,
    dispatch_reserved: false,
    physical_start_claimed: false,
    cancellation_requested: false,
    publication_binding: None,
    publication_policy_originals,
    effect_material_originals: None,
    task_materials_cid,
    checkpoint: None,
  }
  let body = match
    client_run_journal_row_body(
      record,
      local_run_policy_originals=policy,
      run_observation_originals=observation,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  Ok(
    Append({
      key: client_request_scope_cid(request),
      body,
      issued_revision: revision,
      issued_body: @utf8.encode((count + 1).to_string()),
    }),
  )
}
