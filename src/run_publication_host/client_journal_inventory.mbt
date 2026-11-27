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
  cancellation_head : ClientAcceptedCancellationHead?
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
  let original : ClientTaskMaterialsOriginal[Unit]? = None
  inspect_client_run_journal_inventory_with_task_original(
    max_records, scan, read, validate_run, confirm_cancellation, custody_lost, original,
  )
}

///|
/// The same complete inventory with one already retained pure material value.
/// Only exact same material can skip repeated codec work, never physical reads.
pub fn[Plan, E] inspect_client_run_journal_inventory_with_task_original(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  original : ClientTaskMaterialsOriginal[Plan]?,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
  validate_cancellation_run? : ((ClientJournalPhysicalRow) -> Result[
    ClientCancellationRunJournalInspection,
    E,
  ])? = None,
) -> Result[(Int, Int64), E] {
  inspect_client_run_journal_inventory_with_index_funding(
    max_records,
    scan,
    read,
    validate_run,
    confirm_cancellation,
    custody_lost,
    original,
    None,
    None,
    task_material_count~,
    validate_cancellation_run~,
  )
}

///|
/// Complete semantic validation of one observed SDK Run inventory. The Host
/// must establish the same Store and snapshot before another use.
pub struct ClientRunJournalInventoryOriginal {
  count : Int
  revision : Int64
  maximum : Int
}

///|
pub fn[E] capture_client_sdk_run_journal_inventory(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  validate_cancellation_run : (ClientJournalPhysicalRow) -> Result[
    ClientCancellationRunJournalInspection,
    E,
  ],
  task_material_count : (Int) -> Result[Bool?, E],
  custody_lost : E,
) -> Result[ClientRunJournalInventoryOriginal, E] {
  let task_original : ClientTaskMaterialsOriginal[Unit]? = None
  inspect_client_run_journal_inventory_with_task_original(
    max_records,
    scan,
    read,
    validate_run,
    () => Err(custody_lost),
    custody_lost,
    task_original,
    task_material_count=Some(task_material_count),
    validate_cancellation_run=Some(validate_cancellation_run),
  ).map(pair => { count: pair.0, revision: pair.1, maximum: max_records })
}

///|
// The SDK File admission uses the existing Task-only Run validator. The five
// maps below are still scanned. Only Definitions and Task chunk keys can
// acquire entries on this SDK route, at most one and three per observed Run.
fn client_task_only_inventory_index_capacity(count : Int) -> Int64? {
  let records = count.to_int64()
  guard @shape.map_construction_extent(5L, 4L * records) is Some(maps) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: maps.record_headers + 4L * records,
    reference_slots: maps.reference_slots,
    scalar_words: maps.scalar_words,
    // The indexes keep fresh original key strings beyond the active decode.
    // A Definition CID is 71 units; chunk keys add ':' and one ordinal.
    owned_utf16_units: (71L + 3L * 73L) * records,
    owned_wire_bytes: 0L,
  })
}

///|
fn[Plan, E] inspect_client_run_journal_inventory_with_index_funding(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection, E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
  original : ClientTaskMaterialsOriginal[Plan]?,
  fund_task_indexes : ((Int64) -> Result[Unit, E])?,
  fund_task_read : ((Int64) -> Result[Unit, E])?,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
  validate_cancellation_run? : ((ClientJournalPhysicalRow) -> Result[
    ClientCancellationRunJournalInspection,
    E,
  ])? = None,
) -> Result[(Int, Int64), E] {
  let (count, revision) = match
    journal_inventory_count(
      "client_run_custody", max_records, scan, read, custody_lost,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if fund_task_indexes is Some(fund) {
    guard revision >= 0L &&
      client_task_only_inventory_index_capacity(count) is Some(bytes) else {
      return Err(custody_lost)
    }
    match fund(bytes) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let mut cursor = ""
  let mut observed = 0
  let mut cancellation_heads = 0
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
    if observed >= count || row.key <= cursor {
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
    if record.cancellation_head is Some(_) {
      cancellation_heads += 1
    }
    let definition = @publication.publication_contract_identity(record.definition)
    if fund_task_indexes is Some(_) &&
      (record.checkpoint is Some(_) || !valid_client_request_cid(definition)) {
      return Err(custody_lost)
    }
    if record.task_materials_cid is Some(cid) {
      let (_, chunks) = match
        read_task_material_original_details_with_original(
          row.key,
          cid,
          read,
          custody_lost,
          original,
          fund_workspace=fund_task_read,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
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
    if definitions.contains(definition) {
      return Err(custody_lost)
    }
    definitions[definition] = true
    cursor = row.key
  }
  if observed != count {
    return Err(custody_lost)
  }
  // Exact key reads above have already verified every expected chunk's
  // generation, extent and complete canonical contents. The unique key range
  // has no unattached chunks when the same snapshot's cardinality agrees.
  let membership = match task_material_count {
    None => None
    Some(observe) =>
      match observe(task_chunks.length()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  if membership != Some(true) {
    match
      inspect_client_task_chunk_membership(task_chunks, scan, custody_lost) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    if membership is Some(false) {
      return Err(custody_lost)
    }
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
  // Each row already passed the complete Run validator above. Use that same
  // ordered census for reverse cancellation coverage, while still validating
  // every operation, witness and its exact referenced current Run.
  let cancellation = match validate_cancellation_run {
    None => confirm_cancellation()
    Some(validate) =>
      inspect_client_cancellation_journal_inventory_original(
        max_records,
        scan,
        read,
        (row, _) => validate(row),
        custody_lost,
        None,
        Some((observed, revision, cancellation_heads)),
      ).map(_ => ())
  }
  match cancellation {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok((count, revision))
}

///|
// Preserve the ordered audit and original refusals on inexact observations.
fn[E] inspect_client_task_chunk_membership(
  task_chunks : Map[String, Bool],
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[Unit, E] {
  let mut cursor = ""
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
  Ok(())
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
