///|
/// A physical row observed in the original fenced Store transaction. None
/// from a physical port denotes confirmed end/NotFound; query failure is Err.
pub(all) struct ClientJournalPhysicalRow {
  key : String
  body : Bytes
  revision : Int64
}

///|
/// Returned by the original Run/nested-originals/Effect custody validator.
/// This Host boundary does not grant admission, publication or execution.
pub(all) struct ClientRunJournalInspection {
  request : ClientRequestIdentity
  definition : @publication.PublicationContract
  checkpoint : Array[@effect.EffectLedgerEntry]?
  task_materials_cid : String?
}

///|
// The selected issuance coordinate is a local capacity/CAS anchor. Reading it
// does not request a full integrity audit of unrelated retained originals.
fn[E] journal_issuance_anchor(
  table_name : String,
  max_records : Int,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[(Int, Int64), E] {
  let retained = match read(table_name, "issued") {
    Ok(Some(row)) if row.key == "issued" && row.revision >= 0L => row
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let count = match client_journal_issuance_count(retained.body, max_records) {
    Ok(value) => value
    Err(_) => return Err(custody_lost)
  }
  Ok((count, retained.revision))
}

///|
fn[E] journal_inventory_count(
  table_name : String,
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[(Int, Int64), E] {
  match scan(table_name, "") {
    Ok(Some(row)) if row.key == "issued" => ()
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  match scan(table_name, "issued") {
    Ok(None) => ()
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let retained = match read(table_name, "issued") {
    Ok(Some(row)) if row.key == "issued" => row
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let count = match client_journal_issuance_count(retained.body, max_records) {
    Ok(value) => value
    Err(_) => return Err(custody_lost)
  }
  Ok((count, retained.revision))
}

///|
/// The original complete Native inventory algorithm over same-Store ports.
/// The caller retains the transaction/current-authority fence and supplies
/// the existing semantic validators; partial scans do not close this check.
/// Successful inspection is neither a COMMIT ACK nor permission to start.
pub fn[E] inspect_client_run_journal_inventory(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
) -> Result[(Int, Int64), E] {
  let (count, revision) = match
    journal_inventory_count(
      "client_run_custody", max_records, scan, read, custody_lost,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut cursor = ""
  let mut observed = 0
  let definitions : Map[String, Bool] = Map([])
  let checkpoint_scopes : Map[String, Bool] = Map([])
  let responses : Map[String, Bool] = Map([])
  let receipts : Map[String, Bool] = Map([])
  let task_chunks : Map[String, Bool] = Map([])
  while true {
    let row = match scan("client_runs", cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if observed >= count {
      return Err(custody_lost)
    }
    observed += 1
    let record = match validate_run(row) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if row.key != client_request_scope_cid(record.request) {
      return Err(custody_lost)
    }
    if record.task_materials_cid is Some(cid) {
      let wire = match
        read_client_task_material_original(row.key, cid, read, custody_lost) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let chunks = match client_task_material_original_chunks(row.key, wire) {
        Ok(value) => value
        Err(_) => return Err(custody_lost)
      }
      for (key, _) in chunks {
        task_chunks[key] = true
      }
    }
    if record.checkpoint is Some(checkpoint) {
      checkpoint_scopes[row.key] = true
      for entry in checkpoint {
        let state = @effect.effect_ledger_entry_state_code(entry)
        if state >= 2 && state <= 4 {
          guard entry.outcome_receipt_cid is Some(cid) &&
            !receipts.contains(cid) else {
            return Err(custody_lost)
          }
          receipts[cid] = true
        }
        if @effect.effect_ledger_entry_state_code(entry) != 1 {
          continue
        }
        let cid = @effect.effect_ledger_entry_cid(entry)
        match read("client_effect_response_meta", cid) {
          Ok(Some(_)) => {
            if responses.contains(cid) {
              return Err(custody_lost)
            }
            responses[cid] = true
          }
          Ok(None) => ()
          Err(issue) => return Err(issue)
        }
      }
    }
    let definition = @publication.publication_contract_identity(
      record.definition,
    )
    if definitions.contains(definition) {
      return Err(custody_lost)
    }
    definitions[definition] = true
    cursor = row.key
  }
  if observed != count {
    return Err(custody_lost)
  }
  cursor = ""
  let mut chunk_count = 0
  while true {
    let row = match scan("client_task_run_materials", cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if chunk_count >= task_chunks.length() {
      return Err(custody_lost)
    }
    chunk_count += 1
    if !task_chunks.contains(row.key) ||
      row.key <= cursor ||
      row.revision != 0L ||
      row.body.length() == 0 ||
      row.body.length() > 131072 {
      return Err(custody_lost)
    }
    cursor = row.key
  }
  if chunk_count != task_chunks.length() {
    return Err(custody_lost)
  }
  cursor = ""
  let mut witnesses = 0
  while true {
    let row = match scan("client_effect_custody", cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if witnesses >= observed {
      return Err(custody_lost)
    }
    witnesses += 1
    if !checkpoint_scopes.contains(row.key) {
      return Err(custody_lost)
    }
    cursor = row.key
  }
  if witnesses != checkpoint_scopes.length() {
    return Err(custody_lost)
  }
  // No unattached response is adopted, including a pair left behind without
  // its original dispatch or Run. All expected pairs were authenticated above.
  for table in ["client_effect_response_meta", "client_effect_response_bytes"] {
    let mut cursor = ""
    let mut response_count = 0
    while true {
      let row = match scan(table, cursor) {
        Ok(Some(value)) => value
        Ok(None) => break
        Err(issue) => return Err(issue)
      }
      if response_count >= responses.length() {
        return Err(custody_lost)
      }
      response_count += 1
      if !responses.contains(row.key) || row.revision != 0L {
        return Err(custody_lost)
      }
      cursor = row.key
    }
    if response_count != responses.length() {
      return Err(custody_lost)
    }
  }
  let mut receipt_cursor = ""
  let mut receipt_count = 0
  while true {
    let row = match scan("client_effect_row_receipt", receipt_cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if receipt_count >= receipts.length() {
      return Err(custody_lost)
    }
    receipt_count += 1
    if !receipts.contains(row.key) || row.revision != 0L {
      return Err(custody_lost)
    }
    receipt_cursor = row.key
  }
  if receipt_count != receipts.length() {
    return Err(custody_lost)
  }
  match confirm_cancellation() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok((count, revision))
}

///|
// Actual original byte metadata only; no future policy is allocated as RAM.
fn journal_retained_intent_bytes_add(
  retained : Int64,
  wire_bytes : Int,
) -> Int64? {
  let bytes = wire_bytes.to_int64()
  if retained < 0L || bytes < 0L || retained > 9223372036854775807L - bytes {
    None
  } else {
    Some(retained + bytes)
  }
}

///|
/// The existing submitted-intent inventory and actual cumulative canonical bytes.
/// validate_submission uses the original reference/intent decoder and retained
/// Run relationship before returning the original intent for byte accounting.
pub fn[E] inspect_client_submitted_journal_inventory(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_submission : (ClientJournalPhysicalRow) -> Result[
    ClientSubmittedJournalEncoding,
    E,
  ],
  custody_lost : E,
) -> Result[(Int, Int64, Int64), E] {
  let (count, revision) = match
    journal_inventory_count(
      "client_submitted_intent_custody", max_records, scan, read, custody_lost,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut cursor = ""
  let mut observed = 0
  let mut retained_bytes = 0L
  while true {
    let row = match scan("client_submitted_intents", cursor) {
      Ok(Some(value)) => value
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if observed >= count {
      return Err(custody_lost)
    }
    observed += 1
    let record = match validate_submission(row) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if client_submission_reference_record_request_id(record.reference) !=
      row.key {
      return Err(custody_lost)
    }
    retained_bytes = match
      journal_retained_intent_bytes_add(
        retained_bytes,
        record.intent.wire_bytes,
      ) {
      Some(value) => value
      None => return Err(custody_lost)
    }
    cursor = row.key
  }
  if observed != count {
    return Err(custody_lost)
  }
  Ok((count, retained_bytes, revision))
}
