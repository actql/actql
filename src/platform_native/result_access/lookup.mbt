///|
/// Current lookup authorization is distinct from read admission and the
/// original grant. No read/receipt hook is substituted when it is unavailable.
pub fn lookup_native_result_delivery_attempt(
  service : NativeResultAccessService,
  request : @publication.DeliveryAttemptLookupScope,
) -> Result[@store.NativeResultDeliveryLookup?, NativeResultAccessIssue] {
  if request.namespace_id.is_empty() ||
    !valid_cid(request.authority_scope_cid) ||
    !valid_cid(request.run_definition_cid) ||
    request.principal_id.is_empty() ||
    request.purpose.is_empty() ||
    request.result_name.is_empty() ||
    request.attempt_id.is_empty() ||
    request.attempt_id.length() > 256 {
    return Err(InvalidRequest)
  }
  guard service.authority.authorize_lookup is Some(authorize) else {
    return Err(LookupUnavailable)
  }
  if !authorize(request) {
    return Err(AccessDenied)
  }
  let observed = service.store.lookup_result_delivery(request)
  // Do not disclose saved facts or distinguish absence/errors after a policy
  // change while Store access was in progress. No grant/byte/Run state changes.
  if !authorize(request) {
    return Err(AccessDenied)
  }
  store_result(observed)
}
