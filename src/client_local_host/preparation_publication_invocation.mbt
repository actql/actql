///|
/// Issue and bind the invocation as one fixed transition. No caller-supplied
/// invocation or serialized CID can substitute for this exact per-Run result.
/// The semantic issuer is unchanged; selected BND remain restrictions only.
pub fn[I] issue_program_publication_invocation(
  owner : ClientClosedValuesPreparation[I],
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,max_wire_bytes : Int,max_nodes : Int,max_depth : Int,
) -> Result[(@publication.RunEvidenceValue,@publication.PublicationContract),ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) && physical_equal(original,owner) &&
    owner.prepared is Some(body) && physical_equal(body,prepared) &&
    owner.manager_original is Some(holder) &&
    @resources.preparation_body_borrow_value(holder) is Some(held) && physical_equal(held,prepared) &&
    @publication_host.client_compiled_run_matches(compiled,prepared) &&
    @publication_host.client_compiled_run_has_original_definition(compiled,definition) else {return Err(ForeignOriginal)}
  if owner.retiring || !owner.body_ready || owner.publication_invocation_started ||
    @resources.preparation_body_retirement_started(holder) {return Err(WrongPhase)}
  owner.publication_invocation_started=true
  match @publication_host.issue_client_compiled_values_invocation(compiled,definition,data_policy_cid,max_wire_bytes,max_nodes,max_depth) {
    Err(issue)=>Err(PublicationInvocation(issue))
    Ok((evidence,invocation))=>{
      owner.publication_definition=Some(definition)
      owner.publication_invocation=Some(invocation)
      Ok((evidence,invocation))
    }
  }
}
