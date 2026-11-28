///|
/// A checked row from the original saved Preview. It has no dispatch permit
/// until the separate prepared/dispatching Ledger transition is confirmed.
pub struct ClientEffectSavedFileRow {
  application : ClientEffectSavedApplication
  preview : @publication.EffectPreviewIdentity
  locator : @effect.LogicalItemLocator
  key : @effect.EffectDispatchKey
  basis : @effect.EffectLedgerBasis
  request : String
  request_cid : String
  installation_cid : String
  target : String
  version : String
  changes : @canonical.CanonicalValue
  member_index : Int
  ordinal : Int
}

///|
pub fn ClientEffectSavedApplication::prepare_file_row(
  self : ClientEffectSavedApplication,
  member_index : Int,
  ordinal : Int,
  binding : String,
  mapping : String,
  now_ms : Int64,
  limits : @checkpoint.WireLimits,
  fund : (Int, Int, Int) -> Bool,
) -> Result[ClientEffectSavedFileRow, ClientEffectResolutionOriginalIssue] {
  let review = self.computation.preview
  guard self.ordered_original(member_index, ordinal, now_ms)
    is Some((preview, scope, key, row)) &&
    review.program_id is Some(program_id) &&
    review.unit_definition_cid is Some(unit_definition_cid) &&
    review.waiting.checkpoint.artifact.checkpoint.subject
    is @checkpoint.RunUnit(unit_id~, ..) &&
    @publication.effect_preview_member_source_binding_cid(preview, member_index) ==
    Some(binding) &&
    @publication.effect_preview_member_resolved_contract(preview, member_index)
    is Some(@publication.Mapping(_, original_mapping)) &&
    original_mapping == mapping &&
    @publication.effect_preview_member_kind(preview, member_index) ==
    Some("update") &&
    @publication.effect_preview_member_effect_id(preview, member_index)
    is Some(effect_id) &&
    @canonical.object_field(row, "target_row_identity") is Some(target_value) &&
    target_value is @canonical.String(target) &&
    @canonical.object_field(row, "before") is Some(before) &&
    @canonical.object_field(before, "state")
    is Some(@canonical.String("present")) &&
    @canonical.object_field(before, "value") is Some(full_before) &&
    @canonical.object_field(row, "intended_changes") is Some(intended) &&
    @canonical.object_field(intended, "state")
    is Some(@canonical.String("present")) &&
    @canonical.object_field(intended, "value") is Some(changes) &&
    @canonical.object_field(row, "target_guard") is Some(guard_value) &&
    @canonical.object_field(guard_value, "state")
    is Some(@canonical.String("version")) &&
    @canonical.object_field(guard_value, "version_cid")
    is Some(@canonical.String(version)) &&
    @publication.captured_run_effect_source_retention_cid(
      @publication.prepared_captured_effect_run_contract(
        self.computation.capture,
      ),
      effect_id,
    )
    is Some(retention) &&
    fund(0, 16 + 4 * limits.max_depth, limits.max_depth) &&
    measure_client_effect_file_request(
      binding,
      mapping,
      target_value,
      Some(changes),
      full_before,
      version,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Ok((bytes, nodes, depth)) &&
    fund(bytes, nodes, depth) &&
    client_effect_file_request_wire(
      binding,
      mapping,
      target_value,
      Some(changes),
      full_before,
      version,
      bytes,
      nodes,
      depth,
    )
    is Ok(request) &&
    @sha.text_hex(request) is Ok(digest) else {
    return Err(InvalidOriginal)
  }
  let request_cid = "sha256:" + digest
  let max_name = 3 *
    Int::max(
      program_id.length(),
      Int::max(unit_id.length(), effect_id.length()),
    )
  let (key_bytes, key_nodes, key_depth) = @effect.effect_dispatch_key_codec_limits()
  guard @scalar.admit_utf8_length(
      @effect.effect_dispatch_key_correlation_wire(key),
      key_bytes,
    )
    is Ok(correlation_bytes) &&
    fund(
      correlation_bytes + 18 * max_name + 1536,
      key_nodes + 32,
      key_depth + 2,
    ) &&
    @effect.retained_effect_application_row_basis(
      preview,
      scope,
      key,
      program_id,
      unit_id,
      unit_definition_cid,
      review.preview.invocation_cid,
      member_index,
      ordinal,
      request_cid,
      retention,
      max_name,
    )
    is Ok((locator, key, basis)) else {
    return Err(InvalidOriginal)
  }
  Ok({
    application: self,
    preview,
    locator,
    key,
    basis,
    request,
    request_cid,
    installation_cid: binding,
    target,
    version,
    changes,
    member_index,
    ordinal,
  })
}

///|
/// Confirm the retained row still belongs to the selected Check target.
pub fn ClientEffectSavedFileRow::matches_target(
  self : ClientEffectSavedFileRow,
  binding : String,
  reference : String,
  mapping : String,
) -> Bool {
  self.installation_cid == binding &&
  self.application.file_member(self.member_index)
  is Some((expected_binding, expected_reference, expected_mapping, count)) &&
  expected_binding == binding &&
  expected_reference == reference &&
  expected_mapping == mapping &&
  self.ordinal >= 0 &&
  self.ordinal < count
}

///|
/// Bind the canonical target identity to the same selected File path and
/// the original row selector, under the established file operation codec.
pub fn ClientEffectSavedFileRow::selected_file_target(
  self : ClientEffectSavedFileRow,
  path : String,
  resource : String,
  limits : @checkpoint.WireLimits,
  fund : (Int, Int, Int) -> Bool,
) -> String? {
  let correlation = @effect.effect_dispatch_key_correlation_wire(self.key)
  guard path.has_prefix("/") &&
    @scalar.admit_utf8_length(path, limits.max_wire_bytes) is Ok(path_bytes) &&
    @scalar.admit_utf8_length(resource, limits.max_wire_bytes)
    is Ok(resource_bytes) &&
    @scalar.admit_utf8_length(correlation, limits.max_wire_bytes)
    is Ok(row_bytes) &&
    fund(
      512 + 6 * (path_bytes + resource_bytes + row_bytes),
      Int::min(limits.max_nodes, 32 + row_bytes),
      limits.max_depth,
    ) else {
    return None
  }
  let mut separator = 0
  for index in 1..<path.length() {
    if path[index] == '/'.to_int().to_uint16() {
      separator = index
    }
  }
  let directory = if separator == 0 { "/" } else { path[:separator].to_owned() }
  let name = path[separator + 1:].to_owned()
  @publication.effect_file_target_cid(
    self.installation_cid,
    directory,
    name,
    resource,
    correlation,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).to_option()
}
