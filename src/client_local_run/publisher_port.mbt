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
  install_original_local_publisher_port(
    request, attempt, store_authority_cid, preflight.intent.plan.account_id,
    preflight.intent.plan.tuple, original_account, current_account,
    require_current_host,
    current => validate_local_publication_preflight_current(preflight, current) is Ok(_),
    authorize,
  )
}

///|
fn install_original_local_publisher_port(
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  store_authority_cid : String,
  original_account_id : String,
  original_tuple : @authorization.AccessTuple,
  original_account : @authorization.AdmittedAccountConfiguration,
  current_account : () -> @authorization.AdmittedAccountConfiguration,
  require_current_host : () -> Bool,
  original_current : (@authorization.AdmittedAccountConfiguration) -> Bool,
  authorize : (@publication.PublicationPublisherAuthorization) -> Bool,
) -> Result[@publication.PublicationPublisherPort, @publication.PublicationPublisherIssue] {
  let context = match
    @publication.project_publication_request_context(request) {
    Ok(context) => context
    Err(issue) => return Err(issue)
  }
  if context.publication_policy_cid != original_account.configuration_cid() ||
    original_account.account_id() != original_account_id {
    return Err(@publication.ReferenceMismatch)
  }
  if context.publication_target_cid != store_authority_cid {
    return Err(@publication.InvalidStore)
  }
  let publish_tuple : @authorization.AccessTuple = {
    ..original_tuple,
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
      original_current(current) &&
      @authorization.evaluate_account(current, publish_tuple)
      is @authorization.Allow(_)
    },
    authorize,
  )
}

///|
/// Use the same publisher port under an installed File preflight. The
/// trusted Host observes the correct Run journal inside Request/Commit.
pub fn[Store, E] install_local_captured_task_preflight_publisher_port(
  preflight : LocalCapturedTaskPublicationPreflight[Store, E],
  original_account : @authorization.AdmittedAccountConfiguration,
  current_account : () -> @authorization.AdmittedAccountConfiguration,
  require_current_host : () -> Bool,
  authorize : (@publication.PublicationPublisherAuthorization) -> Bool,
) -> Result[@publication.PublicationPublisherPort, @publication.PublicationPublisherIssue] {
  let binding = preflight.observed.step.publication.step
  let (request, attempt) = local_captured_task_publication_preflight_contracts(preflight)
  install_original_local_publisher_port(
    request, attempt, binding.store_authority_cid, binding.account_id, binding.tuple,
    original_account, current_account, require_current_host,
    current => current.configuration_cid() == original_account.configuration_cid(),
    authorize,
  )
}
