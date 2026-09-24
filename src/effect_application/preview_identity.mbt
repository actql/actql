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
  match
    check_admitted_effect_preview_apply_keys(identity, scope, expected_keys) {
    Ok(_) => Ok(identity)
    Err(issue) => Err(issue)
  }
}

///|
/// Check derived row keys against the already admitted private Preview. This
/// retains its exact owner; no transported body is reparsed or renewed.
pub fn check_admitted_effect_preview_apply_keys(
  identity : @publication.EffectPreviewIdentity,
  scope : LogicalRequestScope,
  expected_keys : Array[Array[EffectDispatchKey]],
) -> Result[Unit, EffectPreviewApplyIdentityIssue] {
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
      if key.logical_request_scope_cid != logical_request_scope_cid(scope) {
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
  Ok(())
}

///|
pub(all) enum EffectCollectionBatchIssue {
  InvalidLimits
  InvalidMember
  ForeignKind
  ForeignPolicy
  InvalidSlice
  CapacityExceeded
  ForeignRow(Int)
  ForeignKey(Int)
  ForeignLocator(Int)
} derive(Eq, Debug)

///|
/// Bind one physical send to the admitted Preview's stable row order and
/// derived keys. This does not replace whole-set preflight or authorization.
fn admit_effect_member_slice(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  first_row : Int,
  effect_kind : String,
  collection : Bool,
  scope : LogicalRequestScope,
  row_cids : Array[String],
  locators : Array[LogicalItemLocator],
  keys : Array[EffectDispatchKey],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, EffectCollectionBatchIssue] {
  if max_rows < 1 || max_rows > 200 || max_work < 1 {
    return Err(InvalidLimits)
  }
  let count = row_cids.length()
  if count < 1 ||
    count > max_rows ||
    locators.length() != count ||
    keys.length() != count {
    return Err(InvalidSlice)
  }
  let effect_id = match
    @publication.effect_preview_member_effect_id(preview, member_index) {
    Some(value) => value
    None => return Err(InvalidMember)
  }
  if @publication.effect_preview_member_kind(preview, member_index) !=
    Some(effect_kind) {
    return Err(ForeignKind)
  }
  if collection &&
    @publication.effect_preview_member_failure_policy(preview, member_index) !=
    Some("continue") {
    return Err(ForeignPolicy)
  }
  let total = @publication.effect_preview_row_count(preview, member_index).unwrap()
  if first_row < 0 || first_row > total || count > total - first_row {
    return Err(InvalidSlice)
  }
  if count > max_work - 1 {
    return Err(CapacityExceeded)
  }
  let preview_cid = @publication.effect_preview_semantic_identity(preview)
  for offset in 0..<count {
    let expected = @publication.effect_preview_ordered_row_identity(
      preview,
      member_index,
      first_row + offset,
    ).unwrap()
    if row_cids[offset] != expected {
      return Err(ForeignRow(offset))
    }
    let index = @publication.effect_preview_row_index(
      preview, member_index, expected,
    ).unwrap()
    if keys[offset].logical_request_scope_cid !=
      logical_request_scope_cid(scope) ||
      keys[offset].effect_preview_cid != preview_cid ||
      @publication.effect_preview_row_key(preview, member_index, index) !=
      Some(keys[offset].cid) {
      return Err(ForeignKey(offset))
    }
    let locator = locators[offset]
    if locator.logical_request_scope_cid != logical_request_scope_cid(scope) ||
      locator.effect_id != effect_id ||
      @publication.effect_preview_row_correlation_wire(
        preview, member_index, index,
      ) !=
      Some(locator.item_correlation_wire) ||
      keys[offset].row_or_item_key_wire != locator.item_correlation_wire {
      return Err(ForeignLocator(offset))
    }
    if offset > 0 &&
      !effect_batch_rows_share_member(
        locators[0],
        keys[0],
        locator,
        keys[offset],
      ) {
      return Err(ForeignLocator(offset))
    }
  }
  Ok(())
}

///|
/// Collections may batch only rows from one `continue` member.
pub fn admit_effect_collection_batch(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  first_row : Int,
  effect_kind : String,
  scope : LogicalRequestScope,
  row_cids : Array[String],
  locators : Array[LogicalItemLocator],
  keys : Array[EffectDispatchKey],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, EffectCollectionBatchIssue] {
  admit_effect_member_slice(
    preview, member_index, first_row, effect_kind, true, scope, row_cids, locators,
    keys, max_rows, max_work,
  )
}

///|
/// Ordered halt and continue both use one-row REST dispatch when admitted.
pub fn admit_effect_single_row(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  effect_kind : String,
  scope : LogicalRequestScope,
  row_cid : String,
  locator : LogicalItemLocator,
  key : EffectDispatchKey,
) -> Result[Unit, EffectCollectionBatchIssue] {
  admit_effect_member_slice(
    preview,
    member_index,
    row_index,
    effect_kind,
    false,
    scope,
    [row_cid],
    [locator],
    [key],
    1,
    2,
  )
}
