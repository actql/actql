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

///|
/// Produce an optional ranking against the same Owner-held snapshot. This
/// read-only result still requires ordinary policy admission/commit.
pub fn rank_native_operational_estimate(
  dispatch : @duckdb_standard_host.StrategyHostDispatch,
  sidecar : @strategy.OperationalEstimateSidecar,
  task : Int,
  policy_revision : String,
  clock : @clock.NativeTrustedClock,
) -> Result[@strategy.EmpiricalRanking, NativeStandardPolicyIssue] {
  let before = match clock.observe() {
    Ok(value) => value
    Err(issue) => return Err(Clock(issue))
  }
  match
    @duckdb_standard_host.validate_dispatch_policy_request(
      dispatch,
      sidecar.request,
      before,
    ) {
    Err(issue) => return Err(Dispatch(issue))
    Ok(_) => ()
  }
  guard @duckdb_standard_host.dispatch_policy_candidates(dispatch)
    is Some(candidates) else {
    return Err(InvalidConfiguration)
  }
  let result = match
    @strategy.rank_operational_candidates(
      candidates, sidecar, task, policy_revision, before,
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
      dispatch,
      sidecar.request,
      after,
    ) {
    Err(issue) => Err(Dispatch(issue))
    Ok(_) =>
      if after < sidecar.newest_ms ||
        after - sidecar.oldest_ms > sidecar.max_age_ms {
        Ok({
          ..result,
          selected_position: None,
          reason: "freshness-insufficient",
        })
      } else {
        Ok(result)
      }
  }
}

///|
/// Trusted local policy adapters use the same closed response and Owner commit
/// as a configured transport adapter. No failure creates an offline choice.
pub fn commit_native_local_policy_response(
  dispatch : @duckdb_standard_host.StrategyHostDispatch,
  request : @strategy.PolicyRequest,
  body : String,
  authenticated_policy_id : String,
  clock : @clock.NativeTrustedClock,
) -> Result[Unit, NativeStandardPolicyIssue] {
  let now = match clock.observe() {
    Ok(value) => value
    Err(issue) => return Err(Clock(issue))
  }
  @duckdb_standard_host.commit_dispatch_policy_response_json(
    dispatch, request, body, authenticated_policy_id, now,
  ).map_err(issue => Dispatch(issue))
}
