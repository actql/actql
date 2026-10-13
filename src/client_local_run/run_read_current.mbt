///|
/// Current Run observation is independent of submission and publication.
/// The original preflight supplies the admitted principal/connection and scope;
/// the existing Account Owner evaluates the separate run/read tuple.
pub fn validate_local_preflight_run_read_current(
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[Unit, LocalPublicationIntentIssue] {
  match validate_local_publication_preflight_current(preflight, account) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let read_tuple : @authorization.AccessTuple = {
    ..preflight.intent.plan.tuple,
    resource: "run",
    operation: "read",
  }
  if @authorization.evaluate_account(account, read_tuple)
    is @authorization.Allow(_) {
    Ok(())
  } else {
    Err(AuthorizationMismatch)
  }
}
