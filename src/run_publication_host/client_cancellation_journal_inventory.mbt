///|
/// Projection of the existing complete Run/originals validator. These fields
/// are DATA; only its original fenced reader can establish their provenance.
pub(all) struct ClientCancellationRunJournalInspection {
  request : ClientRequestIdentity
  definition : @publication.PublicationContract
  cancellation_requested : Bool
}

///|
/// The original Native cancellation census over the same fenced Store ports.
/// It retains the issued anchor, immutable operation witness and full Run
/// validator. Success is neither a transaction ACK nor physical-stop evidence.
pub fn[E] inspect_client_cancellation_journal_inventory(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientCancellationRunJournalInspection,
    E,
  ],
  custody_lost : E,
) -> Result[(Int, Int64), E] {
  inspect_client_cancellation_journal_inventory_with_run_identity(
    max_records,
    scan,
    read,
    (row, _, _) => validate_run(row),
    custody_lost,
  )
}

///|
/// Forward the admitted identity DATA from this cancellation to its fresh
/// Run validator. A validator may reuse only matching canonical input and
/// must still perform its remaining checks on the actual Run row.
pub fn[E] inspect_client_cancellation_journal_inventory_with_run_identity(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (
    ClientJournalPhysicalRow,
    ClientRequestIdentity,
    @publication.PublicationContract,
  ) -> Result[ClientCancellationRunJournalInspection, E],
  custody_lost : E,
) -> Result[(Int, Int64), E] {
  let marker = match read("client_cancel_custody", "issued") {
    Ok(Some(value)) if value.key == "issued" => value
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  match scan("client_cancel_custody", "") {
    Ok(Some(row)) if row.key == "issued" => ()
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  match scan("client_cancel_custody", "issued") {
    Ok(None) => ()
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let count = match client_journal_issuance_count(marker.body, max_records) {
    Ok(value) if marker.revision == value.to_int64() => value
    _ => return Err(custody_lost)
  }
  let mut cursor = ""
  let mut observed = 0
  while true {
    let row = match scan("client_cancellations", cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if observed >= count {
      return Err(custody_lost)
    }
    observed += 1
    let value = match decode_client_cancellation_journal_row(row) {
      Ok(value) => value
      Err(_) => return Err(custody_lost)
    }
    let original = match read("client_cancel_originals", row.key) {
      Ok(Some(value)) => value
      Err(issue) => return Err(issue)
      _ => return Err(custody_lost)
    }
    if original.revision != 0L ||
      original.body != @utf8.encode(@sha.hex(row.body)) ||
      client_cancellation_journal_index(
        value.namespace_id,
        client_request_authority_scope_cid(value.request),
        value.cancel_id,
      ) !=
      Some(row.key) {
      return Err(custody_lost)
    }
    let run_row = match
      read("client_runs", client_request_scope_cid(value.request)) {
      Ok(Some(value)) => value
      Err(issue) => return Err(issue)
      _ => return Err(custody_lost)
    }
    let run = match validate_run(run_row, value.request, value.definition) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if client_request_identity_relation(value.request, run.request) !=
      SameRequest ||
      @publication.publication_contract_identity(value.definition) !=
      @publication.publication_contract_identity(run.definition) ||
      run_row.revision < value.observed_revision ||
      (value.action != AlreadyTerminal && !run.cancellation_requested) {
      return Err(custody_lost)
    }
    cursor = row.key
  }
  if observed != count {
    return Err(custody_lost)
  }
  let mut original_cursor = ""
  let mut originals = 0
  while true {
    let row = match scan("client_cancel_originals", original_cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if originals >= count || row.revision != 0L {
      return Err(custody_lost)
    }
    originals += 1
    match read("client_cancellations", row.key) {
      Ok(Some(_)) => ()
      Err(issue) => return Err(issue)
      _ => return Err(custody_lost)
    }
    original_cursor = row.key
  }
  if originals != count {
    return Err(custody_lost)
  }
  Ok((count, marker.revision))
}
