///|
// The existing installed row owner's dispatch/recovery preimages. This is
// deliberately not a RemoteDispatch issuer and does not recompute the already
// checked Preview capability, key or original source/request ordering.
pub fn retained_effect_application_row_basis(
  preview : @publication.EffectPreviewIdentity,
  scope : LogicalRequestScope,
  key : EffectDispatchKey,
  program_id : String,
  node_id : String,
  unit_definition_cid : String,
  invocation_cid : String,
  member_index : Int,
  row_ordinal : Int,
  canonical_request_cid : String,
  retention_contract_cid : String,
  max_name_bytes : Int,
) -> Result[(LogicalItemLocator, EffectDispatchKey, EffectLedgerBasis), Unit] {
  guard @publication.effect_preview_member_effect_id(preview, member_index)
    is Some(effect_id) &&
    @publication.effect_preview_member_kind(preview, member_index) is Some(kind) &&
    @publication.effect_preview_member_identity(preview, member_index)
    is Some(member_cid) &&
    @publication.effect_preview_member_capability_evidence_cid(
      preview, member_index,
    )
    is Some(capability) &&
    @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_ordinal,
    )
    is Some(row) &&
    @publication.effect_preview_ordered_row_correlation_wire(
      preview, member_index, row_ordinal,
    )
    is Some(correlation) else {
    return Err(())
  }
  let (item_bytes, item_nodes, item_depth) = effect_dispatch_key_codec_limits()
  let locator = match
    prepare_logical_item_locator(
      scope, program_id, node_id, effect_id, correlation, max_name_bytes, item_bytes,
      item_nodes, item_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  if admit_effect_single_row(
      preview, member_index, row_ordinal, kind, scope, row, locator, key,
    )
    is Err(_) {
    return Err(())
  }
  let recovery = try {
    let writer = @encode.hashing_writer(1024 + effect_id.length() * 6, 8, 3)
    @encode.begin_object(writer)
    @encode.key(writer, "effect_id")
    @encode.string_value(writer, effect_id)
    @encode.key(writer, "run_invocation_cid")
    @encode.string_value(writer, invocation_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-installed-row-effect-dispatch/0.1")
    @encode.end_object(writer)
    let dispatch = "sha256:" + @encode.finish_hash(writer)
    let writer = @encode.hashing_writer(1024, 4, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-installed-row-effect-recovery/0.1")
    @encode.end_object(writer)
    "sha256:" + @encode.finish_hash(writer)
  } catch {
    _ => return Err(())
  }
  match
    prepare_effect_ledger_basis(
      scope, locator, key, unit_definition_cid, member_cid, row, canonical_request_cid,
      recovery, "unavailable", capability, retention_contract_cid,
    ) {
    Ok(basis) => Ok((locator, key, basis))
    Err(_) => Err(())
  }
}
