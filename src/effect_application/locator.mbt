///|
pub struct LogicalItemLocator {
  logical_request_scope_cid : String
  program_id : String
  node_id : String
  effect_id : String
  item_correlation_wire : String
  cid : String
}

///|
pub struct EffectApplyKey {
  logical_request_scope_cid : String
  effect_preview_cid : String
  effect_id : String
  effect_member_preview_cid : String
  cid : String
}

///|
pub fn prepare_logical_item_locator(
  scope : LogicalRequestScope,
  program_id : String,
  node_id : String,
  effect_id : String,
  item_correlation_wire : String,
  max_name_bytes : Int,
  max_item_bytes : Int,
  max_item_nodes : Int,
  max_item_depth : Int,
) -> Result[LogicalItemLocator, EffectIdentityIssue] {
  if max_name_bytes < 1 ||
    max_name_bytes > 1000000 ||
    max_item_bytes < 1 ||
    max_item_bytes > 1000000 ||
    max_item_nodes < 1 ||
    max_item_nodes > 1000 ||
    max_item_depth < 1 ||
    max_item_depth > 32 {
    return Err(InvalidLimits)
  }
  if !canonical_bounded_text(program_id, max_name_bytes) ||
    !canonical_bounded_text(node_id, max_name_bytes) {
    return Err(InvalidUnitNamespace)
  }
  if !canonical_bounded_text(effect_id, max_name_bytes) {
    return Err(InvalidEffect)
  }
  let item = match
    effect_canonical_json_value(
      item_correlation_wire, max_item_bytes, max_item_nodes, max_item_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidItemCorrelation)
  }
  let writer = @encode.hashing_writer(
    max_item_bytes + max_name_bytes * 18 + 512,
    max_item_nodes + 8,
    max_item_depth + 2,
  ) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "effect_id")
    @encode.string_value(writer, effect_id)
    @encode.key(writer, "item_correlation")
    @json.emit_value(item, writer)
    @encode.key(writer, "logical_request_scope_cid")
    @encode.string_value(writer, scope.cid)
    @encode.key(writer, "unit_namespace")
    @encode.begin_object(writer)
    @encode.key(writer, "node_id")
    @encode.string_value(writer, node_id)
    @encode.key(writer, "program_id")
    @encode.string_value(writer, program_id)
    @encode.end_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-logical-item/0.1")
    @encode.end_object(writer)
    Ok({
      logical_request_scope_cid: scope.cid,
      program_id,
      node_id,
      effect_id,
      item_correlation_wire,
      cid: "sha256:" + @encode.finish_hash(writer),
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn logical_item_locator_cid(locator : LogicalItemLocator) -> String {
  locator.cid
}

///|
pub fn prepare_effect_apply_key(
  scope : LogicalRequestScope,
  effect_preview_cid : String,
  effect_id : String,
  effect_member_preview_cid : String,
  max_effect_bytes : Int,
) -> Result[EffectApplyKey, EffectIdentityIssue] {
  if max_effect_bytes < 1 || max_effect_bytes > 1000000 {
    return Err(InvalidLimits)
  }
  if !effect_cid_valid(effect_preview_cid) {
    return Err(InvalidPreview)
  }
  if !effect_cid_valid(effect_member_preview_cid) {
    return Err(InvalidMemberPreview)
  }
  if !canonical_bounded_text(effect_id, max_effect_bytes) {
    return Err(InvalidEffect)
  }
  let writer = @encode.hashing_writer(max_effect_bytes * 6 + 512, 6, 1) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "effect_id")
    @encode.string_value(writer, effect_id)
    @encode.key(writer, "effect_member_preview_cid")
    @encode.string_value(writer, effect_member_preview_cid)
    @encode.key(writer, "effect_preview_cid")
    @encode.string_value(writer, effect_preview_cid)
    @encode.key(writer, "logical_request_scope_cid")
    @encode.string_value(writer, scope.cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-apply-idempotency-key/0.1")
    @encode.end_object(writer)
    Ok({
      logical_request_scope_cid: scope.cid,
      effect_preview_cid,
      effect_id,
      effect_member_preview_cid,
      cid: "sha256:" + @encode.finish_hash(writer),
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn effect_apply_key_cid(key : EffectApplyKey) -> String {
  key.cid
}
