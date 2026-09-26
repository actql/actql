///|
#export_name("salesforcePrepareWriteCapability")
pub fn salesforce_prepare_write_capability(
  request : @catalog.SingleWriteRequest,
  runtime_bundle_cid : String,
  collection : Bool,
  max_bytes : Int,
) -> @catalog.WriteCapabilityEvidence raise SalesforceCatalogBridgeIssue {
  match
    @catalog.prepare_write_capability_evidence(
      request,
      runtime_bundle_cid,
      if collection {
        ContinueCollection
      } else {
        SerialRows
      },
      max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise WriteCapability(issue)
  }
}

///|
#export_name("salesforceWriteCapabilityIdentity")
pub fn salesforce_write_capability_identity(
  evidence : @catalog.WriteCapabilityEvidence,
) -> String {
  @catalog.write_capability_identity(evidence)
}

///|
#export_name("salesforceWriteCapabilityBody")
pub fn salesforce_write_capability_body(
  evidence : @catalog.WriteCapabilityEvidence,
) -> String {
  @catalog.write_capability_body(evidence)
}

///|
#export_name("salesforceWriteCapabilityRoute")
pub fn salesforce_write_capability_route(
  evidence : @catalog.WriteCapabilityEvidence,
) -> Int {
  match @catalog.write_capability_route(evidence) {
    SerialRows => 0
    ContinueCollection => 1
  }
}

///|
#export_name("salesforceCheckWriteCapabilityRequest")
pub fn salesforce_check_write_capability_request(
  evidence : @catalog.WriteCapabilityEvidence,
  request : @catalog.SingleWriteRequest,
  runtime_bundle_cid : String,
) -> Unit raise SalesforceCatalogBridgeIssue {
  match
    @catalog.check_write_capability_request(
      evidence, request, runtime_bundle_cid,
    ) {
    Ok(_) => ()
    Err(issue) => raise WriteCapability(issue)
  }
}

///|
#export_name("salesforceRecheckWriteCapability")
pub fn salesforce_recheck_write_capability(
  evidence : @catalog.WriteCapabilityEvidence,
  current : @catalog.CatalogObservation,
) -> Unit raise SalesforceCatalogBridgeIssue {
  match @catalog.recheck_write_capability(evidence, current) {
    Ok(_) => ()
    Err(issue) => raise WriteCapability(issue)
  }
}
