///|
pub(all) enum ClientLocalQueryIssue {
  Sequences
  MissingStage
  Requirement(@publication_host.ClientQueryRequirementIssue)
}

///|
/// The installed Local Host uses the same generated sequence for acquisition
/// checking and the later captured computation. This issues no provider grant.
pub fn prepare_local_query_requirement(
  prepared : @publication_host.PreparedClientProgram,
  stage : Int,
  source_index : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@planning.QueryRequirement, ClientLocalQueryIssue] {
  guard prepare_client_local_sequences(
      prepared,
      registry_body,
      values_body,
      fragment_body,
      ordered_body,
      task_count=Some(stage + 1),
    )
    is Some(sequences) else {
    return Err(Sequences)
  }
  guard stage >= 0 && stage < sequences.length() else {
    return Err(MissingStage)
  }
  let limits : @planning.QueryMaterialLimits = {
    max_work: 1000000,
    max_fields: 100,
    max_parameters: 100,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }
  @publication_host.prepare_client_query_requirement(
    prepared,
    sequences[stage],
    stage,
    source_index,
    { max_rows: 100, max_value_bytes: 10000, },
    limits,
  ).map_err(issue => Requirement(issue))
}
