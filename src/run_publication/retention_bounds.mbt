///|
/// Two admitted retention envelopes may describe different effective data
/// policies while retaining exactly the same custody contract and time bounds.
/// This does not authorize changing either policy or extending a dependency.
pub fn result_retention_bounds_equal(
  left : PublicationContract,
  right : PublicationContract,
) -> Bool {
  if left.name != "result_retention_policy" ||
    right.name != "result_retention_policy" {
    return false
  }
  for
    field in [
      "retention_contract_cid", "available_until", "delete_by", "extension_ceiling_at",
      "metadata_retention_policy_cid", "metadata_delete_by", "clock_contract_cid",
    ] {
    if contract_string(left, field) != contract_string(right, field) {
      return false
    }
  }
  true
}

///|
/// Bind a contributing Source's already-resolved policy to the SAME retention
/// custody/timestamps. This is envelope DATA, not a new policy/extension grant.
/// The Host must supply the policy selected by that original Source, and must
/// separately enforce the publication's effective policy and physical custody.
pub fn issue_result_retention_for_data_policy(
  original : PublicationContract,
  effective_data_policy_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  if original.name != "result_retention_policy" ||
    !valid_contract_cid(effective_data_policy_cid) {
    return Err(InvalidObject)
  }
  if contract_string(original, "effective_data_policy_cid") ==
    Some(effective_data_policy_cid) {
    return Ok(original)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(InvalidObject)
  }
  try {
    @encode.begin_object(writer)
    for
      field in [
        "available_until", "clock_contract_cid", "delete_by", "effective_data_policy_cid",
        "extension_ceiling_at", "metadata_delete_by", "metadata_retention_policy_cid",
        "retention_contract_cid", "version",
      ] {
      @encode.key(writer, field)
      @encode.string_value(
        writer,
        if field == "effective_data_policy_cid" {
          effective_data_policy_cid
        } else {
          contract_string(original, field).unwrap()
        },
      )
    }
    @encode.end_object(writer)
    seal_publication_contract(
      "result_retention_policy",
      @encode.finish(writer),
      max_bytes,
      max_nodes,
      max_depth,
    )
  } catch {
    _ => Err(InvalidObject)
  }
}
