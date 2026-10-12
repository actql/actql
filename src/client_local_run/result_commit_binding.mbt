///|
pub(all) enum LocalResultCommitBindingIssue {
  Payload(LocalPublicationPayloadIssue)
  BindingMismatch
}

///|
/// Match the original checked commit binding against the existing issuer's
/// exact Result/preflight/Sealed-record binding. This neither observes a new
/// physical generation nor supplies publisher authority or a durable ACK.
/// The Host must separately fence the same physical generation and reservation.
pub fn validate_local_preflight_commit_binding(
  preflight : LocalPublicationPreflight,
  result : Int,
  original : LocalResultPublication,
  record : @payload.PublicationPayloadRecord,
  account : @authorization.AdmittedAccountConfiguration,
  binding : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, LocalResultCommitBindingIssue] {
  let issued = match
    issue_local_preflight_sealed_result_binding(
      preflight, result, original, record, account, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(issued) => issued
    Err(issue) => return Err(Payload(issue))
  }
  if @publication.publication_contract_identity(binding) !=
    @publication.publication_contract_identity(issued) ||
    @publication.publication_contract_json(binding) !=
    @publication.publication_contract_json(issued) {
    return Err(BindingMismatch)
  }
  Ok(())
}
