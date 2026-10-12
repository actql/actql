///|
/// The original compiled wrapper retains the Host's admitted policy body.
/// This projection is neither a publisher grant nor a durable admission.
pub fn local_run_compiled(plan : LocalRunPlan) -> @host.ClientCompiledRun {
  plan.compiled
}

///|
/// No fabricated Source/Model provenance: the existing Owner issues a formal
/// no-external-source observation bound to this compilation and genuine policy.
/// Current publisher, journal originals and Store ACK remain separate gates.
pub fn issue_source_free_local_run_invocation(
  plan : LocalRunPlan,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  let limits = local_run_material_limits()
  @host.issue_client_compiled_local_values_invocation(
    plan.compiled,
    plan.definition,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  )
}
