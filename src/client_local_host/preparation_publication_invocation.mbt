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
  match
    @publication_host.issue_client_compiled_values_invocation(
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
