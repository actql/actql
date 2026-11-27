///|
/// Candidate for the first ordered dispatch on this exact current lease.
/// The Store must install both rows together and return their exact successors
/// on the same adopted Read before the Host can use the operation.
pub struct ClientEffectSavedFileDispatch {
  row : ClientEffectSavedFileRow
  before_run : ClientJournalPhysicalRow
  next_run : Bytes
  before_witness : ClientJournalPhysicalRow
  next_witness : Bytes
  dispatching : @effect.EffectLedgerEntry
  operation : @publication.EffectFileOperation
  index : Int
  earlier_evidence : String
}

///|
pub fn ClientEffectSavedFileRow::prepare_dispatch(
  self : ClientEffectSavedFileRow,
  actual_run : ClientJournalPhysicalRow,
  actual_witness : ClientJournalPhysicalRow,
  previous : ClientEffectSavedFileTerminal?,
  index : Int,
  target_cid : String,
  now : Int64,
  current : () -> Bool,
  limits : @checkpoint.WireLimits,
  fund : (Int, Int, Int) -> Bool,
  before_decode : (ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ],
  before_encode : (Int, Int, Int) -> Result[Unit, ClientJournalEncodingIssue],
) -> Result[ClientEffectSavedFileDispatch, ClientEffectResolutionOriginalIssue] {
  let application = self.application
  let review = application.computation.preview
  let original = review.waiting
  let claim = application.claim.claim
  let ledger = client_effect_ledger_wire_limits()
  guard exact_retained_file_dispatch_predecessor(self, actual_run, actual_witness, previous, index)
    is Some(earlier_evidence) &&
    now >= 0L &&
    now < application.claim.lease_expires_ms &&
    actual_witness.key == client_request_scope_cid(original.run.request) &&
    current() &&
    decode_client_run_journal_row_with_retained_identity(
      actual_run.body,
      original.run.request,
      original.run.definition,
      require_retained_identity=true,
      before_construction=Some(before_decode),
    )
    is Ok((run, policy, observation)) &&
    !run.cancellation_requested() &&
    run.publication_binding == original.run.publication_binding &&
    run.checkpoint is Some(wire) &&
    fund(
      wire.length(),
      Int::min(wire.length(), limits.max_nodes),
      limits.max_depth,
    ) &&
    decode_client_checkpoint_journal_row(
      wire,
      run.definition,
      ledger,
    )
    is Ok(checkpoint) &&
    checkpoint.artifact.checkpoint_cid ==
    original.checkpoint.artifact.checkpoint_cid &&
    checkpoint.state.status == @publication.Resuming &&
    checkpoint.resume_intent is Some(intent) &&
    @checkpoint.decide_resume_fence(intent, claim, now) ==
    @checkpoint.FenceCurrent &&
    !checkpoint.settlement_only &&
    checkpoint.effect_ledger.length() == 3 * index &&
    checkpoint.effect_ledger.length() <= 125 &&
    client_effect_ledger_base_witness(run.request, run.definition, checkpoint)
    is Some(base) &&
    (base + @utf8.encode(earlier_evidence)) == actual_witness.body &&
    checkpoint.resolution_cid is Some(resolution) else {
    return Err(InvalidOriginal)
  }
  // The existing Ledger codec admits both transitions and the exact request.
  // These bodies and the witness stay retained until their actual Read returns.
  guard fund(ledger.max_wire_bytes, ledger.max_nodes, ledger.max_depth) &&
    @effect.issue_prepared_effect_ledger_entry(
      self.basis,
      ledger.max_wire_bytes,
      ledger.max_nodes,
      ledger.max_depth,
    )
    is Ok(prepared) &&
    @effect.issue_next_effect_ledger_entry(
      prepared,
      "dispatching",
      None,
      ledger.max_wire_bytes,
      ledger.max_nodes,
      ledger.max_depth,
    )
    is Ok(dispatching) &&
    @effect.effect_ledger_entry_follows(Some(prepared), dispatching) &&
    @effect.effect_ledger_entry_admits_dispatch(
      dispatching,
      application.scoped_request,
      self.locator,
      self.key,
      self.request_cid,
    ) &&
    @publication.prepare_effect_file_operation(
      self.preview,
      self.member_index,
      self.ordinal,
      self.installation_cid,
      target_cid,
      self.request_cid,
      dispatching.cid,
      client_request_authority_scope_cid(run.request),
      resolution,
      self.version,
    )
    is Ok(operation) else {
    return Err(InvalidOriginal)
  }
  let entries = checkpoint.effect_ledger.copy()
  entries.push(prepared)
  entries.push(dispatching)
  let successor = { ..checkpoint, effect_ledger: entries, }
  guard client_checkpoint_journal_row_body(successor) is Ok(checkpoint_wire) &&
    client_effect_ledger_base_witness(run.request, run.definition, successor)
    is Some(next_witness) &&
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
  Ok({
    row: self,
    before_run: actual_run,
    next_run,
    before_witness: actual_witness,
    next_witness: next_witness + @utf8.encode(earlier_evidence),
    dispatching,
    operation,
    index,
    earlier_evidence,
  })
}

///|
pub fn ClientEffectSavedFileDispatch::rows(
  self : ClientEffectSavedFileDispatch,
) -> ((ClientJournalPhysicalRow, Bytes), (ClientJournalPhysicalRow, Bytes)) {
  ((self.before_run, self.next_run), (self.before_witness, self.next_witness))
}

///|
/// The caller must have completed the exact physical Read before this
/// candidate can move to the original current, authorized file boundary.
pub fn ClientEffectSavedFileDispatch::confirmed_operation(
  self : ClientEffectSavedFileDispatch,
  run : ClientJournalPhysicalRow,
  witness : ClientJournalPhysicalRow,
  now : Int64,
) -> @publication.EffectFileOperation? {
  if now < 0L ||
    now >= self.row.application.claim.lease_expires_ms ||
    run.key != self.before_run.key ||
    run.revision != self.before_run.revision + 1L ||
    run.body != self.next_run ||
    witness.key != self.before_witness.key ||
    witness.revision != self.before_witness.revision + 1L ||
    witness.body != self.next_witness {
    None
  } else {
    Some(self.operation)
  }
}

///|
/// Describe the exact candidate operation already joined to this row.
/// Callers still have to reobserve both successor records and current access.
pub fn ClientEffectSavedFileDispatch::dispatch_cid(
  self : ClientEffectSavedFileDispatch,
) -> String {
  self.dispatching.cid
}

///|
/// An already selected UPDATE's exact business input scalars. The current
/// physical File owner supplies the predecessor bytes for version validation.
pub fn ClientEffectSavedFileDispatch::replacement_material(
  self : ClientEffectSavedFileDispatch,
) -> (String, String, String)? {
  let row = self.row
  @publication.effect_preview_ordered_row_intended_value_wire(
    row.preview,
    row.member_index,
    row.ordinal,
  ).map(changes => (row.target, row.version, changes))
}

///|
/// The same claim bounds every use of the selected original file operation.
pub fn ClientEffectSavedFileDispatch::operation_lease_ms(
  self : ClientEffectSavedFileDispatch,
) -> Int64 {
  self.row.application.claim.lease_expires_ms
}

///|
fn exact_retained_file_dispatch_predecessor(
  row : ClientEffectSavedFileRow,
  run : ClientJournalPhysicalRow,
  witness : ClientJournalPhysicalRow,
  previous : ClientEffectSavedFileTerminal?,
  index : Int,
) -> String? {
  let mut position = row.ordinal
  for member_index in 0..<row.member_index {
    position += row.application.keys[member_index].length()
  }
  if index != position || index < 0 {
    return None
  }
  match previous {
    None => {
      if index == 0 &&
        row.application.claim.confirmed(run) is Some(_) &&
        witness.revision == 0L {
        Some("")
      } else {
        None
      }
    }
    Some(original) => {
      let dispatch = original.response.dispatch
      if index != dispatch.index + 1 ||
        !physical_equal(row.application, dispatch.row.application) ||
        !matches_saved_file_journal_successor(original.writes[0], run) ||
        !matches_saved_file_journal_successor(original.writes[1], witness) {
        return None
      }
      Some(original.evidence)
    }
  }
}

///|
fn matches_saved_file_journal_successor(
  write : ClientEffectFileJournalWrite,
  actual : ClientJournalPhysicalRow,
) -> Bool {
  let expected = saved_file_journal_successor(write)
  actual.key == expected.key &&
  actual.revision == expected.revision &&
  actual.body == expected.body
}
