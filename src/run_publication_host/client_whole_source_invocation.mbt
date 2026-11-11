///|
/// The same original full-input capture supplies the ordinary Source
/// observation. It is never cast to a Query requirement or emitted/readmitted.
pub fn issue_client_compiled_whole_source_invocation(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  capture : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  acquisition : @acquisition.SourceAcquisition,
  source : @publication.RunEvidenceValue,
  input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  issue_client_compiled_whole_sources_invocation(
    run,
    definition,
    [capture],
    [identity],
    [acquisition],
    [source],
    [input],
    authority_scope_cid,
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|

///|
/// The same original full-input capture supplies the ordinary Source
/// observation. It is never cast to a Query requirement or emitted/readmitted.
pub fn issue_client_compiled_whole_sources_invocation(
  run : ClientCompiledRun,
  definition : @publication.PublicationContract,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  acquisitions : Array[@acquisition.SourceAcquisition],
  sources : Array[@publication.RunEvidenceValue],
  inputs : Array[@publication.RunEvidenceValue],
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  guard run.compilation is Tasks(compilation) &&
    compilation.infers.is_empty() &&
    compilation.serialization is None &&
    bind_client_task_run(run.owner, compilation, run.admission, definition)
    is Ok(_) else {
    return Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
  let occurrences = match
    select_client_direct_acquisition_occurrences(run.owner, max_nodes) {
    Ok(value) => value
    Err(_) =>
      return Err(@publication.RunEvidenceReferenceMismatch("source_coverage"))
  }
  issue_client_direct_source_observation(
    run.owner,
    client_task_compilation_template(compilation),
    occurrences,
    captures,
    identities,
    acquisitions.map(acquisition => WholeSourceOriginal(acquisition)),
    sources,
    inputs,
    authority_scope_cid,
    data_policy_cid,
    capture_started_at,
    capture_completed_at,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}
