///|
pub(all) enum EffectIdentityIssue {
  InvalidAuthorityScope
  InvalidPreview
  InvalidEffect
  InvalidUnitNamespace
  InvalidItemCorrelation
  InvalidMemberPreview
  InvalidCallerRequest
  InvalidRowKey
  InvalidLimits
  CapacityExceeded
  Encoding
} derive(Eq, Debug)

///|
pub type LogicalRequestScope = @request_scope.LogicalRequestScope

///|
pub struct EffectDispatchKey {
  logical_request_scope_cid : String
  effect_preview_cid : String
  row_or_item_key_wire : String
  cid : String
}

///|
fn effect_cid_valid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let digit = value[index]
    if !((digit >= '0' && digit <= '9') || (digit >= 'a' && digit <= 'f')) {
      return false
    }
  }
  true
}

///|
fn canonical_bounded_text(value : String, max_bytes : Int) -> Bool {
  if value.is_empty() || max_bytes < 1 || value.length() > max_bytes {
    return false
  }
  match @canonical.normalize_nfc_lf(value) {
    Ok(normalized) =>
      normalized == value && @utf8.encode(value).length() <= max_bytes
    Err(_) => false
  }
}

///|
fn effect_canonical_json_value(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@json.CanonicalValue, EffectIdentityIssue] {
  if wire.is_empty() || @utf8.encode(wire).length() > max_bytes {
    return Err(InvalidRowKey)
  }
  let parsed = match
    @source.parse_json(wire, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidRowKey)
  }
  let value = @json.from_source(parsed, max_nodes, max_depth, max_bytes) catch {
    _ => return Err(InvalidRowKey)
  }
  if value is @json.Null {
    return Err(InvalidRowKey)
  }
  let canonical = @json.stringify_value(value, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  if canonical != wire {
    return Err(InvalidRowKey)
  }
  Ok(value)
}

///|
pub fn prepare_logical_request_scope(
  authority_scope_cid : String,
  caller_request_id : String,
  max_caller_bytes : Int,
) -> Result[LogicalRequestScope, EffectIdentityIssue] {
  match
    @request_scope.prepare_logical_request_scope(
      authority_scope_cid, caller_request_id, max_caller_bytes,
    ) {
    Ok(scope) => Ok(scope)
    Err(@request_scope.InvalidAuthorityScope) => Err(InvalidAuthorityScope)
    Err(@request_scope.InvalidCallerRequest) => Err(InvalidCallerRequest)
    Err(@request_scope.InvalidLimits) => Err(InvalidLimits)
    Err(@request_scope.Encoding) => Err(Encoding)
  }
}

///|
pub fn logical_request_scope_cid(scope : LogicalRequestScope) -> String {
  @request_scope.logical_request_scope_cid(scope)
}

///|
pub fn prepare_effect_dispatch_key(
  scope : LogicalRequestScope,
  effect_preview_cid : String,
  row_or_item_key_wire : String,
  max_key_bytes : Int,
  max_key_nodes : Int,
  max_key_depth : Int,
) -> Result[EffectDispatchKey, EffectIdentityIssue] {
  if max_key_bytes < 1 ||
    max_key_bytes > 1000000 ||
    max_key_nodes < 1 ||
    max_key_nodes > 1000 ||
    max_key_depth < 1 ||
    max_key_depth > 32 {
    return Err(InvalidLimits)
  }
  if !effect_cid_valid(effect_preview_cid) {
    return Err(InvalidPreview)
  }
  let key = match
    effect_canonical_json_value(
      row_or_item_key_wire, max_key_bytes, max_key_nodes, max_key_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.hashing_writer(
    max_key_bytes + 320,
    max_key_nodes + 4,
    max_key_depth + 1,
  ) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "effect_preview_cid")
    @encode.string_value(writer, effect_preview_cid)
    @encode.key(writer, "logical_request_scope_cid")
    @encode.string_value(writer, logical_request_scope_cid(scope))
    @encode.key(writer, "row_or_item_key")
    @json.emit_value(key, writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-row-idempotency-key/0.1")
    @encode.end_object(writer)
    Ok({
      logical_request_scope_cid: logical_request_scope_cid(scope),
      effect_preview_cid,
      row_or_item_key_wire,
      cid: "sha256:" + @encode.finish_hash(writer),
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn effect_dispatch_key_cid(key : EffectDispatchKey) -> String {
  key.cid
}

///|
pub fn effect_dispatch_key_preview_cid(key : EffectDispatchKey) -> String {
  key.effect_preview_cid
}

///|
pub fn effect_dispatch_key_scope_cid(key : EffectDispatchKey) -> String {
  key.logical_request_scope_cid
}

///|
/// One physical batch may contain rows from only one member identity and
/// Preview. Checked inventory admission is a separate obligation. Distinct
/// row keys are checked by the dispatch owner.
pub fn effect_batch_rows_share_member(
  first_locator : LogicalItemLocator,
  first_key : EffectDispatchKey,
  next_locator : LogicalItemLocator,
  next_key : EffectDispatchKey,
) -> Bool {
  first_locator.logical_request_scope_cid == first_key.logical_request_scope_cid &&
  next_locator.logical_request_scope_cid == next_key.logical_request_scope_cid &&
  first_locator.logical_request_scope_cid ==
  next_locator.logical_request_scope_cid &&
  first_locator.program_id == next_locator.program_id &&
  first_locator.node_id == next_locator.node_id &&
  first_locator.effect_id == next_locator.effect_id &&
  first_key.effect_preview_cid == next_key.effect_preview_cid
}
