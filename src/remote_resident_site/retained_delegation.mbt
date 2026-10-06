///|
/// Explicit local movement delegation for the configured Coordinator. Dispatch
/// authority and each Transfer grant/capability are separate roles. Absence of
/// this configuration grants no internal handoff, even for the same Site.
pub(all) struct ResidentRetainedInputDelegation {
  dispatch : ResidentSiteDelegation
  source_grant_cid : String
  destination_grant_cid : String
  route_capability_cid : String
}

///|
/// Check local delegated movement scope, not remote grant issuance, Run
/// authorization or cancellation completion. Those remain their own Owners.
pub fn check_resident_retained_input_delegation(
  delegation : ResidentRetainedInputDelegation,
  producer : @remote.DispatchRequest,
  request : @transfer.RemoteTransferRequest,
  site_generation : Int,
) -> Result[Unit, ResidentDispatchRefusal] {
  match
    check_resident_dispatch_delegation(
      delegation.dispatch,
      producer,
      site_generation,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let scope = @transfer.request_projection(request)
  if @transfer.request_journal_key(request)[0] !=
    delegation.dispatch.coordinator_authority {
    return Err(ForeignCoordinator)
  }
  if @transfer.request_route(request) != @transfer.DirectStream ||
    scope[2] != delegation.dispatch.site_key ||
    scope[4] != delegation.dispatch.site_key {
    return Err(ForeignSite)
  }
  if scope[3] != site_generation.to_string() ||
    scope[5] != site_generation.to_string() {
    return Err(StaleGeneration)
  }
  if scope[10] != delegation.source_grant_cid ||
    scope[11] != delegation.destination_grant_cid ||
    scope[12] != delegation.route_capability_cid {
    return Err(ForeignGrant)
  }
  Ok(())
}
