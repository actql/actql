///|
/// Dispatch coordinates from the original checked computation, not a Host
/// reconstruction of the Compiled Plan. No fragment grants physical execution.
pub fn client_effect_compilation_task_keys(
  value : ClientEffectCompilation,
) -> Result[Array[String], ClientTaskFragmentIssue] {
  if value.compiled.standard_progress_keys is Some(keys) {
    return Ok(keys.copy())
  }
  let keys = []
  let prepared = value.compiled.owner
  for task in 0..<@strategy.graph_task_count(prepared.graph) {
    let fragment = match
      issue_prepared_client_task_fragment(
        prepared,
        task,
        client_standard_values_sequence_limits(),
        1000000,
        100000,
        100,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    keys.push(client_task_fragment_node_id(fragment))
  }
  Ok(keys)
}

///|
/// Result names and producer ordinals are selected by the same checked graph
/// used for dispatch. The private computation view never escapes as Pure.
pub fn prepare_client_effect_publication_inventory(
  value : ClientEffectCompilation,
) -> Result[
  @publication.CheckedPublicationInventory,
  @publication.PublicationInventoryIssue,
] {
  let names = client_effect_compilation_result_names(value)
  let tasks = []
  for index in 0..<names.length() {
    guard @strategy.graph_result_task(value.compiled.owner.graph, index)
      is Some(task) else {
      return Err(@publication.PublicationInventoryIssue::InvalidTask(index))
    }
    tasks.push(task)
  }
  @publication.prepare_checked_publication_inventory(
    prepared_client_effect_identity(value.owner).program_definition_cid,
    names,
    tasks,
  )
}

///|
/// The ordinary schema Owner reads the original checked Result occurrence.
/// This neither issues a payload nor permits publication before Effect settles.
pub fn issue_client_effect_result_schema(
  value : ClientEffectCompilation,
  result : Int,
  limits : @execution.RelationSchemaIdentityLimits,
) -> Result[@execution.RelationSchemaIdentity, ClientTaskOutputSchemaIssue] {
  issue_prepared_client_result_schema(value.compiled.owner, result, limits)
}

///|
/// Catalog evidence is not a Source read grant and cannot authorize an Effect.
pub fn client_effect_source_evidence_facts(
  value : ClientEffectCompilation,
  stage : Int,
  source_index : Int,
) -> @planning.QuerySourceEvidenceFacts? {
  prepared_client_source_evidence_facts(
    value.compiled.owner,
    stage,
    source_index,
  )
}
