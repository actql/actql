///|
/// Bind the trusted Host publisher port to the genuine pre-Compute preflight.
/// The Host fence must cover its original Store/journal/current configuration.
/// The independent authorize callback must judge the original policy/target
/// at every stage; current Run/Source access below is a separate prerequisite.
pub fn install_local_preflight_publisher_port(
  preflight : LocalPublicationPreflight,
  store_authority_cid : String,
  current_account : () -> @authorization.AdmittedAccountConfiguration,
  require_current_host : () -> Bool,
  authorize : (@publication.PublicationPublisherAuthorization) -> Bool,
) -> Result[
  @publication.PublicationPublisherPort,
  @publication.PublicationPublisherIssue,
] {
  let (request, attempt) = local_publication_preflight_contracts(preflight)
  @publication.install_publication_publisher_port(
    request,
    attempt,
    store_authority_cid,
    () => {
      require_current_host() &&
      validate_local_publication_preflight_current(preflight, current_account())
      is Ok(_)
    },
    authorize,
  )
}
