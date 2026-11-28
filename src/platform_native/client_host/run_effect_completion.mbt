///|
priv struct NativeLocalEffectPublicationSettlement {
  claim : NativeClientEffectResumeClaim
  preview : @publication.EffectPreviewIdentity
  outcomes : @publication.EffectSetApplyReceiptEvidence
  members : Array[@publication.PublicationContract]
  current : () -> Bool
}

///|
// Match every original head to the exact receipt referenced by the committed
// Set. The Run reader and CAS independently authenticate ledger, receipt and
// response bodies against the original physical witness in this transaction.
fn NativeClientRunJournal::require_file_effect_completion_locked(
  self : Self,
  record : NativeClientRunRecord,
  settlement : NativeLocalEffectPublicationSettlement,
  reads : NativeClientJournalReadAccess?,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard self.transaction_active &&
    record.checkpoint is Some(checkpoint) &&
    checkpoint.unknown_effects.is_empty() &&
    !checkpoint.settlement_only &&
    !record.cancellation_requested() &&
    @publication.effect_preview_run_identity(settlement.preview) ==
    @publication.publication_contract_identity(record.definition) &&
    @publication.effect_preview_semantic_identity(settlement.preview) ==
    checkpoint.artifact.checkpoint.required_artifact_cid &&
    @publication.effect_set_apply_receipt_disposition(settlement.outcomes) == 0 &&
    @publication.effect_set_apply_receipt_matches_members(
      settlement.outcomes,
      settlement.preview,
      settlement.members,
    ) else {
    return Err(Checkpoint(InvalidMaterial))
  }
  let mut rows = 0
  for member_index, receipt in settlement.members {
    guard @publication.effect_preview_row_count(
        settlement.preview,
        member_index,
      )
      is Some(count) else {
      return Err(Checkpoint(InvalidMaterial))
    }
    for ordinal in 0..<count {
      guard @publication.effect_preview_ordered_row_identity(
          settlement.preview,
          member_index,
          ordinal,
        )
        is Some(row) &&
        @publication.effect_apply_receipt_row_state(receipt, row) ==
        Some("applied") &&
        @publication.effect_apply_receipt_row_field(
          receipt, row, "dispatch_entry_cid",
        )
        is Some(dispatch_cid) &&
        @publication.effect_apply_receipt_row_field(
          receipt, row, "outcome_receipt_cid",
        )
        is Some(outcome_cid) &&
        checkpoint.effect_ledger
        .iter()
        .find_first(entry => {
          entry.cid == dispatch_cid &&
          @effect.effect_ledger_entry_state_code(entry) == 1
        })
        is Some(dispatch) &&
        effect_ledger_head(
          checkpoint.effect_ledger,
          dispatch.logical_item_locator_cid,
        )
        is Some(head) &&
        @effect.effect_ledger_entry_state_code(head) == 2 &&
        head.outcome_receipt_cid == Some(outcome_cid) &&
        head.attempt_sequence == dispatch.attempt_sequence &&
        @publication.effect_apply_receipt_row_attempt_sequence(receipt, row) ==
        Some(dispatch.attempt_sequence) else {
        return Err(Checkpoint(InvalidMaterial))
      }
      let original = match
        read_client_effect_receipt(self.database, head, reads~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if @publication.effect_row_outcome_receipt_row_identity(original) !=
        Some(row) ||
        @publication.effect_row_outcome_receipt_dispatch_identity(original) !=
        Some(dispatch_cid) {
        return Err(CustodyLost)
      }
      rows += 1
    }
  }
  let mut heads = 0
  for entry in checkpoint.effect_ledger {
    if effect_ledger_head(
        checkpoint.effect_ledger,
        entry.logical_item_locator_cid,
      ).map(value => value.cid) ==
      Some(entry.cid) {
      if @effect.effect_ledger_entry_state_code(entry) != 2 {
        return Err(Checkpoint(InvalidMaterial))
      }
      heads += 1
    }
  }
  if rows != heads {
    return Err(Checkpoint(InvalidMaterial))
  }
  Ok(())
}

///|
fn NativeClientRunJournal::require_current_file_effect_settlement_locked(
  self : Self,
  claim : NativeClientEffectResumeClaim,
  now : Int64,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard self.transaction_active else { return Err(CustodyLost) }
  match self.effect_resume_fence_locked(claim, now, reads~) {
    Ok(Current) => Ok(())
    Ok(SettlementOnly | Stale) => Err(Checkpoint(StaleRevision))
    Err(issue) => Err(issue)
  }
}

///|
fn NativeClientRunJournal::finish_file_effect_resume_locked(
  self : Self,
  record : NativeClientRunRecord,
  observed : NativeLocalObservedRunState,
  state_wire : String,
  settlement : NativeLocalEffectPublicationSettlement,
  operations : NativeClientJournalOperationAccess?,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  guard self.transaction_active &&
    record.checkpoint is Some(checkpoint) &&
    checkpoint.resume_intent is Some(intent) &&
    @host.client_request_identity_relation(
      record.request,
      settlement.claim.request,
    )
    is @host.SameRequest else {
    return Err(Checkpoint(InvalidMaterial))
  }
  let reads = operations.map(value => value.reads)
  guard @scalar.admit_utf8_length(state_wire, 65536) is Ok(bytes) && bytes > 0 else {
    return Err(Checkpoint(InvalidMaterial))
  }
  let nodes = Int::min(bytes, 4096)
  if run_metadata_construction(self.database, reads) is Some(reserve) {
    guard @publication.run_state_observation_construction_inventory(
        bytes, nodes, 64,
      )
      is Some((retained, workspace)) &&
      observed_read_inventory_cost(retained) is Some(r) &&
      observed_read_inventory_cost(workspace) is Some(w) &&
      @execution.checked_preparation_add_product(r, w, 1L) is Some(e) else {
      return Err(CapacityExceeded)
    }
    let raw = @sqlite.publication_construction_block_bound(nodes, nodes, bytes)
    if raw < 1L {
      return Err(CapacityExceeded)
    }
    match reserve(r, e, raw) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  guard @checkpoint.admit_run_state_wire(state_wire, {
      max_wire_bytes: bytes,
      max_nodes: nodes,
      max_depth: 64,
    })
    is Ok(state) &&
    state.status == @publication.Succeeded &&
    state.wire == state_wire &&
    @checkpoint.resume_completion_allowed(state.status) else {
    return Err(Checkpoint(InvalidMaterial))
  }
  if !(settlement.current)() {
    return Err(AuthorizationDenied)
  }
  match
    self.require_current_file_effect_settlement_locked(
      settlement.claim,
      @env.now().reinterpret_as_int64(),
      reads~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let completed = {
    ..record,
    checkpoint: Some({
      ..checkpoint,
      state,
      updated_at: observed.observed_at,
      resume_intent: Some({ ..intent, state: @checkpoint.ResumeCompleted, }),
    }),
  }
  let saved = match self.save_with_operations(completed, operations~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Recheck the generation's actual deadline after encoding and CAS. A late
  // refusal rolls back both the Run and its adjacent Submission projection.
  if !(settlement.current)() ||
    @checkpoint.decide_resume_fence(
      intent,
      settlement.claim.claim,
      @env.now().reinterpret_as_int64(),
    ) !=
    @checkpoint.FenceCurrent {
    return Err(Checkpoint(StaleRevision))
  }
  Ok(saved)
}
