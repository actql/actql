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
