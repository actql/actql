///|
/// Original compiler metadata retained with first admission. This projection is
/// not a permission, execution observation or a restored physical compilation.
struct ClientRunObservationOriginals {
  prepared : @publication.RunEvidenceValue
  authorization : @publication.RunEvidenceValue
}

///|
pub(all) enum ClientRunObservationOriginalsIssue {
  Compilation(ClientCompiledRunIssue)
  Evidence(@publication.RunEvidenceValueIssue)
  Binding(@publication.RunControlReadIssue)
}

///|
/// Capture exactly the existing compiled Owner's originals, without compiling
/// again. The Native Host saves these with its original acceptance transaction.
pub fn capture_client_run_observation_originals(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[ClientRunObservationOriginals, ClientRunObservationOriginalsIssue] {
  match check_client_compiled_run_definition(compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Compilation(issue))
  }
  let prepared = compiled.prepared
  let authorization = compiled.authorization
  match
    @publication.validate_original_interactive_run_evidence(
      definition, prepared, authorization,
    ) {
    Ok(_) => Ok({ prepared, authorization, })
    Err(issue) => Err(Binding(issue))
  }
}

///|
/// Read the exact saved metadata after the Host authenticates its same original
/// request/Run row. A copied Allow remains metadata, never current authority.
/// Missing originals must remain unavailable; callers cannot recapture them.
pub fn restore_client_run_observation_originals(
  definition : @publication.PublicationContract,
  prepared_wire : String,
  authorization_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientRunObservationOriginals, ClientRunObservationOriginalsIssue] {
  let prepared = match
    @publication.admit_run_evidence_value(
      "prepared_invocation", prepared_wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let authorization = match
    @publication.admit_run_evidence_value(
      "run_authorization", authorization_wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  match
    @publication.validate_original_interactive_run_evidence(
      definition, prepared, authorization,
    ) {
    Ok(_) => Ok({ prepared, authorization, })
    Err(issue) => Err(Binding(issue))
  }
}

///|
/// Borrow exact original values for the existing read-only Run projection.
pub fn ClientRunObservationOriginals::prepared(
  self : ClientRunObservationOriginals,
) -> @publication.RunEvidenceValue {
  self.prepared
}

///|
pub fn ClientRunObservationOriginals::authorization(
  self : ClientRunObservationOriginals,
) -> @publication.RunEvidenceValue {
  self.authorization
}
