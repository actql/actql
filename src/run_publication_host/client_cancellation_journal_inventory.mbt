///|
/// Projection of the existing complete Run/originals validator. These fields
/// are DATA; only its original fenced reader can establish their provenance.
pub(all) struct ClientCancellationRunJournalInspection {
  request : ClientRequestIdentity
  definition : @publication.PublicationContract
  cancellation_head : ClientAcceptedCancellationHead?
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
  fund_row? : ((Int64) -> Result[Unit, E])? = None,
) -> Result[(Int, Int64), E] {
  inspect_client_cancellation_journal_inventory_with_run_identity(
    max_records,
    scan,
    read,
    (row, _) => validate_run(row),
    custody_lost,
    fund_row~,
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
    (ClientRequestIdentity, @publication.PublicationContract)?,
  ) -> Result[ClientCancellationRunJournalInspection, E],
  custody_lost : E,
  fund_row? : ((Int64) -> Result[Unit, E])? = None,
) -> Result[(Int, Int64), E] {
  inspect_client_cancellation_journal_inventory_original(
    max_records,
    scan,
    read,
    validate_run,
    custody_lost,
    fund_row,
    None,
  )
}

///|
fn[E] read_client_cancellation_journal_issuance(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
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
  Ok((count, marker.revision))
}

///|
fn[E] inspect_client_cancellation_journal_inventory_original(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (
    ClientJournalPhysicalRow,
    (ClientRequestIdentity, @publication.PublicationContract)?,
  ) -> Result[ClientCancellationRunJournalInspection, E],
  custody_lost : E,
  fund_row : ((Int64) -> Result[Unit, E])?,
  run_coverage : (Int, Int64, Int)?,
) -> Result[(Int, Int64), E] {
  let (count, revision) = match
    read_client_cancellation_journal_issuance(
      max_records, scan, read, custody_lost,
    ) {
    Ok(issued) => issued
    Err(issue) => return Err(issue)
  }
  let mut cursor = ""
  let mut observed = 0
  let mut accepted = 0
  while true {
    let row = match scan("client_cancellations", cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if observed >= count || row.key <= cursor {
      return Err(custody_lost)
    }
    observed += 1
    if fund_row is Some(fund) {
      guard row.revision == 0L &&
        client_cancellation_journal_scan_workspace(row.body.length())
        is Some(bytes) else {
        return Err(custody_lost)
      }
      match fund(bytes) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    let value = match
      read_client_cancellation_row_with_witness(row, read, custody_lost) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let run_key = client_request_scope_cid(value.request)
    let run_row = match read("client_runs", run_key) {
      Ok(Some(value)) if value.key == run_key => value
      Err(issue) => return Err(issue)
      _ => return Err(custody_lost)
    }
    let run = match
      validate_run(run_row, Some((value.request, value.definition))) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if client_request_identity_relation(value.request, run.request) !=
      SameRequest ||
      @publication.publication_contract_identity(value.definition) !=
      @publication.publication_contract_identity(run.definition) ||
      run_row.revision < value.observed_revision {
      return Err(custody_lost)
    }
    match value.action {
      AcceptCancellation => {
        guard run.cancellation_head is Some(head) &&
          head.record_key == row.key &&
          head.observed_revision == value.observed_revision else {
          return Err(custody_lost)
        }
        accepted += 1
      }
      AlreadyRequested => {
        guard run.cancellation_head is Some(head) &&
          head.observed_revision <= value.observed_revision else {
          return Err(custody_lost)
        }
      }
      AlreadyTerminal => ()
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
    if originals >= count || row.revision != 0L || row.key <= original_cursor {
      return Err(custody_lost)
    }
    originals += 1
    match read("client_cancellations", row.key) {
      Ok(Some(receipt)) if receipt.key == row.key => ()
      Err(issue) => return Err(issue)
      _ => return Err(custody_lost)
    }
    original_cursor = row.key
  }
  if originals != count {
    return Err(custody_lost)
  }
  // Forward validation proved an injective mapping from accepted receipts
  // to Run heads in this snapshot. Reverse coverage only needs a bounded
  // census of the heads. Each original receipt and witness was checked above.
  let (run_count, run_revision) = match
    journal_inventory_count(
      "client_run_custody", max_records, scan, read, custody_lost,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if run_coverage is Some((covered_count, covered_revision, covered_heads)) {
    if covered_count != run_count ||
      covered_revision != run_revision ||
      covered_heads != accepted {
      return Err(custody_lost)
    }
    return Ok((count, revision))
  }
  let mut run_cursor = ""
  let mut runs = 0
  let mut heads = 0
  while true {
    let row = match scan("client_runs", run_cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if runs >= run_count || row.key <= run_cursor {
      return Err(custody_lost)
    }
    let run = match validate_run(row, None) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if row.key != client_request_scope_cid(run.request) {
      return Err(custody_lost)
    }
    if run.cancellation_head is Some(_) {
      heads += 1
      if heads > accepted {
        return Err(custody_lost)
      }
    }
    runs += 1
    run_cursor = row.key
  }
  if runs != run_count || heads != accepted {
    return Err(custody_lost)
  }
  Ok((count, revision))
}
