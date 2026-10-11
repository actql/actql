///|
/// Keep the original nominal Run/invocation/retention while admitting observed
/// physical Store facts. Revalidate current Run and Source authority before
/// issuing a binding. A binding is neither durable commit nor a Run outcome.
pub fn issue_local_result_durable_binding(
  value : LocalResultPublication,
  account : @authorization.AdmittedAccountConfiguration,
  material_generation_cid : String,
  store_authority_cid : String,
  observed_byte_count : Int,
  physical_sha256 : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, LocalResultPublicationIssue] {
  match validate_local_result_publication_current(value, account) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  value.output
  .issue_durable_binding(
    value.host.plan.definition,
    value.invocation.invocation,
    value.retention,
    material_generation_cid,
    store_authority_cid,
    observed_byte_count,
    physical_sha256,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
  .map_err(issue => Output(issue))
}
