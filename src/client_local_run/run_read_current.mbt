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

///|
/// A named Result needs its own current Account read decision as well as Run
/// observation. The original checked inventory chooses the resource; a saved
/// publisher, grant, read selection or Run-read Allow cannot replace it.
pub fn validate_local_preflight_result_read_current(
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  result_name : String,
) -> Result[Unit, LocalPublicationIntentIssue] {
  match validate_local_preflight_run_read_current(preflight, account) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let inventory = preflight.intent.inventory
  let mut found = false
  for index in 0..<@publication.checked_publication_inventory_count(inventory) {
    if @publication.checked_publication_inventory_name(inventory, index) == Ok(result_name) {
      found = true
      break
    }
  }
  if !found {
    return Err(MissingResult)
  }
  let read_tuple : @authorization.AccessTuple = {
    ..preflight.intent.plan.tuple,
    resource: "result/" + result_name,
    operation: "read",
  }
  if @authorization.evaluate_account(account, read_tuple)
    is @authorization.Allow(_) {
    Ok(())
  } else {
    Err(AuthorizationMismatch)
  }
}
