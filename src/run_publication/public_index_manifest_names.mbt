///|
/// Names from this exact admitted index/manifest pair. This validates the
/// original Run and invocation references before using the existing bounded
/// manifest projection. It grants no read, egress, retention or Store custody.
pub fn public_index_manifest_result_names_json(
  index : PublicationContract,
  manifest : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, DeliveryIssuanceIssue] {
  match validate_public_read_root(index, manifest) {
    Ok(_) =>
      manifest_result_names_json(manifest, max_wire_bytes, max_nodes, max_depth)
    Err(issue) => Err(issue)
  }
}
