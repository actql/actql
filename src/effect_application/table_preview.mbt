///|
pub(all) enum TablePreviewIssue {
  InvalidMember
  NotWholeOperation
  ApprovalRequired
  ForeignInput
  ForeignRequest
  ForeignGuard
  ForeignState
  ForeignScope
  ForeignKey
} derive(Eq, Debug)

///|
/// A Table member uses one existing Effect item slot for the complete operation,
/// not one slot per input row. This checks approved content, not an apply permit.
/// Current target authority, Catalog installation, source custody and durable
/// claim remain obligations of the existing apply owner.
pub fn check_table_operation_preview(
  operation : TableOperation,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  scope : LogicalRequestScope,
) -> Result[Unit, TablePreviewIssue] {
  if @publication.effect_preview_member_kind(preview, member_index) !=
    Some("store") {
    return Err(InvalidMember)
  }
  if @publication.effect_preview_row_count(preview, member_index) != Some(1) ||
    @publication.effect_preview_member_max_items(preview, member_index) !=
    Some(1L) {
    return Err(NotWholeOperation)
  }
  if @publication.effect_preview_member_approval(preview, member_index) !=
    Some("required") {
    return Err(ApprovalRequired)
  }
  if @publication.effect_preview_member_effect_identity_cid(
      preview, member_index,
    ) !=
    Some(operation.effect_cid) ||
    @publication.effect_preview_member_result_artifact_cid(
      preview, member_index,
    ) !=
    Some(operation.input_artifact_cid) {
    return Err(ForeignInput)
  }
  // The item correlation is the complete request CID. It is neither a table
  // name nor a source-row ordinal, and excludes no approved target material.
  if @publication.effect_preview_row_correlation_wire(preview, member_index, 0) !=
    Some("\"" + operation.cid + "\"") ||
    @publication.effect_preview_row_intended_value_wire(
      preview, member_index, 0,
    ) !=
    Some(operation.wire) {
    return Err(ForeignRequest)
  }
  if operation.scope_cid != logical_request_scope_cid(scope) {
    return Err(ForeignScope)
  }
  // The whole-operation correlation is exactly one quoted SHA-256 CID:
  // 73 UTF-8 bytes, one scalar node, depth one. Reuse the bounded key issuer;
  // semantic Preview identity deliberately excludes this scope-derived key.
  let key = match
    prepare_effect_dispatch_key(
      scope,
      @publication.effect_preview_semantic_identity(preview),
      "\"" + operation.cid + "\"",
      73,
      1,
      1,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignKey)
  }
  if @publication.effect_preview_row_key(preview, member_index, 0) !=
    Some(effect_dispatch_key_cid(key)) {
    return Err(ForeignKey)
  }
  if @publication.effect_preview_row_guard_version_cid(preview, member_index, 0) !=
    operation.expected_generation_cid {
    return Err(ForeignGuard)
  }
  if !@publication.effect_preview_row_states_not_applicable(
      preview, member_index, 0,
    ) {
    return Err(ForeignState)
  }
  Ok(())
}
