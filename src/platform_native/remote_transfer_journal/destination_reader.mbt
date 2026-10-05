///|
/// Derive the existing journal's exact reader occurrence key for restoration
/// and custody inspection. This performs no I/O and grants no reader or start
/// permission. Reader admission still verifies committed material atomically.
pub fn destination_reader_key(
  request : @transfer.RemoteTransferRequest,
  reader_id : String,
) -> Result[String, NativeRemoteTransferJournalIssue] {
  if @transfer.request_projection(request)[1] == "direct" {
    if reader_id.is_empty() ||
      reader_id.length() > 256 ||
      reader_id.contains("\n") ||
      reader_id.contains("\r") {
      return Err(Protocol(@transfer.InvalidTransfer))
    }
    // Direct readers use the existing request-scoped reader table. Store use
    // identity is intentionally unchanged and cannot authorize a Direct use.
    let digest = match @sha.text_hex(reader_id) {
      Ok(value) => value
      Err(_) => return Err(Protocol(@transfer.InvalidTransfer))
    }
    return Ok(@transfer.request_cid(request) + ":direct:" + digest)
  }
  let store_use = match @transfer.prepare_store_use(request, reader_id) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  Ok(@transfer.request_cid(request) + ":" + @transfer.store_use_cid(store_use))
}
