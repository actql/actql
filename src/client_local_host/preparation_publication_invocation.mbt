///|
/// Issue and bind the invocation as one fixed transition. No caller-supplied
/// invocation or serialized CID can substitute for this exact per-Run result.
/// The semantic issuer is unchanged; selected BND remain restrictions only.
pub fn issue_program_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  match
    begin_program_publication_invocation(owner, prepared, compiled, definition) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    @publication_host.issue_client_compiled_source_free_invocation(
      compiled, definition, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => Err(PublicationInvocation(issue))
    Ok((evidence, invocation)) => {
      owner.publication_definition = Some(definition)
      owner.publication_invocation = Some(invocation)
      Ok((evidence, invocation))
    }
  }
}

///|
fn begin_program_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  match managed_run_publication_body(owner, prepared) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !@publication_host.client_compiled_run_matches(compiled, prepared) ||
    !@publication_host.client_compiled_run_has_original_definition(
      compiled, definition,
    ) {
    return Err(ForeignOriginal)
  }
  if owner.publication_invocation_started {
    return Err(WrongPhase)
  }
  owner.publication_invocation_started = true
  Ok(())
}

///|
/// Adopt the capture issuer's completed Model pair on the already captured
/// managed Run. Ordinary Values and captured Source use their own issuers.
pub fn bind_program_model_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  captured : @strategy.CapturedDAG,
  observation : @publication.RunEvidenceValue,
  invocation : @publication.PublicationContract,
  inputs : Array[String],
  policy_cid : String,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  guard owner.source_free_captured is Some(original) &&
    physical_equal(original, captured) &&
    owner.captured_preparation is None &&
    installed_managed_run_compilation_original(owner, prepared)
    is Some(@publication_host.Tasks(compilation)) &&
    @publication_host.client_compiled_run_matches_tasks(
      compiled, prepared, compilation,
    ) &&
    @publication_host.prepared_client_acquisition_count(prepared) == 0 &&
    compilation.serialization is None &&
    !compilation.infers.is_empty() &&
    inputs.length() == compilation.infers.length() &&
    @publication_host.client_compiled_run_infer_observation_policy(compiled) ==
    Some(policy_cid) &&
    @publication.source_free_model_invocation_matches(
      @publication_host.client_compiled_run_template(compiled),
      observation,
      invocation,
      inputs,
      policy_cid,
    ) else {
    return Err(ForeignOriginal)
  }
  match
    begin_program_publication_invocation(owner, prepared, compiled, definition) {
    Err(issue) => Err(issue)
    Ok(_) => {
      owner.publication_definition = Some(definition)
      owner.publication_invocation = Some(invocation)
      Ok(())
    }
  }
}

///|
/// Retire the same semantic aliases after the Native publication child is
/// done. The original Model still owns the issuer and its independent cleanup.
pub fn retire_program_model_publication_invocation(
  owner : ClientInstalledManagedRun,
  invocation : @publication.PublicationContract,
) -> Bool {
  guard owner.publication_invocation is Some(original) &&
    physical_equal(original, invocation) else {
    return false
  }
  clear_managed_run_publication(owner)
  true
}

///|
/// Bind the original captured inventory to the same adopted Run exactly once.
/// Immutable evidence DATA cannot replace the checked capture/Plan lineage.
pub fn issue_program_captured_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
  keyed : @publication_host.ClientKeyedLookupObservation?,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  guard owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, owner.request) else {
    return Err(ForeignOriginal)
  }
  match
    begin_program_publication_invocation(owner, prepared, compiled, definition) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    @publication_host.issue_client_compiled_captured_invocation(
      compiled, definition, captures, identities, requirements, sources, inputs,
      keyed, authority_scope_cid, data_policy_cid, capture_started_at, capture_completed_at,
      max_wire_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => Err(PublicationInvocation(issue))
    Ok((evidence, invocation)) => {
      owner.publication_definition = Some(definition)
      owner.publication_invocation = Some(invocation)
      Ok((evidence, invocation))
    }
  }
}
