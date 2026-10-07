///|
/// Immutable Table material recovered from the exact captured member. The
/// existing Store/Checkpoint/apply owners separately retain custody, confirm
/// availability and authorize continuation; there is no reconstructed Compute.
struct RecoveredClientTablePreview {
  operation : @effect.TableOperation
  mapping : @effect.TableStorageMapping
  preview : @publication.EffectPreviewIdentity
  source : @publication.CapturedEffectSourceArtifact
  member_index : Int
  row_count : Int64
}

///|
pub fn bind_recovered_client_table_preview(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  invocation : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  captured : @publication.PublicationContract,
  scope : @request_scope.LogicalRequestScope,
  mapping_wire : String,
  store_authority_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  table_max_bytes : Int,
  table_max_nodes : Int,
  table_max_depth : Int,
) -> Result[RecoveredClientTablePreview, ClientTableInputIssue] {
  guard @publication.effect_preview_row_intended_value_wire(
      preview, member_index, 0,
    )
    is Some(operation_wire) else {
    return Err(Unavailable)
  }
  let operation = match
    @effect.admit_table_operation(
      operation_wire, table_max_bytes, table_max_nodes, table_max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Operation(issue))
  }
  match
    @effect.check_table_operation_preview(operation, preview, member_index) {
    Ok(_) => ()
    Err(issue) => return Err(Preview(issue))
  }
  let result = match
    @publication.captured_effect_source_result_from_capture(
      preview, member_index, invocation, source, captured, store_authority_cid, max_bytes,
      max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignInput)
  }
  let mapping = match
    @effect.admit_table_storage_mapping(
      mapping_wire, table_max_bytes, table_max_nodes, table_max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  let parsed = match
    @source.parse_json(@publication.publication_contract_json(result), {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let value = @canonical.from_source(parsed, max_nodes, max_depth, max_bytes) catch {
    _ => return Err(Encoding)
  }
  guard @canonical.object_field(value, "logical_result_cid")
    is Some(@canonical.String(relation)) &&
    @canonical.object_field(value, "effective_data_policy_cid")
    is Some(@canonical.String(policy)) &&
    @canonical.object_field(value, "result_schema_cid")
    is Some(@canonical.String(schema)) &&
    @canonical.object_field(value, "actual_row_count")
    is Some(@canonical.Number(rows)) &&
    rows >= 0.0 &&
    rows <= 9007199254740991.0 &&
    rows.to_int64().to_double() == rows &&
    @publication.effect_preview_member_effect_identity_cid(
      preview, member_index,
    )
    is Some(effect_cid) else {
    return Err(ForeignInput)
  }
  if schema != @effect.table_storage_mapping_schema_cid(mapping) ||
    !@effect.table_operation_matches_input(
      operation,
      scope,
      effect_cid,
      @publication.publication_contract_identity(result),
      relation,
      mapping,
      policy,
    ) {
    return Err(ForeignInput)
  }
  Ok({
    operation,
    mapping,
    preview,
    source,
    member_index,
    row_count: rows.to_int64(),
  })
}

///|
pub fn recovered_client_table_preview_operation(
  value : RecoveredClientTablePreview,
) -> @effect.TableOperation {
  value.operation
}

///|
pub fn recovered_client_table_preview_mapping(
  value : RecoveredClientTablePreview,
) -> @effect.TableStorageMapping {
  value.mapping
}

///|
pub fn recovered_client_table_preview_ledger_identity(
  value : RecoveredClientTablePreview,
) -> @publication.EffectPreviewIdentity {
  value.preview
}

///|
pub fn recovered_client_table_preview_member_index(
  value : RecoveredClientTablePreview,
) -> Int {
  value.member_index
}

///|
pub fn recovered_client_table_preview_matches_source(
  value : RecoveredClientTablePreview,
  source : @publication.CapturedEffectSourceArtifact,
) -> Bool {
  physical_equal(value.source, source)
}

///|
pub fn recovered_client_table_preview_commit_outcome(
  value : RecoveredClientTablePreview,
  response_wire : String,
  status_code : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientTableInputIssue] {
  @effect.project_table_commit_outcome(
    value.operation,
    response_wire,
    status_code,
    value.row_count,
    max_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => Commit(issue))
}
