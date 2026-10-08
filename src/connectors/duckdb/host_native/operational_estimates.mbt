///|
/// Optional local reference admission on the original pending dispatch Owner.
/// The configured caller authenticates the local producer and validates/pins
/// its profile before calling. This function does not select or execute a task.
pub fn admit_native_operational_estimate(
  dispatch : @duckdb_standard_host.StrategyHostDispatch,
  request : @strategy.PolicyRequest,
  body : String,
  authenticated_local_issuer : String,
  expected_profile_revision : String,
  clock : @clock.NativeTrustedClock,
) -> Result[@strategy.OperationalEstimateSidecar, NativeStandardPolicyIssue] {
  let before = match clock.observe() {
    Ok(value) => value
    Err(issue) => return Err(Clock(issue))
  }
  match
    @duckdb_standard_host.validate_dispatch_policy_request(
      dispatch, request, before,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Dispatch(issue))
  }
  guard @duckdb_standard_host.dispatch_policy_candidates(dispatch)
    is Some(candidates) else {
    return Err(InvalidConfiguration)
  }
  let sidecar = match
    @strategy.admit_operational_estimate_sidecar_json(
      body, request, candidates, authenticated_local_issuer, expected_profile_revision,
      before,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  let after = match clock.observe() {
    Ok(value) => value
    Err(issue) => return Err(Clock(issue))
  }
  match
    @duckdb_standard_host.validate_dispatch_policy_request(
      dispatch, request, after,
    ) {
    Ok(_) =>
      // Freshness is evaluated at receive completion too. A reference may
      // become unknown; the original profile and request stay unchanged.
      if after < sidecar.newest_ms ||
        after - sidecar.oldest_ms > sidecar.max_age_ms {
        Ok({
          ..sidecar,
          references: sidecar.references.map(reference => {
            ..reference,
            median_ms: None,
            minimum_ms: None,
            maximum_ms: None,
            unknown_reason: Some("freshness-insufficient"),
          }),
        })
      } else {
        Ok(sidecar)
      }
    Err(issue) => Err(Dispatch(issue))
  }
}
