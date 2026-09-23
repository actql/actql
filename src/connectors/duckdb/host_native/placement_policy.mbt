///|
/// One pending product-Host decision. The caller owns the authenticated HTTPS
/// client and durable clock; the configured endpoint fixes the policy identity.
pub struct NativeStandardPolicyConsultation {
  dispatch : @duckdb_standard_host.StrategyHostDispatch
  client : @http.Client
  clock : @clock.NativeTrustedClock
  endpoint : String
  policy_id : String
  request : @strategy.PolicyRequest
  candidates : @strategy.PolicyCandidateSet
  authorize_disclosure : (@strategy.PolicyRequest, @strategy.PolicyCandidateSet) -> Bool
  max_envelope_bytes : Int
  mut committed : Bool
}

///|
pub(all) enum NativeStandardPolicyIssue {
  InvalidConfiguration
  DisclosureDenied
  EnvelopeTooLarge
  AlreadyCommitted
  InvalidResponse
  HttpStatus(Int)
  Dispatch(@duckdb_standard_host.DispatchIssue)
  Clock(@clock.NativeTrustedClockIssue)
  Transport(@http.NativeHttpIssue)
  Wire(@strategy.SearchIssue)
}

///|
/// Prepare the exact pending request before any task starts. On I/O failure the
/// caller must retain this owner and retry the same request or explicitly end
/// the Run; minting a new request is not an execution retry mechanism.
pub fn prepare_native_standard_policy_consultation(
  dispatch : @duckdb_standard_host.StrategyHostDispatch,
  client : @http.Client,
  clock : @clock.NativeTrustedClock,
  endpoint : String,
  policy_id : String,
  request_id : String,
  run_identity : String,
  authority : String,
  deadline_ms : Int64,
  max_envelope_bytes : Int,
  authorize_disclosure : (@strategy.PolicyRequest, @strategy.PolicyCandidateSet) -> Bool,
) -> Result[NativeStandardPolicyConsultation?, NativeStandardPolicyIssue] {
  if !endpoint.has_prefix("https://") ||
    endpoint.length() > 8192 ||
    endpoint.contains("\u{0}") ||
    policy_id.is_empty() ||
    policy_id.length() > 128 ||
    max_envelope_bytes < 1 ||
    max_envelope_bytes > 16777216 {
    return Err(InvalidConfiguration)
  }
  let now = match clock.observe() {
    Ok(value) => value
    Err(issue) => return Err(Clock(issue))
  }
  let needed = match
    @duckdb_standard_host.prepare_dispatch_policy_choice(dispatch) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  if !needed {
    return Ok(None)
  }
  let request = match
    @duckdb_standard_host.prepare_dispatch_policy_request(
      dispatch, request_id, run_identity, authority, deadline_ms, now,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  guard @duckdb_standard_host.dispatch_policy_candidates(dispatch)
    is Some(candidates) &&
    candidates.cid == request.candidate_set_cid else {
    return Err(InvalidConfiguration)
  }
  Ok(
    Some({
      dispatch,
      client,
      clock,
      endpoint,
      policy_id,
      request,
      candidates,
      authorize_disclosure,
      max_envelope_bytes,
      committed: false,
    }),
  )
}

///|
/// The response body supplies no authority: TLS verifies the configured
/// endpoint and `policy_id` is taken only from that trusted configuration.
/// Connection loss does not select the offline policy or dispatch a task.
pub fn consult_native_standard_policy(
  consultation : NativeStandardPolicyConsultation,
) -> Result[Unit, NativeStandardPolicyIssue] {
  if consultation.committed {
    return Err(AlreadyCommitted)
  }
  if !(consultation.authorize_disclosure)(
      consultation.request,
      consultation.candidates,
    ) {
    return Err(DisclosureDenied)
  }
  let request_json = match
    @strategy.placement_policy_request_json(consultation.request) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  let body = @utf8.encode(
    "{\"request\":" +
    request_json +
    ",\"candidates\":" +
    consultation.candidates.canonical_json +
    "}",
  )
  if body.length() > consultation.max_envelope_bytes {
    return Err(EnvelopeTooLarge)
  }
  let before = match consultation.clock.observe() {
    Ok(value) => value
    Err(issue) => return Err(Clock(issue))
  }
  if before > consultation.request.deadline_ms {
    return Err(InvalidResponse)
  }
  let response = match
    consultation.client.post_json(consultation.endpoint, body) {
    Ok(value) => value
    Err(issue) => return Err(Transport(issue))
  }
  if response.status != 200 {
    return Err(HttpStatus(response.status))
  }
  let response_body = @utf8.decode(response.body) catch {
    _ => return Err(InvalidResponse)
  }
  let after = match consultation.clock.observe() {
    Ok(value) => value
    Err(issue) => return Err(Clock(issue))
  }
  match
    @duckdb_standard_host.commit_dispatch_policy_response_json(
      consultation.dispatch,
      consultation.request,
      response_body,
      consultation.policy_id,
      after,
    ) {
    Ok(_) => {
      consultation.committed = true
      Ok(())
    }
    Err(issue) => Err(Dispatch(issue))
  }
}
