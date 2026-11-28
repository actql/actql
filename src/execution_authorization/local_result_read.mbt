///|
pub let local_original_result_read_entry_id : String = "local-result-original-read"

///|
pub let local_original_result_read_resource : String = "result"

///|
let local_result_file_bootstrap_profile : BootstrapProfile = local_standard_profile_identity()

///|
/// Evaluate the exact second tuple of the Local read decision. A caller must
/// separately prove the original Run, requested Result and installed purpose.
/// No broad selector can stand in for the fresh installer's single role.
pub fn local_result_read_authority_resource(
  account : AdmittedAccountConfiguration,
  named_tuple : AccessTuple,
  installed_original_result : Bool,
) -> String? {
  if named_tuple.operation != "read" ||
    !named_tuple.resource.has_prefix("result/") ||
    named_tuple.resource == "result/" {
    return None
  }
  let named = evaluate_account(account, named_tuple)
  if !installed_original_result {
    return if named is Allow(_) { Some(named_tuple.resource) } else { None }
  }
  guard named is (Allow(_) | Deny(NoMatch)) &&
    account.account_id == "local-cli" &&
    named_tuple.principal == "local-cli" else {
    return None
  }
  // File adoption may reserve a disjoint control connection when a Source
  // owns the preferred name. Require its standard profile and the exact
  // current Result role on that same connection.
  if named_tuple.connection != "local" &&
    account.bootstrap != Some(local_result_file_bootstrap_profile) {
    return None
  }
  let exact = account.entries.any(entry => {
    entry.entry_id == local_original_result_read_entry_id &&
    entry.outcome == Allow &&
    entry.exclusions.is_empty() &&
    entry.scope.dims[0] is Finite(["local-cli"]) &&
    entry.scope.dims[1] is Finite([connection]) &&
    connection == named_tuple.connection &&
    entry.scope.dims[2] is Finite([resource]) &&
    resource == local_original_result_read_resource &&
    entry.scope.dims[3] is Finite(["read"])
  })
  let scoped = { ..named_tuple, resource: local_original_result_read_resource, }
  if exact && evaluate_account(account, scoped) is Allow(_) {
    Some(scoped.resource)
  } else {
    None
  }
}
