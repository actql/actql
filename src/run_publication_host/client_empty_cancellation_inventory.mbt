///|
/// Initial portable Local slice of the existing cancellation custody check.
/// Empty means the original issued count/revision is zero and every operation
/// and original-witness namespace was actually observed empty. Missing custody
/// is not initialized. Nonempty history requires the original full validator;
/// it cannot be omitted to complete a narrower inspection silently.
pub fn[E] inspect_client_empty_cancellation_inventory(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
  unsupported : E,
) -> Result[Unit, E] {
  let marker = match read("client_cancel_custody", "issued") {
    Ok(Some(value)) if value.key == "issued" => value
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let count = match client_journal_issuance_count(marker.body, max_records) {
    Ok(value) if marker.revision == value.to_int64() => value
    _ => return Err(custody_lost)
  }
  match scan("client_cancel_custody", "") {
    Ok(Some(value)) if value.key == "issued" => ()
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  match scan("client_cancel_custody", "issued") {
    Ok(None) => ()
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  if count != 0 {
    return Err(unsupported)
  }
  for table_name in ["client_cancellations", "client_cancel_originals"] {
    match scan(table_name, "") {
      Ok(None) => ()
      Err(issue) => return Err(issue)
      _ => return Err(custody_lost)
    }
  }
  Ok(())
}
