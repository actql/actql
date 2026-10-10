///|
/// Checked completion evidence from the original saved row response. This is
/// neither a publication commit nor a release/cleanup observation. Result,
/// receiver, producer and Ledger custody remain with their existing Owners.
pub(all) struct NativeResidentEffectCompletion {
  preview : @publication.EffectPreviewIdentity
  row_receipt : @publication.PublicationContract
  member_receipt : @publication.PublicationContract
  set_receipt : @publication.PublicationContract
  final_receipt : @publication.PublicationContract
}

///|
pub(all) enum NativeResidentEffectCompletionIssue {
  Unavailable
  EvidenceDenied
  Row(NativeResidentEffectWriteIssue)
  Member(@effect.EffectMemberReceiptEvidenceIssue)
  Set(@publication.EffectSetApplyReceiptIssuanceIssue)
  Final(@publication.EffectfulFinalReceiptIssuanceIssue)
  Chain(@publication.EffectfulFinalChainIssue)
}

///|
/// Re-admit the original Store-owned response before composing common member,
/// set and final receipts. The installed caller must authorize evidence access
/// for this original Run; current apply permission is not required for historical
/// settlement and is never obtained here. No Provider, claim or dispatch runs.
pub fn NativeResidentEffectReview::complete_saved_effect(
  self : NativeResidentEffectReview,
  authorize_evidence_read : () -> Bool,
  limits : NativeResidentEffectWriteLimits,
) -> Result[NativeResidentEffectCompletion, NativeResidentEffectCompletionIssue] {
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  guard !self.closed && !self.retiring && self.captured is Some(capture) else {
    return Err(Unavailable)
  }
  let (row_receipt, terminal) = match self.settle_saved_row(limits) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  // Read the durable head again, rather than treating a cached local terminal
  // as current Store custody. A failed read retains the original pending duty.
  let custody = match self.restore_row_custody(limits.ledger) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Row(ReconciliationRequired))
    Err(issue) => return Err(Row(issue))
  }
  if @effect.effect_ledger_entry_cid(custody.head) !=
    @effect.effect_ledger_entry_cid(terminal) ||
    @effect.effect_ledger_entry_wire(custody.head) !=
    @effect.effect_ledger_entry_wire(terminal) {
    return Err(Row(ReconciliationRequired))
  }
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  if self.closed || self.retiring {
    return Err(Unavailable)
  }
  let context = match self.row_context(limits.ledger) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  let bounds = self.policy.preview_limits
  let member_receipt = match
    @effect.issue_effect_member_receipt_from_row_partition(
      context.preview,
      0,
      [context.scope],
      [context.locator],
      [context.key],
      [context.basis],
      [Some(custody.head)],
      [self.approved_row is Some(row) && row.sending],
      [Some(row_receipt)],
      1,
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Member(issue))
  }
  // Saved-response reconciliation is not another physical execution of a member.
  let set_receipt = match
    @publication.issue_effect_set_apply_receipt_from_members(
      context.preview,
      [member_receipt],
      [false],
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Set(issue))
  }
  let final_receipt = match
    @publication.issue_effectful_final_run_receipt(
      self.materials.run_definition,
      self.result.receipt,
      capture.captured,
      context.preview,
      @publication.publication_contract_json(set_receipt),
      [@publication.publication_contract_json(member_receipt)],
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Final(issue))
  }
  match
    @publication.admit_effectful_final_run_evidence_chain(
      self.materials.run_definition,
      self.invocation,
      [self.result.definition],
      [self.result.artifact],
      self.result.manifest,
      self.result.receipt,
      capture.captured,
      context.preview,
      @publication.publication_contract_json(set_receipt),
      [@publication.publication_contract_json(member_receipt)],
      @publication.publication_contract_json(final_receipt),
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Chain(issue))
  }
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  if self.closed || self.retiring {
    return Err(Unavailable)
  }
  Ok({
    preview: context.preview,
    row_receipt,
    member_receipt,
    set_receipt,
    final_receipt,
  })
}
