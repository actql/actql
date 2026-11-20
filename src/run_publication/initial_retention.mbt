///|
// One explicit selection, not Host clock/profile selection or a Resource grant.
// Both passes use this same emitter without a temporary field/tuple inventory.
fn emit_initial_retention(
  writer : @encode.Writer,
  retention_contract_cid : String,
  effective_data_policy_cid : String,
  available_until : String,
  delete_by : String,
  extension_ceiling_at : String,
  metadata_retention_policy_cid : String,
  metadata_delete_by : String,
  clock_contract_cid : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "available_until")
  @encode.string_value(writer, available_until)
  @encode.key(writer, "clock_contract_cid")
  @encode.string_value(writer, clock_contract_cid)
  @encode.key(writer, "delete_by")
  @encode.string_value(writer, delete_by)
  @encode.key(writer, "effective_data_policy_cid")
  @encode.string_value(writer, effective_data_policy_cid)
  @encode.key(writer, "extension_ceiling_at")
  @encode.string_value(writer, extension_ceiling_at)
  @encode.key(writer, "metadata_delete_by")
  @encode.string_value(writer, metadata_delete_by)
  @encode.key(writer, "metadata_retention_policy_cid")
  @encode.string_value(writer, metadata_retention_policy_cid)
  @encode.key(writer, "retention_contract_cid")
  @encode.string_value(writer, retention_contract_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-result-retention-policy/0.1")
  @encode.end_object(writer)
}

///|
/// Measure the original selected fields before constructing their contract.
/// The caller must fund this measurement and its result on its existing Owner.
pub fn initial_result_retention_construction_geometry(
  retention_contract_cid : String,
  effective_data_policy_cid : String,
  available_until : String,
  delete_by : String,
  extension_ceiling_at : String,
  metadata_retention_policy_cid : String,
  metadata_delete_by : String,
  clock_contract_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@encode.EncodingConstructionGeometry, PublicationContractIssue] {
  let writer = @encode.construction_measuring_writer(
    max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidLimits)
  }
  try {
    emit_initial_retention(
      writer, retention_contract_cid, effective_data_policy_cid, available_until,
      delete_by, extension_ceiling_at, metadata_retention_policy_cid, metadata_delete_by,
      clock_contract_cid,
    )
    Ok(@encode.finish_construction_measurement(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(Encoding)
    }
  }
}

///|
/// Pure envelope DATA. Existing closed contract validation and canonical CID
/// rules remain authoritative; supplied timestamps do not extend custody.
pub fn issue_initial_result_retention(
  retention_contract_cid : String,
  effective_data_policy_cid : String,
  available_until : String,
  delete_by : String,
  extension_ceiling_at : String,
  metadata_retention_policy_cid : String,
  metadata_delete_by : String,
  clock_contract_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(InvalidLimits)
  }
  let body = try {
    emit_initial_retention(
      writer, retention_contract_cid, effective_data_policy_cid, available_until,
      delete_by, extension_ceiling_at, metadata_retention_policy_cid, metadata_delete_by,
      clock_contract_cid,
    )
    @encode.finish(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(Encoding)
    }
  }
  seal_publication_contract(
    "result_retention_policy", body, max_bytes, max_nodes, max_depth,
  )
}
