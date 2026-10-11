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
  OutputForeign
  OutcomeNotPublishable
  Row(NativeResidentEffectWriteIssue)
  Member(@effect.EffectMemberReceiptEvidenceIssue)
  Set(@publication.EffectSetApplyReceiptIssuanceIssue)
  Final(@publication.EffectfulFinalReceiptIssuanceIssue)
  Chain(@publication.EffectfulFinalChainIssue)
}

///|
/// Expose the original consumer's retained output only after the existing
/// saved-response and final Receipt chain confirm a publishable Effect outcome.
/// No candidate Runtime/Result, new computation or Provider request is accepted.
/// The returned Runtime still owns its payload, input borrow and formal release.
pub fn NativeResidentEffectReview::completed_result_output(
  self : NativeResidentEffectReview,
  authorize_evidence_read : () -> Bool,
  limits : NativeResidentEffectWriteLimits,
) -> Result[
  (@resident.ResidentExecuted, NativeResidentEffectCompletion),
  NativeResidentEffectCompletionIssue,
] {
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  guard self.current() &&
    self.holder.completed_effect_execution(self.journal) is Some(executed) &&
    @remote.dispatch_request_identity(executed.request) ==
    self.dispatch_identity() else {
    return Err(Unavailable)
  }
  guard self.journal.observation(executed.request) is Ok(saved) &&
    @journal.recovered_site_dispatch_subject(saved) is Some(subject) else {
    return Err(Unavailable)
  }
  let fields = @remote.remote_managed_output_subject_projection(subject)
  if fields.length() < 2 {
    return Err(OutputForeign)
  }
  let facts = match
    executed.runtime.inspect_output_facts(executed.request, fields[1]) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  // Equal candidate bytes are not a substitute for the original holder. Match
  // the independently captured Named Result against that Runtime's owned facts.
  guard self.result.output.result_schema_cid() is Ok(schema) &&
    self.result.output.logical_relation_cid() is Ok(logical) &&
    self.result.output.codec_contract_cid() is Ok(codec) &&
    self.result.output.row_count() is Ok(rows) &&
    facts.result_schema_cid == schema &&
    facts.logical_view_cid == logical &&
    facts.representation_codec_cid == codec &&
    facts.row_count == rows else {
    return Err(OutputForeign)
  }
  let completion = match
    self.complete_saved_effect(authorize_evidence_read, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let bounds = self.policy.preview_limits
  // A reconciled rejected/unknown Effect does not become a successful Result.
  // The existing disposition Owner decides; all original custody stays live.
  guard @publication.effect_set_receipt_run_disposition(
      completion.preview,
      @publication.publication_contract_json(completion.set_receipt),
      [@publication.publication_contract_json(completion.member_receipt)],
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    )
    is Ok(0) else {
    return Err(OutcomeNotPublishable)
  }
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  guard self.current() &&
    self.holder.completed_effect_execution(self.journal) is Some(_) else {
    return Err(Unavailable)
  }
  Ok(
    (
      {
        ..executed,
        result_definition_cid: Some(
          @publication.publication_contract_identity(self.result.definition),
        ),
      },
      completion,
    ),
  )
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
