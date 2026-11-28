///|
/// Bounded observation of a name against the original Journal's issued
/// marker and retained keys. The caller supplies one fenced physical Read.
pub(all) struct ClientSubmittedNameInventory {
  index : String
  issued : Int
  issued_revision : Int64
  original : ClientJournalPhysicalRow?
}

///|
/// An installation without a maintained SQL name count checks the retained
/// key census before treating a name as absent. Only the selected name's
/// body is needed; HMAC verification belongs to the original physical owner.
pub fn[E] inspect_client_submitted_name_inventory(
  name : ClientSubmittedNameKey,
  max_records : Int,
  scan_control : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  scan_name : (String) -> Result[(String, Int64)?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[ClientSubmittedNameInventory, E] {
  let (issued, revision) = match
    journal_inventory_count(
      "client_submission_name_custody", max_records, scan_control, read, custody_lost,
    ) {
    Ok((issued, revision)) if revision == issued.to_int64() =>
      (issued, revision)
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let index = match client_submitted_name_index_input(name) {
    Ok(input) => @sha.hex(@utf8.encode(input))
    Err(_) => return Err(custody_lost)
  }
  let mut cursor = ""
  let mut observed = 0
  let mut selected = false
  while true {
    let (key, generation) = match scan_name(cursor) {
      Ok(Some(row)) => row
      Ok(None) => break
      Err(issue) => return Err(issue)
    }
    if observed == issued ||
      generation != 0L ||
      key.length() != 64 ||
      key <= cursor ||
      !valid_client_request_cid("sha256:" + key) {
      return Err(custody_lost)
    }
    selected = selected || key == index
    observed += 1
    cursor = key
  }
  if observed != issued {
    return Err(custody_lost)
  }
  let original = match read("client_submission_names", index) {
    Ok(None) if !selected => None
    Ok(Some(row)) if selected &&
      row.key == index &&
      row.revision == 0L &&
      row.body.length() > 0 &&
      row.body.length() <= 16384 => Some(row)
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  Ok({ index, issued, issued_revision: revision, original, })
}

///|
/// Observe an occupied name without accepting another Submission candidate.
pub(all) enum ClientSubmittedNameSelection {
  NameMissing
  NameConflict
  NameHistoryUnavailable
  NameRetained(ClientSubmissionReferenceRecord)
}

///|
/// Borrow the authenticated selected name in the same fenced Journal Read.
/// A conflicting intent or scope must be reported even if its original
/// submission row is missing. Only the matching history decodes that body.
pub fn[E] inspect_client_submitted_name_selection(
  key : ClientSubmittedNameKey,
  inventory : ClientSubmittedNameInventory,
  authority_scope_cid : String,
  intent : ClientSubmittedIntent,
  authenticate : (Bytes) -> Result[Bytes, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  decode_intent : (Bytes) -> Result[ClientSubmittedJournalEncoding, E],
  custody_lost : E,
) -> Result[ClientSubmittedNameSelection, E] {
  guard inventory.original is Some(original) else { return Ok(NameMissing) }
  let row = match decode_client_submitted_name_row(original.body) {
    Ok(row) if row.binding.key == key => row
    _ => return Err(custody_lost)
  }
  let preimage = match
    client_submitted_name_authentication_input(row.binding, 8192) {
    Ok(wire) => @utf8.encode(wire)
    Err(_) => return Err(custody_lost)
  }
  match authenticate(preimage) {
    Ok(tag) if tag == row.authenticator => ()
    Ok(_) => return Err(custody_lost)
    Err(issue) => return Err(issue)
  }
  if row.binding.authority_scope_cid != authority_scope_cid ||
    row.binding.intent_cid != client_submitted_intent_cid(intent) {
    return Ok(NameConflict)
  }
  let saved = match
    read("client_submitted_intents", row.binding.submission_id) {
    Ok(Some(value)) if value.key == row.binding.submission_id => value
    Ok(None) => return Ok(NameHistoryUnavailable)
    Ok(Some(_)) => return Err(custody_lost)
    Err(issue) => return Err(issue)
  }
  let original = match decode_intent(saved.body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    inspect_client_named_submitted_original(
      key,
      authority_scope_cid,
      intent,
      row.binding,
      Some(original.reference),
      Some(original.intent),
    ) {
    Ok(reference) => Ok(NameRetained(reference))
    Err(_) => Err(custody_lost)
  }
}
