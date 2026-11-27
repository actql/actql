///|
/// An exact pair of physical Run/ledger observations or insertions owned by
/// the typed Effect response or its terminal transition.
pub(all) struct ClientEffectFileJournalWrite {
  table : String
  key : String
  before : ClientJournalPhysicalRow?
  successor : Bytes
}

///|
/// Original file response following one returned physical replacement.
/// This constructor cannot acknowledge its Store transaction.
pub struct ClientEffectSavedFileResponse {
  dispatch : ClientEffectSavedFileDispatch
  response : @publication.EffectFileOperationReceipt
  writes : Array[ClientEffectFileJournalWrite]
}

///|
fn effect_file_update_outcome_wire(
  identity : String,
  max_bytes : Int,
) -> String? {
  try {
    let writer = @encode.writer(max_bytes, 8, 3)
    @encode.begin_object(writer)
    @encode.key(writer, "result")
    @encode.begin_object(writer)
    @encode.key(writer, "id")
    @encode.string_value(writer, identity)
    @encode.end_object(writer)
    @encode.key(writer, "state")
    @encode.string_value(writer, "applied")
    @encode.end_object(writer)
    Some(@encode.finish(writer))
  } catch {
    _ => None
  }
}

///|
/// Use the exact operation's original typed outcome and adopt the actual
/// Host-returned successor. Both response records bind the same dispatch.
pub fn ClientEffectSavedFileDispatch::prepare_response(
  self : ClientEffectSavedFileDispatch,
  replacement : Bytes,
  device : Int64,
  inode : Int64,
  physical_digest : String,
  max_bytes : Int,
  fund : (Int, Int, Int) -> Bool,
) -> Result[ClientEffectSavedFileResponse, ClientEffectResolutionOriginalIssue] {
  let limits = client_checkpoint_journal_limits()
  guard device >= 0L &&
    inode > 0L &&
    replacement.length() > 0 &&
    replacement.length() <= max_bytes &&
    physical_digest.length() == 64 &&
    fund(replacement.length() + self.row.target.length() * 6, 128, 8) &&
    @sha.hex(replacement) == physical_digest &&
    @publication.admit_effect_file_replacement_evidence(
      replacement, device.to_string(), inode.to_string(),
      replacement.length().to_int64(), max_bytes,
    )
    is Ok(evidence) &&
    effect_file_update_outcome_wire(self.row.target, limits.max_wire_bytes)
    is Some(outcome) &&
    fund(outcome.length() * 6 + 4096, 256, limits.max_depth) &&
    @publication.prepare_effect_file_operation_receipt(
      self.operation, evidence, outcome,
      limits.max_wire_bytes, limits.max_nodes, limits.max_depth,
    )
    is Ok(response) else {
    return Err(InvalidOriginal)
  }
  let metadata = @utf8.encode(@publication.effect_file_operation_receipt_wire(response))
  let witness_prefix = @utf8.decode(self.next_witness) catch {
    _ => return Err(Encoding)
  }
  let dispatch = self.dispatching.cid
  let witness = @utf8.encode(witness_prefix + "\nresponse\n" + dispatch + "\n" + @sha.hex(metadata))
  let run : ClientJournalPhysicalRow = {
    key: self.before_run.key, revision: self.before_run.revision + 1L, body: self.next_run,
  }
  let prior_witness : ClientJournalPhysicalRow = {
    key: self.before_witness.key,
    revision: self.before_witness.revision + 1L,
    body: self.next_witness,
  }
  let writes : Array[ClientEffectFileJournalWrite] = [
    {table: "client_runs", key: run.key, before: Some(run), successor: run.body},
    {table: "client_effect_custody", key: prior_witness.key, before: Some(prior_witness), successor: witness},
    {table: "client_effect_response_meta", key: dispatch, before: None, successor: metadata},
    {table: "client_effect_response_bytes", key: dispatch, before: None, successor: replacement},
  ]
  Ok({ dispatch: self, response, writes })
}

///|
/// Physical candidates remain opaque originals until exact returned Read.
pub fn ClientEffectSavedFileResponse::rows(
  self : ClientEffectSavedFileResponse,
) -> Array[ClientEffectFileJournalWrite] {
  self.writes
}

///|
pub fn ClientEffectSavedFileResponse::response_cid(
  self : ClientEffectSavedFileResponse,
) -> String {
  @publication.effect_file_operation_receipt_cid(self.response)
}
