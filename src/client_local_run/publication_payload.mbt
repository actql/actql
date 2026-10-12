///|
pub(all) enum LocalPublicationPayloadIssue {
  Preflight(LocalPublicationIntentIssue)
  Output(@host.PublicationOutputPayloadIssue)
}

///|
/// Re-open the original Result under its original preflight and current
/// Run/Source authorization. The request never substitutes for nominal Result
/// custody, and neither this child nor its cancellation changes publication.
pub fn prepare_local_preflight_payload_replay(
  preflight : LocalPublicationPreflight,
  result : Int,
  original : LocalResultPublication,
  request : @payload.PublicationPayloadRequest,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[@host.PublicationOutputReplay, LocalPublicationPayloadIssue] {
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
  if @payload.publication_payload_request_attempt(request) !=
    @publication.publication_contract_identity(attempt) {
    return Err(Output(@host.RequestMismatch))
  }
  original.output
  .replay_payload_request(request)
  .map_err(issue => Output(issue))
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

///|
/// Revalidate the original preflight/Result/current Run and Source account,
/// then bind the same filesystem Sealed payload through its content Owner.
/// Neither a durable record nor equal-looking physical facts replace nominal
/// Result custody or grant current publisher authority.
pub fn issue_local_preflight_sealed_result_binding(
  preflight : LocalPublicationPreflight,
  result : Int,
  original : LocalResultPublication,
  record : @payload.PublicationPayloadRecord,
  account : @authorization.AdmittedAccountConfiguration,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, LocalPublicationPayloadIssue] {
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
  let request = @payload.publication_payload_record_request(record)
  if @payload.publication_payload_request_attempt(request) !=
    @publication.publication_contract_identity(attempt) {
    return Err(Output(@host.RequestMismatch))
  }
  original.output
  .issue_sealed_durable_binding(
    original.host.plan.definition,
    original.invocation.invocation,
    original.retention,
    record,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
  .map_err(issue => Output(issue))
}
