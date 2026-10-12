///|
/// Bind the trusted Host publisher port to the genuine pre-Compute preflight.
/// The Host fence must cover its original Store/journal/current configuration.
/// The trusted Host supplies the retained original Account body, not a policy
/// reconstructed from current configuration. Its CID and the original Store
/// are bound by the request. Publish is independent of Run/Source access.
pub fn install_local_preflight_publisher_port(
  preflight : LocalPublicationPreflight,
  store_authority_cid : String,
  original_account : @authorization.AdmittedAccountConfiguration,
  current_account : () -> @authorization.AdmittedAccountConfiguration,
  require_current_host : () -> Bool,
  authorize : (@publication.PublicationPublisherAuthorization) -> Bool,
) -> Result[
  @publication.PublicationPublisherPort,
  @publication.PublicationPublisherIssue,
] {
  let (request, attempt) = local_publication_preflight_contracts(preflight)
  let context = match
    @publication.project_publication_request_context(request) {
    Ok(context) => context
    Err(issue) => return Err(issue)
  }
  if context.publication_policy_cid != original_account.configuration_cid() ||
    original_account.account_id() != preflight.intent.plan.account_id {
    return Err(@publication.ReferenceMismatch)
  }
  if context.publication_target_cid != store_authority_cid {
    return Err(@publication.InvalidStore)
  }
  let publish_tuple : @authorization.AccessTuple = {
    ..preflight.intent.plan.tuple,
    resource: "run",
    operation: "publish",
  }
  if !(@authorization.evaluate_account(original_account, publish_tuple)
    is @authorization.Allow(_)) {
    return Err(@publication.AccessDenied)
  }
  @publication.install_publication_publisher_port(
    request,
    attempt,
    store_authority_cid,
    () => {
      if !require_current_host() {
        return false
      }
      let current = current_account()
      validate_local_publication_preflight_current(preflight, current) is Ok(_) &&
      @authorization.evaluate_account(current, publish_tuple)
      is @authorization.Allow(_)
    },
    authorize,
  )
}
