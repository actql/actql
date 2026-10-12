///|
/// Issue the existing formal no-external-source invocation from the original
/// Plan/Policy and accepted start. This is not a publisher or Store grant.
pub fn issue_local_source_free_invocation(
  host : LocalComputeHost,
  start : LocalComputeStart,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[LocalRunInvocation, LocalResultPublicationIssue] {
  if !physical_equal(host, start.host) {
    return Err(ForeignCompute)
  }
  if !local_publication_current(host, account) {
    return Err(AuthorizationMismatch)
  }
  let (observation, invocation) = match
    issue_source_free_local_run_invocation(host.plan) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  guard @host.client_compiled_run_source_free_result_policy_body(
      host.plan.compiled,
    )
    is Some(policy) else {
    return Err(MissingFacts)
  }
  Ok({
    host,
    origin: SourceFree(start),
    observation,
    invocation,
    data_policy_cid: @publication.captured_effect_dependency_body_cid(policy),
  })
}

///|
fn validate_local_run_invocation_current(
  invocation : LocalRunInvocation,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[Unit, LocalResultPublicationIssue] {
  if !local_publication_current(invocation.host, account) {
    return Err(AuthorizationMismatch)
  }
  match invocation.origin {
    Captured(source) => {
      if !physical_equal(source.host, invocation.host) {
        return Err(ForeignCompute)
      }
      match authorize_local_native_source(source.configuration, account) {
        Err(issue) => return Err(Source(Authorization(issue)))
        Ok(_) => ()
      }
      if !@acquisition_host.native_host_source_capture_identity_matches(
          source.capture,
          source.identity,
        ) {
        return Err(Source(Source(@query.Unavailable)))
      }
    }
    SourceFree(start) => {
      if !physical_equal(start.host, invocation.host) ||
        @host.prepared_client_acquisition_count(invocation.host.plan.prepared) !=
        0 {
        return Err(ForeignCompute)
      }
      guard @host.client_compiled_run_source_free_result_policy_body(
          invocation.host.plan.compiled,
        )
        is Some(policy) &&
        @publication.captured_effect_dependency_body_cid(policy) ==
        invocation.data_policy_cid else {
        return Err(MissingFacts)
      }
    }
  }
  Ok(())
}

///|
fn local_run_invocation_source_cids(
  value : LocalRunInvocation,
) -> Array[String] {
  match value.origin {
    Captured(source) =>
      [@query.captured_source_relation_logical_cid(source.identity)]
    SourceFree(_) => []
  }
}

///|
fn local_run_invocation_source_evidence(
  value : LocalRunInvocation,
) -> Array[@publication.RunEvidenceValue] {
  match value.origin {
    Captured(source) => [source.evidence]
    SourceFree(_) => []
  }
}
