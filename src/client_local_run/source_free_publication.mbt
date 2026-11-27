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
/// The flat Core issuer has already checked every original Model slot and
/// the selected compiled Run. Finish the same source-free Result handoff
/// with its independently admitted policy and current Account.
pub fn issue_local_source_free_model_invocation(
  host : LocalComputeHost,
  start : LocalComputeStart,
  binding : @infer.InvocationBinding,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[LocalRunInvocation, LocalResultPublicationIssue] {
  guard physical_equal(host, start.host) &&
    local_compute_model_run(host) is Some(_) &&
    @host.prepared_client_acquisition_count(host.plan.prepared) == 0 else {
    return Err(ForeignCompute)
  }
  if !local_publication_current(host, account) {
    return Err(AuthorizationMismatch)
  }
  guard @infer.original_issued_invocation_matches_run(
      binding, host.plan.compiled, host.plan.definition,
    ) &&
    @infer.invocation_binding_observation(binding) is Some(observation) &&
    @infer.invocation_binding_invocation(binding) is Some(invocation) &&
    @host.client_compiled_run_source_free_result_policy_body(host.plan.compiled)
      is Some(policy) else {
    return Err(MissingFacts)
  }
  Ok({
    host,
    origin: SourceFreeModel(start, binding),
    observation,
    invocation,
    data_policy_cid: @publication.captured_effect_dependency_body_cid(policy),
  })
}

///|
/// Finish the same bound Model issuer with its exact Whole Source evidence.
pub fn issue_local_whole_source_model_invocation(
  host : LocalComputeHost,
  start : LocalComputeStart,
  binding : @infer.InvocationBinding,
  source : @publication.RunEvidenceValue,
  logical : @publication.RunEvidenceValue,
  identity : @query.CapturedSourceRelationIdentity,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[LocalRunInvocation, LocalResultPublicationIssue] {
  guard physical_equal(host, start.host) &&
    host.publication is WholeSourceModel(_) else {
    return Err(ForeignCompute)
  }
  if !local_publication_current(host, account) {
    return Err(AuthorizationMismatch)
  }
  guard @infer.original_issued_whole_source_invocation_matches_run(
      binding, host.plan.compiled, host.plan.definition, source, logical,
    ) &&
    @infer.invocation_binding_observation(binding) is Some(observation) &&
    @infer.invocation_binding_invocation(binding) is Some(invocation) &&
    @host.client_compiled_run_infer_observation_policy(host.plan.compiled) is Some(policy) else {
    return Err(MissingFacts)
  }
  Ok({
    host,
    origin: WholeSourceModel(start, binding, source, logical, identity),
    observation,
    invocation,
    data_policy_cid: policy,
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
    WholeSourceModel(start, binding, source, logical, _) => {
      let host = invocation.host
      guard physical_equal(start.host, host) &&
        host.publication is WholeSourceModel(_) &&
        @host.client_compiled_run_infer_observation_policy(host.plan.compiled) ==
          Some(invocation.data_policy_cid) &&
        @infer.original_issued_whole_source_invocation_matches_run(
          binding, host.plan.compiled, host.plan.definition, source, logical,
        ) else {
        return Err(MissingFacts)
      }
    }
    SourceFree(start) | SourceFreeModel(start, _) => {
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
      if invocation.origin is SourceFreeModel(_, binding) &&
        !@infer.original_issued_invocation_matches_run(
          binding, invocation.host.plan.compiled, invocation.host.plan.definition,
        ) {
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
    WholeSourceModel(_, _, _, _, identity) =>
      [@query.captured_source_relation_logical_cid(identity)]
    SourceFree(_) | SourceFreeModel(_, _) => []
  }
}

///|
fn local_run_invocation_source_evidence(
  value : LocalRunInvocation,
) -> Array[@publication.RunEvidenceValue] {
  match value.origin {
    Captured(source) => [source.evidence]
    WholeSourceModel(_, _, source, _, _) => [source]
    SourceFree(_) | SourceFreeModel(_, _) => []
  }
}
