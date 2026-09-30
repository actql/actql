///|
#export_name("clientValuesHostDescribeCommittedResult")
pub fn client_values_host_describe_committed_result(
  index : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  result_name : String,
  bindings : Array[@publication.PublicationContract],
  definition : @publication.PublicationContract,
  schema_wire : String,
  format : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String? {
  match
    @publication.describe_committed_result(
      index, manifest, result_name, bindings, definition, schema_wire, format, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(wire) => Some(wire)
    Err(_) => None
  }
}

///|
#export_name("clientValuesHostResultMetadataRetentionState")
pub fn client_values_host_result_metadata_retention_state(
  retention : @publication.PublicationContract,
  observed_at : String,
) -> String? {
  match @publication.result_metadata_retention_state(retention, observed_at) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
#export_name("clientValuesHostIssueManifestReadGrant")
pub fn client_values_host_issue_manifest_read_grant(
  index : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  principal_id : String,
  purpose : String,
  data_ceiling_cid : String,
  max_bytes : Int,
  max_uses : Int,
  expires_at : String,
  authorization_context_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication.PublicationContract raise ClientValuesHostDeliveryIssue {
  match
    @publication.issue_manifest_read_grant(
      index, manifest, principal_id, purpose, data_ceiling_cid, max_bytes, max_uses,
      expires_at, authorization_context_cid, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => raise Rejected
  }
}

///|
#export_name("clientValuesHostManifestReadGrantValidAt")
pub fn client_values_host_manifest_read_grant_valid_at(
  grant : @publication.PublicationContract,
  at : String,
) -> Bool {
  @publication.manifest_read_grant_valid_at(grant, at)
}

///|
#export_name("clientValuesHostManifestReadGrantAllowsBytes")
pub fn client_values_host_manifest_read_grant_allows_bytes(
  grant : @publication.PublicationContract,
  bytes : Int,
) -> Bool {
  @publication.manifest_read_grant_allows_bytes(grant, bytes)
}
