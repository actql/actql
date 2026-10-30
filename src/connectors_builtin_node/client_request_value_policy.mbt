///|
fn client_request_value_policy_limits() -> @program_check.CompileLimits {
  {
    ..@publication_host.client_standard_program_preparation_limits().checking.compilation,
    work: 1000000,
    artifacts: { bytes: 1000000, nodes: 100000, depth: 100, },
  }
}

///|
fn client_request_value_policy_checks(
  graph : @strategy.CheckedDAG,
) -> Array[@program_check.SourceExecution] {
  let program = @strategy.graph_program(graph)
  let checks = []
  for index in 0..<@program_check.source_execution_count(program) {
    let check = @program_check.source_execution_at(program, index).unwrap()
    if @program_check.source_execution_kind(check)
      is @program_check.RequestEgress &&
      @program_check.source_egress_field_count(check) > 0 {
      checks.push(check)
    }
  }
  checks
}

///|
// Internal descriptors for a trusted installed Host; never caller attestations.
#export_name("clientProgramRequestValuePolicySubjects")
pub fn client_program_request_value_policy_subjects(
  value : @publication_host.PreparedClientProgram,
) -> Array[String] raise @program_check.UnitBuildFailure {
  let limits = client_request_value_policy_limits()
  @program_check.request_value_policy_subject_wires(
    client_request_value_policy_checks(
      @publication_host.prepared_client_graph(value),
    ),
    limits.work,
    limits.artifacts.bytes,
    limits.artifacts.nodes,
    limits.artifacts.depth,
  )
}

///|
// The Host has verified the descriptor before selecting its admitted policy.
#export_name("clientProgramBindHostVerifiedRequestValuePolicy")
pub fn client_program_bind_host_verified_request_value_policy(
  value : @publication_host.PreparedClientProgram,
  index : Int,
  policy_cid : String,
) -> @program_check.HostRequestValuePolicyEvidence? {
  guard client_request_value_policy_checks(
      @publication_host.prepared_client_graph(value),
    ).get(index)
    is Some(check) else {
    return None
  }
  let limits = client_request_value_policy_limits()
  Some(
    @program_check.bind_host_verified_request_value_policy_cid(
      check,
      policy_cid,
      limits.work,
      limits.artifacts.bytes,
      limits.artifacts.nodes,
      limits.artifacts.depth,
    ),
  ) catch {
    _ => None
  }
}

///|
// Effectful computation retains the same checked Program and Source owners.
#export_name("clientProgramEffectRequestValuePolicySubjects")
pub fn client_program_effect_request_value_policy_subjects(
  value : @publication_host.PreparedClientEffectComputation,
) -> Array[String] raise @program_check.UnitBuildFailure {
  let limits = client_request_value_policy_limits()
  @program_check.request_value_policy_subject_wires(
    client_request_value_policy_checks(
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(value),
      ),
    ),
    limits.work,
    limits.artifacts.bytes,
    limits.artifacts.nodes,
    limits.artifacts.depth,
  )
}

///|
#export_name("clientProgramEffectBindHostVerifiedRequestValuePolicy")
pub fn client_program_effect_bind_host_verified_request_value_policy(
  value : @publication_host.PreparedClientEffectComputation,
  index : Int,
  policy_cid : String,
) -> @program_check.HostRequestValuePolicyEvidence? {
  guard client_request_value_policy_checks(
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(value),
      ),
    ).get(index)
    is Some(check) else {
    return None
  }
  let limits = client_request_value_policy_limits()
  Some(
    @program_check.bind_host_verified_request_value_policy_cid(
      check,
      policy_cid,
      limits.work,
      limits.artifacts.bytes,
      limits.artifacts.nodes,
      limits.artifacts.depth,
    ),
  ) catch {
    _ => None
  }
}

///|
#export_name("clientProgramCheckEnvironmentWithRequestValuePolicies")
pub fn client_program_check_environment_with_request_value_policies(
  value : @program_check.CheckEnvironment,
  evidence : Array[@program_check.HostRequestValuePolicyEvidence],
) -> @program_check.CheckEnvironment {
  @program_check.checking_environment_with_request_value_policies(
    value, evidence,
  )
}
