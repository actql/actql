///|
pub(all) enum EffectPreviewApplyIdentityIssue {
  Preview(@publication.EffectPreviewIdentityIssue)
  KeyInventoryMismatch
  ForeignKeyScope(Int, Int)
  ForeignKeyPreview(Int, Int)
  RowKeyMismatch(Int, Int)
} derive(Debug)

///|
/// The expected keys must be derived from checked row or item identities,
/// not copied from the transported Preview. This checks the excluded
/// physical bindings without adding them to the semantic CID preimage.
pub fn admit_effect_preview_apply_identity(
  preview_wire : String,
  expected_run_identity_cid : String,
  expected_authoring_context_cid : String,
  scope : LogicalRequestScope,
  expected_keys : Array[Array[EffectDispatchKey]],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.EffectPreviewIdentity, EffectPreviewApplyIdentityIssue] {
  let identity = match
    @publication.admit_effect_preview_identity(
      preview_wire, expected_run_identity_cid, expected_authoring_context_cid, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  let preview_cid = @publication.effect_preview_semantic_identity(identity)
  if expected_keys.length() !=
    @publication.effect_preview_member_count(identity) {
    return Err(KeyInventoryMismatch)
  }
  for member_index in 0..<expected_keys.length() {
    let expected_rows = expected_keys[member_index]
    let row_count = match
      @publication.effect_preview_row_count(identity, member_index) {
      Some(value) => value
      None => return Err(KeyInventoryMismatch)
    }
    if expected_rows.length() != row_count {
      return Err(KeyInventoryMismatch)
    }
    for row_index in 0..<row_count {
      let key = expected_rows[row_index]
      if key.logical_request_scope_cid != scope.cid {
        return Err(ForeignKeyScope(member_index, row_index))
      }
      if key.effect_preview_cid != preview_cid {
        return Err(ForeignKeyPreview(member_index, row_index))
      }
      if @publication.effect_preview_row_key(identity, member_index, row_index) !=
        Some(key.cid) {
        return Err(RowKeyMismatch(member_index, row_index))
      }
    }
  }
  Ok(identity)
}
