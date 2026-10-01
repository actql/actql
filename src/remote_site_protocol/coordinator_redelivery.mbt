///|
/// Validate exact immutable delivery bytes using the existing poll owner.
/// Materials are bounded opaque Run input here; the Run issuer and Site Run
/// admitter own their meaning. This grants neither execution nor new authority.
pub fn coordinator_delivery_envelope_json(
  request : DispatchRequest,
  body : String,
) -> Result[String, DispatchIssue] {
  let delivery = match admit_remote_poll_dispatch_json(body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if delivery.request.dispatch_request_cid != request.dispatch_request_cid {
    return Err(DispatchIdentityMismatch)
  }
  let canonical = match delivery.materials {
    Some(materials) =>
      remote_poll_dispatch_materials_json(request, delivery.binding, materials)
    None => remote_poll_dispatch_json(request, delivery.binding)
  }
  match canonical {
    Ok(value) if value == body => Ok(body)
    _ => Err(InvalidDispatch)
  }
}

///|
/// The caller supplies CURRENT Host-owned authorization/lifetime and binding
/// facts, not fields copied out of a received query. A not-seen reply may only
/// recover an unobserved intent: it cannot erase accepted history. This pure
/// decision changes no revision, receipt, claim or execution permission.
pub fn coordinator_redelivery_eligible(
  record : CoordinatorDispatchIntentRecord,
  request : DispatchRequest,
  not_seen_body : String,
  expected_authority : String,
  expected_site : String,
  expected_generation : Int,
  authorization_current : Bool,
  cancellation_requested : Bool,
) -> Result[Bool, DispatchIssue] {
  let current = match
    coordinator_delivery_context_current(
      request, expected_authority, expected_site, expected_generation, authorization_current,
      cancellation_requested,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !coordinator_dispatch_intent_matches_request(record, request) {
    return Err(DispatchIdentityMismatch)
  }
  if !current {
    return Ok(false)
  }
  if !not_seen_body.is_empty() {
    match admit_remote_poll_not_seen_json(not_seen_body, request) {
      Err(issue) => return Err(issue)
      Ok(_) => if record.site_revision >= 0 { return Ok(false) }
    }
  } else if record.site_revision < 0 {
    // Timeout, missing response and transport failure are not not-seen.
    return Ok(false)
  }
  Ok(coordinator_exact_retransmission_eligible(record, request))
}

///|
/// Trusted Host context checked on initial delivery as well as redelivery.
pub fn coordinator_delivery_context_current(
  request : DispatchRequest,
  expected_authority : String,
  expected_site : String,
  expected_generation : Int,
  authorization_current : Bool,
  cancellation_requested : Bool,
) -> Result[Bool, DispatchIssue] {
  if request.coordinator_authority != expected_authority {
    return Err(ForeignCoordinator)
  }
  if request.site_key != expected_site {
    return Err(ForeignSite)
  }
  if request.site_generation != expected_generation {
    return Err(StaleSiteGeneration)
  }
  Ok(authorization_current && !cancellation_requested)
}
