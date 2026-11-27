///|
/// Retained terminal row evidence after the response's actual Store return.
/// A separate physical append must confirm this transition before the next row.
pub struct ClientEffectSavedFileTerminal {
  response : ClientEffectSavedFileResponse
  receipt : @publication.PublicationContract
  terminal : @effect.EffectLedgerEntry
  writes : Array[ClientEffectFileJournalWrite]
  evidence : String
  checkpoint : ClientCheckpointJournalRecord
  run : ClientRunJournalEncoding
  policy : String?
  observation : String?
}

///|
fn saved_file_journal_successor(
  write : ClientEffectFileJournalWrite,
) -> ClientJournalPhysicalRow {
  {
    key: write.key,
    revision: write.before.map_or(0L, original => original.revision + 1L),
    body: write.successor,
  }
}

///|
pub fn ClientEffectSavedFileResponse::prepare_terminal(
  self : ClientEffectSavedFileResponse,
  current : () -> Bool,
  fund : (Int, Int, Int) -> Bool,
  before_decode : (ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ],
  before_encode : (Int, Int, Int) -> Result[Unit, ClientJournalEncodingIssue],
) -> Result[ClientEffectSavedFileTerminal, ClientEffectResolutionOriginalIssue] {
  let dispatch = self.dispatch
  let row = dispatch.row
  let application = row.application
  let original = application.computation.preview.waiting
  let actual_run = saved_file_journal_successor(self.writes[0])
  let actual_witness = saved_file_journal_successor(self.writes[1])
  let metadata = self.writes[2].successor
  let bounds = client_checkpoint_journal_limits()
  let ledger = client_effect_ledger_wire_limits()
  guard current() &&
    decode_client_run_journal_row_with_retained_identity(
      actual_run.body,
      original.run.request,
      original.run.definition,
      require_retained_identity=true,
      before_construction=Some(before_decode),
    )
    is Ok((run, policy, observation)) &&
    run.checkpoint is Some(checkpoint_wire) &&
    fund(
      checkpoint_wire.length(),
      Int::min(checkpoint_wire.length(), bounds.max_nodes),
      bounds.max_depth,
    ) &&
    decode_client_checkpoint_journal_row(
      checkpoint_wire,
      run.definition,
      ledger,
    )
    is Ok(checkpoint) &&
    checkpoint.artifact.checkpoint_cid ==
    original.checkpoint.artifact.checkpoint_cid &&
    checkpoint.effect_ledger.length() == 3 * dispatch.index + 2 &&
    checkpoint.effect_ledger[checkpoint.effect_ledger.length() - 1].cid ==
    dispatch.dispatching.cid &&
    fund(ledger.max_wire_bytes, ledger.max_nodes, ledger.max_depth) &&
    @publication.issue_effect_row_outcome_receipt_from_file(
      row.preview,
      row.member_index,
      row.ordinal,
      dispatch.dispatching.cid,
      self.response,
      ledger.max_wire_bytes,
      ledger.max_nodes,
      ledger.max_depth,
    )
    is Ok(receipt) else {
    return Err(InvalidOriginal)
  }
  let receipt_wire = @publication.publication_contract_json(receipt)
  let receipt_cid = @publication.publication_contract_identity(receipt)
  guard fund(ledger.max_wire_bytes, ledger.max_nodes, ledger.max_depth) &&
    @effect.issue_effect_row_receipt_terminal_entry_from_file(
      row.preview,
      row.member_index,
      row.ordinal,
      application.scoped_request,
      row.locator,
      row.key,
      row.request_cid,
      dispatch.dispatching,
      checkpoint.effect_ledger.filter(entry => {
        @effect.effect_ledger_entry_locator_cid(entry) ==
        @effect.effect_ledger_entry_locator_cid(dispatch.dispatching)
      }),
      dispatch.dispatching.cid,
      self.response,
      receipt_wire,
      ledger.max_wire_bytes,
      ledger.max_nodes,
      ledger.max_depth,
    )
    is Ok(terminal) else {
    return Err(InvalidOriginal)
  }
  let entries = checkpoint.effect_ledger.copy()
  entries.push(terminal)
  let next = { ..checkpoint, effect_ledger: entries, }
  guard client_effect_ledger_base_witness(run.request, run.definition, next)
    is Some(base) &&
    client_checkpoint_journal_row_body(next) is Ok(checkpoint_wire) &&
    client_run_journal_row_body(
      { ..run, checkpoint: Some(checkpoint_wire), },
      local_run_policy_originals=policy,
      run_observation_originals=observation,
      measure_construction=true,
      before_construction=Some(before_encode),
    )
    is Ok(next_run) &&
    current() else {
    return Err(Encoding)
  }
  let text = @utf8.decode(base) catch { _ => return Err(Encoding) }
  let evidence = dispatch.earlier_evidence +
    "\nresponse\n" +
    dispatch.dispatching.cid +
    "\n" +
    @sha.hex(metadata) +
    "\nreceipt\n" +
    terminal.cid +
    "\n" +
    receipt_cid
  let witness = @utf8.encode(text + evidence)
  let writes : Array[ClientEffectFileJournalWrite] = [
    {
      table: "client_runs",
      key: actual_run.key,
      before: Some(actual_run),
      successor: next_run,
    },
    {
      table: "client_effect_custody",
      key: actual_witness.key,
      before: Some(actual_witness),
      successor: witness,
    },
    {
      table: "client_effect_row_receipt",
      key: receipt_cid,
      before: None,
      successor: @utf8.encode(receipt_wire),
    },
  ]
  Ok({
    response: self,
    receipt,
    terminal,
    writes,
    evidence,
    checkpoint: next,
    run,
    policy,
    observation,
  })
}

///|
pub fn ClientEffectSavedFileTerminal::rows(
  self : ClientEffectSavedFileTerminal,
) -> Array[ClientEffectFileJournalWrite] {
  self.writes
}

///|
pub fn ClientEffectSavedFileTerminal::receipt_cid(
  self : ClientEffectSavedFileTerminal,
) -> String {
  @publication.publication_contract_identity(self.receipt)
}
