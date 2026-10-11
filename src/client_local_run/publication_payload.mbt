///|
pub(all) enum LocalPublicationPayloadIssue {
  Preflight(LocalPublicationIntentIssue)
  Output(@host.PublicationOutputPayloadIssue)
}

///|
/// Project a physical payload intent from one original completed Result and
/// the publication attempt fixed before Compute. The existing payload Owner
/// owns its later transitions; this request grants no publisher authority or
/// Store acknowledgement, and it does not start a write or replace the Result.
pub fn prepare_local_preflight_payload_request(
  preflight : LocalPublicationPreflight,
  result : Int,
  original : LocalResultPublication,
  account : @authorization.AdmittedAccountConfiguration,
  store_authority_cid : String,
  material_generation_cid : String,
  max_payload_bytes : Int64,
) -> Result[@payload.PublicationPayloadRequest, LocalPublicationPayloadIssue] {
  match
    reuse_local_preflight_result_publication(
      preflight,
      result,
      original,
      original.output,
      account,
    ) {
    Err(issue) => return Err(Preflight(issue))
    Ok(_) => ()
  }
  let (_, attempt) = local_publication_preflight_contracts(preflight)
  original.output
  .prepare_payload_request(
    @publication.publication_contract_identity(attempt),
    store_authority_cid,
    material_generation_cid,
    max_payload_bytes,
  )
  .map_err(issue => Output(issue))
}
