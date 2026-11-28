///|
/// Original physical framing shared with the journal writer. A dispatched
/// ledger still needs its independent response and receipt suffixes.
pub fn client_effect_ledger_base_witness(
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  checkpoint : ClientCheckpointJournalRecord,
) -> Bytes? {
  guard checkpoint.effect_ledger.length() <= 128 else { return None }
  let body = checkpoint.artifact.checkpoint_cid +
    "\n" +
    @publication.publication_contract_identity(definition) +
    "\n" +
    client_request_scope_cid(request) +
    "\n" +
    checkpoint.effect_ledger
    .map(entry => @effect.effect_ledger_entry_cid(entry))
    .join("\n")
  Some(@utf8.encode(body))
}

///|
/// Verify the first checkpoint's independent empty Ledger witness within
/// the same original Store read. The caller admits the checkpoint and funds
/// this bounded comparison. A nonempty Ledger needs full response custody.
pub fn[E] confirm_client_empty_effect_ledger_witness(
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  checkpoint : ClientCheckpointJournalRecord,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[Unit, E] {
  guard checkpoint.effect_ledger.is_empty() else { return Err(custody_lost) }
  let key = client_request_scope_cid(request)
  match read("client_effect_custody", key) {
    Err(issue) => Err(issue)
    Ok(Some(row)) if row.key == key &&
      row.revision == 0L &&
      client_effect_ledger_base_witness(request, definition, checkpoint) ==
      Some(row.body) => Ok(())
    Ok(_) => Err(custody_lost)
  }
}

///|
/// Closed physical Effect Ledger entry profile shared by installed Hosts.
pub fn client_effect_ledger_wire_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 65536, max_nodes: 128, max_depth: 16, }
}
